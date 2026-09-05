import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const html = readFileSync(new URL('index.html', root), 'utf8');
const inline = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
  .filter(m => !/\bsrc\s*=/.test(m[1])).map(m => m[2]);
const main = inline.find(s => s.includes('const MODULLER ='));

function portal(fetch = async () => ({ ok: true, json: async () => [] })) {
  const nodes = new Map();
  const frames = [];
  const storage = new Map([['araz_portal_session', 'old session'], ['configuration', 'keep']]);
  function element(id) {
    if (!nodes.has(id)) {
      const classes = new Set();
      nodes.set(id, {
        id, textContent: 'old private data', innerHTML: 'old private data', dataset: {},
        classList: {
          add: x => classes.add(x), remove: x => classes.delete(x), contains: x => classes.has(x),
          toggle(x, enabled) { if (enabled) classes.add(x); else classes.delete(x); }
        },
        replaceChildren() { this.innerHTML = ''; this.textContent = ''; },
        remove() { this.removed = true; nodes.delete(id); }
      });
    }
    return nodes.get(id);
  }
  const context = vm.createContext({
    console, URLSearchParams, setTimeout: () => 0, clearTimeout() {},
    fetch, SB_URL: 'https://invalid.example', SB_KEY: 'test-only', SB_HEADERS: {},
    SESSION_KEY: 'araz_portal_session', navigator: {},
    sessionStorage: { removeItem: k => storage.delete(k) },
    oturumGetir: () => null, oturumKaydet: () => storage.set('araz_portal_session', 'new session'),
    sbHeaderlarYenile() {}, pinBasarisizKaydet() {}, pinBasariliTemizle() {}, pinKilitliMi: () => 0,
    kullaniciYetkileriGetir: async () => ({ stok_takip: 'kayit' }),
    location: { search: '', replace() {} },
    window: { addEventListener() {} },
    document: {
      addEventListener() {}, getElementById: element,
      querySelector: selector => element(selector),
      querySelectorAll: selector => selector.includes('iframe') || selector.includes('data-tab-id')
        ? frames.filter(f => !f.removed) : []
    }
  });
  vm.runInContext(main, context);
  return { context, element, frames, storage, run: code => vm.runInContext(code, context) };
}

test('all inline portal scripts parse', () => {
  for (const script of inline) new vm.Script(script);
});

test('G: logout destroys frames, clears staff state/UI, and preserves configuration', () => {
  const p = portal();
  p.frames.push(p.element('old-frame'));
  p.element('screen-portal').classList.add('active');
  p.element('screen-login').classList.add('hidden');
  const moduleCount = p.run('MODULLER.length');
  p.run(`currentUser = {id:'old', ad:'Private Staff'}; users = [currentUser];
    GORUNUR_MODULLER = [MODULLER[0]]; pinValue = '987654';
    SEKMELER.push({id:'old',ad:'Private document',kapatilabilir:true}); AKTIF_SEKME = 'old'; logout();`);
  assert.equal(p.frames[0].removed, true);
  assert.equal(p.run('currentUser'), null);
  assert.equal(p.run('users.length + GORUNUR_MODULLER.length'), 0);
  assert.equal(p.run('SEKMELER.length'), 1);
  assert.equal(p.run('AKTIF_SEKME'), 'home');
  assert.equal(p.run('pinValue'), '');
  assert.equal(p.run('MODULLER.length'), moduleCount);
  assert.equal(p.storage.has('araz_portal_session'), false);
  assert.equal(p.storage.get('configuration'), 'keep');
  for (const id of ['header-user-name', 'header-user-rol', 'header-avatar', 'welcome-text',
    'welcome-sub', 'welcome-date', 'kpi-talep', 'kpi-onay', 'kpi-skt', 'kpi-kullanici', 'toast']) {
    assert.equal(p.element(id).textContent, '', id);
  }
  assert.equal(p.element('modules-grid').innerHTML, '');
  assert.equal(p.element('sidebar-nav').innerHTML, '');
  assert.equal(p.element('screen-portal').classList.contains('active'), false);
  assert.equal(p.element('screen-login').classList.contains('hidden'), false);
});

test('a pending login cannot recreate a logged-out session', async () => {
  let resolve;
  const p = portal(() => new Promise(r => { resolve = r; }));
  const request = p.run("pinValue = '987654'; checkPin()");
  p.run('logout()');
  resolve({ json: async () => ({ ok: true, kullanici: { id: 'old' }, access_token: 'old-token' }) });
  await request;
  assert.equal(p.run('currentUser'), null);
  assert.equal(p.storage.has('araz_portal_session'), false);
});

test('old user-directory JSON cannot repopulate state after staff change', async () => {
  let resolve;
  const json = new Promise(r => { resolve = r; });
  const p = portal(async () => ({ ok: true, json: () => json }));
  const request = p.run("currentUser = {id:'old'}; loadUsers()");
  await Promise.resolve();
  p.run("logout(); currentUser = {id:'new'};");
  resolve([{ id: 'old-private-record' }]);
  await request;
  assert.equal(p.run('users.length'), 0);
});

test('old permission and KPI requests cannot restore a previous portal', async () => {
  const p = portal();
  let resolvePermissions;
  p.context.kullaniciYetkileriGetir = () => new Promise(r => { resolvePermissions = r; });
  const showing = p.run("currentUser = {id:'old',ad:'Old Staff',rol:'depo'}; showPortal()");
  p.run('logout()');
  resolvePermissions({ stok_takip: 'tam' });
  await showing;
  assert.equal(p.run('GORUNUR_MODULLER.length'), 0);
  assert.equal(p.element('modules-grid').innerHTML, '');
  const pending = [];
  p.context.fetch = () => new Promise(resolve => pending.push(resolve));
  const kpis = p.run("currentUser = {id:'old'}; loadKpiler()");
  p.run('logout()');
  for (const resolve of pending) resolve({ ok: true, json: async () => [{ id: 'old' }] });
  await kpis;
  assert.equal(p.element('kpi-talep').textContent, '');
});

test('a new staff login gets fresh navigation and no old tabs', async () => {
  const p = portal();
  p.run("currentUser = {id:'old'}; logout(); currentUser = {id:'new',ad:'New Staff',rol:'depo'};");
  await p.run('showPortal()');
  assert.equal(p.element('header-user-name').textContent, 'New Staff');
  assert.equal(p.run('SEKMELER.length'), 1);
  assert.equal(p.run('GORUNUR_MODULLER.length'), 2);
  assert.equal(p.run('GORUNUR_MODULLER[0].id'), 'stok');
  assert.equal(p.run('GORUNUR_MODULLER[1].id'), 'urunYonetimi');
});
