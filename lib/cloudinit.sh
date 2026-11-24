#!/usr/bin/env bash
# lib/cloudinit.sh - NoCloud seed generation. Sourced; no top-level side effects.

# ci_write_user_data <dir> <pubkey-file> <provision-script> <user> [<extra-user>...]
# Every listed user gets the host key; the first is the sudo-capable admin, extras are unprivileged
# (their accounts are finished by the provision script). The provision script runs once as root
# (cloud-init runcmd) and is responsible for writing /var/lib/devvm-state (see guest/common.sh).
ci_write_user_data() {
  local dir="$1" keyf="$2" script="$3" first="$4" key u
  shift 4
  [ -f "$keyf" ] || { echo "pubkey file missing: $keyf" >&2; return 1; }
  [ -f "$script" ] || { echo "provision script missing: $script" >&2; return 1; }
  mkdir -p "$dir" || return 1
  key="$(head -n1 "$keyf")"
  {
    echo "#cloud-config"
    echo "users:"
    echo "  - name: $first"
    echo "    sudo: ALL=(ALL) NOPASSWD:ALL"
    echo "    shell: /bin/bash"
    echo "    lock_passwd: true"
    echo "    ssh_authorized_keys:"
    echo "      - $key"
    for u in "$@"; do
      echo "  - name: $u"
      echo "    shell: /bin/bash"
      echo "    lock_passwd: true"
      echo "    ssh_authorized_keys:"
      echo "      - $key"
    done
    echo "ssh_pwauth: false"
    echo "write_files:"
    echo "  - path: /usr/local/sbin/devvm-provision.sh"
    echo "    permissions: '0700'"
    echo "    encoding: b64"
    echo "    content: $(base64 < "$script" | tr -d '\n')"
    echo "runcmd:"
    echo "  - [ bash, -c, 'bash /usr/local/sbin/devvm-provision.sh >> /var/log/devvm-provision.log 2>&1' ]"
  } > "$dir/user-data"
}

# ci_write_meta_data <dir> <instance-id> <hostname>
ci_write_meta_data() {
  mkdir -p "$1" || return 1
  printf 'instance-id: %s\nlocal-hostname: %s\n' "$2" "$3" > "$1/meta-data"
}

# ci_make_seed <dir> <out.iso>  (only user-data + meta-data are included)
ci_make_seed() {
  local dir="$1" out="$2" stage rc
  command -v xorriso >/dev/null 2>&1 || { echo "xorriso not found" >&2; return 1; }
  stage="$(mktemp -d)" || return 1
  cp "$dir/user-data" "$dir/meta-data" "$stage/" && rm -f "$out" \
    && xorriso -as mkisofs -quiet -J -r -V cidata -o "$out" "$stage" >&2
  rc=$?
  rm -rf "$stage"
  return $rc
}
