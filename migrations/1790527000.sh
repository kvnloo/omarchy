#!/bin/bash

echo "Report pam_faillock lockouts instead of masking them as wrong passwords"

# The installer used to write `preauth silent`, so a locked-out user just saw
# "wrong password" over and over instead of being told the account is locked
# (#13185). Strip `silent` from the preauth line on existing installs; the
# install script now writes the audible line for new ones.
#
# The path is a fixed literal named exactly once so the shell test can
# retarget a scratch copy (same seam as the fido2 migration test).
system_auth="/etc/pam.d/system-auth"

if [[ -f $system_auth ]] &&
  grep -Eq '^[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_faillock\.so[[:space:]]+preauth[[:space:]]+silent([[:space:]]|$)' "$system_auth"; then
  sudo sed -i -E \
    -e 's|^([[:space:]]*auth[[:space:]]+required[[:space:]]+pam_faillock\.so[[:space:]]+preauth[[:space:]]+)silent[[:space:]]+|\1|' \
    -e 's|^([[:space:]]*auth[[:space:]]+required[[:space:]]+pam_faillock\.so[[:space:]]+preauth[[:space:]]+)silent$|\1|' \
    "$system_auth"
fi
