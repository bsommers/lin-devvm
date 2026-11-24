# How-to

Copy-paste recipes. Run from the repository root. Variables are described in
[running.md](running.md#configuration-reference); design in [architecture.md](architecture.md).
Only Ubuntu `ROLE=ai WEB=1` has been live-validated; other recipes are marked where untested.

## Contents

- [Launch an AI VM](#launch-an-ai-vm)
- [Add the web IDE](#add-the-web-ide)
- [Run agents with devvm-agent-run](#run-agents-with-devvm-agent-run)
- [Recover with reset](#recover-with-reset)
- [Checkpoint and rollback](#checkpoint-and-rollback)
- [Run several VMs](#run-several-vms)
- [Add a new guest distro](#add-a-new-guest-distro)
- [Add a role](#add-a-role)
- [Override the image](#override-the-image)
- [Use the tracker](#use-the-tracker)
- [Run the tests](#run-the-tests)

## Launch an AI VM

```bash
GUEST=ubuntu ROLE=ai ./provision.sh        # first run downloads and verifies the cloud image
GUEST=ubuntu ROLE=ai ./vm.sh wait          # polls /var/lib/devvm-state; exit 0 on DONE
GUEST=ubuntu ROLE=ai ./vm.sh ssh           # interactive user (dev)
GUEST=ubuntu ROLE=ai ./vm.sh ssh --agent   # unattended-agent user
```

If `wait` reports `FAILED: <step>`, read the log:
`GUEST=ubuntu ROLE=ai ./vm.sh ssh 'sudo tail -n 100 /var/log/devvm-provision.log'`.
Then `./vm.sh reset` (or `provision.sh --force` for a clean slate) after fixing the cause.
Log in to Claude Code once as the agent: `./vm.sh ssh --agent`, then `claude`.

## Add the web IDE

At provision time:

```bash
GUEST=ubuntu ROLE=ai WEB=1 WEB_PASS='something-better' ./provision.sh
```

Open the tunnel (foreground, Ctrl-C closes it):

```bash
GUEST=ubuntu ROLE=ai WEB=1 WEB_PASS='something-better' ./vm.sh web
# web IDE (admin dev):   http://127.0.0.1:<WEB_PORT>
# web IDE (agent agent): http://127.0.0.1:<WEB_PORT+1000>
```

`WEB_PASS` is baked in at provision time; passing it to `vm.sh web` only changes what is printed. To add
the IDE to an existing VM you must re-provision (`./vm.sh reset` with `WEB=1`; `/work` is kept). Read the
caveats in [purpose.md](purpose.md#the-deliberate-plain-web-password).

## Run agents with devvm-agent-run

Inside the guest (as `dev` or `agent`; `ROLE=ai`):

```bash
devvm-agent-run -n job1 -- claude                 # tmux session "job1", runs as agent in /work/agent
devvm-agent-run -n big -m 12G -c 600% -- ./long-task.sh
sudo -u agent tmux ls                             # list sessions
sudo -u agent tmux attach -t job1                 # attach (detach with Ctrl-b d)
```

Defaults: session name `agent-HHMMSS`, `-m 8G` (MemoryMax), `-c 400%` (CPUQuota). If `systemd-run --user`
is unavailable it warns and runs without limits. For a stricter, persistent setup see
`/etc/devvm/devvm-agent@.service.example` (not enabled, untested).

Move files between host and agent workspace:

```bash
GUEST=ubuntu ROLE=ai ./vm.sh push ./repo /work/interactive/     # lands as dev
GUEST=ubuntu ROLE=ai ./vm.sh ssh 'sudo cp -r /work/interactive/repo /work/agent/ && sudo chown -R agent:agent /work/agent/repo'
GUEST=ubuntu ROLE=ai ./vm.sh pull /work/interactive/result ./
```

## Recover with reset

When the VM is broken or cluttered:

```bash
GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh reset      # = provision.sh --reset
GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh wait
```

Keeps `data.qcow2` (everything in `/work`). Loses everything on the system disk: packages, `/home/*`
(including agent credentials and `~/.config/code-server`), and `known_hosts`. Keep the same env as the
original provision, otherwise the rebuilt VM gets different roles or sizes. `provision.sh --force` (or
`vm.sh destroy`) removes the data disk too.

## Checkpoint and rollback

System disk only (`/work` is not captured). Both commands force the VM off. Untested live.

```bash
GUEST=ubuntu ROLE=ai ./vm.sh checkpoint before-upgrade
GUEST=ubuntu ROLE=ai ./vm.sh start
# ... experiment ...
GUEST=ubuntu ROLE=ai ./vm.sh rollback before-upgrade
GUEST=ubuntu ROLE=ai ./vm.sh start
qemu-img snapshot -l ~/vms/lin-ubuntu-ai/disk.qcow2     # list snapshots
```

## Run several VMs

Ports and MAC derive from `VM_NAME`, so distinct names coexist. Always pass the same env to `vm.sh`.

```bash
GUEST=ubuntu ROLE=ai WEB=1 ./provision.sh
GUEST=fedora ROLE=ai       ./provision.sh
GUEST=ubuntu ROLE=dev VM_NAME=scratch ./provision.sh
./vm.sh list                                   # only names containing "lin-"
GUEST=fedora ROLE=ai ./vm.sh ssh
GUEST=ubuntu ROLE=dev VM_NAME=scratch ./vm.sh ssh
```

`vm.sh list` hides names without `lin-`, so keep the `lin-` prefix (for example `VM_NAME=lin-scratch`)
if you want them listed and shown in the tracker. If two names hash to the same slot, set `SSH_PORT`
(and `WEB_PORT`) explicitly.

## Add a new guest distro

1. Create `guests/<name>/guest.env` (copy a similar one). Required by `tests/guests.sh`:
   `GUEST_LABEL GUEST_FAMILY OS_VARIANT DESKTOP IMAGE_URL IMAGE_FILE IMAGE_SUMS GUEST_BANNER`.
   Also set `GUEST_DIR`, `DESKTOP_ENV`, `GUEST_DISK_GB`. Use `${VAR:-default}` for overridable values.
   `IMAGE_SUMS` is a URL to a checksum file (sha256 or sha512 lines, or BSD `SHA256 (name) = hash`)
   or `sha256:<hex>`. Find a valid `OS_VARIANT` with `osinfo-query os`.
2. `GUEST_FAMILY` must be one of `debian rhel arch suse` (those are the only branches in
   `pkg_update`/`pkg_install` and in the role package lists). For a new family, extend
   `guest/common.sh` and `roles/dev.sh`/`roles/ai.sh` (and the `case` in `roles/web.sh` if needed).
3. Optional `guests/<name>/setup.sh`: concatenated after `guest/common.sh`; use `devvm_step`,
   `pkg_install`, `devvm_fail`; guard desktop work with `[ "${DEVVM_DESKTOP:-0}" = 1 ]`.
4. Verify offline, then live:

```bash
bash tests/run.sh
GUEST=<name> ROLE=dev ./provision.sh && GUEST=<name> ROLE=dev ./vm.sh wait
```

Add a row to [running.md](running.md#per-guest-table) and `README.md`.

## Add a role

1. Write `roles/<name>.sh`. It is concatenated into the root script after `guest/common.sh`, so helpers and
   `DEVVM_*` variables are available. Start with `devvm_step "<name>: ..."`, call `devvm_mount_work` if
   you want `/work`, and `unset` temporaries at the end. Use `pkg_install` (fatal) or `pkg_try` (best effort).
2. Select it with `ROLE=<name>`. Note that `provision.sh` creates the extra agent user, and `config.env`
   forces `DATA_DISK_GB=20` and larger RAM/vCPU defaults, only for `ROLE=ai`; other roles must set sizes
   via env or edit `config.env` / `provision.sh`.
3. Add the role to the `for role in dev ai` loop in `tests/compose.sh`, then `bash tests/run.sh`.

## Override the image

```bash
# different upstream URL, same checksum file
GUEST=ubuntu IMAGE_URL=https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
  IMAGE_FILE=jammy-server-cloudimg-amd64.img \
  IMAGE_SUMS=https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS ./provision.sh   # untested

# pin to a known hash (no checksum download)
GUEST=debian IMAGE_SUMS=sha256:<64-hex> ./provision.sh

# air-gapped / reuse cache: image and .sums-* must already be in IMAGE_CACHE
IMAGE_OFFLINE=1 GUEST=ubuntu ./provision.sh

# refresh a rolling image whose checksum changed
rm ~/.cache/lin-devvm/images/Arch-Linux-x86_64-cloudimg.qcow2 && GUEST=arch ./provision.sh
```

Print the exact `virt-install` command without defining a VM:
`HV_DRYRUN=1 GUEST=ubuntu ROLE=ai ./provision.sh` (still downloads the image and builds the overlay and
seed; it only prints the final `virt-install` argv).

## Use the tracker

```bash
tools/track.sh serve                    # http://127.0.0.1:4790/  (TRACKER_PORT / port argument)
tools/track.sh event myagent progress "building" 40
tools/track.sh event myagent done "finished"
tools/track.sh url
tools/track.sh stop
```

`provision.sh` reports its own `provision` events. The page shows plan, event feed, guests, live `lin-*`
domains and test results. Edit `.tracker/plan.json` (schema in `tools/tracker/README.md`) to change the plan.

## Run the tests

```bash
bash tests/run.sh          # all suites; writes .tracker/tests.json; exit 0 iff all pass
bash tests/syntax.sh       # bash -n on every script, plus shellcheck if installed
bash tests/guests.sh       # each guest.env defines the contract variables
GUEST=fedora bash tests/compose.sh   # compose provision script for dev/ai x WEB 0/1 and bash -n it
bash tests/tracker.sh      # starts the server on a random port, checks / and /api/state
```

The same `tests/run.sh` runs in GitHub Actions (`.github/workflows/ci.yml`). These suites never boot a VM.
