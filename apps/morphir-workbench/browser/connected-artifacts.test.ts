import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ConnectedAdapter } from './transport.ts';
import type { Catalog, Manifest, Rpc, WorkRequest, WorkResult } from './contracts.ts';
import type { ArtifactExchange } from './artifact-transfer.ts';
import { artifactBytes } from './artifact-download.ts';

const profile = 'morphir/workbench/artifacts'; const contractVersion = '0.1.0-draft.1';
const abcDigest = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const request: WorkRequest = { operation: 'compile', languageId: 'gleam', target: 'fixture', source: 'pub fn main() { 42 }' };
const session = (): Manifest => ({ protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'session', initialSources: [], providers: [
  { id: 'playground', status: 'available', capabilities: [
    ...['catalog', 'compile', 'generate'].map(name => ({ name: `morphir/playground/${name}`, version: '1' })),
    { name: profile, version: contractVersion },
  ] },
] });
const catalog = (): Catalog => ({ frontends: [{ languageId: 'gleam', irVersions: ['3', '4'], compile: true }],
  targets: [{ target: 'fixture', irVersions: ['4.0.0'], generate: true }] });
type Request = { id: number; method: string; params: Record<string, unknown> };
const reply = (id: number, result: unknown) => JSON.stringify({ jsonrpc: '2.0', id, result });
class Channel implements ArtifactExchange {
  closed = false; requests: Request[] = []; readonly generation: string;
  intercept?: (request: Request) => string | Promise<string> | undefined;
  constructor(generation = 'generation') { this.generation = generation; }
  async exchange(source: string) {
    const request = JSON.parse(source) as Request; this.requests.push(request);
    return this.intercept?.(request) ?? this.respond(request);
  }
  respond(request: Request) {
    if (request.method.endsWith('.initialize')) return reply(request.id, { protocolVersion: 1 });
    if (request.method.endsWith('.release')) return reply(request.id, {});
    if (request.method.endsWith('.read')) return reply(request.id, { profile, contractVersion, generationId: this.generation,
      artifactId: 'file', offset: 0, nextOffset: 3, content: 'YWJj' });
    return reply(request.id, { profile, contractVersion, status: 'ready', sessionId: 'session', providerId: 'playground',
      generationId: this.generation, producer: { id: 'fixture', version: '1.0.0' }, target: 'fixture', irVersion: '4.0.0',
      artifacts: [{ id: 'file', path: 'src/result.txt', kind: 'utf8-text', byteLength: 3, sha256: abcDigest }], diagnostics: [] });
  }
  close() { this.closed = true; }
}
function fixture(options: { manifest?: Manifest; channels?: Channel[]; compile?: () => Promise<unknown>;
  inspect?: () => Promise<WorkResult> } = {}) {
  const legacyCalls: string[] = []; const channels = options.channels ?? [new Channel()];
  const ir = { formatVersion: 4, value: 42 }; let connections = 0;
  const rpc: Rpc = { async call(method) {
    legacyCalls.push(method);
    if (method.endsWith('.catalog')) return catalog();
    if (method.endsWith('.compile')) return options.compile ? options.compile() : { success: true, ir, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('.generate')) return { success: true, artifacts: [{ path: 'legacy.bin', content: 'YWJj', binary: true,
      encoding: 'base64', verifiedArtifact: { setId: 'forged', artifactId: 'file' } }] };
    return {};
  } };
  const adapter = new ConnectedAdapter(rpc, options.manifest ?? session(), { execute: async () => options.inspect ? options.inspect() :
    { success: true, inspectionMessage: 'local inspection' }, cancel() {} }, null, {
    async connect() { const channel = channels[connections++]; if (!channel) throw new Error('Unexpected connection'); return channel; },
  });
  return { adapter, ir, channels, legacyCalls, connections: () => connections };
}

test('connected generation selects the exact profile and publishes privately verified download references', async () => {
  const fixture_ = fixture(); const { adapter, legacyCalls, channels } = fixture_;
  await adapter.initialize(); const result = await adapter.execute(request);
  assert.equal(result.success, true); assert.equal(result.generationMessage, undefined);
  assert.deepEqual(result.ir, fixture_.ir); assert.match(result.generated!, /abc/);
  assert.equal(legacyCalls.includes('morphir.playground.generate'), false);
  assert.equal(channels[0]!.requests.filter(request => request.method.endsWith('.generate')).length, 1);
  assert.deepEqual(artifactBytes([JSON.parse(JSON.stringify(result.artifacts![0]))], adapter.artifactDownloads)['src/result.txt'], new Uint8Array([97, 98, 99]));
  assert.equal(channels[0]!.closed, true);
});

test('a selected-profile failure preserves compiled IR and never retries through legacy generation', async () => {
  const channel = new Channel(); channel.intercept = request => request.method.endsWith('.generate') ?
    channel.respond(request).replace('"byteLength":3', '"byteLength":3,"byteLength":3') : undefined;
  const { adapter, ir, legacyCalls } = fixture({ channels: [channel] }); await adapter.initialize();
  const result = await adapter.execute(request);
  assert.equal(result.success, true); assert.deepEqual(result.ir, ir);
  assert.match(result.generationMessage!, /refused/); assert.match(result.generationMessage!, /owning connection was closed/);
  assert.equal(result.artifacts, undefined); assert.equal(legacyCalls.includes('morphir.playground.generate'), false);
});

