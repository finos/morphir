import WebSocket from 'ws';
import {
  openSync, closeSync, fstatSync, lstatSync, readSync, writeFileSync, fsyncSync, unlinkSync, constants,
} from 'node:fs';
import {hostOrigin} from '../execution-client/origin.mts';
import {validateManifest} from '../execution-client/manifest.mts';
import {boundedResponse} from '../execution-client/transport.mts';
import type {Core, Fetch, Json} from '../execution-client/contracts.mts';

const version = '0.1.0';
const binding = 'workbench-http';

export interface Connection {
  profile: 'morphir/cli/workbench-connection';
  contractVersion: '0.1.0';
  binding: typeof binding;
  origin: string;
  sessionId: string;
  cookie: string;
  descriptor: Json;
}

export class Refusal extends Error {
  constructor(readonly code: string) { super(code); }
}

export function refuse(code: string): never { throw new Refusal(code); }
export const record = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === 'object' && !Array.isArray(value);
export const closed = (value: unknown, keys: string[]) =>
  record(value) && Object.keys(value).sort().join(',') === [...keys].sort().join(',');

export function readBounded(path: string, limit: number, secret = false): string {
  if (secret && (process.platform === 'win32' || !process.getuid)) refuse('connected.private_file_permissions_unavailable');
  let fd = -1;
  try {
    if (!lstatSync(path).isFile()) refuse('connected.regular_file_required');
    fd = openSync(path, constants.O_RDONLY | (constants.O_NOFOLLOW || 0) | (constants.O_NONBLOCK || 0));
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size < 0 || stat.size > limit) refuse('connected.input_limit');
    if (secret && ((stat.mode & 0o077) !== 0 || stat.uid !== process.getuid!())) refuse('connected.private_file_required');
    const chunks: Buffer[] = [];
    let total = 0;
    for (;;) {
      const buffer = Buffer.alloc(Math.min(65536, limit - total + 1));
      const count = readSync(fd, buffer, 0, buffer.length, null);
      if (!count) break;
      total += count;
      if (total > limit) refuse('connected.input_limit');
      chunks.push(buffer.subarray(0, count));
    }
    return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, total));
  } catch (error) {
    if (error instanceof Refusal) throw error;
    return refuse('connected.input_unavailable');
  } finally { if (fd >= 0) closeSync(fd); }
}

export function decode(core: Core, source: string): Json {
  const reply = JSON.parse(core(JSON.stringify({ op: 'decode', source })));
  if (!reply?.ok) refuse('connected.invalid_frame');
  return reply.value;
}

export function connection(core: Core, path: string): Connection {
  const raw = decode(core, readBounded(path, 65536, true));
  if (!closed(raw, ['profile', 'contractVersion', 'binding', 'origin', 'sessionId', 'cookie', 'descriptor'])) refuse('connected.invalid_connection');
  const value = raw as unknown as Connection;
  if (value.profile !== 'morphir/cli/workbench-connection' || value.contractVersion !== version || value.binding !== binding ||
      typeof value.origin !== 'string' || typeof value.sessionId !== 'string' || !value.sessionId || value.sessionId.length > 128 ||
      typeof value.cookie !== 'string' || !/^morphir_session_[A-Za-z0-9_-]{1,128}=[A-Za-z0-9_-]{43}$/.test(value.cookie)) refuse('connected.invalid_connection');
  if (hostOrigin(value.origin)?.origin !== value.origin) refuse('connected.invalid_connection');
  return value;
}

export function context(origin: string, cookie: string, timeout: number, stopped?: AbortSignal) {
  const owned = new AbortController();
  const fetchFn: Fetch = async (path, init = {}) => {
    if (!/^\/api\/(?:session|workbench\/(?:session|submit|query|cancel|release))$/.test(path)) refuse('connected.invalid_route');
    const headers = new Headers(init.headers);
    headers.set('Cookie', cookie);
    if (init.method === 'POST') headers.set('Origin', origin);
    return fetch(origin + path, { ...init, headers, redirect: 'manual',
      signal: AbortSignal.any([owned.signal, init.signal ?? AbortSignal.timeout(timeout), ...(stopped ? [stopped] : [])]) });
  };
  const manifest = async (core: Core) => {
    const response = await fetchFn('/api/session', { signal: AbortSignal.timeout(timeout) });
    if (response.status !== 200) refuse('connected.authentication_failed');
    const raw = decode(core, await boundedResponse(response));
    if (!closed(raw, ['protocolVersion', 'webSocketPath', 'sessionId', 'providers', 'initialSources'])) refuse('connected.invalid_session');
    return validateManifest(raw);
  };
  return {
    fetchFn, close: () => owned.abort(), manifest,
    async authenticate(core: Core) { return (await manifest(core)).sessionId; },
  };
}

export interface ConnectionSetup {
  source: string;
  connection: string;
  timeout: number;
}
/** Reserve private storage before consuming a one-use token. Selection runs only
 * after a fresh authenticated manifest, on this exact owned context. Cancellation
 * prevents local credential publication; once authentication starts, aborting it
 * cannot establish whether the remote host consumed the launch token. */
