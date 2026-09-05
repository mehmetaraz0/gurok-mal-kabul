// No DB URL input: all SQL runs inside a fresh, network-isolated test container.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';

const root = new URL('../', import.meta.url);
const container = `phase0-test-${randomUUID()}`;
const migration = readFileSync(new URL('docs/kurulum/2026-09-05-phase0-hardening.sql', root), 'utf8');
const preflight = readFileSync(new URL('docs/kurulum/2026-09-05-phase0-preflight.sql', root), 'utf8');
const [fixture, tests] = readFileSync(new URL('scripts/phase0-database-tests.sql', root), 'utf8')
  .split('-- PHASE0 FIXTURE END');
const psql = ['exec', '-i', container, 'psql', '-X', '-U', 'postgres', '-d', 'phase0_test', '-v', 'ON_ERROR_STOP=1'];
function docker(args, input) {
  const r = spawnSync('docker', args, { input, encoding: 'utf8', timeout: 180000, maxBuffer: 8 * 1024 * 1024 });
  if (r.error || r.status !== 0) throw new Error(r.error?.message || `${args[0]} failed:\n${r.stdout}\n${r.stderr}`);
  return r.stdout;
}
function query(sql) { return docker(psql, sql); }
let created = false;
try {
  docker(['version', '--format', '{{.Server.Version}}']);
  docker(['run', '--detach', '--rm', '--network', 'none', '--name', container,
    '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
  created = true;
  let ready = false;
  for (let i = 0; i < 60; i++) {
    const r = spawnSync('docker', ['exec', container, 'pg_isready', '-U', 'postgres'], { encoding: 'utf8' });
    if (r.status === 0) { ready = true; break; }
    await delay(1000);
  }
  assert.ok(ready, 'disposable PostgreSQL did not become ready');
  docker(['exec', container, 'createdb', '-U', 'postgres', 'phase0_test']);
  query(fixture);
  query(preflight);
  const originalHelper = query("select pg_get_functiondef('public.auth_otel_erisim(text)'::regprocedure);");
  query('create role phase0_fixture_writer nologin; grant update(marker) on public.satin_alma_talepleri to phase0_fixture_writer; grant phase0_fixture_writer to authenticated;');
  assert.throws(() => query(migration), /Unexpected inherited\/column grant/,
    'migration accepted an inherited protected-column grant');
  assert.equal(query("select pg_get_functiondef('public.auth_otel_erisim(text)'::regprocedure);"), originalHelper,
    'failed migration must restore pre-change helper definitions');
  query('revoke phase0_fixture_writer from authenticated; revoke update(marker) on public.satin_alma_talepleri from phase0_fixture_writer; drop role phase0_fixture_writer;');
  query('create function public.fatura_kaydet(text) returns void language plpgsql as $$ begin return; end; $$;');
  assert.throws(() => query(migration), /Unreviewed overload/);
  assert.equal(query("select pg_get_functiondef('public.auth_otel_erisim(text)'::regprocedure);"), originalHelper);
  query('drop function public.fatura_kaydet(text);');
  query(migration);
  query(migration); // Rerunning must not duplicate the entry guard or audit triggers.
  query(preflight);
  query(tests);
  console.log('A-F, I, J, audit/relationship/grant tests, migration rejection/rollback and reapplication passed (synthetic PostgreSQL fixture).');

  const insert = `insert into phase0_fixture.bookings(hotel_id,room_id,check_in,check_out,status)
    values('810','50000000-0000-0000-0000-000000000001','2026-11-01','2026-11-03','confirmed');`;
  const first = spawn('docker', psql, { stdio: ['pipe', 'pipe', 'pipe'] });
  let output = ''; let error = '';
  first.stderr.on('data', data => { error += data; });
  const closed = new Promise((resolve, reject) => {
    first.on('error', reject); first.on('close', code => resolve(code));
  });
  const held = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('concurrency barrier timed out')), 15000);
    first.stdout.on('data', data => {
      output += data;
      if (output.includes('PHASE0_LOCK_HELD')) { clearTimeout(timeout); resolve(); }
    });
    first.on('error', e => { clearTimeout(timeout); reject(e); });
    first.on('close', () => {
      clearTimeout(timeout);
      if (!output.includes('PHASE0_LOCK_HELD')) reject(new Error(error || 'first transaction stopped before barrier'));
    });
  });
  first.stdin.write(`begin;\n${insert}\n\\echo PHASE0_LOCK_HELD\n`);
  await held;
  // Start B while A is uncommitted; A is released only after B has started.
  const second = spawn('docker', psql, { stdio: ['pipe', 'pipe', 'pipe'] });
  let secondError = '';
  second.stdout.resume(); second.stderr.on('data', data => { secondError += data; });
  const secondClosed = new Promise((resolve, reject) => {
    second.on('error', reject); second.on('close', code => resolve(code));
  });
  second.stdin.end(`set application_name='phase0-second';\n${insert}\n`);
  let waiting = false;
  for (let i = 0; i < 50; i++) {
    if (query("select count(*) from pg_stat_activity where application_name='phase0-second' and wait_event_type='Lock';").includes(' 1')) {
      waiting = true; break;
    }
    await delay(100);
  }
  first.stdin.end('commit;\n');
  assert.equal(await closed, 0, error);
  assert.ok(waiting, 'second transaction must wait on the uncommitted conflicting stay');
  assert.notEqual(await secondClosed, 0, 'both concurrent overlapping reservations succeeded');
  assert.match(secondError, /exclusion constraint/i);
  query("select phase0_fixture.assert_true((select count(*)=1 from phase0_fixture.bookings where check_in='2026-11-01'),'H exactly one concurrent commit');");
  console.log('H passed: independent transactions overlapped, B waited, only A committed.');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (created) {
    const cleanup = spawnSync('docker', ['rm', '--force', container], { encoding: 'utf8', timeout: 30000 });
    if (cleanup.status !== 0) { console.error(`Test container cleanup failed: ${container}`); process.exitCode = 1; }
  }
}
