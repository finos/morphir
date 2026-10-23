// Scripted session controls of the real shared receiver. The injected literal
// header recognizer does not qualify the compiled MoonBit header boundary.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {
  inventoryDigest, receiveOriginals, receiveOriginalsWithProjection,
  type Binding, type Entry, type Hasher, type OriginalSink, type ReleaseAccepted,
} from './originals.ts';
import type {ModelOriginalsProject, ModelOriginalsSession} from './session.ts';

const hash = (): Hasher => {
  const value = createHash('sha256');
  return {update(bytes) {value.update(bytes);}, hex() {return value.digest('hex');}};
};
const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const source = Buffer.from('\ufeff{"formatVersion":2}\r\n');
const opaque = Buffer.from([0, 255, 1, 128]);
const projection = Buffer.from('{"formatVersion":4,"distribution":null}');
const binding: Binding = {sessionId: 'session-A', source: {providerId: 'provider-A', locator: 'workspace:actual'}, projectId: 'project-A'};
const shared = {profile: 'morphir/workbench/model-originals', contractVersion: '0.1.0-draft.1'};
const entries: Entry[] = [
  {kind: 'file', entryId: 'model', path: 'morphir-ir.json', byteLength: source.length, sha256: digest(source)},
  {kind: 'directory', entryId: 'notes', path: 'notes'},
  {kind: 'directory', entryId: 'empty', path: 'notes/empty'},
  {kind: 'file', entryId: 'opaque', path: 'notes/opaque.bin', byteLength: opaque.length, sha256: digest(opaque)},
];
const ready = {
  ...shared, status: 'ready', binding, captureId: 'capture-A',
  coverage: {kind: 'complete', declaration: shared.contractVersion},
  origin: {kind: 'legacy-json', path: 'morphir-ir.json'},
  primary: {kind: 'file', path: 'morphir-ir.json'}, companions: [{kind: 'directory', path: 'notes'}],
  sourceFormatVersion: {status: 'reported', release: '2.0.0'},
  projection: {status: 'available', codec: 'morphir-json', byteLength: projection.length, sha256: digest(projection), formatVersion: '4.0.0'},
  inventory: {entryCount: 4, fileCount: 2, directoryCount: 2, sourceByteLength: source.length + opaque.length, sha256: inventoryDigest(entries, hash())},
};
type Request = Readonly<{method: string; params: unknown}>;
type FixtureOptions = Readonly<{
  bytes?: Uint8Array;
  descriptor?: unknown;
  mutate?: (method: string, value: Record<string, unknown>, params: unknown) => void;
  before?: (method: string, params: unknown) => void;
}>;
function fixture(options: FixtureOptions = {}) {
  let id = 0;
  const actualProjection = Buffer.from(options.bytes ?? projection);
  const requests: Request[] = [];
  const exchange = (method: string, value: Record<string, unknown>, params: unknown) => {
    const requestId = String(++id);
    options.mutate?.(method, value, params);
    return {requestId, request: '', reply: JSON.stringify({jsonrpc: '2.0', id, result: value})};
  };
  const session: ModelOriginalsSession = {
    sessionId: binding.sessionId, sources: [], openSource: async () => [], close() {},
    async exchangeCapture(_project, options) {
      requests.push({method: 'capture', params: options});
      const capture = structuredClone(ready) as Record<string, unknown>;
      capture.projection = projectionDescriptor;
      before?.('capture', options);
      return exchange('capture', capture, options);
    },
    async exchangeOriginals(method, params) {
      requests.push({method, params});
      before?.(method, params);
      const request = params as {startIndex: number; offset: number; target: {kind: string; entryId?: string}};
      if (method === 'release') return exchange(method, {...shared, captureId: ready.captureId, status: 'released'}, params);
      if (method === 'inventory') return exchange(method, {...shared, binding, captureId: ready.captureId,
        inventorySha256: ready.inventory.sha256, startIndex: request.startIndex, entries, next: {kind: 'complete'}}, params);
      const actual = request.target.kind === 'semantic-projection' ? actualProjection : request.target.entryId === 'model' ? source : opaque;
      const next = Math.min(actual.length, request.offset + 65536);
      return exchange(method, {...shared, binding, captureId: ready.captureId, target: request.target,
        offset: request.offset, nextOffset: next, content: actual.subarray(request.offset, next).toString('base64')}, params);
    },
  };
  const before = options.before;
  const projectionDescriptor = options.descriptor === undefined ? {...ready.projection,
    byteLength: actualProjection.length, sha256: digest(actualProjection)} : options.descriptor;
  const files = new Map<string, Buffer[]>();
  let writing = '';
  const sink: OriginalSink = {
    inventory() {}, begin(index) {writing = entries[index]!.path; files.set(writing, []);},
    write(bytes) {files.get(writing)!.push(Buffer.from(bytes));}, end() {},
  };
  return {session, requests, sink, files};
}
function receive(actual: ReturnType<typeof fixture>, recognize: (bytes: Uint8Array) => string = () => '4.0.0',
  current: () => boolean = () => true, accepted?: (value: ReleaseAccepted) => void) {
  return receiveOriginalsWithProjection(actual.session, {} as ModelOriginalsProject, binding,
    actual.sink, hash, current, recognize, accepted);
}
function projectionRead(method: string, params: unknown): boolean {
  return method === 'read' && (params as {target: {kind: string}}).target.kind === 'semantic-projection';
}

