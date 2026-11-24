# 7. Troubleshooting and FAQ

[← Manual index](README.md) · [← Back to Project README](../../README.md)

## Contents
- [Quick triage](#quick-triage)
- [KVM access](#kvm-access)
- [Libvirt session and missing tools](#libvirt-session-and-missing-tools)
- [Image checksum mismatch on rolling images](#image-checksum-mismatch-on-rolling-images)
- [Cloud-init or provisioning fails](#cloud-init-or-provisioning-fails)
- [Port clashes](#port-clashes)
- [Which VM does vm.sh address?](#which-vm-does-vmsh-address)
- [Host key changes](#host-key-changes)
- [Omarchy and desktop caveats](#omarchy-and-desktop-caveats)
- [Error message table](#error-message-table)
- [FAQ](#faq)

## Quick triage

```
./vm.sh status                                   # domain state + guest state line
./vm.sh ssh 'cat /var/lib/devvm-state'           # DONE | installing: <step> | FAILED: <step> (line N)
./vm.sh ssh 'sudo tail -n 80 /var/log/devvm-provision.log'
./vm.sh view                                     # console, if SSH never comes up
```

Use the same env as at provision time for all of these.

## KVM access

`provision.sh` stops with `/dev/kvm not accessible` unless `/dev/kvm` is readable and writable by you.

```
$ ls -l /dev/kvm
crw-rw----+ 1 root kvm 10, 232 ... /dev/kvm
$ id -nG                        # is 'kvm' listed?
```

Typical fix: add your user to the group that owns `/dev/kvm` (usually `kvm`), then log out and back in. If the node is missing, enable virtualisation in firmware and load `kvm_intel` or `kvm_amd`. Inside another VM you need nested virtualisation. There is no TCG fallback in the scripts.

## Libvirt session and missing tools

- VMs run under **`qemu:///session`** (your user, no root). `virsh list` without `-c` queries the system instance and will not show them. Use `./vm.sh list`, or `virsh -c qemu:///session list --all`. `LIBVIRT_URI` overrides this.
- `missing tool: virt-install` (or `virsh`, `xorriso`, `qemu-img`, `curl`, `ssh-keygen`): install it on the host.
- UEFI guests need OVMF firmware available to libvirt; `UEFI_BOOT` (default `uefi`) is passed to `virt-install --boot`.
- `./vm.sh view` fails if `virt-viewer` is missing or there is no display. Every VM also has a VNC listener on host loopback (`virsh -c qemu:///session domdisplay <VM_NAME>`).
- Networking is QEMU user-mode: the guest can reach the internet; the only inbound path is the SSH forward. There is no bridge, no VM-to-VM networking, and the guest has no host-visible IP (`./vm.sh ip` prints `127.0.0.1`).

## Image checksum mismatch on rolling images

```
[images] checksum mismatch for Arch-Linux-x86_64-cloudimg.qcow2 (want <hex> got <hex>); removing
image fetch failed
```

Images are cached by file name and verified against upstream checksums fetched fresh on every run. Rolling or re-published names (Arch `latest`, openSUSE Tumbleweed, Ubuntu `current`, Rocky `latest`) change under the same name, so a previously cached copy stops matching. The mismatching file is deleted automatically; **just rerun** `provision.sh` and it downloads the current one. If it fails repeatedly:

- the mirror may be mid-update (checksum file and image out of step): wait and retry;
- a truncated download: `curl -C -` resumes, a rerun re-verifies;
- `no checksum for <name> in <url>`: the upstream checksum list does not contain `IMAGE_FILE` (e.g. Fedora `FEDORA_BUILD` out of date); fix `IMAGE_FILE`/`FEDORA_BUILD`;
- pin by hand: `IMAGE_SUMS=sha256:<hex>` (SHA-512 is detected by 128 hex chars);
- offline: `IMAGE_OFFLINE=1` uses only the cache and fails with `offline and <name> not cached` otherwise;
- `cannot fetch sums <url>`: first-time network failure; later runs fall back to the cached sums file (`sums fetch failed; using cached copy`).

## Cloud-init or provisioning fails

The whole install is one root script run once by cloud-init: `bash /usr/local/sbin/devvm-provision.sh >> /var/log/devvm-provision.log 2>&1`. It records progress in `/var/lib/devvm-state`.

1. `./vm.sh wait` returning `guest: FAILED: <step> (line N)` tells you the failing step. A hang with no change in `status` for a long time means a slow step (kubuntu, omarchy) or a stuck network.
2. Read the log (as `dev`; SSH works as soon as cloud-init has created the user, even while provisioning runs):
   ```
   $ ./vm.sh ssh 'sudo grep -nE "FAIL|WARN" /var/log/devvm-provision.log'
   $ ./vm.sh ssh 'sudo tail -n 100 /var/log/devvm-provision.log'
   $ ./vm.sh ssh 'sudo tail -n 50 /var/log/cloud-init-output.log'      # standard cloud-init log
   $ ./vm.sh ssh 'cat /var/lib/devvm-state; ls -l /var/lib/devvm-ready'  # ready marker exists only on success
   ```
3. If SSH never works: `./vm.sh view` to watch the console; check the host can reach the image mirror; confirm `seed.iso` exists in `VM_DIR`.
4. Fix the cause, then redo from scratch: `./provision.sh --reset` (keeps `/work`) or `--force` (clean slate). Re-running the composed script by hand (`sudo bash /usr/local/sbin/devvm-provision.sh`) may work but is not an advertised or tested path.

Notes: `[devvm WARN]` lines (optional packages, `gh`, Claude Code/uv install, node tarball, code-server) are non-fatal; the VM still reaches `DONE`. Hard failures (`[devvm FAIL]`) include unknown distro family, a failed apt/dnf/pacman/zypper install after 3 retries, the Omarchy clone, `kubuntu-desktop` install, and code-server listening on a non-loopback address. SSH to the guest is kept key-only (`PasswordAuthentication no`).

## Port clashes

Ports are derived from the VM name (`slot = cksum(VM_NAME) % 899`): SSH `2300+slot`, web tunnel `18080+slot`, agent tunnel `+1000`. Two names can collide, and any port can clash with something else on the host.

| Symptom | Fix |
|---|---|
| the domain fails to start or exits immediately and the host forward on `SSH_PORT` cannot bind (check `virsh -c qemu:///session start` output) | pick another `SSH_PORT=...` and re-provision (`--force`/`--reset`) |
| `vm.sh web` prints `Address already in use` / `bind ... failed` | `WEB_PORT=...` (host-only, change any time) |
| tracker port busy | `TRACKER_PORT=...` |

`SSH_PORT` is fixed into the domain at creation. If you set a different `SSH_PORT` later when calling `vm.sh`, it dials the wrong port. Check what a VM uses with `virsh -c qemu:///session dumpxml <VM_NAME> | grep hostfwd`. Find ports for a name without creating anything: `GUEST=x ROLE=y bash -c 'source ./config.env; echo $SSH_PORT $WEB_PORT'`.

## Which VM does vm.sh address?

Whichever one **your current environment** names. `vm.sh` sources `config.env`, which builds `VM_NAME = ${VM_NAME:-lin-$GUEST-$ROLE}` from `GUEST` (default `ubuntu`), `ROLE` (default `dev`) and `VM_NAME`. So:

```
GUEST=fedora ROLE=ai WEB=1 ./provision.sh   # creates lin-fedora-ai
./vm.sh status                              # addresses lin-ubuntu-dev (defaults!)  -> "error: Domain not found"
GUEST=fedora ROLE=ai ./vm.sh status         # correct (WEB is irrelevant to addressing)
```

`WEB` does not affect the name or ports, only `GUEST`, `ROLE` and `VM_NAME` do (plus `ADMIN_USER`/`AGENT_USER`/`SSH_KEY`/`SSH_PORT` for logging in). A custom `VM_NAME=foo` must be repeated on every call. Confirm what you would hit:

```
GUEST=fedora ROLE=ai bash -c 'source ./config.env; echo $VM_NAME $VM_DIR'
./vm.sh list                              # all lin-* domains
```

## Host key changes

`vm.sh` keeps one `known_hosts` per VM in `$VM_DIR` (`StrictHostKeyChecking=accept-new`), so rebuilt VMs on a reused port do not pollute `~/.ssh/known_hosts`. `reset` and `--force` delete it, so the new host key is accepted fresh. If you see `REMOTE HOST IDENTIFICATION HAS CHANGED`:

- via `vm.sh`: the VM was rebuilt outside these scripts; `rm ~/vms/<VM_NAME>/known_hosts`;
- via plain `ssh` to `127.0.0.1:<port>` (e.g. in the remote-access recipes): `ssh-keygen -R "[127.0.0.1]:<port>"`. Different VMs sharing a port over time cause this; prefer `vm.sh ssh`, or give plain ssh `-o UserKnownHostsFile=$HOME/vms/<VM_NAME>/known_hosts`.

## Omarchy and desktop caveats

- **Omarchy is best effort.** It officially targets its own ISO (archinstall, limine, LUKS, snapper); on the Arch cloud image those steps are skipped or fail. Budget 20-40 minutes. Upstream prompts, reboots or layout assumptions can leave it half-installed: look for `WARNING: Omarchy install.sh failed or was interrupted` in `/var/log/devvm-provision.log`; the stamp `/var/lib/devvm-omarchy-done` exists only if it finished. The provisioning state may still end `DONE` because the failure is only a warning. Rerunning the install is idempotent to the extent upstream is.
- No Omarchy or desktop guest has been boot-tested here. Hyprland and Plasma are slow without 3D acceleration (virtio video, no GPU passthrough).
- Desktop guests force RAM to `VM_RAM_MB_DESKTOP` (8192) even for `ROLE=ai`; override with `VM_RAM_MB_DESKTOP`.
- Arch guests do a full `pacman -Syu` on first provision (rolling): slow, and sensitive to mirror state.

## Error message table

| Message | Meaning / action |
|---|---|
| `unknown GUEST 'x' (no guests/x/guest.env); available: ...` | typo; the list shows valid names |
| `unknown ROLE 'x'` | only `dev`, `ai` exist |
| `missing tool: X` | install X on the host |
| `/dev/kvm not accessible` | [KVM access](#kvm-access) |
| `VM <name> exists (use --force ...)` | use `--reset` (keep `/work`) or `--force` |
| `image fetch failed` | see [checksum](#image-checksum-mismatch-on-rolling-images) / network |
| `xorriso not found` | install xorriso |
| `usage: vm.sh push <local> <remote>` | wrong arg count |
| `guest: ssh not reachable yet` | still booting, wrong env, or wrong `SSH_PORT` |
| `timeout waiting for provisioning` | raise `WAIT_TIMEOUT` or check the log |
| `error: failed to get domain ...` (virsh) | env points at a VM that does not exist |

## FAQ

**Can I reach a guest service from my LAN?** Not by design: everything is host loopback. Use `ssh -L` through the host ([chapter 4](04-web-ide-over-ssh.md#reach-it-from-another-machine)); do not rebind to `0.0.0.0`.

**Do I need sudo on the host?** No; libvirt session mode is rootless.

**How do I give a guest more disk later?** Not scripted. Provision with `VM_DISK_GB` / `DATA_DISK_GB` set; the values are applied at creation. Growing an existing qcow2 is a manual `qemu-img resize` plus in-guest filesystem work.

**How do I change Claude Code or Node versions?** As `agent`: `npm install -g @anthropic-ai/claude-code@<ver>`; Node is a tarball under `~/.local/node`.

**Is the data disk backed up?** No. `reset` preserves it, `destroy` and `--force` delete it, and nothing copies it elsewhere. Use git remotes or `./vm.sh pull`.

**Which guests are proven?** Only Ubuntu 24.04 `ROLE=ai WEB=1` has been live-booted (provision, isolation, web tunnel, reset keeping `/work`). The rest pass static tests only.
