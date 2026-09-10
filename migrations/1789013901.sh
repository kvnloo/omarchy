echo "Reset SDDM theme to omarchy if current theme lacks QtVersion=6 and Qt5 greeter is absent"

sddm_config=/etc/sddm.conf.d/10-theme.conf

# Only root can write the SDDM config. If sudo fails, mark pending and prompt
# the user to rerun from a terminal where they can enter a password.
as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# The SDDM config may not exist yet, or might be a broken symlink. Either way
# means the config is unconfigured; let SDDM use its default until setup runs.
if [[ ! -f $sddm_config ]]; then
  exit 0
fi

# Read the current theme from the SDDM config. If Current= is missing or empty,
# SDDM falls back to its default behavior -- nothing to repair.
current_theme=$(grep -E '^\s*Current\s*=' "$sddm_config" | head -1 | sed 's/^[^=]*=//' | xargs)
if [[ -z $current_theme ]]; then
  exit 0
fi

# Already using omarchy -- nothing to check or fix.
if [[ $current_theme == "omarchy" ]]; then
  exit 0
fi

# Look for the theme's metadata.desktop in the standard SDDM theme directories.
# Check both /usr/share/sddm/themes (packaged themes) and ~/.local/share/sddm/themes
# (user themes), following SDDM's search order.
metadata_file=
for theme_dir in /usr/share/sddm/themes ~/.local/share/sddm/themes; do
  candidate="$theme_dir/$current_theme/metadata.desktop"
  if [[ -f $candidate ]]; then
    metadata_file=$candidate
    break
  fi
done

# The configured theme does not exist. SDDM would fail to start the greeter
# anyway, so resetting to omarchy is the right repair.
if [[ -z $metadata_file ]]; then
  echo "SDDM theme '$current_theme' not found; resetting to omarchy..."
  if ! as_root sed -i 's/^\s*Current\s*=.*/Current=omarchy/' "$sddm_config"; then
    echo "Administrator privileges required to repair SDDM theme config. Run omarchy-migrate again from a terminal." >&2
    exit 1
  fi
  exit 0
fi

# Check if the theme's metadata declares QtVersion=6. Case-insensitive match
# since .desktop files can vary in casing, and any value starting with 6 counts.
if grep -qiE '^\s*QtVersion\s*=\s*6' "$metadata_file"; then
  exit 0
fi

# The theme lacks QtVersion=6. Check if Qt5 greeter libraries are present.
# SDDM looks for sddm-greeter in /usr/bin (or /usr/lib/sddm/ for the Qt5 variant
# on some distros). On Arch, the package provides /usr/bin/sddm-greeter-qt6 when
# built with Qt6, and /usr/lib/qt5/plugins/sddm-greeter/ contains the Qt5 plugin.
qt5_present=false
for qt5_indicator in /usr/lib/qt5/plugins/sddm-greeter /usr/lib/sddm/sddm-greeter-qt5; do
  if [[ -e $qt5_indicator ]]; then
    qt5_present=true
    break
  fi
done

# If Qt5 is still present, the theme can load. No repair needed.
if $qt5_present; then
  exit 0
fi

# The current theme lacks QtVersion=6 and Qt5 greeter libs are absent. SDDM
# would fail to start, leaving a black screen or login loop. Reset to omarchy.
echo "SDDM theme '$current_theme' requires Qt5 but Qt5 greeter libraries are not installed."
echo "Resetting SDDM theme to omarchy to prevent login failure..."
if ! as_root sed -i 's/^\s*Current\s*=.*/Current=omarchy/' "$sddm_config"; then
  echo "Administrator privileges required to repair SDDM theme config. Run omarchy-migrate again from a terminal." >&2
  exit 1
fi

echo "SDDM theme has been reset to omarchy. Run 'omarchy-refresh-sddm' to restore default theme files if needed."
