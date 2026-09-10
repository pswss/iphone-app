import assert from 'node:assert/strict';
import worker, { tick } from './src/index.js';

// No APNs traffic: a throwaway signing key and in-memory KV exercise the real handlers.
const key = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const pem = Buffer.from(await crypto.subtle.exportKey('pkcs8', key.privateKey)).toString('base64');
const records = new Map();
const expirations = [];
const env = {
  REG_KEY: 'test-registration-key-only', APNS_AUTH_KEY: pem, APNS_KEY_ID: 'test', APPLE_TEAM_ID: 'test',
  SCHEDULES: {
    async put(name, value, options) { records.set(name, value); expirations.push(options.expiration); },
    async get(name) { return records.get(name); },
    async delete(name) { records.delete(name); },
    async list({ cursor }) { return cursor ? { keys: [{ name: 'dev:expired' }], list_complete: true } : { keys: [{ name: 'dev:test' }], list_complete: false, cursor: 'page-2' }; },
  },
};
let now = 1_800_000_000;
const clock = Date.now, originalFetch = globalThis.fetch;
Date.now = () => now * 1000;
let calls = 0, status = 503;
globalThis.fetch = async () => { calls++; return new Response(null, { status }); };
try {
  const register = () => worker.fetch(new Request('https://oneul.test/register', {
    method: 'POST', headers: { 'x-oneul-key': env.REG_KEY },
    body: JSON.stringify({ deviceID: 'test', updateToken: 'a'.repeat(64), staleAt: now + 86400, items: [{ at: now, event: 'update', state: { phase: 'gap' } }] }),
  }), env);
  assert.equal((await register()).status, 200);
  records.set('dev:expired', JSON.stringify({ staleAt: now - 1 }));
  await tick(env);
  let record = JSON.parse(records.get('dev:test'));
  assert.equal(record.items[0].sent, false);
  assert.equal(record.items[0].attempts, 1);
  assert.equal(records.has('dev:expired'), false, 'pagination must process the second page');
  await tick(env);
  assert.equal(calls, 1, 'backoff prevents immediate retry');
  now += 60; status = 200;
  await tick(env);
  record = JSON.parse(records.get('dev:test'));
  assert.equal(record.items[0].sentOK, true);
  assert.equal(record.items[0].attempts, 2);
  assert.equal(expirations.at(-1), expirations[0], 'retry must not extend retention');
  await register(); status = 400;
  await tick(env);
  assert.equal(JSON.parse(records.get('dev:test')).items[0].sent, true);
  const before = calls;
  now += 180;
  await tick(env);
  assert.equal(calls, before, 'permanent errors must not be refreshed');
  await register(); status = 503;
  for (let attempt = 0; attempt < 4; attempt++) { await tick(env); now += 180; }
  assert.equal(JSON.parse(records.get('dev:test')).items[0].attempts, 3);
  assert.equal((await worker.fetch(new Request('https://oneul.test/register', { method: 'POST' }), { REG_KEY: '' })).status, 401);
  console.log('Push retry, retention, pagination and permanent-failure checks passed');
} finally { Date.now = clock; globalThis.fetch = originalFetch; }
