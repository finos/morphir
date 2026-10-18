import type { Core, CoreReply, Execution, ExecutionDescriptor, ExecutionOptions, ExecutionTransport, Json, NativeReply, Progress, WorkRequest, WorkResult } from './contracts.ts';
import { workbenchError } from '../../../types/data.ts';
import type { WorkbenchError } from '../../../types/data.ts';
import { HttpExecutionTransport, executionFrameLimit as limit } from './execution-transport.ts';
// The compiled MoonBit cursor owns every receipt decision across transports.
const version = '0.2.0-draft.1';
const bytes = (text: string) => new TextEncoder().encode(text).byteLength;
const exact = (value: unknown, keys: string[]) => !!value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...keys].sort().join(',');

type ExecutionChannel =
  | { kind: 'native'; descriptor: () => Promise<string>; request: (source: string) => Promise<string> }
  | { kind: 'http'; request: NonNullable<ExecutionTransport['request']> };

export class ExecutionClient {
  sessionId: string;
  private channel: ExecutionChannel;
  core: Core;
  pause: () => Promise<void>;
  authenticate?: () => Promise<string>;
  offer: ExecutionDescriptor | null;
  execution: Execution | null;
  result: WorkResult | null;
  polling: boolean;
  releasePending: boolean;
  releaseReauthenticated: boolean;
  uncertainSubmission: boolean;
  active: boolean;
  cancelOnSubmit: boolean;
  generation: number;
  progress: Progress;
  suspended = false;
  lastError?: WorkbenchError;
  cancelling: { generation: number; promise: Promise<void> } | null = null;
  constructor(sessionId: string, { fetchFn = fetch, core = command => globalThis.morphirWorkbenchExecutions(command),
    pause = () => new Promise(resolve => setTimeout(resolve, 150)), authenticate, timeout = 10000, transport }: ExecutionOptions = {}) {
    this.sessionId = sessionId;
    const selected: ExecutionTransport = transport ?? new HttpExecutionTransport({ fetchFn, timeout });
    if (typeof selected.nativeRequest === 'function' && typeof selected.nativeDescriptor === 'function') {
      this.channel = { kind: 'native', descriptor: () => selected.nativeDescriptor!(), request: source => selected.nativeRequest!(source) };
    } else if (selected.nativeRequest || selected.nativeDescriptor || typeof selected.request !== 'function') {
      throw new Error('Execution transports require either paired native operations or an HTTP request operation.');
    } else {
      this.channel = { kind: 'http', request: (...args) => selected.request!(...args) };
    }
    this.core = core;
    this.pause = pause;
    this.authenticate = authenticate;
    this.offer = null;
    this.execution = null;
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
  command<T = Json>(command: unknown): CoreReply<T> {
    const reply: CoreReply<T> = JSON.parse(this.core(JSON.stringify(command)));
    if (!reply.ok) throw new Error(`Host execution evidence was rejected (${reply.code || 'invalid'}).`);
    if (reply.execution) { this.execution = reply.execution; this.result = reply.result ?? null; }
    return reply;
  }
  encodeRequest(path: string, body?: unknown) {
    let value = body;
    if (this.channel.kind === 'native') {
      if (!['submit', 'query', 'cancel', 'release'].includes(path)) throw new Error('Unknown native execution operation.');
      value = { profile: 'morphir/workbench/native', contractVersion: version,
        operation: `execution.${path}`, sessionId: this.sessionId, payload: body };
    }
    const source = value === undefined ? undefined : JSON.stringify(value);
    if (source !== undefined && (source.length > limit || bytes(source) > limit)) {
      throw new Error('Host execution request exceeds the complete 1-MiB frame limit.');
    }
    return source;
  }
  async request<T = Json>(path: string, body?: unknown, optional = false): Promise<T | null> {
    const source = this.encodeRequest(path, body);
    if (this.channel.kind === 'native') {
      let text;
      try { text = await this.channel.request(source!); }
      catch (cause) {
        // Framework/transport exceptions are not validated native error replies.
        throw new Error('The native execution reply was lost or unavailable. Its effect is unknown.', { cause });
      }
      if (typeof text !== 'string') throw new Error('The native host returned an invalid raw execution reply.');
      if (text.length > limit || bytes(text) > limit) throw new Error('Native execution response exceeds the 1-MiB frame limit.');
      const reply = this.command<NativeReply<T>>({ op: 'native-response', source: text,
        operation: `execution.${path}`, sessionId: this.sessionId }).value;
      if (!reply.ok) {
        throw Object.assign(new Error(reply.error.message), { native: true, code: reply.error.code,
          effect: reply.error.effect, rejected: reply.error.effect === 'none' });
      }
      return reply.value;
    }
    const response = await this.channel.request(path, source, optional);
    if (optional && response.status === 404) return null;
    const text = response.source;
    if (typeof text !== 'string') throw new Error('The host returned an invalid execution frame.');
    if (bytes(text) > limit) throw new Error('Host execution response exceeds the 1-MiB limit.');
    const value = this.command<T & { error: { code: string; message: string } }>({ op: 'decode', source: text }).value;
    if (!response.ok) {
      const validError = exact(value, ['error']) && exact(value.error, ['code', 'message']) &&
        typeof value.error.code === 'string' && value.error.code.length > 0 && bytes(value.error.code) <= 128 &&
        typeof value.error.message === 'string' && value.error.message.length > 0 && bytes(value.error.message) <= 512;
      const error: WorkbenchError = new Error(validError ? value.error.message : 'The host returned an invalid execution error envelope.');
      // Only a closed 4xx rejection proves that another explicit submit is safe.
      error.status = response.status;
      if (validError) error.code = value.error.code;
      error.rejected = validError && response.status >= 400 && response.status < 500;
      throw error;
    }
    return value;
  }
  async descriptor(optional = false): Promise<ExecutionDescriptor | null> {
    if (this.channel.kind === 'native') {
      // The binding checks its page/session and admits raw replies before any projection.
      // Explicit transport selection keeps HTTP authentication validation separate.
      const source = await this.channel.descriptor();
      if (typeof source !== 'string') throw new Error('The native descriptor must be raw JSON text.');
      if (source.length > limit || bytes(source) > limit) throw new Error('Native descriptor exceeds the 1-MiB limit.');
      const value = this.command<ExecutionDescriptor>({ op: 'native-descriptor', source, sessionId: this.sessionId }).value;
      return Object.hasOwn(value, 'offer') ? value : null;
    }
    const value = await this.request<ExecutionDescriptor>('session', undefined, optional);
    if (value === null) return null;
    if (!exact(value, ['profile', 'contractVersion', 'offer']) || value.profile !== 'morphir/workbench/host' || value.contractVersion !== version) {
      throw new Error('The host execution profile is incompatible.');
    }
    return this.command<ExecutionDescriptor>({ op: 'offer', value, sessionId: this.sessionId }).value;
  }
  async initialize() { this.offer = await this.descriptor(true); return this.offer !== null; }
  emit() { this.progress(this.execution); }
  disconnected(cause: unknown) {
    const error = workbenchError(cause);
    this.suspended = true;
    this.lastError = error;
    if (this.execution) { this.command({ op: 'disconnect' }); this.emit(); }
    return Object.assign(error, { execution: this.execution, executionTransport: true });
  }
  async execute(request: Pick<WorkRequest, 'source' | 'entry' | 'arguments' | 'argumentsIon' | 'executionMode' | 'admission'>, progress: Progress = () => {}): Promise<WorkResult> {
    if (request.executionMode === 'capability' || request.admission != null) {
      throw new Error('This host mapping does not offer checking-policy selection.');
    }
    if (!this.offer) throw new Error('This host does not offer execution evaluation.');
    if (this.active || this.polling) throw new Error('A host execution is already active. Resume it instead of submitting again.');
    if (this.uncertainSubmission) throw new Error('Submission status is unknown. No second execution was submitted. Reopen the host session to recover.');
    if (this.execution && this.execution.state !== 'terminal') throw new Error('A host execution is already active. Resume it instead of submitting again.');
    if (this.releasePending) {
      try { await this.release(); } catch (cause) { const error = workbenchError(cause); throw this.disconnected(error); }
    }
    this.progress = progress;
    const body = { contractVersion: version, model: request.source, entry: request.entry,
      inputs: { format: typeof request.argumentsIon === 'string' ? 'ion-text' : 'json',
        source: typeof request.argumentsIon === 'string' ? request.argumentsIon : JSON.stringify(request.arguments) } };
    // Check bounds before sending: an oversized request has no uncertain host effect.
    this.encodeRequest('submit', body);
    ++this.generation;
    this.active = true;
    this.cancelOnSubmit = false;
    let submitted: { identity: Json; calls: string[]; receipt: Json } | null;
    try { submitted = await this.request<{ identity: Json; calls: string[]; receipt: Json }>('submit', body); }
    catch (cause) { const error = workbenchError(cause);
      this.active = false;
      if (!error.rejected) { this.uncertainSubmission = true; error.submissionUnknown = true; error.executionTransport = true; }
      throw error;
    }
    try {
      if (!submitted || !exact(submitted, ['identity', 'calls', 'receipt']) || !Array.isArray(submitted.calls) || submitted.calls.length !== 1 || submitted.calls[0] !== 'workbench') throw new Error('Invalid host submission envelope.');
      this.command({ op: 'start', offer: this.offer.offer, identity: submitted.identity, calls: ['workbench'], receipt: submitted.receipt });
    } catch (cause) { const error = workbenchError(cause);
      this.active = false; this.uncertainSubmission = true;
      throw Object.assign(error, { submissionUnknown: true, executionTransport: true });
    }
    this.suspended = false;
    this.emit();
    try {
      if (this.cancelOnSubmit) await this.cancel();
      return await this.poll();
    } finally { this.active = false; }
  }
  private isTerminal() { return this.execution?.state === 'terminal'; }
  async poll(): Promise<WorkResult> {
    if (!this.execution) throw new Error('There is no retained execution to observe.');
    if (this.polling) throw new Error('This host execution is already being observed.');
    this.polling = true;
    try {
      while (!this.isTerminal()) {
        await this.pause();
        if (this.suspended) throw this.lastError;
        if (this.isTerminal()) break;
        const receipt = await this.request('query', { contractVersion: version, identity: this.execution.identity });
        if (this.suspended) throw this.lastError;
        this.command({ op: 'observe', receipt });
        this.emit();
      }
      const result = this.result;
      this.releasePending = true;
      try { await this.release(); } catch (cause) { const error = workbenchError(cause); this.disconnected(error); }
      return { success: false, ...result, execution: this.execution };
    } catch (cause) { const error = workbenchError(cause); throw this.disconnected(error); }
    finally { this.polling = false; }
  }
  async cancel() {
    if (this.active && (!this.execution || this.execution.state === 'terminal')) { this.cancelOnSubmit = true; return; }
    if (!this.execution || this.execution.state === 'terminal' || this.execution.cancelAction !== 'send') return;
    const generation = this.generation;
    const identity = this.execution.identity;
    if (this.cancelling?.generation === generation) return this.cancelling.promise;
    const cancellation = { generation, promise: Promise.resolve() };
    cancellation.promise = (async () => {
      try {
        const receipt = await this.request('cancel', { contractVersion: version, identity });
        if (generation !== this.generation) return;
        this.command({ op: 'observe', receipt });
        this.emit();
      } catch (cause) { const error = workbenchError(cause);
        if (generation !== this.generation) return;
        throw this.disconnected(error);
      }
    })();
    this.cancelling = cancellation;
    try { return await cancellation.promise; }
    finally { if (this.cancelling === cancellation) this.cancelling = null; }
  }
  async resume(progress: Progress = () => {}): Promise<WorkResult> {
    if (!this.execution) throw new Error('There is no retained execution to resume.');
    if (this.polling) throw new Error('This host execution is already being observed.');
    this.progress = progress;
    try {
      const sessionId = await this.authenticate?.();
      if (sessionId !== undefined && sessionId !== this.sessionId) throw new Error('The authenticated host session changed. The retained execution cannot be resumed.');
      const descriptor = await this.descriptor();
      if (descriptor === null) throw new Error('This session no longer offers execution evaluation.');
      if (this.offer?.profile === 'morphir/workbench/native' &&
          (descriptor.profile !== this.offer.profile || descriptor.operations.join(',') !== this.offer.operations.join(','))) {
        throw new Error('The native session capabilities changed. Reopen the application page.');
      }
      this.command({ op: 'reconnect', offer: descriptor.offer });
      this.releaseReauthenticated = sessionId === this.sessionId && this.execution.state === 'terminal';
      this.suspended = false;
      this.emit();
      if (this.execution.state === 'terminal') {
        if (this.releasePending) await this.release();
        return { success: false, ...this.result, execution: this.execution };
      }
    } catch (cause) { const error = workbenchError(cause); throw this.disconnected(error); }
    return this.poll();
  }
  async release() {
    if (!this.execution) throw new Error('There is no retained execution to release.');
    try {
      const value = await this.request<{ released: boolean }>('release', { contractVersion: version, identity: this.execution.identity });
      if (!value || !exact(value, ['released']) || value.released !== true) throw new Error('The host did not confirm execution release.');
      this.releasePending = false;
    } catch (cause) { const error = workbenchError(cause);
      // A successful release reply can be lost. Fresh authentication and exact
      // offer validation make absence of this already-terminal identity safe.
      if (this.releaseReauthenticated && this.execution.state === 'terminal' &&
          ((error.status === 404 && error.code === 'workbench.host_unknown_execution') ||
           (error.native === true && error.code === 'not_found' && error.effect === 'none'))) {
        this.releasePending = false;
        return;
      }
      throw error;
    } finally { this.releaseReauthenticated = false; }
  }
}
