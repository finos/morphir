import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ArtifactTransferAttempt, type ArtifactExchange, type ArtifactTransferEffects } from './artifact-transfer.ts';
import { selectArtifactTransferProfile } from './artifact-client/artifact-transfer.ts';

const profile = 'morphir/workbench/artifacts';
const contractVersion = '0.1.0-draft.1';
const abcDigest = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const ffDigest = 'a8100ae6aa1940d0b663bb31cd466142ebbdbd5187131b92d93818987832eb89';
const emptyDigest = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const selected = selectArtifactTransferProfile({ id: 'playground', status: 'available', capabilities: [{ name: profile, version: contractVersion }] });
if (!selected.ok) throw new Error('Bad selection fixture');
const selection = selected.value;
type Request = { id: number; method: string; params: Record<string, unknown> };
const reply = (id: number, result: unknown) => JSON.stringify({ jsonrpc: '2.0', id, result });
const descriptors = [
  { id: 'text', path: 'src/example.txt', kind: 'utf8-text', byteLength: 3, sha256: abcDigest },
  { id: 'binary', path: 'data/original.bin', kind: 'binary', byteLength: 1, sha256: ffDigest },
  { id: 'empty', path: 'data/empty.bin', kind: 'binary', byteLength: 0, sha256: emptyDigest },
];
const manifest = () => ({ profile, contractVersion, status: 'ready', sessionId: 'session', providerId: 'playground',
  generationId: 'owned-generation', producer: { id: 'fixture', version: '1.0.0' }, target: 'fixture', irVersion: '4',
  artifacts: structuredClone(descriptors), diagnostics: [] });
class FixtureChannel implements ArtifactExchange {
  closed = false;
  closes = 0;
  requests: Request[] = [];
  readonly intercept?: (request: Request) => string | Promise<string> | undefined;
  constructor(intercept?: (request: Request) => string | Promise<string> | undefined) { this.intercept = intercept; }
  async exchange(source: string): Promise<string> {
    if (this.closed) throw new Error('Closed fixture connection');
    const request = JSON.parse(source) as Request;
    this.requests.push(request);
    const intercepted = this.intercept?.(request);
    if (intercepted !== undefined) return intercepted;
    return this.respond(request);
  }
  respond(request: Request) {
    if (request.method === 'morphir.session.initialize') return reply(request.id, { protocolVersion: 1 });
    if (request.method === 'morphir.artifacts.generate') return reply(request.id, manifest());
    if (request.method === 'morphir.artifacts.release') return reply(request.id, {});
    if (request.method !== 'morphir.artifacts.read') throw new Error('Unexpected fixture method');
    const content = request.params.artifactId === 'text' ? 'YWJj' : request.params.artifactId === 'binary' ? '/w==' : '';
    const nextOffset = request.params.artifactId === 'text' ? 3 : request.params.artifactId === 'binary' ? 1 : 0;
    return reply(request.id, { profile, contractVersion, generationId: 'owned-generation', artifactId: request.params.artifactId,
      offset: 0, nextOffset, content });
  }
  close() { if (!this.closed) { this.closed = true; ++this.closes; } }
}
const input = () => ({ sessionId: 'session', target: 'fixture', irVersion: '4', ir: { value: 42 }, options: { format: 'literal' } });
function attempt(channel: FixtureChannel, effects: Partial<ArtifactTransferEffects> = {}) {
  return new ArtifactTransferAttempt(selection, input(), { connect: async () => channel, isCurrent: () => true, ...effects });
}
const calls = (channel: FixtureChannel, method: string) => channel.requests.filter(request => request.method === `morphir.artifacts.${method}`);

test('one-shot transfer verifies the entire inventory and releases the exact generation', async () => {
  const channel = new FixtureChannel(); const transfer = attempt(channel);
  const result = await transfer.run();
  assert.equal(result.kind, 'verified');
  if (result.kind !== 'verified') throw new Error(JSON.stringify(result));
  assert.deepEqual(result.cleanup, { kind: 'released', generationId: 'owned-generation' });
  assert.deepEqual(result.files.manifest.artifacts.map(file => [...result.files.bytes(file.id)]), [[97, 98, 99], [255], []]);
  assert.equal(calls(channel, 'generate').length, 1); assert.equal(calls(channel, 'read').length, 3);
  assert.equal(calls(channel, 'release').length, 1); assert.equal(channel.closes, 1);
  assert.equal(transfer.phase, 'finished');
  await assert.rejects(transfer.run(), /only once/);
});

