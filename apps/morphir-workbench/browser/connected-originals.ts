import type {RpcSocket} from '../../../pkgs/morphir-host/artifact-client/contracts.ts';
import type {WorkResult} from './contracts.ts';
import {productObservation} from './product-observer.ts';
import {
  ModelOriginalsConnectionLimits, openModelOriginalsSession,
  type ModelOriginalsProject, type ModelOriginalsSession, type ModelOriginalsSource,
} from './model-originals-session.ts';
import {
  receiveOriginals, receiveOriginalsWithProjection,
  type Capture, type Entry, type Hasher, type OriginalSink, type ReceivedProjection, type VerifiedProjection,
} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';

export interface OriginalPayload {
  readonly files: readonly Readonly<{path: string; bytes: Uint8Array}>[];
  readonly directories: readonly string[];
  readonly sourceFormatVersion: Capture['sourceFormatVersion'];
}
export type ConnectedOriginalsOpening = OwnedOpening;
export type ConnectedModelOpening = OwnedOpening;
export type StagedOriginals = OriginalsStage;
export type PendingOriginalInspection = OwnedPendingInspection;
type OpeningEvent =
  | Readonly<{kind: 'sources' | 'projects'; opening: ConnectedOriginalsOpening}>
  | Readonly<{kind: 'failed'; opening: ConnectedOriginalsOpening; message: string}>;
export type ConnectedOriginalsEvent = OpeningEvent
  | Readonly<{kind: 'received'; opening: ConnectedOriginalsOpening; stage: StagedOriginals}>;
type ModelDelivery =
  | Readonly<{kind: 'inspection'; opening: ConnectedModelOpening; stage: PendingOriginalInspection}>
  | Readonly<{kind: 'received'; opening: ConnectedModelOpening; stage: RetainedOriginalsStage; inspectionMessage: string}>;
export type ConnectedModelEvent = OpeningEvent | ModelDelivery;
export type InspectionPendingBoundary = Readonly<{kind: 'inspection-pending'; stage: PendingOriginalInspection}>
  | Readonly<{kind: 'originals-only' | 'retired' | 'failed'}>;
export type OpeningSettlement = Readonly<{kind: 'stored' | 'retired' | 'failed'}>;
export type ConnectedChoiceOutcome = Readonly<{kind:
  'source-selected' | 'project-selected' | 'not-ready' | 'unavailable' | 'other-selection' | 'retired' | 'replaced'}>;
export type ChoiceActivation = (actualIndex: number, actualCount: number) => 'clicked' | 'unavailable';
type ObservedChoice = Readonly<{kind: 'source'; value: ModelOriginalsSource}>
  | Readonly<{kind: 'project'; value: ModelOriginalsProject}>;
type PendingChoice = Readonly<{expected: ObservedChoice; resolve: (outcome: ConnectedChoiceOutcome) => void}>;
interface CommonOptions {
  base: URL;
  limits: ModelOriginalsConnectionLimits;
  makeHash: () => Hasher;
  /** The caller's actual opening attempt and workspace must still be current. */
  current: () => boolean;
  fetch?: (input: URL, init: RequestInit) => Promise<Response>;
  createSocket?: (url: string) => RpcSocket;
}
interface Options extends CommonOptions {
  /** Queue delivery only. The current handler decides whether to take the stage. */
  receive: (event: ConnectedOriginalsEvent) => void;
}
interface ModelOptions extends CommonOptions {
  recognizeHeader: (actualBytes: Uint8Array) => string;
  receive: (event: ConnectedModelEvent) => void;
}
type OpeningOptions = (Options & {kind: 'originals'}) | (ModelOptions & {kind: 'model'});
type ModelBoundaries = Readonly<{
  pending: Promise<InspectionPendingBoundary>; pendingFinished: (outcome: InspectionPendingBoundary) => void;
  settled: Promise<OpeningSettlement>; settledFinished: (outcome: OpeningSettlement) => void;
}>;
function modelBoundaries(): ModelBoundaries {
  let pendingFinished!: ModelBoundaries['pendingFinished'], settledFinished!: ModelBoundaries['settledFinished'];
  const pending = new Promise<InspectionPendingBoundary>(resolve => {pendingFinished = resolve;});
  const settled = new Promise<OpeningSettlement>(resolve => {settledFinished = resolve;});
  return Object.freeze({pending, pendingFinished, settled, settledFinished});
}
type Selection = {session: ModelOriginalsSession; source: ModelOriginalsSource};
type State =
  | {kind: 'discovering'}
  | {kind: 'sources'; session: ModelOriginalsSession}
  | ({kind: 'opening'} & Selection)
  | ({kind: 'projects'; projects: readonly ModelOriginalsProject[]} & Selection)
  | ({kind: 'receiving'; project: ModelOriginalsProject} & Selection)
  | ({kind: 'queued'; project: ModelOriginalsProject; stage: StagedOriginals | RetainedOriginalsStage} & Selection)
  | ({kind: 'inspection'; project: ModelOriginalsProject; stage: PendingOriginalInspection} & Selection)
  | {kind: 'failed'} | {kind: 'retired'};
