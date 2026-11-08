#!/usr/bin/env bash
# Ubuntu 26.04 Desktop workstation setup. Run as your normal user, not sudo.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/desktop.sh
source "$SCRIPT_DIR/lib/desktop.sh"

DRY_RUN=false
REPLACE_DOTFILES=false
DESKTOP=false
GNOME_TWEAKS=false
CHEWING=true
ENABLE_SSH=false
CHANGE_SHELL=false
WORK_DIR=
BACKUP_DIR=

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

Set up a personal Ubuntu 26.04 Desktop workstation. Existing files and Git
checkouts are preserved by default. Network access and sudo are required.

  --dry-run           Print the plan without downloads, writes, or sudo.
  --replace-dotfiles  Back up and replace changed managed dotfiles. Merge Git
                      preferences via an include; never replace Git identity.
  --desktop           Install Windows-inspired Fluent GTK and apply desktop
                      preferences (GTK4/libadwaita apps may not use the theme).
  --gnome-tweaks      Install GNOME Tweaks.
  --chewing           Install and enable Chewing (the default).
  --skip-chewing      Skip Chewing installation and input-source changes.
                      Otherwise a graphical GNOME session is required.
  --enable-ssh        Install OpenSSH server and enable ssh.socket. This opens
                      a network listener, including during package installation.
  --change-shell      Change your login shell to zsh.
  -h, --help          Show this help.

No LibreOffice, Peek, automatic package removal, or system-wide pip installs.
See README.md for package lists, backups, and third-party shell components.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --replace-dotfiles) REPLACE_DOTFILES=true ;;
      --desktop) DESKTOP=true ;;
      --gnome-tweaks) GNOME_TWEAKS=true ;;
      --chewing) CHEWING=true ;;
      --skip-chewing) CHEWING=false ;;
      --enable-ssh) ENABLE_SSH=true ;;
      --change-shell) CHANGE_SHELL=true ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
  done
}

check_ubuntu() {
  local release_file=${1:-/etc/os-release}
  local ID='' VERSION_ID=''
  [[ -r $release_file ]] || die 'Cannot identify this operating system.'
  # shellcheck source=/dev/null
  source "$release_file"
  [[ $ID == ubuntu && $VERSION_ID == 26.04 ]] ||
    die 'Only Ubuntu 26.04 is supported; no changes made.'
}

