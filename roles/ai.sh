# shellcheck shell=bash
# roles/ai.sh - dedicated AI-coding VM: unprivileged agent user + interactive admin, /work data disk.
A="$DEVVM_ADMIN_USER"; G="$DEVVM_AGENT_USER"

devvm_step "ai: base tools"
case "$DEVVM_GUEST_FAMILY" in
  debian) pkg_install git curl wget tmux htop ripgrep jq build-essential python3 python3-pip python3-venv unzip xz-utils ca-certificates sudo ;;
  rhel)   pkg_install git curl wget tmux jq gcc gcc-c++ make python3 python3-pip unzip xz ca-certificates sudo
    # htop/ripgrep live in EPEL on RHEL clones (not Fedora): best effort
    { pkg_try epel-release; pkg_try htop ripgrep; } ;;
  arch)   pkg_install git curl wget tmux htop ripgrep jq base-devel python python-pip unzip xz ca-certificates sudo ;;
  suse)   pkg_install git curl wget tmux htop ripgrep jq gcc gcc-c++ make python3 python3-pip unzip xz ca-certificates sudo ;;
esac
case "$DEVVM_GUEST_FAMILY" in
  arch) pkg_try github-cli ;;
  *)    pkg_try gh ;;
esac
have gh || devvm_warn "gh not available from distro repos; install it manually if needed"

devvm_step "ai: users and home isolation"
id "$G" >/dev/null 2>&1 || useradd -m -s /bin/bash "$G"
gh_="$(getent passwd "$G" | cut -d: -f6)"; ah_="$(getent passwd "$A" | cut -d: -f6)"
for u in "$A" "$G"; do gpasswd -d "$u" sudo >/dev/null 2>&1 || true; done
gpasswd -d "$G" wheel >/dev/null 2>&1 || true
rm -f "/etc/sudoers.d/$G" 2>/dev/null || true
chmod 750 "$ah_" "$gh_"
# agent must not be able to read admin's home: ensure it is not in admin's primary group
gpasswd -d "$G" "$A" >/dev/null 2>&1 || true
chown "$G:$G" "$gh_"

devvm_mount_work
if mountpoint -q /work; then
  mkdir -p /work/agent /work/interactive
  chown "$G:$G" /work/agent; chown "$A:$A" /work/interactive
  chmod 750 /work/agent /work/interactive; chmod 755 /work
  ln -sfn /work/agent "$gh_/work"; chown -h "$G:$G" "$gh_/work"
  ln -sfn /work/interactive "$ah_/work"; chown -h "$A:$A" "$ah_/work"
fi

devvm_step "ai: node LTS + npm prefix for $G"
as_agent() { sudo -u "$G" -H bash -c "$*"; }
arch_="$(uname -m)"; case "$arch_" in x86_64) narch=x64 ;; aarch64) narch=arm64 ;; *) narch="" ;; esac
if [[ -n "$narch" ]]; then
  nbase="https://nodejs.org/dist/latest-v22.x"
  nfile="$(curl -fsSL "$nbase/SHASUMS256.txt" 2>/dev/null | awk -v a="linux-$narch.tar.xz" '$2 ~ a"$" {print $2; exit}')"
  if [[ -n "$nfile" ]]; then
    as_agent "mkdir -p ~/.local/node ~/.npm-global && curl -fsSL '$nbase/$nfile' | tar -xJ --strip-components=1 -C ~/.local/node" \
      || devvm_warn "node tarball install failed"
  else
    devvm_warn "could not resolve node LTS tarball"
  fi
fi
if [[ ! -x "$gh_/.local/node/bin/node" ]]; then
  devvm_warn "falling back to distro nodejs"
  case "$DEVVM_GUEST_FAMILY" in arch) pkg_try nodejs npm ;; *) pkg_try nodejs npm ;; esac
fi
cat > "$gh_/.devvm-env" <<'ENVF'
export PATH="$HOME/.local/bin:$HOME/.local/node/bin:$HOME/.npm-global/bin:$PATH"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
ENVF
for f in .profile .bashrc; do
  # shellcheck disable=SC2016
  grep -q devvm-env "$gh_/$f" 2>/dev/null || echo '[ -f "$HOME/.devvm-env" ] && . "$HOME/.devvm-env"' >> "$gh_/$f"
done
chown "$G:$G" "$gh_/.devvm-env" "$gh_/.profile" "$gh_/.bashrc"

