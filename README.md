# Ubuntu workstation setup

Personal workstation configuration for **Ubuntu 26.04 Desktop (GNOME)**.
Other releases are rejected. There is no Windows or older-Ubuntu setup path.

## Run

Review the scripts and dotfiles, then run **as your normal user**, not with sudo:

```bash
./setup.sh --dry-run
./setup.sh
```

The default installs command-line tools, shell components, and missing dotfiles,
and installs and enables Chewing alongside existing input sources. Run it in a
logged-in graphical GNOME session; use `--skip-chewing` to skip input setup.
It does **not** change your login shell, enable SSH, or apply theme settings.
Existing files and checkouts are preserved. Preview works without sudo or a
graphical session and performs no writes, downloads, or package operations.

Optional components can be combined:

```bash
./setup.sh --dry-run --desktop --gnome-tweaks --chewing --change-shell
./setup.sh --desktop --gnome-tweaks --chewing --change-shell
```

| Option | Effect |
| --- | --- |
| `--replace-dotfiles` | Back up changed managed files, then replace them; activate shared Git preferences without replacing your Git identity. |
| `--desktop` | Build Windows-inspired Fluent Light GTK, select light appearance and Windows-style titlebar buttons, apply fonts, move the dock to the bottom, and configure Ptyxis. Requires your graphical GNOME session. |
| `--gnome-tweaks` | Install GNOME Tweaks. |
| `--chewing` | Install and enable Chewing alongside existing input sources (the default). |
| `--skip-chewing` | Skip Chewing installation and input-source changes. |
| `--enable-ssh` | Install OpenSSH server and enable **ssh.socket**. **Opens a network listener**, possibly during package installation. Review authentication and firewall rules first. |
| `--change-shell` | Set the current user's login shell to Zsh. Log out/in afterward. |

## What is installed

All executable tools and fonts come from Ubuntu's APT repositories, including
`git-delta`, `ripgrep`, `micro`, `fzf`, and `fonts-jetbrains-mono`. The script no
longer downloads architecture-specific `.deb` files or pipes installers to a shell.
Ubuntu's **universe** repository must be available; missing candidates are reported.

- **Development:** Git/delta, build-essential, Clang, Python development headers,
  pip, setuptools, venv, and Pipenv.
- **Shell and CLI:** Zsh, bat, fd, ripgrep, fzf, tmux, ncdu, htop, tree, curl,
  wget, aria2, dos2unix, and CA certificates.
- **Editors:** Micro and Nano.
- **Desktop integration:** JetBrains Mono, wl-clipboard for Wayland, and xclip for
  X11/XWayland. Roboto and Roboto Slab are installed with `--desktop`.
- **Third-party shell configuration:** Oh My Zsh, Powerlevel10k,
  zsh-autosuggestions, zsh-syntax-highlighting, and you-should-use.
- **Themes:** Dracula for Micro; Windows-inspired Fluent Light GTK only with
  `--desktop`. Ptyxis uses its bundled Dracula palette for the existing profile.

**LibreOffice and Peek are not installed.** Already-installed applications are
not uninstalled. There is no automatic `autoremove`, distribution upgrade, global
pip installation, or forced update/reset of an existing checkout.

