import type { Adapter, Invoke, Json, WorkRequest } from './contracts.ts';
import type { bridge as bridgeType } from './native-test-fixture.ts';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { NativeAdapter, NativeSession, NativeExecutionTransport, nativeBridgeVersion, nativePolicyBridgeVersion, selectLocalAdapter } from './native-session.ts';
import { ExecutionClient } from './execution-session.ts';
import { core, descriptor, bridge, failure, success } from './native-test-fixture.ts';

globalThis.morphirWorkbenchExecutions = core();
import { deferred, malformed } from '../../../tests/helpers.ts';
const local = (): Adapter & { calls: WorkRequest[] } => ({ calls: [] as WorkRequest[], cancel() {}, dispose() {}, async initialize() { return { success: true, catalog: { frontends: [], targets: [] }, connected: false }; },
  async execute(request: WorkRequest) { this.calls.push(request); return { success: true, value: '42' }; } });
const session = (handle: Parameters<typeof bridgeType>[0], timeout?: number) => new NativeSession(bridge(handle), timeout, core());
const executionDescriptor = () => ({ ...descriptor, operations: ['executions'], offer: {
  profile: 'morphir/workbench/executions', contractVersion: nativeBridgeVersion, hostId: 'host',
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
  const calls: { operation: string; sessionId?: string; profile: string }[] = []; const worker = local();
  const native = { core: { invokeOp(name: string, source: string) {
    assert.equal(this, native.core); assert.equal(name, 'app:workbench_native');
    const frame = JSON.parse(source); calls.push(frame); return success(frame.operation, { ...descriptor, contractVersion: nativePolicyBridgeVersion });
  } } };
  const adapter = selectLocalAdapter(new URL('https://proton.localhost/index.html'), worker, native);
  const reply = await adapter.initialize();
  assert.equal(reply.connected, false); assert.equal(reply.nativeSession, true); assert.equal(reply.executionsAvailable, false);
  assert.deepEqual(calls.map(f => f.operation), ['session.open', 'session.check']);
  assert.deepEqual(Object.keys(calls[0]!).sort(), ['contractVersion', 'operation', 'profile']);
  assert.equal(calls[0]!.profile, descriptor.profile); assert.equal(calls[1]!.sessionId, descriptor.sessionId);
  assert.deepEqual(await adapter.execute({ operation: 'evaluate', source: '{}' }), { success: true, value: '42' });
  await assert.rejects(adapter.execute({ operation: 'project', project: 'outside' }), /does not offer/);
  adapter.dispose();
});

test('malformed descriptors, wrong operations and old private shapes never start a local worker', async () => {
  for (const reply of [{ ...descriptor, contractVersion: '0.1.0-draft.2' }, { ...descriptor, operations: ['evaluate'] },
    { ...descriptor, extra: true }, { ...descriptor, sessionId: '' }, null,
    { ok: true, bridgeVersion: nativeBridgeVersion, sessionId: 'old', operations: [] },
    success('session.check', descriptor), '{"ok":true,"ok":true,"operation":"session.open","value":{}}']) {
    const worker = local(); let initialized = 0; worker.initialize = async () => { ++initialized; throw new Error('Must not initialize'); };
    const adapter = new NativeAdapter(worker, bridge(() => reply), undefined, { core: core() });
    await assert.rejects(adapter.initialize(), /incompatible/); assert.equal(initialized, 0);
  }
  await assert.rejects(selectLocalAdapter(new URL('https://proton.localhost'), local(), null).initialize(), /unavailable/);
});

test('changed or rejected session authority refuses work before the local worker', async () => {
  for (const reply of [{ ...descriptor, sessionId: 'replacement' }, failure(), executionDescriptor()]) {
    const worker = local();
    const adapter = new NativeAdapter(worker, bridge(f => f.operation === 'session.open' ? descriptor : reply), undefined, { core: core() });
    await adapter.session.open();
    await assert.rejects(adapter.execute({ operation: 'run', source: '42' })); assert.equal(worker.calls.length, 0);
  }
  const stable = executionDescriptor(); const s = session(f => f.operation === 'session.open' ? stable : { ...stable, offer: { ...stable.offer, hostId: 'changed' } });
  await s.open(); await assert.rejects(s.check(), /authority changed/);
});

test('cancelled admission and disposed completion cannot start or publish stale work', async () => {
  const pending = deferred(); const worker = local(); let waiting = false;
  const adapter = new NativeAdapter(worker, bridge(f => f.operation === 'session.check' && waiting ? pending.promise : descriptor), undefined, { core: core() });
  await adapter.initialize(); waiting = true;
  const execution = adapter.execute({ operation: 'run', source: '42' });
  adapter.cancel(); pending.resolve!(descriptor);
  await assert.rejects(execution, /Discarded/); assert.equal(worker.calls.length, 0);
  waiting = false; const completion = deferred<import('./contracts.ts').WorkResult>(); worker.execute = () => completion.promise;
  const executing = adapter.execute({ operation: 'run', source: '42' });
  await new Promise(setImmediate); adapter.dispose(); completion.resolve!({ success: true });
  await assert.rejects(executing, /Discarded/);
});

test('native deadlines and late handshake replies cannot revive a closed client', async () => {
  await assert.rejects(session(() => new Promise(() => {}), 5).open(), /timed out/);
  const pending = deferred(); const late = session(() => pending.promise);
  const opening = late.open(); late.dispose(); pending.resolve!(descriptor);
  await assert.rejects(opening, /closed/); assert.equal(late.id, null);
});

test('a late admission reply cannot start an older request after its replacement', async () => {
  const checks = [deferred(), deferred()]; const worker = local(); let waiting = false, checked = 0;
  const adapter = new NativeAdapter(worker, bridge(f => f.operation === 'session.check' && waiting && checked < 2 ? checks[checked++]!.promise : descriptor), undefined, { core: core() });
  await adapter.initialize(); waiting = true;
  const older = adapter.execute({ operation: 'run', source: 'old' }); const latest = adapter.execute({ operation: 'run', source: 'latest' });
  await new Promise(setImmediate); checks[1]!.resolve!(descriptor); await latest; checks[0]!.resolve!(descriptor);
  await assert.rejects(older, /Discarded/); assert.deepEqual(worker.calls.map(r => r.source), ['latest']);
});

test('native transport preserves raw requests and admitted error effects without HTTP statuses', async () => {
  const calls: Parameters<NonNullable<Parameters<typeof bridge>[0]>>[0][] = [], claimed = executionDescriptor();
  const s = session(f => { calls.push(f); return f.operation.startsWith('execution.') ? failure('conflict', 'none') : claimed; });
  await s.open(); const t = new NativeExecutionTransport(s);
  assert.deepEqual(JSON.parse(await t.nativeDescriptor()), claimed);
  const source = s.encode('execution.submit', { contractVersion: nativeBridgeVersion, model: ' {"exact":9007199254740993} ', entry: 'example:main#answer', inputs: { format: 'ion-text', source: '[1]' } });
  const raw = await t.nativeRequest(source); assert.deepEqual(JSON.parse(raw).error.effect, 'none');
  assert.equal(calls.find(f => f.operation === 'execution.submit')!.payload.model, ' {"exact":9007199254740993} ');
  assert.equal(calls.filter(f => f.operation === 'session.check').length, 3);
});

test('native execution admission never falls back; explicit local evaluation stays local', async () => {
  const worker = local(); const adapter = new NativeAdapter(worker, bridge(), undefined, { core: core() }); await adapter.initialize();
  adapter.executionsAvailable = true; let requests = 0;
  adapter.executions = malformed({ async execute() { ++requests; throw new Error('Native admission rejected'); } });
  await assert.rejects(adapter.execute({ operation: 'evaluate', executionMode: 'typed' }), /Native admission rejected/);
  assert.equal(requests, 1); assert.equal(worker.calls.length, 0);
  await adapter.execute({ operation: 'evaluate', executionMode: 'local' }); assert.equal(worker.calls.length, 1);
});

test('native transport rejects malformed, uncorrelated and oversize raw replies and lost frames', async () => {
  for (const reply of ['x'.repeat(1048577), { status: 200, source: '{}' }, success('execution.cancel', {}),
    '{"ok":false,"error":{"code":"conflict","effect":"none","effect":"unknown","message":"x"}}']) {
    const s = session(f => f.operation.startsWith('execution.') ? (typeof reply === 'string' ? reply : JSON.stringify(reply)) : descriptor);
    await s.open(); await assert.rejects(new NativeExecutionTransport(s).nativeRequest(s.encode('execution.query', {})), /invalid raw|incompatible/);
  }
  const s = session(f => f.operation.startsWith('execution.') ? new Promise(() => {}) : descriptor, 5);
  await s.open(); await assert.rejects(new NativeExecutionTransport(s).nativeRequest(s.encode('execution.submit', {})), /effect may be unknown/);
});

test('the bundled adapter initializes native hooks and runs typed evaluation through the compiled cursor', async () => {
  const d = executionDescriptor(), calls: Parameters<NonNullable<Parameters<typeof bridge>[0]>>[0][] = [], worker = local();
  const { profile: _profile, contractVersion: _version, operations: _operations, ...owner } = d.offer;
  const identity = { ...owner, executionId: 'execution', snapshotId: 'snapshot' };
  const receipt = { contractVersion: nativeBridgeVersion, identity, sequence: 0, state: 'submitted', cancelRequested: false, outcomes: null };
  const terminal = { ...receipt, sequence: 1, state: 'terminal', outcomes: {
    contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '42' } } }], cleanup: null, extensions: null,
  } };
  const adapter = new NativeAdapter(worker, bridge(f => {
    calls.push(f);
    if (f.operation.startsWith('session.')) return d;
    if (f.operation === 'execution.submit') return { identity, calls: ['workbench'], receipt };
    if (f.operation === 'execution.release') return { released: true };
    return terminal;
  }), 1000, { core: core(), pause: async () => {} });
  assert.equal((await adapter.initialize()).executionsAvailable, true);
  const result = await adapter.execute({ operation: 'evaluate', executionMode: 'typed', source: '{}', entry: 'calls:main#answer', arguments: [] });
  assert.equal(result.success, true); assert.equal(worker.calls.length, 0);
  assert.equal(calls.filter(f => f.operation === 'execution.submit').length, 1);
  assert.equal(calls.filter(f => f.operation === 'execution.release').length, 1);
  adapter.dispose();
});