test('input and trusted effects are captured before connecting', async () => {
  const connected = Promise.withResolvers<ArtifactExchange>();
  const channel = new FixtureChannel(); const source = input();
  const effects = { connect: () => connected.promise, isCurrent: () => true };
  const transfer = new ArtifactTransferAttempt(selection, source, effects);
  const result = transfer.run(); source.ir.value = 99; source.options.format = 'changed';
  effects.isCurrent = () => false;
  connected.resolve(channel);
  assert.equal((await result).kind, 'verified');
  assert.deepEqual(calls(channel, 'generate')[0]!.params.generation, {
    ir: { value: 42 }, target: 'fixture', irVersion: '4', options: { format: 'literal' },
  });
});

test('generation request bounds and nonfinite numbers refuse before opening any connection', () => {
  let connections = 0;
  const effects = { connect: async () => { ++connections; return new FixtureChannel(); }, isCurrent: () => true };
  assert.throws(() => new ArtifactTransferAttempt(selection, { ...input(), ir: NaN }, effects), { reason: 'nonfinite-number' });
  assert.throws(() => new ArtifactTransferAttempt(selection, { ...input(), ir: 'x'.repeat(1048576) }, effects), { reason: 'request-limit' });
  assert.equal(connections, 0);
});

test('ill-formed Unicode in local IR and options refuses before any connection', () => {
  let connections = 0;
  const effects = { connect: async () => { ++connections; return new FixtureChannel(); }, isCurrent: () => true };
  for (const field of ['ir', 'options'] as const) {
    for (const invalid of ['\ud800', '\udfff', 'before\ud800after', '\udfff\ud800']) {
      for (const value of [invalid, [invalid], { nested: invalid }, { [invalid]: 'valid' }]) {
        assert.throws(() => new ArtifactTransferAttempt(selection, { ...input(), [field]: value }, effects), { reason: 'ill-formed-unicode' });
      }
    }
  }
  assert.equal(connections, 0);
});

test('valid supplementary Unicode in local keys and values survives capture', async () => {
  const channel = new FixtureChannel();
  const ir = { '\ud83d\ude00': ['\ud83d\ude80', '\ufffd'] };
  const options = { '\ud83c\udf0d': '\ud83c\udf31' };
  const result = await new ArtifactTransferAttempt(selection, { ...input(), ir, options }, {
    connect: async () => channel, isCurrent: () => true,
  }).run();
  assert.equal(result.kind, 'verified');
  assert.deepEqual(calls(channel, 'generate')[0]!.params.generation, { ir, options, target: 'fixture', irVersion: '4' });
});

test('malformed raw manifests cannot become parsed metadata or trigger reads', async () => {
  const channel = new FixtureChannel(request => request.method.endsWith('.generate') ?
    reply(request.id, manifest()).replace('"byteLength":3', '"byteLength":3,"byteLength":3') : undefined);
  const result = await attempt(channel).run();
  assert.equal(result.kind, 'failed'); assert.equal(calls(channel, 'read').length, 0);
  assert.equal(calls(channel, 'release').length, 0); assert.equal(channel.closed, true);
  assert.deepEqual(result.cleanup, { kind: 'connection-closed', generationId: null, reason: 'unknown-retention' });
});

test('a wrong final digest exposes no verified prefix and releases known retention', async () => {
  const channel = new FixtureChannel(request => request.method.endsWith('.generate') ?
    reply(request.id, { ...manifest(), artifacts: descriptors.map(file => file.id === 'empty' ? { ...file, sha256: abcDigest } : file) }) : undefined);
  const result = await attempt(channel).run();
  assert.equal(result.kind, 'failed'); assert.equal('files' in result, false);
  assert.equal(calls(channel, 'release').length, 1); assert.equal(channel.closed, true);
  assert.equal(result.cleanup.kind, 'released');
});

