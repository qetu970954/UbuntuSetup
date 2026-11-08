#!/usr/bin/env bash
# Shared helpers, sourced by setup.sh. No work is performed on source.

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
path_exists() { [[ -e $1 || -L $1 ]]; }

run() {
  if $DRY_RUN; then
    printf '  +'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

prepare_workspace() {
  if [[ -z $WORK_DIR ]]; then
    if $DRY_RUN; then
      WORK_DIR=/tmp/ubuntu-setup.preview
    else
      WORK_DIR=$(mktemp -d -t ubuntu-setup.XXXXXXXX)
    fi
  fi
}

cleanup() {
  if ! $DRY_RUN && [[ -n $WORK_DIR ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}

prepare_backup() {
  if [[ -z $BACKUP_DIR ]]; then
    if $DRY_RUN; then
      BACKUP_DIR="$STATE_HOME/ubuntu-setup/backups/preview"
    else
      mkdir -p -- "$STATE_HOME/ubuntu-setup/backups"
      BACKUP_DIR=$(mktemp -d "$STATE_HOME/ubuntu-setup/backups/$(date -u +%Y%m%dT%H%M%SZ).XXXXXXXX")
      chmod 700 "$BACKUP_DIR"
    fi
  fi
}

install_file() {
  local source=$1 destination=$2 backup
  [[ -f $source ]] || $DRY_RUN || die "Missing configuration source: $source"
  if path_exists "$destination"; then
    if cmp -s -- "$source" "$destination"; then
      printf 'Already current: %s\n' "$destination"
      return
    fi
    if ! $REPLACE_DOTFILES; then
      printf 'Keeping existing %s\n' "$destination"
      return
    fi
    [[ ! -d $destination || -L $destination ]] || die "Refusing to replace a directory: $destination"
    prepare_backup
    # Use the full destination path to also cover custom XDG locations.
    backup="$BACKUP_DIR/files$destination"
    run mkdir -p -- "$(dirname -- "$backup")"
    run cp -a -- "$destination" "$backup"
    # Never overwrite the target of a user's symlink.
    if [[ -L $destination ]]; then
      run rm -- "$destination"
    fi
  fi
  run install -D -m 644 -- "$source" "$destination"
}

clone_repo() {
  local url=$1 destination=$2 checkout
  if path_exists "$destination"; then
    printf 'Keeping existing %s\n' "$destination"
    return
  fi
  prepare_workspace
  checkout="$WORK_DIR/$(basename -- "$destination")"
  # A failed download never leaves a partial checkout in the final location.
  run git clone --depth 1 -- "$url" "$checkout"
  run mkdir -p -- "$(dirname -- "$destination")"
  run mv -- "$checkout" "$destination"
}
