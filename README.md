# lin-devvm

Unattended **Linux dev VMs** on a Linux host: rootless KVM via libvirt, vendor cloud images + cloud-init, everything reachable **only over SSH** (ports bound to `127.0.0.1`). Sibling of [win-devvm](../win-devvm).

| `GUEST` | Base | Notes |
|---|---|---|
| `ubuntu` | Ubuntu 24.04 | default |
| `kubuntu` | Ubuntu 24.04 + `kubuntu-desktop` | KDE Plasma (`./vm.sh view`) |
| `debian` | Debian 13 | genericcloud |
| `fedora` | Fedora 45 | |
| `arch` | Arch Linux | rolling image |
| `omarchy` | Arch + Omarchy installer | best effort, Hyprland; see `guests/omarchy/setup.sh` |
| `opensuse` | Tumbleweed | |
| `rocky` | Rocky 10 | |

## Roles
- `ROLE=dev` (default): interactive workstation (`dev` user, sudo, toolchains).
- `ROLE=ai`: **dedicated AI-coding VM**. Separate unprivileged `agent` user (no sudo, can't read `dev`'s home) runs unattended agents; `dev` is for interactive work. Node + Claude Code, tmux, gh, uv preinstalled; `devvm-agent-run` starts resource-limited agent sessions. `/work` is a persistent data disk, so if the VM gets gummed up, `./vm.sh reset` rebuilds the system disk from the cloud image and keeps `/work`.
- `WEB=1`: also install a browser IDE (code-server) bound to guest loopback with a **plain password** (`WEB_PASS`, default `devvm`). It is reached only through an SSH tunnel: `./vm.sh web` -> `http://127.0.0.1:<WEB_PORT>` (a second instance for `agent` at +1000 in the ai role).

## Quickstart
```
GUEST=fedora ROLE=ai WEB=1 ./provision.sh
GUEST=fedora ROLE=ai WEB=1 ./vm.sh wait
GUEST=fedora ROLE=ai ./vm.sh ssh            # interactive user
GUEST=fedora ROLE=ai ./vm.sh ssh --agent    # unattended-agent user
GUEST=fedora ROLE=ai WEB=1 ./vm.sh web      # tunnel to the browser IDE
```
Use the same `GUEST/ROLE/VM_NAME` env for `vm.sh` as for `provision.sh` (VM name defaults to `lin-$GUEST-$ROLE`; ports derive from it so VMs coexist).

## vm.sh
`start stop kill status wait view ip ssh [--agent] web push pull checkpoint [name] rollback [name] reset list destroy`. `provision.sh --force` recreates everything; `--reset` keeps the data disk.

## Layout
`config.env` defaults · `provision.sh`/`vm.sh` · `lib/` (libvirt, cloud-init seed, image cache with sha256/sha512 verification) · `guest/common.sh` (in-guest helpers, state file `/var/lib/devvm-state`) · `guests/<name>/guest.env` (+`setup.sh`) · `roles/{dev,ai,web}.sh` · `tools/` + `.tracker/` (local progress page) · `tests/`.

## Tracker
`tools/track.sh serve` -> http://127.0.0.1:4790 : plan, event feed, guest list, live `lin-*` VM state, test results.

## Security notes
Lab use. The default web password is public in this repo; override `WEB_PASS`. Nothing listens beyond `127.0.0.1` on the host; SSH is key-only (key `~/.ssh/id_lindevvm`). Omarchy/KDE guests are slow without 3D acceleration.
## Tests
`tests/run.sh` (syntax, shellcheck, guest contract, script composition, tracker). Live-validated: Ubuntu 24.04 `ROLE=ai WEB=1` provision, user isolation, web login over tunnel, `reset` preserving `/work`.
