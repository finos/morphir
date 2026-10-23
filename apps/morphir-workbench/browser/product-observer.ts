// Private product observations. No source, selection, download or host grants.
import type {ReadyOriginalArchive, ArchiveDownloadResult} from './originals-archive-contract.ts';
import type {ModelOriginalsSession, ModelOriginalsSource, ModelOriginalsProject} from './model-originals-session.ts';
export type ObservationState = Readonly<{kind: 'unobserved' | 'active' | 'closed'}>
  | Readonly<{kind: 'incomplete'; cause: 'sink-raised' | 'owner-limit' | 'event-limit' | 'owner-mismatch'}>;
export type ObservationLimits = Readonly<{owners: number; events: number}>;
type Visit = Readonly<{workspace: string; opening: number}>;
type Inventory = Visit & Readonly<{attempt: string; inventoryRevision: string; openingOrdinal: number}>;
type Archive = Inventory & Readonly<{operationOrdinal: number}>;
type Ready = Archive & Readonly<{readyOrdinal: number}>;
type DownloadResult = Readonly<{kind: 'returned'; result: 'download-requested' | 'retired' | 'failed'}>
  | Readonly<{kind: 'raised'}>;
export type ProductFact = Readonly<{sequence: number} & (
  | {kind: 'opening-stored'; actual: Visit & {attempt: string; openingOrdinal: number}}
  | {kind: 'source-selected'; actual: Visit & {attempt: string; openingOrdinal: number}; sessionId: string; providerId: string; locator: string}
  | {kind: 'project-selected' | 'transfer-verified'; actual: Visit & {attempt: string; openingOrdinal: number}; sessionId: string; providerId: string; locator: string; projectId: string}
  | {kind: 'inventory-adopted'; actual: Inventory}
  | {kind: 'archive-stored' | 'archive-retirement-requested' | 'archive-settled-retired'; actual: Archive}
  | {kind: 'archive-ready' | 'download-will-request'; actual: Ready}
  | {kind: 'download-result'; actual: Ready; outcome: DownloadResult}
  | {kind: 'model-closed' | 'workspace-closed'; actual: Visit}
)>;
type Opening = Visit & {attempt: string; openingOrdinal: number};
type WithoutSequence<T> = T extends unknown ? Omit<T, 'sequence'> : never;
type FactBody = WithoutSequence<ProductFact>;
type State = {kind: 'prepared'} | {kind: 'attached'; limits: ObservationLimits; sink: (fact: ProductFact) => void}
  | {kind: 'active'; limits: ObservationLimits; sink: (fact: ProductFact) => void}
  | {kind: 'unobserved' | 'closed'} | {kind: 'incomplete'; cause: Extract<ObservationState, {kind: 'incomplete'}>['cause']};

