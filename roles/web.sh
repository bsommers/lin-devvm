# shellcheck shell=bash
# roles/web.sh - browser IDE (code-server), loopback only; reach it through the SSH tunnel (./vm.sh web).
devvm_step "web: install code-server"
have curl || pkg_install curl
cs_install_tarball() {
  local ver arch url d
  case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; *) return 1 ;; esac
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/coder/code-server/releases/latest)" || return 1
  ver="${url##*/v}"; [[ -n "$ver" ]] || return 1
  d="/usr/local/lib/code-server-$ver"; mkdir -p "$d"
  curl -fsSL "https://github.com/coder/code-server/releases/download/v$ver/code-server-$ver-linux-$arch.tar.gz" \
    | tar -xz --strip-components=1 -C "$d" || return 1
  ln -sf "$d/bin/code-server" /usr/local/bin/code-server
}
if ! have code-server; then
  retry 2 bash -c 'curl -fsSL https://code-server.dev/install.sh | sh' || devvm_warn "install.sh failed; trying release tarball"
fi
have code-server || cs_install_tarball || devvm_warn "code-server tarball install failed"

if have code-server; then
  csbin="$(command -v code-server)"
  # Own unit (overrides any vendor code-server@.service) so the layout is identical on every family.
  cat > /etc/systemd/system/code-server@.service <<UNIT
[Unit]
Description=code-server for %i
After=network.target

[Service]
Type=exec
User=%i
ExecStart=$csbin
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
  cs_config() { # <user> <port>
    local u="$1" p="$2" h
    h="$(getent passwd "$u" | cut -d: -f6)"
    install -d -m 700 -o "$u" -g "$u" "$h/.config" "$h/.config/code-server"
    cat > "$h/.config/code-server/config.yaml" <<CFG
bind-addr: 127.0.0.1:$p
auth: password
password: $DEVVM_WEB_PASS
cert: false
CFG
    chown "$u:$u" "$h/.config/code-server/config.yaml"; chmod 600 "$h/.config/code-server/config.yaml"
  }
  cs_check() { # <port>: wait for listener, assert loopback only
    local p="$1" out
    for _ in $(seq 1 30); do
      out="$(ss -ltnH 2>/dev/null | awk -v s=":$p\$" '$4 ~ s {print $4}')"
      [[ -n "$out" ]] && break; sleep 2
    done
    devvm_step "web: listen check port $p: ${out:-none}"
    [[ -n "$out" ]] || { devvm_warn "code-server not listening on $p"; return 0; }
    if echo "$out" | grep -vqE '^(127\.0\.0\.1|\[::1\]):'; then devvm_fail "code-server port $p not loopback-only: $out"; fi
  }
  # SELinux (fedora/rocky): a lib_t node binary runs as init_t, which may not execmem -> V8 traps. bin_t makes it transition to a service domain.
  if have getenforce && [[ "$(getenforce 2>/dev/null)" == Enforcing ]]; then
    for n in /usr/local/lib/code-server-*/lib/node /usr/lib/code-server/lib/node; do
      [[ -f "$n" ]] && { chcon -t bin_t "$n" || devvm_warn "chcon bin_t $n failed"; }
    done
  fi
  devvm_step "web: configure code-server"
  systemctl daemon-reload
  cs_config "$DEVVM_ADMIN_USER" "$DEVVM_WEB_PORT_GUEST"
  systemctl enable --now "code-server@$DEVVM_ADMIN_USER" || devvm_warn "code-server@$DEVVM_ADMIN_USER failed to start"
  ports="$DEVVM_WEB_PORT_GUEST"
  if [[ "$DEVVM_ROLE" == ai ]]; then
    cs_config "$DEVVM_AGENT_USER" "$((DEVVM_WEB_PORT_GUEST + 1))"
    systemctl enable --now "code-server@$DEVVM_AGENT_USER" || devvm_warn "code-server@$DEVVM_AGENT_USER failed to start"
    ports="$ports $((DEVVM_WEB_PORT_GUEST + 1))"
  fi
  for p in $ports; do cs_check "$p"; done
  mkdir -p /etc/devvm
  {
    echo
    echo "Web IDE (code-server): 127.0.0.1:$DEVVM_WEB_PORT_GUEST as $DEVVM_ADMIN_USER (loopback only, plain password in ~/.config/code-server/config.yaml)."
    [[ "$DEVVM_ROLE" == ai ]] && echo "Agent workspace IDE: 127.0.0.1:$((DEVVM_WEB_PORT_GUEST + 1)) as $DEVVM_AGENT_USER (same password)."
    echo "Reach it from the host with './vm.sh web' (SSH tunnel); it is not exposed on any other interface."
  } >> /etc/devvm/README
else
  devvm_warn "code-server unavailable; web IDE skipped"
fi
