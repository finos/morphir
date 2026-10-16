// Bundled page-bound native protocol. Capability advertisement and platform
// qualification remain separate from using the accepted wire contract here.
import { JobClient } from './job-session.js';
import { NativeWorkspaceClient } from './native-workspace.js';
export const nativeBridgeVersion = '0.1.0-draft.1';
const limit = 1048576;
// Admission closes both objects. Compare every descriptor/offer field in a fixed
// order so equivalent JSON member order does not look like changed authority.
const descriptorText = value => JSON.stringify(value,
  ['profile', 'contractVersion', 'sessionId', 'operations', 'offer', 'hostId', 'providerId']);
const bytes = source => new TextEncoder().encode(source).byteLength;

export class NativeSession {
  constructor(invoke, timeout = 10000, core = command => globalThis.morphirWorkbenchJobs(command)) {
    this.invoke = invoke; this.timeout = timeout; this.core = core;
    this.id = null; this.disposed = false; this.operations = [];
  }
  encode(operation, payload) {
    const frame = { profile: 'morphir/workbench/native', contractVersion: nativeBridgeVersion, operation };
    if (operation !== 'session.open') frame.sessionId = this.id;
    if (payload !== undefined) frame.payload = payload;
    const source = JSON.stringify(frame);
    if (source.length > limit || bytes(source) > limit) throw new Error('The complete native request exceeds its frame limit.');
    return source;
  }
  admit(source, operation, sessionId) {
    if (typeof source !== 'string' || source.length > limit || bytes(source) > limit) throw new Error('The native host returned an invalid raw reply.');
    const decoded = JSON.parse(this.core(JSON.stringify({ op: 'native-response', source, operation, sessionId })));
    if (!decoded.ok) throw new Error(`The native reply is incompatible (${decoded.code || 'invalid'}).`);
    return decoded.value;
  }
  async exchange(source, operation, sessionId, interactive = false) {
    if (this.disposed) throw new Error('The desktop session is closed.');
    let timer;
    try {
      const invocation = Promise.resolve().then(() => this.invoke('app:workbench_native', source));
      // Interactive OS picker latency is outside the worker/request deadline.
      const raw = await (interactive ? invocation : Promise.race([invocation,
        new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('The native request timed out. Its effect may be unknown.')), this.timeout); }),
      ]));
      if (this.disposed) throw new Error('The desktop session is closed.');
      return { source: raw, envelope: this.admit(raw, operation, sessionId) };
    } finally { clearTimeout(timer); }
  }
  value(envelope) {
    if (!envelope.ok) throw Object.assign(new Error(envelope.error.message), {
      native: true, code: envelope.error.code, effect: envelope.error.effect,
    });
    return envelope.value;
  }
  async open() {
    const { envelope } = await this.exchange(this.encode('session.open'), 'session.open', null);
    const descriptor = this.value(envelope);
    this.id = descriptor.sessionId; this.operations = descriptor.operations;
    this.descriptor = descriptorText(descriptor);
  }
  async check() {
    if (!this.id) throw new Error('The desktop session has not been opened.');
    const { envelope } = await this.exchange(this.encode('session.check'), 'session.check', this.id);
    const descriptor = this.value(envelope);
    if (descriptorText(descriptor) !== this.descriptor) throw new Error('The desktop session capabilities or authority changed. Reopen the application page.');
    return descriptor;
  }
  async request(operation, payload, interactive = false) {
    await this.check();
    const result = await this.exchange(this.encode(operation, payload), operation, this.id, interactive);
    await this.check();
    return this.value(result.envelope);
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    if (this.id) {
      // Navigation may already have revoked this page. Never retry its close.
      try { Promise.resolve(this.invoke('app:workbench_native', this.encode('session.close'))).catch(() => {}); } catch { /* Bridge already gone. */ }
    }
  }
}

export class NativeJobTransport {
  constructor(session) { this.session = session; }
  async nativeDescriptor() { return JSON.stringify(await this.session.check()); }
  async nativeRequest(source) {
    // This is the complete locally generated request from JobClient. Preserve it
    // exactly; only inspect operation/session for this originating invocation.
    const request = JSON.parse(source);
    if (!['job.submit', 'job.query', 'job.cancel', 'job.release'].includes(request.operation) || request.sessionId !== this.session.id) {
      throw new Error('Invalid native job operation or session.');
    }
    await this.session.check();
    const result = await this.session.exchange(source, request.operation, this.session.id);
    await this.session.check();
    // JobClient independently admits this same complete raw reply and handles
    // native error effects. Transport failures cannot manufacture no-effect.
    return result.source;
  }
}

export class NativeAdapter {
  constructor(local, invoke, timeout, jobOptions = {}) {
    this.local = local;
    this.session = new NativeSession(invoke, timeout, jobOptions.core);
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
    if (this.session.operations.includes('jobs')) {
      this.jobs = new JobClient(this.session.id, { ...this.jobOptions, transport: new NativeJobTransport(this.session),
        authenticate: async () => { await this.session.check(); return this.session.id; } });
      this.jobsAvailable = await this.jobs.initialize();
      if (!this.jobsAvailable) throw new Error("The native host advertised jobs without a compatible offer.");
      this.current(epoch);
    }
    if (this.session.operations.includes('workspace')) this.workspace = new NativeWorkspaceClient(this.session, this.local);
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
