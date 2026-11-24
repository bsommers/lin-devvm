# guests/kubuntu/setup.sh - KDE Plasma on the Ubuntu cloud image (concatenated after guest/common.sh).
if [ "${DEVVM_DESKTOP:-0}" = 1 ]; then
  devvm_step "installing kubuntu-desktop (KDE Plasma + SDDM)"
  export DEBIAN_FRONTEND=noninteractive
  echo 'sddm shared/default-display-manager select sddm' | debconf-set-selections
  pkg_install kubuntu-desktop sddm || devvm_fail "kubuntu-desktop install failed"
  devvm_step "enabling graphical boot (sddm)"
  systemctl set-default graphical.target
  systemctl enable sddm.service || true
fi