test('equivalent descriptor and nested offer member order preserves authority', async () => {
  const d = executionDescriptor();
  const reordered = { offer: Object.fromEntries(Object.entries(d.offer).reverse()),
    operations: d.operations, sessionId: d.sessionId, contractVersion: d.contractVersion, profile: d.profile };
  const s = session(f => f.operation === 'session.open' ? d : reordered);
  await s.open(); await s.check();
});

test('native mapping refuses checking-policy requests before any local fallback', async () => {
  const worker = local();
  const adapter = new NativeAdapter(worker, bridge(), undefined, { core: core() });
  for (const request of [
    { operation: 'evaluate', source: '{}', executionMode: 'capability' },
    { operation: 'evaluate', source: '{}', executionMode: 'typed', admission: { policy: 'permissive' } },
  ]) await assert.rejects(adapter.execute(request), /does not offer checking-policy/);
  assert.equal(worker.calls.length, 0);
  adapter.dispose();
});

const checkingOffer = {
  profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', runtime: 'scheme',
  evaluator: 'scheme-portable-v1/shared-sdk/bounded', policies: ['strict', 'permissive'],
};
const policyDescriptor = () => ({ ...executionDescriptor(), contractVersion: nativePolicyBridgeVersion, capabilityChecks: checkingOffer });
const policyModel = JSON.stringify({ formatVersion: 4, distribution: { Library: { packageName: 'client', dependencies: {}, def: { modules: { main: { Public: { types: {}, values: { answer: { Public: { doc: '', ExpressionBody: { inputTypes: {}, outputType: 'morphir/SDK:basics#int', body: { Literal: { IntegerLiteral: 42 } } } } } } } } } } } } });
const policySelection = (policy = 'strict') => ({ profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy });
const policyAccepted = (policy = 'strict') => {
  const identity = { hostId: 'host', sessionId: descriptor.sessionId, providerId: 'scheme', executionId: 'execution', snapshotId: 'snapshot' };
  const receipt = { contractVersion: nativeBridgeVersion, identity, sequence: 0, state: 'submitted', cancelRequested: false, outcomes: null };
  return { identity, calls: ['workbench'], receipt, plan: { profile: 'morphir/workbench/execution-plan', contractVersion: nativeBridgeVersion, identity, planId: 'plan', runtime: 'scheme', evaluator: checkingOffer.evaluator,
    admission: policySelection(policy), boundary: { entries: [{ name: 'client:main#answer', inputs: [], output: { type: 'int' } }], definitions: [] } } };
};