devvm_step "ai: claude-code and uv for $G"
as_agent '. ~/.devvm-env; command -v npm >/dev/null && npm install -g @anthropic-ai/claude-code' \
  || devvm_warn "npm install @anthropic-ai/claude-code failed (install later as $G)"
as_agent '. ~/.devvm-env; curl -fsSL https://astral.sh/uv/install.sh | sh' || devvm_warn "uv install failed"
as_agent 'git config --global init.defaultBranch main' || true

devvm_step "ai: linger + hardening example + wrapper"
loginctl enable-linger "$G" || devvm_warn "enable-linger failed"
mkdir -p /etc/devvm
cat > /etc/devvm/devvm-agent@.service.example <<UNIT
# Example only (NOT enabled). Copy to /etc/systemd/system/devvm-agent@.service, then:
#   systemctl enable --now devvm-agent@$G
[Unit]
Description=Resource-limited agent tmux session for %i
After=network-online.target

[Service]
Type=forking
User=%i
WorkingDirectory=/work/%i
ExecStart=/usr/bin/tmux new-session -d -s agent
ExecStop=/usr/bin/tmux kill-server
MemoryMax=8G
CPUQuota=400%
TasksMax=2048
ProtectSystem=strict
ReadWritePaths=/work/%i /home/%i
InaccessiblePaths=$ah_
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT
cat > /usr/local/bin/devvm-agent-run <<'WRAP'
#!/usr/bin/env bash
# devvm-agent-run [-n session] [-m memmax] [-c cpuquota] -- command...
# Runs command as the agent user inside a detached tmux session, in a resource-limited systemd scope.
set -u
AGENT="${DEVVM_AGENT_USER:-__AGENT__}"
name="agent-$(date +%H%M%S)"; mem=8G; cpu=400%
while getopts n:m:c: o; do case $o in n) name=$OPTARG ;; m) mem=$OPTARG ;; c) cpu=$OPTARG ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1)); [[ "${1:-}" == -- ]] && shift
[[ $# -gt 0 ]] || { echo "usage: devvm-agent-run [-n name] [-m 8G] [-c 400%] -- cmd..." >&2; exit 2; }
if [[ "$(id -un)" != "$AGENT" ]]; then exec sudo -n -u "$AGENT" -H "$0" -n "$name" -m "$mem" -c "$cpu" -- "$@"; fi
cd /work/agent 2>/dev/null || cd "$HOME" || exit 1
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
cmd="$(printf '%q ' "$@")"
tm=(tmux new-session -d -s "$name" "bash -lc $(printf '%q' "$cmd")")
if systemd-run --user --scope -q -p "MemoryMax=$mem" -p "CPUQuota=$cpu" -- "${tm[@]}" 2>/dev/null; then :
else echo "warn: systemd-run --user unavailable; running without limits" >&2; "${tm[@]}"; fi
echo "started tmux session '$name' as $AGENT (attach: sudo -u $AGENT tmux attach -t $name)"
WRAP
sed -i "s/__AGENT__/$G/" /usr/local/bin/devvm-agent-run
chmod 755 /usr/local/bin/devvm-agent-run

devvm_step "ai: README"
cat > /etc/devvm/README <<README
lin-devvm AI-coding VM ($DEVVM_VM_NAME)
=======================================
Two users, deliberately separate:
  $A  interactive human user, sudo, home /home/$A, workspace /work/interactive
  $G  unprivileged agent user (no sudo), runs unattended agents, workspace /work/agent
Homes are mode 750; $G cannot read $A's home.
Agent tools (in $G's home): node LTS, claude-code, uv, git, gh, tmux, ripgrep, python3.
Lingering is enabled for $G, so tmux sessions survive logout.
  ./vm.sh ssh --agent                      log in as $G
  devvm-agent-run -n job -- claude         run a command as $G in tmux with MemoryMax/CPUQuota
  /etc/devvm/devvm-agent@.service.example  systemd-hardened (ProtectSystem=strict) example, not enabled
/work is a separate persistent data disk. If the VM gets gummed up, run './vm.sh reset' on the host:
it rebuilds the system disk and keeps /work (and everything in /work/agent, /work/interactive).
Provisioning log: /var/log/devvm-provision.log, state: /var/lib/devvm-state
README
chmod 644 /etc/devvm/README
unset A G gh_ ah_ arch_ narch nbase nfile
