import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  inventoryDigest, receiveOriginalsWithProjection,
  type Binding, type Entry, type Hasher, type OriginalSink, type ReleaseAccepted,
} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';
import type { ModelOriginalsProject, ModelOriginalsSession } from '../../../pkgs/morphir-host/model-originals-client/session.ts';

// The type comes from source; execution uses only the actual built wrapper and
// its fixed sibling generated MoonBit release library, never a parser stub.
const { ProjectionHeaderLimits, ProjectionHeaderFailure, recognizeProjectionHeader }:
  typeof import('./verify-projection-header.ts') = await import(new URL('../dist/verify-projection-header.js', import.meta.url).href);
const utf8 = (text: string) => new TextEncoder().encode(text);
const limits = () => ProjectionHeaderLimits.create({ maxBytes: 1024, maxDepth: 8, maxValues: 32 });
function refused(code: typeof ProjectionHeaderFailure.prototype.code, operation: () => unknown) {
  assert.throws(operation, (error: unknown) => error instanceof ProjectionHeaderFailure && error.code === code);
}

test('actual generated bridge recognizes historical and future versions independently of typed support', () => {
  for (const [input, expected] of [
    ['{"formatVersion":2,"distribution":null}', '2.0.0'],
    ['{"formatVersion":99,"distribution":false}', '99.0.0'],
    ['{"formatVersion":4294967295}', '4294967295.0.0'],
    ['{"formatVersion":"99.2.7"}', '99.2.7'],
  ]) assert.equal(recognizeProjectionHeader(utf8(input!), limits()), expected);
});

test('actual generated bridge rejects BOM, escaped duplicates and malformed whole documents', () => {
  for (const input of [
    '\ufeff{"formatVersion":4}',
    '{"formatVersion":4,"formatVersion":4}',
    '{"formatVersion":4,"\\u0066ormatVersion":4}',
    '{"formatVersion":4,"later":{"a":1,"\\u0061":2}}',
    '{"formatVersion":4} {}', '{"formatVersion":4,"later":}', '{"formatVersion":04}', '{}',
  ]) refused('invalid-header', () => recognizeProjectionHeader(utf8(input), limits()));
});

test('actual generated bridge rejects floating, overflowing and noncanonical release headers', () => {
  for (const version of ['4.0', '4e0', '-1', '-0', '0', '4294967296', 'true', 'null', '[4]',
    '"1.0.0"', '"2.0.0"', '"3.01.0"', '"4.0.0+build"', '"99.4294967296.0"']) {
    refused('invalid-header', () => recognizeProjectionHeader(utf8(`{"formatVersion":${version}}`), limits()));
  }
});

test('explicit byte bounds precede UTF8 and parser limits on actual input bytes', () => {
  const source = utf8('{"formatVersion":4}');
  assert.equal(recognizeProjectionHeader(source, ProjectionHeaderLimits.create({ maxBytes: source.length, maxDepth: 1, maxValues: 2 })), '4.0.0');
  refused('byte-limit', () => recognizeProjectionHeader(source, ProjectionHeaderLimits.create({ maxBytes: source.length - 1, maxDepth: 1, maxValues: 2 })));
  refused('byte-limit', () => recognizeProjectionHeader(Uint8Array.of(255, 255), ProjectionHeaderLimits.create({ maxBytes: 1, maxDepth: 0, maxValues: 1 })));
  refused('invalid-utf8', () => recognizeProjectionHeader(Uint8Array.of(255), limits()));
  refused('decode-limit', () => recognizeProjectionHeader(source, ProjectionHeaderLimits.create({ maxBytes: source.length, maxDepth: 0, maxValues: 2 })));
  refused('decode-limit', () => recognizeProjectionHeader(source, ProjectionHeaderLimits.create({ maxBytes: source.length, maxDepth: 1, maxValues: 1 })));
});

