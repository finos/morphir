import type { Adapter, Catalog, CoreReply, Diagnostic, JobOptions, Language, Manifest, Progress, Project, Target, WorkRequest, WorkResult, WorkerPort, Rpc, RpcSocket, Fetch } from './contracts.ts';
import { isRecord, workbenchError } from '../../../types/data.ts';
import { JobClient } from './job-session.ts';
// Browser host boundary. Private operation envelopes never go onto Morphir RPC.
export class LocalAdapter {
  workerFactory: () => WorkerPort;
  timeout: number;
  nextId: number;
  active: { id: number; cancel(): void } | null;
  declare runtimeLabel?: string;
  constructor(workerFactory: LocalAdapter['workerFactory'] = () => {
    const worker = new Worker(new URL('./worker.js', import.meta.url));
    const port: WorkerPort = { postMessage: message => worker.postMessage(message), terminate: () => worker.terminate() };
    worker.onmessage = event => port.onmessage?.(event);
    worker.onerror = () => port.onerror?.();
    return port;
  }, timeout = 15000) {
    this.workerFactory = workerFactory;
    this.timeout = timeout;
    this.nextId = 0;
    this.active = null;
  }
  async initialize() {
    const catalog = await this.execute({ operation: 'catalog', source: '' });
    if (!catalog.success || !Array.isArray(catalog.frontends) || !Array.isArray(catalog.targets)) throw new Error(catalog.message || 'The local compiler catalog is unavailable.');
    return { success: true, operation: 'initialize', connected: false, catalog: { ...catalog, frontends: catalog.frontends, targets: catalog.targets }, projects: [], message: 'Browser local · ready to compile' };
  }
  execute(request: WorkRequest, _progress?: Progress): Promise<WorkResult> {
    this.cancel();
    if (request.sourceBase64 !== undefined && (typeof request.sourceBase64 !== 'string' || request.sourceBase64.length > Math.ceil(16 * 1024 * 1024 / 3) * 4 ||
        request.operation !== 'inspect' || !['morphir-json', 'ion-text', 'ion-binary'].includes(request.sourceCodec ?? ''))) {
      return Promise.reject(new Error('Model bytes must use a supported codec and fit the 16 MiB import limit.'));
    }
    if (typeof request.source !== 'string' || request.source.length > 16 * 1024 * 1024) {
      return Promise.reject(new Error('Source must be text smaller than 16 MiB.'));
    }
    if (request.arguments !== undefined && JSON.stringify(request.arguments).length > 16 * 1024 * 1024) {
      return Promise.reject(new Error('Function arguments must be smaller than 16 MiB.'));
    }
    if (typeof request.argumentsIon === 'string' && request.argumentsIon.length > 16 * 1024 * 1024) {
      return Promise.reject(new Error('Ion arguments must be smaller than 16 MiB.'));
    }
    return new Promise<WorkResult>((resolve, reject) => {
      const worker = this.workerFactory();
      const id = ++this.nextId;
      const finish = (error: unknown, result?: WorkResult) => {
        clearTimeout(timer);
        worker.terminate();
        if (this.active?.id === id) this.active = null;
        if (error) reject(error); else resolve(result!);
      };
      const timer = setTimeout(() => finish(new Error('Local execution timed out after 15 seconds.')), this.timeout);
      this.active = { id, cancel: () => finish(new Error('Cancelled')) };
      worker.onmessage = ({ data }) => {
        if (data.id === id) finish(null, data.result);
      };
      worker.onerror = () => finish(new Error('The local runtime worker failed.'));
      try { worker.postMessage({ id, request }); } catch (cause) { const error = workbenchError(cause); finish(error); }
    });
  }
  cancel() { this.active?.cancel(); }
  dispose() { this.cancel(); }
}

