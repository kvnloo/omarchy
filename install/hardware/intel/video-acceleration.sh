# This installs hardware video acceleration for Intel GPUs

if INTEL_GPU=$(lspci | grep -iE 'vga|3d|display' | grep -i 'intel'); then
  # HD Graphics / Iris / Xe / Arc / Non-Arc Panther Lake use intel-media-driver + VPL.
  # Xe needs the word after it: a bare "xe" also matches "Xeon" in pre-Xe PCI
  # strings (e.g. Xeon E3 Haswell iGPUs), which need the older driver below.
  if [[ ${INTEL_GPU,,} =~ (hd\ graphics|uhd\ graphics|xe\ graphics|iris|arc|panther\ lake) ]]; then
    omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
  else
    # Everything else (GMA through ~2017, including generations the new-driver
    # match does not recognize) uses libva-intel-driver.
    omarchy-pkg-add libva-intel-driver
  fi
fi
