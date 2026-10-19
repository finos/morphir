import { unzipSync } from 'fflate';
import type { Json as RuntimeJson } from '../../../types/data.ts';
import { isRecord, workbenchError } from '../../../types/data.ts';
import { ArtifactTransferAttempt, ArtifactTransferProtocolError, ArtifactInputError,
  type ArtifactExchange, type ArtifactGenerationInput, type ArtifactTransferEffects,
  type ArtifactTransferResult } from './artifact-transfer.ts';
import { ArtifactVerificationError } from './verified-artifacts.ts';
import { ArtifactDownloadRegistry } from './artifact-registry.ts';
import { artifactBytes, projectArchive } from './artifact-download.ts';
import { selectArtifactTransferProfile } from './artifact-client/artifact-transfer.ts';
import { wellFormed } from './artifact-client/artifact-wire.ts';
import type { Artifact } from './contracts.ts';
import type * as C from './artifact-client-trace-contract.ts';

/** Controlled effects around production owners. No case IDs or expected output. */
const kinds: readonly C.EffectKind[] = ['connect', 'initialize', 'generate', 'read', 'digest', 'release'];
function count<T extends number>(value: number, maximum = Number.MAX_SAFE_INTEGER): T {
  if (!Number.isSafeInteger(value) || value < 0 || value > maximum) throw new Error('Invalid measured count.');
  return value as T;
}
function errorText(cause: unknown): C.BoundedText {
  let text = workbenchError(cause).message.slice(0, 512);
  const last = text.charCodeAt(text.length - 1);
  if (last >= 0xd800 && last <= 0xdbff) text = text.slice(0, -1);
  if (!wellFormed(text)) throw new Error('An infrastructure error has invalid Unicode.');
  return text as C.BoundedText;
}
async function measure(bytes: Uint8Array<ArrayBuffer>): Promise<C.MeasuredBytes> {
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  const sha256 = [...hash].map(byte => byte.toString(16).padStart(2, '0')).join('') as C.Sha256;
  return { byteLength: count(bytes.byteLength), sha256 };
}
async function measureText(text: string): Promise<C.MeasuredText> {
  return { utf16Length: count(text.length, 1048576), utf8: await measure(new TextEncoder().encode(text)) };
}
function failure(error: unknown): C.FailureEvidence {
  if (error instanceof ArtifactInputError) return { kind: 'input', reason: error.reason };
  if (error instanceof ArtifactTransferProtocolError) return { kind: 'protocol', failure: error.failure };
  if (error instanceof ArtifactVerificationError) return { kind: 'verification', reason: error.reason };
  return { kind: 'other', message: errorText(error) };
}
function cloneJson(value: C.Json): RuntimeJson {
  return JSON.parse(JSON.stringify(value)) as RuntimeJson;
}
function fileAlias(index: number): C.FileAlias { return `file-${count(index, 256)}` as C.FileAlias; }
function sameContext(a: C.LocalContext | null, b: C.LocalContext) {
  return a !== null && a.sourceId === b.sourceId && a.revision === b.revision && a.epoch === b.epoch;
}