export function validateManifest(manifest: unknown): Manifest {
  if (!isRecord(manifest)) throw new Error('Invalid session manifest.');
  if (manifest?.protocolVersion !== 1 || manifest.webSocketPath !== '/rpc' || typeof manifest.sessionId !== 'string' || !manifest.sessionId) {
    throw new Error('This client requires connected Morphir protocol v1 and /rpc.');
  }
  if (!Array.isArray(manifest.providers) || !Array.isArray(manifest.initialSources)) throw new Error('Invalid session manifest.');
  const ids = new Set();
  for (const provider of manifest.providers) {
    if (typeof provider.id !== 'string' || ids.has(provider.id) || !Array.isArray(provider.capabilities)) throw new Error('Invalid session provider.');
    ids.add(provider.id);
  }
  if (manifest.initialSources.some(source => !ids.has(source.providerId) || typeof source.locator !== 'string' || typeof source.displayName !== 'string')) {
    throw new Error('An initial source references an unknown provider.');
  }
  return manifest as unknown as Manifest;
}

export class RpcClient {
  socket: RpcSocket;
  timeout: number;
  nextId: number;
  pending: Map<number, { resolve(value: unknown): void; reject(error: unknown): void; timer: ReturnType<typeof setTimeout> }>;
  closed: boolean;
  constructor(socket: RpcClient['socket'], timeout = 60000) {
    this.socket = socket;
    this.timeout = timeout;
    this.nextId = 0;
    this.pending = new Map();
    this.closed = false;
    socket.addEventListener('message', event => {
      let message;
      try { message = JSON.parse((event as MessageEvent<string>).data); } catch { this.fail(new Error('Invalid JSON from the connected host.')); return; }
      if (message.jsonrpc !== '2.0') { this.fail(new Error('Invalid JSON-RPC response.')); return; }
      // Notifications are not RPC replies. No watch subscription is opened by this slice.
      if (message.id === undefined) return;
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      clearTimeout(pending.timer);
      if (message.error) pending.reject(new Error(message.error.message || 'Morphir RPC failed'));
      else if ('result' in message) pending.resolve(message.result);
      else pending.reject(new Error('Missing RPC result.'));
    });
    socket.addEventListener('close', () => this.fail(new Error('The Morphir host disconnected. Reload to reconnect.')));
    socket.addEventListener('error', () => this.fail(new Error('The Morphir host connection failed.')));
  }
  fail(error: Error) {
    this.closed = true;
    for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(error); }
    this.pending.clear();
  }
  call<T = unknown>(method: string, params: unknown): Promise<T> {
    if (this.closed || this.socket.readyState !== 1) return Promise.reject(new Error('The Morphir host is not connected.'));
    if (this.nextId >= Number.MAX_SAFE_INTEGER) return Promise.reject(new Error('Reconnect to renew RPC request IDs.'));
    const id = ++this.nextId;
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('The connected host request timed out. It may still be running.'));
      }, this.timeout);
      this.pending.set(id, { resolve: value => resolve(value as T), reject, timer });
      try { this.socket.send(JSON.stringify({ jsonrpc: '2.0', id, method, params })); }
      catch (cause) { const error = workbenchError(cause); clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }
  dispose() { this.fail(new Error('Disconnected')); this.socket.close(); }
}

const major = (version: string) => String(version).split('.')[0];
export function chooseVersion(frontend: Language, target?: Pick<Target, 'irVersions'> | null) {
  const offered = frontend.irVersions.filter(version => !target || target.irVersions.some(other => major(other) === major(version)));
  if (!offered.length) throw new Error('This language and target have no compatible IR version.');
  return offered.find(version => major(version) === '4') ?? offered[0];
}

function diagnosticMessage(result: { diagnostics?: Diagnostic[] }, fallback: string) {
  return result.diagnostics?.map(diagnostic => diagnostic.message).filter(Boolean).join('\n') || fallback;
}