test('production native mapping requires its exact checking descriptor without downgrade', async () => {
  const worker = local(); let calls = 0;
  const adapter = selectLocalAdapter(new URL('https://proton.localhost/index.html'), worker, { core: { invokeOp: bridge(() => { ++calls; return descriptor; }) } });
  await assert.rejects(adapter.initialize(), /incompatible/);
  assert.equal(calls, 1);
  assert.equal(worker.calls.length, 0);
});

test('native policy checks capture source and selection before a held authority check', async () => {
  const d = policyDescriptor(), accepted = policyAccepted('permissive'), pending = deferred();
  const worker = local(); let hold = false; let submitted: Record<string, Json> | undefined;
  const adapter = new NativeAdapter(worker, bridge(f => {
    if (f.operation === 'session.check' && hold) { hold = false; return pending.promise; }
    if (f.operation.startsWith('session.')) return d;
    if (f.operation === 'execution.submit') { submitted = f.payload; return accepted; }
    if (f.operation === 'execution.release') return { released: true };
    return { ...accepted.receipt, sequence: 1, state: 'terminal', outcomes: { contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '42' } } }], cleanup: null, extensions: null } };
  }), 1000, { core: core(), nativeMapping: 'capability-checks', pause: async () => {} });
  assert.equal((await adapter.initialize()).capabilityRuntime, 'native');
  const request: WorkRequest = { operation: 'evaluate', executionMode: 'capability', source: policyModel, entry: 'client:main#answer', arguments: [], admission: policySelection('permissive') };
  hold = true;
  const running = adapter.execute(request);
  request.source = '{}'; request.entry = 'other:main#entry'; request.arguments = [123]; request.admission = policySelection('strict');
  pending.resolve!(d);
  const result = await running;
  assert.equal(result.success, true);
  assert.equal(submitted!.model, policyModel);
  assert.equal(submitted!.entry, 'client:main#answer');
  assert.deepEqual(submitted!.inputs, { format: 'json', source: '[]' });
  assert.deepEqual(submitted!.admission, policySelection('permissive'));
  assert.deepEqual(result.admission, policySelection('permissive'));
  assert.deepEqual(result.executionPlan, accepted.plan);
  assert.deepEqual(adapter.executions!.acceptedPlan, accepted.plan);
  assert.equal(worker.calls.length, 0);
  adapter.dispose();
  assert.deepEqual(adapter.executions!.acceptedPlan, accepted.plan);
});

