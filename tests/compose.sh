#!/usr/bin/env bash
# Compose the guest provision script like provision.sh does and syntax-check it.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0
G="${GUEST:-ubuntu}"
if [[ ! -r "$HERE/guests/$G/guest.env" ]]; then echo "SKIP: guests/$G/guest.env not present"; exit 0; fi
# shellcheck disable=SC2015
for role in dev ai; do for web in 0 1; do
  out="$(mktemp)"
  (
    export GUEST="$G" ROLE="$role" WEB="$web"
    # shellcheck source=/dev/null
    source "$HERE/config.env" || exit 1
    {
      echo '#!/usr/bin/env bash'
      for v in GUEST GUEST_FAMILY ROLE WEB ADMIN_USER AGENT_USER WEB_PASS WEB_PORT_GUEST DESKTOP DESKTOP_ENV DATA_DISK_GB VM_NAME; do
        printf 'export DEVVM_%s=%q\n' "$v" "${!v:-}"
      done
      cat "$HERE/guest/common.sh"
      [[ -r "$HERE/guests/$GUEST/setup.sh" ]] && cat "$HERE/guests/$GUEST/setup.sh"
      cat "$HERE/roles/$ROLE.sh"
      [[ "$WEB" == 1 ]] && cat "$HERE/roles/web.sh"
      echo 'devvm_finish'
    } > "$out"
    bash -n "$out"
  ) && echo "ok   $G role=$role web=$web" || { echo "FAIL $G role=$role web=$web"; rc=1; }
  rm -f "$out"
done; done
exit $rc