/** Compress actual observed text, never reconstruct a request from its intent. */
function observedFrame(source: string): C.FrameSource {
  const segments: C.FrameSegment[] = [];
  const runs = /([\x00-\x7f])\1{63,}/g;
  let start = 0;
  for (const match of source.matchAll(runs)) {
    if (match.index > start) segments.push({ kind: 'literal', source: source.slice(start, match.index) });
    segments.push({ kind: 'repeat-ascii', byte: count(match[0].charCodeAt(0), 127), count: count(match[0].length) });
    start = match.index + match[0].length;
  }
  if (start < source.length) segments.push({ kind: 'literal', source: source.slice(start) });
  return segments.length > 0 && segments.length <= 32 && JSON.stringify(segments).length < source.length
    ? { kind: 'segments', segments } : { kind: 'text', source };
}
function expandFrame(frame: C.FrameSource): string {
  if (frame.kind === 'text') {
    if (new TextEncoder().encode(frame.source).byteLength > 131073) throw new Error('Oversized raw peer frame recipe.');
    return frame.source;
  }
  if (!frame.segments.length || frame.segments.length > 32) throw new Error('Invalid frame segment count.');
  let length = 0;
  for (const segment of frame.segments) {
    const size = segment.kind === 'literal' ? new TextEncoder().encode(segment.source).byteLength :
      count(segment.count, 131073);
    if (segment.kind === 'repeat-ascii') count(segment.byte, 127);
    length += size;
    if (length > 131073) throw new Error('Oversized raw peer frame recipe.');
  }
  return frame.segments.map(segment => segment.kind === 'literal' ? segment.source :
    String.fromCharCode(segment.byte).repeat(segment.count)).join('');
}
function recipeLength(recipe: C.ByteRecipe): number {
  if (recipe.kind === 'hex') {
    if (recipe.hex.length % 2 !== 0 || !/^[0-9a-f]*$/.test(recipe.hex)) throw new Error('Invalid byte recipe.');
    return count(recipe.hex.length / 2, 16777217);
  }
  if (recipe.kind === 'chunk-indexed-u8') count(recipe.seed, 255);
  if (recipe.kind === 'repeat-u8') count(recipe.byte, 255);
  return count(recipe.length, 16777217);
}
function expandBytes(recipe: C.ByteRecipe): Uint8Array<ArrayBuffer> {
  const length = recipeLength(recipe);
  if (recipe.kind === 'hex') return Uint8Array.from({ length }, (_, index) => Number.parseInt(recipe.hex.slice(index * 2, index * 2 + 2), 16));
  if (recipe.kind === 'repeat-u8') return new Uint8Array(length).fill(recipe.byte);
  return Uint8Array.from({ length }, (_, index) => recipe.kind === 'cycle-u8' ? index % 256 :
    (index % 256) ^ ((Math.floor(index / 65536) + recipe.seed) % 256));
}
function encode64(bytes: Uint8Array): string {
  let text = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) text += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  return btoa(text);
}
function inputSlot(input: { ir: RuntimeJson; options: RuntimeJson }, field: 'ir' | 'options', path: C.JsonPath) {
  let parent: RuntimeJson | { ir: RuntimeJson; options: RuntimeJson } = input;
  let key: string | number = field;
  if (path.length > 32) throw new Error('A local value path is too deep.');
  for (const step of path) {
    const child: RuntimeJson = (parent as Record<string | number, RuntimeJson>)[key]!;
    if (step.kind === 'index' ? !Array.isArray(child) || !Object.hasOwn(child, step.index) : !isRecord(child) || !Object.hasOwn(child, step.key)) {
      throw new Error('A local value path does not exist.');
    }
    parent = child as RuntimeJson[] | { [key: string]: RuntimeJson };
    key = step.kind === 'index' ? step.index : step.key;
  }
  const target = parent as Record<string | number, RuntimeJson>;
  return { parent, target, key };
}
function faultInput(input: { ir: RuntimeJson; options: RuntimeJson }, fault: C.LocalFault) {
  const { parent, target, key } = inputSlot(input, fault.field, fault.path);
  if (fault.kind === 'unpaired-surrogate-key') {
    if (Array.isArray(parent) || parent === input || typeof key !== 'string') throw new Error('A key fault requires an object member.');
    const value = target[key]!; delete target[key];
    Object.defineProperty(target, fault.unit === 'high' ? '\ud800' : '\udfff', { value, enumerable: true, configurable: true, writable: true });
  } else if (fault.kind === 'unpaired-surrogate-value') target[key] = fault.unit === 'high' ? '\ud800' : '\udfff';
  else if (fault.kind === 'nonfinite-number') target[key] = fault.value === 'nan' ? NaN : fault.value === 'positive-infinity' ? Infinity : -Infinity;
}