check_environment() {
  check_ubuntu
  [[ -n ${HOME:-} && $HOME == /* && -d $HOME ]] || die 'HOME must be an existing absolute directory.'
  CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
  DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
  STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
  ZSH_DIR=${ZSH:-$HOME/.oh-my-zsh}
  CUSTOM_DIR=${ZSH_CUSTOM:-$ZSH_DIR/custom}
  local path desktop=${XDG_CURRENT_DESKTOP:-}
  for path in "$CONFIG_HOME" "$DATA_HOME" "$STATE_HOME" "$ZSH_DIR" "$CUSTOM_DIR"; do
    [[ $path == /* ]] || die "Expected an absolute path: $path"
  done
  if ! $DRY_RUN; then
    [[ $EUID -ne 0 ]] || die 'Run as your normal user, not root or sudo.'
    command -v sudo >/dev/null || die 'sudo is required.'
    if $DESKTOP || $CHEWING; then
      [[ ${desktop,,} == *gnome* && -n ${DBUS_SESSION_BUS_ADDRESS:-} &&
         -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] ||
        die '--desktop and the default Chewing setup require a graphical GNOME session; use --skip-chewing to skip input setup.'
      command -v gsettings >/dev/null || die 'GNOME gsettings is required.'
    fi
  fi
}

install_packages() {
  step 'Installing Ubuntu packages'
  local -a packages=(
    # Build tools and Python (use virtual environments, not sudo pip).
    build-essential clang python3-dev python3-pip python3-setuptools python3-venv pipenv
    # CLI, shell, editors, and clipboard support for Wayland/XWayland.
    git git-delta zsh bat fd-find ripgrep fzf micro nano tmux ncdu htop tree
    curl wget aria2 dos2unix ca-certificates wl-clipboard xclip
    fonts-jetbrains-mono
  )
  $DESKTOP && packages+=(fonts-roboto fonts-roboto-slab sassc gtk2-engines-murrine gnome-themes-extra)
  $GNOME_TWEAKS && packages+=(gnome-tweaks)
  $CHEWING && packages+=(ibus-chewing python3-gi)
  $ENABLE_SSH && packages+=(openssh-server)
  run sudo apt-get update
  # Require a candidate for every requested package before attempting installation.
  if ! $DRY_RUN; then
    local package candidate
    for package in "${packages[@]}"; do
      candidate=$(LC_ALL=C apt-cache policy "$package")
      [[ $candidate == *'Candidate:'* && $candidate != *'Candidate: (none)'* ]] ||
        die "No candidate for $package. Check the Ubuntu repositories (including universe)."
    done
  fi
  run sudo apt-get install -y --no-install-recommends "${packages[@]}"
}

install_command_links() {
  step 'Preparing bat and fd command names'
  local name target
  for name in bat fd; do
    case "$name" in bat) target=/usr/bin/batcat ;; fd) target=/usr/bin/fdfind ;; esac
    if path_exists "$HOME/.local/bin/$name"; then
      printf 'Keeping %s\n' "$HOME/.local/bin/$name"
    else
      run mkdir -p -- "$HOME/.local/bin"
      run ln -s -- "$target" "$HOME/.local/bin/$name"
    fi
  done
}

install_shell() {
  step 'Installing shell components (existing checkouts are not updated)'
  clone_repo https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
  clone_repo https://github.com/zsh-users/zsh-autosuggestions.git "$CUSTOM_DIR/plugins/zsh-autosuggestions"
  clone_repo https://github.com/zsh-users/zsh-syntax-highlighting.git "$CUSTOM_DIR/plugins/zsh-syntax-highlighting"
  clone_repo https://github.com/MichaelAquilina/zsh-you-should-use.git "$CUSTOM_DIR/plugins/you-should-use"
  clone_repo https://github.com/romkatv/powerlevel10k.git "$CUSTOM_DIR/themes/powerlevel10k"
}

install_git_preferences() {
  local preferences="$CONFIG_HOME/git/ubuntu-setup.gitconfig" includes
  install_file "$SCRIPT_DIR/.gitconfig" "$preferences"
  # An include keeps all existing identities, signing settings, and conditional includes.
  if ! $DRY_RUN; then
    includes=$(git config --global --get-all include.path) || {
      [[ $? == 1 ]] || die 'Cannot read your global Git configuration.'
      includes=
    }
    if grep -Fxq -- "$preferences" <<< "$includes"; then
      return
    fi
  fi
  if ! $REPLACE_DOTFILES && { path_exists "${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}" ||
      path_exists "$CONFIG_HOME/git/config"; }; then
    printf 'Keeping existing Git configuration. To activate shared preferences:\n'
    printf '  git config --global --add include.path %q\n' "$preferences"
  else
    run git config --global --add include.path "$preferences"
  fi
}

install_dotfiles() {
  step 'Installing configuration (preserve by default; replace only with backups)'
  local name
  for name in .zshrc .p10k.zsh .nanorc .tmux.conf; do
    install_file "$SCRIPT_DIR/$name" "$HOME/$name"
  done
  install_git_preferences
  install_file "$SCRIPT_DIR/config/micro/settings.json" "$CONFIG_HOME/micro/settings.json"

  local theme="$CONFIG_HOME/micro/colorschemes/dracula.micro"
  if path_exists "$theme"; then
    printf 'Keeping %s\n' "$theme"
  else
    prepare_workspace
    run curl --fail --location --retry 3 --connect-timeout 15 --max-time 120 \
      https://raw.githubusercontent.com/dracula/micro/master/dracula.micro \
      --output "$WORK_DIR/dracula.micro"
    install_file "$WORK_DIR/dracula.micro" "$theme"
  fi
}

main() {
  parse_args "$@"
  check_environment
  trap cleanup EXIT
  trap 'printf "Error at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
  $DRY_RUN && step 'Dry run: no commands that change the system will be executed'
  install_packages
  install_command_links
  install_shell
  install_dotfiles
  if $DESKTOP; then
    install_desktop_theme
    configure_desktop
  fi
  if $CHEWING; then
    configure_chewing
  fi
  if $ENABLE_SSH; then
    step 'Enabling SSH socket activation (network listener)'
    run sudo systemctl enable --now ssh.socket
  fi
  if $CHANGE_SHELL; then
    step 'Changing your login shell to zsh'
    if $DRY_RUN; then
      run sudo chsh -s /usr/bin/zsh "$(id -un)"
    else
      local zsh_path
      zsh_path=$(command -v zsh)
      if [[ $(getent passwd "$(id -un)" | cut -d: -f7) != "$zsh_path" ]]; then
        run sudo chsh -s "$zsh_path" "$(id -un)"
      fi
    fi
  fi
  step 'Done. Start zsh to try the shell; log out/in after changing your login shell.'
  [[ -z $BACKUP_DIR ]] || printf 'Backups: %s\n' "$BACKUP_DIR"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
