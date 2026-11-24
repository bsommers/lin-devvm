#!/usr/bin/env node
// lin-devvm build tracker: zero-dependency live dashboard.
//   TRACKER_PORT=4790 TRACKER_HOST=127.0.0.1 TRACKER_ROOT=<repo> node tools/tracker/server.mjs
// Files (under <repo>/.tracker/):
//   events/<agent>.jsonl  one JSON per line: {"t":ISO,"agent":"x","state":"start|progress|done|failed|blocked|note","pct":0-100,"msg":"..."}
//   plan.json  {"title":"..","phases":[{"id":"core","name":"Core","status":"todo|doing|done|blocked",
//               "tasks":[{"name":"..","status":"todo|doing|done|blocked","owner":"agent"}]}]}
//   tests.json (optional, written by tests/run.sh) {"t":ISO,"passed":N,"failed":N,"total":N,"suites":[{"name","status"}]}
// Endpoints: GET / (page), GET /api/state (JSON), GET /api/stream (SSE, pushes state on change).
import http from 'node:http';
import fs from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(process.env.TRACKER_ROOT || join(HERE, '..', '..'));
const PORT = Number(process.env.TRACKER_PORT || 4790);
const HOST = process.env.TRACKER_HOST || '127.0.0.1';
const TRK = join(ROOT, '.tracker');

const rd = p => { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } };
const rj = p => { try { return JSON.parse(rd(p)); } catch { return null; } };
const sh = (cmd, args, ms = 4000) => new Promise(res =>
  execFile(cmd, args, { cwd: ROOT, timeout: ms, maxBuffer: 1 << 20 }, (e, out) => res(e ? null : out)));

let lastPlan = null;
function events() {
  const dir = join(TRK, 'events'), agents = {};
  let files = []; try { files = fs.readdirSync(dir).filter(f => f.endsWith('.jsonl')); } catch {}
  for (const f of files) {
    const evs = [];
    for (const l of (rd(join(dir, f)) || '').split('\n')) {
      if (!l.trim()) continue;
      try { const e = JSON.parse(l); if (e && typeof e === 'object') evs.push(e); } catch {}
    }
    const id = f.replace(/\.jsonl$/, '');
    const last = evs[evs.length - 1] || {};
    let pct = null; for (const e of evs) if (typeof e.pct === 'number') pct = e.pct;
    agents[id] = { id, state: last.state || '', pct, msg: last.msg || '', t: last.t || '', count: evs.length, events: evs.slice(-60) };
  }
  return agents;
}
function guests() {
  const dir = join(ROOT, 'guests'), out = [];
  let ds = []; try { ds = fs.readdirSync(dir, { withFileTypes: true }).filter(d => d.isDirectory()); } catch {}
  for (const d of ds) {
    const txt = rd(join(dir, d.name, 'guest.env')) || '';
    const get = k => { const m = txt.match(new RegExp('^\\s*(?:export\\s+)?' + k + '=(.*)$', 'm')); return m ? m[1].replace(/\s+#.*$/, '').replace(/^["']|["']$/g, '').trim() : ''; };
    const dk = (get('DESKTOP') || get('GUEST_DESKTOP')).toLowerCase();
    const sum = get('IMAGE_SHA256') || get('IMG_SHA256') || get('IMAGE_SHA512') || get('IMAGE_CHECKSUM') || get('IMAGE_SUM');
    const ver = get('IMAGE_VERIFIED') || get('VERIFIED');
    out.push({ id: d.name, label: get('LABEL') || get('GUEST_LABEL') || get('NAME') || d.name, family: get('FAMILY') || get('GUEST_FAMILY'),
      desktop: !!dk && !['0', 'no', 'none', 'false', ''].includes(dk),
      verified: /^(1|yes|true)$/i.test(ver) || (!!sum && !/^(0|none|skip)$/i.test(sum)) });
  }
  return out;
}
async function state() {
  const [virsh, branch, status, log] = await Promise.all([
    sh('virsh', ['-c', 'qemu:///session', 'list', '--all']),
    sh('git', ['rev-parse', '--abbrev-ref', 'HEAD']),
    sh('git', ['status', '--porcelain']),
    sh('git', ['log', '-5', '--format=%h %s'])]);
  const vms = virsh == null ? null : virsh.split('\n').slice(2).map(l => l.trim().split(/\s{2,}|\s+(?=running|shut off|paused|idle)/)).filter(a => a.length >= 2 && /^lin-/.test(a[1]))
    .map(a => ({ name: a[1], state: a.slice(2).join(' ') }));
  const lines = status ? status.split('\n').filter(Boolean) : [];
  const p = rj(join(TRK, 'plan.json')); if (p) lastPlan = p;
  return { now: new Date().toISOString(), root: ROOT, plan: lastPlan || { phases: [] }, agents: events(), guests: guests(), vms,
    git: branch == null ? null : { branch: branch.trim(), changed: lines.length, untracked: lines.filter(l => l.startsWith('??')).length, log: (log || '').split('\n').filter(Boolean) },
    tests: rj(join(TRK, 'tests.json')) };
}

const clients = new Set(); let lastJson = '';
setInterval(async () => {
  if (!clients.size) return;
  const j = JSON.stringify(await state()); const k = j.replace(/"now":"[^"]*"/, '');
  if (k === lastJson) return; lastJson = k;
  for (const c of clients) c.write('data: ' + j + '\n\n');
}, 1500);

http.createServer(async (req, res) => {
  const u = (req.url || '/').split('?')[0];
  if (u === '/' || u === '/index.html') {
    const h = rd(join(HERE, 'index.html'));
    res.writeHead(h ? 200 : 404, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' }); return res.end(h || 'missing index.html');
  }
  if (u === '/api/state') { res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' }); return res.end(JSON.stringify(await state())); }
  if (u === '/api/stream') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
    res.write('data: ' + JSON.stringify(await state()) + '\n\n'); clients.add(res); req.on('close', () => clients.delete(res)); return;
  }
  res.writeHead(404, { 'content-type': 'text/plain' }); res.end('not found');
}).listen(PORT, HOST, () => console.log(`tracker http://${HOST}:${PORT}/ root=${ROOT}`));
process.on('uncaughtException', e => console.error('uncaught', e && e.stack || e));
