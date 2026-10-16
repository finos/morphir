import { test } from 'node:test';
import assert from 'node:assert/strict';
import { NativeAdapter, NativeSession, NativeJobTransport, nativeBridgeVersion, selectLocalAdapter } from './native-session.js';
import { core, descriptor, bridge, failure, success } from './native-test-fixture.js';

globalThis.morphirWorkbenchJobs = core();
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const local = () => ({ calls: [], cancel() {}, async initialize() { return { success: true, catalog: {}, connected: false }; },
  async execute(request) { this.calls.push(request); return { success: true, value: '42' }; } });
const session = (handle, timeout) => new NativeSession(bridge(handle), timeout, core());
const jobDescriptor = () => ({ ...descriptor, operations: ['jobs'], offer: {
  profile: 'morphir/workbench/jobs', contractVersion: nativeBridgeVersion, hostId: 'host',
  sessionId: descriptor.sessionId, providerId: 'scheme', operations: ['query', 'cancel'],
} });

test('native discovery is restricted to bundled entries; explicit runtime selection takes precedence', () => {
  const worker = local(); const native = { core: { invokeOp() {} } };
  for (const href of ['http://127.0.0.1:5173', 'https://example.com', 'https://proton.localhost.evil',
    'http://proton.localhost', 'https://proton.localhost:1234', 'https://proton.localhost/?mode=connected',
    'https://proton.localhost/?mode=standalone']) assert.equal(selectLocalAdapter(new URL(href), worker, native), worker);
  for (const href of ['https://proton.localhost/frontend/dist/index.html', 'proton://app/index.html']) {
    assert.ok(selectLocalAdapter(new URL(href), worker, native) instanceof NativeAdapter);
  }
});

test('native initialization preserves bridge receiver and uses correlated raw envelopes', async () => {
  const calls = []; const worker = local();
  const native = { core: { invokeOp(name, source) {
    assert.equal(this, native.core); assert.equal(name, 'app:workbench_native');
    const frame = JSON.parse(source); calls.push(frame); return success(frame.operation, descriptor);
  } } };
  const adapter = selectLocalAdapter(new URL('https://proton.localhost/index.html'), worker, native);
  const reply = await adapter.initialize();
  assert.equal(reply.connected, false); assert.equal(reply.nativeSession, true); assert.equal(reply.jobsAvailable, false);
  assert.deepEqual(calls.map(f => f.operation), ['session.open', 'session.check']);
  assert.deepEqual(Object.keys(calls[0]).sort(), ['contractVersion', 'operation', 'profile']);
  assert.equal(calls[0].profile, descriptor.profile); assert.equal(calls[1].sessionId, descriptor.sessionId);
  assert.deepEqual(await adapter.execute({ operation: 'evaluate', source: '{}' }), { success: true, value: '42' });
  await assert.rejects(adapter.execute({ operation: 'project', project: 'outside' }), /does not offer/);
  adapter.dispose();
});

test('malformed descriptors, wrong operations and old private shapes never start a local worker', async () => {
  for (const reply of [{ ...descriptor, contractVersion: '0.1.0-draft.2' }, { ...descriptor, operations: ['evaluate'] },
    { ...descriptor, extra: true }, { ...descriptor, sessionId: '' }, null,
    { ok: true, bridgeVersion: nativeBridgeVersion, sessionId: 'old', operations: [] },
    success('session.check', descriptor), '{"ok":true,"ok":true,"operation":"session.open","value":{}}']) {
    const worker = local(); let initialized = 0; worker.initialize = () => { ++initialized; };
    const adapter = new NativeAdapter(worker, bridge(() => reply), undefined, { core: core() });
    await assert.rejects(adapter.initialize(), /incompatible/); assert.equal(initialized, 0);
  }
  await assert.rejects(selectLocalAdapter(new URL('https://proton.localhost'), local(), null).initialize(), /unavailable/);
});

test('changed or rejected session authority refuses work before the local worker', async () => {
  for (const reply of [{ ...descriptor, sessionId: 'replacement' }, failure(), jobDescriptor()]) {
    const worker = local();
    const adapter = new NativeAdapter(worker, bridge(f => f.operation === 'session.open' ? descriptor : reply), undefined, { core: core() });
    await adapter.session.open();
    await assert.rejects(adapter.execute({ operation: 'run', source: '42' })); assert.equal(worker.calls.length, 0);
  }
  const stable = jobDescriptor(); const s = session(f => f.operation === 'session.open' ? stable : { ...stable, offer: { ...stable.offer, hostId: 'changed' } });
  await s.open(); await assert.rejects(s.check(), /authority changed/);
});

test('cancelled admission and disposed completion cannot start or publish stale work', async () => {
  const pending = deferred(); const worker = local(); let waiting = false;
  const adapter = new NativeAdapter(worker, bridge(f => f.operation === 'session.check' && waiting ? pending.promise : descriptor), undefined, { core: core() });
  await adapter.initialize(); waiting = true;
  const execution = adapter.execute({ operation: 'run', source: '42' });
  adapter.cancel(); pending.resolve(descriptor);
  await assert.rejects(execution, /Discarded/); assert.equal(worker.calls.length, 0);
  waiting = false; const completion = deferred(); worker.execute = () => completion.promise;
  const executing = adapter.execute({ operation: 'run', source: '42' });
  await new Promise(setImmediate); adapter.dispose(); completion.resolve({ success: true });
  await assert.rejects(executing, /Discarded/);
});

