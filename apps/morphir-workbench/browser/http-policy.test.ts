import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createExecutionProvider } from '../scripts/execution-provider.ts';
import { ExecutionClient } from './execution-session.ts';
import { core } from './native-test-fixture.ts';
import type { ExecutionOperation } from '../scripts/execution-contracts.ts';
const model = readFileSync(new URL('../fixtures/capability-execution.json', import.meta.url), 'utf8');
const request = () => ({ source: model, entry: 'selected:main#answer', arguments: [], executionMode: 'capability' as const,
  admission: { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: 'permissive' } });

test('HTTP policy negotiation exposes only the validated exact evaluator and captures the accepted selection', async t => {
  const provider = await createExecutionProvider({ mapping: 'capability-checks' });
  t.after(() => provider.close());
  const requests: { path: string; body?: string }[] = [];
  const client = new ExecutionClient('session', { core: core(), pause: () => new Promise(r => setTimeout(r, 5)),
    transport: { async request(path, source) {
      requests.push({ path, body: source });
      const value = path === 'session' ? await provider.session('session') : await provider.command(path as ExecutionOperation, source!, 'session');
      return { ok: true, status: 200, source: JSON.stringify(value) };
    } } });
  assert.equal(client.capabilityEvaluator, undefined);
  await client.initialize();
  assert.equal(client.capabilityEvaluator, 'scheme-portable-v1/shared-sdk/bounded');
  const draft = request();
  const resultPromise = client.execute(draft);
  draft.source = '{}'; draft.admission.policy = 'strict';
  const result = await resultPromise;
  assert.deepEqual(result.typed, { type: 'int', value: '42' });
  assert.equal((client.acceptedPlan as { admission: { policy: string } }).admission.policy, 'permissive');
  assert.equal(JSON.parse(requests.find(r => r.path === 'submit')!.body!).contractVersion, '0.2.0-draft.2');
  assert.equal(requests.filter(r => r.path === 'submit').length, 1);
});

test('HTTP policy negotiation rejects unknown versions, scopes and capability offers without downgrade', async () => {
  const offer = { profile: 'morphir/workbench/executions', contractVersion: '0.2.0-draft.1', hostId: 'host',
    sessionId: 'session', providerId: 'scheme', operations: ['query', 'cancel'] };
  const descriptor = { profile: 'morphir/workbench/host', contractVersion: '0.2.0-draft.2', offer,
    capabilityChecks: { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', runtime: 'scheme',
      evaluator: 'scheme-portable-v1/shared-sdk/bounded', policies: ['strict', 'permissive'] } };
  for (const invalid of [
    { ...descriptor, contractVersion: '0.2.0-draft.2+build' },
    { ...descriptor, offer: { ...offer, sessionId: 'other' } },
    { ...descriptor, capabilityChecks: { ...descriptor.capabilityChecks, policies: ['strict'] } },
    { ...descriptor, capabilityChecks: { ...descriptor.capabilityChecks, runtime: 'javascript' } },
  ]) {
    const client = new ExecutionClient('session', { core: core(), fetchFn: async () => new Response(JSON.stringify(invalid)) });
    await assert.rejects(client.initialize(), /incompatible|rejected/);
    assert.equal(client.capabilityEvaluator, undefined);
  }
});

test('HTTP reconnect reauthenticates and preserves the accepted selection when the offer changes', async t => {
  for (const change of ['auth', 'offer'] as const) {
    const provider = await createExecutionProvider({ mapping: 'capability-checks' });
    t.after(() => provider.close());
    let authenticated = true, changed = false, lost = false, submits = 0, queries = 0;
    const client = new ExecutionClient('session', { core: core(), authenticate: async () => {
      if (!authenticated) throw new Error('Authentication expired');
      return 'session';
    }, pause: () => new Promise(resolve => setTimeout(resolve, 5)), transport: { async request(path, source) {
      if (path === 'session') {
        const descriptor = await provider.session('session');
        if (changed) descriptor.offer.operations = ['query'];
        return { ok: true, status: 200, source: JSON.stringify(descriptor) };
      }
      if (path === 'submit') submits++;
      if (path === 'query') {
        queries++;
        if (!lost) { lost = true; throw new Error('Lost query reply'); }
      }
      const value = await provider.command(path as ExecutionOperation, source!, 'session');
      return { ok: true, status: 200, source: JSON.stringify(value) };
    } } });
    await client.initialize();
    await assert.rejects(client.execute(request()), /Lost query reply/);
    const retained = structuredClone(client.acceptedPlan);
    const execution = structuredClone(client.execution);
    if (change === 'auth') authenticated = false; else changed = true;
    await assert.rejects(client.resume(), /Authentication expired|capabilities changed/);
    assert.deepEqual(client.acceptedPlan, retained);
    assert.deepEqual(client.execution, execution);
    assert.equal(submits, 1); assert.equal(queries, 1);
    authenticated = true; changed = false;
    const result = await client.resume();
    assert.deepEqual(result.typed, { type: 'int', value: '42' });
    assert.deepEqual(client.acceptedPlan, retained);
    assert.equal(submits, 1);
  }
});