const construction = Symbol('connected-originals-owner');
const noChoiceIdentity: readonly string[] = Object.freeze([]);

/** Create only after the domain has accepted an opening and checked retention. */
export function openConnectedOriginals(options: Options): ConnectedOriginalsOpening {
  return new OwnedOpening(construction, {...options, kind: 'originals', base: new URL(options.base.href)});
}
/** The domain must accept this distinct complete/projection opening first. */
export function openConnectedModel(options: ModelOptions): ConnectedModelOpening {
  return new OwnedOpening(construction, {...options, kind: 'model', base: new URL(options.base.href)});
}

class OwnedOpening {
  readonly #options: OpeningOptions;
  readonly #boundaries: ModelBoundaries | undefined;
  readonly #abort = new AbortController();
  #state: State = {kind: 'discovering'};
  #pending: Promise<void>;
  #removeSocketListener: (() => void) | undefined;
  #choice: PendingChoice | undefined;

  constructor(token: typeof construction, options: OpeningOptions) {
    if (token !== construction) throw new Error('Use the connected originals opening factory.');
    this.#options = options;
    this.#boundaries = options.kind === 'model' ? modelBoundaries() : undefined;
    // Give the caller its owned handle before the first network effect/delivery.
    this.#pending = Promise.resolve().then(() => this.#discover());
  }
  view(): State['kind'] { return this.#state.kind; }
  sourceNames(): readonly string[] {
    return this.#state.kind === 'sources' ? this.#state.session.sources.map(source => source.displayName) : [];
  }
  projectNames(): readonly string[] {
    return this.#state.kind === 'projects' ? this.#state.projects.map(project => project.name) : [];
  }
  /** DOM correspondence only. Selection still uses the actual nominal row. */
  sourceIdentity(index: number): readonly string[] {
    if (this.#state.kind !== 'sources' || !Number.isSafeInteger(index)) return noChoiceIdentity;
    const source = this.#state.session.sources[index];
    return source ? Object.freeze([source.providerId, source.locator]) : noChoiceIdentity;
  }
  projectIdentity(index: number): readonly string[] {
    if (this.#state.kind !== 'projects' || !Number.isSafeInteger(index)) return noChoiceIdentity;
    const project = this.#state.projects[index];
    return project ? Object.freeze([project.projectId]) : noChoiceIdentity;
  }
  /** Trusted UI adapter only: arm before a genuine click. The fixed driver port
   * never receives this callback. Its result is resolved by actual selection,
   * not by activation returning successfully. */
  async observeSourceChoice(providerId: string, locator: string, activate: ChoiceActivation): Promise<ConnectedChoiceOutcome> {
    if (!this.#active()) return {kind: 'retired'};
    if (this.#state.kind !== 'sources') return {kind: 'not-ready'};
    const index = this.#state.session.sources.findIndex(source => source.providerId === providerId && source.locator === locator);
    const source = this.#state.session.sources[index];
    if (!source) return {kind: 'unavailable'};
    return this.#observeChoice({kind: 'source', value: source}, index, this.#state.session.sources.length, activate);
  }
  async observeProjectChoice(projectId: string, activate: ChoiceActivation): Promise<ConnectedChoiceOutcome> {
    if (!this.#active()) return {kind: 'retired'};
    if (this.#state.kind !== 'projects') return {kind: 'not-ready'};
    const index = this.#state.projects.findIndex(project => project.projectId === projectId);
    const project = this.#state.projects[index];
    if (!project) return {kind: 'unavailable'};
    return this.#observeChoice({kind: 'project', value: project}, index, this.#state.projects.length, activate);
  }
  async #observeChoice(expected: ObservedChoice, index: number, count: number, activate: ChoiceActivation): Promise<ConnectedChoiceOutcome> {
    if (this.#choice) throw new Error('Observed choice already outstanding.');
    let resolve!: PendingChoice['resolve'];
    const outcome = new Promise<ConnectedChoiceOutcome>(finish => {resolve = finish;});
    const pending = {expected, resolve}; this.#choice = pending;
    try {
      if (activate(index, count) === 'unavailable' && this.#choice === pending) {
        this.#choice = undefined; resolve({kind: 'unavailable'});
      }
    } catch (error) {if (this.#choice === pending) this.#choice = undefined; throw error;}
    return outcome;
  }
  #acceptedChoice(actual: ObservedChoice): void {
    const pending = this.#choice;
    if (!pending) return;
    this.#choice = undefined;
    pending.resolve({kind: pending.expected.kind === actual.kind && pending.expected.value === actual.value
      ? actual.kind === 'source' ? 'source-selected' : 'project-selected' : 'other-selection'});
  }
  cancelObservedChoice(kind: 'retired' | 'replaced'): void {
    const pending = this.#choice; this.#choice = undefined;
    pending?.resolve({kind});
  }
  /** Settles the operation currently in flight, without manufacturing a host join. */
  whenSettled(): Promise<void> { return this.#pending; }
  /** Logical application boundaries only, never physical source/socket joins. */
  whenInspectionPending(): Promise<InspectionPendingBoundary> {
    return this.#boundaries?.pending ?? Promise.resolve({kind: 'originals-only'});
  }
  whenOpeningSettled(): Promise<OpeningSettlement> {
    if (!this.#boundaries) throw new PendingInspectionFailure('not-model-opening');
    return this.#boundaries.settled;
  }
  get currentPendingInspection(): PendingOriginalInspection | undefined {
    return this.#active() && this.#state.kind === 'inspection' && this.#state.stage.held() ? this.#state.stage : undefined;
  }
  holdInspection(stage: PendingOriginalInspection, enqueue: () => void, cancel: () => void): 'held' | 'ignored' {
    if (!this.#active() || this.#state.kind !== 'inspection' || this.#state.stage !== stage) return 'ignored';
    return stage.hold(enqueue, cancel);
  }
  settleOriginals(): 'settled' | 'ignored' {
    if (!this.#active() || this.#options.kind !== 'model' || this.#state.kind !== 'queued' ||
        !(this.#state.stage instanceof RetainedOriginalsStage) || this.#state.stage.markStored() !== 'stored') return 'ignored';
    this.#stored(); return 'settled';
  }
  #stored(): void {
    this.#boundaries?.settledFinished({kind: 'stored'});
    this.dispose();
  }

  #current(): boolean {
    if (this.#state.kind === 'retired' || this.#state.kind === 'failed' || this.#abort.signal.aborted) return false;
    try { return this.#options.current(); } catch { return false; }
  }
  #active(): boolean {
    if (this.#current()) return true;
    this.dispose(); return false;
  }
  #deliver(event: OpeningEvent): void {
    if (!this.#active()) return;
    try { this.#options.receive(event); }
    catch { this.dispose(); }
  }
  #deliverOriginals(stage: StagedOriginals): void {
    if (!this.#active() || this.#options.kind !== 'originals') return;
    try {this.#options.receive({kind: 'received', opening: this, stage});} catch {this.dispose();}
  }
  #deliverModel(event: ModelDelivery): void {
    if (!this.#active() || this.#options.kind !== 'model') return;
    try {this.#options.receive(event);} catch {this.dispose();}
  }
  #finish(kind: 'retired' | 'failed'): void {
    const previous = this.#state;
    this.#state = {kind};
    const choice = this.#choice; this.#choice = undefined; choice?.resolve({kind: 'retired'});
    this.#boundaries?.pendingFinished({kind}); this.#boundaries?.settledFinished({kind});
    this.#removeSocketListener?.(); this.#removeSocketListener = undefined;
    // Set the terminal state first: abort/close can synchronously call listeners.
    this.#abort.abort();
    if ('session' in previous) previous.session.close();
    if (previous.kind === 'queued' || previous.kind === 'inspection') previous.stage.dispose();
  }
  dispose(): void {
    if (this.#state.kind !== 'retired') this.#finish('retired');
  }
  #failed(cause: unknown): void {
    if (!this.#current()) { if (this.#state.kind !== 'failed') this.dispose(); return; }
    this.#finish('failed');
    try { this.#options.receive({kind: 'failed', opening: this,
      message: cause instanceof Error ? cause.message : 'Unable to open model originals.'}); }
    catch { this.dispose(); }
  }
  #socket(url: string): RpcSocket {
    const socket = (this.#options.createSocket ?? (url => new WebSocket(url)))(url);
    const closed = () => this.#failed(new Error('The model source connection closed.'));
    socket.addEventListener('close', closed);
    socket.addEventListener('error', closed);
    this.#removeSocketListener = () => {
      socket.removeEventListener('close', closed); socket.removeEventListener('error', closed);
    };
    return socket;
  }
  async #discover(): Promise<void> {
    if (!this.#active()) return;
    try {
      const opened = await openModelOriginalsSession(this.#options.base, {
        limits: this.#options.limits,
        signal: this.#abort.signal, fetch: this.#options.fetch, createSocket: url => this.#socket(url),
      });
      if (opened.kind !== 'ready') throw new Error('This host does not offer model originals.');
      if (!this.#active()) { opened.session.close(); return; }
      this.#state = {kind: 'sources', session: opened.session};
      this.#deliver({kind: 'sources', opening: this});
    } catch (cause) { this.#failed(cause); }
  }
  chooseSource(index: number): 'started' | 'ignored' {
    if (!this.#active() || this.#state.kind !== 'sources' || !Number.isSafeInteger(index)) return 'ignored';
    const source = this.#state.session.sources[index];
    if (!source) return 'ignored';
    const selection = {session: this.#state.session, source};
    this.#state = {kind: 'opening', ...selection};
    this.#acceptedChoice({kind: 'source', value: source});
    productObservation.selected(this, 'source-selected', selection.session, source);
    this.#pending = this.#projects(selection);
    return 'started';
  }
  async #projects(selection: Selection): Promise<void> {
    try {
      const projects = await selection.session.openSource(selection.source);
      if (!this.#active()) return;
      this.#state = {kind: 'projects', ...selection, projects};
      this.#deliver({kind: 'projects', opening: this});
    } catch (cause) { this.#failed(cause); }
  }
  chooseProject(index: number): 'started' | 'ignored' {
    if (!this.#active() || this.#state.kind !== 'projects' || !Number.isSafeInteger(index)) return 'ignored';
    const project = this.#state.projects[index];
    if (!project) return 'ignored';
    const selection = {session: this.#state.session, source: this.#state.source, project};
    this.#state = {kind: 'receiving', ...selection};
    this.#acceptedChoice({kind: 'project', value: project});
    productObservation.selected(this, 'project-selected', selection.session, selection.source, project);
    this.#pending = this.#receive(selection);
    return 'started';
  }
  async #receive(selection: Selection & {project: ModelOriginalsProject}): Promise<void> {
    const sink = new StagingSink();
    try {
      const binding = {
        sessionId: selection.session.sessionId,
        source: {providerId: selection.source.providerId, locator: selection.source.locator}, projectId: selection.project.projectId,
      };
      if (this.#options.kind === 'model') {
        const result = await receiveOriginalsWithProjection(selection.session, selection.project, binding,
          sink, this.#options.makeHash, () => this.#current(), this.#options.recognizeHeader);
        if (!this.#active()) return;
        productObservation.selected(this, 'transfer-verified', selection.session, selection.source, selection.project);
        const payload = sink.finish(result.capture);
        if (result.projection.kind === 'verified') {
          const stage = OwnedPendingInspection.create(construction, payload, result.projection.value,
            () => this.#current() && this.#state.kind === 'inspection' && this.#state.stage === stage,
            () => {if (this.#state.kind === 'inspection' && this.#state.stage === stage) this.dispose();},
            () => this.#boundaries!.pendingFinished({kind: 'inspection-pending', stage}),
            () => this.#stored());
          this.#state = {kind: 'inspection', ...selection, stage};
          this.#deliverModel({kind: 'inspection', opening: this, stage});
        } else {
          const stage = RetainedOriginalsStage.create(construction, payload,
            () => this.#current() && this.#state.kind === 'queued' && this.#state.stage === stage,
            () => {if (this.#state.kind === 'queued' && this.#state.stage === stage) this.dispose();});
          this.#state = {kind: 'queued', ...selection, stage};
          this.#boundaries!.pendingFinished({kind: 'originals-only'});
          this.#deliverModel({kind: 'received', opening: this, stage, inspectionMessage: inspectionMessage(result.projection)});
        }
        return;
      }
      const result = await receiveOriginals(selection.session, selection.project, binding,
        sink, this.#options.makeHash, () => this.#current());
      if (!this.#active()) return;
      productObservation.selected(this, 'transfer-verified', selection.session, selection.source, selection.project);
      const stage = new OriginalsStage(construction, sink.finish(result.capture),
        () => this.#current() && this.#state.kind === 'queued' && this.#state.stage === stage,
        () => {
          if (this.#state.kind === 'queued' && this.#state.stage === stage) this.dispose();
        });
      this.#state = {kind: 'queued', ...selection, stage};
      // Do not retire in finally: queued delivery has not adopted the originals.
      this.#deliverOriginals(stage);
    } catch (cause) { this.#failed(cause); }
    finally { sink.clear(); }
  }
}

function inspectionMessage(projection: Exclude<ReceivedProjection, {kind: 'verified'}>): string {
  if (projection.kind === 'unavailable') return `Model inspection is unavailable (${projection.reason}). Original files remain available.`;
  switch (projection.reason) {
    case 'transfer-invalid': return 'The semantic projection could not be verified. Original files remain available.';
    case 'header-invalid': return 'The semantic projection header is invalid. Original files remain available.';
    case 'header-mismatch': return 'The semantic projection header does not match its descriptor. Original files remain available.';
  }
}

export class PendingInspectionFailure extends Error {
  constructor(readonly code: 'stale' | 'not-enqueued' | 'already-inspected' | 'not-model-opening') {
    super(code); this.name = 'PendingInspectionFailure'; Object.freeze(this);
  }
}
type InspectionState =
  | {kind: 'available'; payload: OriginalPayload; projection: VerifiedProjection}
  | {kind: 'taken'; projection: VerifiedProjection}
  | {kind: 'held'; projection: VerifiedProjection; enqueue: () => void; cancel: () => void}
  | {kind: 'enqueued'; projection: VerifiedProjection; cancel: () => void}
  | {kind: 'inspecting'; cancel: () => void}
  | {kind: 'awaiting-adoption' | 'retired'};

/** A genuine production inspection Cmd is held before enqueue. This logical
 * owner cannot prove fresh source authority, model storage or physical joins.
 */
class OwnedPendingInspection {
  #state: InspectionState;
  readonly #current: () => boolean;
  readonly #retire: () => void;
  readonly #held: () => void;
  readonly #stored: () => void;
  private constructor(token: typeof construction, payload: OriginalPayload, projection: VerifiedProjection,
    current: () => boolean, retire: () => void, held: () => void, stored: () => void) {
    if (token !== construction) throw new Error('Only a verified model opening can stage inspection.');
    this.#state = {kind: 'available', payload, projection};
    this.#current = current; this.#retire = retire; this.#held = held; this.#stored = stored;
  }
  static create(token: typeof construction, payload: OriginalPayload, projection: VerifiedProjection,
    current: () => boolean, retire: () => void, held: () => void, stored: () => void): OwnedPendingInspection {
    return new OwnedPendingInspection(token, payload, projection, current, retire, held, stored);
  }
  current(): boolean {return this.#state.kind !== 'retired' && this.#current();}
  held(): boolean {return this.#state.kind === 'held' && this.current();}
  #active(): boolean {if (this.current()) return true; this.dispose(); return false;}
  take(adoptOriginals: (payload: OriginalPayload) => void): 'taken' | 'stale' {
    if (!this.#active() || this.#state.kind !== 'available') return 'stale';
    const {payload, projection} = this.#state;
    this.#state = {kind: 'taken', projection};
    try {adoptOriginals(payload); return 'taken';} catch (error) {this.dispose(); throw error;}
  }
  hold(enqueue: () => void, cancel: () => void): 'held' | 'ignored' {
    if (!this.#active() || this.#state.kind !== 'taken') return 'ignored';
    this.#state = {kind: 'held', projection: this.#state.projection, enqueue, cancel};
    this.#held(); return 'held';
  }
  executePendingCore(): 'enqueued' | 'ignored' {
    if (!this.#active() || this.#state.kind !== 'held') return 'ignored';
    const {projection, enqueue, cancel} = this.#state;
    // Consume before reentrant scheduler callbacks or an enqueue exception.
    this.#state = {kind: 'enqueued', projection, cancel};
    try {enqueue();} catch (error) {this.dispose(); throw error;}
    return 'enqueued';
  }
  async inspect(perform: (projection: VerifiedProjection) => Promise<WorkResult>): Promise<WorkResult> {
    if (!this.#active()) throw new PendingInspectionFailure('stale');
    if (this.#state.kind !== 'enqueued') throw new PendingInspectionFailure(
      this.#state.kind === 'inspecting' || this.#state.kind === 'awaiting-adoption' ? 'already-inspected' : 'not-enqueued');
    const {projection, cancel} = this.#state;
    this.#state = {kind: 'inspecting', cancel};
    try {
      const result = await perform(projection);
      if (this.#state.kind === 'inspecting' && this.#active()) this.#state = {kind: 'awaiting-adoption'};
      return result;
    } catch (error) {
      if (this.#state.kind === 'inspecting' && this.#active()) this.#state = {kind: 'awaiting-adoption'};
      throw error;
    }
  }
  /** Only the application's returned post-store Cmd calls this method. */
  settle(): 'settled' | 'ignored' {
    if (!this.#active() || this.#state.kind !== 'awaiting-adoption') return 'ignored';
    this.#state = {kind: 'retired'}; this.#stored(); return 'settled';
  }
  dispose(): void {
    const previous = this.#state;
    if (previous.kind === 'retired') return;
    this.#state = {kind: 'retired'};
    try {
      if (previous.kind === 'held' || previous.kind === 'enqueued' || previous.kind === 'inspecting') {
        try {previous.cancel();} catch { /* Cancellation cannot revive ownership or replace the actual operation error. */ }
      }
    } finally {this.#retire();}
  }
}

type RetainedOriginalsState = {kind: 'available'; payload: OriginalPayload} | {kind: 'taken' | 'stored' | 'retired'};
/** Model-mode fallback keeps its opening alive until actual domain storage. */
class RetainedOriginalsStage {
  #state: RetainedOriginalsState;
  readonly #current: () => boolean;
  readonly #retire: () => void;
  private constructor(token: typeof construction, payload: OriginalPayload, current: () => boolean, retire: () => void) {
    if (token !== construction) throw new Error('Only a verified opening can retain originals.');
    this.#state = {kind: 'available', payload}; this.#current = current; this.#retire = retire;
  }
  static create(token: typeof construction, payload: OriginalPayload, current: () => boolean, retire: () => void): RetainedOriginalsStage {
    return new RetainedOriginalsStage(token, payload, current, retire);
  }
  current(): boolean {return this.#state.kind !== 'retired' && this.#state.kind !== 'stored' && this.#current();}
  take(adopt: (payload: OriginalPayload) => void): 'taken' | 'stale' {
    if (!this.current()) {this.dispose(); return 'stale';}
    if (this.#state.kind !== 'available') return 'stale';
    const {payload} = this.#state; this.#state = {kind: 'taken'};
    try {adopt(payload); return 'taken';} catch (error) {this.dispose(); throw error;}
  }
  markStored(): 'stored' | 'ignored' {
    if (!this.current() || this.#state.kind !== 'taken') return 'ignored';
    this.#state = {kind: 'stored'}; return 'stored';
  }
  dispose(): void {
    if (this.#state.kind === 'retired' || this.#state.kind === 'stored') return;
    this.#state = {kind: 'retired'}; this.#retire();
  }
}

class OriginalsStage {
  #payload: OriginalPayload | undefined;
  readonly #current: () => boolean;
  readonly #retire: () => void;
  constructor(token: typeof construction, payload: OriginalPayload, current: () => boolean, retire: () => void) {
    if (token !== construction) throw new Error('Only a verified opening can stage originals.');
    this.#payload = payload; this.#current = current; this.#retire = retire;
  }
  current(): boolean { return this.#payload !== undefined && this.#current(); }
  take(adopt: (payload: OriginalPayload) => void): 'taken' | 'stale' {
    if (!this.current()) { this.dispose(); return 'stale'; }
    const payload = this.#payload!;
    // Consume before callback so duplicate/reentrant delivery cannot adopt twice.
    this.#payload = undefined;
    try { adopt(payload); return 'taken'; } finally { this.#retire(); }
  }
  dispose(): void {
    if (this.#payload === undefined) return;
    this.#payload = undefined; this.#retire();
  }
}

class StagingSink implements OriginalSink {
  #entries: readonly Entry[] = [];
  #files: {path: string; bytes: Uint8Array}[] = [];
  #directories: string[] = [];
  #writing: {path: string; bytes: Uint8Array; offset: number} | undefined;
  inventory(entries: readonly Entry[]): void {
    this.#entries = entries;
    this.#directories = entries.filter(entry => entry.kind === 'directory').map(entry => entry.path);
  }
  begin(index: number): void {
    const entry = this.#entries[index];
    if (this.#writing || entry?.kind !== 'file') throw new Error('Invalid originals sink entry.');
    this.#writing = {path: entry.path, bytes: new Uint8Array(entry.byteLength), offset: 0};
  }
  write(bytes: Uint8Array): void {
    const writing = this.#writing;
    if (!writing || bytes.length > writing.bytes.length - writing.offset) throw new Error('Invalid originals sink write.');
    writing.bytes.set(bytes, writing.offset); writing.offset += bytes.length;
  }
  end(): void {
    const writing = this.#writing;
    if (!writing || writing.offset !== writing.bytes.length) throw new Error('Incomplete original bytes.');
    this.#files.push({path: writing.path, bytes: writing.bytes}); this.#writing = undefined;
  }
  finish(capture: Capture): OriginalPayload {
    if (this.#writing || this.#files.length !== capture.fileCount || this.#directories.length !== capture.directoryCount)
      throw new Error('Incomplete originals sink.');
    return {files: this.#files, directories: this.#directories, sourceFormatVersion: capture.sourceFormatVersion};
  }
  clear(): void { this.#entries = []; this.#files = []; this.#directories = []; this.#writing = undefined; }
}
