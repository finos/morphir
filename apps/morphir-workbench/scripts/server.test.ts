import type { TestContext } from 'node:test';
import type { Server, IncomingMessage, IncomingHttpHeaders } from 'node:http';
import type { AddressInfo, Socket } from 'node:net';
import type { ExecutionGateway } from './execution-contracts.ts';
import { malformed } from '../../../tests/helpers.ts';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request as httpRequest } from 'node:http';
import { once } from 'node:events';
import { createWorkbenchServer, hostOrigin } from './server.ts';

async function listen(server: Server) {
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}
const get = (url: string, headers?: HeadersInit) => fetch(url, { headers, redirect: 'manual' });

test('proxy target is an explicit loopback HTTP origin', () => {
  assert.equal(hostOrigin('http://127.0.0.1:3000')!.origin, 'http://127.0.0.1:3000');
  for (const url of ['https://127.0.0.1:3000', 'http://example.com:3000', 'http://127.0.0.1:3000/rpc', 'http://user:pass@127.0.0.1:3000', 'http://127.0.0.1:3000/?token=secret']) {
    assert.throws(() => hostOrigin(url), /must be/);
  }
});

test('launch cookie is exchanged through the proxy and private routes enforce the browser origin', async t => {
  const requests: { url?: string; host?: string; cookie?: string }[] = [];
  const upstream = createServer((request, response) => {
    requests.push({ url: request.url, host: request.headers.host, cookie: request.headers.cookie });
    if (request.url === '/launch?token=one-use') {
      response.writeHead(303, { 'Set-Cookie': 'morphir_session_test=secret; HttpOnly; SameSite=Strict; Path=/', Location: '/' }).end();
    } else if (request.url === '/api/session' && request.headers.cookie === 'morphir_session_test=secret') {
      response.writeHead(200, { 'Content-Type': 'application/json' }).end('{"protocolVersion":1}');
    } else response.writeHead(401).end();
  });
  const target = await listen(upstream);
  const proxy = createWorkbenchServer({ host: target });
  const base = await listen(proxy);
  t.after(() => { proxy.closeAllConnections(); proxy.close(); upstream.closeAllConnections(); upstream.close(); });
  const launch = await get(`${base}/launch?token=one-use`);
  assert.equal(launch.status, 303); assert.equal(launch.headers.get('location'), '/?mode=connected');
  assert.match(launch.headers.get('set-cookie')!, /HttpOnly; SameSite=Strict/);
  const cookie = launch.headers.get('set-cookie')!.split(';')[0]!;
  assert.equal((await get(`${base}/api/session`, { Cookie: cookie })).status, 200);
  assert.equal(requests[1]!.host, new URL(target).host);
  assert.equal((await get(`${base}/api/session`, { Cookie: cookie, Origin: 'https://attacker.example' })).status, 403);
  assert.equal((await get(`${base}/api/session`, { Cookie: cookie, 'Sec-Fetch-Site': 'cross-site' })).status, 403);
  assert.equal(requests.length, 2);
  const wrongHost = await new Promise(resolve => {
    httpRequest(`${base}/api/session`, { headers: { Host: 'attacker.example' } }, response => { response.resume(); resolve(response.statusCode); }).end();
  });
  assert.equal(wrongHost, 403);
});

