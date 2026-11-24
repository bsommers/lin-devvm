# Purpose

## Problem

Running unattended AI coding agents (and trying out Linux distros) directly on a workstation mixes
untrusted, long-running, network-capable processes with your personal files and credentials. Building
a throw-away VM by hand is slow and not repeatable. `lin-devvm` makes a Linux dev VM one command:
rootless KVM via libvirt, a vendor cloud image, and cloud-init, with the VM reachable **only over SSH
on `127.0.0.1`**.

Sibling project: `win-devvm` (Windows guests). This repo covers Linux guests only.

## Tenets

1. **SSH-only, loopback-only.** The only host-side listeners are the QEMU SSH forward
   (`127.0.0.1:SSH_PORT`), the optional tunnel opened by `vm.sh web`, and the VNC console, all bound to
   `127.0.0.1`. The guest NIC is QEMU user-mode networking (no inbound path from the LAN). Inside the
   guest, `sshd` is key-only and code-server binds `127.0.0.1` (provisioning fails if it does not).
2. **Rootless.** `LIBVIRT_URI=qemu:///session`; no sudo on the host, no host-wide libvirt changes.
3. **Reproducible from the vendor image.** Everything the guest has is composed from checked-in shell
   (`guest/common.sh`, `guests/<g>/`, `roles/`), delivered through cloud-init. The system disk is a
   disposable qcow2 overlay over a checksum-verified cached image.
4. **AI-agent session separate from the interactive session.** With `ROLE=ai`, unattended agents run as
   an unprivileged `agent` user (no sudo, cannot read the admin's home); the human works as `dev`.
   A compromised or misbehaving agent does not start with the admin's files, keys or sudo.
5. **Reset keeps `/work`.** `/work` lives on its own persistent data disk (`data.qcow2`).
   `./vm.sh reset` rebuilds only the system disk from the cloud image, so a gummed-up VM is
   cheap to recover and the work survives. Only `/work` survives: anything in `/home/*` (for example the
   agent's Claude Code login) is on the system disk and is lost.
6. **Many VMs side by side.** Host ports and the MAC derive from `VM_NAME` (`vm_slot`), so several VMs
   coexist without configuration.
7. **Honest about what is tested.** Only Ubuntu 24.04 `ROLE=ai WEB=1` has been booted and validated
   end to end (see [running.md](running.md#per-guest-table)).

## Non-goals

Not a hardened or production image. Not a multi-host or cloud orchestrator. Not a container/VM
sandbox *between* admin and agent (they share one kernel). No GPU passthrough. No automatic
patching after first provision.

## Threat model

Assumed: a single trusted human on a single-user host, using the VM as a lab machine. The adversary
of interest is *buggy or manipulated agent code running as `agent`*, plus network exposure.

| Surface | Posture |
|---|---|
| Host network exposure | SSH forward, web tunnel and VNC bind `127.0.0.1` only; user-mode NIC means the LAN cannot reach the guest. |
| Host privilege | Everything runs as your user (`qemu:///session`). |
| Guest SSH | Key auth only (`PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`, `X11Forwarding no`). Key `~/.ssh/id_lindevvm` (ed25519, no passphrase) is authorised for every provisioned user. Host keys accepted on first use (`accept-new`) into a per-VM `known_hosts`. |
| Agent vs admin | Different Unix users; homes `0750`; agent removed from `sudo`/`wheel` and from the admin's group; `/work/agent` and `/work/interactive` are `0750` to their owners. |
| Agent resource limits | `devvm-agent-run` applies `MemoryMax`/`CPUQuota` through a `systemd-run --user` scope (falls back to **no limits** with a warning if that is unavailable). |
| Guest outbound | Unrestricted NAT. The agent can reach the internet and anything the host's NAT path reaches. |

### The deliberate plain web password

With `WEB=1`, code-server is installed with `auth: password` and the password is `WEB_PASS`
(default `devvm`, **public in this repo**). It is written in plaintext to
`~/.config/code-server/config.yaml` (mode `0600`) of each user, embedded in the cloud-init seed
(`$VM_DIR/seed.iso`, dir mode `0700`) and the root-only `/usr/local/sbin/devvm-provision.sh`, and printed
by `./vm.sh web`. It is a convenience gate, not a secret.

Mitigation, layered:

- the listener is loopback-only inside the guest; `roles/web.sh` checks with `ss` and calls
  `devvm_fail` if it is bound anywhere else;
- the guest has no inbound route except the SSH forward, so the web port is reachable only through an
  SSH tunnel, which requires the private key;
- the tunnel (`vm.sh web`) is opened on demand and closed with Ctrl-C;
- override `WEB_PASS` for anything beyond a throw-away VM.

Remaining exposure you should know about:

- The tunnel's host port is on host loopback, which **any local user of the host can connect to**; at
  that point only the plain password stands in the way. The admin IDE has a terminal and the admin has
  `NOPASSWD` sudo, so it is effectively guest root. Do not run `vm.sh web` on a shared host.
- The VNC console (`--graphics vnc,listen=127.0.0.1`) has no password; same local-user caveat.
- The password also reaches the agent's IDE (port +1) and is readable by the admin.

### What is NOT hardened

- `dev` (admin) has `sudo NOPASSWD:ALL`.
- Admin and agent share a kernel and a machine; separation is Unix permissions only. The
  `devvm-agent@.service.example` unit (`ProtectSystem=strict`, `InaccessiblePaths`, ...) is shipped
  disabled as an example and is untested.
- No firewall in the guest; no egress filtering; no SELinux/AppArmor tuning.
- Images are verified by checksum fetched over HTTPS; PGP signatures (for example Fedora's
  clearsigned CHECKSUM) are not checked.
- Third-party installers are piped from the network at provision time (code-server install script,
  rustup, uv, nodejs.org tarball, `npm install -g @anthropic-ai/claude-code`, Omarchy).
- No guest user has a password (`lock_passwd: true`), so there is no console login; graphical logins
  on desktop guests (kubuntu, omarchy) are an open, untested item.
- The SSH private key has no passphrase.
- Do not store secrets in the guest that you would not expose to anything running as your user on the
  host, and do not publish `$VM_DIR`.
