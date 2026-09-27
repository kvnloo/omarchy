# Let TRIM and the dm-crypt workqueue bypass reach the SSD on encrypted installs,
# for the install path and for the migration that repairs machines installed
# before this existed.
#
# dm-crypt refuses TRIM unless its mapping was opened with allow-discards, so an
# encrypted root advertises no discard support at all (discard_granularity 0),
# and btrfs — which enables discard=async on its own since 6.2, but only for
# devices that advertise discard support — never releases a block on the SSD.
# The controller keeps treating freed blocks as live data, which costs write
# amplification and endurance. fstrim cannot help either: with the option absent
# the discard reaches dm-crypt's queue and stops there.
#
# The mkinitcpio encrypt hook — the parser Omarchy's HOOKS drop-in selects over
# the base mkinitcpio.conf — reads the kernel cmdline parameter
# cryptdevice=<device>:<name>:<options> and hands the third colon field to
# cryptsetup as a comma-separated option list, so the options belong there:
#
#   allow-discards      let TRIM reach the drive
#   no-read-workqueue   bypass dm-crypt's crypt workqueue on reads
#   no-write-workqueue  bypass dm-crypt's crypt workqueue on writes
#
# Those names are the hook's own spellings. It matches each option against a
# whitelist and warns about, but ignores, everything else, so the parameter has
# to say allow-discards rather than whatever cryptsetup takes on a command line.
# The workqueue options are what cryptsetup calls --perf-no_read_workqueue and
# --perf-no_write_workqueue. They skip the queue hop between the block layer
# and the cipher; the default crypt workqueue is unbound, not per-CPU (that
# needs the separate same_cpu_crypt option), so the effect is workload
# dependent — faster on some NVMe, noise elsewhere — and no measurement here
# claims more than that. Discard bios bypass the crypt queues entirely, so the
# bypasses are independent of the discards; they ship together because both
# want the shortest path between the filesystem and the device.
#
# Trade-off, stated plainly: letting discards through tells anyone who can read
# the raw device which blocks are in use, which can reveal the filesystem type
# and how full it is (see the kernel's Documentation/admin-guide/dm-crypt.rst).
# The migration also records the flags in the LUKS2 header with --persistent
# when the live refresh runs, so they then apply to every later activation even
# if the kernel cmdline parameter is removed afterwards; fresh installs stay
# cmdline-only.
#
# A machine that unlocks through rd.luks.* has no cryptdevice= parameter to
# extend and is left alone. A commented-out cryptdevice= is not effective
# either: the hook never sees it, so it is ignored for detection, editing,
# and verification alike.

source "$(dirname -- "${BASH_SOURCE[0]}")/as-root.sh"

# Written in this order on the parameters that lack them.
OMARCHY_LUKS_TRIM_OPTIONS=(allow-discards no-read-workqueue no-write-workqueue)

# Each active cryptdevice= parameter in <file>, one per line. A parameter on a
# comment line is not active: the encrypt hook never sees it, so it must not
# count as a cryptdevice to repair or to verify.
omarchy_luks_active_params() {
  grep -Ev '^[[:space:]]*#' "$1" 2>/dev/null |
    grep -oE "cryptdevice=[^:[:space:]\"']+:[^:[:space:]\"']+(:[^:[:space:]\"']*)?"
}

# True when the cryptdevice= parameter <param> carries <option> in its option
# field. The option field is the third colon field; it may be absent or empty,
# both of which the hook accepts.
omarchy_luks_param_has_option() {
  local spec="${1#cryptdevice=}" rest opts
  rest="${spec#*:}" # drop the device field
  opts=""
  [[ $rest == *:* ]] && opts="${rest#*:}"
  [[ ",$opts," == *",$2,"* ]]
}

# True when <file> exists and carries at least one active cryptdevice=
# parameter.
omarchy_luks_has_cryptdevice() {
  [[ -f $1 ]] && omarchy_luks_active_params "$1" | grep -q .
}

# True when every active cryptdevice= parameter in <file> already carries all
# the TRIM options. Each parameter is judged on its own: one repaired
# parameter does not stand in for another.
omarchy_luks_has_trim_options() {
  local file="$1" param option
  omarchy_luks_has_cryptdevice "$file" || return 1
  while IFS= read -r param; do
    for option in "${OMARCHY_LUKS_TRIM_OPTIONS[@]}"; do
      omarchy_luks_param_has_option "$param" "$option" || return 1
    done
  done < <(omarchy_luks_active_params "$file")
}