type Deferred<T> = { readonly promise: Promise<T>; readonly resolve: (value: T) => void; readonly reject: (cause: unknown) => void };
function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void; let reject!: (cause: unknown) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
type Held = { readonly index: C.EffectIndex; settled: boolean } & (
  { readonly kind: 'connect'; readonly deferred: Deferred<ArtifactExchange> } |
  { readonly kind: 'digest'; readonly deferred: Deferred<ArrayBuffer>; readonly bytes: ArrayBuffer } |
  { readonly kind: 'initialize' | 'generate' | 'read' | 'release'; readonly deferred: Deferred<string>; readonly source: string }
);
type State =
  | { kind: 'not-started' }
  | { kind: 'construction-refused'; failure: C.FailureEvidence }
  | { kind: 'running'; attempt: ArtifactTransferAttempt; result: ArtifactTransferResult | null };
class AttemptPort implements ArtifactExchange {
  readonly definition: C.AttemptDefinition;
  readonly caller: { sessionId: string; target: string; irVersion: string; ir: RuntimeJson; options: RuntimeJson };
  readonly effects: ArtifactTransferEffects;
  readonly held: Held[] = [];
  readonly events: Promise<C.ClientEvent>[];
  readonly current: () => C.LocalContext | null;
  state: State = { kind: 'not-started' };
  signal: AbortSignal | null = null;
  closed = false;
  closeCalls = 0;
  connected = false;
  cancelPending = 0;
  peerBytes: Uint8Array<ArrayBuffer>[] | null = null;
  constructor(definition: C.AttemptDefinition, current: () => C.LocalContext | null, events: Promise<C.ClientEvent>[]) {
    this.definition = definition; this.current = current; this.events = events;
    this.caller = { ...definition.input, ir: cloneJson(definition.input.ir), options: cloneJson(definition.input.options) };
    this.effects = {
      connect: signal => {
        this.signal = signal;
        const held = { kind: 'connect' as const, index: this.index(), settled: false, deferred: deferred<ArtifactExchange>() };
        this.held.push(held);
        this.event({ kind: 'effect', attempt: definition.id, index: held.index, effect: 'connect', argument: { signalAborted: signal.aborted } });
        return held.deferred.promise;
      },
      isCurrent: () => sameContext(this.current(), definition.context),
      digest: bytes => {
        if (this.events.length >= 4096) throw new Error('Artifact client event limit exceeded.');
        const held = { kind: 'digest' as const, index: this.index(), settled: false, deferred: deferred<ArrayBuffer>(), bytes };
        this.held.push(held);
        this.event(measure(new Uint8Array(bytes)).then(argument => ({ kind: 'effect', attempt: definition.id, index: held.index, effect: 'digest', argument })));
        return held.deferred.promise;
      },
    };
  }
  index(): C.EffectIndex { return count(this.held.length, 4095); }
  event(event: C.ClientEvent | Promise<C.ClientEvent>) {
    if (this.events.length >= 4096) throw new Error('Artifact client event limit exceeded.');
    this.events.push(Promise.resolve(event));
  }
  start() {
    if (this.state.kind !== 'not-started') throw new Error('An attempt starts once.');
    const selection = selectArtifactTransferProfile(this.definition.offer);
    if (!selection.ok) { this.state = { kind: 'construction-refused', failure: { kind: 'protocol', failure: selection.error } }; return; }
    for (const recipe of this.definition.localValues ?? []) {
      const { target, key } = inputSlot(this.caller, recipe.field, recipe.path);
      target[key] = String.fromCharCode(recipe.byte).repeat(recipe.count);
    }
    for (const fault of this.definition.localFaults) faultInput(this.caller, fault);
    let attempt: ArtifactTransferAttempt;
    try { attempt = new ArtifactTransferAttempt(selection.value, this.caller satisfies ArtifactGenerationInput, this.effects); }
    catch (error) { this.state = { kind: 'construction-refused', failure: failure(error) }; return; }
    const state: Extract<State, { kind: 'running' }> = { kind: 'running', attempt, result: null };
    this.state = state;
    void attempt.run().then(result => { state.result = result; });
  }
  exchange(source: string): Promise<string> {
    const request: unknown = JSON.parse(source);
    if (!isRecord(request)) throw new Error('Production sent an invalid request.');
    const kind = request.method === 'morphir.session.initialize' ? 'initialize' :
      request.method === 'morphir.artifacts.generate' ? 'generate' :
      request.method === 'morphir.artifacts.read' ? 'read' :
      request.method === 'morphir.artifacts.release' ? 'release' : null;
    if (kind === null) throw new Error('Production sent an unexpected method.');
    const held: Extract<Held, { source: string }> = { kind, index: this.index(), settled: false, source, deferred: deferred<string>() };
    this.held.push(held);
    this.event({ kind: 'effect', attempt: this.definition.id, index: held.index, effect: kind, argument: { frame: observedFrame(source) } });
    if (this.closed) {
      held.settled = true;
      this.event({ kind: 'settled', attempt: this.definition.id, index: held.index, settlement: 'rejected' });
      held.deferred.reject(new Error('The owned channel is closed.'));
    }
    return held.deferred.promise;
  }
  close() {
    // Count actual calls, even if a production owner incorrectly closes twice.
    ++this.closeCalls; this.closed = true;
    this.event({ kind: 'close', attempt: this.definition.id });
  }
  pending(ref: C.EffectRef): Held {
    const held = this.held[ref.index];
    if (!held || held.settled || held.kind !== ref.kind) throw new Error('The referenced effect is absent, settled or has a different kind.');
    return held;
  }
  async peer(held: Extract<Held, { source: string }>): Promise<string> {
    const request = JSON.parse(held.source) as { id: number; params: Record<string, unknown> };
    let result: unknown;
    if (held.kind === 'initialize') result = { protocolVersion: 1 };
    else if (held.kind === 'release') result = {};
    else {
      const peer = this.definition.peer;
      if (peer.kind === 'failed') {
        if (held.kind !== 'generate') throw new Error('A failed peer has no artifact bytes.');
        result = { profile: 'morphir/workbench/artifacts', contractVersion: '0.1.0-draft.1', status: 'failed', diagnostics: peer.diagnostics };
      } else {
        const bytes = this.peerBytes ??= peer.artifacts.map(file => expandBytes(file.content));
        if (held.kind === 'generate') {
          if (this.state.kind !== 'running') throw new Error('The peer has no captured attempt binding.');
          const capture = this.state.attempt.capture;
          const artifacts = await Promise.all(peer.artifacts.map(async (file, index) => ({ id: file.id, path: file.path, kind: file.kind,
            byteLength: bytes[index]!.byteLength, sha256: (await measure(bytes[index]!)).sha256 })));
          result = { profile: 'morphir/workbench/artifacts', contractVersion: '0.1.0-draft.1', status: 'ready',
            sessionId: capture.sessionId, providerId: capture.selection.providerId, target: capture.target, irVersion: capture.irVersion,
            generationId: peer.generationId, producer: peer.producer, artifacts, diagnostics: peer.diagnostics };
        } else {
          const index = peer.artifacts.findIndex(file => file.id === request.params.artifactId);
          if (index < 0) throw new Error('Production requested an unknown file.');
          const offset = count(Number(request.params.offset), bytes[index]!.byteLength);
          const maxBytes = count(Number(request.params.maxBytes), 65536);
          const content = bytes[index]!.subarray(offset, offset + maxBytes);
          result = { profile: 'morphir/workbench/artifacts', contractVersion: '0.1.0-draft.1', generationId: peer.generationId,
            artifactId: peer.artifacts[index]!.id, offset, nextOffset: offset + content.byteLength, content: encode64(content) };
        }
      }
    }
    return JSON.stringify({ jsonrpc: '2.0', id: request.id, result });
  }
}

