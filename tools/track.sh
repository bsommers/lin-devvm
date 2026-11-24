#!/usr/bin/env bash
# track.sh event <agent> <state> <msg> [pct] | serve [port] | stop | url
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRK="$ROOT/.tracker"; PID="$TRK/server.pid"
PORT="${TRACKER_PORT:-4790}"; HOST="${TRACKER_HOST:-127.0.0.1}"
mkdir -p "$TRK/events"
alive() { [[ -s $PID ]] && kill -0 "$(cat "$PID")" 2>/dev/null && grep -q node "/proc/$(cat "$PID")/cmdline" 2>/dev/null; }
case "${1:-}" in
  event)
    [[ $# -ge 4 ]] || { echo "usage: track.sh event <agent> <state> <msg> [pct]" >&2; exit 2; }
    agent="$2" state="$3" msg="$4" pct="${5:-}"
    [[ $agent =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad agent name" >&2; exit 2; }
    [[ -z $pct || $pct =~ ^[0-9]+$ ]] || { echo "pct must be an integer" >&2; exit 2; }
    t="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
    esc() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/}; printf '%s' "$s"; }
    line="{\"t\":\"$t\",\"agent\":\"$(esc "$agent")\",\"state\":\"$(esc "$state")\""
    [[ -n $pct ]] && line+=",\"pct\":$pct"
    printf '%s,"msg":"%s"}\n' "$line" "$(esc "$msg")" >> "$TRK/events/$agent.jsonl" ;;
  serve)
    [[ -n ${2:-} ]] && PORT="$2"
    if alive; then echo "already running (pid $(cat "$PID"))"; echo "http://$HOST:$PORT/"; exit 0; fi
    TRACKER_PORT="$PORT" TRACKER_HOST="$HOST" TRACKER_ROOT="$ROOT" nohup node "$ROOT/tools/tracker/server.mjs" >> "$TRK/server.log" 2>&1 &
    echo $! > "$PID"; echo "http://$HOST:$PORT/" > "$TRK/server.url"; echo "http://$HOST:$PORT/" ;;
  stop)
    if alive; then kill "$(cat "$PID")"; echo stopped; else echo "not running"; fi; rm -f "$PID" ;;
  url) cat "$TRK/server.url" 2>/dev/null || echo "http://$HOST:$PORT/" ;;
  *) echo "usage: track.sh event <agent> <state> <msg> [pct] | serve [port] | stop | url" >&2; exit 2 ;;
esac