test('complete projection receiver verifies both byte roles and releases before returning', async () => {
  const actual = fixture();
  const recognized: Uint8Array[] = [];
  const received = await receiveOriginalsWithProjection(actual.session, {} as ModelOriginalsProject, binding,
    actual.sink, hash, () => true, bytes => {recognized.push(bytes.slice()); return '4.0.0';});
  assert.deepEqual(actual.requests[0], {method: 'capture', params: {scope: 'complete', semantic: 'projection'}});
  assert.equal(actual.requests.at(-1)!.method, 'release');
  assert.deepEqual(received.capture.sourceFormatVersion, {status: 'reported', release: '2.0.0'});
  assert.deepEqual(Buffer.concat(actual.files.get('morphir-ir.json')!), source);
  assert.deepEqual(Buffer.concat(actual.files.get('notes/opaque.bin')!), opaque);
  assert.equal(received.entries[2]!.path, 'notes/empty');
  assert.equal(received.projection.kind, 'verified');
  if (received.projection.kind !== 'verified') throw new Error('verified projection required');
  assert.equal(received.projection.value.formatVersion, '4.0.0');
  assert.deepEqual(Buffer.from(received.projection.value.copyBytes()), projection);
  assert.deepEqual(recognized.map(bytes => Buffer.from(bytes)), [projection]);
});

test('verified projection retains private bytes across recognizer and caller mutation', async () => {
  const actual = fixture();
  let recognizerInput: Uint8Array | undefined;
  const received = await receive(actual, bytes => {
    assert.deepEqual(Buffer.from(bytes), projection);
    recognizerInput = bytes; bytes.fill(0); return '4.0.0';
  });
  assert.equal(received.projection.kind, 'verified');
  if (received.projection.kind !== 'verified') throw new Error('verified projection required');
  const value = received.projection.value;
  assert(Object.isFrozen(value));
  value.copyBytes().fill(1);
  recognizerInput!.fill(2);
  assert.deepEqual(Buffer.from(value.copyBytes()), projection);
  assert.equal(value.formatVersion, '4.0.0');
});

for (const reason of ['unsupported_representation', 'invalid_model', 'decode_limit', 'projection_limit', 'capacity', 'timeout'] as const)
test(`unavailable ${reason} preserves originals only after accepted release`, async () => {
  const actual = fixture({descriptor: {status: 'unavailable', reason}});
  let recognized = false;
  const accepted: ReleaseAccepted[] = [];
  const received = await receive(actual, () => {recognized = true; return '4.0.0';}, () => true, value => accepted.push(value));
  assert.deepEqual(received.projection, {kind: 'unavailable', reason});
  assert.equal(recognized, false);
  assert.equal(actual.requests.filter(row => projectionRead(row.method, row.params)).length, 0);
  assert.deepEqual(Buffer.concat(actual.files.get('morphir-ir.json')!), source);
  assert.equal(actual.requests.at(-1)!.method, 'release');
  assert.equal(accepted.length, 1);
  assert.equal(JSON.parse(accepted[0]!.exchange.reply).result.status, 'released');
});

