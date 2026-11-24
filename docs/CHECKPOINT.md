# Checkpoint (2026-11-24)
Repo: https://github.com/bsommers/lin-devvm (public, main, clean, all pushed; last commit ba24f7b).
Done: core (provision/vm/libvirt/cloud-init), 8 guests, roles dev/ai/web, tracker (:4790, `tools/track.sh serve`), tests+CI, full docs + usermanual.
Live-validated: ubuntu ROLE=ai WEB=1 (provision, user isolation, web tunnel login, reset keeps /work). Test VM lin-ubuntu-ai is stopped (state in ~/vms/lin-ubuntu-ai).
Untested: other guests, ROLE=dev, checkpoint/rollback, multi-VM.
Known gaps: OMARCHY_* env not forwarded to guest; desktop guests have no user password (graphical login); reset wipes /home; vm.sh web ignores WEB.
Next: boot-test fedora/debian/arch/rocky/opensuse/kubuntu; fix gaps above.
