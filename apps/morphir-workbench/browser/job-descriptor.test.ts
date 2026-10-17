import type { JobOptions, Json } from './contracts.ts';
import { workbenchError } from '../../../types/data.ts';
import { malformed } from '../../../tests/helpers.ts';
interface Frame { operation: string; sessionId: string; profile: string; contractVersion: string; payload: Record<string, Json>; }
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { JobClient } from './job-session.ts';

import { core } from './native-test-fixture.ts';
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
function clientFor(raw: unknown) {
  return new JobClient('session', { core: core(), fetchFn: noHttp, transport: {
    async nativeDescriptor() { return malformed<string>(raw); }, nativeRequest: noHttp,
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

function reconnectFixture(nextDescriptor: unknown = descriptor) {
  let checks = 0, queries = 0;
  const requests: string[] = [];
  const client = new JobClient('session', { core: core(), fetchFn: noHttp, pause: async () => {},
    authenticate: async () => 'session', transport: {
      async nativeDescriptor() { return JSON.stringify(++checks === 1 ? descriptor : nextDescriptor); },
      async nativeRequest(source) {
        const { operation: nativeOperation } = JSON.parse(source);
        const operation = nativeOperation.slice(4);
        requests.push(operation);
        if (operation === 'query' && ++queries === 1) throw new Error('Lost native reply');
        const value = operation === 'submit' ? { identity, calls: ['workbench'], receipt } :
          operation === 'query' ? terminal : { released: true };
        return JSON.stringify({ ok: true, operation: nativeOperation, value });
      },
    } });
  return { client, requests, checks: () => checks };
}

test('native descriptor reconciliation retains the same cursor and submits only once', async () => {
  const fixture = reconnectFixture(), { client, requests } = fixture;
  assert.equal(await client.initialize(), true);
  await assert.rejects(client.execute(request), /reply.*unknown/);
  assert.equal(client.job!.connected, false); assert.equal(client.job!.sequence, 0);
  const result = await client.resume();
  assert.deepEqual(result.typed, { type: 'int', value: '42' });
  assert.equal(result.job!.state, 'terminal'); assert.equal(client.releasePending, false);
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
    const { client, requests } = reconnectFixture(next!);
    await client.initialize();
    await assert.rejects(client.execute(request), /reply.*unknown/);
    const before = structuredClone(client.job);
    await assert.rejects(client.resume(), /rejected|no longer offers|capabilities changed/);
    assert.deepEqual(client.job, before);
    assert.deepEqual(requests, ['submit', 'query']);
  }
});

const nativeError = (code: string, effect: string, message = 'The request was rejected.') => JSON.stringify({ ok: false, error: { code, effect, message } });
function nativeFixture(respond?: (frame: Frame, frames: Frame[]) => unknown | Promise<unknown>, options: JobOptions = {}) {
  const frames: Frame[] = [];
  const client = new JobClient('session', { core: core(), fetchFn: noHttp, pause: async () => {},
    authenticate: async () => 'session', ...options, transport: {
      async nativeDescriptor() { return JSON.stringify(descriptor); },
      async nativeRequest(source) {
        const frame = JSON.parse(source); frames.push(frame);
        assert.equal(frame.profile, 'morphir/workbench/native'); assert.equal(frame.contractVersion, version);
        assert.equal(frame.sessionId, 'session');
        const custom = await respond?.(frame, frames);
        if (custom !== undefined) return malformed<string>(custom);
        const value = frame.operation === 'job.submit' ? { identity, calls: ['workbench'], receipt } :
          frame.operation === 'job.query' ? (frames.some(f => f.operation === 'job.cancel') ? { ...terminal, sequence: 2, cancelRequested: true } : terminal) : frame.operation === 'job.cancel' ? { ...receipt, sequence: 1, cancelRequested: true } : { released: true };
        return JSON.stringify({ ok: true, operation: frame.operation, value });
      },
    } });
  return { client, frames };
}

test('only an admitted native no-effect error permits another explicit submit', async () => {
  for (const code of ['invalid_request', 'unauthorized', 'unavailable', 'not_found', 'conflict', 'limit']) {
    for (const effect of ['none', 'unknown']) {
      const { client, frames } = nativeFixture((_, frames) => frames.length === 1 ? nativeError(code, effect) : undefined);
      await client.initialize();
      await assert.rejects(client.execute(request), cause => { const error=workbenchError(cause);
        assert.equal(error.code, code); assert.equal(error.effect, effect); assert.equal(error.status, undefined);
        assert.equal(error.rejected, effect === 'none'); return true;
      });
      assert.equal(frames.length, 1, 'No automatic retry');
      assert.equal(client.uncertainSubmission, effect === 'unknown');
      if (effect === 'none') {
        assert.equal((await client.execute(request)).typed!.value, '42');
        assert.equal(frames.filter(f => f.operation === 'job.submit').length, 2);
      } else {
        await assert.rejects(client.execute(request), /unknown/);
        assert.equal(frames.length, 1);
      }
    }
  }
});

test('lost and malformed native replies cannot manufacture a no-effect rejection', async () => {
  const bad = [
    () => { throw Object.assign(new Error('Framework failure'), { rejected: true, effect: 'none', status: 400 }); },
    () => nativeError('unavailable', 'none').replace('"effect":"none"', '"effect":"none","effect":"unknown"'),
    () => JSON.stringify({ ok: false, status: 400, error: { code: 'unavailable', effect: 'none', message: 'Rejected' } }),
    () => JSON.stringify({ ok: false, error: { code: 'unavailable', message: 'Rejected' } }),
    () => nativeError('workbench.host_unknown_job', 'none'),
    () => JSON.stringify({ ok: true, operation: 'job.query', value: receipt }),
    () => ({ status: 400, source: nativeError('unavailable', 'none') }),
    () => 'x'.repeat(1048577),
  ];
  for (const respond of bad) {
    const { client, frames } = nativeFixture(respond); await client.initialize();
    await assert.rejects(client.execute(request), error => workbenchError(error).submissionUnknown === true);
    assert.equal(client.uncertainSubmission, true); assert.equal(client.job, null);
    await assert.rejects(client.execute(request), /unknown/); assert.equal(frames.length, 1);
  }
});

test('native preflight bounds the complete request and preserves original Ion input source', async () => {
  const { client, frames } = nativeFixture(); await client.initialize();
  const body = { contractVersion: version, model: '{}', entry: request.entry, inputs: { format: 'json', source: '[]' } };
  const overhead = new TextEncoder().encode(client.encodeRequest('submit', body)).length;
  const source = ' '.repeat(1048576 - overhead) + '{}';
  await assert.rejects(client.execute({ ...request, source: source + ' ' }), /complete.*frame limit/);
  assert.equal(client.uncertainSubmission, false); assert.equal(client.active, false); assert.equal(frames.length, 0);
  assert.equal((await client.execute({ ...request, source })).typed!.value, '42');
  assert.equal(new TextEncoder().encode(JSON.stringify(frames[0])).length, 1048576);
  assert.equal(frames[0]!.payload.model, source);
  const ion = '$ion_1_0 [1.0000000000000000001d0, meta::"😀"]';
  const ionFixture = nativeFixture(); await ionFixture.client.initialize();
  await ionFixture.client.execute({ ...request, argumentsIon: ion });
  assert.deepEqual(ionFixture.frames[0]!.payload.inputs, { format: 'ion-text', source: ion });
});

test('native cancellation acknowledges a request before admitting terminal evidence', async () => {
  let proceed; const waiting = new Promise<void>(resolve => { proceed = resolve; });
  const { client, frames } = nativeFixture(undefined, { pause: () => waiting });
  await client.initialize(); const result = client.execute(request);
  while (!client.job) await new Promise(resolve => setImmediate(resolve));
  await client.cancel();
  assert.equal(client.job.cancelRequested, true); assert.equal(client.job.state, 'submitted');
  assert.equal(frames.at(-1)!.operation, 'job.cancel');
  proceed!(); assert.equal((await result).job!.state, 'terminal');
});

test('native release absence confirms cleanup only after fresh matching authority and no effect', async () => {
  for (const effect of ['none', 'unknown']) {
    const { client, frames } = nativeFixture(frame => frame.operation === 'job.release' ? nativeError('not_found', effect) : undefined);
    await client.initialize(); const result = await client.execute(request);
    assert.equal(result.job!.state, 'terminal'); assert.equal(client.releasePending, true);
    if (effect === 'none') {
      assert.equal((await client.resume()).typed!.value, '42'); assert.equal(client.releasePending, false);
    } else {
      await assert.rejects(client.resume(), /rejected/); assert.equal(client.releasePending, true);
    }
    assert.equal(frames.filter(f => f.operation === 'job.submit').length, 1);
    assert.equal(frames.filter(f => f.operation === 'job.release').length, 2);
  }
});

test('native hooks must be paired before any HTTP fallback can occur', () => {
  for (const transport of [{ nativeDescriptor() {} }, { nativeRequest() {} }]) {
    assert.throws(() => new JobClient('session', { fetchFn: noHttp, transport: malformed(transport) }), /paired/);
  }
});

test('compiled native session opening permits an unknown session only for that originating operation', () => {
  const handler = core();
  const decode = (operation: string, sessionId: string | null) => JSON.parse(handler(JSON.stringify({ op: 'native-response', operation, sessionId,
    source: JSON.stringify({ ok: true, operation, value: descriptor }) })));
  assert.equal(decode('session.open', null).ok, true);
  assert.equal(decode('session.check', null).ok, false);
  assert.equal(decode('session.check', 'other').ok, false);
  assert.equal(decode('session.check', 'session').ok, true);
});
