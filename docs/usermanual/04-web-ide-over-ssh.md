# 4. Web IDE over SSH

[← Manual index](README.md) · [← Back to Project README](../../README.md)

## Contents
- [What it is](#what-it-is)
- [Enable it](#enable-it)
- [Ports](#ports)
- [Open it locally](#open-it-locally)
- [Why a plain password](#why-a-plain-password)
- [Changing the password](#changing-the-password)
- [Reach it from another machine](#reach-it-from-another-machine)
- [Checking and restarting the service](#checking-and-restarting-the-service)
- [Pitfalls](#pitfalls)

Status: web login through the tunnel was live-verified on Ubuntu `ROLE=ai WEB=1`. Other guests install code-server the same way (vendor script, then release tarball as fallback) but are unbooted.

## What it is

`WEB=1` adds `roles/web.sh`: it installs [code-server](https://github.com/coder/code-server) (VS Code in the browser) via `code-server.dev/install.sh`, falling back to the latest GitHub release tarball, and runs it as a systemd unit `code-server@<user>` bound to **guest loopback only**. The provisioning script verifies with `ss -ltn` that each port is listening on `127.0.0.1` / `[::1]` and fails provisioning if not. Nothing else is exposed: the host side is just an SSH tunnel.

If neither install route works, provisioning warns `code-server unavailable; web IDE skipped` and continues.

## Enable it

```
GUEST=ubuntu ROLE=ai WEB=1 WEB_PASS='something-else' ./provision.sh
```

`WEB` and `WEB_PASS` are baked in at provision time. To add the IDE to an existing VM you must reprovision (`./provision.sh --reset` keeps `/work` on `ROLE=ai`) with `WEB=1` set. `WEB=1` also needs to be passed to `vm.sh` only if you want your env consistent; `vm.sh` itself does not read it (the tunnel command works regardless, but points at nothing if the IDE was never installed).

## Ports

| What | Value | Notes |
|---|---|---|
| Guest `dev` IDE | `127.0.0.1:8080` (`WEB_PORT_GUEST`) | inside the VM |
| Guest `agent` IDE (`ROLE=ai`) | `127.0.0.1:8081` (`WEB_PORT_GUEST`+1) | inside the VM |
| Host tunnel for `dev` | `127.0.0.1:WEB_PORT` (`18080 + slot`) | opened by `vm.sh web` |
| Host tunnel for `agent` | `127.0.0.1:WEB_PORT+1000` | opened by `vm.sh web` when `ROLE=ai` |
| SSH to the guest | `127.0.0.1:SSH_PORT` (`2300 + slot`) | always |

For `lin-ubuntu-ai`: SSH 2432, dev IDE 18212, agent IDE 19212. Your numbers come from the VM name (see [chapter 2](02-choosing-a-guest-and-role.md#sizing-and-resource-variables) for the one-liner that prints them). Override with `WEB_PORT=...` if it clashes; that one is host-only and safe to change at any time.

## Open it locally

```
$ GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh web
web IDE (admin dev): http://127.0.0.1:18212  (password: devvm)
web IDE (agent agent): http://127.0.0.1:19212  (password: devvm)
tunnel open, Ctrl-C to close
```

Open the URL in a browser on the host and enter the password. The command stays in the foreground (`ssh -N`); use another terminal, or background it with `&`. Ctrl-C closes the tunnel. The `dev` IDE opens in `dev`'s home; the `agent` IDE runs as `agent`, so it sees `/work/agent` and cannot see `dev`'s files.

## Why a plain password

The password is stored as clear text in `~/.config/code-server/config.yaml` (mode 600, owned by the user) and printed by `vm.sh web`. This is deliberate:

- the listener is loopback-inside-the-guest, reachable only after an authenticated SSH tunnel; the password is a second, convenience gate, not the perimeter;
- a hashed password would add a secret-generation step and a place to lose it, with no real benefit when the transport is already key-only SSH;
- a fixed default makes unattended provisioning and automation reproducible.

Consequences: the default `devvm` is public in this repository, and the password also sits in the cloud-init seed on the host (`~/vms/<VM_NAME>/seed.iso`, `0700` provision script in the guest). This is for lab use. Anyone who can SSH into the guest as that user can read it. Set your own `WEB_PASS`, and do not reuse a real password.

## Changing the password

At provision time: `WEB_PASS=...`. Afterwards, in the guest, edit `~/.config/code-server/config.yaml` for the relevant user (`password:` line) and restart:

```
dev$   sudo systemctl restart code-server@dev
agent$ # as dev:
dev$   sudo systemctl restart code-server@agent
```

`vm.sh web` prints whatever `WEB_PASS` is in your **host** environment, so after changing it in the guest, export the same `WEB_PASS` on the host or just ignore the printed value.

## Reach it from another machine

`vm.sh web` listens only on the host's `127.0.0.1`, so a laptop cannot connect directly. Chain a second SSH forward through the host. This uses plain `ssh`, not a repo feature.

Option A: tunnel to the host's tunnel (needs `./vm.sh web` running on the host):

```
laptop$ ssh -N -L 18212:127.0.0.1:18212 you@build-host
# in another terminal, or before, on build-host:  GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh web
laptop$ xdg-open http://127.0.0.1:18212            # browser on the laptop
```

For the agent IDE, add `-L 19212:127.0.0.1:19212` (or use a separate `-L`).

Option B: no `vm.sh web`, forward straight to the guest's SSH hostfwd and then to code-server (needs the guest key `~/.ssh/id_lindevvm` copied to the laptop):

```
laptop$ ssh -N -L 2222:127.0.0.1:2432 you@build-host &
laptop$ ssh -i ~/.ssh/id_lindevvm -p 2222 -N -L 8080:127.0.0.1:8080 dev@127.0.0.1
laptop$ # browse http://127.0.0.1:8080
```

(`2432` is `SSH_PORT`; port 8080 is the in-guest code-server; use 8081 for the agent IDE.) Add `-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=...` if you want host-key hygiene separate from your normal `known_hosts`. Do not bind these forwards to `0.0.0.0`: that would put the plain-password IDE on your LAN.

## Checking and restarting the service

```
$ ./vm.sh ssh 'systemctl status code-server@dev --no-pager | head -5'
$ ./vm.sh ssh 'ss -ltn | grep -E ":808[01]"'
LISTEN 0 511 127.0.0.1:8080 0.0.0.0:*
LISTEN 0 511 127.0.0.1:8081 0.0.0.0:*
$ ./vm.sh ssh 'cat /etc/devvm/README'          # includes the web IDE lines
```

## Pitfalls

- "Connection refused" in the browser: the tunnel is not running, `WEB_PORT` clashes with another process (SSH will say `Address already in use`), or code-server failed to start (check `systemctl status`).
- The browser may warn about nothing: `cert: false`, plain HTTP over a loopback tunnel. Do not put this behind a reverse proxy without adding TLS.
- Two VMs with the same `WEB_PORT` cannot both be tunnelled at once; ports come from the VM name, so this is rare, but see [chapter 7](07-troubleshooting-and-faq.md#port-clashes).
- The unit is `Restart=on-failure` and enabled for boot, so it comes back after `./vm.sh stop` / `start`.
