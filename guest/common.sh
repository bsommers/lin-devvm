# shellcheck shell=bash
# guest/common.sh - concatenated into the single root provision script (no shebang / set -e here).
# Env header provides DEVVM_* variables.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
DEVVM_STATE=/var/lib/devvm-state
DEVVM_STEP="init"
mkdir -p /var/lib /etc/devvm

_devvm_state() { printf '%s\n' "$1" > "$DEVVM_STATE"; chmod 644 "$DEVVM_STATE"; }
devvm_step() { DEVVM_STEP="$1"; echo "[devvm $(date +%T)] $1"; _devvm_state "installing: $1"; }
devvm_warn() { echo "[devvm WARN] $*" >&2; }
devvm_fail() {
  trap - ERR
  echo "[devvm FAIL] ${1:-$DEVVM_STEP}" >&2
  _devvm_state "FAILED: ${1:-$DEVVM_STEP}"
  exit 1
}
devvm_finish() {
  trap - ERR
  touch /var/lib/devvm-ready
  _devvm_state DONE
  echo "[devvm] provisioning complete"
}
trap 'devvm_fail "$DEVVM_STEP (line $LINENO)"' ERR
set -E

have() { command -v "$1" >/dev/null 2>&1; }

# retry <tries> <cmd...>: exponential-ish backoff (5s,10s,20s...)
retry() {
  local n="$1" i=1 d=5; shift
  until "$@"; do
    (( i >= n )) && return 1
    echo "[devvm] retry $i/$n failed: $*; sleeping ${d}s" >&2
    sleep "$d"; i=$((i + 1)); d=$((d * 2))
  done
}

pkg_update() {
  case "$DEVVM_GUEST_FAMILY" in
    debian) retry 3 apt-get update -y ;;
    rhel)   retry 3 dnf -y makecache ;;
    arch)   retry 3 pacman -Sy --noconfirm ;;
    suse)   retry 3 zypper -n refresh ;;
    *) devvm_fail "unknown family $DEVVM_GUEST_FAMILY" ;;
  esac
}

# pkg_install <pkgs...>: all-or-nothing install, retried (network may not be up yet)
pkg_install() {
  case "$DEVVM_GUEST_FAMILY" in
    debian) retry 3 apt-get -y -o Dpkg::Options::=--force-confold install --no-install-recommends "$@" ;;
    rhel)   retry 3 dnf -y install "$@" ;;
    arch)   retry 3 pacman -Syu --noconfirm --needed "$@" ;;
    suse)   retry 3 zypper -n install --no-recommends "$@" ;;
    *) devvm_fail "unknown family $DEVVM_GUEST_FAMILY" ;;
  esac
}

# pkg_try <pkgs...>: best-effort, one package at a time; never fails
pkg_try() { local p; for p in "$@"; do pkg_install "$p" >/dev/null 2>&1 || devvm_warn "optional package not installed: $p"; done; return 0; }

devvm_svc_enable() { systemctl enable --now "$1" >/dev/null 2>&1 || devvm_warn "could not enable $1"; return 0; }

devvm_base() {
  devvm_step "hostname"
  hostnamectl set-hostname "$DEVVM_VM_NAME" 2>/dev/null || hostname "$DEVVM_VM_NAME" || true

  devvm_step "package index"
  pkg_update

  devvm_step "ssh hardening"
  have sshd || [[ -x /usr/sbin/sshd ]] || pkg_install openssh-server 2>/dev/null || pkg_install openssh
  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/10-devvm.conf <<'SSHD'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
AllowTcpForwarding yes
SSHD
  # Some distros lack an Include of sshd_config.d; make sure ours is honoured.
  if [[ -f /etc/ssh/sshd_config ]] && ! grep -qiE '^\s*Include\s+/etc/ssh/sshd_config\.d' /etc/ssh/sshd_config; then
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
  fi
  if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
    systemctl enable sshd >/dev/null 2>&1 || true; systemctl restart sshd || true
  else
    systemctl enable ssh >/dev/null 2>&1 || true; systemctl restart ssh || true
  fi

  devvm_step "qemu-guest-agent"
  have qemu-ga || pkg_try qemu-guest-agent
  systemctl enable --now qemu-guest-agent >/dev/null 2>&1 || systemctl enable --now qemu-ga >/dev/null 2>&1 || true
}

# devvm_mount_work: persistent data disk -> /work (roles call this). No-op when DATA_DISK_GB=0.
devvm_mount_work() {
  [[ "${DEVVM_DATA_DISK_GB:-0}" -gt 0 ]] || { echo "[devvm] no data disk configured"; return 0; }
  devvm_step "mount /work"
  local dev=/dev/disk/by-id/virtio-devvm-data i
  for i in $(seq 1 30); do [[ -e $dev ]] && break; sleep 1; done
  [[ -e $dev ]] || { devvm_warn "data disk $dev not found; skipping /work"; return 0; }
  if ! blkid "$dev" >/dev/null 2>&1; then
    mkfs.ext4 -q -L work "$dev"
  fi
  mkdir -p /work
  grep -q '^LABEL=work ' /etc/fstab || echo 'LABEL=work /work ext4 defaults,nofail 0 2' >> /etc/fstab
  systemctl daemon-reload >/dev/null 2>&1 || true
  mountpoint -q /work || mount /work
  chown "$DEVVM_ADMIN_USER:$DEVVM_ADMIN_USER" /work
}

devvm_base
