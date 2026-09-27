#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# install/hardware/intel/video-acceleration.sh picks the VA-API driver from the
# lspci description: intel-media-driver (iHD, Broadwell and newer) or
# libva-intel-driver (i965, GMA through ~2017). Two generations were routed
# wrong: "xe" matched "Xeon" in pre-Xe PCI strings, sending Haswell iGPUs to a
# driver that cannot drive them, and unrecognized older descriptions (Sandy/
# Ivy Bridge, non-Xeon Haswell) installed no driver at all.

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"

cat >"$STUB_DIR/lspci" <<'STUB'
#!/bin/bash
printf '%s\n' "$FAKE_LSPCI"
STUB

cat >"$STUB_DIR/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_CALLS"
STUB

chmod +x "$STUB_DIR"/*

# Runs the script against one lspci line; leaves requested packages in $CALLS.
detect() {
  : >"$TMPDIR/calls"
  FAKE_LSPCI="$1" FAKE_CALLS="$TMPDIR/calls" \
    PATH="$STUB_DIR:$PATH" \
    bash "$ROOT/install/hardware/intel/video-acceleration.sh"
  CALLS=$(cat "$TMPDIR/calls")
}

HASWELL_XEON='00:02.0 VGA compatible controller [0300]: Intel Corporation Xeon E3-1200 v3/4th Gen Core Processor Integrated Graphics Controller [8086:041a]'
IVY_BRIDGE='00:02.0 VGA compatible controller [0300]: Intel Corporation 3rd Gen Core processor Graphics Controller [8086:0166]'
TIGER_LAKE='00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics] [8086:9a49]'
ARC='03:00.0 VGA compatible controller [0300]: Intel Corporation DG2 [Arc A380] [8086:56a5]'
GMA='00:02.0 VGA compatible controller [0300]: Intel Corporation Mobile 945GM/GMS, 943/940GML Express Integrated Graphics Controller [8086:27a2]'

# A Xeon-branded Haswell iGPU is pre-Broadwell: the "xe" in "Xeon" must not
# route it to intel-media-driver, which only supports Broadwell and newer.
detect "$HASWELL_XEON"
[[ $CALLS == *"libva-intel-driver"* ]] || fail "Haswell Xeon iGPU gets libva-intel-driver" "$CALLS"
[[ $CALLS != *"intel-media-driver"* ]] || fail "Haswell Xeon iGPU does not get intel-media-driver" "$CALLS"
pass "Haswell Xeon iGPU gets libva-intel-driver, not intel-media-driver"

# Older generations the new-driver match never recognized still need a driver.
detect "$IVY_BRIDGE"
[[ $CALLS == *"libva-intel-driver"* ]] || fail "Ivy Bridge iGPU gets libva-intel-driver" "$CALLS"
pass "Ivy Bridge iGPU gets libva-intel-driver instead of nothing"

# GMA keeps the driver it always had.
detect "$GMA"
[[ $CALLS == *"libva-intel-driver"* ]] || fail "GMA iGPU keeps libva-intel-driver" "$CALLS"
pass "GMA iGPU keeps libva-intel-driver"

# Current generations are unaffected.
detect "$TIGER_LAKE"
[[ $CALLS == *"intel-media-driver"* && $CALLS == *"libvpl"* && $CALLS == *"vpl-gpu-rt"* ]] \
  || fail "Iris Xe iGPU gets intel-media-driver + VPL" "$CALLS"
pass "Iris Xe iGPU still gets intel-media-driver + VPL"

detect "$ARC"
[[ $CALLS == *"intel-media-driver"* ]] || fail "Arc GPU gets intel-media-driver" "$CALLS"
pass "Arc GPU still gets intel-media-driver"

# No Intel GPU, no packages.
detect '01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA106 [GeForce RTX 3060] [10de:2503]'
[[ -z $CALLS ]] || fail "non-Intel GPU installs no VA-API driver" "$CALLS"
pass "non-Intel GPU installs no VA-API driver"
