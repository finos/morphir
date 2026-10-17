import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { resolve } from 'node:path';
import { isRecord } from '../../../types/data.ts';

// Input validity evidence is separate from the shared MCK verdict. Every
// selected fixture is a complete program whose published result is Int 42.
const [kit, worker] = process.argv.slice(2);
if (!kit || !worker) throw new Error('Pass the selected kit and production worker');
const corpus: unknown = JSON.parse(readFileSync(resolve(kit, 'cases.json'), 'utf8'));
if (!isRecord(corpus) || !Array.isArray(corpus.cases))
  throw new Error('Invalid owner fixture corpus');
let response: unknown;
const self: {
  onmessage?: (event: unknown) => void;
  postMessage: (message: { result: unknown }) => void;
} = { postMessage(message) { response = structuredClone(message.result); } };
runInNewContext(readFileSync(worker, 'utf8'), {
  self, TextEncoder, TextDecoder, console, atob, btoa,
});
function request(value: unknown) {
  response = undefined;
  self.onmessage?.({ data: { id: 1, request: value } });
  if (!isRecord(response)) throw new Error('Production worker did not respond');
  assert.equal(response.success, true);
  return response;
}
function evaluate(source: string, entry: string) {
  assert.deepEqual(request({
    operation: 'evaluate', executionMode: 'typed', source, entry, arguments: [],
  }).typed, { type: 'int', value: '42' });
}
const selected = new Map([
  ['workspace-exact-morphir-json', 'morphir-json'],
  ['workspace-exact-ion-text', 'ion-text'],
  ['workspace-exact-ion-binary', 'ion-binary'],
  ['workspace-two-chunks-exact-offsets', 'morphir-json'],
]);
const seen = new Set<string>();
for (const item of corpus.cases) {
  if (!isRecord(item) || typeof item.id !== 'string' || !selected.has(item.id))
    continue;
  assert.equal(seen.has(item.id), false);
  seen.add(item.id);
  if (!isRecord(item.input) || !isRecord(item.input.evaluation) ||
      !Array.isArray(item.input.roots)) throw new Error('Missing concrete inputs');
  const evaluation = item.input.evaluation;
  if (typeof evaluation.model !== 'string' || typeof evaluation.entry !== 'string')
    throw new Error('Missing runnable model and entry');
  evaluate(evaluation.model, evaluation.entry);
  const root = item.input.roots[0];
  if (!isRecord(root) || typeof root.manifest !== 'string' || !Array.isArray(root.files))
    throw new Error('Missing complete workspace root');
  const file = root.files[0];
  if (!isRecord(file) || typeof file.source !== 'string' ||
      !['utf8', 'base64'].includes(String(file.encoding)))
    throw new Error('Missing checkpoint bytes');
  const bytes = Buffer.from(file.source, file.encoding === 'base64' ? 'base64' : 'utf8');
  const inspected = request({
    operation: 'inspect', source: '', sourceCodec: selected.get(item.id),
    sourceBase64: bytes.toString('base64'),
  });
  if (typeof inspected.irSource !== 'string') throw new Error('Importer returned no model');
  evaluate(inspected.irSource, evaluation.entry);
}
assert.deepEqual([...seen].sort(), [...selected.keys()].sort());
console.log('Four owner JSON/Ion checkpoint inputs import and evaluate to exact Int 42');