Use virtual environments for Python projects; do not bypass Ubuntu's
externally-managed Python protection:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install <package>
```

## Zhuyin (Chewing)

The default setup installs Chewing, checks whether IBus recognizes it, refreshes
the IBus cache and restarts the GNOME IBus service if needed, then appends it to
your existing input sources. Restarting IBus briefly interrupts input methods.
The original source list is backed up under the state directory described below.
Press **Super+Space** to switch sources. If Chewing is still missing, close Settings
and run these commands **as your normal user, without sudo**:

```bash
ibus write-cache
systemctl --user restart org.freedesktop.IBus.session.GNOME.service
ibus list-engine | grep -i chewing
```

The restart briefly interrupts input methods. The last command should list
`chewing - Chewing`. Reopen **Settings → Keyboard → Input Sources → +**, expand
the language list if necessary, and look under **Chinese (Taiwan)** or **Other**
for **Chewing**. Use **Super+Space** to switch sources.

If your locale still hides it, you can reveal all input-source choices:

```bash
gsettings set org.gnome.desktop.input-sources show-all-sources true
```

Then close and reopen Settings. This reveals choices without replacing your
current layouts. There is no need to rerun the whole installer to refresh IBus.

## Dotfiles and local preferences

| Repository file | Purpose |
| --- | --- |
| `.zshrc` | Oh My Zsh/plugins, fzf integration, command aliases, Wayland-first `clip`/`paste` helpers. Preserves the terminal's `TERM`. |
| `.p10k.zsh` | Compact, single-line prompt with directory, Git status, command duration, Python environment, and clock. No patched font required. |
| `.gitconfig` | Shared delta and Git preferences, **no personal identity**. |
| `.tmux.conf` | Standalone Ctrl-a-prefix configuration, top status bar, and Dracula-inspired colors. No external tmux framework. |
| `.nanorc` | Indentation and line numbers; Ubuntu's `/etc/nanorc` supplies syntax highlighting. |
| `config/micro/settings.json` | Dracula, four-space indentation. |

The installer respects `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`,
`ZSH`, and `ZSH_CUSTOM` when set to absolute paths. Default destinations are in
your home directory. `~/.local/bin/bat` and `fd` are created only when absent.
Existing symlinks and checkout directories are not reset.

Git preferences are installed to
`${XDG_CONFIG_HOME:-$HOME/.config}/git/ubuntu-setup.gitconfig` and activated using
an include. If a global Git config already exists, the default run leaves it
untouched and prints the activation command. `--replace-dotfiles` opts into
adding the include; existing names, emails, signing settings, and conditional
includes remain intact. Subsequent runs do not duplicate the include.

Set your own identity if this is a new machine:

```bash
git config --global user.name 'Your Name'
git config --global user.email 'you@example.com'
```

Put machine-specific shell preferences in `~/.zshrc.local`. `paste` is a clipboard
helper in this configuration; use `command paste` for the standard Unix utility.

### Backups and reruns

Replacement backups live **outside this repository** under
`${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-setup/backups/<run>/`:

- `files/` retains each original's absolute path, contents, and symlink metadata.
  Restore an individual file with `cp -a`, after removing its replacement.
- `gsettings.tsv` records each changed schema, key, and previous GVariant value.
  Restore with `gsettings set SCHEMA KEY 'PREVIOUS_VALUE'`, passing the entire
  previous-value field as one argument. **Do not source or eval the TSV.**

Identical files are skipped, so reruns do not create duplicate file backups.
Existing theme directories and shell checkouts remain untouched even in replace
mode. Missing downloads are staged in a temporary directory, removed on exit.

Third-party shell components are fetched from their upstream default branches on
first installation. Fluent GTK's upstream installer is pinned to a commit and
builds in an isolated temporary HOME. These are not fully reproducible builds;
review upstream code before running it, and update checkouts separately.

### Desktop limitations

Fluent GTK cannot recolor every GTK4/libadwaita application or the GNOME shell.
The script does not inject custom GTK CSS, install shell extensions, replace icon
themes or change favorites. Chewing setup appends to existing input sources.
`--desktop` moves an existing
Ubuntu dock to the bottom but leaves its other preferences unchanged. Missing or
locked settings are reported and skipped. If Ptyxis has no default profile yet, open it once and
rerun `--desktop`. GNOME Terminal and gedit-specific settings have been removed.

## Layout and validation

`setup.sh` coordinates installation; `lib/common.sh` handles safe file operations
and previews; `lib/desktop.sh` contains opt-in GNOME configuration.

```bash
for file in setup.sh lib/*.sh; do bash -n "$file" || break; done
python3 tests/test_setup.py
# If installed:
shellcheck -x setup.sh lib/common.sh lib/desktop.sh
zsh -n .zshrc && zsh -n .p10k.zsh
```

Tests run with temporary home directories and mocked privileged/network commands.
They cover previews, option boundaries, release/session guards, backups, symlinks,
failed downloads, Git identity preservation, and GNOME-setting backups. They do
not run a real installation or change the current desktop. CLI preview tests
require Ubuntu 26.04; the suite uses only Python's standard library and Bash.