test('limits validate every JS number before the Int32 foreign ABI and have no defaults', () => {
  for (const key of ['maxBytes', 'maxDepth', 'maxValues'] as const) {
    for (const value of [NaN, Infinity, -Infinity, 0.5, -1, 2_147_483_648, Number.MAX_SAFE_INTEGER + 1, '8', null, undefined]) {
      refused('invalid-limits', () => ProjectionHeaderLimits.create({ maxBytes: 1024, maxDepth: 8, maxValues: 32, [key]: value }));
    }
  }
  for (const key of ['maxBytes', 'maxValues'] as const) {
    refused('invalid-limits', () => ProjectionHeaderLimits.create({ maxBytes: 1024, maxDepth: 8, maxValues: 32, [key]: 0 }));
  }
  for (const input of [undefined, null, {}, { maxBytes: 1024 }, []]) refused('invalid-limits', () => ProjectionHeaderLimits.create(input));
  assert.equal(recognizeProjectionHeader(utf8('{"formatVersion":99}'), ProjectionHeaderLimits.create({ maxBytes: 2_147_483_647, maxDepth: 2_147_483_647, maxValues: 2_147_483_647 })), '99.0.0');
});

test('limits own their input snapshot and reject forged nominal values', () => {
  const input = { maxBytes: 1024, maxDepth: 8, maxValues: 32 };
  const selected = ProjectionHeaderLimits.create(input);
  input.maxBytes = 0; input.maxDepth = -1; input.maxValues = 0;
  assert.equal(recognizeProjectionHeader(utf8('{"formatVersion":99}'), selected), '99.0.0');
  for (const forged of [{}, Object.create(ProjectionHeaderLimits.prototype), null]) {
    refused('invalid-limits', () => recognizeProjectionHeader(utf8('{"formatVersion":99}'), forged));
  }
  refused('invalid-limits', () => ProjectionHeaderLimits.create({ get maxBytes() { throw new Error('caller getter'); }, maxDepth: 8, maxValues: 32 }));
});

test('recognizer requires actual unshared Uint8Array bytes without consulting input accessors or species', () => {
  const source = utf8('{"formatVersion":99}');
  for (const bytes of [source.buffer, new DataView(source.buffer), new Uint8ClampedArray(source), [...source], Object.create(Uint8Array.prototype), null]) {
    refused('invalid-header', () => recognizeProjectionHeader(bytes as Uint8Array, limits()));
  }
  refused('invalid-header', () => recognizeProjectionHeader(new Uint8Array(new SharedArrayBuffer(source.length)), limits()));
  Object.defineProperty(source, 'buffer', { get() { throw new Error('caller buffer accessor'); } });
  Object.defineProperty(source, 'constructor', { get() { throw new Error('caller species accessor'); } });
  assert.equal(recognizeProjectionHeader(source, limits()), '99.0.0');
});

test('recognizer preserves actual byte windows and permits explicitly bounded large headers', () => {
  const body = utf8('{"formatVersion":99}');
  const surrounding = new Uint8Array(body.length + 2); surrounding.set(body, 1); surrounding[0] = 255; surrounding[surrounding.length - 1] = 255;
  assert.equal(recognizeProjectionHeader(surrounding.subarray(1, -1), limits()), '99.0.0');
  const large = utf8(`{"formatVersion":99,"padding":"${'a'.repeat(131_073)}"}`);
  assert.equal(recognizeProjectionHeader(large, ProjectionHeaderLimits.create({ maxBytes: large.length, maxDepth: 1, maxValues: 3 })), '99.0.0');
  refused('byte-limit', () => recognizeProjectionHeader(large, ProjectionHeaderLimits.create({ maxBytes: large.length - 1, maxDepth: 1, maxValues: 3 })));
});

