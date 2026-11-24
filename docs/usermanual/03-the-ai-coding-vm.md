# 3. The AI-coding VM

[← Manual index](README.md) · [← Back to Project README](../../README.md)

## Contents
- [Design in one paragraph](#design-in-one-paragraph)
- [Two users](#two-users)
- [The /work layout](#the-work-layout)
- [What is preinstalled](#what-is-preinstalled)
- [Running Claude Code](#running-claude-code)
- [devvm-agent-run](#devvm-agent-run)
- [tmux sessions](#tmux-sessions)
- [Getting files in and out](#getting-files-in-and-out)
- [Reset recovery](#reset-recovery)
- [Optional systemd hardening unit](#optional-systemd-hardening-unit)
- [Pitfalls](#pitfalls)

Status: verified live only on `GUEST=ubuntu ROLE=ai WEB=1` (provision, user isolation, `reset` keeping `/work`). Other guests use the same scripts per distro family but are unbooted.

## Design in one paragraph

`ROLE=ai` makes a VM you can let an agent run wild in: an unprivileged `agent` user does the unattended work, you use the sudo-capable `dev` user for interactive work, and a separate persistent disk (`/work`) carries the real work product. If the system gets gummed up, `./vm.sh reset` rebuilds the system disk from the cloud image and leaves `/work` alone.

## Two users

| | `dev` (`ADMIN_USER`) | `agent` (`AGENT_USER`) |
|---|---|---|
| Purpose | you, interactive | unattended agents |
| sudo | yes, passwordless | no (removed from `sudo`/`wheel`, no sudoers file) |
| Home | `/home/dev`, mode 750 | `/home/agent`, mode 750 |
| Workspace | `/work/interactive` (`~/work`) | `/work/agent` (`~/work`) |
| Login | `./vm.sh ssh` | `./vm.sh ssh --agent` |
| Web IDE (if `WEB=1`) | guest port 8080 | guest port 8081 |

Both accounts have password login locked and the same host key authorised. `agent` is not in `dev`'s primary group, so it cannot read `dev`'s home. This is account-level isolation inside one VM, not a hard security boundary: both share a kernel, and `agent` has outbound network access.

## The /work layout

```
/work                  755, owned by dev   (ext4, label "work", fstab "nofail")
├── agent/             750, agent:agent    <- /home/agent/work symlink
└── interactive/       750, dev:dev        <- /home/dev/work symlink
```

`/work` lives on `data.qcow2` (`DATA_DISK_GB`, default 20), exposed to the guest with serial `devvm-data` (`/dev/disk/by-id/virtio-devvm-data`). It is formatted only if no filesystem is found. If the disk does not show up in 30 s, provisioning warns `data disk ... not found; skipping /work` and carries on.

Neither user can read the other's workspace (both 750). To hand `agent` something `dev` prepared, copy with sudo:

```
dev$   sudo cp -a ~/work/myrepo /work/agent/ && sudo chown -R agent:agent /work/agent/myrepo
```

## What is preinstalled

In `agent`'s home (via `~/.devvm-env`, sourced from `.profile` and `.bashrc`): Node.js v22 LTS tarball under `~/.local/node` (falls back to distro `nodejs`/`npm` if the tarball fails), `npm` prefix `~/.npm-global`, `@anthropic-ai/claude-code`, `uv`, `git config init.defaultBranch main`. System-wide: git, curl, wget, tmux, htop, ripgrep, jq, build tools, python3/pip, and `gh` (best effort: a warning `gh not available from distro repos` is non-fatal). Lingering is enabled for `agent` so its user-systemd and tmux survive logout. `/etc/devvm/README` in the guest summarises this.

Install steps for Node, Claude Code and uv are non-fatal on failure (a `[devvm WARN]` line in the log). If one failed, install it by hand as `agent`.

## Running Claude Code

```
$ ./vm.sh ssh --agent
agent$ claude --version        # PATH comes from ~/.devvm-env
agent$ cd ~/work && git clone <repo> && cd <repo>
agent$ tmux new -s claude      # keep it alive after you disconnect
agent$ claude                  # first run asks you to authenticate
```

Authentication is Claude Code's own interactive flow; lin-devvm does not store or inject credentials. The login lives in `agent`'s home on the system disk, so a `reset` removes it (re-authenticate afterwards).

One-shot commands over SSH do not start a login shell; if `claude` is not found, wrap it:

```
$ ./vm.sh ssh --agent 'bash -lc "claude --version"'
```

## devvm-agent-run

`/usr/local/bin/devvm-agent-run [-n name] [-m memmax] [-c cpuquota] -- command...` runs a command as `agent` in a detached tmux session, inside a resource-limited user scope.

| Option | Default | Meaning |
|---|---|---|
| `-n name` | `agent-HHMMSS` | tmux session name |
| `-m memmax` | `8G` | systemd `MemoryMax` |
| `-c cpuquota` | `400%` | systemd `CPUQuota` (400% = 4 cores) |

It can be run from either user; as `dev` it re-executes itself via `sudo -n -u agent`. It works in `/work/agent` (falls back to the agent's home), and runs the command through `bash -lc`.

```
dev$ devvm-agent-run -n refactor -m 6G -c 300% -- claude -p "refactor module X"
started tmux session 'refactor' as agent (attach: sudo -u agent tmux attach -t refactor)
```

Limits use `systemd-run --user --scope`; if that is unavailable it prints `warn: systemd-run --user unavailable; running without limits` and runs unlimited. Without `--` and a command it prints the usage line and exits 2. Remote one-liner from the host:

```
$ ./vm.sh ssh 'devvm-agent-run -n job1 -- sleep 600'
```

## tmux sessions

```
dev$ sudo -u agent tmux ls                       # list agent sessions
dev$ sudo -u agent tmux attach -t refactor       # attach (Ctrl-b d to detach)
agent$ tmux ls                                   # same, when logged in as agent
```

Sessions survive SSH disconnects (linger). They do not survive a VM reboot, `stop`, `rollback` or `reset`. The `ai` role does not write a `.tmux.conf` (only `ROLE=dev` does), so tmux uses its defaults.

## Getting files in and out

`./vm.sh push` and `pull` copy as `dev` only (see [chapter 5](05-daily-operations.md#file-transfer)). For the agent, push into `/work/interactive` and then `sudo cp`/`chown` into `/work/agent`, or use git (`gh` and `git` are installed for `agent`).

## Reset recovery

When the system is broken (bad package state, full root disk, agent trashed its environment):

```
$ GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh reset      # same env as provisioning
$ GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh wait
```

`reset` runs `provision.sh --reset`: it destroys and undefines the domain, deletes `disk.qcow2`, `seed.iso` and `known_hosts`, then reprovisions from the cached cloud image, reusing the untouched `data.qcow2`.

| Kept | Lost |
|---|---|
| everything under `/work` (both workspaces) | everything outside `/work`: both home directories (Claude login, `~/.npm-global`, dotfiles), installed packages, tmux sessions |
| the host key and `VM_DIR` | checkpoints (they live in the deleted `disk.qcow2`) |

Keep `WEB`, `ROLE`, `GUEST`, `VM_NAME` the same on reset, or you will rebuild a differently configured system. Expect a full provisioning cycle again. File ownership on `/work/agent` is by uid; cloud-init recreates the users in the same order, so uids normally match, but check `ls -ln /work/agent` after a reset if you changed users.

`./vm.sh destroy` and `provision.sh --force`, by contrast, delete `VM_DIR` including `data.qcow2`.

## Optional systemd hardening unit

`/etc/devvm/devvm-agent@.service.example` is a template, **not enabled**: a unit that starts a tmux session as `%i` with `MemoryMax=8G`, `CPUQuota=400%`, `TasksMax=2048`, `ProtectSystem=strict`, `ReadWritePaths=/work/%i /home/%i`, `InaccessiblePaths=` the dev home, `PrivateTmp`, `NoNewPrivileges`. To use it, copy it to `/etc/systemd/system/devvm-agent@.service` and `sudo systemctl enable --now devvm-agent@agent`. It is untested; the `WorkingDirectory=/work/%i` assumes the unit instance name equals the workspace directory name (`agent`).

## Pitfalls

- `reset` wipes homes: keep anything valuable (repos, notes) under `/work`, and push code to a git remote.
- `agent` cannot `sudo`; install system packages as `dev`.
- A command under `devvm-agent-run` that outgrows `-m` is killed by the kernel/systemd; look at `dmesg` or rerun with a bigger limit.
- `reset` and `rollback` stop whatever the agent was running.
- Do not store secrets you care about in a VM whose purpose is to run an untrusted agent.
