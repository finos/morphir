import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ModelOriginalsConnectionLimits, openModelOriginalsSession,
  type ModelOriginalsObservation,
} from './model-originals-session.ts';

const profile = 'morphir/workbench/model-originals';
const version = '0.1.0-draft.1';
const root = { providerId: 'provider-A', locator: 'workspace:orders', displayName: 'Orders' };
const project = { id: '["provider-A","workspace:orders","packages/orders"]', name: 'Pricing', state: 'unloaded' };
const manifest = () => ({ protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'session-A',
  providers: [{ id: 'provider-A', name: 'Morphir connected', kind: 'connected', status: 'available', capabilities: [
    { name: 'morphir/workspace/open', version: '1' }, { name: profile, version },
  ] }], initialSources: [root] });
const snapshot = () => ({ snapshot: { id: 'workspace-A', root, name: 'Orders', configAnchor: null,
  state: 'open', projects: [project], modelSources: [], knowledgeBaseSources: [], diagnostics: [] } });
const unavailable = { profile, contractVersion: version, status: 'unavailable', reason: 'not_compiled' };
const limits = () => ModelOriginalsConnectionLimits.create({ manifestBytes: 128 * 1024 });
type Request = { id: number; method: string; params: Record<string, unknown> };

class Socket extends EventTarget {
  readyState = 1;
  closes = 0;
  requests: string[] = [];
  constructor(readonly respond: (request: Request) => string | undefined) { super(); }
  send(raw: string) {
    this.requests.push(raw);
    queueMicrotask(() => {
      const reply = this.respond(JSON.parse(raw) as Request);
      if (reply !== undefined) this.dispatchEvent(new MessageEvent('message', { data: reply }));
    });
  }
  close() { ++this.closes; this.readyState = 3; this.dispatchEvent(new Event('close')); }
}
function peer(request: Request) {
  const result = request.method === 'morphir.session.initialize' ? { protocolVersion: 1 }
    : request.method === 'morphir.workspace.open' ? snapshot() : unavailable;
  return JSON.stringify({ jsonrpc: '2.0', id: request.id, result });
}
function fixture(options: { manifestRaw?: string; respond?: (request: Request) => string | undefined; status?: number;
  onObservation?: (event: ModelOriginalsObservation) => void } = {}) {
  let fetched = 0, sockets = 0;
  const socket = new Socket(options.respond ?? peer);
  const abort = new AbortController();
  const observations: ModelOriginalsObservation[] = [];
  const open = () => openModelOriginalsSession(new URL('http://morphir.local/workbench'), {
    limits: limits(), signal: abort.signal,
    fetch: async (input, init) => {
      ++fetched;
      assert.equal(String(input), 'http://morphir.local/api/session');
      assert.equal(init?.credentials, 'same-origin'); assert.equal(init?.cache, 'no-store');
      assert.equal(init?.signal, abort.signal);
      return new Response(options.manifestRaw ?? JSON.stringify(manifest()), { status: options.status ?? 200 });
    },
    createSocket: url => { ++sockets; assert.equal(url, 'ws://morphir.local/rpc'); return socket; },
    observe: event => { observations.push(event); options.onObservation?.(event); },
  });
  return { open, socket, abort, observations, counts: () => ({ fetched, sockets }) };
}

