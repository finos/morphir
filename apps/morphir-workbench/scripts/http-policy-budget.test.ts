import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Worker } from 'node:worker_threads';
import { createExecutionProvider } from './execution-provider.ts';

const fixture = readFileSync(new URL('../fixtures/capability-execution.json', import.meta.url), 'utf8');
const selection = { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: 'permissive' };
const body = (model: string, version = '0.2.0-draft.2') => JSON.stringify({ contractVersion: version, model,
  entry: 'selected:main#answer', inputs: { format: 'json', source: '[]' }, runtime: 'scheme',
  providerId: 'moonbit-scheme', admission: selection });
function wideModel(width: number) {
  const model = JSON.parse(fixture);
  const fields: Record<string, string> = {};
  for (let i = 0; i < 1000; i++) fields[`f${String(i).padStart(4, '0')}${'a'.repeat(width)}`] = 'morphir/SDK:basics#int';
  model.distribution.Library.def.modules.main.Public.values.answer.Public.ExpressionBody.outputType = { Record: { fields } };
  return JSON.stringify(model);
}

test('HTTP reserves the entire serialized accepted reply before publishing or starting a worker', async t => {
  let workers = 0;
  const provider = await createExecutionProvider({ mapping: 'capability-checks', workerFactory: () => {
    workers++;
    return new Worker(new URL('./execution-worker.ts', import.meta.url), {
      workerData: { module: new URL('../_build/js/release/build/finos/morphir-workbench/worker/worker.js', import.meta.url).href },
    });
  } });
  t.after(() => provider.close());
  const descriptor = await provider.session('session');
  const createHost = globalThis.morphirWorkbenchExecutionHost;
  const oversized = wideModel(1009);
  const request = body(oversized);
  assert.ok(Buffer.byteLength(request) < 1048576, 'Public request fits the complete input frame');
  // The existing private path establishes that this is a valid selected model
  // and its boundary fits. Only the full public reply exceeds the frame budget.
  const host = createHost(JSON.stringify(descriptor.offer));
  const privateReply = JSON.parse(host(JSON.stringify({ op: 'submit-scheme', body: body(oversized, '0.2.0-draft.1') })));
  assert.equal(privateReply.ok, true);
  assert.ok(Buffer.byteLength(JSON.stringify(privateReply.value.plan.boundary)) <= 1048576);
  assert.ok(Buffer.byteLength(JSON.stringify(privateReply.value)) > 1048576);
  await assert.rejects(provider.command('submit', request, 'session'), { code: 'workbench.host_input_limit', status: 413 });
  assert.equal(workers, 0);
  const accepted = await provider.command('submit', body(fixture), 'session');
  assert.equal(accepted.identity.executionId, 'execution-1', 'Rejected reply consumes no execution identity');
  assert.equal(accepted.plan?.planId, 'plan-1', 'Rejected reply consumes no retained plan identity');
  assert.equal(workers, 1);
});

test('near-limit HTTP reply remains within budget after the actual Node JSON roundtrip', async t => {
  const provider = await createExecutionProvider({ mapping: 'capability-checks' });
  t.after(() => provider.close());
  const descriptor = await provider.session('session');
  const host = globalThis.morphirWorkbenchExecutionHost(JSON.stringify(descriptor.offer));
  const reply = JSON.parse(host(JSON.stringify({ op: 'submit-http-policy', body: body(wideModel(1008)) })));
  assert.equal(reply.ok, true);
  const encoded = JSON.stringify(reply.value);
  assert.ok(Buffer.byteLength(encoded) > 1047000);
  assert.ok(Buffer.byteLength(encoded) <= 1048576);
  assert.equal(JSON.stringify(JSON.parse(encoded)), encoded);
});
