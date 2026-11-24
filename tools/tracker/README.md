# tracker
Live local dashboard. `tools/track.sh serve [port]` (default 127.0.0.1:4790, `TRACKER_PORT`), `stop`, `url`,
`event <agent> <state> <msg> [pct]` appends to `.tracker/events/<agent>.jsonl`.

Files in `.tracker/`:
- `events/<agent>.jsonl`: `{"t","agent","state","pct","msg"}` (state: start|progress|done|failed|blocked|note)
- `plan.json`: `{"phases":[{"id","name","status","tasks":[{"name","status","owner"}]}]}`, status = todo|doing|done|blocked
- `tests.json` (from tests/run.sh): `{"t","passed","failed","total","suites":[{"name","status"}]}`

API: `/api/state` (JSON), `/api/stream` (SSE). Guests are read from `guests/*/guest.env` (LABEL, FAMILY, DESKTOP, IMAGE_SHA256/IMAGE_VERIFIED).
