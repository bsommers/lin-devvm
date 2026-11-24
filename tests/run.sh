#!/usr/bin/env bash
# Run all suites; writes .tracker/tests.json for the tracker page. Exit 0 iff all pass.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0; pass=0; fail=0; suites=""
for t in syntax.sh guests.sh compose.sh tracker.sh; do
  [ -f "$ROOT/tests/$t" ] || continue
  echo "== $t"
  if bash "$ROOT/tests/$t"; then st=pass; pass=$((pass+1)); else st=fail; fail=$((fail+1)); rc=1; fi
  suites="$suites{\"name\":\"$t\",\"status\":\"$st\"},"
done
mkdir -p "$ROOT/.tracker"
printf '{"t":"%s","passed":%d,"failed":%d,"total":%d,"suites":[%s]}\n' "$(date -u +%FT%TZ)" $pass $fail $((pass+fail)) "${suites%,}" > "$ROOT/.tracker/tests.json"
[ $rc -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit $rc
