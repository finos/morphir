import type {RpcSocket} from '../../../pkgs/morphir-host/artifact-client/contracts.ts';
import {
  ModelOriginalsConnectionLimits, openModelOriginalsSession,
  type ModelOriginalsProject, type ModelOriginalsSession, type ModelOriginalsSource,
} from './model-originals-session.ts';
import {
  receiveOriginals, type Capture, type Entry, type Hasher, type OriginalSink,
} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';

export interface OriginalPayload {
  readonly files: readonly Readonly<{path: string; bytes: Uint8Array}>[];
  readonly directories: readonly string[];
  readonly sourceFormatVersion: Capture['sourceFormatVersion'];
}
export type ConnectedOriginalsOpening = OwnedOpening;
export type StagedOriginals = OriginalsStage;
export type ConnectedOriginalsEvent =
  | Readonly<{kind: 'sources' | 'projects'; opening: ConnectedOriginalsOpening}>
  | Readonly<{kind: 'received'; opening: ConnectedOriginalsOpening; stage: StagedOriginals}>
  | Readonly<{kind: 'failed'; opening: ConnectedOriginalsOpening; message: string}>;
interface Options {
  base: URL;
  limits: ModelOriginalsConnectionLimits;
  makeHash: () => Hasher;
  /** The caller's actual opening attempt and workspace must still be current. */
  current: () => boolean;
  /** Queue delivery only. The current handler decides whether to take the stage. */
  receive: (event: ConnectedOriginalsEvent) => void;
  fetch?: (input: URL, init: RequestInit) => Promise<Response>;
  createSocket?: (url: string) => RpcSocket;
}
type Selection = {session: ModelOriginalsSession; source: ModelOriginalsSource};
type State =
  | {kind: 'discovering'}
  | {kind: 'sources'; session: ModelOriginalsSession}
  | ({kind: 'opening'} & Selection)
  | ({kind: 'projects'; projects: readonly ModelOriginalsProject[]} & Selection)
  | ({kind: 'receiving'; project: ModelOriginalsProject} & Selection)
  | ({kind: 'queued'; project: ModelOriginalsProject; stage: StagedOriginals} & Selection)
  | {kind: 'failed'} | {kind: 'retired'};
const construction = Symbol('connected-originals-owner');

/** Create only after the domain has accepted an opening and checked retention. */
export function openConnectedOriginals(options: Options): ConnectedOriginalsOpening {
  return new OwnedOpening(construction, {...options, base: new URL(options.base.href)});
}

class OwnedOpening {
  readonly #options: Options;
  readonly #abort = new AbortController();
  #state: State = {kind: 'discovering'};
  #pending: Promise<void>;
  #removeSocketListener: (() => void) | undefined;

  constructor(token: typeof construction, options: Options) {
    if (token !== construction) throw new Error('Use the connected originals opening factory.');
    this.#options = options;
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
  /** Settles the operation currently in flight, without manufacturing a host join. */
  whenSettled(): Promise<void> { return this.#pending; }

  #current(): boolean {
    if (this.#state.kind === 'retired' || this.#state.kind === 'failed' || this.#abort.signal.aborted) return false;
    try { return this.#options.current(); } catch { return false; }
  }
  #active(): boolean {
    if (this.#current()) return true;
    this.dispose(); return false;
  }
  #deliver(event: ConnectedOriginalsEvent): void {
    if (!this.#active()) return;
    try { this.#options.receive(event); }
    catch { this.dispose(); }
  }
  #finish(kind: 'retired' | 'failed'): void {
    const previous = this.#state;
    this.#state = {kind};
    this.#removeSocketListener?.(); this.#removeSocketListener = undefined;
    // Set the terminal state first: abort/close can synchronously call listeners.
    this.#abort.abort();
    if ('session' in previous) previous.session.close();
    if (previous.kind === 'queued') previous.stage.dispose();
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
    this.#pending = this.#receive(selection);
    return 'started';
  }
  async #receive(selection: Selection & {project: ModelOriginalsProject}): Promise<void> {
    const sink = new StagingSink();
    try {
      const result = await receiveOriginals(selection.session, selection.project, {
        sessionId: selection.session.sessionId,
        source: {providerId: selection.source.providerId, locator: selection.source.locator}, projectId: selection.project.projectId,
      }, sink, this.#options.makeHash, () => this.#current());
      if (!this.#active()) return;
      const stage = new OriginalsStage(construction, sink.finish(result.capture),
        () => this.#current() && this.#state.kind === 'queued' && this.#state.stage === stage,
        () => {
          if (this.#state.kind === 'queued' && this.#state.stage === stage) this.dispose();
        });
      this.#state = {kind: 'queued', ...selection, stage};
      // Do not retire in finally: queued delivery has not adopted the originals.
      this.#deliver({kind: 'received', opening: this, stage});
    } catch (cause) { this.#failed(cause); }
    finally { sink.clear(); }
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
