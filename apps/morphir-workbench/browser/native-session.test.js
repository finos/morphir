import { test } from 'node:test';
import assert from 'node:assert/strict';
import { NativeAdapter, NativeSession, nativeBridgeVersion, selectLocalAdapter } from './native-session.js';

const descriptor = { ok: true, bridgeVersion: nativeBridgeVersion, sessionId: 'proton-session-1', operations: [] };
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const local = () => ({ calls: [], cancel() {}, async initialize() { return { success: true, catalog: {}, connected: false }; },
  async execute(request) { this.calls.push(request); return { success: true, value: '42' }; } });

test('native discovery is restricted to bundled entries; explicit runtime selection takes precedence', () => {
  const worker = local(); const bridge = { core: { invokeOp() {} } };
  for (const href of ['http://127.0.0.1:5173', 'https://example.com', 'https://proton.localhost.evil',
    'http://proton.localhost', 'https://proton.localhost:1234', 'https://proton.localhost/?mode=connected',
    'https://proton.localhost/?mode=standalone']) {
    assert.equal(selectLocalAdapter(new URL(href), worker, bridge), worker);
  }
  for (const href of ['https://proton.localhost/frontend/dist/index.html', 'proton://app/index.html']) {
    assert.ok(selectLocalAdapter(new URL(href), worker, bridge) instanceof NativeAdapter);
  }
});

test('native initialization preserves bridge receiver, verifies the session, and offers only local workers', async () => {
  const calls = []; const worker = local();
  const bridge = { core: { invokeOp(name, payload) {
    assert.equal(this, bridge.core); calls.push([name, payload]); return descriptor;
  } } };
  const adapter = selectLocalAdapter(new URL('https://proton.localhost/index.html'), worker, bridge);
  const reply = await adapter.initialize();
  assert.equal(reply.connected, false); assert.equal(reply.nativeSession, true); assert.equal(reply.jobsAvailable, false);
  assert.match(reply.message, /Desktop local/);
  assert.deepEqual(calls, [['app:workbench_session_open', nativeBridgeVersion], ['app:workbench_session_check', descriptor.sessionId]]);
  assert.deepEqual(await adapter.execute({ operation: 'evaluate', source: '{}' }), { success: true, value: '42' });
  assert.equal(worker.calls.length, 1);
  await assert.rejects(adapter.execute({ operation: 'project', project: 'outside' }), /does not offer/);
  adapter.dispose();
});

test('missing bridge, incompatible versions and unexpected capability claims do not fall back to a worker', async () => {
  for (const reply of [{ ...descriptor, bridgeVersion: '0.1.0-draft.2' }, { ...descriptor, operations: ['evaluate'] },
    { ...descriptor, extra: true }, { ...descriptor, sessionId: '' }, { ...descriptor, ok: false }, null]) {
    const worker = local(); let initialized = 0; worker.initialize = () => { ++initialized; };
    const adapter = new NativeAdapter(worker, async () => reply);
    await assert.rejects(adapter.initialize(), /incompatible/); assert.equal(initialized, 0);
  }
  await assert.rejects(selectLocalAdapter(new URL('https://proton.localhost'), local(), null).initialize(), /unavailable/);
});

test('changed or rejected sessions refuse work before invoking the local worker', async () => {
  for (const reply of [{ ...descriptor, sessionId: 'replacement' }, { ok: false, code: 'workbench.native_stale_session' }]) {
    const worker = local();
    const adapter = new NativeAdapter(worker, async name => name.endsWith('_open') ? descriptor : reply);
    await adapter.session.open();
    await assert.rejects(adapter.execute({ operation: 'run', source: '42' }), /session/);
    assert.equal(worker.calls.length, 0);
  }
});

test('cancelled admission never starts a worker; disposed completion cannot publish a result', async () => {
  const pending = deferred(); const worker = local(); let waiting = false;
  const adapter = new NativeAdapter(worker, async name => name.endsWith('_check') && waiting ? pending.promise : descriptor);
  await adapter.initialize(); waiting = true;
  const execution = adapter.execute({ operation: 'run', source: '42' });
  adapter.cancel(); pending.resolve(descriptor);
  await assert.rejects(execution, /Discarded/); assert.equal(worker.calls.length, 0);
  waiting = false;
  const completion = deferred(); worker.execute = () => completion.promise;
  const execution2 = adapter.execute({ operation: 'run', source: '42' });
  await new Promise(resolve => setImmediate(resolve)); adapter.dispose(); completion.resolve({ success: true });
  await assert.rejects(execution2, /Discarded/);
});

test('native deadlines and late handshake replies cannot revive a closed client', async () => {
  const session = new NativeSession(() => new Promise(() => {}), 5);
  await assert.rejects(session.open(), /timed out/);
  const pending = deferred(); const late = new NativeSession(() => pending.promise);
  const opening = late.open(); late.dispose(); pending.resolve(descriptor);
  await assert.rejects(opening, /closed/); assert.equal(late.id, null);
});

test('a late admission reply cannot start an older request after its replacement', async () => {
  const checks = [deferred(), deferred()]; const worker = local(); let waiting = false, checked = 0;
  const adapter = new NativeAdapter(worker, async name => {
    if (name.endsWith('_check') && waiting && checked < 2) return checks[checked++].promise;
    return descriptor;
  });
  await adapter.initialize(); waiting = true;
  const older = adapter.execute({ operation: 'run', source: 'old' });
  const latest = adapter.execute({ operation: 'run', source: 'latest' });
  await new Promise(resolve => setImmediate(resolve));
  checks[1].resolve(descriptor); await latest;
  checks[0].resolve(descriptor);
  await assert.rejects(older, /Discarded/);
  assert.deepEqual(worker.calls.map(request => request.source), ['latest']);
});