test('actual initialization, discovery and capture share one monotonic request sequence', async () => {
  const f = fixture(); const opened = await f.open(); assert.equal(opened.kind, 'ready');
  if (opened.kind !== 'ready') throw new Error('Missing session');
  const session = opened.session;
  assert.equal(session.sources.length, 1);
  const projects = await session.openSource(session.sources[0]!);
  assert.equal(projects.length, 1); assert.equal(projects[0]!.name, 'Pricing');
  const exchange = await session.exchangeCapture(projects[0]!, { scope: 'complete', semantic: 'projection' });
  assert.equal(exchange.requestId, '3');
  assert.deepEqual(f.socket.requests.map(raw => JSON.parse(raw) as Request), [
    { jsonrpc: '2.0', id: 1, method: 'morphir.session.initialize', params: { protocolVersion: 1, sessionId: 'session-A' } },
    { jsonrpc: '2.0', id: 2, method: 'morphir.workspace.open', params: { source: root } },
    { jsonrpc: '2.0', id: 3, method: 'morphir.model-originals.capture', params: {
      contractVersion: version, source: { providerId: 'provider-A', locator: 'workspace:orders' },
      projectId: project.id, scope: 'complete', semantic: 'projection',
    } },
  ]);
  assert.equal(exchange.reply, JSON.stringify({ jsonrpc: '2.0', id: 3, result: unavailable }));
  assert(Object.isFrozen(projects[0]));
  assert.equal(f.observations.filter(event => event.kind === 'exchange').length, 3);
  await assert.rejects(session.exchangeCapture(projects[0]!, { scope: 'primary', semantic: 'none' }), /capture|closed/i);
  assert.equal(f.socket.requests.length, 3);
  session.close(); session.close(); assert.equal(f.socket.closes, 1);
});

test('absent, incompatible or disconnected offers never create a socket or downgrade', async () => {
  for (const change of ['absent', 'version', 'disconnected']) {
    const offered = manifest();
    if (change === 'absent') offered.providers[0]!.capabilities.pop();
    if (change === 'version') offered.providers[0]!.capabilities[1]!.version = '0.1.0-draft.2';
    if (change === 'disconnected') offered.providers[0]!.status = 'disconnected';
    const f = fixture({ manifestRaw: JSON.stringify(offered) });
    assert.deepEqual(await f.open(), { kind: 'unavailable', reason: 'not-offered' });
    assert.deepEqual(f.counts(), { fetched: 1, sockets: 0 });
  }
});

test('authentication, duplicate manifest members and ambiguous offers refuse before socket effects', async () => {
  const duplicate = JSON.stringify(manifest()).replace('"sessionId":"session-A"', '"sessionId":"session-A","sessionId":"session-A"');
  const ambiguous = manifest(); ambiguous.providers[0]!.capabilities.push({ name: profile, version });
  for (const options of [{ status: 401 }, { status: 403 }, { manifestRaw: duplicate }, { manifestRaw: JSON.stringify(ambiguous) }]) {
    const f = fixture(options); await assert.rejects(f.open());
    assert.equal(f.counts().sockets, 0);
  }
});

test('literal initialize correlation and protocol checks precede workspace discovery', async () => {
  for (const raw of [
    '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":1}}',
    '{"jsonrpc":"2.0","id":1.0,"result":{"protocolVersion":1}}',
    '{"jsonrpc":"2.0","id":1,"id":1,"result":{"protocolVersion":1}}',
    '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2}}',
    '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1},"error":{"code":-32000,"message":"bad"}}',
  ]) {
    const f = fixture({ respond: () => raw }); await assert.rejects(f.open());
    assert.equal(f.socket.requests.length, 1); assert.equal(f.socket.closes, 1);
  }
});

test('project selections belong to their actual connection and preserve IDs despite equal labels', async () => {
  const f = fixture({ respond: request => request.method === 'morphir.workspace.open'
    ? JSON.stringify({ jsonrpc: '2.0', id: request.id, result: { snapshot: { ...snapshot().snapshot,
      projects: [project, { ...project, id: 'another-project' }] } } }) : peer(request) });
  const a = await f.open(); const g = fixture(); const b = await g.open();
  assert.equal(a.kind, 'ready'); assert.equal(b.kind, 'ready');
  if (a.kind !== 'ready' || b.kind !== 'ready') throw new Error('Missing session');
  const projects = await a.session.openSource(a.session.sources[0]!);
  assert.deepEqual(projects.map(p => p.projectId), [project.id, 'another-project']);
  await assert.rejects(b.session.exchangeCapture(projects[0]!, { scope: 'primary', semantic: 'none' }), /selection/i);
  assert.equal(g.socket.requests.length, 1);
  a.session.close(); assert.equal(f.socket.closes, 1); assert.equal(g.socket.closes, 0);
  b.session.close();
});