test('actual compiled recognizer composes with the shared receiver and strict release for valid and BOM projection bytes', async () => {
  // Scripted transport only: this control qualifies dependency composition,
  // not an actual authenticated host, browser action or typed inspection.
  const source = Buffer.from('\ufeff{"formatVersion":2}\r\n');
  const validProjection = Buffer.from('{"formatVersion":4,"distribution":null}');
  const makeHash = (): Hasher => {
    const hash = createHash('sha256');
    return { update(bytes) { hash.update(bytes); }, hex() { return hash.digest('hex'); } };
  };
  const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
  const binding: Binding = { sessionId: 'session-A', source: { providerId: 'provider-A', locator: 'workspace:actual' }, projectId: 'project-A' };
  const prefix = { profile: 'morphir/workbench/model-originals', contractVersion: '0.1.0-draft.1' };
  const entries: Entry[] = [{ kind: 'file', entryId: 'model', path: 'morphir-ir.json', byteLength: source.length, sha256: digest(source) }];
  const inventorySha256 = inventoryDigest(entries, makeHash());
  for (const bom of [false, true]) {
    const projection = bom ? Buffer.concat([Buffer.from([239, 187, 191]), validProjection]) : Buffer.from(validProjection);
    const capture = {
      ...prefix, status: 'ready', binding, captureId: 'capture-A',
      coverage: { kind: 'complete', declaration: prefix.contractVersion },
      origin: { kind: 'legacy-json', path: 'morphir-ir.json' },
      primary: { kind: 'file', path: 'morphir-ir.json' }, companions: [],
      sourceFormatVersion: { status: 'reported', release: '2.0.0' },
      projection: { status: 'available', codec: 'morphir-json', byteLength: projection.length, sha256: digest(projection), formatVersion: '4.0.0' },
      inventory: { entryCount: 1, fileCount: 1, directoryCount: 0, sourceByteLength: source.length, sha256: inventorySha256 },
    };
    let id = 0;
    const requests: { method: string; params: unknown }[] = [];
    const stages: string[] = [];
    const exchange = (value: object) => {
      const requestId = String(++id);
      return { requestId, request: '', reply: JSON.stringify({ jsonrpc: '2.0', id, result: value }) };
    };
    const session: ModelOriginalsSession = {
      sessionId: binding.sessionId, sources: [], async openSource() { return []; }, close() {},
      async exchangeCapture(_project, options) {
        requests.push({ method: 'capture', params: options });
        return exchange(capture);
      },
      async exchangeOriginals(method, params) {
        requests.push({ method, params });
        if (method === 'release') return exchange({ ...prefix, captureId: capture.captureId, status: 'released' });
        if (method === 'inventory') return exchange({ ...prefix, binding, captureId: capture.captureId,
          inventorySha256, startIndex: 0, entries, next: { kind: 'complete' } });
        const input = params as { target: { kind: 'original'; entryId: string } | { kind: 'semantic-projection' }; offset: number; maxBytes: number };
        assert.equal(input.offset, 0); assert.equal(input.maxBytes, 65536);
        const actual = input.target.kind === 'semantic-projection' ? projection : source;
        return exchange({ ...prefix, binding, captureId: capture.captureId, target: input.target,
          offset: input.offset, nextOffset: actual.length, content: actual.toString('base64') });
      },
    };
    const originals: Buffer[] = [];
    const sink: OriginalSink = {
      inventory(actual) { assert.deepEqual(actual, entries); },
      begin(index) { assert.equal(index, 0); }, write(bytes) { originals.push(Buffer.from(bytes)); }, end() {},
    };
    const accepted: ReleaseAccepted[] = [];
    const headerLimits = ProjectionHeaderLimits.create({ maxBytes: 1024, maxDepth: 8, maxValues: 32 });
    const received = await receiveOriginalsWithProjection(session,
      { projectId: binding.projectId, name: 'Actual project' } as ModelOriginalsProject,
      binding, sink, makeHash, () => true,
      bytes => { stages.push('header'); return recognizeProjectionHeader(bytes, headerLimits); },
      value => { stages.push('released'); accepted.push(value); });
    stages.push('returned');
    assert.deepEqual(requests[0], { method: 'capture', params: { scope: 'complete', semantic: 'projection' } });
    assert.equal(requests.at(-1)!.method, 'release');
    assert.deepEqual(stages, ['header', 'released', 'returned']);
    assert.equal(accepted.length, 1);
    assert.equal(JSON.parse(accepted[0]!.exchange.reply).result.status, 'released');
    assert.deepEqual(received.capture.sourceFormatVersion, { status: 'reported', release: '2.0.0' });
    assert.deepEqual(Buffer.concat(originals), source);
    if (bom) {
      // Digest verification succeeded for these exact BOM bytes. Refusal is
      // specifically the actual compiled header boundary, after that transfer.
      assert.deepEqual(received.projection, { kind: 'unusable', reason: 'header-invalid' });
    } else {
      assert.equal(received.projection.kind, 'verified');
      if (received.projection.kind !== 'verified') throw new Error('verified projection required');
      assert.equal(received.projection.value.formatVersion, '4.0.0');
      const copy = received.projection.value.copyBytes();
      assert.deepEqual(Buffer.from(copy), validProjection);
      copy.fill(0);
      assert.deepEqual(Buffer.from(received.projection.value.copyBytes()), validProjection);
    }
  }
});
