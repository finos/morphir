import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { resolve } from 'node:path';
import { isRecord } from '../../../types/data.ts';

// Fixture validity check, separate from MCK verdicts. Expected Int 42 is fixed
// by the published fixture program, never derived from observed client output.
const [kit, worker] = process.argv.slice(2);
if (!kit || !worker)
  throw new Error('Pass the selected kit and compiled production worker');
const corpus: unknown = JSON.parse(
  readFileSync(resolve(kit, 'cases.json'), 'utf8'),
);
if (!isRecord(corpus) || !Array.isArray(corpus.cases))
  throw new Error('Invalid fixture corpus');
let response: unknown;
const self: {
  onmessage?: (event: unknown) => void;
  postMessage: (message: { result: unknown }) => void;
} = {
  postMessage(message) {
    response = structuredClone(message.result);
  },
};
runInNewContext(readFileSync(worker, 'utf8'), {
  self,
  TextEncoder,
  TextDecoder,
  console,
  atob,
  btoa,
});
function request(request: unknown) {
  response = undefined;
  self.onmessage?.({ data: { id: 1, request } });
  if (!isRecord(response))
    throw new Error('Production worker did not return a result');
  assert.equal(response.success, true);
  return response;
}
function evaluate(source: string, entry: string) {
  const result = request({
    operation: 'evaluate',
    executionMode: 'typed',
    source,
    entry,
    arguments: [],
  });
  assert.deepEqual(result.typed, { type: 'int', value: '42' });
}
const selected = [
  'workspace-exact-morphir-json',
  'workspace-exact-ion-text',
  'workspace-exact-ion-binary',
  'workspace-two-chunks-exact-offsets',
];
let count = 0;
for (const item of corpus.cases) {
  if (!isRecord(item) || !selected.includes(String(item.id))) continue;
  if (
    !isRecord(item.input) ||
    !isRecord(item.input.evaluation) ||
    !Array.isArray(item.input.invocations)
  )
    throw new Error('Missing concrete fixture inputs');
  const evaluation = item.input.evaluation;
  if (
    typeof evaluation.model !== 'string' ||
    typeof evaluation.entry !== 'string'
  )
    throw new Error('Missing runnable model');
  evaluate(evaluation.model, evaluation.entry);
  const invocations = item.input.invocations.filter(isRecord);
  const opening = invocations.find((x) => x.operation === 'workspace.open');
  if (typeof opening?.source !== 'string')
    throw new Error('Missing transfer descriptor');
  const opened: unknown = JSON.parse(opening.source);
  if (!isRecord(opened) || !isRecord(opened.value))
    throw new Error('Missing transfer metadata');
  const chunks = invocations
    .filter((x) => x.operation === 'workspace.read')
    .map((x) => {
      if (typeof x.source !== 'string') throw new Error('Missing chunk bytes');
      const reply: unknown = JSON.parse(x.source);
      if (
        !isRecord(reply) ||
        !isRecord(reply.value) ||
        typeof reply.value.content !== 'string'
      )
        throw new Error('Invalid chunk fixture');
      return Buffer.from(reply.value.content, 'base64');
    });
  const bytes = Buffer.concat(chunks);
  assert.equal(bytes.length, opened.value.size);
  const inspected = request({
    operation: 'inspect',
    source: '',
    sourceCodec: opened.value.format,
    sourceBase64: bytes.toString('base64'),
  });
  if (typeof inspected.irSource !== 'string')
    throw new Error('Inspection did not return a model');
  evaluate(inspected.irSource, evaluation.entry);
  count++;
}
assert.equal(count, selected.length);
console.log(
  'Four concrete JSON/Ion assets import and evaluate to exact Int 42 through the production worker',
);
