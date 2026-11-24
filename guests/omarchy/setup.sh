# guests/omarchy/setup.sh - install Omarchy on top of the Arch cloud image (after guest/common.sh).
# Unattended: git clone + upstream install.sh run as $DEVVM_ADMIN_USER with passwordless sudo
#   (OMARCHY_USER_NAME / OMARCHY_USER_EMAIL preseed the git identity prompts).
# NOT guaranteed unattended: upstream may add prompts, expects its ISO's disk layout (limine/LUKS/snapper
# steps are skipped or fail on a cloud image), and may reboot. Failures here are warnings, not fatal.
if [ "${DEVVM_DESKTOP:-0}" = 1 ]; then
  devvm_step "installing Omarchy prerequisites"
  pkg_update
  pkg_install git base-devel curl sudo
  _u="${DEVVM_ADMIN_USER:-dev}"
  if [ -d "/home/$_u/.local/share/omarchy/.git" ]; then
    devvm_step "Omarchy already cloned; skipping fetch"
  else
    devvm_step "cloning Omarchy (${OMARCHY_REF:-master})"
    sudo -u "$_u" git clone --depth 1 -b "${OMARCHY_REF:-master}" "${OMARCHY_REPO:-https://github.com/basecamp/omarchy.git}" \
      "/home/$_u/.local/share/omarchy" || devvm_fail "omarchy clone failed"
  fi
  if [ -e /var/lib/devvm-omarchy-done ]; then
    devvm_step "Omarchy install already completed"
  else
    devvm_step "running Omarchy install.sh (slow; unattended best effort)"
    if sudo -u "$_u" env HOME="/home/$_u" OMARCHY_USER_NAME="${OMARCHY_USER_NAME:-$_u}" \
         OMARCHY_USER_EMAIL="${OMARCHY_USER_EMAIL:-$_u@localhost}" OMARCHY_PATH="/home/$_u/.local/share/omarchy" \
         bash -c 'cd "$OMARCHY_PATH" && source install.sh' </dev/null; then
      touch /var/lib/devvm-omarchy-done
    else
      devvm_step "WARNING: Omarchy install.sh failed or was interrupted; see /var/log/devvm-provision.log"
    fi
  fi
fi
