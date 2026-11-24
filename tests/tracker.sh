#!/usr/bin/env bash
# Smoke test for the tracker server.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=$((20000 + RANDOM % 20000))
TRACKER_PORT=$PORT TRACKER_ROOT="$ROOT" node "$ROOT/tools/tracker/server.mjs" >/dev/null 2>&1 &
SP=$!; trap 'kill $SP 2>/dev/null || true' EXIT
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$PORT/api/state" >/dev/null 2>&1 && break; sleep 0.1; done
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/"); [[ $code == 200 ]] || { echo "FAIL index $code"; exit 1; }
curl -s "http://127.0.0.1:$PORT/api/state" | node -e '
const s=JSON.parse(require("fs").readFileSync(0,"utf8"));
for(const k of ["plan","agents","guests","vms","git","tests"]) if(!(k in s)) {console.error("FAIL missing key "+k);process.exit(1)}'
echo "PASS tracker"
