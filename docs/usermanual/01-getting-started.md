# 1. Getting started

[← Manual index](README.md) · [← Back to Project README](../../README.md)

## Contents
- [What you get](#what-you-get)
- [Host prerequisites](#host-prerequisites)
- [Create your first VM](#create-your-first-vm)
- [Wait for provisioning](#wait-for-provisioning)
- [Log in](#log-in)
- [Where things live on the host](#where-things-live-on-the-host)
- [Pitfalls](#pitfalls)

## What you get

`provision.sh` downloads a vendor cloud image (checksum-verified, cached), puts a qcow2 overlay on it, builds a cloud-init seed ISO, and starts a libvirt domain under `qemu:///session` (no root, no sudo). Cloud-init creates your users with your SSH key and runs one composed provision script as root. The guest is reachable only via `127.0.0.1:<SSH_PORT>` on the host (QEMU user-mode networking with a host forward). SSH is key-only; the key is `~/.ssh/id_lindevvm` (ed25519, generated if missing).

## Host prerequisites

`provision.sh` checks these and exits with `missing tool: <name>` or `/dev/kvm not accessible`:

| Requirement | Why |
|---|---|
| `virt-install`, `virsh` | define and start the domain |
| `xorriso` | build the cloud-init seed ISO |
| `qemu-img` | overlay, data disk, snapshots |
| `curl`, `ssh-keygen` | image download, key generation |
| read+write access to `/dev/kvm` | KVM acceleration |
| `virt-viewer` | only for `./vm.sh view` (desktop guests) |
| `xz` | only if an image is `*.xz` |
| `node` | only for the [tracker](06-tracker-and-tests.md) |

Network access is needed for the image and for packages inside the guest. Package names for the tools differ per host distro; install them with your host's package manager.

## Create your first VM

The only combination that has been live-booted is Ubuntu, AI role, web IDE:

```
$ GUEST=ubuntu ROLE=ai WEB=1 ./provision.sh
[images] downloading https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
[images] verified noble-server-cloudimg-amd64.img

VM 'lin-ubuntu-ai' started (Ubuntu 24.04, role=ai, web=1). Ubuntu 24.04 cloud image; cloud-init creates dev and runs the devvm provision script.
  progress : ./vm.sh status   ./vm.sh wait      (guest state in /var/lib/devvm-state)
  screen   : ./vm.sh view          (virt-viewer) or VNC: vnc://127.0.0.1:5900
  ssh      : ./vm.sh ssh           (127.0.0.1:2432 -> guest:22; ./vm.sh ssh --agent for the agent user)
  web IDE  : ./vm.sh web           (SSH tunnel -> http://127.0.0.1:18212, password: $WEB_PASS)
```

(The exact VNC address, and the second download lines on a cached image, will differ. `[images]` lines go to stderr; the image is only downloaded the first time.)

`provision.sh` returns as soon as the domain is started; the guest keeps installing in the background. If the VM already exists it refuses:

```
VM lin-ubuntu-ai exists (use --force to recreate, --reset to rebuild the system disk)
```

| Flag | Effect |
|---|---|
| (none) | create; error if the VM exists |
| `--force` | destroy the VM and `rm -rf` its `VM_DIR` (including `/work` data), recreate |
| `--reset` | rebuild only the system disk, keep the data disk (see [chapter 3](03-the-ai-coding-vm.md#reset-recovery)) |

## Wait for provisioning

```
$ GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh status
running
guest: installing: ai: claude-code and uv for agent

$ GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh wait
guest: DONE
```

`wait` polls the guest over SSH every 10 s until the state file `/var/lib/devvm-state` says `DONE*` (exit 0) or `FAILED*` (exit 1); default timeout is `WAIT_TIMEOUT=3600` seconds (exit 1 with `timeout waiting for provisioning`). The state values are `installing: <step>`, `DONE`, `FAILED: <step> (line N)`. Before SSH is up, `status` prints `guest: ssh not reachable yet` and `wait` simply keeps polling. Heavy guests (kubuntu, omarchy) take much longer; see [chapter 2](02-choosing-a-guest-and-role.md).

## Log in

```
$ GUEST=ubuntu ROLE=ai ./vm.sh ssh                 # as dev (sudo, interactive)
$ GUEST=ubuntu ROLE=ai ./vm.sh ssh --agent         # as agent (ROLE=ai only)
$ GUEST=ubuntu ROLE=ai ./vm.sh ssh 'uname -a'      # run one command as dev
```

`vm.sh ssh` accepts the host key on first use (`StrictHostKeyChecking=accept-new`) and stores it in `$VM_DIR/known_hosts`, not in your `~/.ssh/known_hosts`.

## Where things live on the host

| Path | Content |
|---|---|
| `~/vms/<VM_NAME>/` (`VM_DIR`, mode 700) | `disk.qcow2` (system overlay), `seed.iso`, `known_hosts`, `data.qcow2` (if data disk) |
| `~/.cache/lin-devvm/images/` (`IMAGE_CACHE`) | downloaded images and cached checksum files |
| `~/.ssh/id_lindevvm[.pub]` (`SSH_KEY`) | key authorised for every guest user |
| libvirt session `qemu:///session` | the domain named `VM_NAME` (default `lin-<GUEST>-<ROLE>`) |

## Pitfalls

- A forgotten `--force` on an existing name deletes `/work` too. `--reset` is the data-preserving one.
- `WEB=1` is decided at provision time. Adding it later means `--reset` or `--force` with `WEB=1` set.
- Rootless means `virsh list` (no `-c`) will not show your VMs; use `./vm.sh list` or `virsh -c qemu:///session list --all`.
- Only Ubuntu `ROLE=ai WEB=1` has been live-tested; if another combination fails, [chapter 7](07-troubleshooting-and-faq.md) shows how to read the provisioning log.
