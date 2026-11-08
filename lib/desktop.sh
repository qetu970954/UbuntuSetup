#!/usr/bin/env bash
# Opt-in GNOME settings for Ubuntu 26.04, sourced by setup.sh.

install_desktop_theme() {
  step 'Installing Windows-inspired Fluent GTK (existing themes are preserved)'
  local destination="$DATA_HOME/themes/Fluent-Light" checkout stage
  if path_exists "$destination"; then
    printf 'Keeping existing %s\n' "$destination"
    return
  fi
  prepare_workspace
  checkout="$WORK_DIR/fluent-src"
  stage="$WORK_DIR/fluent-built"
  # Pin the upstream installer; build in a temporary directory, never in HOME.
  run git init -q "$checkout"
  run git -C "$checkout" fetch --depth 1 https://github.com/vinceliuice/Fluent-gtk-theme.git 7a49a464b0188c340101c52965c18190b1c694cf
  run git -C "$checkout" checkout -q --detach FETCH_HEAD
  run mkdir -p -- "$stage" "$WORK_DIR/theme-home"
  if ! $DRY_RUN; then
    command -v sassc >/dev/null || die 'sassc is required to build Fluent.'
  fi
  # Upstream cleans old themes; isolate HOME and XDG_DATA_HOME from user files.
  run env HOME="$WORK_DIR/theme-home" XDG_DATA_HOME="$stage" bash "$checkout/install.sh" --dest "$stage" --color light --size standard
  if ! $DRY_RUN; then
    [[ -f $stage/Fluent-Light/gtk-3.0/gtk.css && -f $stage/Fluent-Light/index.theme ]] ||
      die 'The Fluent build did not produce the expected GTK theme.'
  fi
  run mkdir -p -- "$(dirname -- "$destination")"
  run mv -- "$stage/Fluent-Light" "$destination"
}

set_setting() {
  local schema=$1 key=$2 value=$3 schema_id keys current
  if $DRY_RUN; then
    run gsettings set "$schema" "$key" "$value"
    return
  fi
  schema_id=${schema%%:*}
  if ! grep -Fxq -- "$schema_id" <<< "$GNOME_SCHEMAS"; then
    warn "Skipping missing schema: $schema_id"
    return
  fi
  keys=$(gsettings list-keys "$schema")
  if ! grep -Fxq -- "$key" <<< "$keys"; then
    warn "Skipping missing key: $schema $key"
    return
  fi
  if [[ $(gsettings writable "$schema" "$key") != true ]]; then
    warn "Skipping locked setting: $schema $key"
    return
  fi
  current=$(gsettings get "$schema" "$key")
  [[ $current != "$value" ]] || return 0
  prepare_backup
  # Tab-separated schema, key, and GVariant value; never evaluated as shell code.
  printf '%s\t%s\t%s\n' "$schema" "$key" "$current" >> "$BACKUP_DIR/gsettings.tsv"
  run gsettings set "$schema" "$key" "$value"
}

configure_chewing() {
  step 'Enabling Zhuyin (IBus Chewing) while preserving existing input sources'
  if $DRY_RUN; then
    printf '  Would refresh the IBus registry and restart its GNOME service if Chewing is not registered.\n'
    printf '  Would append (ibus, chewing) to existing GNOME input sources if absent.\n'
    return
  fi
  local engines current updated
  engines=$(ibus list-engine) || die 'Cannot query IBus in this graphical session.'
  if ! grep -Eq '^[[:space:]]*chewing[[:space:]]+-' <<< "$engines"; then
    warn 'Chewing is not registered yet. Rebuilding the IBus cache and restarting IBus; input methods will be briefly interrupted.'
    ibus write-cache || die 'Could not rebuild the IBus cache.'
    systemctl --user restart org.freedesktop.IBus.session.GNOME.service || die 'Could not restart the GNOME IBus service.'
    # The service may take a moment to register its engines.
    local attempt=0
    while (( attempt < 10 )); do
      engines=$(ibus list-engine 2>/dev/null) || engines=
      grep -Eq '^[[:space:]]*chewing[[:space:]]+-' <<< "$engines" && break
      sleep 1
      ((attempt += 1))
    done
    grep -Eq '^[[:space:]]*chewing[[:space:]]+-' <<< "$engines" ||
      die 'IBus still does not list Chewing. Log out and back in, then rerun setup.'
  fi
  GNOME_SCHEMAS="$(gsettings list-schemas)"
  current=$(gsettings get org.gnome.desktop.input-sources sources)
  updated=$(/usr/bin/python3 "$SCRIPT_DIR/lib/add_chewing.py" "$current") ||
    die 'Could not safely parse existing input sources.'
  set_setting org.gnome.desktop.input-sources sources "$updated"
  [[ $(gsettings get org.gnome.desktop.input-sources sources) == "$updated" ]] ||
    die 'Could not enable Chewing in GNOME input sources (the setting may be locked).'
  printf 'Chewing is available. Press Super+Space to switch input sources.\n'
}

configure_desktop() {
  step 'Applying opt-in GNOME settings (previous values are backed up)'
  if ! $DRY_RUN; then
    GNOME_SCHEMAS="$(gsettings list-schemas)"$'\n'"$(gsettings list-relocatable-schemas)"
  fi
  set_setting org.gnome.desktop.interface gtk-theme "'Fluent-Light'"
  set_setting org.gnome.desktop.interface color-scheme "'prefer-light'"
  set_setting org.gnome.desktop.wm.preferences button-layout "':minimize,maximize,close'"
  set_setting org.gnome.desktop.interface font-name "'Roboto Condensed 14'"
  set_setting org.gnome.desktop.interface document-font-name "'Roboto Slab 14'"
  set_setting org.gnome.desktop.interface monospace-font-name "'JetBrains Mono 14'"
  set_setting org.gnome.desktop.wm.preferences titlebar-font "'Roboto Condensed Bold 14'"
  set_setting org.gnome.desktop.interface enable-animations false
  set_setting org.gnome.desktop.session idle-delay 'uint32 900'
  set_setting org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"

  # Ptyxis is the Ubuntu 26.04 terminal; do not write obsolete GNOME Terminal keys.
  set_setting org.gnome.Ptyxis use-system-font true
  set_setting org.gnome.Ptyxis interface-style "'dark'"
  local uuid
  if $DRY_RUN; then
    uuid=DEFAULT_PROFILE_UUID
  elif grep -Fxq org.gnome.Ptyxis <<< "$GNOME_SCHEMAS"; then
    uuid=$(gsettings get org.gnome.Ptyxis default-profile-uuid)
    uuid=${uuid#\'}
    uuid=${uuid%\'}
    [[ $uuid =~ ^[[:xdigit:]-]+$ ]] || uuid=
  else
    uuid=
  fi
  if [[ -n $uuid ]]; then
    set_setting "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$uuid/" palette "'dracula'"
  else
    warn 'No Ptyxis default profile found. Open Ptyxis once, then rerun --desktop.'
  fi
  warn 'Fluent affects GTK3 apps; many GTK4/libadwaita and Snap apps use their own styling. Icons, favorites, and extensions are unchanged.'
}