test('chunk boundaries retain original bytes across the full-size and one-byte reads', async () => {
  // Independent shared recipe cycle-65537, authored and OpenSSL checked before the controller.
  const bytes = Uint8Array.from({ length: 65537 }, (_, index) => index % 256);
  const channel = new FixtureChannel(request => {
    if (request.method.endsWith('.generate')) return reply(request.id, { ...manifest(), artifacts: [{
      id: 'cycle', path: 'data/cycle.bin', kind: 'binary', byteLength: 65537,
      sha256: '2deb0bd2129a9d3aed91e3cff58b3993752be549642890a3e853ec1065f9b617',
    }] });
    if (request.method.endsWith('.read')) {
      const offset = Number(request.params.offset);
      const chunk = bytes.slice(offset, offset + Number(request.params.maxBytes));
      return reply(request.id, { profile, contractVersion, generationId: 'owned-generation', artifactId: 'cycle',
        offset, nextOffset: offset + chunk.byteLength, content: Buffer.from(chunk).toString('base64') });
    }
    return undefined;
  });
  const result = await attempt(channel).run();
  assert.equal(result.kind, 'verified');
  if (result.kind === 'verified') {
    const id = result.files.manifest.artifacts[0]!.id;
    assert.deepEqual(result.files.bytes(id), bytes);
    const head = result.files.previewBytes(id);
    assert.equal(head.byteLength, 65536); head[1] = 255;
    assert.equal(result.files.bytes(id)[1], 1);
  }
  assert.deepEqual(calls(channel, 'read').map(request => request.params.offset), [0, 65536]);
  assert.equal(calls(channel, 'release').length, 1);
});

test('wrong chunk identity fails closed and releases only the captured generation', async () => {
  const channel = new FixtureChannel(request => request.method.endsWith('.read') ?
    reply(request.id, { profile, contractVersion, generationId: 'other-generation', artifactId: 'text', offset: 0, nextOffset: 3, content: 'YWJj' }) : undefined);
  const result = await attempt(channel).run();
  assert.equal(result.kind, 'failed');
  assert.deepEqual(calls(channel, 'release')[0]!.params, { contractVersion, generationId: 'owned-generation' });
});

for (const boundary of ['initialize', 'generate', 'read', 'hash', 'release'] as const) {
  test(`context replacement after awaited ${boundary} discards output and cleans its own resources`, async () => {
    let current = true;
    const channel = new FixtureChannel(request => {
      if (request.method.endsWith(`.${boundary}`)) current = false;
      return undefined;
    });
    const result = await attempt(channel, { isCurrent: () => current, digest: async bytes => {
      const hash = await crypto.subtle.digest('SHA-256', bytes);
      if (boundary === 'hash') current = false;
      return hash;
    } }).run();
    assert.equal(result.kind, 'discarded'); assert.equal(channel.closed, true);
    assert.equal(calls(channel, 'generate').length, boundary === 'initialize' ? 0 : 1);
    assert.equal(calls(channel, 'release').length, boundary === 'initialize' ? 0 : 1);
  });
}

test('an obsolete generation reply is decoded before releasing its exact identity', async () => {
  let current = true;
  const channel = new FixtureChannel(request => { if (request.method.endsWith('.generate')) current = false; return undefined; });
  const result = await attempt(channel, { isCurrent: () => current }).run();
  assert.equal(result.kind, 'discarded'); assert.equal(calls(channel, 'read').length, 0);
  assert.deepEqual(calls(channel, 'release')[0]!.params, { contractVersion, generationId: 'owned-generation' });
});

test('cancellation closes a late-opened owned connection without sending any requests', async () => {
  const connected = Promise.withResolvers<ArtifactExchange>(); const channel = new FixtureChannel();
  const transfer = attempt(channel, { connect: () => connected.promise });
  const result = transfer.run();
  assert.equal((await transfer.cancel()).kind, 'not-connected');
  connected.resolve(channel);
  assert.equal((await result).kind, 'discarded'); assert.equal(channel.closed, true); assert.equal(channel.requests.length, 0);
});

test('cancellation while hashing releases once before the pending hash finishes', { timeout: 2000 }, async () => {
  const hashing = Promise.withResolvers<void>(); const hash = Promise.withResolvers<ArrayBuffer>();
  const channel = new FixtureChannel(); const transfer = attempt(channel, { digest: async () => { hashing.resolve(); return hash.promise; } });
  const result = transfer.run(); await hashing.promise;
  const cleanup = await transfer.cancel();
  assert.equal(cleanup.kind, 'released'); assert.equal(calls(channel, 'release').length, 1);
  hash.resolve(new ArrayBuffer(32));
  assert.equal((await result).kind, 'discarded'); assert.equal(calls(channel, 'release').length, 1);
});