export async function establishConnection(config: ConnectionSetup, core: Core, interrupted: () => boolean,
  select: (manifest: Awaited<ReturnType<ReturnType<typeof context>['manifest']>>, http: ReturnType<typeof context>) => Promise<Json>,
  cancelled: () => boolean = () => false,
): Promise<{origin: string; sessionId: string}> {
  if (process.platform === 'win32' || !process.getuid) refuse('connected.private_file_permissions_unavailable');
  let launch: URL;
  try { launch = new URL(config.source.trim()); } catch { refuse('connected.invalid_launch'); }
  const origin = hostOrigin(launch.origin);
  if (!origin || launch.pathname !== '/launch' || launch.hash || launch.username || launch.password ||
      [...launch.searchParams.keys()].join(',') !== 'token' || !/^[A-Za-z0-9_-]{43}$/.test(launch.searchParams.get('token') ?? '')) refuse('connected.invalid_launch');
  let fd = -1;
  let saved = false;
  const stopped = new AbortController();
  const deadline = AbortSignal.timeout(config.timeout);
  const onInterrupt = () => stopped.abort();
  const observeStop = () => { if (interrupted() || cancelled()) stopped.abort(); };
  const checkStopped = (beforeAuthentication = false) => {
    observeStop();
    if (stopped.signal.aborted) refuse(beforeAuthentication ? 'connected.interrupted_before_authentication' : 'connected.interrupted_before_submission');
    if (deadline.aborted) refuse('connected.timeout_before_submission');
  };
  process.on('SIGINT', onInterrupt);
  const watch = setInterval(observeStop, 20);
  try {
    checkStopped(true);
    // Reserve the destination before consuming a one-use launch credential.
    fd = openSync(config.connection, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW || 0), 0o600);
    checkStopped(true);
    const response = await fetch(launch, { redirect: 'manual', signal: AbortSignal.any([deadline, stopped.signal]) });
    if (response.status !== 302 && response.status !== 303 && response.status !== 307) refuse('connected.authentication_failed');
    const cookies = response.headers.getSetCookie();
    await response.body?.cancel();
    if (cookies.length !== 1 || !/;\s*HttpOnly(?:;|$)/i.test(cookies[0]!) || !/;\s*SameSite=Strict(?:;|$)/i.test(cookies[0]!) ||
        !/;\s*Path=\/(?:;|$)/i.test(cookies[0]!) || /;\s*Domain=/i.test(cookies[0]!)) refuse('connected.invalid_authentication');
    const cookie = cookies[0]!.split(';')[0]!;
    if (!/^morphir_session_[A-Za-z0-9_-]{1,128}=[A-Za-z0-9_-]{43}$/.test(cookie)) refuse('connected.invalid_authentication');
    const http = context(origin.origin, cookie, Math.min(config.timeout, 10000), AbortSignal.any([deadline, stopped.signal]));
    try {
      const manifest = await http.manifest(core);
      const sessionId = manifest.sessionId;
      const descriptor = await select(manifest, http);
      checkStopped();
      const document: Connection = { profile: 'morphir/cli/workbench-connection', contractVersion: version, binding,
        origin: origin.origin, sessionId, cookie, descriptor };
      const encoded = JSON.stringify(document);
      if (Buffer.byteLength(encoded) > 65536) refuse('connected.connection_limit');
      writeFileSync(fd, encoded);
      fsyncSync(fd);
      saved = true;
      return {origin: origin.origin, sessionId};
    } finally { http.close(); }
  } catch (error) {
    if (error instanceof Refusal) throw error;
    if (stopped.signal.aborted) return refuse('connected.interrupted_before_submission');
    if (deadline.aborted) return refuse('connected.timeout_before_submission');
    return refuse('connected.connection_not_created');
  } finally {
    clearInterval(watch);
    process.off('SIGINT', onInterrupt);
    if (fd >= 0) {
      try {
        if (!saved) {
          try {
            const owned = fstatSync(fd), current = lstatSync(config.connection);
            if (owned.dev === current.dev && owned.ino === current.ino) unlinkSync(config.connection);
          } catch { /* The reserved carrier may already have been removed or replaced. */ }
        }
      } finally { closeSync(fd); }
    }
  }
}

/** A fresh socket belongs to one attempt. A bounded close grace terminates
 * only this socket when a serial remote dispatch cannot acknowledge Close. */
export function authenticatedWebSocket(selected: Connection): EventTarget & {readonly readyState: number; send(source: string): void; close(): void} {
  const origin = hostOrigin(selected.origin);
  if (!origin || origin.origin !== selected.origin) refuse('connected.invalid_connection');
  const socket = new WebSocket(origin.origin.replace('http:', 'ws:') + '/rpc', {
    headers: {Cookie: selected.cookie, Origin: origin.origin}, followRedirects: false,
    handshakeTimeout: 10000, maxPayload: 131072, perMessageDeflate: false,
  });
  const events = new EventTarget();
  let closing: ReturnType<typeof setTimeout> | undefined;
  socket.on('open', () => events.dispatchEvent(new Event('open')));
  socket.on('message', (data, binary) => {
    events.dispatchEvent(new MessageEvent('message', {data: binary ? data : data.toString()}));
  });
  socket.on('error', () => events.dispatchEvent(new Event('error')));
  socket.on('close', () => {
    clearTimeout(closing);
    events.dispatchEvent(new Event('close'));
  });
  const readable = Object.defineProperty(events, 'readyState', {get: () => socket.readyState}) as
    EventTarget & {readonly readyState: number};
  return Object.assign(readable, {
    send(source: string) {socket.send(source);},
    close() {
      if (closing || socket.readyState === WebSocket.CLOSED) return;
      socket.close();
      closing = setTimeout(() => socket.terminate(), 100);
      closing.unref();
    },
  });
}
