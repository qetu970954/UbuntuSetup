"""Non-destructive setup tests: temporary homes, mocked commands, no sudo/network."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ubuntu-setup-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home with spaces"
        self.home.mkdir()
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("GIT_CONFIG", "XDG_"))
            and key not in ("ZSH", "ZSH_CUSTOM", "DBUS_SESSION_BUS_ADDRESS", "DISPLAY", "WAYLAND_DISPLAY")
        }
        self.env.update(HOME=str(self.home), GIT_CONFIG_NOSYSTEM="1", LC_ALL="C")

    def shell(self, body, *, success=True):
        prefix = (
            "set -euo pipefail\n"
            f"source {shlex.quote(str(ROOT / 'setup.sh'))}\n"
            'CONFIG_HOME="$HOME/.config"\n'
            'DATA_HOME="$HOME/.local/share"\n'
            'STATE_HOME="$HOME/.local/state"\n'
        )
        result = subprocess.run(
            ["bash", "-c", prefix + body], env=self.env,
            text=True, capture_output=True, cwd=self.base,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def cli(self, *args):
        return subprocess.run(
            ["bash", str(ROOT / "setup.sh"), *args], env=self.env,
            text=True, capture_output=True, cwd=self.base,
        )

    def zsh(self, body):
        # Permit validation with a temporarily extracted (not installed) Zsh.
        module_dir = self.env.get("ZSH_TEST_MODULE_PATH")
        prefix = f"module_path=({shlex.quote(module_dir)}); " if module_dir else ""
        return subprocess.run(
            ["zsh", "-dfi", "-c", prefix + body], env=self.env,
            capture_output=True, text=True, cwd=self.base,
        )

    def block_external_commands(self):
        directory = self.base / "guard-bin"
        directory.mkdir()
        for name in ("sudo", "curl", "git", "gsettings", "systemctl", "chsh", "apt-get", "ibus"):
            executable = directory / name
            executable.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$HOME/UNEXPECTED_COMMAND"\nexit 99\n')
            executable.chmod(0o755)
        self.env["PATH"] = str(directory) + os.pathsep + self.env["PATH"]

    def test_bash_syntax(self):
        for path in [ROOT / "setup.sh", *sorted((ROOT / "lib").glob("*.sh"))]:
            result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_help_and_unknown_option_do_not_execute_commands(self):
        self.block_external_commands()
        help_result = self.cli("--help")
        self.assertEqual(help_result.returncode, 0, help_result.stderr)
        self.assertIn("Ubuntu 26.04", help_result.stdout)
        unknown = self.cli("--not-an-option")
        self.assertNotEqual(unknown.returncode, 0)
        self.assertIn("Unknown option", unknown.stderr)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_default_dry_run_is_read_only_and_excludes_optional_packages(self):
        self.block_external_commands()
        result = self.cli("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        install = next(line for line in result.stdout.splitlines() if "apt-get install" in line)
        for package in ("git-delta", "fzf", "micro", "python3-venv", "wl-clipboard", "ibus-chewing", "python3-gi"):
            self.assertIn(package, install)
        for package in ("libreoffice", "peek", "gnome-tweaks", "openssh-server"):
            self.assertNotIn(package, install)
        for command in ("gsettings set", "systemctl", "chsh", "autoremove"):
            self.assertNotIn(command, result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_all_options_dry_run_is_read_only_even_without_a_desktop_session(self):
        self.block_external_commands()
        existing = self.home / ".zshrc"
        existing.write_text("keep me\n")
        before = sorted(self.home.rglob("*"))
        result = self.cli(
            "--dry-run", "--replace-dotfiles", "--desktop", "--gnome-tweaks",
            "--chewing", "--enable-ssh", "--change-shell",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for text in ("gnome-tweaks", "ibus-chewing", "openssh-server", "ssh.socket", "chsh", "org.gnome.Ptyxis"):
            self.assertIn(text, result.stdout)
        self.assertIn("org.gnome.shell.extensions.dash-to-dock dock-position", result.stdout)
        self.assertIn("BOTTOM", result.stdout)
        self.assertIn("Would refresh the IBus registry", result.stdout)
        self.assertIn("Fluent-Light", result.stdout)
        for obsolete in ("org.gnome.Terminal", "org.gnome.gedit", "enabled-extensions"):
            self.assertNotIn(obsolete, result.stdout)
        self.assertEqual(before, sorted(self.home.rglob("*")))
        self.assertEqual(existing.read_text(), "keep me\n")

    def test_skip_chewing_avoids_package_and_input_changes(self):
        self.block_external_commands()
        result = self.cli("--dry-run", "--skip-chewing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("ibus-chewing", result.stdout)
        self.assertNotIn("Would append (ibus, chewing)", result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_chewing_variant_preserves_multiple_sources_and_is_idempotent(self):
        tool = ROOT / "lib/add_chewing.py"
        sources = "[('xkb', 'us'), ('xkb', 'de'), ('ibus', 'other')]"
        first = subprocess.run(["/usr/bin/python3", str(tool), sources], capture_output=True, text=True, check=True)
        self.assertEqual(first.stdout.strip(), "[('xkb', 'us'), ('xkb', 'de'), ('ibus', 'other'), ('ibus', 'chewing')]")
        second = subprocess.run(["/usr/bin/python3", str(tool), first.stdout.strip()], capture_output=True, text=True, check=True)
        self.assertEqual(second.stdout, first.stdout)
        invalid = subprocess.run(["/usr/bin/python3", str(tool), "not a variant"], capture_output=True, text=True)
        self.assertNotEqual(invalid.returncode, 0)

    def test_chewing_refreshes_stale_ibus_then_appends_and_preserves_sources(self):
        (self.home / "sources").write_text("[('xkb', 'us'), ('xkb', 'de')]\n")
        commands = r'''
STATE_HOME="$HOME/state"
gsettings() {
  case "$1" in
    list-schemas) printf 'org.gnome.desktop.input-sources\n' ;;
    list-keys) printf 'sources\n' ;;
    writable) printf 'true\n' ;;
    get) command cat "$HOME/sources" ;;
    set) printf '%s\n' "$4" > "$HOME/sources" ;;
    *) return 2 ;;
  esac
}
ibus() {
  case "$1" in
    list-engine) [[ ! -f $HOME/restarted ]] || printf '  chewing - Chewing\n' ;;
    write-cache) printf 'write-cache\n' >> "$HOME/ibus-calls" ;;
  esac
}
systemctl() { printf '%s\n' "$*" >> "$HOME/ibus-calls"; touch "$HOME/restarted"; }
configure_chewing
configure_chewing
'''
        self.shell(commands)
        self.assertEqual((self.home / "sources").read_text().strip(),
                         "[('xkb', 'us'), ('xkb', 'de'), ('ibus', 'chewing')]")
        self.assertEqual((self.home / "ibus-calls").read_text().splitlines(), [
            "write-cache", "--user restart org.freedesktop.IBus.session.GNOME.service",
        ])
        backups = list((self.home / "state/ubuntu-setup/backups").glob("*/gsettings.tsv"))
        self.assertEqual(len(backups), 1)
        self.assertIn("[('xkb', 'us'), ('xkb', 'de')]", backups[0].read_text())

    def test_default_install_and_rerun_with_mocked_packages_and_downloads(self):
        commands = r'''
check_environment() {
  CONFIG_HOME="$HOME/.config"
  DATA_HOME="$HOME/.local/share"
  STATE_HOME="$HOME/.local/state"
  ZSH_DIR="$HOME/.oh-my-zsh"
  CUSTOM_DIR="$ZSH_DIR/custom"
}
sudo() { printf '%s\n' "$*" >> "$HOME/privileged-calls"; }
apt-cache() { printf '  Candidate: test-version\n'; }
git() {
  if [[ $1 == clone ]]; then
    printf '%s\n' "$*" >> "$HOME/clone-calls"
    mkdir -p -- "${@: -1}"
  else
    command git "$@"
  fi
}
configure_chewing() { printf 'configured chewing\n' >> "$HOME/chewing-calls"; }
curl() {
  printf 'download\n' >> "$HOME/download-calls"
  while (($#)); do
    if [[ $1 == --output ]]; then
      printf 'test theme\n' > "$2"
      return
    fi
    shift
  done
  return 99
}
main
'''
        self.shell(commands)
        for name in (".zshrc", ".p10k.zsh", ".nanorc", ".tmux.conf"):
            self.assertEqual((self.home / name).read_bytes(), (ROOT / name).read_bytes())
        self.assertTrue((self.home / ".local/bin/bat").is_symlink())
        self.assertTrue((self.home / ".local/bin/fd").is_symlink())
        clones = (self.home / "clone-calls").read_text()
        self.assertEqual(len(clones.splitlines()), 5)
        self.assertEqual((self.home / "download-calls").read_text(), "download\n")
        self.assertNotIn("systemctl", (self.home / "privileged-calls").read_text())
        self.assertNotIn("chsh", (self.home / "privileged-calls").read_text())
        self.shell(commands)
        self.assertEqual((self.home / "clone-calls").read_text(), clones)
        self.assertEqual((self.home / "download-calls").read_text(), "download\n")
        self.assertFalse((self.home / ".local/state/ubuntu-setup/backups").exists())
        result = self.shell('git config --global --get-all include.path')
        self.assertEqual(len(result.stdout.splitlines()), 1)

    def test_existing_dotfile_is_preserved(self):
        destination = self.home / ".zshrc"
        destination.write_text("user configuration\n")
        self.shell('install_file "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"')
        self.assertEqual(destination.read_text(), "user configuration\n")
        self.assertFalse((self.home / ".local").exists())

    def test_replacement_is_backed_up_and_rerun_creates_no_duplicate_backup(self):
        destination = self.home / ".zshrc"
        destination.write_text("original\n")
        self.shell('REPLACE_DOTFILES=true\ninstall_file "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"')
        self.assertEqual(destination.read_bytes(), (ROOT / ".zshrc").read_bytes())
        backups = list((self.home / ".local/state/ubuntu-setup/backups").glob("*/files/**/.zshrc"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "original\n")
        before = sorted(self.home.rglob("*"))
        self.shell('REPLACE_DOTFILES=true\ninstall_file "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"')
        self.assertEqual(before, sorted(self.home.rglob("*")))

    def test_symlink_target_is_not_overwritten(self):
        target = self.base / "external-config"
        target.write_text("external original\n")
        destination = self.home / ".zshrc"
        destination.symlink_to(target)
        self.shell('REPLACE_DOTFILES=true\ninstall_file "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"')
        self.assertFalse(destination.is_symlink())
        self.assertEqual(target.read_text(), "external original\n")
        backups = list((self.home / ".local/state/ubuntu-setup/backups").glob("*/files/**/.zshrc"))
        self.assertEqual(len(backups), 1)
        self.assertTrue(backups[0].is_symlink())
        self.assertEqual(backups[0].readlink(), target)

    def test_dangling_symlink_is_preserved_by_default(self):
        destination = self.home / ".zshrc"
        destination.symlink_to(self.base / "missing")
        self.shell('install_file "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"')
        self.assertTrue(destination.is_symlink())

    def test_directory_is_never_replaced(self):
        destination = self.home / ".zshrc"
        destination.mkdir()
        result = self.shell(
            'REPLACE_DOTFILES=true\ninstall_file "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"', success=False,
        )
        self.assertIn("Refusing to replace a directory", result.stderr)
        self.assertTrue(destination.is_dir())

    def test_missing_source_does_not_remove_existing_symlink(self):
        destination = self.home / ".zshrc"
        destination.symlink_to(self.base / "missing-target")
        self.shell(
            'REPLACE_DOTFILES=true\ninstall_file "$HOME/missing-source" "$HOME/.zshrc"', success=False,
        )
        self.assertTrue(destination.is_symlink())

    def test_existing_checkout_is_preserved(self):
        checkout = self.home / "checkout"
        checkout.mkdir()
        self.shell('git() { return 99; }\nclone_repo https://invalid.example/repo "$HOME/checkout"')
        self.assertEqual(list(checkout.iterdir()), [])

    def test_failed_clone_leaves_no_final_checkout(self):
        result = self.shell(
            'trap cleanup EXIT\n'
            'git() { mkdir -p -- "${@: -1}"; return 9; }\n'
            'clone_repo https://invalid.example/repo "$HOME/checkout"', success=False,
        )
        self.assertEqual(result.returncode, 9)
        self.assertFalse((self.home / "checkout").exists())

    def test_unsupported_release_is_rejected(self):
        release = self.base / "os-release"
        release.write_text('ID=ubuntu\nVERSION_ID="24.04"\n')
        result = self.shell(f"check_ubuntu {shlex.quote(str(release))}", success=False)
        self.assertIn("Only Ubuntu 26.04", result.stderr)
        release.write_text('ID=debian\nVERSION_ID="26.04"\n')
        self.shell(f"check_ubuntu {shlex.quote(str(release))}", success=False)

    def test_desktop_requires_session_before_sudo_or_downloads(self):
        self.block_external_commands()
        result = self.cli("--desktop")
        self.assertNotEqual(result.returncode, 0)
        # Root is rejected before graphical-session validation, when applicable.
        self.assertRegex(result.stderr, "graphical GNOME session|not root or sudo")
        self.assertEqual(list(self.home.iterdir()), [])

    def test_git_identity_is_preserved_and_include_is_not_duplicated(self):
        primary = self.home / ".gitconfig"
        original = '[user]\n name = Existing User\n email = existing@example.invalid\n signingkey = KEEP\n'
        primary.write_text(original)
        self.shell('REPLACE_DOTFILES=true\ninstall_git_preferences\ninstall_git_preferences')
        self.assertTrue(primary.read_text().startswith(original))
        self.assertEqual(primary.read_text().count("path ="), 1)
        result = self.shell('git config --global --includes user.email\ngit config --global --includes user.signingkey\ngit config --global --includes core.pager')
        self.assertEqual(result.stdout.splitlines(), ["existing@example.invalid", "KEEP", "delta"])

    def test_git_preferences_do_not_activate_over_existing_config_by_default(self):
        primary = self.home / ".gitconfig"
        original = '[user]\n name = Keep Me\n'
        primary.write_text(original)
        result = self.shell('install_git_preferences')
        self.assertEqual(primary.read_text(), original)
        self.assertIn("To activate shared preferences", result.stdout)
        self.assertTrue((self.home / ".config/git/ubuntu-setup.gitconfig").is_file())

    def test_new_git_config_uses_preferences_without_identity(self):
        self.shell('install_git_preferences')
        result = self.shell('git config --global --includes core.pager\n! git config --global --includes user.email')
        self.assertEqual(result.stdout.strip(), "delta")

    def test_missing_gsettings_schema_is_skipped(self):
        result = self.shell(
            "GNOME_SCHEMAS=org.example.Other\n"
            'gsettings() { printf "unexpected call"; return 99; }\n'
            'set_setting org.example.Missing key true'
        )
        self.assertIn("Skipping missing schema", result.stderr)
        self.assertNotIn("unexpected call", result.stdout)
        self.assertFalse((self.home / ".local").exists())

    def test_gsettings_change_backs_up_previous_value(self):
        self.shell(
            'GNOME_SCHEMAS=org.example.Settings\n'
            'gsettings() {\n'
            '  case "$1" in\n'
            '    list-keys) printf "enabled\\n" ;;\n'
            '    writable) printf "true\\n" ;;\n'
            '    get) printf "false\\n" ;;\n'
            '    set) printf "%s\\n" "$*" > "$HOME/settings-call" ;;\n'
            '  esac\n'
            '}\n'
            'set_setting org.example.Settings enabled true'
        )
        backups = list((self.home / ".local/state/ubuntu-setup/backups").glob("*/gsettings.tsv"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "org.example.Settings\tenabled\tfalse\n")
        self.assertEqual((self.home / "settings-call").read_text(), "set org.example.Settings enabled true\n")

    @unittest.skipUnless(shutil.which("tmux"), "tmux is not installed")
    def test_standalone_tmux_configuration(self):
        socket = str(self.base / "tmux.sock")
        command = ["tmux", "-S", socket]
        try:
            result = subprocess.run(
                [*command, "-f", str(ROOT / ".tmux.conf"), "new-session", "-d", "-s", "config-test", "sleep 30"],
                env=self.env, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            for option, expected in (("prefix", "C-a"), ("status-position", "top"), ("default-terminal", "tmux-256color")):
                result = subprocess.run(
                    [*command, "show-options", "-gv", option], env=self.env, capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)
        finally:
            subprocess.run([*command, "kill-server"], env=self.env, capture_output=True)

    @unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
    def test_zsh_config_without_optional_components_preserves_terminal(self):
        self.env["TERM"] = "screen-256color"
        result = self.zsh(f'source {shlex.quote(str(ROOT / ".zshrc"))}; print -r -- "$TERM"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "screen-256color")
        self.assertEqual(result.stderr, "")

    @unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
    def test_clipboard_helpers_prefer_wayland(self):
        directory = self.home / ".local/bin"
        directory.mkdir(parents=True)
        for name in ("wl-copy", "wl-paste", "xclip"):
            command = directory / name
            command.write_text(f'#!/bin/sh\nprintf "{name}\\n" >> "$HOME/clipboard-calls"\n')
            command.chmod(0o755)
        self.env.update(WAYLAND_DISPLAY="wayland-test", DISPLAY=":99")
        result = self.zsh(f'source {shlex.quote(str(ROOT / ".zshrc"))}; clip; paste')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual((self.home / "clipboard-calls").read_text(), "wl-copy\nwl-paste\n")
        self.env.pop("WAYLAND_DISPLAY")
        result = self.zsh(f'source {shlex.quote(str(ROOT / ".zshrc"))}; clip; paste')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "clipboard-calls").read_text(), "wl-copy\nwl-paste\nxclip\nxclip\n")

    def test_repository_git_preferences_have_no_identity(self):
        result = subprocess.run(
            ["git", "config", "--file", str(ROOT / ".gitconfig"), "--get-regexp", "^user\\."],
            env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