/** Flush bounded promise continuations; never auto-deliver an effect or sleep. */
async function quiesce(ports: readonly AttemptPort[], events: readonly unknown[]) {
  let prior = ''; let idle = 0;
  for (let turn = 0; turn < 256; ++turn) {
    await Promise.resolve();
    const state = events.length + ':' + ports.map(port => [port.held.length, port.held.filter(effect => effect.settled).length,
      port.state.kind === 'running' ? port.state.attempt.phase + ':' + port.state.result?.kind : port.state.kind, port.cancelPending].join('/')).join(';');
    idle = state === prior ? idle + 1 : 0; prior = state;
    if (idle >= 16) return;
  }
  throw new Error('Artifact client did not reach bounded quiescence.');
}

/** Input has already passed the shared closed scenario schema and budget checks. */
export async function runArtifactClientScenario(input: C.ClientScenario): Promise<C.ClientEvidence> {
  if (!input.attempts.length || input.attempts.length > 4 || !input.actions.length || input.actions.length > 512) throw new Error('Invalid scenario bounds.');
  let peerBudget = 0;
  let localFrameWork = 0;
  for (const attempt of input.attempts) {
    let localBytes = 0;
    if ((attempt.localValues?.length ?? 0) > 4) throw new Error('Too many local value recipes.');
    for (const recipe of attempt.localValues ?? []) {
      if (recipe.kind !== 'repeat-ascii-value') throw new Error('Unknown local value recipe.');
      const byte = count(recipe.byte, 127);
      localBytes += count(recipe.count, 1048577);
      if (localBytes > 1048577) throw new Error('Local value expansion exceeds its bound.');
      const width = byte < 32 ? [8, 9, 10, 12, 13].includes(byte) ? 2 : 6 : byte === 34 || byte === 92 ? 2 : 1;
      localFrameWork += recipe.count * width;
      if (!Number.isSafeInteger(localFrameWork) || localFrameWork > 134217728) throw new Error('Local frame work exceeds its bound.');
    }
    peerBudget += localBytes;
    if (attempt.peer.kind === 'ready') {
      if (attempt.peer.artifacts.length > 257) throw new Error('Too many peer files.');
      let sum = 0;
      for (const file of attempt.peer.artifacts) sum += recipeLength(file.content);
      if (sum > 67108865) throw new Error('Peer bytes exceed the negative-fixture limit.');
      peerBudget += sum;
    }
  }
  if (peerBudget > 134217728) throw new Error('Peer expansion budget exceeded.');
  const events: Promise<C.ClientEvent>[] = [];
  let current: C.LocalContext | null = null;
  const ports = input.attempts.map(definition => new AttemptPort(definition, () => current, events));
  const byId = new Map(ports.map(port => [port.definition.id, port]));
  if (byId.size !== ports.length) throw new Error('Duplicate attempt identity.');
  const portFor = (id: C.AttemptId) => { const port = byId.get(id); if (!port) throw new Error('Unknown attempt.'); return port; };
  const registry = new ArtifactDownloadRegistry();
  const views = new Map<C.ViewId, { port: AttemptPort; artifacts: Artifact[] }>();
  const actualSetIds = new Set<string>();
  let activeViews: C.ViewId | null = null;
  const checkpoints: C.ClientCheckpoint[] = [];
  let observationBytes = 0;
  const chargeObservation = (length: number) => {
    observationBytes += count(length);
    if (!Number.isSafeInteger(observationBytes) || observationBytes > 134217728) throw new Error('Client observation work budget exceeded.');
  };
  function owner(port: AttemptPort) {
    if (port.state.kind !== 'running' || port.state.result?.kind !== 'verified') throw new Error('The attempt has no verified owner.');
    return port.state.result.files;
  }
  function select(selection: C.ViewSelection): Artifact[] {
    const view = views.get(selection.views); if (!view) throw new Error('Unknown view selection.');
    const selected = selection.indices.map(index => {
      const artifact = view.artifacts[index]; if (!artifact) throw new Error('Unknown selected file.');
      return structuredClone(artifact);
    });
    for (const mutation of selection.mutations) {
      const artifact = selected[mutation.index]; if (!artifact) throw new Error('Unknown mutated selection.');
      if (mutation.kind === 'path') artifact.path = mutation.path;
      else {
        const from = views.get(mutation.fromViews)?.artifacts[mutation.fromIndex];
        if (!from?.verifiedArtifact) throw new Error('Unknown foreign reference.');
        artifact.verifiedArtifact = structuredClone(from.verifiedArtifact);
      }
    }
    return selected;
  }
  async function deliver(port: AttemptPort, held: Held, delivery: C.Delivery) {
    if (held.kind === 'connect') {
      if (delivery.kind !== 'connect') throw new Error('A connection requires connect delivery.');
      held.settled = true; port.connected = true;
      port.event({ kind: 'settled', attempt: port.definition.id, index: held.index, settlement: 'resolved' });
      held.deferred.resolve(port);
    } else if (held.kind === 'digest') {
      if (delivery.kind !== 'digest' && delivery.kind !== 'digest-mutated-input') throw new Error('A hash requires digest delivery.');
      let result: ArrayBuffer;
      if (delivery.kind === 'digest-mutated-input') {
        const bytes = new Uint8Array(held.bytes); for (let index = 0; index < bytes.length; ++index) bytes[index] = bytes[index]! ^ delivery.xor;
        result = await crypto.subtle.digest('SHA-256', held.bytes);
      } else result = delivery.result === 'actual' ? await crypto.subtle.digest('SHA-256', held.bytes) : new ArrayBuffer(delivery.result === 'short-31' ? 31 : 32);
      held.settled = true;
      port.event({ kind: 'settled', attempt: port.definition.id, index: held.index, settlement: 'resolved' });
      held.deferred.resolve(result);
    } else {
      if (delivery.kind !== 'peer' && delivery.kind !== 'raw') throw new Error('A wire request requires a peer frame.');
      const result = delivery.kind === 'peer' ? await port.peer(held) : expandFrame(delivery.frame);
      held.settled = true;
      port.event({ kind: 'settled', attempt: port.definition.id, index: held.index, settlement: 'resolved' });
      held.deferred.resolve(result);
    }
  }
  for (const [actionIndex, action] of input.actions.entries()) {
    let actionResult: C.ActionResult = { kind: 'none' };
    switch (action.action) {
      case 'start': portFor(action.attempt).start(); break;
      case 'set-current': current = action.context; break;
      case 'deliver': { const port = portFor(action.effect.attempt); await deliver(port, port.pending(action.effect), action.value); break; }
      case 'reject': {
        const port = portFor(action.effect.attempt); const held = port.pending(action.effect); held.settled = true;
        port.event({ kind: 'settled', attempt: port.definition.id, index: held.index, settlement: 'rejected' });
        held.deferred.reject(new Error(action.message)); break;
      }
      case 'drain-reads': {
        const port = portFor(action.attempt); const maximum = count(action.maxReads, 4096);
        for (let read = 0; read < maximum; ++read) {
          const held = port.held.find(effect => !effect.settled);
          if (!held || held.kind !== 'read') break;
          await deliver(port, held, { kind: 'peer' }); await quiesce(ports, events);
        }
        if (port.held.some(effect => !effect.settled && effect.kind === 'read')) throw new Error('Read drain exceeded its declared bound.');
        break;
      }
      case 'replace-caller': portFor(action.attempt).caller[action.field] = cloneJson(action.value); break;
      case 'replace-effect-functions': {
        const effects = portFor(action.attempt).effects;
        effects.connect = async () => { throw new Error('Replaced connect function used.'); };
        Object.assign(effects, { isCurrent: () => { throw new Error('Replaced currentness function used.'); },
          digest: async () => { throw new Error('Replaced digest function used.'); } }); break;
      }
      case 'cancel': {
        const port = portFor(action.attempt); if (port.state.kind !== 'running') throw new Error('No attempt to cancel.');
        ++port.cancelPending;
        void port.state.attempt.cancel().then(cleanup => { --port.cancelPending; port.event({ kind: 'cancel-result', attempt: port.definition.id, cleanup }); }); break;
      }
      case 'close-channel': portFor(action.attempt).close(); break;
      case 'clear-registry': registry.clear(); activeViews = null; break;
      case 'publish': {
        const port = portFor(action.attempt);
        if (views.has(action.views)) throw new Error('A view identity is used once.');
        let files: ReturnType<typeof owner>; let artifacts: Artifact[];
        try {
          files = owner(port); artifacts = registry.publish(files);
        } catch (error) { actionResult = { kind: 'refused', operation: 'publish', message: errorText(error) }; break; }
        const setId = artifacts[0]?.verifiedArtifact?.setId;
        if (artifacts.length && (typeof setId !== 'string' || !setId || actualSetIds.has(setId))) throw new Error('Actual view-set identity is absent or reused.');
        if (setId !== undefined) actualSetIds.add(setId);
        views.set(action.views, { port, artifacts }); activeViews = action.views;
        const measured: C.ViewEvidence[] = [];
        for (const [index, artifact] of artifacts.entries()) {
          const descriptor = files.manifest.artifacts[index]!;
          if (artifact.path !== descriptor.path || artifact.verifiedArtifact?.artifactId !== descriptor.id ||
              artifact.verifiedArtifact.setId !== setId || artifact.encoding !== 'verified-bytes') throw new Error('Actual view binding mismatch.');
          const binaryPreview = artifact.previewBase64 === undefined ? null :
            await measure(Uint8Array.from(atob(artifact.previewBase64), character => character.charCodeAt(0)));
          measured.push({ file: fileAlias(index), path: artifact.path, binary: artifact.binary, encoding: artifact.encoding,
            byteLength: count(artifact.byteLength!), previewState: artifact.previewState!, content: await measureText(artifact.content),
            binaryPreview, reference: { views: action.views, file: fileAlias(index) } });
        }
        actionResult = { kind: 'published', views: action.views, artifacts: measured };
        break;
      }
      case 'mutate-copy': {
        try {
          const files = owner(portFor(action.attempt));
          const descriptor = files.manifest.artifacts.find((_, index) => fileAlias(index) === action.file);
          if (!descriptor || action.offset >= descriptor.byteLength) throw new Error('Unknown file-copy position.');
          chargeObservation(descriptor.byteLength);
          const bytes = files.bytes(descriptor.id); bytes[action.offset] = bytes[action.offset]! ^ action.xor;
        } catch (error) { actionResult = { kind: 'refused', operation: 'mutate-copy', message: errorText(error) }; }
        break;
      }
      case 'download': case 'archive': {
        const selection = select(action.views);
        chargeObservation(selection.reduce((total, artifact) => total + (artifact.byteLength ?? 0), 0));
        let output: Record<string, Uint8Array<ArrayBuffer>> | null = null;
        let archive: Uint8Array<ArrayBuffer> | null = null;
        try {
          if (action.action === 'archive') archive = projectArchive(selection, registry);
          else output = artifactBytes(selection, registry, action.complete);
        } catch (error) { actionResult = { kind: 'refused', operation: action.action, message: errorText(error) }; break; }
        // A malformed actual ZIP fails infrastructure qualification; it cannot
        // be reported as though production had refused a download.
        if (archive) output = Object.fromEntries(Object.entries(unzipSync(archive)).map(([path, bytes]) => [path, new Uint8Array(bytes)]));
        if (!output) throw new Error('No actual download output.');
        const measured = await Promise.all(Object.entries(output).map(async ([path, bytes]) => ({ path, bytes: await measure(bytes) })));
        actionResult = archive === null ? { kind: 'download', files: measured } :
          { kind: 'archive', archive: { encodedByteLength: count(archive.byteLength), entries: measured } };
        break;
      }
      case 'observe': break;
    }
    await quiesce(ports, events);
    const attempts: C.AttemptCheckpoint[] = ports.map(port => {
      const state = port.state;
      return { id: port.definition.id, phase: state.kind === 'running' ? state.attempt.phase : state.kind,
        pending: port.held.filter(effect => !effect.settled).map(effect => ({ index: effect.index, effect: effect.kind })),
        signalAborted: port.signal?.aborted ?? null,
        terminal: state.kind === 'running' ? state.result ? { kind: state.result.kind, cleanup: state.result.cleanup } : { kind: 'pending' } :
          state.kind === 'not-started' ? { kind: 'pending' } : { kind: 'construction-refused' }, closeCalls: count(port.closeCalls) };
    });
    checkpoints.push({ actionIndex: count(actionIndex, 511), eventCount: count(events.length, 4096), label: action.action === 'observe' ? action.label : null,
      currentContext: current, attempts, registry: activeViews === null ? { kind: 'empty' } : { kind: 'published', views: activeViews }, actionResult });
  }
  const attempts: C.AttemptEvidence[] = [];
  for (const port of ports) {
    const state = port.state;
    if (state.kind === 'not-started' || state.kind === 'running' && state.result === null || port.cancelPending ||
        port.held.some(effect => !effect.settled) || port.connected && !port.closed) throw new Error('Scenario left an unfinished attempt or owned resource.');
    const effects = Object.fromEntries(kinds.map(kind => [kind, count(port.held.filter(effect => effect.kind === kind).length)])) as C.CountsByEffectKind;
    if (state.kind === 'construction-refused') {
      attempts.push({ id: port.definition.id, capture: null, phase: 'construction-refused', result: { kind: 'construction-refused', failure: state.failure }, closeCalls: count(port.closeCalls), effects });
      continue;
    }
    if (state.kind !== 'running' || !state.result) throw new Error('Missing terminal result.');
    const capture = state.attempt.capture;
    const actual = state.result;
    let result: C.RunResult;
    if (actual.kind === 'verified') {
      const inventory: C.OwnedFileEvidence[] = [];
      for (const [index, descriptor] of actual.files.manifest.artifacts.entries()) {
        chargeObservation(descriptor.byteLength);
        const bytes = await measure(actual.files.bytes(descriptor.id)); const preview = actual.files.preview(descriptor.id);
        const measured: C.PreviewEvidence = preview.kind === 'text' || preview.kind === 'text-prefix' ? { kind: preview.kind, text: await measureText(preview.text) } :
          preview.kind === 'binary' ? { kind: 'binary', prefix: await measure(actual.files.previewBytes(descriptor.id)) } : { kind: 'invalid-utf8' };
        inventory.push({ id: fileAlias(index), path: descriptor.path, declaredKind: descriptor.kind, bytes, preview: measured });
      }
      const manifest = actual.files.manifest;
      result = { kind: 'verified', manifest: { profile: manifest.profile, contractVersion: manifest.contractVersion,
        sessionId: manifest.sessionId, providerId: manifest.providerId, generationId: manifest.generationId,
        producer: manifest.producer, target: manifest.target, irVersion: manifest.irVersion, diagnostics: manifest.diagnostics }, inventory, cleanup: actual.cleanup };
    } else if (actual.kind === 'failed') result = { kind: 'failed', failure: failure(actual.error), cleanup: actual.cleanup };
    else result = actual;
    attempts.push({ id: port.definition.id, capture: { ...capture.selection, sessionId: capture.sessionId, target: capture.target, irVersion: capture.irVersion },
      phase: state.attempt.phase, result, closeCalls: count(port.closeCalls), effects });
  }
  const evidence = { events: await Promise.all(events), checkpoints, attempts };
  if (new TextEncoder().encode(JSON.stringify(evidence)).byteLength > 1048576) throw new Error('Client evidence exceeds the shared observation bound.');
  return evidence;
}
