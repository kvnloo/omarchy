echo "Let TRIM reach the SSD through dm-crypt on the LUKS root volume"

# The install leaf (install/config/luks-trim.sh) adds the dm-crypt options to
# fresh installs. This repairs machines installed before it existed, using the
# same helper, so both paths agree on the exact option list.

source "$OMARCHY_PATH/install/helpers/luks-trim.sh"

limine_conf="${OMARCHY_LUKS_TRIM_LIMINE_CONF:-/etc/default/limine}"
trim_marker="${OMARCHY_LUKS_TRIM_MARKER:-/var/lib/omarchy/migrations/1790190839}"

[[ ! -e $trim_marker ]] || exit 0

# No /etc/default/limine, or no active cryptdevice= parameter in it: nothing
# to repair. A commented-out parameter is not effective, so it counts as no
# parameter at all.
if ! omarchy_luks_has_cryptdevice "$limine_conf"; then
  exit 0
fi

# The encrypt hook needs limine-mkinitcpio to regenerate the boot image. The
# tool is gone on images that no longer use limine; leave them alone.
if omarchy-cmd-missing limine-mkinitcpio; then
  exit 0
fi

if ! omarchy_luks_has_trim_options "$limine_conf"; then
  echo "Allowing TRIM through dm-crypt in $limine_conf"
  omarchy_luks_add_trim_options "$limine_conf"
fi

if ! as_root limine-mkinitcpio; then
  echo "limine-mkinitcpio failed; the boot entries were not regenerated." >&2
  exit 1
fi

# The generated artifacts are what boots, so they are what proves the repair.
# limine-entry-tool --get-cmdline recomputes from the config files and cannot
# catch a build that skipped the kernel image while exiting 0 anyway.
if ! omarchy_luks_boot_artifacts_trimmed; then
  echo "The generated boot entries do not carry the TRIM options; rerun omarchy-migrate after fixing the boot image build." >&2
  exit 1
fi

# Let the options take effect on the running mapping without a reboot, when
# the mapping is already open. Skipped in unattended updates: omarchy update
# runs under script(1), so the terminal gate below cannot tell an unattended
# run apart from an operator who can answer a passphrase prompt. The kernel
# cmdline repair above plus a reboot covers the unattended case.
mapping=$(omarchy_luks_mapping_name "$limine_conf") || mapping=""
trim_live=0
if [[ -n $mapping && -t 0 && -t 1 && -z ${OMARCHY_UPDATE_UNATTENDED:-} ]]; then
  echo "Refreshing the running LUKS mapping; cryptsetup will ask for the disk passphrase."
  if as_root cryptsetup refresh --allow-discards --perf-no_read_workqueue \
    --perf-no_write_workqueue --persistent "$mapping"; then
    trim_live=1
  else
    echo "The running mapping was left as it is; the options apply at the next boot." >&2
  fi
elif [[ -n $mapping && -n ${OMARCHY_UPDATE_UNATTENDED:-} ]]; then
  echo "Skipping the live refresh of the running LUKS mapping (unattended update); the options apply at the next boot."
fi

if (( !trim_live )); then
  omarchy-state set reboot-required
fi

as_root install -Dm644 /dev/null "$trim_marker"
