import { openArtifactChannel, type ArtifactRpcChannel } from '../../../pkgs/morphir-host/artifact-client/artifact-rpc.ts';
import type { RpcSocket } from '../../../pkgs/morphir-host/artifact-client/contracts.ts';
import {
  ExactJsonNumber, parseArtifactFrame, wellFormed, utf8Length, type ExactJson,
} from '../../../pkgs/morphir-host/artifact-client/artifact-client/artifact-wire.ts';

// This proposed offer is inactive until the complete client/host profile is qualified.
const profile = 'morphir/workbench/model-originals';
const version = '0.1.0-draft.1';
const workspaceOffer = 'morphir/workspace/open';
const maxManifestBytes = 128 * 1024; // Existing literal reader/frame ceiling.

export class ModelOriginalsConnectionLimits {
  readonly #manifestBytes: number;
  private constructor(bytes: number) {
    if (!Number.isSafeInteger(bytes) || bytes < 1 || bytes > maxManifestBytes)
      throw failure('Invalid manifest byte limit.');
    this.#manifestBytes = bytes; Object.freeze(this);
  }
  static create(value: { manifestBytes: number }): ModelOriginalsConnectionLimits {
    return new ModelOriginalsConnectionLimits(value.manifestBytes);
  }
  static manifestBudget(value: ModelOriginalsConnectionLimits): number {
    if (!(value instanceof ModelOriginalsConnectionLimits) || !(#manifestBytes in value))
      throw failure('Missing validated connection limits.');
    return value.#manifestBytes;
  }
  get manifestBytes(): number { return this.#manifestBytes; }
}

declare const sourceSelection: unique symbol;
declare const projectSelection: unique symbol;
export interface ModelOriginalsSource {
  readonly [sourceSelection]: true;
  readonly providerId: string;
  readonly locator: string;
  readonly displayName: string;
}
export interface ModelOriginalsProject {
  readonly [projectSelection]: true;
  readonly projectId: string;
  readonly name: string;
}
type ModelOriginalsMethod = 'morphir.session.initialize' | 'morphir.workspace.open' | 'morphir.model-originals.capture';
export type ModelOriginalsObservation =
  | Readonly<{ kind: 'manifest'; raw: string }>
  | Readonly<{ kind: 'exchange'; method: ModelOriginalsMethod; requestId: string; request: string; reply: string }>
  | Readonly<{ kind: 'closed' }>;
export type ModelOriginalsCaptureExchange = Readonly<{ requestId: string; request: string; reply: string }>;
export interface ModelOriginalsSession {
  readonly sources: readonly ModelOriginalsSource[];
  openSource(source: ModelOriginalsSource): Promise<readonly ModelOriginalsProject[]>;
  /** Raw correlated exchange only. This does not verify a capture or adopt a model. */
  exchangeCapture(project: ModelOriginalsProject, options: {
    scope: 'primary' | 'complete'; semantic: 'none' | 'projection';
  }): Promise<ModelOriginalsCaptureExchange>;
  close(): void;
}
type Options = {
  limits: ModelOriginalsConnectionLimits;
  signal: AbortSignal;
  fetch?: (input: URL, init: RequestInit) => Promise<Response>;
  createSocket?: (url: string) => RpcSocket;
  observe?: (event: ModelOriginalsObservation) => void;
};
type Opened = { kind: 'unavailable'; reason: 'not-offered' } | { kind: 'ready'; session: ModelOriginalsSession };
type SourceRef = Readonly<{ providerId: DiscoveryIdentity<'provider'>; locator: DiscoveryIdentity<'locator'>;
  displayName: string; persistence?: 'session' }>;
type Offer = { sessionId: DiscoveryIdentity<'session'>; webSocketPath: string; sources: readonly SourceRef[] };
type State = 'idle' | 'pending' | 'capture-observed' | 'closed';

function failure(message: string): Error { return new Error(`Model originals connection: ${message}`); }
function object(value: ExactJson | undefined): ReadonlyMap<string, ExactJson> {
  if (!(value instanceof Map)) throw failure('Expected an object.');
  return value;
}
function fields(value: ExactJson | undefined, required: readonly string[], optional: readonly string[] = []): ReadonlyMap<string, ExactJson> {
  const result = object(value);
  if (required.some(key => !result.has(key)) || [...result.keys()].some(key => !required.includes(key) && !optional.includes(key)))
    throw failure('Unexpected discovery fields.');
  return result;
}
function list(value: ExactJson | undefined): readonly ExactJson[] {
  if (!Array.isArray(value)) throw failure('Expected an array.');
  return value;
}
function text(value: ExactJson | undefined): string {
  if (typeof value !== 'string' || !wellFormed(value)) throw failure('Expected a Unicode string.');
  return value;
}
type IdentityRole = 'session' | 'provider' | 'locator' | 'workspace' | 'project';
class DiscoveryIdentity<Role extends IdentityRole> {
  readonly #role: Role;
  readonly #value: string;
  private constructor(role: Role, value: string) { this.#role = role; this.#value = value; Object.freeze(this); }
  static read<Role extends IdentityRole>(role: Role, value: ExactJson | undefined): DiscoveryIdentity<Role> {
    const result = text(value);
    const maximum = role === 'session' || role === 'provider' ? 128 : role === 'locator' ? 4096 : 12288;
    let points = 0;
    for (const character of result) {
      const point = character.codePointAt(0)!;
      if (++points > maximum || point < 0x20 || (point >= 0x7f && point <= 0x9f))
        throw failure('Invalid discovery identity.');
    }
    if (!points) throw failure('Empty discovery identity.');
    return new DiscoveryIdentity(role, result);
  }
  get value(): string { return this.#value; }
  equals(other: DiscoveryIdentity<Role>): boolean { return this.#role === other.#role && this.#value === other.#value; }
}
function numericToken(value: ExactJson | undefined, expected: string): void {
  if (!(value instanceof ExactJsonNumber) || value.lexeme !== expected)
    throw failure('Invalid literal protocol version or request correlation.');
}
function literal(raw: string): ExactJson {
  try { return parseArtifactFrame(raw); }
  catch { throw failure('Invalid or excessive literal JSON.'); }
}
function readSource(value: ExactJson | undefined): SourceRef {
  const root = fields(value, ['providerId', 'locator', 'displayName'], ['persistence']);
  const providerId = DiscoveryIdentity.read('provider', root.get('providerId'));
  const locator = DiscoveryIdentity.read('locator', root.get('locator'));
  const displayName = text(root.get('displayName'));
  const persistence = root.get('persistence');
  if (persistence !== undefined && persistence !== 'session') throw failure('Invalid source persistence.');
  return Object.freeze(persistence === undefined ? { providerId, locator, displayName }
    : { providerId, locator, displayName, persistence });
}
function readOffer(raw: string): Offer {
  const manifest = fields(literal(raw), ['protocolVersion', 'sessionId', 'webSocketPath', 'providers', 'initialSources']);
  numericToken(manifest.get('protocolVersion'), '1');
  const sessionId = DiscoveryIdentity.read('session', manifest.get('sessionId'));
  const webSocketPath = text(manifest.get('webSocketPath'));
  if (webSocketPath !== '/rpc') throw failure('The v1 socket path must be /rpc.');
  const providerIds = new Set<string>();
  const offered = new Set<string>();
  for (const item of list(manifest.get('providers'))) {
    const provider = fields(item, ['id', 'name', 'kind', 'status', 'capabilities'], ['provenance']);
    const id = DiscoveryIdentity.read('provider', provider.get('id'));
    if (providerIds.has(id.value)) throw failure('Duplicate provider identity.');
    providerIds.add(id.value);
    const status = text(provider.get('status'));
    text(provider.get('name'));
    if (provider.get('kind') !== 'connected' || (status !== 'available' && status !== 'disconnected'))
      throw failure('Unknown provider kind or status.');
    if (provider.has('provenance')) {
      const provenance = fields(provider.get('provenance'), ['extensionId', 'extensionVersion']);
      text(provenance.get('extensionId')); text(provenance.get('extensionVersion'));
    }
    let originals: string | undefined, workspace: string | undefined;
    for (const item of list(provider.get('capabilities'))) {
      const capability = fields(item, ['name', 'version']);
      const name = text(capability.get('name')), offeredVersion = text(capability.get('version'));
      if (name === profile) {
        if (originals !== undefined) throw failure('Ambiguous model originals offer.');
        originals = offeredVersion;
      }
      if (name === workspaceOffer) {
        if (workspace !== undefined) throw failure('Ambiguous workspace offer.');
        workspace = offeredVersion;
      }
    }
    if (status === 'available' && originals === version && workspace === '1') offered.add(id.value);
  }
  const sources: SourceRef[] = [];
  const seen = new Map<string, Set<string>>();
  for (const item of list(manifest.get('initialSources'))) {
    const source = readSource(item);
    if (!providerIds.has(source.providerId.value)) throw failure('Unknown source provider.');
    const locators = seen.get(source.providerId.value) ?? new Set<string>();
    if (locators.has(source.locator.value)) throw failure('Duplicate source identity.');
    locators.add(source.locator.value); seen.set(source.providerId.value, locators);
    if (offered.has(source.providerId.value)) sources.push(source);
  }
  return { sessionId, webSocketPath, sources: Object.freeze(sources) };
}

async function readManifest(response: Response, maximum: number, signal: AbortSignal): Promise<string> {
  if (!response.ok) throw failure(`Session discovery HTTP ${response.status}.`);
  if (!response.body) throw failure('Missing session discovery body.');
  const reader = response.body.getReader();
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', cancel, { once: true });
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let bytes = 0, result = '';
  try {
    for (;;) {
      if (signal.aborted) throw failure('Opening cancelled.');
      const chunk = await reader.read();
      if (signal.aborted) throw failure('Opening cancelled.');
      if (chunk.done) break;
      if (chunk.value.byteLength > maximum - bytes) throw failure('Manifest byte limit exceeded.');
      bytes += chunk.value.byteLength;
      result += decoder.decode(chunk.value, { stream: true });
    }
    return result + decoder.decode();
  } catch (cause) {
    // Cancellation is best effort and must not hold the failed opener indefinitely.
    void reader.cancel().catch(() => {});
    throw cause;
  } finally { signal.removeEventListener('abort', cancel); reader.releaseLock(); }
}

/**
 * Establish a distinct, attempt-owned v1 channel. No UI activation or producer
 * advertisement occurs here. The caller must supply its manifest byte budget.
 */
export async function openModelOriginalsSession(base: URL, options: Options): Promise<Opened> {
  base = new URL(base.href);
  // Snapshot boundary accessors before any validation or awaited effects.
  options = Object.freeze({ limits: options.limits, signal: options.signal, fetch: options.fetch,
    createSocket: options.createSocket, observe: options.observe });
  const maximum = ModelOriginalsConnectionLimits.manifestBudget(options.limits);
  if (options.signal.aborted) throw failure('Opening cancelled.');
  if ((base.protocol !== 'http:' && base.protocol !== 'https:') || base.username || base.password)
    throw failure('Expected an HTTP origin without credentials.');
  const response = await (options.fetch ?? globalThis.fetch)(new URL('/api/session', base), {
    credentials: 'same-origin', cache: 'no-store', signal: options.signal, redirect: 'error',
  });
  const raw = await readManifest(response, maximum, options.signal);
  if (options.signal.aborted) throw failure('Opening cancelled.');
  const offer = readOffer(raw);
  options.observe?.(Object.freeze({ kind: 'manifest', raw }));
  if (options.signal.aborted) throw failure('Opening cancelled.');
  if (!offer.sources.length) return { kind: 'unavailable', reason: 'not-offered' };
  const socketUrl = new URL(offer.webSocketPath, base);
  if (socketUrl.origin !== base.origin || socketUrl.username || socketUrl.password || socketUrl.hash)
    throw failure('The socket must belong to the discovered HTTP origin.');
  socketUrl.protocol = base.protocol === 'https:' ? 'wss:' : 'ws:';
  const channel = await openArtifactChannel(() => (options.createSocket ?? (url => new WebSocket(url)))(socketUrl.href), options.signal);
  return { kind: 'ready', session: await OwnedSession.open(channel, offer, options) };
}

const ownedConstruction = Symbol();
class OwnedSession implements ModelOriginalsSession {
  readonly sources: readonly ModelOriginalsSource[];
  readonly #sourceRefs = new WeakMap<ModelOriginalsSource, SourceRef>();
  readonly #projects = new WeakMap<ModelOriginalsProject, {
    source: SourceRef; projectId: DiscoveryIdentity<'project'>; generation: symbol;
  }>();
  #generation = Symbol();
  #state: State = 'idle';
  #nextId = 1n;
  readonly #channel: ArtifactRpcChannel;
  readonly #signal: AbortSignal;
  readonly #observe: Options['observe'];

  private constructor(token: typeof ownedConstruction, channel: ArtifactRpcChannel, sources: readonly SourceRef[], signal: AbortSignal, observe: Options['observe']) {
    if (token !== ownedConstruction) throw failure('Use the initialized connection factory.');
    this.#channel = channel; this.#signal = signal; this.#observe = observe;
    this.sources = Object.freeze(sources.map(source => {
      const selection = Object.freeze({ providerId: source.providerId.value, locator: source.locator.value,
        displayName: source.displayName }) as ModelOriginalsSource;
      this.#sourceRefs.set(selection, source);
      return selection;
    }));
    signal.addEventListener('abort', this.#cancelled, { once: true });
    if (signal.aborted) this.close();
    Object.freeze(this);
  }
  static async open(channel: ArtifactRpcChannel, offer: Offer, options: Options): Promise<OwnedSession> {
    const session = new OwnedSession(ownedConstruction, channel, offer.sources, options.signal, options.observe);
    try {
      await session.#run('morphir.session.initialize', { protocolVersion: 1, sessionId: offer.sessionId.value }, result => {
        numericToken(fields(result, ['protocolVersion']).get('protocolVersion'), '1');
      });
      return session;
    } catch (cause) { session.close(); throw cause; }
  }
  #cancelled = () => this.close();
  #active(): void {
    if (this.#state === 'closed' || this.#signal.aborted || this.#channel.closed) {
      this.close(); throw failure('The owned connection is closed or cancelled.');
    }
  }
  #idle(): void {
    this.#active();
    if (this.#state !== 'idle') throw failure(this.#state === 'capture-observed'
      ? 'A capture has already been observed. Close its owned connection.' : 'An exchange is already pending.');
  }
  async #run<T>(method: ModelOriginalsMethod, params: object,
    decode: (result: ExactJson, exchange: ModelOriginalsCaptureExchange) => T, capture = false): Promise<T> {
    this.#idle();
    this.#state = 'pending';
    try {
      if (this.#nextId > 18446744073709551615n) throw failure('Request IDs exhausted.');
      const requestId = String(this.#nextId++);
      const request = `{"jsonrpc":"2.0","id":${requestId},"method":${JSON.stringify(method)},"params":${JSON.stringify(params)}}`;
      if (capture && utf8Length(request) > 16 * 1024) throw failure('Capture request exceeds 16 KiB.');
      const reply = await this.#channel.exchange(request);
      this.#active();
      const exchange = Object.freeze({ requestId, request, reply });
      this.#observe?.(Object.freeze({ kind: 'exchange', method, ...exchange }));
      this.#active();
      const envelope = object(literal(reply));
      if (envelope.size !== 3 || envelope.get('jsonrpc') !== '2.0' || !envelope.has('result') || envelope.has('error'))
        throw failure('Expected a successful closed JSON-RPC reply.');
      numericToken(envelope.get('id'), requestId);
      const value = decode(envelope.get('result')!, exchange);
      this.#active();
      this.#state = capture ? 'capture-observed' : 'idle';
      return value;
    } catch (cause) { this.close(); throw cause; }
  }
  async openSource(selection: ModelOriginalsSource): Promise<readonly ModelOriginalsProject[]> {
    this.#idle();
    const source = this.#sourceRefs.get(selection);
    if (!source) throw failure('Source selection belongs to another connection.');
    // Any actual new opening invalidates the earlier discovery, including a failed opening.
    const generation = Symbol(); this.#generation = generation;
    const wireSource = { providerId: source.providerId.value, locator: source.locator.value,
      displayName: source.displayName, ...(source.persistence === undefined ? {} : { persistence: source.persistence }) };
    return this.#run('morphir.workspace.open', { source: wireSource }, result => {
      const snapshot = object(object(result).get('snapshot'));
      const root = readSource(snapshot.get('root'));
      if (!root.providerId.equals(source.providerId) || !root.locator.equals(source.locator) || snapshot.get('state') !== 'open')
        throw failure('Workspace snapshot does not match the actual selected source.');
      DiscoveryIdentity.read('workspace', snapshot.get('id'));
      const seen = new Set<string>();
      const projects: ModelOriginalsProject[] = [];
      for (const item of list(snapshot.get('projects'))) {
        const project = object(item), projectId = DiscoveryIdentity.read('project', project.get('id')), name = text(project.get('name'));
        if (seen.has(projectId.value)) throw failure('Duplicate project identity.');
        seen.add(projectId.value);
        const state = project.get('state');
        if (state !== 'unloaded' && state !== 'error') throw failure('Unknown project state.');
        if (state === 'error') continue;
        const selected = Object.freeze({ projectId: projectId.value, name }) as ModelOriginalsProject;
        this.#projects.set(selected, { source, projectId, generation }); projects.push(selected);
      }
      return Object.freeze(projects);
    });
  }
  async exchangeCapture(selection: ModelOriginalsProject, options: {
    scope: 'primary' | 'complete'; semantic: 'none' | 'projection';
  }): Promise<ModelOriginalsCaptureExchange> {
    this.#idle();
    const binding = this.#projects.get(selection);
    if (!binding || binding.generation !== this.#generation) throw failure('Project selection is foreign or stale.');
    const { scope, semantic } = options;
    if (!['primary', 'complete'].includes(scope) || !['none', 'projection'].includes(semantic))
      throw failure('Invalid capture options.');
    return this.#run('morphir.model-originals.capture', { contractVersion: version,
      source: { providerId: binding.source.providerId.value, locator: binding.source.locator.value }, projectId: binding.projectId.value,
      scope, semantic }, (_result, exchange) => exchange, true);
  }
  close(): void {
    if (this.#state === 'closed') return;
    this.#state = 'closed';
    this.#signal.removeEventListener('abort', this.#cancelled);
    this.#channel.close();
    // An observer cannot prevent teardown or create authority by throwing.
    try { this.#observe?.(Object.freeze({ kind: 'closed' })); } catch { /* Teardown already completed. */ }
  }
}
