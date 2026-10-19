import type { Core, CoreReply, Execution, ExecutionDescriptor, ExecutionOptions, ExecutionTransport, Json, NativeMapping, NativeReply, Progress, WorkRequest, WorkResult } from './contracts.mts';
import { workbenchError } from '../../../types/data.ts';
import type { WorkbenchError } from '../../../types/data.ts';
import { HttpExecutionTransport, executionFrameLimit as limit } from './transport.mts';
// The compiled MoonBit cursor owns every receipt decision across transports.
const version = '0.2.0-draft.1';
const nativePolicyVersion = '0.2.0-draft.2';
const bytes = (text: string) => new TextEncoder().encode(text).byteLength;
const exact = (value: unknown, keys: string[]) => !!value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...keys].sort().join(',');

type ExecutionChannel =
  | { kind: 'native'; descriptor: () => Promise<string>; request: (source: string) => Promise<string> }
  | { kind: 'http'; request: NonNullable<ExecutionTransport['request']> };

export class ExecutionClient {
  readonly nativeMapping: NativeMapping;
  acceptedPlan: Json | null = null;
  private readonly onAcceptedPlan?: (plan: Json) => void;
  sessionId: string;
  private channel: ExecutionChannel;
  core: Core;
  pause: () => Promise<void>;
  authenticate?: () => Promise<string>;
  offer: ExecutionDescriptor | null;
  private negotiatedDescriptor: ExecutionDescriptor | null = null;
  private initialization: Promise<boolean> | null = null;
  private reconciliation: 'idle' | 'pending' = 'idle';
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
  constructor(sessionId: string, { fetchFn = fetch, core = () => { throw new Error("An explicit execution validation core is required."); },
    pause = () => new Promise(resolve => setTimeout(resolve, 150)), authenticate, timeout = 10000, transport, nativeMapping = 'executions', onAcceptedPlan }: ExecutionOptions = {}) {
    this.sessionId = sessionId;
    this.nativeMapping = nativeMapping;
    this.onAcceptedPlan = onAcceptedPlan;
    const selected: ExecutionTransport = transport ?? new HttpExecutionTransport({ fetchFn, timeout });
    if (typeof selected.nativeRequest === 'function' && typeof selected.nativeDescriptor === 'function') {
      this.channel = { kind: 'native', descriptor: () => selected.nativeDescriptor!(), request: source => selected.nativeRequest!(source) };
    } else if (selected.nativeRequest || selected.nativeDescriptor || typeof selected.request !== 'function') {
      throw new Error('Execution transports require either paired native operations or an HTTP request operation.');
    } else {
      if (nativeMapping !== 'executions') throw new Error('Capability checking policies require the qualified native mapping.');
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
    if (!reply.ok) throw new Error(reply.code === 'workbench.host_session_capacity'
      ? 'This desktop session has reached its execution limit. Reopen the application page.'
      : `Host execution evidence was rejected (${reply.code || 'invalid'}).`);
    if (reply.execution) {
      const wasTerminal = this.execution?.state === 'terminal';
      this.execution = reply.execution; this.result = reply.result ?? null;
      // Cancellation can deliver terminal evidence while an older query reply
      // is still in flight. Release remains pending even if that query is lost.
      if (!wasTerminal && this.execution.state === 'terminal') this.releasePending = true;
    }
    return reply;
  }
  encodeRequest(path: string, body?: unknown) {
    let value = body;
    if (this.channel.kind === 'native') {
      if (!['submit', 'query', 'cancel', 'release'].includes(path)) throw new Error('Unknown native execution operation.');
      value = { profile: 'morphir/workbench/native', contractVersion: this.nativeMapping === 'capability-checks' ? nativePolicyVersion : version,
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
      const reply = this.command<NativeReply<T>>({ op: this.nativeMapping === 'capability-checks' ? 'native-policy-response' : 'native-response', source: text,
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
      const value = this.command<ExecutionDescriptor>({ op: this.nativeMapping === 'capability-checks' ? 'native-policy-descriptor' : 'native-descriptor', source, sessionId: this.sessionId }).value;
      return Object.hasOwn(value, 'offer') ? value : null;
    }
    const value = await this.request<ExecutionDescriptor>('session', undefined, optional);
    if (value === null) return null;
    if (value.contractVersion === nativePolicyVersion) {
      return this.command<ExecutionDescriptor>({ op: 'host-policy-descriptor', source: JSON.stringify(value), sessionId: this.sessionId }).value;
    }
    if (!exact(value, ['profile', 'contractVersion', 'offer']) || value.profile !== 'morphir/workbench/host' || value.contractVersion !== version) {
      throw new Error('The host execution profile is incompatible.');
    }
    return this.command<ExecutionDescriptor>({ op: 'offer', value, sessionId: this.sessionId }).value;
  }
  initialize(): Promise<boolean> {
    // A page negotiates once. Concurrent callers share that exact handshake;
    // a delayed reinitialization cannot replace an accepted session's scope.
    if (this.initialization) return this.initialization;
    if (this.active || this.execution) return Promise.reject(new Error('An accepted host session cannot be initialized again.'));
    this.initialization = this.descriptor(true).then(descriptor => {
      this.negotiatedDescriptor = structuredClone(descriptor);
      this.offer = structuredClone(descriptor);
      return descriptor !== null;
    }).catch(cause => { this.initialization = null; throw cause; });
    return this.initialization;
  }
  get capabilityEvaluator(): 'scheme-portable-v1/shared-sdk/bounded' | undefined {
    return this.negotiatedDescriptor?.contractVersion === nativePolicyVersion &&
      this.negotiatedDescriptor.capabilityChecks?.evaluator === 'scheme-portable-v1/shared-sdk/bounded'
      ? this.negotiatedDescriptor.capabilityChecks.evaluator : undefined;
  }
  emit() { this.progress(this.execution); }
  disconnected(cause: unknown) {
    const error = workbenchError(cause);
    this.suspended = true;
    this.lastError = error;
    if (this.execution) { this.command({ op: 'disconnect' }); this.emit(); }
    return Object.assign(error, { execution: this.execution, executionTransport: true });
  }
  async execute(request: Pick<WorkRequest, 'source' | 'entry' | 'arguments' | 'argumentsIon' | 'executionMode' | 'admission'>, progress: Progress = () => {}): Promise<WorkResult> {
    // Capture before release, authentication, page checks or any host effect.
    const captured = structuredClone(request);
    const capturedDescriptor = structuredClone(this.negotiatedDescriptor);
    const policyMapping = capturedDescriptor?.contractVersion === nativePolicyVersion;
    const httpPolicy = policyMapping && this.channel.kind === 'http';
    if (!policyMapping && (captured.executionMode === 'capability' || captured.admission != null)) {
      throw new Error('This host mapping does not offer checking-policy selection.');
    }
    if (!capturedDescriptor) throw new Error('This host does not offer execution evaluation.');
    if (this.active || this.polling || this.reconciliation === 'pending') throw new Error('A host execution is already active. Resume it instead of submitting again.');
    if (this.uncertainSubmission) throw new Error('Submission status is unknown. No second execution was submitted. Reopen the host session to recover.');
    if (this.execution && this.execution.state !== 'terminal') throw new Error('A host execution is already active. Resume it instead of submitting again.');
    const provider = capturedDescriptor.offer;
    const body = { contractVersion: httpPolicy ? nativePolicyVersion : version, model: captured.source, entry: captured.entry,
      inputs: { format: typeof captured.argumentsIon === 'string' ? 'ion-text' : 'json',
        source: typeof captured.argumentsIon === 'string' ? captured.argumentsIon : JSON.stringify(captured.arguments) },
      ...(policyMapping ? { runtime: 'scheme', providerId: typeof provider === 'object' && provider !== null && !Array.isArray(provider) ? provider.providerId : undefined,
        ...(captured.admission != null ? { admission: captured.admission } : {}) } : {}) };
    const capturedBody = JSON.stringify(body);
    // Check frame bounds before parsing the captured selection, then validate
    // it before any submission or cleanup.
    this.encodeRequest('submit', body);
    if (policyMapping) this.command({ op: httpPolicy ? 'validate-http-policy' : 'validate-native-policy', offer: provider, body: capturedBody });
    // Reserve this attempt before cleanup can yield, so another click cannot
    // enter the same pending release and create a second accepted execution.
    ++this.generation;
    this.active = true;
    this.cancelOnSubmit = false;
    if (this.releasePending) {
      try { await this.release(); } catch (cause) {
        this.active = false;
        const error = workbenchError(cause); throw this.disconnected(error);
      }
    }
    this.progress = progress;
    let submitted: { identity: Json; calls: string[]; receipt: Json; plan?: Json } | null;
    try { submitted = await this.request<{ identity: Json; calls: string[]; receipt: Json; plan?: Json }>('submit', body); }
    catch (cause) { const error = workbenchError(cause);
      this.active = false;
      if (!error.rejected) { this.uncertainSubmission = true; error.submissionUnknown = true; error.executionTransport = true; }
      throw error;
    }
    try {
      if (!submitted || !exact(submitted, policyMapping ? ['identity', 'calls', 'receipt', 'plan'] : ['identity', 'calls', 'receipt']) || !Array.isArray(submitted.calls) || submitted.calls.length !== 1 || submitted.calls[0] !== 'workbench') throw new Error('Invalid host submission envelope.');
      this.command({ op: policyMapping ? (httpPolicy ? 'start-http-policy' : 'start-native-policy') : 'start', offer: provider, identity: submitted.identity, calls: ['workbench'], receipt: submitted.receipt,
        ...(policyMapping ? { body: capturedBody, plan: submitted.plan } : {}) });
      if (policyMapping) {
        this.acceptedPlan = structuredClone(submitted.plan!);
        // Diagnostic observation cannot roll back a validated accepted execution.
        try { this.onAcceptedPlan?.(structuredClone(this.acceptedPlan)); } catch { /* Observer owns its failures. */ }
      }
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
    if (this.active || this.polling || this.reconciliation === 'pending') throw new Error('This host execution is already being observed.');
    // Pin the retained execution across asynchronous reauthentication and offer
    // checks. A second submit or resume cannot replace it while these yield.
    this.reconciliation = 'pending';
    try {
      this.progress = progress;
      try {
        const sessionId = await this.authenticate?.();
        if (sessionId !== undefined && sessionId !== this.sessionId) throw new Error('The authenticated host session changed. The retained execution cannot be resumed.');
        const descriptor = await this.descriptor();
        if (descriptor === null) throw new Error('This session no longer offers execution evaluation.');
        if (this.negotiatedDescriptor &&
            (this.negotiatedDescriptor.profile === 'morphir/workbench/native' || this.negotiatedDescriptor.contractVersion === nativePolicyVersion) &&
            (JSON.stringify(descriptor, ['profile','contractVersion','sessionId','operations','offer','hostId','providerId','capabilityChecks','runtime','evaluator','policies']) !== JSON.stringify(this.negotiatedDescriptor, ['profile','contractVersion','sessionId','operations','offer','hostId','providerId','capabilityChecks','runtime','evaluator','policies']))) {
          throw new Error('The host session capabilities changed. Reopen the application page.');
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
      return await this.poll();
    } finally { this.reconciliation = 'idle'; }
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
