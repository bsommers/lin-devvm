# shellcheck shell=bash
# libvirt/KVM backend (rootless qemu:///session). Sourced by provision.sh / vm.sh.
V() { virsh -c "$LIBVIRT_URI" "$@"; }
hv_run() { if [[ -n "${HV_DRYRUN:-}" ]]; then printf '%s\n' "$@"; else "$@"; fi; }   # HV_DRYRUN=1: print argv, don't run

hv_check() {
  local f
  for f in virt-install virsh xorriso qemu-img curl ssh-keygen; do
    command -v "$f" >/dev/null || { echo "missing tool: $f" >&2; exit 1; }
  done
  [[ -r /dev/kvm && -w /dev/kvm ]] || { echo "/dev/kvm not accessible" >&2; exit 1; }
}

hv_exists() { V dominfo "$VM_NAME" >/dev/null 2>&1; }

hv_destroy() {
  V destroy "$VM_NAME" 2>/dev/null || true
  V undefine "$VM_NAME" --nvram 2>/dev/null || V undefine "$VM_NAME" 2>/dev/null || true
}

# $1 = staged dir (user-data, meta-data). KEEP_DATA=1 keeps an existing data disk.
hv_create() {
  local vi base disks=() fwd="hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
  # shellcheck source=/dev/null
  source "$HERE/lib/images.sh"; source "$HERE/lib/cloudinit.sh"
  base="$(image_fetch "$IMAGE_URL" "$IMAGE_FILE" "$IMAGE_SUMS")" || { echo "image fetch failed" >&2; exit 1; }
  image_overlay "$base" "$VM_DIR/disk.qcow2" "$VM_DISK_GB"
  ci_make_seed "$1" "$VM_DIR/seed.iso"
  disks=(--disk "path=$VM_DIR/disk.qcow2,bus=virtio,cache=none,discard=unmap,boot.order=1"
         --disk "path=$VM_DIR/seed.iso,device=cdrom,bus=sata")
  if (( DATA_DISK_GB > 0 )); then
    [[ -f "$VM_DIR/data.qcow2" ]] || qemu-img create -q -f qcow2 "$VM_DIR/data.qcow2" "${DATA_DISK_GB}G"
    disks+=(--disk "path=$VM_DIR/data.qcow2,bus=virtio,cache=none,discard=unmap,serial=devvm-data")
  fi
  vi=("$(command -v virt-install)")
  [[ -x /usr/bin/python3 ]] && vi=(/usr/bin/python3 "${vi[0]}")   # system python (gi bindings)
  hv_run "${vi[@]}" --connect "$LIBVIRT_URI" \
    --name "$VM_NAME" --osinfo "$OS_VARIANT" \
    --memory "$VM_RAM_MB" --vcpus "$VM_VCPUS" --cpu host-passthrough \
    --boot "${UEFI_BOOT:-uefi}" --import \
    "${disks[@]}" \
    --network none \
    --qemu-commandline="-netdev user,id=n0,$fwd -device virtio-net-pci,netdev=n0,mac=$VM_MAC,bus=pcie.0,addr=0x1e" \
    --graphics vnc,listen=127.0.0.1 --video virtio \
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --noautoconsole --wait 0
}

hv_start() { V start "$VM_NAME"; }
hv_stop()  { V shutdown "$VM_NAME"; }
hv_kill()  { V destroy "$VM_NAME"; }
hv_state() { V domstate "$VM_NAME"; }
hv_view()  { exec virt-viewer -c "$LIBVIRT_URI" "$VM_NAME"; }
hv_ssh_dest() { echo "127.0.0.1 $SSH_PORT"; }   # "<host> <port>"
hv_info() {
  cat <<MSG
  screen   : ./vm.sh view          (virt-viewer) or VNC: $(V domdisplay "$VM_NAME" 2>/dev/null || echo see 'virsh domdisplay')
  ssh      : ./vm.sh ssh           (127.0.0.1:$SSH_PORT -> guest:22; ./vm.sh ssh --agent for the agent user)
MSG
  [[ "$WEB" == 1 ]] && echo "  web IDE  : ./vm.sh web           (SSH tunnel -> http://127.0.0.1:$WEB_PORT, password: \$WEB_PASS)"
  return 0
}
