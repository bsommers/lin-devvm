#!/usr/bin/env bash
# Provision and boot a Linux dev VM (libvirt/KVM, rootless) from a vendor cloud image.
# Usage: GUEST=fedora ROLE=ai WEB=1 ./provision.sh [--force | --reset]
#   --force  destroy the existing VM and its state, recreate
#   --reset  rebuild only the system disk; keeps the persistent data disk (/work) of ROLE=ai VMs
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.env"
# shellcheck source=/dev/null
source "$HERE/lib/libvirt.sh"
MODE="${1:-}"
tracker() { "$HERE/tools/track.sh" "$@" 2>/dev/null || true; }

hv_check
if hv_exists; then
  case "$MODE" in
    --force) hv_destroy; rm -rf "$VM_DIR" ;;
    --reset) hv_destroy; rm -f "$VM_DIR/disk.qcow2" "$VM_DIR/seed.iso" "$VM_DIR/known_hosts" ;;
    *) echo "VM $VM_NAME exists (use --force to recreate, --reset to rebuild the system disk)" >&2; exit 1 ;;
  esac
fi
mkdir -p "$VM_DIR"; chmod 700 "$VM_DIR"

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
[[ -f "$SSH_KEY" ]] || ssh-keygen -q -t ed25519 -N "" -C "lin-devvm" -f "$SSH_KEY"

# Compose the in-guest provision script: env header + guest/common.sh + guest setup + role (+ web IDE).
{
  echo '#!/usr/bin/env bash'
  for v in GUEST GUEST_FAMILY ROLE WEB ADMIN_USER AGENT_USER WEB_PASS WEB_PORT_GUEST DESKTOP DESKTOP_ENV DATA_DISK_GB VM_NAME; do
    printf 'export DEVVM_%s=%q\n' "$v" "${!v:-}"
  done
  cat "$HERE/guest/common.sh"
  [[ -r "$HERE/guests/$GUEST/setup.sh" ]] && cat "$HERE/guests/$GUEST/setup.sh"
  cat "$HERE/roles/$ROLE.sh"
  [[ "$WEB" == 1 ]] && cat "$HERE/roles/web.sh"
  echo 'devvm_finish'
} > "$STAGE/provision-guest.sh"
bash -n "$STAGE/provision-guest.sh"

users=()
[[ "$ROLE" == ai ]] && users=("$AGENT_USER")
ci_users() { source "$HERE/lib/cloudinit.sh"; ci_write_user_data "$STAGE" "$SSH_KEY.pub" "$STAGE/provision-guest.sh" "$ADMIN_USER" "${users[@]+"${users[@]}"}"; ci_write_meta_data "$STAGE" "$VM_NAME-$(date +%s)" "$VM_NAME"; }
ci_users

tracker event provision start "$VM_NAME ($GUEST/$ROLE)"
hv_create "$STAGE"
tracker event provision created "$VM_NAME"

cat <<MSG

VM '$VM_NAME' started ($GUEST_LABEL, role=$ROLE, web=$WEB). $GUEST_BANNER
  progress : ./vm.sh status   ./vm.sh wait      (guest state in /var/lib/devvm-state)
$(hv_info)
MSG
