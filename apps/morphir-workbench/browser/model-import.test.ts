import test from 'node:test';
import assert from 'node:assert/strict';
import { captureOriginalRequest, ModelImporter, readModelFile, type ModelFile, type ModelInput } from './model-import.ts';
import type { WorkRequest, WorkResult } from './contracts.ts';

const limit = 16 * 1024 * 1024;
const bytes = (name: string, contents: number[]): ModelFile => ({
  name, size: contents.length, async arrayBuffer() { return Uint8Array.from(contents).buffer; },
});
const flush = () => new Promise<void>(resolve => setImmediate(resolve));

test('file capture retains exact BOM CRLF binary and numeric lexeme bytes across codecs', async () => {
  const raw = new TextEncoder().encode('\ufeff{\r\n"number":90071992547409931234567890}\r\n');
  for (const [name, codec] of [['model.JSON', 'morphir-json'], ['model.ion', 'ion-text'], ['model.ionb', 'ion-binary']] as const) {
    const data = name.endsWith('ionb') ? [0, 255, 128, 1] : [...raw];
    const selected = await readModelFile(bytes(name, data));
    assert.equal(selected.kind, 'selected');
    if (selected.kind !== 'selected') throw new Error('expected selection');
    assert.equal(selected.codec, codec);
    assert.deepEqual([...Buffer.from(selected.contentBase64, 'base64')], data);
  }
});

test('invalid names codecs and declared sizes are refused before reading', async () => {
  let reads = 0;
  for (const [name, size, reason] of [
    ['../model.json', 0, 'invalid-name'], ['model\0.json', 0, 'invalid-name'],
    ['a'.repeat(257) + '.json', 0, 'invalid-name'], ['model.exe', 0, 'unsupported-codec'],
    ['model.json', limit + 1, 'oversized'], ['model.json', -1, 'oversized'],
    ['model.json', 0.5, 'oversized'],
  ] as const) {
    assert.deepEqual(await readModelFile({ name, size, async arrayBuffer() { reads++; return new ArrayBuffer(0); } }), { kind: 'refused', reason });
  }
  assert.equal(reads, 0);
});

test('file reads enforce actual size, handle failures and capture metadata before awaiting', async () => {
  assert.deepEqual(await readModelFile({ ...bytes('model.json', [1]), size: 2 }), { kind: 'refused', reason: 'unreadable' });
  assert.deepEqual(await readModelFile({ name: 'model.json', size: 1, async arrayBuffer() { return new ArrayBuffer(limit + 1); } }), { kind: 'refused', reason: 'oversized' });
  assert.deepEqual(await readModelFile({ name: 'model.json', size: 1, async arrayBuffer() { throw new Error('disk unavailable'); } }), { kind: 'refused', reason: 'unreadable' });
  let resolve!: (data: ArrayBuffer) => void;
  const file = { name: 'first.json', size: 1, arrayBuffer: () => new Promise<ArrayBuffer>(done => { resolve = done; }) };
  const pending = readModelFile(file);
  file.name = 'later.exe'; file.size = 99;
  resolve(Uint8Array.of(42).buffer);
  assert.deepEqual(await pending, { kind: 'selected', filename: 'first.json', codec: 'morphir-json', contentBase64: 'Kg==' });
});

class Input implements ModelInput {
  type = ''; accept = ''; files: ModelFile[] = []; removed = 0;
  listeners = new Map<string, () => void>();
  addEventListener(type: string, listener: () => void): void { this.listeners.set(type, listener); }
  click(): void {}
  remove(): void { this.removed++; }
  fire(type: string): void { this.listeners.get(type)?.(); }
}

test('a replaced picker cannot publish after a newer selection', async () => {
  const inputs: Input[] = [], replies: string[] = [];
  const importer = new ModelImporter(() => { const input = new Input(); inputs.push(input); return input; });
  let resolve!: (data: ArrayBuffer) => void;
  importer.start('1', reply => replies.push(reply));
  const first = inputs[0]!;
  first.files = [{ name: 'old.json', size: 1, arrayBuffer: () => new Promise(done => { resolve = done; }) }];
  first.fire('change');
  importer.start('2', reply => replies.push(reply));
  const current = inputs[1]!; current.files = [bytes('new.ionb', [255])]; current.fire('change');
  await flush(); resolve(Uint8Array.of(1).buffer); await flush();
  first.fire('cancel');
  assert.deepEqual(replies.map(reply => JSON.parse(reply) as unknown), [{ kind: 'selected', filename: 'new.ionb', codec: 'ion-binary', contentBase64: '/w==' }]);
  assert.equal(first.removed, 1); assert.equal(current.removed, 1);
});

test('scoped cancellation and disposal suppress only their current read', async () => {
  const input = new Input(), replies: string[] = [];
  const importer = new ModelImporter(() => input);
  let resolve!: (data: ArrayBuffer) => void;
  importer.start('3', reply => replies.push(reply));
  input.files = [{ name: 'pending.json', size: 1, arrayBuffer: () => new Promise(done => { resolve = done; }) }];
  input.fire('change'); importer.cancel('2'); assert.equal(input.removed, 0);
  importer.cancel('3'); resolve(Uint8Array.of(1).buffer); await flush();
  input.fire('cancel'); importer.dispose();
  assert.deepEqual(replies, []); assert.equal(input.removed, 1);
});

test('cancel is published once and unexpected file metadata failures are reported', async () => {
  const inputs: Input[] = [], replies: string[] = [];
  const importer = new ModelImporter(() => { const input = new Input(); inputs.push(input); return input; });
  importer.start('4', reply => replies.push(reply));
  inputs[0]!.fire('cancel'); inputs[0]!.fire('change');
  importer.start('5', reply => replies.push(reply));
  inputs[1]!.files = [{ get name(): string { throw new Error('unreadable metadata'); }, size: 0, async arrayBuffer() { return new ArrayBuffer(0); } }];
  inputs[1]!.fire('change'); await flush();
  assert.deepEqual(replies.map(reply => JSON.parse(reply) as unknown), [{ kind: 'cancelled' }, { kind: 'refused', reason: 'unreadable' }]);
});

test('original enrichment captures request inputs and requires successful version evidence', () => {
  const request: WorkRequest = { operation: 'inspect', source: '', sourceFilename: 'first.json', sourceCodec: 'morphir-json', sourceBase64: 'AQID' };
  const enrich = captureOriginalRequest(request)!;
  request.sourceFilename = 'later.ion'; request.sourceBase64 = '';
  const result: WorkResult = { success: true, sourceFormatVersion: '1.0.0' };
  assert.deepEqual(enrich(result).modelSource, { kind: 'original-file', filename: 'first.json', codec: 'morphir-json', formatVersion: '1.0.0', contentBase64: 'AQID' });
  assert.equal(result.modelSource, undefined);
  const failed: WorkResult = { success: false };
  assert.equal(enrich(failed), failed);
  assert.throws(() => enrich({ success: true }), /input format version/);
  assert.equal(captureOriginalRequest({ operation: 'inspect', source: '' }), null);
});
