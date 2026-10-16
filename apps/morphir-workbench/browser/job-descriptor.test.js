import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { JobClient } from './job-session.js';

// Use the production compiled cursor, with a fresh retained state per client.
const compiled = readFileSync(new URL('../dist/job-core.js', import.meta.url), 'utf8');
const core = () => {
  const context = { TextEncoder, TextDecoder, console };
  runInNewContext(compiled, context);
  return context.morphirWorkbenchJobs;
};
const version = '0.1.0-draft.1';
const offer = { profile: 'morphir/workbench/jobs', contractVersion: version,
  hostId: 'host', sessionId: 'session', providerId: 'scheme', operations: ['query', 'cancel'] };
const descriptor = { profile: 'morphir/workbench/native', contractVersion: version,
  sessionId: 'session', operations: ['jobs', 'workspace'], offer };
const identity = { hostId: 'host', sessionId: 'session', providerId: 'scheme', jobId: 'job', snapshotId: 'snapshot' };
const receipt = { contractVersion: version, identity, sequence: 0, state: 'submitted', cancelRequested: false, outcomes: null };
const terminal = { ...receipt, sequence: 1, state: 'terminal', outcomes: {
  contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '42' } } }],
  cleanup: null, extensions: null,
} };
const request = { source: '{}', entry: 'example:main#answer', arguments: [] };
const noHttp = () => { throw new Error('Native negotiation must not use HTTP'); };
function clientFor(raw) {
  return new JobClient('session', { core: core(), fetchFn: noHttp, transport: {
    async nativeDescriptor() { return raw; }, request: noHttp,
  } });
}

test('native descriptor transport admits original text with the compiled core and no HTTP descriptor', async () => {
  const client = clientFor(JSON.stringify(descriptor));
  assert.equal(await client.initialize(), true);
  assert.deepEqual(client.offer, descriptor);
  for (const operations of [[], ['workspace']]) {
    const { offer: _, ...withoutJobs } = descriptor;
    assert.equal(await clientFor(JSON.stringify({ ...withoutJobs, operations })).initialize(), false);
  }
  const boundary = JSON.stringify(descriptor);
  assert.equal(await clientFor(' '.repeat(1048576 - boundary.length) + boundary).initialize(), true);
  await assert.rejects(clientFor(' '.repeat(1048577 - boundary.length) + boundary).initialize(), /limit/);
});

test('native descriptor identifiers retain native ASCII and frozen jobs UTF-16 bounds', async () => {
  const handler = core();
  for (const sessionId of ['s'.repeat(128), 'a_Z.9-']) {
    const value = { ...descriptor, sessionId, offer: { ...offer, sessionId, providerId: '😀'.repeat(64) } };
    const reply = JSON.parse(handler(JSON.stringify({ op: 'native-descriptor', source: JSON.stringify(value), sessionId })));
    assert.equal(reply.ok, true);
    assert.deepEqual(reply.value, value);
  }
  const value = { ...descriptor, offer: { ...offer, operations: ['cancel', 'query'] } };
  assert.equal(await clientFor(JSON.stringify(value)).initialize(), true, 'Frozen offer ordering remains compatible');
});

test('native descriptor transport cannot switch admission based on an untrusted profile', async () => {
  for (const value of [
    null, descriptor,
    JSON.stringify({ profile: 'morphir/workbench/host', contractVersion: version, offer }),
    JSON.stringify({ ...descriptor, contractVersion: `${version}+build` }),
    JSON.stringify({ ...descriptor, operations: ['workspace', 'jobs'] }),
    JSON.stringify({ ...descriptor, offer: { ...offer, sessionId: 'other' } }),
    JSON.stringify({ ...descriptor, offer: { ...offer, providerId: '😀'.repeat(65) } }),
    JSON.stringify({ ...descriptor, offer: { ...offer, extra: true } }),
    JSON.stringify(descriptor).replace('"hostId":"host"', '"hostId":"host","ho\\u0073tId":"host"'),
    JSON.stringify(descriptor) + '{}',
  ]) await assert.rejects(clientFor(value).initialize(), /raw JSON text|rejected/);
  const http = new JobClient('session', { core: core(), fetchFn: async () => new Response(JSON.stringify(descriptor)) });
  await assert.rejects(http.initialize(), /incompatible/);
  const httpValid = new JobClient('session', { core: core(), fetchFn: async () => new Response(JSON.stringify({
    profile: 'morphir/workbench/host', contractVersion: version, offer,
  })) });
  assert.equal(await httpValid.initialize(), true);
});

function reconnectFixture(nextDescriptor = descriptor) {
  let checks = 0, queries = 0;
  const requests = [];
  const client = new JobClient('session', { core: core(), fetchFn: noHttp, pause: async () => {},
    authenticate: async () => 'session', transport: {
      async nativeDescriptor() { return JSON.stringify(++checks === 1 ? descriptor : nextDescriptor); },
      async request(operation) {
        requests.push(operation);
        if (operation === 'query' && ++queries === 1) throw new Error('Lost native reply');
        const value = operation === 'submit' ? { identity, calls: ['workbench'], receipt } :
          operation === 'query' ? terminal : { released: true };
        return { ok: true, status: 200, source: JSON.stringify(value) };
      },
    } });
  return { client, requests, checks: () => checks };
}

test('native descriptor reconciliation retains the same cursor and submits only once', async () => {
  const fixture = reconnectFixture(), { client, requests } = fixture;
  assert.equal(await client.initialize(), true);
  await assert.rejects(client.execute(request), /Lost native reply/);
  assert.equal(client.job.connected, false); assert.equal(client.job.sequence, 0);
  const result = await client.resume();
  assert.deepEqual(result.typed, { type: 'int', value: '42' });
  assert.equal(result.job.state, 'terminal'); assert.equal(client.releasePending, false);
  assert.deepEqual(requests, ['submit', 'query', 'query', 'release']);
  assert.equal(fixture.checks(), 2);
});

test('changed native authority and withdrawn jobs leave retained evidence disconnected', async () => {
  const { offer: _, ...withoutJobs } = descriptor;
  for (const next of [
    { ...descriptor, offer: { ...offer, hostId: 'new-host' } },
    { ...descriptor, offer: { ...offer, providerId: 'new-provider' } },
    { ...descriptor, offer: { ...offer, operations: ['query'] } },
    { ...descriptor, operations: ['jobs'] },
    { ...withoutJobs, operations: ['workspace'] },
  ]) {
    const { client, requests } = reconnectFixture(next);
    await client.initialize();
    await assert.rejects(client.execute(request), /Lost native reply/);
    const before = structuredClone(client.job);
    await assert.rejects(client.resume(), /rejected|no longer offers|capabilities changed/);
    assert.deepEqual(client.job, before);
    assert.deepEqual(requests, ['submit', 'query']);
  }
});