test('WebSocket proxy checks its own origin before rewriting the upstream Host and Origin', async t => {
  let observed;
  const upstream = createServer();
  upstream.on('upgrade', (request, socket) => {
    observed = request.headers;
    socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');
    socket.on('data', data => socket.write(data));
    socket.on('error', () => {});
    socket.on('end', () => socket.destroy());
  });
  const target = await listen(upstream);
  const proxy = createWorkbenchServer({ host: target });
  const base = await listen(proxy);
  t.after(() => { proxy.close(); upstream.close(); });
  const open = (origin: string) => new Promise<{ response: IncomingMessage; socket?: Socket }>(resolve => {
    const request = httpRequest(`${base}/rpc`, { headers: {
      Connection: 'Upgrade', Upgrade: 'websocket', Origin: origin, Cookie: 'morphir_session_test=secret',
      'Sec-WebSocket-Key': 'a-test-key', 'Sec-WebSocket-Version': '13',
    } });
    request.on('upgrade', (response, socket) => resolve({ response, socket }));
    request.on('response', response => { response.resume(); resolve({ response }); });
    request.end();
  });
  assert.equal((await open('https://attacker.example')).response.statusCode, 403);
  assert.equal(observed, undefined);
  const { response, socket } = await open(base);
  assert.equal(response.statusCode, 101);
  assert.equal(observed!.host, new URL(target).host);
  assert.equal(observed!.origin, target);
  assert.equal(observed!.cookie, 'morphir_session_test=secret');
  const data = once(socket!, 'data'); socket!.write('frame bytes');
  assert.equal(String((await data)[0]), 'frame bytes');
  socket!.destroy();
});

async function executionGateway(t: TestContext, options: { authHang?: boolean; authResponse?: string; executions?: ExecutionGateway; executionAuthDeadlineMs?: number; executionBodyDeadlineMs?: number } = {}) {
  const seen: { path?: string; headers: IncomingHttpHeaders }[] = [];
  let session = 'authenticated-session';
  const upstream = createServer((request, response) => {
    seen.push({ path: request.url, headers: request.headers });
    if (request.headers.cookie !== 'morphir_session_test=secret') { response.writeHead(401).end(); return; }
    if (options.authHang) return;
    response.writeHead(200, { 'Content-Type': 'application/json' }).end(options.authResponse ?? JSON.stringify({ protocolVersion: 1, webSocketPath: '/rpc', sessionId: session, providers: [], initialSources: [] }));
  });
  const target = await listen(upstream);
  const commands: { op: string; body: string; sessionId: string }[] = [];
  let bound: string | undefined;
  const executions: ExecutionGateway & { closed?: boolean } = options.executions ?? {
    decode: JSON.parse,
    async session(sessionId) {
      if (bound && bound !== sessionId) throw Object.assign(new Error('private source should not leak'), { status: 409, code: 'workbench.session_changed' });
      bound = sessionId;
      return { profile: 'morphir/workbench/host', contractVersion: '0.2.0-draft.1', offer: { sessionId } };
    },
    async command(op, body, sessionId) { commands.push({ op, body, sessionId }); return { state: 'running' }; },
    async close() { this.closed = true; },
  };
  const proxy = createWorkbenchServer({ host: target, executions, ...options });
  const base = await listen(proxy);
  t.after(async () => { proxy.closeAllConnections(); await new Promise(resolve => proxy.close(resolve)); await proxy.executionCleanup; upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve)); });
  const headers = { Cookie: 'morphir_session_test=secret', Origin: base, 'Content-Type': 'application/json' };
  return { base, headers, executions, seen, commands, changeSession: (value: string) => { session = value; } };
}