test('native policy authority includes the checking evaluator and complete policy inventory', async () => {
  const d = policyDescriptor();
  for (const capabilityChecks of [{ ...checkingOffer, evaluator: 'other' }, { ...checkingOffer, policies: ['strict'] }, { ...checkingOffer, runtime: 'other' }]) {
    const s = new NativeSession(bridge(f => f.operation === 'session.open' ? d : { ...d, capabilityChecks }), 1000, core(), 'capability-checks');
    await s.open(); await assert.rejects(s.check());
  }
  const reversed = { ...d, capabilityChecks: Object.fromEntries(Object.entries(checkingOffer).reverse()), offer: Object.fromEntries(Object.entries(d.offer).reverse()) };
  const s = new NativeSession(bridge(f => f.operation === 'session.open' ? d : reversed), 1000, core(), 'capability-checks');
  await s.open(); await s.check();
});

test('a changed accepted policy cannot become an accepted plan or permit auto retry', async () => {
  const worker = local(); let submissions = 0; const d = policyDescriptor();
  const adapter = new NativeAdapter(worker, bridge(f => {
    if (f.operation.startsWith('session.')) return d;
    if (f.operation === 'execution.submit') { ++submissions; return policyAccepted('strict'); }
    throw new Error('Unexpected operation');
  }), 1000, { core: core(), nativeMapping: 'capability-checks' });
  await adapter.initialize();
  const request: WorkRequest = { operation: 'evaluate', executionMode: 'capability', source: policyModel, entry: 'client:main#answer', arguments: [], admission: policySelection('permissive') };
  await assert.rejects(adapter.execute(request));
  assert.equal(adapter.executions!.uncertainSubmission, true);
  assert.equal(adapter.executions!.acceptedPlan, null);
  await assert.rejects(adapter.execute(request), /unknown/);
  assert.equal(submissions, 1); assert.equal(worker.calls.length, 0);
  adapter.dispose();
});