/** One document; explicit finite cumulative owner/event limits, no event history. */
export function createProductObservation(document: object) {
  let state: State = {kind: 'prepared'}, owners = 0, sequence = 0;
  let openings = new WeakMap<object, Opening>(), inventories = new Map<string, Inventory>();
  let archives = new WeakMap<object, Archive>(), readyArchives = new WeakMap<object, Ready>();
  const key = (workspace: string, opening: number, revision: string) => JSON.stringify([workspace, opening, revision]);
  function incomplete(cause: Extract<ObservationState, {kind: 'incomplete'}>['cause']) {
    state = {kind: 'incomplete', cause}; openings = new WeakMap(); inventories.clear(); archives = new WeakMap(); readyArchives = new WeakMap();
  }
  function allocate(): number | undefined {
    if (state.kind !== 'active') return;
    if (owners >= state.limits.owners || owners >= Number.MAX_SAFE_INTEGER) {incomplete('owner-limit'); return;}
    return ++owners;
  }
  // Internal fixed call sites only. No generic event publisher is exported.
  function publish(fact: FactBody) {
    if (state.kind !== 'active') return;
    if (sequence >= state.limits.events || sequence >= Number.MAX_SAFE_INTEGER) {incomplete('event-limit'); return;}
    const sink = state.sink;
    try {sink(Object.freeze({...fact, sequence: ++sequence}) as ProductFact);}
    catch {incomplete('sink-raised');}
  }
  const api = {
    attach(actual: object, limits: ObservationLimits, sink: (fact: ProductFact) => void): 'attached' | 'foreign-document' | 'already-attached' | 'late' {
      if (actual !== document) return 'foreign-document';
      if (state.kind === 'attached') return 'already-attached';
      if (state.kind !== 'prepared') return 'late';
      const ownerLimit = limits.owners, eventLimit = limits.events;
      for (const value of [ownerLimit, eventLimit]) if (!Number.isSafeInteger(value) || value < 0) throw new RangeError('Explicit finite observation limits required.');
      state = {kind: 'attached', limits: Object.freeze({owners: ownerLimit, events: eventLimit}), sink}; return 'attached';
    },
    start(actual: object): void {
      if (actual !== document) return;
      if (state.kind === 'attached') state = {...state, kind: 'active'};
      else if (state.kind === 'prepared') state = {kind: 'unobserved'};
    },
    state(): ObservationState {
      if (state.kind === 'incomplete') return {...state};
      return {kind: state.kind === 'active' ? 'active' : state.kind === 'closed' ? 'closed' : 'unobserved'};
    },
    close(): void {if (state.kind !== 'incomplete') state = {kind: 'closed'}; openings = new WeakMap(); inventories.clear(); archives = new WeakMap(); readyArchives = new WeakMap();},
    openingStored(owner: object, workspace: string, opening: number, attempt: string): void {
      if (state.kind !== 'active' || openings.has(owner)) return;
      const ordinal = allocate(); if (ordinal === undefined) return;
      const actual = Object.freeze({workspace, opening, attempt, openingOrdinal: ordinal});
      openings.set(owner, actual); publish({kind: 'opening-stored', actual});
    },
    selected(owner: object, kind: 'source-selected' | 'project-selected' | 'transfer-verified', session: ModelOriginalsSession, source: ModelOriginalsSource, project?: ModelOriginalsProject): void {
      if (state.kind !== 'active') return;
      const actual = openings.get(owner); if (!actual) {incomplete('owner-mismatch'); return;}
      const sessionId = session.sessionId;
      if (kind === 'source-selected') publish({kind, actual, sessionId, providerId: source.providerId, locator: source.locator});
      else if (project) publish({kind, actual, sessionId, providerId: source.providerId, locator: source.locator, projectId: project.projectId});
      else incomplete('owner-mismatch');
    },
    inventoryAdopted(owner: object, workspace: string, opening: number, attempt: string, inventoryRevision: string): void {
      if (state.kind !== 'active') return;
      const previous = openings.get(owner);
      if (!previous || previous.workspace !== workspace || previous.opening !== opening || previous.attempt !== attempt) {incomplete('owner-mismatch'); return;}
      if (allocate() === undefined) return;
      const actual = Object.freeze({...previous, inventoryRevision}); inventories.set(key(workspace, opening, inventoryRevision), actual);
      publish({kind: 'inventory-adopted', actual});
    },
    archiveStored(owner: object, workspace: string, opening: number, revision: string): void {
      if (state.kind !== 'active' || archives.has(owner)) return;
      const inventory = inventories.get(key(workspace, opening, revision));
      if (!inventory) {incomplete('owner-mismatch'); return;}
      const operationOrdinal = allocate(); if (operationOrdinal === undefined) return;
      const actual = Object.freeze({...inventory, operationOrdinal}); archives.set(owner, actual); publish({kind: 'archive-stored', actual});
    },
    archive(owner: object, kind: 'archive-retirement-requested' | 'archive-settled-retired'): void {
      if (state.kind !== 'active') return;
      const actual = archives.get(owner); if (!actual) {incomplete('owner-mismatch'); return;}
      publish({kind, actual});
    },
    ready(owner: object, ready: object): void {
      if (state.kind !== 'active' || readyArchives.has(ready)) return;
      const previous = archives.get(owner); if (!previous) {incomplete('owner-mismatch'); return;}
      const readyOrdinal = allocate(); if (readyOrdinal === undefined) return;
      const actual = Object.freeze({...previous, readyOrdinal}); readyArchives.set(ready, actual); publish({kind: 'archive-ready', actual});
    },
    downloadWill(owner: object, ready: object): void {
      if (state.kind !== 'active') return;
      const actual = readyArchives.get(ready), operation = archives.get(owner);
      if (!actual || !operation || actual.operationOrdinal !== operation.operationOrdinal) {incomplete('owner-mismatch'); return;}
      publish({kind: 'download-will-request', actual});
    },
    download(owner: object, ready: object, outcome: DownloadResult): void {
      if (state.kind !== 'active') return;
      const actual = readyArchives.get(ready), operation = archives.get(owner);
      if (!actual || !operation || actual.operationOrdinal !== operation.operationOrdinal) {incomplete('owner-mismatch'); return;}
      publish({kind: 'download-result', actual, outcome: Object.freeze({...outcome})});
    },
    requestDownload(operation: object, archive: ReadyOriginalArchive): ArchiveDownloadResult {
      api.downloadWill(operation, archive);
      try {
        const result = archive.requestDownload(); api.download(operation, archive, {kind: 'returned', result: result.kind}); return result;
      } catch (error) {api.download(operation, archive, {kind: 'raised'}); throw error;}
    },
    closed(workspace: string, opening: number, kind: 'model-closed' | 'workspace-closed'): void {
      publish({kind, actual: Object.freeze({workspace, opening})});
      for (const [id, inventory] of inventories) if (inventory.workspace === workspace && inventory.opening === opening) inventories.delete(id);
    },
  };
  return Object.freeze(api);
}

// Exactly one module instance is shared by generated MoonBit and both entries.
const realmDocument = (globalThis as {readonly document?: object}).document;
const scope = createProductObservation(realmDocument ?? {});
export const productObservation = scope;
export const openingStored = scope.openingStored;
export const inventoryAdopted = scope.inventoryAdopted;
export const archiveStored = scope.archiveStored;
export function modelClosed(workspace: string, opening: number) {scope.closed(workspace, opening, 'model-closed');}
export function workspaceClosed(workspace: string, opening: number) {scope.closed(workspace, opening, 'workspace-closed');}
/** Internal outer boundary preserves real returned result or identical exception. */
export function requestObservedDownload(operation: object, archive: ReadyOriginalArchive): ArchiveDownloadResult {
  return scope.requestDownload(operation, archive);
}