test('cancellation during a pending generation closes only that connection and never retries', { timeout: 2000 }, async () => {
  const pending = Promise.withResolvers<void>(); const deliver = Promise.withResolvers<string>();
  const old = new FixtureChannel(request => {
    if (request.method.endsWith('.generate')) { pending.resolve(); return deliver.promise; }
    return undefined;
  });
  const newer = new FixtureChannel(); const transfer = attempt(old);
  const result = transfer.run(); await pending.promise;
  const cleanup = await transfer.cancel();
  assert.equal(cleanup.kind, 'connection-closed'); assert.equal(old.closed, true); assert.equal(newer.closed, false);
  deliver.resolve(reply(2, manifest()));
  assert.equal((await result).kind, 'discarded'); assert.equal(calls(old, 'generate').length, 1); assert.equal(calls(old, 'release').length, 0);
});

test('release refusal prevents publishing verified bytes and surfaces connection cleanup', async () => {
  const channel = new FixtureChannel(request => request.method.endsWith('.release') ? reply(request.id, { ignored: true }) : undefined);
  const result = await attempt(channel).run();
  assert.equal(result.kind, 'failed'); assert.equal('files' in result, false);
  assert.deepEqual(result.cleanup, { kind: 'connection-closed', generationId: 'owned-generation', reason: 'release-failed' });
  assert.equal(channel.closed, true); assert.equal(calls(channel, 'release').length, 1);
});

test('generator diagnostics do not start reads or invent a retained generation', async () => {
  const diagnostics = [{ severity: 'error', code: 'fixture.failed', message: 'Deliberate generator refusal', location: null }];
  const channel = new FixtureChannel(request => request.method.endsWith('.generate') ?
    reply(request.id, { profile, contractVersion, status: 'failed', diagnostics }) : undefined);
  const result = await attempt(channel).run();
  assert.equal(result.kind, 'generation-failed');
  if (result.kind === 'generation-failed') assert.deepEqual(result.diagnostics, diagnostics);
  assert.equal(result.cleanup.kind, 'not-retained'); assert.equal(calls(channel, 'read').length, 0);
  assert.equal(calls(channel, 'release').length, 0); assert.equal(channel.closed, true);
});

test('lost generation reply never retries even when a producer might have executed', async () => {
  const channel = new FixtureChannel(request => { if (request.method.endsWith('.generate')) throw new Error('Connection lost'); return undefined; });
  const result = await attempt(channel).run();
  assert.equal(result.kind, 'failed'); assert.equal(calls(channel, 'generate').length, 1);
  assert.equal(calls(channel, 'read').length, 0); assert.equal(channel.closed, true);
});

for (const boundary of ['initialize', 'generate', 'read', 'release'] as const) {
  test(`a rejected awaited ${boundary} reconciles replacement before returning a failure`, async () => {
    let current = true;
    const channel = new FixtureChannel(request => {
      if (request.method.endsWith(`.${boundary}`)) { current = false; throw new Error('Late transport failure'); }
      return undefined;
    });
    const result = await attempt(channel, { isCurrent: () => current }).run();
    assert.equal(result.kind, 'discarded'); assert.equal(channel.closed, true);
    assert.equal(calls(channel, 'generate').length, boundary === 'initialize' ? 0 : 1);
  });
}

test('a rejected awaited connection reconciles replacement without any RPC', async () => {
  let current = true; const channel = new FixtureChannel();
  const result = await attempt(channel, { isCurrent: () => current, connect: async () => {
    current = false; throw new Error('Late connection failure');
  } }).run();
  assert.equal(result.kind, 'discarded'); assert.equal(result.cleanup.kind, 'not-connected');
  assert.equal(channel.requests.length, 0);
});

test('cancellation during release awaits the same acknowledgement without a second release', { timeout: 2000 }, async () => {
  const releasing = Promise.withResolvers<Request>(); const acknowledgement = Promise.withResolvers<string>();
  const channel = new FixtureChannel(request => {
    if (request.method.endsWith('.release')) { releasing.resolve(request); return acknowledgement.promise; }
    return undefined;
  });
  const transfer = attempt(channel); const result = transfer.run();
  const request = await releasing.promise; const cleanup = transfer.cancel();
  assert.equal(calls(channel, 'release').length, 1); assert.equal(channel.closed, false);
  acknowledgement.resolve(reply(request.id, {}));
  assert.equal((await cleanup).kind, 'released'); assert.equal((await result).kind, 'discarded');
  assert.equal(calls(channel, 'release').length, 1); assert.equal(channel.closes, 1);
});