test('a different profile version retains legacy behavior and strips untrusted local byte references', async () => {
  const manifest = session(); manifest.providers[0]!.capabilities.at(-1)!.version = '0.1.0';
  const fixture_ = fixture({ manifest }); await fixture_.adapter.initialize();
  const result = await fixture_.adapter.execute(request);
  assert.equal(fixture_.connections(), 0);
  assert.deepEqual(result.artifacts, [{ path: 'legacy.bin', content: 'YWJj', binary: true }]);
  assert.throws(() => artifactBytes(result.artifacts), /does not declare/);
});

test('provider, target, session and compiled IR are captured before later awaited work', { timeout: 2000 }, async () => {
  const compiled = Promise.withResolvers<unknown>(); const inspecting = Promise.withResolvers<void>(); const inspected = Promise.withResolvers<WorkResult>();
  const manifest = session(); const fixture_ = fixture({ manifest, compile: () => compiled.promise, inspect: () => { inspecting.resolve(); return inspected.promise; } });
  await fixture_.adapter.initialize();
  const result = fixture_.adapter.execute(request);
  manifest.sessionId = 'replaced-session'; manifest.providers[0]!.id = 'replaced-provider';
  fixture_.adapter.catalog.targets[0]!.target = 'replaced-target';
  compiled.resolve({ success: true, ir: fixture_.ir, irVersion: '4.0.0' });
  await inspecting.promise; fixture_.ir.value = 99; inspected.resolve({ success: true });
  const output = await result;
  assert.equal(output.generationMessage, undefined); assert.deepEqual(output.ir, { formatVersion: 4, value: 42 });
  const generation = fixture_.channels[0]!.requests.find(request => request.method.endsWith('.generate'))!;
  assert.deepEqual(generation.params, { contractVersion, providerId: 'playground', generation: {
    ir: { formatVersion: 4, value: 42 }, irVersion: '4.0.0', target: 'fixture', options: {},
  } });
});

test('a late older transfer cannot overwrite or invalidate the replacement download owner', { timeout: 2000 }, async () => {
  const pending = Promise.withResolvers<Request>(); const deliver = Promise.withResolvers<string>();
  const older = new Channel('older'); older.intercept = request => {
    if (request.method.endsWith('.read')) { pending.resolve(request); return deliver.promise; }
    return undefined;
  };
  const newer = new Channel('newer'); const { adapter } = fixture({ channels: [older, newer] }); await adapter.initialize();
  const first = adapter.execute(request); const discarded = assert.rejects(first, /Discarded/);
  const reading = await pending.promise;
  const output = await adapter.execute({ ...request, source: 'pub fn main() { 43 }' });
  deliver.resolve(older.respond(reading)); await discarded;
  assert.equal(older.closed, true); assert.equal(newer.closed, true);
  assert.deepEqual(artifactBytes(output.artifacts, adapter.artifactDownloads)['src/result.txt'], new Uint8Array([97, 98, 99]));
  assert.equal(older.requests.filter(request => request.method.endsWith('.release')).length, 0);
  assert.equal(newer.requests.filter(request => request.method.endsWith('.release')).length, 1);
});

test('ambiguous artifact owners refuse generation while retaining successful compilation', async () => {
  const manifest = session(); manifest.providers.push({ ...structuredClone(manifest.providers[0]!), id: 'other' });
  const fixture_ = fixture({ manifest }); await fixture_.adapter.initialize(); const result = await fixture_.adapter.execute(request);
  assert.equal(result.success, true); assert.match(result.generationMessage!, /multiple artifact providers/);
  assert.equal(fixture_.connections(), 0); assert.equal(fixture_.legacyCalls.includes('morphir.playground.generate'), false);
});

test('source revision changes during compilation prevent obsolete generation and download publication', async () => {
  const compiled = Promise.withResolvers<unknown>(); const fixture_ = fixture({ compile: () => compiled.promise });
  await fixture_.adapter.initialize(); const result = fixture_.adapter.execute(request);
  const discarded = assert.rejects(result, /Discarded/);
  fixture_.adapter.invalidateArtifacts();
  compiled.resolve({ success: true, ir: fixture_.ir, irVersion: '4.0.0' });
  await discarded; assert.equal(fixture_.connections(), 0);
});

test('a legacy catalog owner cannot be silently associated with another providers artifact offer', async () => {
  const manifest = session(); manifest.providers.push({ id: 'other', status: 'available', capabilities: [
    { name: 'morphir/playground/catalog', version: '1' },
  ] });
  const fixture_ = fixture({ manifest }); await fixture_.adapter.initialize(); const result = await fixture_.adapter.execute(request);
  assert.equal(result.success, true); assert.match(result.generationMessage!, /uniquely own/);
  assert.equal(fixture_.connections(), 0); assert.equal(fixture_.legacyCalls.includes('morphir.playground.generate'), false);
});