test('foreign snapshot roots and duplicate actual project IDs never create usable selections', async () => {
  for (const bad of [
    { ...snapshot().snapshot, root: { ...root, providerId: 'foreign' } },
    { ...snapshot().snapshot, projects: [project, project] },
  ]) {
    const f = fixture({ respond: request => request.method === 'morphir.workspace.open'
      ? JSON.stringify({ jsonrpc: '2.0', id: request.id, result: { snapshot: bad } }) : peer(request) });
    const result = await f.open(); if (result.kind !== 'ready') throw new Error('Missing session');
    await assert.rejects(result.session.openSource(result.session.sources[0]!));
    assert.equal(f.socket.requests.length, 2); assert.equal(f.socket.closes, 1);
  }
});

test('an aborted opener performs no effects, and abort after initialization closes only its owned channel', async () => {
  const before = fixture(); before.abort.abort(); await assert.rejects(before.open(), /cancel/i);
  assert.deepEqual(before.counts(), { fetched: 0, sockets: 0 });
  const active = fixture(); const other = fixture();
  const a = await active.open(); const b = await other.open();
  if (a.kind !== 'ready' || b.kind !== 'ready') throw new Error('Missing session');
  active.abort.abort(); assert.equal(active.socket.closes, 1); assert.equal(other.socket.closes, 0);
  await assert.rejects(a.session.openSource(a.session.sources[0]!), /closed|cancel/i);
  b.session.close();
});

test('the production factory uses actual HTTP and WebSocket initialization without replacing its state', async () => {
  const requests: string[] = [];
  const server = Bun.serve({ port: 0,
    fetch(request, server) {
      if (new URL(request.url).pathname === '/api/session') return Response.json(manifest());
      if (server.upgrade(request)) return;
      return new Response('Not found', { status: 404 });
    }, websocket: { message(socket, raw) {
      assert.equal(typeof raw, 'string'); requests.push(String(raw));
      socket.send(peer(JSON.parse(String(raw)) as Request));
    } },
  });
  try {
    const opened = await openModelOriginalsSession(new URL(server.url), { limits: limits(), signal: new AbortController().signal });
    if (opened.kind !== 'ready') throw new Error('Missing actual initialized session');
    const projects = await opened.session.openSource(opened.session.sources[0]!);
    const result = await opened.session.exchangeCapture(projects[0]!, { scope: 'primary', semantic: 'none' });
    assert.equal(result.requestId, '3');
    assert.deepEqual(requests.map(raw => (JSON.parse(raw) as Request).id), [1, 2, 3]);
    opened.session.close();
  } finally { await server.stop(true); }
});

test('manifest budgets use streamed UTF-8 bytes, including split multibyte input and exact limits', async () => {
  const value = manifest(); value.initialSources[0]!.displayName = 'Orders 🐟';
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  for (const maximum of [bytes.length, bytes.length - 1]) {
    let sockets = 0;
    const socket = new Socket(peer);
    const start = bytes.indexOf(0xf0) + 1;
    const result = openModelOriginalsSession(new URL('http://morphir.local'), {
      limits: ModelOriginalsConnectionLimits.create({ manifestBytes: maximum }), signal: new AbortController().signal,
      fetch: async () => new Response(new ReadableStream({ start(controller) {
        controller.enqueue(bytes.slice(0, start)); controller.enqueue(bytes.slice(start)); controller.close();
      } })), createSocket: () => { ++sockets; return socket; },
    });
    if (maximum === bytes.length) {
      const opened = await result; assert.equal(opened.kind, 'ready');
      if (opened.kind === 'ready') opened.session.close();
      assert.equal(sockets, 1);
    } else { await assert.rejects(result, /byte limit/i); assert.equal(sockets, 0); }
  }
  for (const maximum of [0, -1, 1.1, Infinity, 131073])
    assert.throws(() => ModelOriginalsConnectionLimits.create({ manifestBytes: maximum }));
  let sockets = 0;
  await assert.rejects(openModelOriginalsSession(new URL('http://morphir.local'), {
    limits: limits(), signal: new AbortController().signal,
    fetch: async () => new Response(new Uint8Array([0xff])), createSocket: () => { ++sockets; return new Socket(peer); },
  }));
  assert.equal(sockets, 0);
});

