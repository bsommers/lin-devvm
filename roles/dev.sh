# shellcheck shell=bash
# roles/dev.sh - interactive workstation for DEVVM_ADMIN_USER.
devvm_step "dev: base tools"
case "$DEVVM_GUEST_FAMILY" in
  debian) pkg_install git curl wget tmux htop ripgrep fd-find jq build-essential python3 python3-pip python3-venv unzip ca-certificates nodejs npm ;;
  rhel)   pkg_install git curl wget tmux jq gcc gcc-c++ make python3 python3-pip unzip ca-certificates nodejs npm
          pkg_try fd-find
    # htop/ripgrep live in EPEL on RHEL clones (not Fedora): best effort
    { pkg_try epel-release; pkg_try htop ripgrep; } ;;
  arch)   pkg_install git curl wget tmux htop ripgrep fd jq base-devel python python-pip unzip ca-certificates nodejs npm ;;
  suse)   pkg_install git curl wget tmux htop ripgrep jq gcc gcc-c++ make python3 python3-pip unzip ca-certificates nodejs npm
          pkg_try fd ;;
esac
# Debian ships fd as fdfind
if have fdfind && ! have fd; then ln -sf "$(command -v fdfind)" /usr/local/bin/fd; fi

devvm_step "dev: rust (rustup) for $DEVVM_ADMIN_USER"
if ! sudo -u "$DEVVM_ADMIN_USER" -H bash -lc 'command -v rustup' >/dev/null 2>&1; then
  retry 3 sudo -u "$DEVVM_ADMIN_USER" -H bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal' \
    || devvm_warn "rustup install failed (non-fatal)"
fi

devvm_step "dev: shell niceties"
cat > /etc/profile.d/devvm.sh <<'PROF'
export EDITOR=vim
alias ll='ls -alF'
alias gs='git status -sb'
[ -n "${BASH_VERSION:-}" ] && PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ '
PROF
home="$(getent passwd "$DEVVM_ADMIN_USER" | cut -d: -f6)"
cat > "$home/.tmux.conf" <<'TMUX'
set -g mouse on
set -g history-limit 50000
set -g default-terminal "screen-256color"
TMUX
chown "$DEVVM_ADMIN_USER:$DEVVM_ADMIN_USER" "$home/.tmux.conf"
sudo -u "$DEVVM_ADMIN_USER" git config --global init.defaultBranch main || true
devvm_mount_work
if [[ -d /work ]]; then ln -sfn /work "$home/work"; chown -h "$DEVVM_ADMIN_USER:$DEVVM_ADMIN_USER" "$home/work"; fi
unset home
