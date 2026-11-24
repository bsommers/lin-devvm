# Checkpoint (2026-11-24)
Repo https://github.com/bsommers/lin-devvm (public, main).
Live boot-tested ROLE=ai WEB=1: ubuntu, kubuntu(KDE ok), debian, fedora, arch, rocky, opensuse -> DONE, isolation ok, web IDE loopback-only. omarchy: Arch base OK, Omarchy install.sh blocked by its guard (limine+btrfs) - documented partial.
Fixes this round: q35 machine forced (rocky), secure-boot off for arch/omarchy, SELinux bin_t relabel of code-server node (fedora/rocky), EPEL best-effort htop/ripgrep (rocky), sha512 sums (debian).
Test VMs lin-*-ai are stopped (state ~/vms/lin-*-ai; `vm.sh destroy` to reclaim disk).
Untested: ROLE=dev live, checkpoint/rollback, multi-VM (partly exercised: 5 ran concurrently OK).
Known gaps: OMARCHY_* env not forwarded; desktop guests have no user password; reset wipes /home.
