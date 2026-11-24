# Running

## Contents

- [Prerequisites](#prerequisites)
- [Configuration reference](#configuration-reference)
- [provision.sh](#provisionsh)
- [vm.sh](#vmsh)
- [tools/track.sh](#toolstracksh)
- [Files, directories and ports](#files-directories-and-ports)
- [Per-guest table](#per-guest-table)
- [Image checksums and refresh](#image-checksums-and-refresh)
- [Exit codes](#exit-codes)
- [Validation status](#validation-status)

## Prerequisites

Host: Linux with KVM. `provision.sh` checks (`hv_check`) for these commands and for read/write access to
`/dev/kvm`:

`virt-install virsh xorriso qemu-img curl ssh-keygen`

Also used: `ssh`, `scp` (`vm.sh`), `virt-viewer` (`vm.sh view`), `xz` (only if an image name ends in
`.xz`; none of the shipped guests do), `node` (tracker), `shellcheck` (optional; `tests/syntax.sh` runs it
when present). `virt-install` is run through `/usr/bin/python3` if that exists (system `gi` bindings).
The libvirt session daemon is used (`qemu:///session`); no sudo is needed.

Disk: each VM needs its overlay (`VM_DISK_GB`) plus the cached base image (`~/.cache/lin-devvm/images`)
plus the optional data disk. Put large state on a disk with space (`VM_DIR`, `IMAGE_CACHE`).

## Configuration reference

All values are environment variables read by `config.env` (override on the command line or export them).
Use the **same** values for `provision.sh` and `vm.sh`.

| Variable | Default | Meaning |
|---|---|---|
| `GUEST` | `ubuntu` | Selects `guests/<GUEST>/guest.env`. Exit 1 if unknown. |
| `ROLE` | `dev` | Selects `roles/<ROLE>.sh` (`dev` or `ai`; `web` is a file but is used via `WEB`). Exit 1 if missing. |
| `WEB` | `0` | `1` also installs code-server (loopback only; reach with `vm.sh web`). |
| `VM_NAME` | `lin-$GUEST-$ROLE` | libvirt domain name, guest hostname, source of the port/MAC slot. |
| `VM_DIR` | `$HOME/vms/$VM_NAME` | Per-VM state directory. |
| `ADMIN_USER` | `dev` | Interactive user (sudo NOPASSWD). |
| `AGENT_USER` | `agent` | Unprivileged agent user (`ROLE=ai` only). |
| `SSH_KEY` | `$HOME/.ssh/id_lindevvm` | ed25519 key; generated (no passphrase) if missing. `$SSH_KEY.pub` goes into the guest. |
| `WEB_PASS` | `devvm` | code-server password (plain). |
| `WEB_PORT_GUEST` | `8080` | Guest loopback port of the admin IDE (agent = +1). |
| `WEB_PORT` | `18080 + slot` | Host loopback port opened by `vm.sh web` (agent = +1000). |
| `IMAGE_CACHE` | `$HOME/.cache/lin-devvm/images` | Cached base images and fetched checksum files (`.sums-*`). |
| `VM_DISK_GB` | `GUEST_DISK_GB` (guest.env: 20, or 40 for kubuntu/omarchy; fallback 40) | Virtual size of the system overlay. |
| `DATA_DISK_GB` | `0`; forced to `20` when `ROLE=ai` and left at 0 | Persistent `/work` disk; `0` = none. Works for `ROLE=dev` too if set. |
| `VM_RAM_MB` | `12288` for `ROLE=ai`, else `8192` | Guest memory. Overridden for `DESKTOP=1` guests (next row). |
| `VM_RAM_MB_DESKTOP` | `8192` | For desktop guests (`DESKTOP=1`) `VM_RAM_MB` is *replaced* by this value. |
| `VM_VCPUS` | `6` for `ROLE=ai`, else `4` | vCPUs. |
| `LIBVIRT_URI` | `qemu:///session` | libvirt connection. |
| `SSH_PORT` | `2300 + slot` | Host `127.0.0.1` port forwarded to guest 22. |
| `VM_MAC` | derived from `VM_NAME` | NIC MAC (`52:54:00:xx:xx:xx`). |
| `HERE` | repo directory | Normally auto-detected. |
| `OS_VARIANT` | per guest | `virt-install --osinfo` value. |
| `UEFI_BOOT` | `uefi` | Value for `virt-install --boot` (`${UEFI_BOOT:-uefi}`). |
| `IMAGE_URL`, `IMAGE_FILE`, `IMAGE_SUMS` | per guest | Override the image; `IMAGE_SUMS` is a checksum-file URL or `sha256:<hex>`. |
| `IMAGE_OFFLINE` | `0` | `1`: never download; use cached image and cached `.sums-*`. |
| `HV_DRYRUN` | unset | Non-empty: `virt-install` argv is printed instead of executed. |
| `WAIT_TIMEOUT` | `3600` | Seconds `vm.sh wait` polls. |
| `FEDORA_REL`, `FEDORA_BUILD` | `45`, `1.4` | Fedora release and compose id (change together). |
| `ROCKY_REL` | `10` | Rocky major version. |
| `OMARCHY_REF`, `OMARCHY_REPO`, `OMARCHY_USER_NAME`, `OMARCHY_USER_EMAIL` | `master`, upstream repo, admin user, `<admin>@localhost` | Read by `guests/omarchy/setup.sh` **inside the guest**; they are not in the exported `DEVVM_*` header, so host-side overrides currently have no effect. |
| `TRACKER_PORT`, `TRACKER_HOST` | `4790`, `127.0.0.1` | Tracker server bind (also read by `track.sh`). |
| `TRACKER_ROOT` | repo root | Tracker data root (used by `server.mjs`). |

Derived (not set directly): `VM_SLOT = cksum(VM_NAME) mod 899`; `GUEST_LABEL`, `GUEST_FAMILY`, `DESKTOP`,
`DESKTOP_ENV`, `GUEST_BANNER`, `GUEST_DISK_GB` come from `guest.env`.

## provision.sh

```
GUEST=<g> ROLE=<r> [WEB=1] [VM_NAME=..] ./provision.sh [--force | --reset]
```

| Argument | Effect |
|---|---|
| (none) | Create the VM. Exit 1 if the domain already exists. |
| `--force` | Destroy and undefine the domain, `rm -rf $VM_DIR` (**including `data.qcow2`**), recreate. |
| `--reset` | Destroy and undefine the domain; remove `disk.qcow2`, `seed.iso`, `known_hosts`; **keep `data.qcow2`**; recreate. |

Any other first argument behaves like no flag. The script returns once the VM is defined and started;
provisioning continues in the guest. Follow it with `./vm.sh status` / `./vm.sh wait`.

## vm.sh

```
./vm.sh {start|stop|kill|status|wait|view|ip|ssh [--agent] [cmd...]|web|push|pull|checkpoint|rollback|reset|list|destroy}
```

Select the VM with the same `GUEST`/`ROLE`/`VM_NAME` env. No argument means `status`; an unknown command
prints the usage line and exits 2.

| Command | Behaviour |
|---|---|
| `start` | `virsh start`. |
| `stop` | `virsh shutdown` (ACPI, graceful). |
| `kill` | `virsh destroy` (power off). |
| `status` | `virsh domstate` plus the guest state (`/var/lib/devvm-state`) over SSH, or "ssh not reachable yet". |
| `wait` | Poll the state every 10 s until `DONE` (exit 0), `FAILED` (exit 1) or `WAIT_TIMEOUT` (exit 1). |
| `view` | `virt-viewer` on the console (graphical guests). |
| `ip` | Prints `127.0.0.1` (the SSH host; the port is `SSH_PORT`). |
| `ssh [--agent] [cmd...]` | SSH as `ADMIN_USER`, or as `AGENT_USER` with `--agent` (only meaningful for `ROLE=ai`). Options: `-i $SSH_KEY`, `StrictHostKeyChecking=accept-new`, per-VM `known_hosts`. |
| `web` | Foreground SSH tunnel to the IDE(s); prints URLs and the password; Ctrl-C closes. Does not check that `WEB=1` was used. |
| `push <local> <remote>` | `scp -r` to `ADMIN_USER@127.0.0.1:<remote>`. |
| `pull <remote> <local>` | `scp -r` from the guest. |
| `checkpoint [name]` | Force the VM off, `qemu-img snapshot -c <name>` (default `checkpoint`) on `disk.qcow2`. VM stays stopped. |
| `rollback [name]` | Force off, `qemu-img snapshot -a <name>`. VM stays stopped; run `start`. |
| `reset` | `exec ./provision.sh --reset`: rebuild the system disk, keep `/work`. |
| `list` | `virsh list --all`, filtered to the header line and names containing `lin-`. |
| `destroy` | Prompts `[y/N]`, then destroys/undefines and `rm -rf $VM_DIR` (data disk included). Anything but `y` exits 1. |

## tools/track.sh

```
tools/track.sh event <agent> <state> <msg> [pct]
tools/track.sh serve [port]      # default 127.0.0.1:4790, background node server
tools/track.sh stop
tools/track.sh url
```

`<agent>` must match `[A-Za-z0-9._-]+`; `pct` an integer. Events go to `.tracker/events/<agent>.jsonl`;
the server pid/log/url are `.tracker/server.pid`, `server.log`, `server.url`. Documented states:
`start|progress|done|failed|blocked|note` (see `tools/tracker/README.md`). Endpoints: `/`, `/api/state`,
`/api/stream` (SSE).

## Files, directories and ports

| Path | Content |
|---|---|
| `$VM_DIR` (0700) | `disk.qcow2`, `seed.iso`, `data.qcow2` (if any), `known_hosts`. |
| `$IMAGE_CACHE` | Downloaded images, `.sums-<key>` checksum files. |
| `$SSH_KEY`, `$SSH_KEY.pub` | Host key pair for all guest users. |
| `.tracker/` (repo) | `events/*.jsonl`, `plan.json`, `tests.json`, server pid/log/url. |
| Guest `/var/lib/devvm-state`, `/var/lib/devvm-ready` | Provisioning state / ready marker. |
| Guest `/var/log/devvm-provision.log` | Full provision output. |
| Guest `/usr/local/sbin/devvm-provision.sh` | The composed script (0700, root; contains `WEB_PASS`). |
| Guest `/etc/devvm/README` | Role notes (and web notes). |
| Guest `/work`, `/work/agent`, `/work/interactive` | Data disk (when `DATA_DISK_GB>0`). |

| Port | Where | Purpose |
|---|---|---|
| `2300 + slot` (`SSH_PORT`) | host 127.0.0.1 | SSH to guest :22 |
| `18080 + slot` (`WEB_PORT`) | host 127.0.0.1, only while `vm.sh web` runs | admin code-server |
| `19080 + slot` (`WEB_PORT + 1000`) | same | agent code-server (`ROLE=ai`) |
| 8080 / 8081 | guest 127.0.0.1 | code-server admin / agent |
| `4790` | host 127.0.0.1 | tracker |
| VNC | host 127.0.0.1, auto-assigned | console (`vm.sh view`; `virsh domdisplay`) |

## Per-guest table

`GUEST_FAMILY` picks the package manager. "Live" means actually booted and checked by the author.

| `GUEST` | Image | Family | Disk GB | Desktop | Checksum source | Status / caveats |
|---|---|---|---|---|---|---|
| `ubuntu` | Ubuntu 24.04 noble cloudimg (`current`) | debian | 20 | no | `SHA256SUMS` | **Only live-validated guest** (`ROLE=ai WEB=1`: provision, user isolation, web login over tunnel, reset keeps `/work`). |
| `kubuntu` | same noble image + `kubuntu-desktop`, SDDM | debian | 40 | yes (KDE) | `SHA256SUMS` | Untested. ~1.5 GB of packages; RAM forced to `VM_RAM_MB_DESKTOP`. No user password is set, so graphical login is unresolved. |
| `debian` | Debian 13 genericcloud (`latest`) | debian | 20 | no | `SHA512SUMS` (128-hex) | Untested. `lib/images.sh` verifies sha512 when the expected hash is 128 hex; the NOTE in `guests/debian/guest.env` claiming it is SHA256-only is stale. Fallback: `IMAGE_SUMS=sha256:<hex>`. |
| `fedora` | Fedora 45 Cloud Base Generic `1.4` | rhel | 20 | no | `Fedora-Cloud-45-1.4-x86_64-CHECKSUM` | Untested. Pinned by `FEDORA_REL`/`FEDORA_BUILD`; clearsigned file is parsed but the PGP signature is not verified. |
| `arch` | Arch cloudimg (`latest`, rolling) | arch | 20 | no | `.SHA256` | Untested. Rolling: see refresh below. First provision does a full `-Syu`. |
| `omarchy` | Arch cloudimg + upstream Omarchy `install.sh` | arch | 40 | yes (Hyprland) | `.SHA256` | **Best effort, not officially supported**: Omarchy targets its ISO installer (limine/LUKS/snapper); script may prompt, drift or reboot. Failure of `install.sh` is a warning, not fatal. Needs GPU acceleration; virtio-gpu is slow. 20-40 min. Untested. |
| `opensuse` | Tumbleweed Minimal-VM cloud | suse | 20 | no | `<image>.sha256` | Untested. Rolling: see refresh below. |
| `rocky` | Rocky 10 GenericCloud Base (`latest`) | rhel | 20 | no | `<image>.CHECKSUM` (BSD style) | Untested. |

`dev`/`ai` role package lists exist for all four families; they are exercised offline only (syntax and
composition tests), except Ubuntu.

## Image checksums and refresh

`image_fetch url name sums` (in `lib/images.sh`):

1. Resolve the expected hash: `sums` is either `sha256:<hex>` or a URL fetched with `curl` into
   `$IMAGE_CACHE/.sums-<key>` (a failed fetch reuses the cached copy; `IMAGE_OFFLINE=1` never fetches).
   The parser accepts `<hash>  <name>`, `<hash> *<name>` and `SHA256 (<name>) = <hash>`, with 64 (sha256)
   or 128 (sha512) hex digits.
2. Download the image if not cached (`curl -fL -C - --retry 3`).
3. Compute the digest (sha512 if the expected hash has 128 digits, else sha256) and compare **on every
   run**. On mismatch the cached file is **deleted** and the call fails ("image fetch failed").

Consequence for rolling/"latest"/"current" URLs (arch, omarchy, opensuse, debian `latest`, rocky
`latest`, ubuntu/kubuntu `current`): when upstream republishes the image the cached copy no longer
matches the fresh checksum, the first provision after that fails and removes the stale file, and simply
**re-running the same command downloads the new image**. To refresh deliberately, delete the file in
`$IMAGE_CACHE`. Existing VMs are unaffected only as long as their cached base remains: their
`disk.qcow2` overlay references it by absolute path. Pin an image with
`IMAGE_URL`/`IMAGE_FILE`/`IMAGE_SUMS=sha256:<hex>` to avoid the churn.

## Exit codes

| Code | Where | Meaning |
|---|---|---|
| 1 | `config.env` | unknown `GUEST` or `ROLE` |
| 1 | `provision.sh` | missing tool or `/dev/kvm`; VM exists without flag; image fetch failed |
| 1 | `vm.sh wait` | guest `FAILED` or timeout |
| 1 | `vm.sh destroy` | not confirmed |
| 2 | `vm.sh` | unknown command or bad `push`/`pull` arity |
| 2 | `track.sh` | bad usage, agent name or pct |

## Validation status

Offline (`tests/run.sh`, also CI): syntax and shellcheck, guest contract, composition of every
role/web combination for one guest, tracker smoke test. Live: only **Ubuntu 24.04 `ROLE=ai WEB=1`**.
Everything else in this repository is unverified on real hardware, notably: guests other than ubuntu,
`checkpoint`/`rollback`, `ROLE=dev` on a live VM, `devvm-agent@.service.example`, the `systemd-run`
fallback path, multi-VM coexistence, and the Debian sha512 path.
