import type { IncomingMessage, OutgoingHttpHeaders, Server, ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import type { ExecutionOperation, ExecutionGateway } from './execution-contracts.ts';
import { isRecord, workbenchError } from '../../../types/data.ts';
import { createServer, request as forwardRequest } from 'node:http';
import { readFile } from 'node:fs/promises';
import { validateManifest } from '../browser/transport.ts';

const executionLimit = 1024 * 1024;
const executionPaths = new Map<string, ExecutionOperation | 'session'>([['/api/workbench/session', 'session'], ['/api/workbench/submit', 'submit'], ['/api/workbench/query', 'query'], ['/api/workbench/cancel', 'cancel'], ['/api/workbench/release', 'release']]);
const executionFailure = (code: string, status: number) => Object.assign(new Error('The Workbench execution request failed.'), { code, status });
function executionJSON(response: ServerResponse, status: number, value: unknown) {
  let text = JSON.stringify(value);
  if (Buffer.byteLength(text) > executionLimit) { status = 503; text = JSON.stringify({ error: { code: 'workbench.host_response_limit', message: 'The host response exceeded its limit.' } }); }
  if (!response.destroyed) { response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); response.end(text); }
}
function executionError(response: ServerResponse, cause: unknown) {
  const error = workbenchError(cause);
  const code = typeof error?.code === 'string' && /^[a-zA-Z0-9_.-]{1,128}$/.test(error.code) ? error.code : 'workbench.host_unavailable';
  const status = [400, 401, 403, 404, 409, 413, 503].includes(error.status ?? 503) ? error.status! : 503;
  executionJSON(response, status, { error: { code, message: status === 401 ? 'Authenticate with the Morphir host before using executions.' : code === 'workbench.session_changed' ? 'The authenticated host session changed. The retained execution owner is unchanged.' : 'The host rejected this execution request.' } });
}
function authenticateExecution(upstream: URL, cookie: string | undefined, deadlineMs: number, decode: (source: string) => unknown) {
  return new Promise<string>((resolve, reject) => {
    let settled = false;
    const done = (error: unknown, value?: string) => { if (settled) return; settled = true; clearTimeout(timer); error ? reject(error) : resolve(value!); };
    const forwarded = forwardRequest(new URL('/api/session', upstream), { headers: { Host: upstream.host, ...(cookie ? { Cookie: cookie } : {}) } }, result => {
      const chunks: Buffer[] = []; let size = 0;
      result.on('data', chunk => { size += chunk.length; if (size > executionLimit) { done(executionFailure('workbench.host_unavailable', 503)); result.destroy(); } else chunks.push(chunk); });
      result.on('end', () => {
        if (result.statusCode === 401 || result.statusCode === 403) { done(executionFailure('workbench.host_authentication', 401)); return; }
        try {
          if (result.statusCode !== 200) throw new Error('Session unavailable');
          const session = decode(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
          const keys = ['protocolVersion', 'webSocketPath', 'sessionId', 'providers', 'initialSources'];
          if (!isRecord(session) || Array.isArray(session) || Object.keys(session).length !== keys.length || !keys.every(key => Object.hasOwn(session, key)) || typeof session.sessionId !== 'string' || session.sessionId.length > 128) throw new Error('Invalid manifest');
          validateManifest(session);
          done(null, session.sessionId);
        } catch { done(executionFailure('workbench.host_unavailable', 503)); }
      });
      result.on('error', () => done(executionFailure('workbench.host_unavailable', 503)));
    });
    const timer = setTimeout(() => { done(executionFailure('workbench.host_unavailable', 503)); forwarded.destroy(); }, deadlineMs);
    forwarded.on('error', () => done(executionFailure('workbench.host_unavailable', 503)));
    forwarded.end();
  });
}
function readExecutionBody(request: IncomingMessage, deadlineMs: number) {
  return new Promise<string>((resolve, reject) => {
    const chunks: Buffer[] = []; let size = 0, settled = false;
    const done = (error: unknown, value?: string) => {
      if (settled) return; settled = true;
      clearTimeout(timer); request.off('data', data); request.off('end', end); request.off('error', failed); request.off('aborted', failed);
      if (!request.complete) request.once('error', () => {});
      error ? reject(error) : resolve(value!);
    };
    const data = (chunk: Buffer) => { size += chunk.length; if (size > executionLimit) { done(executionFailure('workbench.host_input_limit', 413)); request.resume(); } else chunks.push(chunk); };
    const end = () => { try { done(null, new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); } catch { done(executionFailure('workbench.host_utf8', 400)); } };
    const failed = () => done(executionFailure('workbench.host_disconnected', 400));
    const timer = setTimeout(() => { done(executionFailure('workbench.host_body_deadline', 503)); request.resume(); }, deadlineMs);
    request.on('data', data); request.on('end', end); request.on('error', failed); request.on('aborted', failed);
  });
}

export function hostOrigin(value?: string | null) {
  if (!value) return null;
  const host = new URL(value);
  if (host.protocol !== 'http:' || host.hostname !== '127.0.0.1' || !host.port || host.pathname !== '/' || host.search || host.hash || host.username || host.password) {
    throw new Error('MORPHIR_WORKBENCH_HOST_URL must be http://127.0.0.1:<port> with no path, query or credentials.');
  }
  return host;
}

export function createWorkbenchServer({ root = new URL('../dist/', import.meta.url), host = null, executions = null, executionAuthDeadlineMs = 2000, executionBodyDeadlineMs = 5000 }: { root?: URL; host?: string | null; executions?: ExecutionGateway | null; executionAuthDeadlineMs?: number; executionBodyDeadlineMs?: number } = {}) {
  const upstream = hostOrigin(host);
  if (executions && !upstream) throw new Error('Workbench executions require a configured upstream host.');
  const mime: Record<string, string> = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.json': 'application/json' };
  let authority: string;
  const allowed = (request: IncomingMessage) => request.headers.host === authority &&
    (!request.headers.origin || request.headers.origin === `http://${authority}`) &&
    request.headers['sec-fetch-site'] !== 'cross-site';
  const server = createServer(async (request, response) => {
    if (!allowed(request) || !request.url?.startsWith('/') || request.url?.startsWith('//')) {
      if (request.url?.startsWith('/api/workbench/')) executionError(response, executionFailure('workbench.host_origin', 403));
      else response.writeHead(403).end('Invalid workbench origin.');
      return;
    }
    let url;
    try { url = new URL(request.url!, `http://${authority}`); } catch { response.writeHead(400).end(); return; }
    if (url.origin !== `http://${authority}`) { response.writeHead(403).end(); return; }
    if (url.pathname.startsWith('/api/workbench/')) {
      const op = executionPaths.get(url.pathname);
      if (!executions || !op) { executionError(response, executionFailure('workbench.host_disabled', 404)); return; }
      try {
        if (url.search) throw executionFailure('workbench.host_shape', 400);
        if ((op === 'session' && request.method !== 'GET') || (op !== 'session' && request.method !== 'POST')) throw executionFailure('workbench.host_method', 400);
        if (op !== 'session' && request.headers.origin !== `http://${authority}`) throw executionFailure('workbench.host_origin', 403);
        const sessionId = await authenticateExecution(upstream!, request.headers.cookie, executionAuthDeadlineMs, source => executions.decode(source));
        if (response.destroyed) return;
        if (op === 'session') executionJSON(response, 200, await executions.session(sessionId));
        else {
          if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers['content-type'] ?? '') || (request.headers['content-encoding'] && request.headers['content-encoding'] !== 'identity')) throw executionFailure('workbench.host_content_type', 400);
          const body = await readExecutionBody(request, executionBodyDeadlineMs);
          if (!response.destroyed) executionJSON(response, 200, await executions.command(op, body, sessionId));
        }
      } catch (error) {
        if (!request.complete) { response.setHeader('Connection', 'close'); response.once('finish', () => request.destroy()); }
        executionError(response, error);
      }
      return;
    }
    if (request.method !== 'GET') { response.writeHead(405).end(); return; }
    if (upstream && ['/launch', '/api/session'].includes(url.pathname)) {
      const forwarded = forwardRequest(new URL(url.pathname + url.search, upstream), {
        headers: { Host: upstream.host, ...(request.headers.cookie ? { Cookie: request.headers.cookie } : {}) },
      }, result => {
        const headers: OutgoingHttpHeaders = { 'Cache-Control': 'no-store', 'Content-Type': result.headers['content-type'] || 'text/plain' };
        if (result.headers['set-cookie']) headers['Set-Cookie'] = result.headers['set-cookie'];
        // The one-time launch token never becomes a persisted URL or log entry.
        if ((result.statusCode ?? 502) >= 300 && (result.statusCode ?? 502) < 400) headers.Location = '/?mode=connected';
        response.writeHead(result.statusCode ?? 502, headers);
        result.pipe(response);
      });
      forwarded.setTimeout(10000, () => forwarded.destroy(new Error('Host timeout')));
      forwarded.on('error', () => { if (!response.headersSent) response.writeHead(502); response.end('The Morphir host is unavailable.'); });
      request.on('aborted', () => forwarded.destroy());
      forwarded.end();
      return;
    }
    const file = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    // Built-in samples are static JSON under samples/<language>/<id>.json.
    if (!/^[a-zA-Z0-9-]+\.(html|css|js|svg)$/.test(file) && !/^samples\/[a-z0-9-]+\/[a-zA-Z0-9-]+\.json$/.test(file)) { response.writeHead(404).end(); return; }
    try {
      let content = await readFile(new URL(file, root));
      if (upstream && file === 'index.html') content = Buffer.from(content.toString().replace('</head>', '<meta name="morphir-host-mode" content="connected"></head>'));
      response.writeHead(200, { 'Content-Type': mime[file.slice(file.lastIndexOf('.'))], 'Cache-Control': 'no-store' });
      response.end(content);
    } catch { response.writeHead(404).end('Build the workbench with npm run build first.'); }
  });
  const ownedServer = server as Server & { executionCleanup: Promise<void> };
  ownedServer.executionCleanup = Promise.resolve();
  server.on('close', () => {
    ownedServer.executionCleanup = Promise.resolve().then(() => executions?.close());
    ownedServer.executionCleanup.catch(() => {});
  });
  server.on('listening', () => { authority = `127.0.0.1:${(server.address() as AddressInfo).port}`; });
  server.on('upgrade', (request, socket, head) => {
    if (!upstream || request.url !== '/rpc' || !allowed(request) || request.headers.origin !== `http://${authority}`) {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return;
    }
    const headers: OutgoingHttpHeaders = { Host: upstream.host, Origin: upstream.origin, Connection: 'Upgrade', Upgrade: 'websocket' };
    for (const name of ['cookie', 'sec-websocket-key', 'sec-websocket-version', 'sec-websocket-protocol', 'sec-websocket-extensions']) {
      if (request.headers[name]) headers[name] = request.headers[name];
    }
    const forwarded = forwardRequest(new URL('/rpc', upstream), { headers });
    forwarded.setTimeout(10000, () => forwarded.destroy(new Error('Host timeout')));
    forwarded.on('upgrade', (response, remote, remoteHead) => {
      forwarded.setTimeout(0);
      socket.write(`HTTP/1.1 ${response.statusCode} ${response.statusMessage}\r\n`);
      for (let i = 0; i < response.rawHeaders.length; i += 2) socket.write(`${response.rawHeaders[i]}: ${response.rawHeaders[i + 1]}\r\n`);
      socket.write('\r\n');
      if (remoteHead.length) socket.write(remoteHead);
      if (head.length) remote.write(head);
      socket.pipe(remote); remote.pipe(socket);
      remote.on('error', () => socket.destroy());
      remote.on('close', () => socket.destroy());
      socket.on('close', () => remote.destroy());
    });
    forwarded.on('response', response => {
      socket.end(`HTTP/1.1 ${response.statusCode} Host rejected WebSocket\r\nConnection: close\r\n\r\n`);
      response.resume();
    });
    forwarded.on('error', () => socket.destroy());
    socket.on('error', () => forwarded.destroy());
    socket.on('close', () => forwarded.destroy());
    forwarded.end();
  });
  return ownedServer;
}
