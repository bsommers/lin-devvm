# lin-devvm documentation

Unattended Linux dev VMs on a Linux host: rootless libvirt/KVM, vendor cloud images, cloud-init, SSH-only
on `127.0.0.1`. The quickstart is in [../README.md](../README.md).

## Reading order

1. [purpose.md](purpose.md): the problem, tenets, threat model, what is not hardened.
2. [architecture.md](architecture.md): layers, provisioning flow, cloud-init composition, state protocol,
   disks, ports, user isolation, web tunnel, tracker (with Mermaid diagrams).
3. [running.md](running.md): prerequisites, every variable, full CLI reference, files/ports, per-guest
   table, image checksum refresh, validation status.
4. [how-to.md](how-to.md): copy-paste recipes (AI VM, web IDE, agents, reset, checkpoint, several VMs,
   new guest, new role, image override, tracker, tests).
5. [usermanual/](usermanual/): the user manual.

## Other files

| File | Content |
|---|---|
| [diagrams/ascii_architecture.txt](diagrams/ascii_architecture.txt) | ASCII: provision flow, VM lifecycle incl. reset, network/tunnel, user isolation |
| [CHECKPOINT.md](CHECKPOINT.md) | Dated project status note (done / not yet booted / next) |

## Status in one line

Only Ubuntu 24.04 `ROLE=ai WEB=1` has been booted and validated end to end (provision, user isolation, web
login over the tunnel, `reset` keeping `/work`). Other guests and recipes are code-complete but untested live.
