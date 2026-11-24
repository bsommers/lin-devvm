# lin-devvm User Manual

[← Back to Project README](../../README.md)

Task-oriented guide to creating and running unattended Linux dev VMs (rootless KVM/libvirt, cloud images, cloud-init, SSH-only access) with `lin-devvm`.

## Honest status

Only **Ubuntu 24.04 `ROLE=ai WEB=1`** has been live-booted (provision, user isolation, web login over the tunnel, `reset` keeping `/work`). The other guests (`kubuntu`, `debian`, `fedora`, `arch`, `omarchy`, `opensuse`, `rocky`) and `ROLE=dev` are covered by syntax, contract and script-composition tests only; treat them as untested until you have booted them. `omarchy` is best effort by design. Each chapter flags where this matters.

## Chapters

| # | Chapter | Read it to... |
|---|---|---|
| 1 | [Getting started](01-getting-started.md) | check prerequisites, create your first VM, log in |
| 2 | [Choosing a guest and role](02-choosing-a-guest-and-role.md) | pick `GUEST`, `ROLE`, `WEB`, and size resources |
| 3 | [The AI-coding VM](03-the-ai-coding-vm.md) | use the `agent`/`dev` split, `/work`, `devvm-agent-run`, tmux, Claude Code, `reset` |
| 4 | [Web IDE over SSH](04-web-ide-over-ssh.md) | open code-server through a tunnel, locally or from another machine |
| 5 | [Daily operations](05-daily-operations.md) | start/stop/status/push/pull/checkpoint/rollback/reset/destroy, several VMs |
| 6 | [Tracker and tests](06-tracker-and-tests.md) | run the live dashboard and the test suites |
| 7 | [Troubleshooting and FAQ](07-troubleshooting-and-faq.md) | fix KVM, libvirt, checksum, cloud-init, port, host-key problems |

## The 60-second picture

```
GUEST=ubuntu ROLE=ai WEB=1 ./provision.sh      # create + boot (returns quickly; guest installs in background)
GUEST=ubuntu ROLE=ai WEB=1 ./vm.sh wait        # block until DONE
GUEST=ubuntu ROLE=ai ./vm.sh ssh --agent       # log in
```

The one rule to remember: **`vm.sh` finds its VM from the same `GUEST` / `ROLE` / `VM_NAME` environment you gave `provision.sh`.** Different env, different VM (see [chapter 7](07-troubleshooting-and-faq.md#which-vm-does-vmsh-address)).

## Conventions

- Commands are run from the repository root on the host unless a prompt says `guest$`.
- Environment variables are shown inline (`GUEST=fedora ROLE=ai ./vm.sh status`); you can `export` them instead.
- All configuration lives in `config.env`; every value can be overridden from the environment.