for (const [name, descriptor] of Object.entries({
  null: null,
  'not-requested': {status: 'not-requested'},
  'unknown unavailable reason': {status: 'unavailable', reason: 'unknown'},
  'unavailable extra': {status: 'unavailable', reason: 'invalid_model', extra: true},
  'wrong codec': {...ready.projection, codec: 'yaml'},
  'one byte over projection budget': {...ready.projection, byteLength: 67108865},
  'negative byte length': {...ready.projection, byteLength: -1},
  'fractional byte length': {...ready.projection, byteLength: 1.5},
  'invalid digest': {...ready.projection, sha256: 'A'.repeat(64)},
  'noncanonical release': {...ready.projection, formatVersion: '4.00.0'},
  'overflow release': {...ready.projection, formatVersion: '4294967296.0.0'},
  'release prerelease': {...ready.projection, formatVersion: '4.0.0-alpha'},
  'available extra': {...ready.projection, extra: true},
})) test(`invalid projection descriptor refuses capture: ${name}`, async () => {
  const actual = fixture({descriptor});
  await assert.rejects(receive(actual));
  assert.deepEqual(actual.requests.map(row => row.method), ['capture']);
});

test('originals-only receiver remains strict and never requests projection bytes', async () => {
  const substituted = fixture();
  await assert.rejects(receiveOriginals(substituted.session, {} as ModelOriginalsProject, binding,
    substituted.sink, hash, () => true));
  assert.deepEqual(substituted.requests.map(row => row.method), ['capture']);
  const none = fixture({descriptor: {status: 'not-requested'}});
  await receiveOriginals(none.session, {} as ModelOriginalsProject, binding, none.sink, hash, () => true);
  assert.deepEqual(none.requests[0], {method: 'capture', params: {scope: 'complete', semantic: 'none'}});
  assert.equal(none.requests.some(row => projectionRead(row.method, row.params)), false);
  assert.equal(none.requests.at(-1)!.method, 'release');
});

for (const [name, mutate] of Object.entries<NonNullable<FixtureOptions['mutate']>>({
  target: (method, value, params) => {if (projectionRead(method, params)) value.target = {kind: 'original', entryId: 'model'};},
  binding: (method, value, params) => {if (projectionRead(method, params)) value.binding = {...binding, projectId: 'other'};},
  capture: (method, value, params) => {if (projectionRead(method, params)) value.captureId = 'other';},
  offset: (method, value, params) => {if (projectionRead(method, params)) value.offset = 1;},
  length: (method, value, params) => {if (projectionRead(method, params)) value.nextOffset = projection.length - 1;},
  digest: (method, value, params) => {if (projectionRead(method, params)) value.content = Buffer.alloc(projection.length).toString('base64');},
  'noncanonical base64': (method, value, params) => {if (projectionRead(method, params)) value.content = 'AB==';},
})) test(`invalid projection transfer retains verified originals after release: ${name}`, async () => {
  const actual = fixture({mutate});
  let recognized = false;
  const received = await receive(actual, () => {recognized = true; return '4.0.0';});
  assert.deepEqual(received.projection, {kind: 'unusable', reason: 'transfer-invalid'});
  assert.equal(recognized, false);
  assert.deepEqual(Buffer.concat(actual.files.get('notes/opaque.bin')!), opaque);
  assert.equal(actual.requests.at(-1)!.method, 'release');
});