test('execution selection is frozen across pending release and cleanup reserves the next attempt', async () => {
  const d = policyDescriptor(), pending = deferred<string>(); let releases = 0; let submits = 0;
  let accepted = policyAccepted('permissive'); const bodies: Json[] = [];
  const client = new ExecutionClient(descriptor.sessionId, { core: core(), nativeMapping: 'capability-checks', pause: async () => {}, transport: {
    async nativeDescriptor() { return JSON.stringify(d); },
    async nativeRequest(source) {
      const frame = JSON.parse(source);
      if (frame.operation === 'execution.release') {
        ++releases;
        if (releases === 1) return failure('unavailable', 'unknown');
        if (releases === 2) return pending.promise;
        return success(frame.operation, { released: true });
      }
      if (frame.operation === 'execution.submit') {
        ++submits; bodies.push(frame.payload); accepted = policyAccepted('permissive');
        accepted.identity.executionId = `execution-${submits}`;
        accepted.identity.snapshotId = `snapshot-${submits}`;
        accepted.plan.planId = `plan-${submits}`;
        return success(frame.operation, accepted);
      }
      return success(frame.operation, { ...accepted.receipt, sequence: 1, state: 'terminal', outcomes: { contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '42' } } }], cleanup: null, extensions: null } });
    },
  } });
  await client.initialize();
  const request: WorkRequest = { operation: 'evaluate', executionMode: 'capability', source: policyModel, entry: 'client:main#answer', arguments: [], admission: policySelection('permissive') };
  await client.execute(request);
  assert.equal(client.releasePending, true);
  const second = client.execute(request);
  assert.equal(client.active, true);
  request.source = '{}'; request.entry = 'different:main#answer'; request.arguments = [123]; request.admission = policySelection('strict');
  await assert.rejects(client.execute(request), /already active/);
  pending.resolve!(success('execution.release', { released: true }));
  assert.equal((await second).success, true);
  assert.equal(submits, 2);
  assert.deepEqual(bodies[1], bodies[0]);
  assert.deepEqual(client.acceptedPlan, accepted.plan);
});

