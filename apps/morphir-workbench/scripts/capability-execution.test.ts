import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { setTimeout as pause } from 'node:timers/promises';
import { Worker } from 'node:worker_threads';
import { createExecutionProvider } from './execution-provider.ts';
import type { Identity, ExecutionProvider, Receipt, SchemeExecutionPlan, SchemeSubmission } from './execution-contracts.ts';

const version = '0.2.0-draft.1';
const session = 'capability-session';
const admission = (policy: string) => ({ profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy });
const model = await readFile(new URL('../fixtures/capability-execution.json', import.meta.url), 'utf8');
const body = (identity: Identity) => JSON.stringify({ contractVersion: version, identity });
const selection = (plan: SchemeExecutionPlan) => ({ planId: plan.planId, providerId: plan.identity.providerId, runtime: plan.runtime, policy: plan.admission.policy });
const submission = (source = model, policy: string | null = 'permissive', format = 'json') => JSON.stringify({
  contractVersion: version, model: source, entry: 'selected:main#answer', runtime: 'scheme', providerId: 'moonbit-scheme',
  inputs: { format, source: '[]' }, ...(policy === null ? {} : { admission: admission(policy) }),
});
async function terminal(provider: ExecutionProvider, identity: Identity): Promise<Receipt> {
  for (let attempt = 0; attempt < 300; attempt++) {
    const receipt = await provider.command('query', body(identity), session);
    if (receipt.state === 'terminal') return receipt;
    await pause(10);
  }
  throw new Error('Owned Scheme worker did not finish');
}

test('current MoonBit String and Int32 libraries retain policy through real Scheme executions', async t => {
  type Compiled = { success: boolean; irSource: string; nodes: { id: string; label: string }[] };
  const scope: { result?: Compiled; postMessage(value: { result: Compiled }): void;
    onmessage?: (event: { data: { id: number; request: Record<string, unknown> } }) => void } = {
    postMessage(value) { this.result = value.result; },
  };
  const previousSelf: unknown = Reflect.get(globalThis, 'self');
  try {
    Object.assign(globalThis, { self: scope });
    await import(new URL('../_build/js/release/build/finos/morphir-workbench/worker/worker.js', import.meta.url).href);
    assert.equal(typeof scope.onmessage, 'function');
    scope.onmessage!({ data: { id: 1, request: {
      operation: 'compile', languageId: 'moonbit', target: 'moonbit',
      frontendProfile: 'moonbit-model-library-2026-10-17',
      source: 'pub fn welcome(name : String) -> String { "Hi " + name }\n'
        + 'pub fn choose(count : Int, other : Int, left : String, right : String) -> Int { if left < right { count } else { other } }',
    } } });
  } finally {
    if (previousSelf === undefined) Reflect.deleteProperty(globalThis, 'self');
    else Reflect.set(globalThis, 'self', previousSelf);
  }
  const compiled = scope.result;
  assert.ok(compiled?.success, JSON.stringify(compiled));
  const bounded = { type: 'custom', owner: 'morphir/SDK:int#int-32', tag: 'morphir/SDK:int#int32',
    items: [{ type: 'int', value: '2147483647' }] };
  const cases = [
    { name: 'welcome', arguments: [{ type: 'text', units: [55357, 56832] }], value: { type: 'text', units: [72, 105, 32, 55357, 56832] } },
    { name: 'choose', arguments: [bounded, { ...bounded, items: [{ type: 'int', value: '-2147483648' }] },
      { type: 'text', units: [98] }, { type: 'text', units: [97, 97] }], value: bounded },
  ];
  const provider = await createExecutionProvider(); t.after(() => provider.close());
  for (const policy of ['strict', 'permissive']) for (const example of cases) {
    const entry = compiled.nodes.find(node => node.label === example.name)?.id.replace(/^value\|/, '');
    assert.ok(entry, example.name);
    const accepted: SchemeSubmission = await provider.schemeCommand('submit-scheme', JSON.stringify({
      contractVersion: version, model: compiled.irSource, entry, runtime: 'scheme', providerId: 'moonbit-scheme',
      inputs: { format: 'json', source: JSON.stringify(example.arguments) }, admission: admission(policy),
    }), session);
    const captured: SchemeExecutionPlan = structuredClone(accepted.plan);
    const result = await terminal(provider, accepted.identity);
    assert.deepEqual(result.outcomes?.calls[0]?.outcome, { status: 'returned', value: example.value });
    assert.equal(captured.admission.policy, policy);
    assert.deepEqual(await provider.schemeCommand('plan-scheme', body(accepted.identity), session), captured);
    await provider.command('release', body(accepted.identity), session);
  }
});

test('real Scheme worker uses captured policy and rich snapshot for JSON and Ion executions', async t => {
  const requests: unknown[] = [];
  const workers: Worker[] = [];
  const provider = await createExecutionProvider({ workerFactory: () => {
    const worker = new Worker(new URL('./execution-worker.ts', import.meta.url), {
      workerData: { module: new URL('../_build/js/release/build/finos/morphir-workbench/worker/worker.js', import.meta.url).href },
    });
    const send = worker.postMessage.bind(worker);
    worker.postMessage = value => { requests.push(structuredClone(value)); send(value); };
    workers.push(worker); return worker;
  } });
  t.after(() => provider.close());
  for (const format of ['json', 'ion-text']) {
    const accepted = await provider.schemeCommand('submit-scheme', submission(model, 'permissive', format), session);
    const captured = structuredClone(accepted.plan);
    accepted.plan.admission.policy = 'strict';
    accepted.plan.boundary = null;
    assert.deepEqual(await provider.schemeCommand('plan-scheme', body(accepted.identity), session), captured);
    const receipt = await terminal(provider, accepted.identity);
    assert.deepEqual(receipt.outcomes?.calls[0]?.outcome, { status: 'returned', value: { type: 'int', value: '42' } });
    assert.equal(workers.at(-1)?.threadId, -1, 'The host publishes after actual worker exit');
    const request = requests.at(-1) as { request: { operation: string; snapshot: { sourceBase64: string }; plan: SchemeExecutionPlan } };
    assert.equal(request.request.operation, 'evaluate-scheme-execution');
    assert.ok(request.request.snapshot.sourceBase64.length > 0);
    assert.deepEqual(request.request.plan, captured);
    await provider.command('release', body(accepted.identity), session);
  }
  assert.equal(workers.length, 2);
});

