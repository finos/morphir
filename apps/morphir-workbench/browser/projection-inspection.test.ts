import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {LocalAdapter} from './transport.ts';
import type {WorkerPort, WorkRequest} from './contracts.ts';
import {inventoryDigest, receiveOriginalsWithProjection, type Hasher, type VerifiedProjection} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';
import type {ModelOriginalsProject, ModelOriginalsSession} from '../../../pkgs/morphir-host/model-originals-client/session.ts';

const {ProjectionHeaderLimits, recognizeProjectionHeader}: typeof import('./verify-projection-header.ts') =
  await import(new URL('../dist/verify-projection-header.js', import.meta.url).href);
const bounds = ProjectionHeaderLimits.create({maxBytes: 64 * 1024 * 1024, maxDepth: 128, maxValues: 100000});
const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const hash = (): Hasher => {const value = createHash('sha256'); return {update(bytes) {value.update(bytes);}, hex() {return value.digest('hex');}};};

// Scripted transport, actual shared receiver + compiled header reader. This
// constructs no test-only projection owner and makes no host/platform claim.
async function verified(text: string): Promise<VerifiedProjection> {
  const bytes = Buffer.from(text), original = Buffer.alloc(0);
  const prefix = {profile: 'morphir/workbench/model-originals', contractVersion: '0.1.0-draft.1'};
  const binding = {sessionId: 'session', source: {providerId: 'provider', locator: 'workspace:model'}, projectId: 'project'};
  const entries = [{kind: 'file' as const, entryId: 'original', path: 'morphir-ir.json', byteLength: 0, sha256: digest(original)}];
  const inventorySha256 = inventoryDigest(entries, hash());
  let id = 0, released = false;
  const exchange = (result: unknown) => ({requestId: String(++id), request: '', reply: JSON.stringify({jsonrpc: '2.0', id, result})});
  const session: ModelOriginalsSession = {
    sessionId: binding.sessionId, sources: [], async openSource() {return [];}, close() {},
    async exchangeCapture() {return exchange({...prefix, status: 'ready', binding, captureId: 'capture',
      coverage: {kind: 'complete', declaration: prefix.contractVersion}, origin: {kind: 'legacy-json', path: 'morphir-ir.json'},
      primary: {kind: 'file', path: 'morphir-ir.json'}, companions: [], sourceFormatVersion: {status: 'not-reported'},
      projection: {status: 'available', codec: 'morphir-json', byteLength: bytes.length, sha256: digest(bytes),
        formatVersion: recognizeProjectionHeader(bytes, bounds)},
      inventory: {entryCount: 1, fileCount: 1, directoryCount: 0, sourceByteLength: 0, sha256: inventorySha256}});},
    async exchangeOriginals(method, raw) {
      const input = raw as {offset: number; target: {kind: string}};
      if (method === 'release') {released = true; return exchange({...prefix, captureId: 'capture', status: 'released'});}
      if (method === 'inventory') return exchange({...prefix, binding, captureId: 'capture', inventorySha256,
        startIndex: 0, entries, next: {kind: 'complete'}});
      const content = input.target.kind === 'semantic-projection' ? bytes : original;
      const next = Math.min(content.length, input.offset + 65536);
      return exchange({...prefix, binding, captureId: 'capture', target: input.target, offset: input.offset,
        nextOffset: next, content: content.subarray(input.offset, next).toString('base64')});
    },
  };
  const result = await receiveOriginalsWithProjection(session, {projectId: 'project', name: 'Actual project'} as ModelOriginalsProject,
    binding, {inventory() {}, begin() {}, write() {}, end() {}}, hash, () => true,
    actual => recognizeProjectionHeader(actual, bounds));
  assert(released);
  assert.equal(result.projection.kind, 'verified');
  if (result.projection.kind !== 'verified') throw new Error('verified projection required');
  return result.projection.value;
}

test('only receiver-owned projections enter the private worker path, ordinary input limits stay unchanged', async () => {
  let workers = 0, captured: WorkRequest | undefined;
  const adapter = new LocalAdapter(() => {
    workers++;
    const port: WorkerPort = {terminate() {}, postMessage(message) {
      captured = message.request;
      queueMicrotask(() => port.onmessage?.({data: {id: message.id, result: {success: true}}}));
    }};
    return port;
  });
  for (const forged of [{copyBytes: () => Buffer.from('{}')}, null, {}]) {
    await assert.rejects(adapter.inspectProjection(forged as unknown as VerifiedProjection));
  }
  assert.equal(workers, 0);
  const source = `{"formatVersion":4,"padding":"${'x'.repeat(16 * 1024 * 1024)}"}`;
  await assert.rejects(adapter.execute({operation: 'inspect', source}), /16 MiB/);
  await assert.rejects(adapter.execute({operation: 'inspect-connected-projection', source: '{}'}), /projection/i);
  assert.equal(workers, 0);
  const projection = await verified(source);
  projection.copyBytes().fill(0);
  assert.equal((await adapter.inspectProjection(projection)).success, true);
  assert.equal(workers, 1);
  assert.equal(captured?.operation, 'inspect-connected-projection');
  assert.equal(Buffer.from(captured!.sourceBase64!, 'base64').toString(), source);
  assert.equal(captured?.sourceCodec, undefined);
});

test('actual compiled worker inspects a released projection and preserves typed refusal for unsupported versions', async () => {
  const adapter = new LocalAdapter(() => {
    const worker = new Worker(new URL('../dist/worker.js', import.meta.url).href);
    const port: WorkerPort = {postMessage(message) {worker.postMessage(message);}, terminate() {void worker.terminate();}};
    worker.onmessage = event => port.onmessage?.(event);
    worker.onerror = () => port.onerror?.();
    return port;
  });
  try {
    const source = '{"formatVersion":4,"distribution":{"Library":{"packageName":"example","dependencies":{},"def":{"modules":{}}}}}';
    const result = await adapter.inspectProjection(await verified(source));
    assert.equal(result.success, true, result.message ?? "Projection inspection failed");
    assert(result.ir);
    assert.equal(result.modelSource?.kind, 'semantic-projection');
    const large = await adapter.inspectProjection(await verified(' '.repeat(16 * 1024 * 1024 + 1) + source));
    assert.equal(large.success, true, large.message ?? "Projection inspection failed");
    assert.deepEqual(large.ir, result.ir);
    const unsupported = await adapter.inspectProjection(await verified('{"formatVersion":99,"distribution":null}'));
    assert.equal(unsupported.success, false);
    assert.equal(unsupported.ir, undefined);
  } finally {adapter.dispose();}
});

test('cancelling projection inspection refuses its late worker reply without a second result', async () => {
  let worker!: WorkerPort, requestId = 0, terminated = 0;
  const adapter = new LocalAdapter(() => worker = {terminate() {terminated++;}, postMessage(message) {requestId = message.id;}});
  const pending = adapter.inspectProjection(await verified('{"formatVersion":4}'));
  adapter.cancelModelOpen();
  await assert.rejects(pending, /Cancelled/);
  worker.onmessage?.({data: {id: requestId, result: {success: true}}});
  assert.equal(terminated, 1);
  assert.equal(adapter.active, null);
});
