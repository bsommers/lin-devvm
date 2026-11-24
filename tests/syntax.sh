#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; rc=0
for f in "$ROOT"/*.sh "$ROOT"/lib/*.sh "$ROOT"/guest/*.sh "$ROOT"/roles/*.sh "$ROOT"/guests/*/*.sh "$ROOT"/guests/*/guest.env "$ROOT"/tools/*.sh "$ROOT"/config.env; do
  [ -f "$f" ] || continue; bash -n "$f" || { echo "FAIL syntax $f"; rc=1; }
done
if command -v shellcheck >/dev/null; then shellcheck -x "$ROOT"/*.sh "$ROOT"/lib/*.sh "$ROOT"/roles/*.sh "$ROOT"/guest/*.sh || rc=1; fi
[ $rc -eq 0 ] && echo "syntax ok"; exit $rc