test('native deadlines and late handshake replies cannot revive a closed client', async () => {
  await assert.rejects(session(() => new Promise(() => {}), 5).open(), /timed out/);
  const pending = deferred(); const late = session(() => pending.promise);
  const opening = late.open(); late.dispose(); pending.resolve(descriptor);
  await assert.rejects(opening, /closed/); assert.equal(late.id, null);
});

test('a late admission reply cannot start an older request after its replacement', async () => {
  const checks = [deferred(), deferred()]; const worker = local(); let waiting = false, checked = 0;
  const adapter = new NativeAdapter(worker, bridge(f => f.operation === 'session.check' && waiting && checked < 2 ? checks[checked++].promise : descriptor), undefined, { core: core() });
  await adapter.initialize(); waiting = true;
  const older = adapter.execute({ operation: 'run', source: 'old' }); const latest = adapter.execute({ operation: 'run', source: 'latest' });
  await new Promise(setImmediate); checks[1].resolve(descriptor); await latest; checks[0].resolve(descriptor);
  await assert.rejects(older, /Discarded/); assert.deepEqual(worker.calls.map(r => r.source), ['latest']);
});

test('native transport preserves raw requests and admitted error effects without HTTP statuses', async () => {
  const calls = [], claimed = jobDescriptor();
  const s = session(f => { calls.push(f); return f.operation.startsWith('job.') ? failure('conflict', 'none') : claimed; });
  await s.open(); const t = new NativeJobTransport(s);
  assert.deepEqual(JSON.parse(await t.nativeDescriptor()), claimed);
  const source = s.encode('job.submit', { contractVersion: nativeBridgeVersion, model: ' {"exact":9007199254740993} ', entry: 'example:main#answer', inputs: { format: 'ion-text', source: '[1]' } });
  const raw = await t.nativeRequest(source); assert.deepEqual(JSON.parse(raw).error.effect, 'none');
  assert.equal(calls.find(f => f.operation === 'job.submit').payload.model, ' {"exact":9007199254740993} ');
  assert.equal(calls.filter(f => f.operation === 'session.check').length, 3);
});

test('native job admission never falls back; explicit local evaluation stays local', async () => {
  const worker = local(); const adapter = new NativeAdapter(worker, bridge(), undefined, { core: core() }); await adapter.initialize();
  adapter.jobsAvailable = true; let requests = 0;
  adapter.jobs = { async execute() { ++requests; throw new Error('Native admission rejected'); } };
  await assert.rejects(adapter.execute({ operation: 'evaluate', executionMode: 'typed' }), /Native admission rejected/);
  assert.equal(requests, 1); assert.equal(worker.calls.length, 0);
  await adapter.execute({ operation: 'evaluate', executionMode: 'local' }); assert.equal(worker.calls.length, 1);
});

test('native transport rejects malformed, uncorrelated and oversize raw replies and lost frames', async () => {
  for (const reply of ['x'.repeat(1048577), { status: 200, source: '{}' }, success('job.cancel', {}),
    '{"ok":false,"error":{"code":"conflict","effect":"none","effect":"unknown","message":"x"}}']) {
    const s = session(f => f.operation.startsWith('job.') ? (typeof reply === 'string' ? reply : JSON.stringify(reply)) : descriptor);
    await s.open(); await assert.rejects(new NativeJobTransport(s).nativeRequest(s.encode('job.query', {})), /invalid raw|incompatible/);
  }
  const s = session(f => f.operation.startsWith('job.') ? new Promise(() => {}) : descriptor, 5);
  await s.open(); await assert.rejects(new NativeJobTransport(s).nativeRequest(s.encode('job.submit', {})), /effect may be unknown/);
});

test('the bundled adapter initializes native hooks and runs typed evaluation through the compiled cursor', async () => {
  const d = jobDescriptor(), calls = [], worker = local();
  const identity = { ...d.offer, jobId: 'job', snapshotId: 'snapshot' };
  delete identity.profile; delete identity.contractVersion; delete identity.operations;
  const receipt = { contractVersion: nativeBridgeVersion, identity, sequence: 0, state: 'submitted', cancelRequested: false, outcomes: null };
  const terminal = { ...receipt, sequence: 1, state: 'terminal', outcomes: {
    contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '42' } } }], cleanup: null, extensions: null,
  } };
  const adapter = new NativeAdapter(worker, bridge(f => {
    calls.push(f);
    if (f.operation.startsWith('session.')) return d;
    if (f.operation === 'job.submit') return { identity, calls: ['workbench'], receipt };
    if (f.operation === 'job.release') return { released: true };
    return terminal;
  }), 1000, { core: core(), pause: async () => {} });
  assert.equal((await adapter.initialize()).jobsAvailable, true);
  const result = await adapter.execute({ operation: 'evaluate', executionMode: 'typed', source: '{}', entry: 'calls:main#answer', arguments: [] });
  assert.equal(result.success, true); assert.equal(worker.calls.length, 0);
  assert.equal(calls.filter(f => f.operation === 'job.submit').length, 1);
  assert.equal(calls.filter(f => f.operation === 'job.release').length, 1);
  adapter.dispose();
});


test('equivalent descriptor and nested offer member order preserves authority', async () => {
  const d = jobDescriptor();
  const reordered = { offer: Object.fromEntries(Object.entries(d.offer).reverse()),
    operations: d.operations, sessionId: d.sessionId, contractVersion: d.contractVersion, profile: d.profile };
  const s = session(f => f.operation === 'session.open' ? d : reordered);
  await s.open(); await s.check();
});