test('header rejection and header mismatch preserve originals without verified projection', async () => {
  const invalid = fixture();
  const invalidResult = await receive(invalid, () => {throw new Error('literal header refused');});
  assert.deepEqual(invalidResult.projection, {kind: 'unusable', reason: 'header-invalid'});
  assert.equal(invalid.requests.at(-1)!.method, 'release');
  const mismatched = fixture();
  const mismatchResult = await receive(mismatched, () => '99.0.0');
  assert.deepEqual(mismatchResult.projection, {kind: 'unusable', reason: 'header-mismatch'});
  assert.equal(mismatched.requests.at(-1)!.method, 'release');
});

test('projection chunks use the exact canonical 65536 byte split and empty target read', async () => {
  const prefix = '{"formatVersion":4,"padding":"', suffix = '"}';
  const bytes = Buffer.from(prefix + 'a'.repeat(65537 - prefix.length - suffix.length) + suffix);
  const actual = fixture({bytes});
  const received = await receive(actual, observed => {assert.deepEqual(Buffer.from(observed), bytes); return '4.0.0';});
  assert.equal(received.projection.kind, 'verified');
  const reads = actual.requests.filter(row => projectionRead(row.method, row.params));
  assert.deepEqual(reads.map(row => row.params), [0, 65536].map(offset => ({captureId: 'capture-A', target: {kind: 'semantic-projection'}, offset, maxBytes: 65536})));
  const shortened = fixture({bytes, mutate(method, value, params) {
    if (projectionRead(method, params) && (params as {offset: number}).offset === 0) {
      value.content = bytes.subarray(0, 65535).toString('base64'); value.nextOffset = 65535;
    }
  }});
  assert.deepEqual((await receive(shortened)).projection, {kind: 'unusable', reason: 'transfer-invalid'});
  assert.equal(shortened.requests.filter(row => projectionRead(row.method, row.params)).length, 1);
  const empty = fixture({bytes: Buffer.alloc(0)});
  assert.deepEqual((await receive(empty, bytes => {assert.equal(bytes.length, 0); throw new Error('no header');})).projection,
    {kind: 'unusable', reason: 'header-invalid'});
  assert.equal(empty.requests.filter(row => projectionRead(row.method, row.params)).length, 1);
});

test('transport original corruption and release failures cannot become projection fallback success', async () => {
  const disconnected = new Error('actual session exchange failed');
  for (const stage of ['projection', 'release'] as const) {
    const actual = fixture({before(method, params) {if (stage === 'release' ? method === 'release' : projectionRead(method, params)) throw disconnected;}});
    await assert.rejects(receive(actual), cause => cause === disconnected);
  }
  const corrupt = fixture({mutate(method, value, params) {
    if (method === 'read' && !projectionRead(method, params)) value.content = Buffer.alloc(source.length).toString('base64');
  }});
  await assert.rejects(receive(corrupt));
  assert.equal(corrupt.requests.some(row => projectionRead(row.method, row.params)), false);
  for (const descriptor of [ready.projection, {status: 'unavailable', reason: 'invalid_model'}]) {
    const actual = fixture({descriptor, mutate(method, value) {if (method === 'release') value.captureId = 'other';}});
    let accepted = false;
    await assert.rejects(receive(actual, () => {throw new Error('header refused');}, () => true, () => {accepted = true;}));
    assert.equal(accepted, false);
  }
});

test('projection fallback cannot hide cancellation before during or after release', async () => {
  for (const stage of ['projection', 'header', 'release'] as const) {
    let current = true, accepted = false;
    const actual = fixture({before(method, params) {
      if (stage === 'projection' && projectionRead(method, params) || stage === 'release' && method === 'release') current = false;
    }});
    await assert.rejects(receive(actual, () => {
      if (stage === 'header') current = false;
      throw new Error('invalid header does not waive cancellation');
    }, () => current, () => {accepted = true;}));
    assert.equal(accepted, false);
  }
  const actual = fixture();
  const received = await receive(actual, () => '4.0.0', () => true, () => {throw new Error('observer cannot change completion');});
  assert.equal(received.projection.kind, 'verified');
  assert.equal(actual.requests.at(-1)!.method, 'release');
});