export class ConnectedAdapter {
  rpc: Rpc;
  jobs: Pick<JobClient, 'initialize' | 'execute' | 'resume' | 'cancel' | 'active' | 'job'> | null;
  manifest: Manifest;
  local: Pick<Adapter, 'execute' | 'cancel'>;
  catalog: Catalog;
  projects: Project[];
  documentVersion: number;
  epoch: number;
  workspaceMessage?: string;
  jobsAvailable = false;
  constructor(rpc: Rpc, manifest: Manifest, local: Pick<Adapter, 'execute' | 'cancel'>, jobs: Pick<JobClient, 'initialize' | 'execute' | 'resume' | 'cancel' | 'active' | 'job'> | null = null) {
    this.rpc = rpc;
    this.jobs = jobs;
    this.manifest = validateManifest(manifest);
    this.local = local;
    this.catalog = { frontends: [], targets: [] };
    this.projects = [];
    this.documentVersion = 0;
    this.epoch = 0;
  }
  private call<T = unknown>(method: string, params: Record<string, unknown>): Promise<T> {
    return this.rpc.call(method, params).then(value => value as T);
  }
  supports(capability: string, providerId?: string) {
    return this.manifest.providers.some(provider => (!providerId || provider.id === providerId) && provider.status === 'available' &&
      provider.capabilities.some(cap => cap.name === capability && cap.version === '1'));
  }
  async initialize() {
    await this.rpc.call('morphir.session.initialize', { protocolVersion: 1, sessionId: this.manifest.sessionId });
    if (this.supports('morphir/playground/catalog')) {
      const catalog = await this.call<Catalog>('morphir.playground.catalog', {});
      if (!Array.isArray(catalog?.frontends) || !Array.isArray(catalog?.targets)) throw new Error('Invalid playground catalog.');
      this.catalog = {
        frontends: this.supports('morphir/playground/compile') ? catalog.frontends.filter(frontend => frontend.compile) : [],
        targets: this.supports('morphir/playground/generate') ? catalog.targets.filter(target => target.generate) : [],
      };
    }
    for (const source of this.manifest.initialSources) {
      if (!this.supports('morphir/workspace/open', source.providerId) || !this.supports('morphir/project-model/open', source.providerId)) continue;
      try {
        const opened = await this.call<{ snapshot: { projects: Project[] } }>('morphir.workspace.open', { source });
        const snapshot = opened?.snapshot;
        if (!Array.isArray(snapshot?.projects) || snapshot.projects.some(project => typeof project?.id !== 'string' || typeof project?.name !== 'string')) {
          throw new Error('Invalid workspace snapshot from the Morphir host.');
        }
        for (const project of snapshot.projects) {
          this.projects.push({ id: String(this.projects.length), name: project.name, projectId: project.id, source });
        }
      } catch (cause) { const error = workbenchError(cause); this.workspaceMessage = error.message; }
    }
    this.jobsAvailable = this.jobs ? await this.jobs.initialize() : false;
    return { success: true, operation: 'initialize', connected: true, jobsAvailable: this.jobsAvailable, catalog: this.catalog, projects: this.projects,
      message: this.workspaceMessage || (this.catalog.frontends.length ? 'Connected · ready to compile' : 'Connected · no compiler is advertised') };
  }
  async execute(request: WorkRequest, progress?: Progress): Promise<WorkResult> {
    if (request.operation === 'resume-job') return this.jobs!.resume(progress);
    if (request.operation === 'evaluate' && this.jobsAvailable) return this.jobs!.execute(request, progress);
    const epoch = this.epoch;
    const stillCurrent = () => { if (epoch !== this.epoch) throw new Error("Discarded. The host may still be working."); };
    if (request.operation === 'inspect') return this.local.execute(request);
    if (request.operation === 'project') {
      const project = this.projects.find(project => project.id === request.project);
      if (!project) throw new Error('Unknown workspace project.');
      const opened = await this.call<{ content: string }>('morphir.project-model.open', { source: project.source, projectId: project.projectId });
      stillCurrent();
      return this.local.execute({ operation: 'inspect', source: opened.content });
    }
    if (request.operation !== 'compile') throw new Error('The connected v1 protocol does not offer evaluation.');
    const frontend = this.catalog.frontends.find(frontend => frontend.languageId === request.languageId);
    if (!frontend) throw new Error('This language is unavailable on the connected host.');
    const target = request.target ? this.catalog.targets.find(target => target.target === request.target) : null;
    if (request.target && !target) throw new Error('This generation target is unavailable.');
    const irVersion = chooseVersion(frontend, target);
    const extension = frontend.fileExtensions?.[0] || '.txt';
    const compiled = await this.call<WorkResult & { irVersion: string }>('morphir.playground.compile', {
      languageId: frontend.languageId,
      documents: [{ uri: `file:///main${extension}`, languageId: frontend.languageId, version: ++this.documentVersion, text: request.source }],
      package: { name: 'user' }, irVersion, options: {},
    });
    stillCurrent();
    if (!compiled.success || !compiled.ir || !compiled.irVersion) {
      // Keep the host's structured v1 diagnostics for the Diagnostics panel.
      throw Object.assign(new Error(diagnosticMessage(compiled, 'Compilation failed.')),
        { diagnostics: Array.isArray(compiled.diagnostics) ? compiled.diagnostics : [] });
    }
    let inspected: WorkResult;
    try {
      inspected = await this.local.execute({ operation: 'inspect', source: JSON.stringify(compiled.ir) });
    } catch (cause) { const error = workbenchError(cause);
      inspected = { success: false, message: error?.message || 'Local inspection failed.' };
    }
    // Discard takes precedence over an inspection fallback and prevents generation.
    stillCurrent();
    // Preserve host compilation when client inspection cannot decode or execute.
    const result: WorkResult = { ...inspected, success: true, ir: compiled.ir, irSource: JSON.stringify(compiled.ir), generated: '', diagnostics: compiled.diagnostics,
      inspectionMessage: inspected.success ? '' : inspected.message };
    if (target) {
      try {
        const generated = await this.call<WorkResult & { artifacts: import('./contracts.ts').Artifact[] }>('morphir.playground.generate', { ir: compiled.ir, irVersion: compiled.irVersion, target: target.target, options: {} });
        if (!Array.isArray(generated.artifacts) || generated.artifacts.some(artifact =>
          !artifact || typeof artifact.path !== 'string' || typeof artifact.content !== 'string' || typeof artifact.binary !== 'boolean')) {
          throw new Error('The host returned an invalid generated file envelope.');
        }
        // v1 does not negotiate binary encodings. Never adopt a local-worker
        // encoding declaration from an arbitrary connected host extension.
        result.artifacts = generated.artifacts.map(({path, content, binary}) => ({path, content, binary}));
        result.generated = (generated.artifacts ?? []).map(artifact => `; ${artifact.path}\n${artifact.binary ? '[Binary artifact: text preview unavailable]' : artifact.content}`).join('\n\n');
        if (!generated.success) result.generationMessage = diagnosticMessage(generated, 'Generation failed.');
      } catch (cause) { const error = workbenchError(cause); result.generationMessage = error.message; }
    }
    return result;
  }
  cancel() {
    if (this.jobs?.active || (this.jobs?.job && this.jobs.job.state !== 'terminal')) return this.jobs.cancel();
    ++this.epoch; this.local.cancel(); /* v1 has no server cancellation method */ }
  dispose() { ++this.epoch; this.local.cancel(); this.rpc.dispose?.(); }
}

