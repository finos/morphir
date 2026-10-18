import type { Adapter, Core, CoreReply, Invoke, ExecutionOptions, NativeBridge, NativeDescriptor, NativeMapping, NativeOperations, NativeReply, Progress, WorkRequest, WorkResult } from './contracts.ts';
// Bundled page-bound native protocol. Capability advertisement and platform
// qualification remain separate from using the accepted wire contract here.
import { ExecutionClient } from './execution-session.ts';
import { NativeWorkspaceClient } from './native-workspace.ts';
export const nativeBridgeVersion = '0.2.0-draft.1';
export const nativePolicyBridgeVersion = '0.2.0-draft.2';
export const nativeVersion = (mapping: NativeMapping) => mapping === 'capability-checks' ? nativePolicyBridgeVersion : nativeBridgeVersion;
const limit = 1048576;
// Validation closes both objects. Compare every descriptor/offer field in a fixed
// order so equivalent JSON member order does not look like changed authority.
const descriptorText = (value: NativeDescriptor) => JSON.stringify(value,
  ['profile', 'contractVersion', 'sessionId', 'operations', 'offer', 'hostId', 'providerId', 'capabilityChecks', 'runtime', 'evaluator', 'policies']);
const bytes = (source: string) => new TextEncoder().encode(source).byteLength;

