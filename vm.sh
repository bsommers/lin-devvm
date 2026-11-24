#!/usr/bin/env bash
# Day-2 helper. Select the VM with the same GUEST/ROLE/VM_NAME env used at provision time.
#   ./vm.sh {start|stop|kill|status|wait|view|ip|ssh [--agent] [cmd...]|web|push|pull|checkpoint|rollback|reset|list|destroy}
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/config.env"
# shellcheck source=/dev/null
source "$HERE/lib/libvirt.sh"

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$VM_DIR/known_hosts" -o LogLevel=ERROR)
dest() { read -r SSH_HOST SSH_PORT_ < <(hv_ssh_dest); }
guest_ssh() { dest; ssh "${SSH_OPTS[@]}" -p "$SSH_PORT_" "$ADMIN_USER@$SSH_HOST" "$@"; }
state() { guest_ssh -o BatchMode=yes -o ConnectTimeout=3 'cat /var/lib/devvm-state 2>/dev/null || echo "installing"' 2>/dev/null; }

case "${1:-status}" in
  start)   hv_start ;;
  stop)    hv_stop ;;
  kill)    hv_kill ;;
  view)    hv_view ;;
  ip)      read -r h _ < <(hv_ssh_dest); echo "$h" ;;
  ssh)     shift; user="$ADMIN_USER"
           if [[ "${1:-}" == --agent ]]; then user="$AGENT_USER"; shift; fi
           dest; exec ssh "${SSH_OPTS[@]}" -p "$SSH_PORT_" "$user@$SSH_HOST" "$@" ;;
  web)     # SSH tunnel to the guest browser IDE(s); nothing is exposed beyond 127.0.0.1. Ctrl-C closes it.
           dest; fwd=(-L "127.0.0.1:$WEB_PORT:127.0.0.1:$WEB_PORT_GUEST")
           echo "web IDE (admin $ADMIN_USER): http://127.0.0.1:$WEB_PORT  (password: $WEB_PASS)"
           if [[ "$ROLE" == ai ]]; then
             fwd+=(-L "127.0.0.1:$((WEB_PORT + 1000)):127.0.0.1:$((WEB_PORT_GUEST + 1))")
             echo "web IDE (agent $AGENT_USER): http://127.0.0.1:$((WEB_PORT + 1000))  (password: $WEB_PASS)"
           fi
           echo "tunnel open, Ctrl-C to close"
           exec ssh "${SSH_OPTS[@]}" -p "$SSH_PORT_" -N "${fwd[@]}" "$ADMIN_USER@$SSH_HOST" ;;
  push)    [[ $# -eq 3 ]] || { echo "usage: vm.sh push <local> <remote>" >&2; exit 2; }
           dest; scp -q "${SSH_OPTS[@]}" -P "$SSH_PORT_" -r "$2" "$ADMIN_USER@$SSH_HOST:$3" ;;
  pull)    [[ $# -eq 3 ]] || { echo "usage: vm.sh pull <remote> <local>" >&2; exit 2; }
           dest; scp -q "${SSH_OPTS[@]}" -P "$SSH_PORT_" -r "$ADMIN_USER@$SSH_HOST:$2" "$3" ;;
  status)  hv_state; echo "guest: $(state || echo 'ssh not reachable yet')" ;;
  wait)    end=$(( $(date +%s) + ${WAIT_TIMEOUT:-3600} ))
           while (( $(date +%s) < end )); do
             s="$(state || true)"
             case "$s" in DONE*) echo "guest: $s"; exit 0 ;; FAILED*) echo "guest: $s"; exit 1 ;; esac
             sleep 10
           done; echo "timeout waiting for provisioning" >&2; exit 1 ;;
  checkpoint) # offline qcow2 internal snapshot of the system disk: ./vm.sh checkpoint [name]
           hv_kill 2>/dev/null || true; qemu-img snapshot -c "${2:-checkpoint}" "$VM_DIR/disk.qcow2"; echo "checkpoint '${2:-checkpoint}' saved (VM is stopped; ./vm.sh start)" ;;
  rollback) hv_kill 2>/dev/null || true; qemu-img snapshot -a "${2:-checkpoint}" "$VM_DIR/disk.qcow2"; echo "rolled back to '${2:-checkpoint}' (./vm.sh start)" ;;
  reset)   # worst case: rebuild the system disk from the cloud image, keep /work (data disk)
           exec "$HERE/provision.sh" --reset ;;
  list)    V list --all | grep -E 'Name|lin-' || true ;;
  destroy) read -rp "Delete VM $VM_NAME and $VM_DIR (including /work data)? [y/N] " a; [[ $a == y ]] || exit 1
           hv_destroy; rm -rf "$VM_DIR" ;;
  *) sed -n 3p "$0"; exit 2 ;;
esac