test('strict omission is retained and permissive reached operations stay typed failures', async t => {
  const provider = await createExecutionProvider(); t.after(() => provider.close());
  await assert.rejects(provider.schemeCommand('submit-scheme', submission(model, null), session));
  const plain = JSON.parse(model);
  plain.distribution.Library.def.modules.main.Public.values.answer.Public.ExpressionBody.body = { Literal: { IntegerLiteral: 42 } };
  const strict = await provider.schemeCommand('submit-scheme', submission(JSON.stringify(plain), null), session);
  assert.equal(strict.plan.admission.policy, 'strict');
  assert.equal((await terminal(provider, strict.identity)).outcomes?.calls[0]?.outcome.status, 'returned');
  assert.equal((await provider.schemeCommand('plan-scheme', body(strict.identity), session)).admission.policy, 'strict');
  const reached = JSON.parse(model);
  reached.distribution.Library.def.modules.main.Public.values.answer.Public.ExpressionBody.body.IfThenElse.condition = true;
  const execution = await provider.schemeCommand('submit-scheme', submission(JSON.stringify(reached)), session);
  const result = (await terminal(provider, execution.identity)).outcomes?.calls[0]?.outcome;
  assert.equal(result?.status, 'failed');
  assert.equal(result?.failure?.stage, 'evaluate');
  assert.equal(result?.failure?.code, 'execution.unsupported_reached');
});

test('replan retains source and policy with new identities; mismatched selection never resubmits', async t => {
  const provider = await createExecutionProvider(); t.after(() => provider.close());
  const first = await provider.schemeCommand('submit-scheme', submission(), session);
  const old = await terminal(provider, first.identity);
  for (const change of [{ providerId: 'replacement' }, { runtime: 'javascript' }, { policy: 'strict' }, { planId: 'plan-stale' }]) {
    await assert.rejects(provider.schemeCommand('replan-scheme', JSON.stringify({ contractVersion: version, identity: first.identity,
      selection: { ...selection(first.plan), ...change } }), session));
    assert.deepEqual(await provider.command('query', body(first.identity), session), old);
  }
  await provider.session(session);
  assert.deepEqual(await provider.command('query', body(first.identity), session), old, 'Reconnect/query retain original receipt');
  const replanned = await provider.schemeCommand('replan-scheme', JSON.stringify({ contractVersion: version, identity: first.identity,
    selection: selection(first.plan) }), session);
  assert.notEqual(replanned.identity.executionId, first.identity.executionId);
  assert.notEqual(replanned.identity.snapshotId, first.identity.snapshotId);
  assert.notEqual(replanned.plan.planId, first.plan.planId);
  assert.deepEqual(replanned.plan.boundary, first.plan.boundary);
  assert.equal(replanned.plan.admission.policy, 'permissive');
  assert.equal((await terminal(provider, replanned.identity)).outcomes?.calls[0]?.outcome.status, 'returned');
  assert.deepEqual(await provider.command('query', body(first.identity), session), old);
});

test('a real worker with a changed policy cannot publish an apparently valid result', async t => {
  const provider = await createExecutionProvider({ workerFactory: () => {
    const worker = new Worker(new URL('./execution-worker.ts', import.meta.url), {
      workerData: { module: new URL('../_build/js/release/build/finos/morphir-workbench/worker/worker.js', import.meta.url).href },
    });
    const send = worker.postMessage.bind(worker);
    worker.postMessage = value => {
      const changed = structuredClone(value);
      changed.request.plan.admission.policy = 'strict'; send(changed);
    };
    return worker;
  } });
  t.after(() => provider.close());
  const execution = await provider.schemeCommand('submit-scheme', submission(), session);
  const outcome = (await terminal(provider, execution.identity)).outcomes?.calls[0]?.outcome;
  assert.equal(outcome?.status, 'failed');
  assert.equal(outcome?.failure?.code, 'workbench.worker_selection');
  assert.equal((await provider.schemeCommand('plan-scheme', body(execution.identity), session)).admission.policy, 'permissive');
});

test('a mismatched first worker plan remains a failure after a valid-looking second result', async t => {
  const script = `self.onmessage = ({ data }) => {
    const plan = data.request.plan;
    const terminalOutcomes = { contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome:
      { status: 'returned', value: { type: 'int', value: '42' } } }], cleanup: null, extensions: null };
    self.postMessage({ id: 1, result: { terminalOutcomes, executionPlan: { ...plan, planId: 'stale-plan' } } });
    self.postMessage({ id: 1, result: { terminalOutcomes, executionPlan: plan } });
  };`;
  const provider = await createExecutionProvider({ workerFactory: () => new Worker(new URL('./execution-worker.ts', import.meta.url), {
    workerData: { module: `data:text/javascript,${encodeURIComponent(script)}` },
  }) });
  t.after(() => provider.close());
  const execution = await provider.schemeCommand('submit-scheme', submission(), session);
  const outcome = (await terminal(provider, execution.identity)).outcomes?.calls[0]?.outcome;
  assert.equal(outcome?.status, 'failed');
  assert.equal(outcome?.failure?.code, 'workbench.worker_selection');
});
