# 2. Choosing a guest and role

[← Manual index](README.md) · [← Back to Project README](../../README.md)

## Contents
- [Three knobs](#three-knobs)
- [Guests](#guests)
- [Roles](#roles)
- [Web IDE flag](#web-ide-flag)
- [Sizing and resource variables](#sizing-and-resource-variables)
- [Other environment variables](#other-environment-variables)
- [Recommendations](#recommendations)
- [Pitfalls](#pitfalls)

## Three knobs

```
GUEST=<distro>  ROLE=<dev|ai>  WEB=<0|1>   ./provision.sh
```

`GUEST` selects `guests/<GUEST>/guest.env` (image, family, desktop). `ROLE` selects `roles/<ROLE>.sh`. `WEB=1` appends `roles/web.sh`. Unknown values stop immediately with `unknown GUEST '...'` / `unknown ROLE '...'`. Defaults: `GUEST=ubuntu ROLE=dev WEB=0`.

## Guests

| `GUEST` | Base image | Family | Disk (GB) | Desktop | Live-booted? |
|---|---|---|---|---|---|
| `ubuntu` | Ubuntu 24.04 (noble cloud image) | debian | 20 | no | **yes (ROLE=ai WEB=1 only)** |
| `kubuntu` | Ubuntu 24.04 + `kubuntu-desktop` (KDE, SDDM) | debian | 40 | KDE | no |
| `debian` | Debian 13 genericcloud | debian | 20 | no | no |
| `fedora` | Fedora 45 Cloud Base (`FEDORA_REL`/`FEDORA_BUILD`) | rhel | 20 | no | no |
| `rocky` | Rocky 10 GenericCloud (`ROCKY_REL`) | rhel | 20 | no | no |
| `arch` | Arch Linux cloud image (rolling `latest`) | arch | 20 | no | no |
| `omarchy` | Arch cloud image + upstream Omarchy installer (Hyprland) | arch | 40 | Hyprland | no, best effort |
| `opensuse` | Tumbleweed Minimal-VM Cloud (rolling) | suse | 20 | no | no |

The "family" picks the package manager used inside the guest (apt, dnf, pacman, zypper).

Guest-specific notes:
- **kubuntu**: first provision installs about 1.5 GB of packages and switches to `graphical.target`. Use `./vm.sh view` (needs `virt-viewer`) to see the desktop.
- **omarchy**: there is no Omarchy cloud image. `guests/omarchy/setup.sh` runs upstream's `install.sh` unattended as `dev` and expects 20-40 minutes. It may prompt, expect its ISO disk layout, or reboot; failures are logged as warnings, not fatal. Hyprland without 3D acceleration is slow. Stamp file `/var/lib/devvm-omarchy-done` marks success. The setup script reads `OMARCHY_REPO`, `OMARCHY_REF`, `OMARCHY_USER_NAME`, `OMARCHY_USER_EMAIL`, but `provision.sh` does not forward those into the guest, so the defaults apply (upstream repo, `master`, git identity `dev` / `dev@localhost`).
- **debian**: Debian publishes only `SHA512SUMS`; `lib/images.sh` accepts 128-hex (SHA-512) entries, so verification works (the NOTE in `guests/debian/guest.env` is stale).
- **fedora**: `FEDORA_BUILD` (default `1.4`) must match a published compose for `FEDORA_REL`; if the download 404s, bump it.
- **arch / opensuse**: rolling images, see [checksum mismatch](07-troubleshooting-and-faq.md#image-checksum-mismatch-on-rolling-images).

## Roles

| | `ROLE=dev` (default) | `ROLE=ai` |
|---|---|---|
| Users | `dev` (sudo, NOPASSWD) | `dev` (sudo) + `agent` (no sudo, isolated home) |
| Tools | git, curl, wget, tmux, htop, ripgrep, fd, jq, build tools, python3, nodejs+npm, rustup (for `dev`) | git, curl, wget, tmux, htop, ripgrep, jq, build tools, python3, `gh` (best effort), Node 22 + Claude Code + uv (in `agent`'s home) |
| `/work` data disk | none by default (`DATA_DISK_GB=0`) | 20 GB persistent disk |
| `vm.sh ssh --agent` | not meaningful | works |
| `devvm-agent-run`, `reset` keeping data | n/a | yes |
| Default RAM / vCPU | 8192 MB / 4 | 12288 MB / 6 |

The roles are alternatives, not layers: `ROLE=ai` does not install the `dev` role's rustup or `fd`. Role `dev` also writes `~/.tmux.conf` (mouse on, 50000-line history) and a few shell aliases (`ll`, `gs`) in `/etc/profile.d/devvm.sh`.

Setting `DATA_DISK_GB=<n>` with `ROLE=dev` gives it a persistent `/work` too (symlinked as `~/work`), though `reset` semantics are documented and tested for `ROLE=ai`.

## Web IDE flag

`WEB=1` installs code-server for `dev` (and for `agent` when `ROLE=ai`) bound to guest loopback. See [chapter 4](04-web-ide-over-ssh.md).

## Sizing and resource variables

| Variable | Default | Meaning |
|---|---|---|
| `VM_RAM_MB` | 12288 (ai), 8192 (dev) | guest RAM. For desktop guests (`kubuntu`, `omarchy`) it is forced to `VM_RAM_MB_DESKTOP` (default 8192), even for `ROLE=ai` |
| `VM_VCPUS` | 6 (ai), 4 (dev) | vCPUs |
| `VM_DISK_GB` | per-guest `GUEST_DISK_GB` (20, or 40 for desktops) | virtual size of the system overlay |
| `DATA_DISK_GB` | 0 (dev), 20 (ai) | persistent `/work` disk; 0 means none |
| `VM_NAME` | `lin-$GUEST-$ROLE` | libvirt domain and state-dir name |
| `VM_DIR` | `~/vms/$VM_NAME` | per-VM state |
| `ADMIN_USER` / `AGENT_USER` | `dev` / `agent` | usernames (fixed at provision time) |
| `SSH_KEY` | `~/.ssh/id_lindevvm` | host key pair |
| `SSH_PORT` | `2300 + slot` | host loopback port forwarded to guest 22 |
| `WEB_PORT` | `18080 + slot` | host loopback tunnel port for `vm.sh web` |
| `WEB_PORT_GUEST` | 8080 | code-server port inside the guest |
| `WEB_PASS` | `devvm` | web IDE password |
| `LIBVIRT_URI` | `qemu:///session` | libvirt connection |
| `IMAGE_CACHE` | `~/.cache/lin-devvm/images` | image cache |
| `IMAGE_URL`, `IMAGE_FILE`, `IMAGE_SUMS`, `OS_VARIANT` | per guest | override the image source; `IMAGE_SUMS` may be `sha256:<hex>` |
| `IMAGE_OFFLINE` | 0 | `1`: never use the network for images; fail if not cached |
| `UEFI_BOOT` | `uefi` | value passed to `virt-install --boot` |
| `WAIT_TIMEOUT` | 3600 | seconds `vm.sh wait` polls |
| `HV_DRYRUN` | unset | `1`: print the `virt-install` argv instead of running it (`hv_run`) |

`slot` is `cksum(VM_NAME) % 899`, so each VM name has stable, distinct-in-practice ports. Example: `lin-ubuntu-ai` gives SSH 2432, web 18212 (agent IDE 19212); `lin-fedora-dev` gives SSH 2671, web 18451. Print yours with:

```
GUEST=fedora ROLE=dev bash -c 'source ./config.env; echo "$VM_NAME ssh=$SSH_PORT web=$WEB_PORT dir=$VM_DIR"'
lin-fedora-dev ssh=2671 web=18451 dir=/home/<you>/vms/lin-fedora-dev
```

## Recommendations

- Want the tested path: `GUEST=ubuntu ROLE=ai WEB=1`.
- Want unattended agents: `ROLE=ai` (isolation + persistent `/work` + reset recovery).
- Want a plain interactive box: `ROLE=dev`.
- Want a desktop: `kubuntu` first; `omarchy` only if you accept a possibly half-finished install.
- Trying an untested guest: use a throwaway `VM_NAME` and `./vm.sh wait` plus the log (chapter 7) so a failure costs nothing.

## Pitfalls

- Changing `GUEST`, `ROLE`, `WEB`, or `VM_NAME` between commands addresses a different VM.
- Resource variables only take effect at (re)provision time; they are baked into the libvirt domain.
- `SSH_PORT` is baked into the domain too; setting a different `SSH_PORT` later makes `vm.sh` dial the wrong port.
- `ADMIN_USER`/`AGENT_USER` must also be identical on later `vm.sh` calls (they select the SSH login).
