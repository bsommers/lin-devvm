# 5. Daily operations

[← Manual index](README.md) · [← Back to Project README](../../README.md)

## Contents
- [Command reference](#command-reference)
- [Power](#power)
- [Status and waiting](#status-and-waiting)
- [Logging in](#logging-in)
- [File transfer](#file-transfer)
- [Checkpoint and rollback](#checkpoint-and-rollback)
- [Reset, destroy, force](#reset-destroy-force)
- [Several VMs at once](#several-vms-at-once)
- [Pitfalls](#pitfalls)

Every command below must run with the same `GUEST`/`ROLE`/`VM_NAME` env as the `provision.sh` call. The examples assume you exported them:

```
export GUEST=ubuntu ROLE=ai WEB=1
```

## Command reference

`./vm.sh <command>`; with no command it runs `status`. Unknown commands print the usage line and exit 2.

| Command | Does | Notes |
|---|---|---|
| `start` | `virsh start` | boot a stopped VM |
| `stop` | `virsh shutdown` | graceful ACPI shutdown; returns immediately |
| `kill` | `virsh destroy` | hard power-off (data on disk stays) |
| `status` | `virsh domstate` + guest provisioning state | default command |
| `wait` | poll until provisioning `DONE`/`FAILED` | `WAIT_TIMEOUT` seconds, default 3600 |
| `ssh [--agent] [cmd...]` | SSH as `dev` (or `agent`) | `--agent` must be first |
| `web` | open the web IDE tunnel(s) | [chapter 4](04-web-ide-over-ssh.md) |
| `view` | `virt-viewer` on the VM console | needs `virt-viewer` and a display |
| `ip` | prints `127.0.0.1` | the guest is reached through a port forward |
| `push <local> <remote>` | `scp -r` host to guest as `dev` | exactly 2 args |
| `pull <remote> <local>` | `scp -r` guest to host as `dev` | exactly 2 args |
| `checkpoint [name]` | offline snapshot of the system disk | VM is killed first; default name `checkpoint` |
| `rollback [name]` | restore a snapshot | VM is killed first; start it afterwards |
| `reset` | rebuild system disk, keep `/work` | `provision.sh --reset` |
| `list` | list `lin-*` libvirt domains | all VMs, not just this one |
| `destroy` | delete VM and `VM_DIR` | asks `[y/N]` |

## Power

```
$ ./vm.sh start
Domain 'lin-ubuntu-ai' started
$ ./vm.sh stop
Domain 'lin-ubuntu-ai' is being shutdown
$ ./vm.sh kill                      # if shutdown hangs
Domain 'lin-ubuntu-ai' destroyed
```

(The messages are virsh's, wording may vary by version.) `kill` is a power cut: fine for a disposable VM, but filesystems may need recovery.

## Status and waiting

```
$ ./vm.sh status
running
guest: DONE
```

The second line is `DONE`, `installing: <step>`, `FAILED: <step> (line N)` (from `/var/lib/devvm-state` in the guest), or `ssh not reachable yet` while booting/off. `wait` exits 0 on `DONE`, 1 on `FAILED` or timeout.

## Logging in

```
$ ./vm.sh ssh                               # interactive dev shell
$ ./vm.sh ssh --agent                       # agent shell (ROLE=ai)
$ ./vm.sh ssh 'df -h /work'                 # one command as dev
$ ./vm.sh ssh --agent 'bash -lc "claude --version"'
```

SSH options are fixed: key `SSH_KEY`, `StrictHostKeyChecking=accept-new`, per-VM `$VM_DIR/known_hosts`, `LogLevel=ERROR`.

## File transfer

```
$ ./vm.sh push ./myproject /work/interactive/        # copy a directory to the guest
$ ./vm.sh pull /work/interactive/out ./out            # copy results back
```

Both use `scp -r` as `dev`. Remote paths are interpreted by the guest (relative paths start in `/home/dev`). `dev` cannot write `/work/agent`, and `agent` is not reachable by these commands; see [chapter 3](03-the-ai-coding-vm.md#getting-files-in-and-out). Note `scp -r` into an existing directory creates a nested copy; target a path that does not exist, or the parent, deliberately.

## Checkpoint and rollback

```
$ ./vm.sh checkpoint before-upgrade
checkpoint 'before-upgrade' saved (VM is stopped; ./vm.sh start)
$ ./vm.sh start
... something breaks ...
$ ./vm.sh rollback before-upgrade
rolled back to 'before-upgrade' (./vm.sh start)
$ ./vm.sh start
```

These are qcow2 internal snapshots (`qemu-img snapshot`) of `disk.qcow2` taken **offline**, which is why the VM is killed first (a hard power-off, not a clean shutdown; run `./vm.sh stop` and wait yourself first for a clean state). List them with `qemu-img snapshot -l ~/vms/<VM_NAME>/disk.qcow2`.

What it does **not** cover: the `/work` data disk (`data.qcow2`) is not snapshotted, so rollback does not undo file changes under `/work`. `reset` and `destroy` delete the snapshots with the disk. Snapshots grow the overlay file.

## Reset, destroy, force

| Action | System disk | `/work` (`data.qcow2`) | Domain | Confirms? |
|---|---|---|---|---|
| `./vm.sh reset` | rebuilt from image | kept | recreated | no |
| `./vm.sh destroy` | deleted | **deleted** | removed | yes, type `y` |
| `./provision.sh --force` | rebuilt | **deleted** | recreated | no |

`destroy` prompt: `Delete VM lin-ubuntu-ai and /home/<you>/vms/lin-ubuntu-ai (including /work data)? [y/N]`; anything other than `y` exits 1. Cached base images in `IMAGE_CACHE` are never deleted by these.

## Several VMs at once

Ports and MACs derive from `VM_NAME`, so differently named VMs coexist. Give each its own env:

```
GUEST=fedora ROLE=ai WEB=1 ./provision.sh
GUEST=debian ROLE=dev      ./provision.sh
GUEST=ubuntu ROLE=ai VM_NAME=agent-b ./provision.sh      # second ubuntu/ai VM

GUEST=fedora ROLE=ai WEB=1 ./vm.sh ssh --agent
GUEST=ubuntu ROLE=ai VM_NAME=agent-b ./vm.sh status
./vm.sh list
 Id   Name              State
 1    lin-fedora-ai     running
 -    lin-debian-dev    shut off
```

`list` filters the `virsh list --all` output for the header line and names containing `lin-`. A VM with a custom `VM_NAME` that lacks `lin-` is hidden from `list`; use `virsh -c qemu:///session list --all`. Make sure the combined RAM/vCPU of running VMs fits your host (ai defaults: 12 GB, 6 vCPU each). A shell function or `direnv` per project directory is a convenient way to pin the env.

## Pitfalls

- `stop` returns before the guest is off; check `./vm.sh status` before copying `VM_DIR`.
- `checkpoint` kills the VM; any unsaved in-guest work is at crash-consistency level.
- Forgetting the env on `vm.sh` yields `lin-ubuntu-dev` (the default) rather than your VM; see [chapter 7](07-troubleshooting-and-faq.md#which-vm-does-vmsh-address).
- `push`/`pull` have no `--agent` variant.
