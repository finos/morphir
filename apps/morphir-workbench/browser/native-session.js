// Private Proton bootstrap, not an advertised Morphir native execution profile.
import { JobClient } from './job-session.js';
import { NativeWorkspaceClient } from './native-workspace.js';
export const nativeBridgeVersion = '0.1.0-draft.1';
const keys = value => value && typeof value === 'object' && !Array.isArray(value) ? Object.keys(value).sort().join(',') : '';

export class NativeSession {
  constructor(invoke, timeout = 10000) {
    this.invoke = invoke;
    this.timeout = timeout;
    this.id = null;
    this.disposed = false;
  }
  async call(operation, payload) {
    if (this.disposed) throw new Error('The desktop session is closed.');
    let timer;
    try {
      const reply = await Promise.race([
        Promise.resolve().then(() => this.invoke(`app:workbench_session_${operation}`, payload)),
        new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('The desktop session request timed out.')), this.timeout); }),
      ]);
      if (this.disposed) throw new Error('The desktop session is closed.');
      if (keys(reply) === 'code,ok' && reply.ok === false && typeof reply.code === 'string' && /^[a-zA-Z0-9_.-]{1,128}$/.test(reply.code)) {
        throw new Error(`The desktop session was rejected (${reply.code}).`);
      }
      if (keys(reply) !== 'bridgeVersion,ok,operations,sessionId' || reply.ok !== true ||
          reply.bridgeVersion !== nativeBridgeVersion || typeof reply.sessionId !== 'string' ||
          !/^[a-zA-Z0-9_.-]{1,128}$/.test(reply.sessionId) || !Array.isArray(reply.operations) ||
          reply.operations.length > 2 || reply.operations.some(operation => !['jobs', 'workspace'].includes(operation)) ||
          new Set(reply.operations).size !== reply.operations.length || reply.operations.join(',') !== [...reply.operations].sort().join(',')) {
        throw new Error('The desktop session reply is incompatible.');
      }
      return reply;
    } finally { clearTimeout(timer); }
  }
  async open() {
    const reply = await this.call('open', nativeBridgeVersion);
    this.id = reply.sessionId;
    this.operations = reply.operations.join(',');
  }
  async check() {
    if (!this.id) throw new Error('The desktop session has not been opened.');
    const reply = await this.call('check', this.id);
    if (reply.sessionId !== this.id) throw new Error('The desktop session changed. Reopen the application page.');
    if (reply.operations.join(',') !== this.operations) throw new Error('The desktop session capabilities changed. Reopen the application page.');
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    if (this.id) {
      // Navigation may already have revoked this page. Never retry its close.
      try { Promise.resolve(this.invoke('app:workbench_session_close', this.id)).catch(() => {}); } catch { /* Bridge already gone. */ }
    }
  }
}

export class NativeJobTransport {
  constructor(session) { this.session = session; }
  async request(path, body) {
    await this.session.check();
    let timer;
    try {
      const reply = await Promise.race([
        Promise.resolve().then(() => this.session.invoke('app:workbench_job', JSON.stringify({ sessionId: this.session.id, path, body: body ?? null }))),
        new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('The native job request timed out. Its effect may be unknown.')), this.session.timeout); }),
      ]);
      await this.session.check();
      if (keys(reply) !== 'source,status' || !Number.isInteger(reply.status) || reply.status < 100 || reply.status > 599 ||
          typeof reply.source !== 'string' || new TextEncoder().encode(reply.source).byteLength > 1048576) throw new Error('The native host returned an invalid job frame.');
      return { ok: reply.status >= 200 && reply.status < 300, status: reply.status, source: reply.source };
    } finally { clearTimeout(timer); }
  }
}

export class NativeAdapter {
  constructor(local, invoke, timeout, jobOptions = {}) {
    this.local = local;
    this.session = new NativeSession(invoke, timeout);
    this.runtimeLabel = 'Desktop local';
    this.epoch = 0;
    this.disposed = false;
    this.jobOptions = jobOptions;
  }
  current(epoch) {
    if (this.disposed || epoch !== this.epoch) throw new Error('Discarded. The desktop request is no longer current.');
  }
  async initialize() {
    const epoch = ++this.epoch;
    await this.session.open();
    this.current(epoch);
    const result = await this.local.initialize();
    this.current(epoch);
    await this.session.check();
    this.current(epoch);
    if (this.session.operations.split(',').includes('jobs')) {
      this.jobs = new JobClient(this.session.id, { ...this.jobOptions, transport: new NativeJobTransport(this.session),
        authenticate: async () => { await this.session.check(); return this.session.id; } });
      this.jobsAvailable = await this.jobs.initialize();
      if (!this.jobsAvailable) throw new Error("The native host advertised jobs without a compatible offer.");
      this.current(epoch);
    }
    if (this.session.operations.split(',').includes('workspace')) this.workspace = new NativeWorkspaceClient(this.session, this.local);
    return { ...result, nativeSession: true, workspaceAvailable: !!this.workspace, jobsAvailable: !!this.jobsAvailable, message: 'Desktop local · ready to compile' };
  }
  async execute(request, progress) {
    const epoch = ++this.epoch;
    await this.session.check();
    this.current(epoch);
    if (request.operation === 'resume-job' && this.jobsAvailable) return this.jobs.resume(progress);
    if (request.operation === 'evaluate' && request.executionMode === 'typed' && this.jobsAvailable) return this.jobs.execute(request, progress);
    if (request.operation === 'workspace' && this.workspace) {
      const result = await this.workspace.choose(); this.current(epoch); return result;
    }
    if (request.operation === 'project' && this.workspace) {
      const result = await this.workspace.openProject(request.project); this.current(epoch); return result;
    }
    if (request.operation === 'project' || request.operation === 'workspace' || request.operation === 'resume-job') throw new Error('This desktop session does not offer native jobs or workspace access.');
    const result = await this.local.execute(request);
    this.current(epoch);
    await this.session.check();
    this.current(epoch);
    return result;
  }
  cancel() {
    if (this.jobs?.active || (this.jobs?.job && this.jobs.job.state !== 'terminal')) return this.jobs.cancel();
    ++this.epoch; this.local.cancel(); return this.workspace?.cancel();
  }
  dispose() { this.disposed = true; ++this.epoch; this.workspace?.dispose(); this.local.cancel(); this.session.dispose(); }
}

export function selectLocalAdapter(location, local, bridge = globalThis.__MoonBit__) {
  const url = new URL(location.href);
  const mode = url.searchParams.get('mode');
  if (mode && mode !== 'native') return local;
  const bundled = (url.protocol === 'https:' && url.host === 'proton.localhost') ||
    (url.protocol === 'proton:' && url.host === 'app');
  if (!bundled) return local;
  return new NativeAdapter(local, (name, payload) => {
    if (typeof bridge?.core?.invokeOp !== 'function') throw new Error('The desktop command bridge is unavailable.');
    return bridge.core.invokeOp(name, payload);
  });
}