export async function connect(location: Pick<Location, 'href' | 'protocol'>, local: Adapter, fetchFn: Fetch = fetch, Socket: typeof WebSocket = WebSocket) {
  const response = await fetchFn('/api/session', { credentials: 'same-origin', cache: 'no-store' });
  if (!response.ok) throw new Error('Open this client through the Morphir host launch URL to authenticate.');
  const manifest = validateManifest(await response.json());
  const url = new URL(manifest.webSocketPath, location.href);
  url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const socket = new Socket(url.href);
  const rpc = new RpcClient(socket);
  try {
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => { socket.close(); reject(new Error('Morphir connection timed out.')); }, 10000);
      socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
      socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('Cannot connect to the same-origin Morphir host.')); }, { once: true });
      socket.addEventListener('close', () => { clearTimeout(timer); reject(new Error('Morphir connection closed before initialization.')); }, { once: true });
    });
    const jobs = new JobClient(manifest.sessionId, { fetchFn, authenticate: async () => {
      const response = await fetchFn('/api/session', { credentials: 'same-origin', cache: 'no-store' });
      if (!response.ok) throw new Error('Authenticate with the same host session to resume this job.');
      return validateManifest(await response.json()).sessionId;
    } });
    return new ConnectedAdapter(rpc, manifest, local, jobs);
  } catch (cause) { const error = workbenchError(cause); rpc.dispose(); throw error; }
}