test('discovery cannot redirect a socket to another origin or embed credentials and fragments', async () => {
  for (const webSocketPath of ['//elsewhere.test/rpc', 'https://elsewhere.test/rpc',
    'http://user:mypassword@morphir.local/rpc', '/rpc#fragment']) {
    const offered = { ...manifest(), webSocketPath };
    const f = fixture({ manifestRaw: JSON.stringify(offered) }); await assert.rejects(f.open());
    assert.equal(f.counts().sockets, 0);
  }
});

test('refreshing discovery invalidates earlier project selections without resetting request IDs', async () => {
  const f = fixture(); const opened = await f.open();
  if (opened.kind !== 'ready') throw new Error('Missing session');
  const session = opened.session, source = session.sources[0]!;
  const first = await session.openSource(source), current = await session.openSource(source);
  await assert.rejects(session.exchangeCapture(first[0]!, { scope: 'primary', semantic: 'none' }), /stale/i);
  assert.equal(f.socket.requests.length, 3);
  const exchanged = await session.exchangeCapture(current[0]!, { scope: 'primary', semantic: 'none' });
  assert.equal(exchanged.requestId, '4'); session.close();
});

test('copied discovery objects and invalid capture options cannot grant request authority', async () => {
  const f = fixture(); const opened = await f.open();
  if (opened.kind !== 'ready') throw new Error('Missing session');
  const session = opened.session;
  await assert.rejects(session.openSource({ ...session.sources[0]! }), /selection/i);
  const projects = await session.openSource(session.sources[0]!);
  await assert.rejects(session.exchangeCapture({ ...projects[0]! }, { scope: 'primary', semantic: 'none' }), /selection/i);
  await assert.rejects(session.exchangeCapture(projects[0]!, { scope: 'everything' as never, semantic: 'none' }));
  assert.equal(f.socket.requests.length, 2); session.close();
});

test('pending requests reject overlapping discovery and settle on actual cancellation', async () => {
  const f = fixture({ respond: request => request.method === 'morphir.workspace.open' ? undefined : peer(request) });
  const opened = await f.open(); if (opened.kind !== 'ready') throw new Error('Missing session');
  const pending = opened.session.openSource(opened.session.sources[0]!);
  await assert.rejects(opened.session.openSource(opened.session.sources[0]!), /pending/i);
  assert.equal(f.socket.requests.length, 2); f.abort.abort();
  await assert.rejects(pending, /closed|cancel/i); assert.equal(f.socket.closes, 1);
});

test('observer reentrancy cannot publish discovery after its connection is cancelled', async () => {
  const f = fixture({ onObservation: event => {
    if (event.kind === 'exchange' && event.method === 'morphir.workspace.open') f.abort.abort();
  } });
  const opened = await f.open(); if (opened.kind !== 'ready') throw new Error('Missing session');
  await assert.rejects(opened.session.openSource(opened.session.sources[0]!), /closed|cancel/i);
  assert.equal(f.socket.requests.length, 2); assert.equal(f.socket.closes, 1);
});

test('cancelling a pending manifest read cancels its owned stream before any socket', async () => {
  const abort = new AbortController(); let cancelled = 0, sockets = 0;
  let reading!: () => void;
  const started = new Promise<void>(resolve => { reading = resolve; });
  const pending = openModelOriginalsSession(new URL('http://morphir.local'), {
    limits: limits(), signal: abort.signal, createSocket: () => { ++sockets; return new Socket(peer); },
    fetch: async () => new Response(new ReadableStream({
      pull() { reading(); }, cancel() { ++cancelled; },
    })),
  });
  await started; abort.abort(); await assert.rejects(pending, /cancel/i);
  assert.equal(cancelled, 1); assert.equal(sockets, 0);
});

