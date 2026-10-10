# Install Intel Low Power Mode Daemon for supported hybrid Intel CPUs (Alder Lake and newer)
# Supported models: Alder Lake (151/154), Raptor Lake (183/186/191),
# Meteor Lake (170/172), Lunar Lake (189), Arrow Lake-U (181),
# Panther Lake (204)

cpuinfo_path="${OMARCHY_CPUINFO_PATH:-/proc/cpuinfo}"

if omarchy-hw-intel && omarchy-battery-present; then
  cpu_model=$(grep -m1 "^model\s*:" "$cpuinfo_path" 2>/dev/null | cut -d: -f2 | tr -d ' ')
  if [[ "$cpu_model" =~ ^(151|154|170|172|181|183|186|189|191|204)$ ]]; then
    omarchy-pkg-add intel-lpmd
    sudo systemctl enable intel_lpmd.service
  fi
fi
