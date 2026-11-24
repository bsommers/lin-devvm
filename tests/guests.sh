#!/usr/bin/env bash
# Every guest.env must define the contract variables.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; rc=0
for d in "$ROOT"/guests/*/; do
  g="$(basename "$d")"
  out="$(cd "$ROOT" && GUEST=$g HERE=$ROOT bash -c 'source ./config.env; for v in GUEST_LABEL GUEST_FAMILY OS_VARIANT DESKTOP IMAGE_URL IMAGE_FILE IMAGE_SUMS GUEST_BANNER; do [ -n "${!v:-}" ] || echo "missing $v"; done' 2>&1)"
  if [ -n "$out" ]; then echo "FAIL $g: $out"; rc=1; else echo "ok $g"; fi
done
exit $rc