test('execution routes are disabled without explicit provider and require a configured upstream host', async t => {
  const server = createWorkbenchServer(); const base = await listen(server);
  t.after(() => { server.closeAllConnections(); server.close(); });
  for (const method of ['GET', 'POST']) assert.equal((await fetch(`${base}/api/workbench/session`, { method })).status, 404);
  assert.throws(() => createWorkbenchServer({ executions: malformed({}) }), /upstream|host/i);
});
test('execution descriptor authenticates cookie against bounded v1 session and forwards only cookie', async t => {
  const { base, headers, seen } = await executionGateway(t);
  assert.equal((await get(`${base}/api/workbench/session`)).status, 401);
  const response = await get(`${base}/api/workbench/session`, { ...headers, Authorization: 'must-not-forward' });
  assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('access-control-allow-origin'), null);
  assert.equal((await response.json()).offer.sessionId, 'authenticated-session');
  assert.equal(seen.at(-1)!.path, '/api/session'); assert.equal(seen.at(-1)!.headers.authorization, undefined);
  assert.equal(seen.at(-1)!.headers.origin, undefined);
});
test('retired job routes cannot dispatch work even with valid authentication', async t => {
  const { base, headers, commands, seen } = await executionGateway(t);
  for (const path of ['jobs', 'jobs/submit', 'jobs/query', 'jobs/cancel', 'jobs/release']) {
    const response = await fetch(`${base}/api/workbench/${path}`, { method: 'POST', headers, body: '{}' });
    assert.equal(response.status, 404);
  }
  assert.equal(commands.length, 0);
  assert.equal(seen.length, 0);
  assert.equal((await fetch(`${base}/api/workbench/submit`, { method: 'POST', headers, body: '{}' })).status, 200);
  assert.equal(commands.length, 1);
});
test('execution POST requires exact origin JSON and forwards unmodified raw body after fresh authentication', async t => {
  const { base, headers, commands, seen } = await executionGateway(t);
  const body = '{"contractVersion":"0.2.0-draft.1","duplicate":1,"duplicate":2}';
  const response = await fetch(`${base}/api/workbench/submit`, { method: 'POST', headers, body });
  assert.equal(response.status, 200); assert.equal(commands[0]!.body, body); assert.equal(commands[0]!.sessionId, 'authenticated-session');
  const authenticated = seen.length;
  assert.equal((await fetch(`${base}/api/workbench/query`, { method: 'POST', headers: { Cookie: headers.Cookie, 'Content-Type': 'application/json' }, body: '{}' })).status, 403);
  assert.equal((await fetch(`${base}/api/workbench/query`, { method: 'POST', headers: { ...headers, Origin: 'https://attacker.example' }, body: '{}' })).status, 403);
  assert.equal(seen.length, authenticated);
  assert.equal((await fetch(`${base}/api/workbench/query`, { method: 'POST', headers: { ...headers, 'Content-Type': 'text/plain' }, body: '{}' })).status, 400);
  assert.equal(commands.length, 1);
});
test('changed authenticated session returns bounded409 without replacing owner', async t => {
  const { base, headers, changeSession } = await executionGateway(t);
  assert.equal((await get(`${base}/api/workbench/session`, headers)).status, 200);
  changeSession('replacement');
  const response = await get(`${base}/api/workbench/session`, headers);
  assert.equal(response.status, 409); assert.equal((await response.json()).error.code, 'workbench.session_changed');
  changeSession('authenticated-session'); assert.equal((await get(`${base}/api/workbench/session`, headers)).status, 200);
});
test('execution body byte limit and fatal UTF8 reject before core invocation', async t => {
  const { base, headers, commands } = await executionGateway(t);
  assert.equal((await fetch(`${base}/api/workbench/submit`, { method: 'POST', headers, body: 'x'.repeat(1024 * 1024 + 1) })).status, 413);
  assert.equal((await fetch(`${base}/api/workbench/submit`, { method: 'POST', headers, body: Buffer.from([0xff]) })).status, 400);
  assert.equal(commands.length, 0);
});

