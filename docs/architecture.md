# Architecture
host: provision.sh -> lib/libvirt.sh (virt-install, user-mode NIC, hostfwd 127.0.0.1:SSH_PORT->22) -> cloud image overlay + NoCloud seed.
seed user-data = users (dev [+agent]) with the host key + one root script (devvm-provision.sh) composed from guest/common.sh + guests/<g>/setup.sh + roles/<role>.sh [+ roles/web.sh].
guest: reports progress in /var/lib/devvm-state (installing:<step> | DONE | FAILED:<step>); vm.sh wait polls it over SSH.
disks: disk.qcow2 (disposable overlay) + data.qcow2 (/work, ROLE=ai, kept by `reset`).
web: code-server on guest 127.0.0.1:8080 (+8081 for agent); `vm.sh web` = ssh -L. No host port is opened except the SSH hostfwd and the tunnel, both loopback.