# Add every missing option to every active cryptdevice= parameter in <file>.
# An existing option list is extended with a comma; a parameter with an empty
# or absent option field gains the list after the name. Comment lines are never
# touched, and a parameter that already carries an option keeps it exactly
# once, which is what makes a repeat run change nothing.
omarchy_luks_add_trim_options() {
  local file="$1" tmp awkprog
  tmp="$(mktemp)" || return 1
  awkprog="$(mktemp)" || { rm -f "$tmp"; return 1; }
  cat >"$awkprog" <<'AWK'
BEGIN { n = split(options, want, " ") }
/^[[:space:]]*#/ { print; next }
{
  line = $0; out = ""
  while (match(line, /cryptdevice=[^:[:space:]"']+:[^:[:space:]"']+(:[^:[:space:]"']*)?/)) {
    pre = substr(line, 1, RSTART - 1)
    param = substr(line, RSTART, RLENGTH)
    line = substr(line, RSTART + RLENGTH)
    spec = substr(param, 13) # strip "cryptdevice="
    c1 = index(spec, ":")
    dev = substr(spec, 1, c1 - 1)
    rest = substr(spec, c1 + 1)
    c2 = index(rest, ":")
    if (c2 == 0) { name = rest; opts = "" }
    else { name = substr(rest, 1, c2 - 1); opts = substr(rest, c2 + 1) }
    for (i = 1; i <= n; i++)
      if (index("," opts ",", "," want[i] ",") == 0)
        opts = (opts == "" ? want[i] : opts "," want[i])
    out = out pre "cryptdevice=" dev ":" name ":" opts
  }
  print out line
}
AWK
  awk -v options="${OMARCHY_LUKS_TRIM_OPTIONS[*]}" -f "$awkprog" "$file" >"$tmp"
  rm -f "$awkprog"
  as_root cp "$tmp" "$file"
  rm -f "$tmp"
}

# True when <text> (a generated boot cmdline, never the config just edited)
# carries <option> on an active cryptdevice= parameter.
omarchy_luks_text_has_trim_option() {
  local text="$1" option="$2" param
  while IFS= read -r param; do
    omarchy_luks_param_has_option "$param" "$option" && return 0
  done < <(printf '%s\n' "$text" |
    grep -Ev '^[[:space:]]*#' |
    grep -oE "cryptdevice=[^:[:space:]\"']+:[^:[:space:]\"']+(:[^:[:space:]\"']*)?")
  return 1
}

# True when every generated boot artifact that exists carries all three TRIM
# options on its cryptdevice= parameters. This reads the generated
# /boot/limine.conf and the .cmdline section of each Omarchy UKI -- the
# artifacts that actually boot -- never the config file the migration just
# edited. limine-entry-tool --get-cmdline recomputes from the config files, so
# it cannot catch a build that skipped the kernel image and exited 0 anyway.
omarchy_luks_boot_artifacts_trimmed() {
  local boot_conf="${OMARCHY_LUKS_TRIM_BOOT_CONF:-/boot/limine.conf}"
  local uki_dir="${OMARCHY_LUKS_TRIM_UKI_DIR:-/boot/EFI/Linux}"
  local checked=0 uki cmdline option

  if [[ -f $boot_conf ]]; then
    checked=1
    cmdline="$(as_root cat "$boot_conf" 2>/dev/null)"
    for option in "${OMARCHY_LUKS_TRIM_OPTIONS[@]}"; do
      omarchy_luks_text_has_trim_option "$cmdline" "$option" || return 1
    done
  fi

  if command -v objcopy >/dev/null 2>&1; then
    for uki in "$uki_dir"/omarchy_linux*.efi; do
      [[ -f $uki ]] || continue
      checked=1
      cmdline="$(as_root objcopy -O binary --only-section=.cmdline "$uki" /dev/stdout 2>/dev/null | tr -d '\0')"
      for option in "${OMARCHY_LUKS_TRIM_OPTIONS[@]}"; do
        omarchy_luks_text_has_trim_option "$cmdline" "$option" || return 1
      done
    done
  fi

  ((checked))
}

# The mapping name from the first active cryptdevice= parameter, for
# refreshing a mapping that is already open. Fails when no active parameter
# names a mapping.
omarchy_luks_mapping_name() {
  local spec

  spec=$(omarchy_luks_active_params "$1" | head -1) || true
  [[ $spec == cryptdevice=*:* ]] || return 1
  spec=${spec#cryptdevice=}
  spec=${spec#*:}
  printf '%s\n' "${spec%%:*}"
}