test('one HTTP initialization owns negotiation while concurrent callers and execution run', async t => {
  const provider = await createExecutionProvider({ mapping: 'capability-checks' });
  t.after(() => provider.close());
  let descriptorCalls = 0;
  let deliver: (() => void) | undefined;
  const gate = new Promise<void>(resolve => { deliver = resolve; });
  const client = new ExecutionClient('session', { core: core(), pause: () => new Promise(resolve => setTimeout(resolve, 5)),
    transport: { async request(path, source) {
      if (path === 'session') {
        descriptorCalls++;
        await gate;
        return { ok: true, status: 200, source: JSON.stringify(await provider.session('session')) };
      }
      const value = await provider.command(path as ExecutionOperation, source!, 'session');
      return { ok: true, status: 200, source: JSON.stringify(value) };
    } } });
  const first = client.initialize();
  const second = client.initialize();
  deliver!();
  assert.equal(await first, true); assert.equal(await second, true);
  assert.equal(descriptorCalls, 1, 'Concurrent initialization shares one immutable negotiation');
  const pending = client.execute(request());
  // An accepted or pending execution cannot cause another descriptor request.
  // Repeated initialize is idempotent and cannot race a replacement authority.
  assert.equal(await client.initialize(), true);
  const result = await pending;
  assert.equal(result.success, true);
  assert.equal(descriptorCalls, 1);
  assert.equal(client.capabilityEvaluator, 'scheme-portable-v1/shared-sdk/bounded');
  assert.equal((client.acceptedPlan as { admission: { policy: string } }).admission.policy, 'permissive');
});

test('a held HTTP reauthentication reserves the retained execution against submit and another resume', async t => {
  const provider = await createExecutionProvider({ mapping: 'capability-checks' });
  t.after(() => provider.close());
  let authenticate: (() => void) | undefined;
  const authentication = new Promise<void>(resolve => { authenticate = resolve; });
  let submits = 0, descriptors = 0;
  const client = new ExecutionClient('session', { core: core(), pause: () => new Promise(resolve => setTimeout(resolve, 5)),
    authenticate: async () => { await authentication; return 'session'; },
    transport: { async request(path, source) {
      if (path === 'session') descriptors++;
      if (path === 'submit') submits++;
      const value = path === 'session' ? await provider.session('session') : await provider.command(path as ExecutionOperation, source!, 'session');
      return { ok: true, status: 200, source: JSON.stringify(value) };
    } } });
  await client.initialize(); await client.execute(request());
  const identity = structuredClone(client.execution!.identity), plan = structuredClone(client.acceptedPlan);
  const pending = client.resume();
  await assert.rejects(client.execute(request()), /already active/);
  await assert.rejects(client.resume(), /already being observed/);
  assert.equal(submits, 1); assert.equal(descriptors, 1);
  assert.deepEqual(client.execution!.identity, identity); assert.deepEqual(client.acceptedPlan, plan);
  authenticate!();
  assert.equal((await pending).success, true);
  assert.equal(client.active, false);
  assert.equal(descriptors, 2);
  assert.deepEqual(client.execution!.identity, identity); assert.deepEqual(client.acceptedPlan, plan);
  await client.execute(request());
  assert.equal(submits, 2);
  assert.notDeepEqual(client.execution!.identity, identity);
});