test('real duplicate-aware core authenticates exact manifests and rejects duplicate submission members', async t => {
  const { createExecutionProvider } = await import('./execution-provider.ts');
  const { readFile } = await import('node:fs/promises');
  const executions = await createExecutionProvider();
  const { base, headers, changeSession } = await executionGateway(t, { executions });
  const session = await get(`${base}/api/workbench/session`, headers);
  assert.equal(session.status, 200); assert.match(session.headers.get('content-type')!, /application\/json; charset=utf-8/);
  const descriptor = await session.json();
  assert.equal(descriptor.offer.sessionId, 'authenticated-session');
  const model = await readFile(new URL('../fixtures/typed-pricing.json', import.meta.url), 'utf8');
  const submit = JSON.stringify({ contractVersion: '0.2.0-draft.1', model, entry: 'pricing:quotes#difference', inputs: { format: 'json', source: '[{"type":"int","value":"7"},{"type":"int","value":"3"}]' } });
  const duplicate = submit.replace('{', '{"contractVersion":"0.2.0-draft.1",');
  const rejected = await fetch(`${base}/api/workbench/submit`, { method: 'POST', headers, body: duplicate });
  assert.equal(rejected.status, 400); const errorText = await rejected.text(); assert(!errorText.includes(model)); assert(!errorText.includes('secret'));
  const accepted = await fetch(`${base}/api/workbench/submit`, { method: 'POST', headers, body: submit });
  assert.equal(accepted.status, 200); const execution = await accepted.json(); assert.equal(execution.receipt.sequence, 0);
  changeSession('new-session');
  const query = JSON.stringify({ contractVersion: '0.2.0-draft.1', identity: execution.identity });
  assert.equal((await fetch(`${base}/api/workbench/query`, { method: 'POST', headers, body: query })).status, 409);
  changeSession('authenticated-session');
  let latest;
  for (let attempt = 0; attempt < 100; attempt++) {
    latest = await (await fetch(`${base}/api/workbench/query`, { method: 'POST', headers, body: query })).json();
    if (latest.state === 'terminal') break;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.equal(latest.state, 'terminal'); assert.deepEqual(latest.outcomes.calls[0].outcome, { status: 'returned', value: { type: 'int', value: '4' } });
  assert.deepEqual(await (await fetch(`${base}/api/workbench/release`, { method: 'POST', headers, body: query })).json(), { released: true });
  const absent = await fetch(`${base}/api/workbench/query`, { method: 'POST', headers, body: query });
  assert.equal(absent.status, 404); assert.equal((await absent.json()).error.code, 'workbench.host_unknown_execution');
});
test('malformed duplicate foreign and oversized authentication manifests never bind a provider', async t => {
  const { createExecutionProvider } = await import('./execution-provider.ts');
  const manifest = { protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'authenticated-session', providers: [], initialSources: [] };
  for (const authResponse of [
    JSON.stringify(manifest).replace('{', '{"sessionId":"wrong-owner",'),
    JSON.stringify({ ...manifest, protocolVersion: 2 }),
    JSON.stringify({ ...manifest, extra: true }),
    JSON.stringify({ ...manifest, providers: 'wrong' }),
    ' '.repeat(1024 * 1024 + 1),
  ]) {
    const executions = await createExecutionProvider(); let bindings = 0;
    const original = executions.session; executions.session = (...args) => { bindings++; return original(...args); };
    const { base, headers } = await executionGateway(t, { executions, authResponse });
    assert.equal((await get(`${base}/api/workbench/session`, headers)).status, 503);
    assert.equal(bindings, 0);
  }
});
test('authentication and body deadlines fail without invoking an execution or inventing terminal state', async t => {
  const unavailable = await executionGateway(t, { authHang: true, executionAuthDeadlineMs: 20 });
  assert.equal((await get(`${unavailable.base}/api/workbench/session`, unavailable.headers)).status, 503);
  const gateway = await executionGateway(t, { executionBodyDeadlineMs: 20 });
  const status = await new Promise((resolve, reject) => {
    const request = httpRequest(`${gateway.base}/api/workbench/submit`, { method: 'POST', headers: gateway.headers }, response => { response.resume(); resolve(response.statusCode); });
    request.on('error', reject); request.write('{');
  });
  assert.equal(status, 503); assert.equal(gateway.commands.length, 0);
});

test('built-in sample JSON is served from samples/<language>/ and nothing else under it', async t => {
  const server = createWorkbenchServer();
  const origin = await listen(server);
  t.after(() => server.close());
  const index = await get(origin + '/samples/elm/index.json');
  assert.equal(index.status, 200);
  assert.match(index.headers.get('content-type') ?? '', /application\/json/);
  assert.equal((await get(origin + '/samples/elm/..%2Findex.html')).status, 404);
  assert.equal((await get(origin + '/samples/elm/x/y.json')).status, 404);
});
