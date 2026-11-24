# shellcheck shell=bash
# Helpers shared by provision.sh, vm.sh and the backend.

# Escape a value for use as a sed replacement with the | delimiter.
esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

# Stable small integer (0..898) derived from a VM name, so several VMs never collide on ports/MACs.
vm_slot() { echo $(( $(printf '%s' "$1" | cksum | cut -d' ' -f1) % 899 )); }

# Locally administered MAC for QEMU's user-mode NIC.
vm_mac() {
  local s h; s="$(vm_slot "$1")"; h=$(( $(printf '%s' "$1" | cksum | cut -d' ' -f1) % 256 ))
  printf '52:54:00:%02x:%02x:%02x' $((s % 256)) $((s / 256)) "$h"
}