test('closed v1 discovery and rejected raw replies remain observable without becoming selections', async () => {
  for (const mutate of [
    (m: ReturnType<typeof manifest>) => ({ ...m, extra: true }),
    (m: ReturnType<typeof manifest>) => ({ ...m, providers: [{ ...m.providers[0]!, kind: 'unknown' }] }),
    (m: ReturnType<typeof manifest>) => ({ ...m, initialSources: [{ ...root, locator: 'bad\u0000locator' }] }),
    (m: ReturnType<typeof manifest>) => ({ ...m, initialSources: [{ ...root, providerId: 'unknown' }] }),
  ]) {
    const f = fixture({ manifestRaw: JSON.stringify(mutate(manifest())) });
    await assert.rejects(f.open()); assert.equal(f.counts().sockets, 0);
  }
  const raw = '{"jsonrpc":"2.0","id":1.0,"result":{"protocolVersion":1}}';
  const f = fixture({ respond: () => raw }); await assert.rejects(f.open());
  const exchange = f.observations.find(event => event.kind === 'exchange');
  assert.equal(exchange?.kind === 'exchange' ? exchange.reply : undefined, raw);
  assert.equal(f.socket.closes, 1);
});

test('capture options are read once before validation and the same values are sent', async () => {
  const f = fixture(); const opened = await f.open();
  if (opened.kind !== 'ready') throw new Error('Missing session');
  const projects = await opened.session.openSource(opened.session.sources[0]!);
  let scopes = 0, semantics = 0;
  await opened.session.exchangeCapture(projects[0]!, {
    get scope(): 'primary' { return ++scopes === 1 ? 'primary' : 'everything' as never; },
    get semantic(): 'none' { return ++semantics === 1 ? 'none' : 'unchecked' as never; },
  });
  assert.deepEqual((JSON.parse(f.socket.requests[2]!) as Request).params, {
    contractVersion: version, source: { providerId: root.providerId, locator: root.locator },
    projectId: project.id, scope: 'primary', semantic: 'none',
  });
  assert.equal(scopes, 1); assert.equal(semantics, 1); opened.session.close();
});

test('a manifest limit getter cannot change the stored validated budget', () => {
  let reads = 0;
  const limit = ModelOriginalsConnectionLimits.create({
    get manifestBytes() { return ++reads <= 3 ? 128 : Infinity; },
  });
  assert.equal(limit.manifestBytes, 128); assert.equal(reads, 1);
});

test('runtime construction and overridden limit getters cannot bypass the byte budget', async () => {
  assert.throws(() => Reflect.construct(ModelOriginalsConnectionLimits, [Infinity]));
  const genuine = ModelOriginalsConnectionLimits.create({ manifestBytes: 1 });
  let reads = 0, sockets = 0;
  const pending = openModelOriginalsSession(new URL('http://morphir.local'), {
    get limits() { return ++reads === 1 ? genuine : { manifestBytes: Infinity } as ModelOriginalsConnectionLimits; },
    signal: new AbortController().signal,
    fetch: async () => new Response(JSON.stringify(manifest())),
    createSocket: () => { ++sockets; return new Socket(peer); },
  });
  await assert.rejects(pending, /byte limit/i); assert.equal(reads, 1); assert.equal(sockets, 0);
});

test('a caller URL mutation during discovery cannot change the captured socket origin', async () => {
  const base = new URL('http://morphir.local/workbench'), socket = new Socket(peer);
  const opened = await openModelOriginalsSession(base, {
    limits: limits(), signal: new AbortController().signal,
    fetch: async input => {
      assert.equal(String(input), 'http://morphir.local/api/session');
      base.href = 'https://elsewhere.test/';
      return Response.json(manifest());
    }, createSocket: url => { assert.equal(url, 'ws://morphir.local/rpc'); return socket; },
  });
  if (opened.kind !== 'ready') throw new Error('Missing session');
  opened.session.close();
});
