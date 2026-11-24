# 6. Tracker and tests

[← Manual index](README.md) · [← Back to Project README](../../README.md)

## Contents
- [The tracker](#the-tracker)
- [track.sh reference](#tracksh-reference)
- [Files and API](#files-and-api)
- [Using it from agents](#using-it-from-agents)
- [The test suites](#the-test-suites)
- [Pitfalls](#pitfalls)

## The tracker

A zero-dependency Node dashboard (`tools/tracker/server.mjs`, needs `node` on the host) that shows a build plan, an event feed, the guest list, live `lin-*` VM state (via `virsh -c qemu:///session list --all`) and the last test results. It is a local helper for the project, separate from running VMs. `provision.sh` also posts events to it (`provision start`, `provision created`); these are silently dropped if the tracker is not running.

```
$ tools/track.sh serve
http://127.0.0.1:4790/
$ tools/track.sh serve
already running (pid 12345)
http://127.0.0.1:4790/
$ tools/track.sh url
http://127.0.0.1:4790/
$ tools/track.sh stop
stopped
```

## track.sh reference

| Command | Effect |
|---|---|
| `serve [port]` | start the server in the background (default port `TRACKER_PORT`=4790, host `TRACKER_HOST`=127.0.0.1); prints the URL; log in `.tracker/server.log` |
| `stop` | kill the server (`stopped` / `not running`) |
| `url` | print the last served URL |
| `event <agent> <state> <msg> [pct]` | append one JSON line to `.tracker/events/<agent>.jsonl` |

`event` validation: at least 4 arguments (else usage, exit 2); `agent` must match `[A-Za-z0-9._-]+` (`bad agent name`); `pct`, if given, must be an integer (`pct must be an integer`). Conventional states are `start | progress | done | failed | blocked | note`; the script does not enforce them.

```
$ tools/track.sh event docs start "writing the manual"
$ tools/track.sh event docs progress "chapters 1-3 done" 40
$ tools/track.sh event docs done "all chapters"
```

Each line looks like `{"t":"2026-11-23T10:00:00.000Z","agent":"docs","state":"progress","pct":40,"msg":"chapters 1-3 done"}`.

## Files and API

State lives in `.tracker/` at the repository root.

| File | Written by | Shape |
|---|---|---|
| `events/<agent>.jsonl` | `track.sh event` | `{"t","agent","state","pct","msg"}` per line |
| `plan.json` | you | `{"title","phases":[{"id","name","status","tasks":[{"name","status","owner"}]}]}`, status `todo\|doing\|done\|blocked` |
| `tests.json` | `tests/run.sh` | `{"t","passed","failed","total","suites":[{"name","status"}]}` |
| `server.pid`, `server.url`, `server.log` | `track.sh` | server bookkeeping |

HTTP endpoints: `GET /` (page), `GET /api/state` (JSON with keys `plan`, `agents`, `guests`, `vms`, `git`, `tests`), `GET /api/stream` (server-sent events, pushed on change). The server binds to `127.0.0.1` by default; reach it from another machine with an `ssh -L` tunnel to the host, as in [chapter 4](04-web-ide-over-ssh.md#reach-it-from-another-machine).

## Using it from agents

Because `event` is a one-line append, agents on the host (or any script) can report progress with it. Inside a guest there is no tracker; run the call on the host, for example from a wrapper around `./vm.sh ssh ...`.

## The test suites

```
$ bash tests/run.sh
== syntax.sh
syntax ok
== guests.sh
ok arch
ok debian
...
== compose.sh
ok   ubuntu role=dev web=0
...
== tracker.sh
PASS tracker
ALL SUITES PASSED
```

`tests/run.sh` runs four suites in order, writes `.tracker/tests.json`, and exits 0 only if all pass.

| Suite | Checks |
|---|---|
| `syntax.sh` | `bash -n` on all scripts and `guest.env` files; `shellcheck -x` on top-level, `lib/`, `roles/`, `guest/` scripts if `shellcheck` is installed (skipped silently otherwise) |
| `guests.sh` | every `guests/*/guest.env` defines `GUEST_LABEL GUEST_FAMILY OS_VARIANT DESKTOP IMAGE_URL IMAGE_FILE IMAGE_SUMS GUEST_BANNER` |
| `compose.sh` | for `GUEST` (default `ubuntu`) composes the in-guest script for `ROLE` dev/ai x `WEB` 0/1 and syntax-checks it (`GUEST=fedora bash tests/compose.sh` to pick another) |
| `tracker.sh` | starts the tracker on a random port, checks `/` returns 200 and `/api/state` has all keys; needs `node` and `curl` |

These are static and composition tests. They **do not boot a VM**, so a green run says nothing about whether a guest actually provisions; only Ubuntu `ROLE=ai WEB=1` has been booted by hand. CI (`.github/workflows/ci.yml`) installs shellcheck and runs `bash tests/run.sh` on push and pull request.

## Pitfalls

- `tests/run.sh` overwrites `.tracker/tests.json`; run it from a checkout you control.
- `track.sh serve` writes to `.tracker/` under the repo, so run it as a user who can write there.
- `track.sh stop` only kills a process whose `/proc/<pid>/cmdline` contains `node`; a stale pid file is removed.
- Port 4790 busy: `tools/track.sh serve 4791` or `TRACKER_PORT=4791`.
