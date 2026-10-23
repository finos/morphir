import {createHash} from 'node:crypto';
import {inventoryDigest, type Entry} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';

/** Shared actual HTTP/WebSocket host for browser and routed-owner application tests. */
export function startOriginalsFixture(scenario: 'single-file' | 'paged-inventory' | 'projected-model' = 'single-file') {
  const projection = Buffer.from('{"formatVersion":4,"distribution":{"Library":{"packageName":"example","dependencies":{},"def":{"modules":{}}}}}');
  const original = scenario === 'projected-model' ? Buffer.from('\ufeff' + projection.toString() + '\r\n')
    : Buffer.from('\ufeff# original\r\nformatVersion: 4\r\n');
  const shared = {profile: 'morphir/workbench/model-originals', contractVersion: '0.1.0-draft.1'};
  const sources = ['A', 'B'].map(id => ({providerId: 'provider', locator: `workspace:${id}`, displayName: 'Same source'}));
  const binding = {sessionId: 'session', source: {providerId: 'provider', locator: 'workspace:B'}, projectId: 'project-B'};
  const entries: Entry[] = [{kind: 'file', entryId: 'file', path: 'model.yaml', byteLength: original.length,
    sha256: createHash('sha256').update(original).digest('hex')}];
  if (scenario === 'paged-inventory') {
    entries.push({kind: 'directory', entryId: 'notes', path: 'notes'});
    for (let index = 0; index < 1000; ++index) entries.push({kind: 'directory', entryId: `empty-${index}`,
      path: `notes/empty-${String(index).padStart(4, '0')}`});
  }
  const hash = createHash('sha256');
  const digest = inventoryDigest(entries, {update(bytes) {hash.update(bytes);}, hex() {return hash.digest('hex');}});
  const requests: {method: string; params: unknown}[] = [];
  let manifests = 0;
  let release!: () => void, requestedRelease!: () => void;
  const pendingRelease = new Promise<void>(resolve => {requestedRelease = resolve;});
  const host = Bun.serve({port: 0, hostname: '127.0.0.1', fetch(request, server) {
    if (new URL(request.url).pathname === '/api/session') { ++manifests; return Response.json({protocolVersion: 1, sessionId: 'session', webSocketPath: '/rpc',
      providers: [{id: 'provider', name: 'Fixture', kind: 'connected', status: 'available', capabilities: [
        {name: 'morphir/workspace/open', version: '1'}, {name: shared.profile, version: shared.contractVersion},
      ]}], initialSources: sources}); }
    if (server.upgrade(request)) return;
    return new Response('Not found', {status: 404});
  }, websocket: {message(socket, raw) {
    const request = JSON.parse(String(raw)) as {id: number; method: string; params: {source: typeof sources[number]; target: {kind: string}; offset: number; startIndex: number; maxEntries: number; semantic: string}};
    requests.push(request);
    let result: unknown;
    switch (request.method) {
      case 'morphir.session.initialize': result = {protocolVersion: 1}; break;
      case 'morphir.workspace.open': result = {snapshot: {id: 'workspace', root: request.params.source, name: 'Fixture', state: 'open',
        configAnchor: null, projects: ['A', 'B'].map(id => ({id: `project-${id}`, name: 'Same project', state: 'unloaded'})),
        modelSources: [], knowledgeBaseSources: [], diagnostics: []}}; break;
      case 'morphir.model-originals.capture': result = {...shared, status: 'ready', binding, captureId: 'capture',
        coverage: {kind: 'complete', declaration: shared.contractVersion},
        origin: {kind: 'compiled', record: {byteLength: 100, sha256: '0'.repeat(64), schema: 1, task: 'compile', module: '',
          ir: {path: 'model.yaml', layout: 'single-file', format: 'yaml', version: 'v4'}}},
        primary: {kind: 'file', path: 'model.yaml'}, companions: scenario === 'paged-inventory' ? [{kind: 'directory', path: 'notes'}] : [], sourceFormatVersion: {status: 'reported', release: '4.0.0'},
        projection: request.params.semantic === 'projection' ? (scenario === 'projected-model'
          ? {status: 'available', codec: 'morphir-json', byteLength: projection.length,
            sha256: createHash('sha256').update(projection).digest('hex'), formatVersion: '4.0.0'}
          : {status: 'unavailable', reason: 'invalid_model'}) : {status: 'not-requested'},
        inventory: {entryCount: entries.length, fileCount: 1, directoryCount: entries.length - 1, sourceByteLength: original.length, sha256: digest}}; break;
      case 'morphir.model-originals.inventory': {
        const startIndex = request.params.startIndex;
        if (!Number.isSafeInteger(startIndex) || startIndex < 0 || startIndex >= entries.length || request.params.maxEntries !== 256) throw new Error('Invalid fixture inventory request');
        const finish = Math.min(startIndex + request.params.maxEntries, entries.length);
        result = {...shared, binding, captureId: 'capture', inventorySha256: digest,
          startIndex, entries: entries.slice(startIndex, finish), next: finish === entries.length ? {kind: 'complete'} : {kind: 'more', startIndex: finish}};
        break;
      }
      case 'morphir.model-originals.read': {
        const bytes = request.params.target.kind === 'semantic-projection' ? projection : original;
        const next = Math.min(bytes.length, request.params.offset + 65536);
        result = {...shared, binding, captureId: 'capture', target: request.params.target,
          offset: request.params.offset, nextOffset: next, content: bytes.subarray(request.params.offset, next).toString('base64')}; break;
      }
      case 'morphir.model-originals.release': result = {...shared, captureId: 'capture', status: 'released'}; break;
      default: throw new Error(`Unexpected method ${request.method}`);
    }
    const reply = () => socket.send(JSON.stringify({jsonrpc: '2.0', id: request.id, result}));
    if (request.method.endsWith('.release')) {release = reply; requestedRelease();} else reply();
  }}});
  return {host, original, shared, binding, requests, pendingRelease, release() {release();}, get manifests() {return manifests;}};
}

if (import.meta.main) {
  const fixture = startOriginalsFixture();
  console.log(fixture.host.url.origin);
  void fixture.pendingRelease.then(() => fixture.release());
  // The owning test closes stdin, then awaits this actual host process exit.
  for await (const _ of Bun.stdin.stream()) { /* no input protocol */ }
  await fixture.host.stop(true);
}
