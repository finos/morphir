import { HttpJobTransport, jobFrameLimit as limit } from './job-transport.js';
// The compiled MoonBit cursor owns every receipt decision across transports.
const version = '0.1.0-draft.1';
const bytes = text => new TextEncoder().encode(text).byteLength;
const exact = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...keys].sort().join(',');

export class JobClient {
  constructor(sessionId, { fetchFn = fetch, core = command => globalThis.morphirWorkbenchJobs(command),
    pause = () => new Promise(resolve => setTimeout(resolve, 150)), authenticate, timeout = 10000, transport } = {}) {
    this.sessionId = sessionId;
    this.transport = transport ?? new HttpJobTransport({ fetchFn, timeout });
    this.core = core;
    this.pause = pause;
    this.authenticate = authenticate;
    this.offer = null;
    this.job = null;
    this.result = null;
    this.polling = false;
    this.releasePending = false;
    this.releaseReauthenticated = false;
    this.uncertainSubmission = false;
    this.active = false;
    this.cancelOnSubmit = false;
    this.generation = 0;
    this.progress = () => {};
  }
  command(command) {
    const reply = JSON.parse(this.core(JSON.stringify(command)));
    if (!reply.ok) throw new Error(`Host job evidence was rejected (${reply.code || 'invalid'}).`);
    if (reply.job) { this.job = reply.job; this.result = reply.result; }
    return reply;
  }
  async request(path, body, optional = false) {
    const source = body === undefined ? undefined : JSON.stringify(body);
    if (source !== undefined && bytes(source) > limit) throw new Error('Host job request exceeds the 1-MiB limit.');
    const response = await this.transport.request(path, source, optional);
    if (optional && response.status === 404) return null;
    const text = response.source;
    if (typeof text !== 'string') throw new Error('The host returned an invalid job frame.');
    if (bytes(text) > limit) throw new Error('Host job response exceeds the 1-MiB limit.');
    const value = this.command({ op: 'decode', source: text }).value;
    if (!response.ok) {
      const validError = exact(value, ['error']) && exact(value.error, ['code', 'message']) &&
        typeof value.error.code === 'string' && value.error.code.length > 0 && bytes(value.error.code) <= 128 &&
        typeof value.error.message === 'string' && value.error.message.length > 0 && bytes(value.error.message) <= 512;
      const error = new Error(validError ? value.error.message : 'The host returned an invalid job error envelope.');
      // Only a closed 4xx rejection proves that another explicit submit is safe.
      error.status = response.status;
      if (validError) error.code = value.error.code;
      error.rejected = validError && response.status >= 400 && response.status < 500;
      throw error;
    }
    return value;
  }
  async descriptor(optional = false) {
    const value = await this.request('session', undefined, optional);
    if (value === null) return null;
    if (!exact(value, ['profile', 'contractVersion', 'offer']) || value.profile !== 'morphir/workbench/host' || value.contractVersion !== version) {
      throw new Error('The host job profile is incompatible.');
    }
    return this.command({ op: 'offer', value, sessionId: this.sessionId }).value;
  }
  async initialize() { this.offer = await this.descriptor(true); return this.offer !== null; }
  emit() { this.progress(this.job); }
  disconnected(error) {
    this.suspended = true;
    this.lastError = error;
    if (this.job) { this.command({ op: 'disconnect' }); this.emit(); }
    return Object.assign(error, { job: this.job, jobTransport: true });
  }
  async execute(request, progress = () => {}) {
    if (!this.offer) throw new Error('This host does not offer job evaluation.');
    if (this.uncertainSubmission) throw new Error('Submission status is unknown. No second job was submitted. Reopen the host session to recover.');
    if (this.job && this.job.state !== 'terminal') throw new Error('A host job is already active. Resume it instead of submitting again.');
    if (this.releasePending) {
      try { await this.release(); } catch (error) { throw this.disconnected(error); }
    }
    this.progress = progress;
    const body = { contractVersion: version, model: request.source, entry: request.entry,
      inputs: { format: typeof request.argumentsIon === 'string' ? 'ion-text' : 'json',
        source: typeof request.argumentsIon === 'string' ? request.argumentsIon : JSON.stringify(request.arguments) } };
    // Check bounds before sending: an oversized request has no uncertain host effect.
    if (bytes(JSON.stringify(body)) > limit) throw new Error('Host job request exceeds the 1-MiB limit.');
    ++this.generation;
    this.active = true;
    this.cancelOnSubmit = false;
    let submitted;
    try { submitted = await this.request('submit', body); }
    catch (error) {
      this.active = false;
      if (!error.rejected) { this.uncertainSubmission = true; error.submissionUnknown = true; error.jobTransport = true; }
      throw error;
    }
    try {
      if (!exact(submitted, ['identity', 'calls', 'receipt']) || !Array.isArray(submitted.calls) || submitted.calls.length !== 1 || submitted.calls[0] !== 'workbench') throw new Error('Invalid host submission envelope.');
      this.command({ op: 'start', offer: this.offer.offer, identity: submitted.identity, calls: ['workbench'], receipt: submitted.receipt });
    } catch (error) {
      this.active = false; this.uncertainSubmission = true;
      throw Object.assign(error, { submissionUnknown: true, jobTransport: true });
    }
    this.suspended = false;
    this.emit();
    try {
      if (this.cancelOnSubmit) await this.cancel();
      return await this.poll();
    } finally { this.active = false; }
  }
  async poll() {
    if (this.polling) throw new Error('This host job is already being observed.');
    this.polling = true;
    try {
      while (this.job.state !== 'terminal') {
        await this.pause();
        if (this.suspended) throw this.lastError;
        if (this.job.state === 'terminal') break;
        const receipt = await this.request('query', { contractVersion: version, identity: this.job.identity });
        if (this.suspended) throw this.lastError;
        this.command({ op: 'observe', receipt });
        this.emit();
      }
      const result = this.result;
      this.releasePending = true;
      try { await this.release(); } catch (error) { this.disconnected(error); }
      return { ...result, job: this.job };
    } catch (error) { throw this.disconnected(error); }
    finally { this.polling = false; }
  }
  async cancel() {
    if (this.active && (!this.job || this.job.state === 'terminal')) { this.cancelOnSubmit = true; return; }
    if (!this.job || this.job.state === 'terminal' || this.job.cancelAction !== 'send') return;
    const generation = this.generation;
    const identity = this.job.identity;
    if (this.cancelling?.generation === generation) return this.cancelling.promise;
    const cancellation = { generation };
    cancellation.promise = (async () => {
      try {
        const receipt = await this.request('cancel', { contractVersion: version, identity });
        if (generation !== this.generation) return;
        this.command({ op: 'observe', receipt });
        this.emit();
      } catch (error) {
        if (generation !== this.generation) return;
        throw this.disconnected(error);
      }
    })();
    this.cancelling = cancellation;
    try { return await cancellation.promise; }
    finally { if (this.cancelling === cancellation) this.cancelling = null; }
  }
  async resume(progress = () => {}) {
    if (!this.job) throw new Error('There is no retained job to resume.');
    if (this.polling) throw new Error('This host job is already being observed.');
    this.progress = progress;
    try {
      const sessionId = await this.authenticate?.();
      if (sessionId !== undefined && sessionId !== this.sessionId) throw new Error('The authenticated host session changed. The retained job cannot be resumed.');
      const descriptor = await this.descriptor();
      this.command({ op: 'reconnect', offer: descriptor.offer });
      this.releaseReauthenticated = sessionId === this.sessionId && this.job.state === 'terminal';
      this.suspended = false;
      this.emit();
      if (this.job.state === 'terminal') {
        if (this.releasePending) await this.release();
        return { ...this.result, job: this.job };
      }
    } catch (error) { throw this.disconnected(error); }
    return this.poll();
  }
  async release() {
    try {
      const value = await this.request('release', { contractVersion: version, identity: this.job.identity });
      if (!exact(value, ['released']) || value.released !== true) throw new Error('The host did not confirm job release.');
      this.releasePending = false;
    } catch (error) {
      // A successful release reply can be lost. Fresh authentication and exact
      // offer admission make absence of this already-terminal identity safe.
      if (this.releaseReauthenticated && this.job.state === 'terminal' &&
          error.status === 404 && error.code === 'workbench.host_unknown_job') {
        this.releasePending = false;
        return;
      }
      throw error;
    } finally { this.releaseReauthenticated = false; }
  }
}