test('a native page without execution authority refuses policies before local work', async () => {
  const worker = local();
  const d = { ...descriptor, contractVersion: nativePolicyBridgeVersion };
  const adapter = new NativeAdapter(worker, bridge(() => d), 1000, { core: core(), nativeMapping: 'capability-checks' });
  await adapter.initialize();
  await assert.rejects(adapter.execute({ operation: 'evaluate', executionMode: 'capability', source: policyModel, entry: 'client:main#answer', arguments: [] }), /does not offer/);
  assert.equal(worker.calls.length, 0);
  adapter.dispose();
});

test('a released identity cannot be accepted as a fresh desktop execution', async () => {
  const d = policyDescriptor(), accepted = policyAccepted();
  let submits = 0, queries = 0, releases = 0, publications = 0, observed = 0;
  const client = new ExecutionClient(descriptor.sessionId, { core: core(), nativeMapping: 'capability-checks',
    onAcceptedPlan() { ++observed; throw new Error('Diagnostic observer failed'); }, pause: async () => {}, transport: {
    async nativeDescriptor() { return JSON.stringify(d); },
    async nativeRequest(source) {
      const frame = JSON.parse(source);
      if (frame.operation === 'execution.submit') { ++submits; return success(frame.operation, accepted); }
      if (frame.operation === 'execution.release') { ++releases; return success(frame.operation, { released: true }); }
      ++queries;
      return success(frame.operation, { ...accepted.receipt, sequence: 1, state: 'terminal', outcomes: { contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '42' } } }], cleanup: null, extensions: null } });
    },
  } });
  await client.initialize();
  const request: WorkRequest = { operation: 'evaluate', executionMode: 'capability', source: policyModel, entry: 'client:main#answer', arguments: [] };
  assert.equal((await client.execute(request, () => { ++publications; })).success, true);
  assert.equal(client.uncertainSubmission, false);
  assert.equal(observed, 1);
  const completedPublications = publications;
  await assert.rejects(client.execute(request, () => { ++publications; }), /rejected/);
  assert.equal(client.uncertainSubmission, true);
  assert.equal(observed, 1);
  assert.deepEqual(client.acceptedPlan, accepted.plan);
  assert.equal(publications, completedPublications);
  assert.equal(submits, 2); assert.equal(queries, 1); assert.equal(releases, 1);
  await assert.rejects(client.execute(request), /unknown/);
  assert.equal(submits, 2);
});

test('a fresh execution cannot reuse an accepted plan or rebind an accepted execution id', async () => {
  for (const reused of ['plan', 'execution']) {
    const d = policyDescriptor(); let submits = 0, queries = 0, observed = 0;
    let accepted = policyAccepted();
    const client = new ExecutionClient(descriptor.sessionId, { core: core(), nativeMapping: 'capability-checks', onAcceptedPlan() { ++observed; }, pause: async () => {}, transport: {
      async nativeDescriptor() { return JSON.stringify(d); },
      async nativeRequest(source) {
        const frame = JSON.parse(source);
        if (frame.operation === 'execution.submit') {
          ++submits; accepted = policyAccepted();
          if (submits > 1) {
            accepted.identity.snapshotId = 'fresh-snapshot';
            if (reused === 'plan') accepted.identity.executionId = 'fresh-execution';
            else accepted.plan.planId = 'fresh-plan';
          }
          return success(frame.operation, accepted);
        }
        if (frame.operation === 'execution.release') return success(frame.operation, { released: true });
        ++queries;
        return success(frame.operation, { ...accepted.receipt, sequence: 1, state: 'terminal', outcomes: { contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '42' } } }], cleanup: null, extensions: null } });
      },
    } });
    await client.initialize();
    const request: WorkRequest = { operation: 'evaluate', executionMode: 'capability', source: policyModel, entry: 'client:main#answer', arguments: [] };
    await client.execute(request);
    const retained = structuredClone(client.acceptedPlan);
    await assert.rejects(client.execute(request), /rejected/);
    assert.equal(client.uncertainSubmission, true);
    assert.equal(observed, 1);
    assert.deepEqual(client.acceptedPlan, retained);
    assert.equal(queries, 1);
  }
});