export class NativeSession {
  readonly mapping: NativeMapping;
  invoke: Invoke;
  timeout: number;
  core: Core;
  id: string | null;
  disposed: boolean;
  operations: string[];
  descriptor?: string;
  constructor(invoke: Invoke, timeout = 10000, core: Core = command => globalThis.morphirWorkbenchExecutions(command), mapping: NativeMapping = 'executions') {
    this.mapping = mapping;
    this.invoke = invoke; this.timeout = timeout; this.core = core;
    this.id = null; this.disposed = false; this.operations = [];
  }
  encode(operation: string, payload?: unknown) {
    const frame: { profile: string; contractVersion: string; operation: string; sessionId?: string | null; payload?: unknown } = { profile: 'morphir/workbench/native', contractVersion: nativeVersion(this.mapping), operation };
    if (operation !== 'session.open') frame.sessionId = this.id;
    if (payload !== undefined) frame.payload = payload;
    const source = JSON.stringify(frame);
    if (source.length > limit || bytes(source) > limit) throw new Error('The complete native request exceeds its frame limit.');
    return source;
  }
  admit<T>(source: unknown, operation: string, sessionId: string | null): NativeReply<T> {
    if (typeof source !== 'string' || source.length > limit || bytes(source) > limit) throw new Error('The native host returned an invalid raw reply.');
    const decoded: CoreReply<NativeReply<T>> = JSON.parse(this.core(JSON.stringify({ op: this.mapping === 'capability-checks' ? 'native-policy-response' : 'native-response', source, operation, sessionId })));
    if (!decoded.ok) throw new Error(`The native reply is incompatible (${decoded.code || 'invalid'}).`);
    return decoded.value;
  }
  async exchange<T>(source: string, operation: string, sessionId: string | null, interactive = false) {
    if (this.disposed) throw new Error('The desktop session is closed.');
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const invocation = Promise.resolve().then(() => this.invoke('app:workbench_native', source));
      // Interactive OS picker latency is outside the worker/request deadline.
      const raw = await (interactive ? invocation : Promise.race([invocation,
        new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('The native request timed out. Its effect may be unknown.')), this.timeout); }),
      ]));
      if (this.disposed) throw new Error('The desktop session is closed.');
      return { source: raw, envelope: this.admit<T>(raw, operation, sessionId) };
    } finally { clearTimeout(timer); }
  }
  value<T>(envelope: NativeReply<T>): T {
    if (!envelope.ok) throw Object.assign(new Error(envelope.error.message), {
      native: true, code: envelope.error.code, effect: envelope.error.effect,
    });
    return envelope.value;
  }
  async open() {
    const { envelope } = await this.exchange<NativeDescriptor>(this.encode('session.open'), 'session.open', null);
    const descriptor = this.value(envelope);
    this.id = descriptor.sessionId; this.operations = descriptor.operations;
    this.descriptor = descriptorText(descriptor);
  }
  async check() {
    if (!this.id) throw new Error('The desktop session has not been opened.');
    const { envelope } = await this.exchange<NativeDescriptor>(this.encode('session.check'), 'session.check', this.id);
    const descriptor = this.value(envelope);
    if (descriptorText(descriptor) !== this.descriptor) throw new Error('The desktop session capabilities or authority changed. Reopen the application page.');
    return descriptor;
  }
  async request<K extends keyof NativeOperations>(operation: K, payload?: unknown, interactive = false): Promise<NativeOperations[K]> {
    await this.check();
    const result = await this.exchange<NativeOperations[K]>(this.encode(operation, payload), operation, this.id, interactive);
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

export class NativeExecutionTransport {
  session: NativeSession;
  constructor(session: NativeSession) { this.session = session; }
  async nativeDescriptor() { return JSON.stringify(await this.session.check()); }
  async nativeRequest(source: string) {
    // This is the complete locally generated request from ExecutionClient. Preserve it
    // exactly; only inspect operation/session for this originating invocation.
    const request = JSON.parse(source);
    if (!['execution.submit', 'execution.query', 'execution.cancel', 'execution.release'].includes(request.operation) || request.sessionId !== this.session.id) {
      throw new Error('Invalid native execution operation or session.');
    }
    await this.session.check();
    const result = await this.session.exchange(source, request.operation, this.session.id);
    await this.session.check();
    // ExecutionClient independently admits this same complete raw reply and handles
    // native error effects. Transport failures cannot manufacture no-effect.
    if (typeof result.source !== 'string') throw new Error('Invalid native execution reply.');
    return result.source;
  }
}

export class NativeAdapter {
  local: Adapter;
  session: NativeSession;
  runtimeLabel: string;
  epoch: number;
  disposed: boolean;
  executionOptions: ExecutionOptions;
  executions?: ExecutionClient;
  executionsAvailable = false;
  workspace?: NativeWorkspaceClient;
  constructor(local: Adapter, invoke: Invoke, timeout?: number, executionOptions: ExecutionOptions = {}) {
    this.local = local;
    this.session = new NativeSession(invoke, timeout, executionOptions.core, executionOptions.nativeMapping);
    this.runtimeLabel = 'Desktop local';
    this.epoch = 0;
    this.disposed = false;
    this.executionOptions = executionOptions;
  }
  current(epoch: number) {
    if (this.disposed || epoch !== this.epoch) throw new Error('Discarded. The desktop request is no longer current.');
  }
  async initialize(): Promise<WorkResult> {
    const epoch = ++this.epoch;
    await this.session.open();
    this.current(epoch);
    const result = await this.local.initialize();
    this.current(epoch);
    await this.session.check();
    this.current(epoch);
    if (this.session.operations.includes('executions')) {
      this.executions = new ExecutionClient(this.session.id!, { ...this.executionOptions, transport: new NativeExecutionTransport(this.session),
        authenticate: async () => { await this.session.check(); return this.session.id!; } });
      this.executionsAvailable = await this.executions.initialize();
      if (!this.executionsAvailable) throw new Error("The native host advertised executions without a compatible offer.");
      this.current(epoch);
    }
    if (this.session.operations.includes('workspace')) this.workspace = new NativeWorkspaceClient(this.session, this.local);
    return { ...result, capabilityEvaluator: this.session.mapping === 'capability-checks' && this.executionsAvailable ? 'scheme-portable-v1/shared-sdk/bounded' : undefined, capabilityRuntime: this.session.mapping === 'capability-checks' && this.executionsAvailable ? 'native' : undefined, nativeSession: true, workspaceAvailable: !!this.workspace, executionsAvailable: !!this.executionsAvailable, message: 'Desktop local · ready to compile' };
  }
  async execute(request: WorkRequest, progress?: Progress): Promise<WorkResult> {
    // Snapshot all source/input/policy data before checking page authority.
    request = structuredClone(request);
    if (this.session.mapping !== 'capability-checks' && (request.executionMode === 'capability' || request.admission != null)) {
      throw new Error('This native session does not offer checking-policy selection.');
    }
    if ((request.executionMode === 'capability' || request.admission != null) &&
        (request.operation !== 'evaluate' || !this.executionsAvailable)) {
      throw new Error('This native session does not offer checking-policy selection.');
    }
    // Worksheets use only captured local source and own a browser worker.
    // Native session epochs must not discard that worker's cancellation report.
    if (request.operation === 'worksheet') return this.local.execute(request);
    const epoch = ++this.epoch;
    await this.session.check();
    this.current(epoch);
    if (this.executionsAvailable && (request.operation === 'resume-execution' ||
        (request.operation === 'evaluate' && (request.executionMode === 'typed' || request.executionMode === 'capability')))) {
      const currentProgress: Progress = execution => {
        if (!this.disposed && epoch === this.epoch) progress?.(execution);
      };
      const result = request.operation === 'resume-execution'
        ? await this.executions!.resume(currentProgress)
        : await this.executions!.execute(request, currentProgress);
      this.current(epoch);
      return result;
    }
    if (request.operation === 'workspace' && this.workspace) {
      const result = await this.workspace.choose(); this.current(epoch); return result;
    }
    if (request.operation === 'project' && this.workspace) {
      const result = await this.workspace.openProject(typeof request.project === 'string' ? request.project : ''); this.current(epoch); return result;
    }
    if (request.operation === 'project' || request.operation === 'workspace' || request.operation === 'resume-execution') throw new Error('This desktop session does not offer native executions or workspace access.');
    const result = await this.local.execute(request);
    this.current(epoch);
    await this.session.check();
    this.current(epoch);
    return result;
  }
  cancel() {
    if (this.executions?.active || (this.executions?.execution && this.executions.execution.state !== 'terminal')) return this.executions.cancel();
    ++this.epoch; this.local.cancel(); return this.workspace?.cancel();
  }
  dispose() { this.disposed = true; ++this.epoch; this.workspace?.dispose(); this.local.cancel(); this.session.dispose(); }
}

export function selectLocalAdapter(location: Pick<Location, 'href'>, local: Adapter, bridge: NativeBridge | null | undefined = globalThis.__MoonBit__) {
  const url = new URL(location.href);
  const mode = url.searchParams.get('mode');
  if (mode && mode !== 'native') return local;
  const bundled = (url.protocol === 'https:' && url.host === 'proton.localhost') ||
    (url.protocol === 'proton:' && url.host === 'app');
  if (!bundled) return local;
  return new NativeAdapter(local, (name, payload) => {
    if (typeof bridge?.core?.invokeOp !== 'function') throw new Error('The desktop command bridge is unavailable.');
    return bridge.core.invokeOp(name, payload);
  }, undefined, { nativeMapping: 'capability-checks' });
}
