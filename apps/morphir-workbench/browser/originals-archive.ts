import {requestOriginalArchiveDownload} from './originals-archive-download.ts';
import {Uint8ArrayReader, ZipWriter} from '@zip.js/zip.js';
import {originalPath} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';
import {parseRelativeArtifactPath, portableArtifactKey} from '../../../pkgs/morphir-host/artifact-client/artifact-client/artifact-path.ts';
import {allocationLength, checkedCentralDirectoryCapacity, checkedOutputCapacity, CheckedArchiveWriter} from './originals-archive-storage.ts';
import {operationBrand, readyBrand, type ArchiveFailure, type OriginalArchiveInput, type OriginalArchiveOperation,
  type ReadyOriginalArchive, type ArchiveStart, type OriginalArchiveEvent, type ArchiveDownloadResult} from './originals-archive-contract.ts';
export type {ArchiveFailure, OriginalArchiveMetadataSink, OriginalArchiveSnapshotSink, OriginalArchiveInput,
  OriginalArchiveOperation, ReadyOriginalArchive, ArchiveStart, OriginalArchiveEvent, ArchiveDownloadResult} from './originals-archive-contract.ts';

const construction = Symbol('originals-archive-construction');

class ArchiveFault extends Error {
  constructor(readonly failure: ArchiveFailure) {super(failure.message);}
}
function refuse(kind: ArchiveFailure['kind'], message: string): never {throw new ArchiveFault({kind, message});}
function failure(error: unknown, stage: ArchiveFailure['kind']): ArchiveFailure {
  return error instanceof ArchiveFault ? error.failure : {kind: stage, message: `Original archive ${stage} failed.`};
}
function natural(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0) refuse('size', 'Archive metadata must use exact natural numbers.');
  return value;
}
function checked(value: bigint): bigint {
  if (value < 0n || value > (1n << 64n) - 1n) refuse('size', 'Archive size exceeds UInt64.');
  return value;
}
interface Counts {entries: number; raw: bigint; names: bigint; components: number; codeUnits: number;}
function counts(): Counts {return {entries: 0, raw: 0n, names: 0n, components: 0, codeUnits: 0};}
/** Scalar scan before path splitting, normalization, UTF8 allocation or copying. */
function describeRow(total: Counts, path: string, directory: boolean, length: number): void {
  if (typeof path !== 'string' || !path.length || path.length > 8000) refuse('inventory', 'Invalid original path.');
  let bytes = directory ? 1 : 0, components = 1, scalars = 0;
  for (let index = 0; index < path.length; ++index) {
    const unit = path.charCodeAt(index); ++scalars;
    if (unit === 47) ++components;
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const low = path.charCodeAt(++index);
      if (!(low >= 0xdc00 && low <= 0xdfff)) refuse('inventory', 'Original paths cannot contain unpaired surrogates.');
      bytes += 4;
    } else {
      if (unit >= 0xdc00 && unit <= 0xdfff) refuse('inventory', 'Original paths cannot contain unpaired surrogates.');
      bytes += unit < 128 ? 1 : unit < 2048 ? 2 : 3;
    }
  }
  if (scalars > 4000 || components > 256 || bytes - (directory ? 1 : 0) > 16000 || bytes > 65535) refuse('inventory', 'Original path exceeds its connected bounds.');
  if (++total.entries > 100064) refuse('inventory', 'Original inventory exceeds its connected entry bound.');
  total.raw = checked(total.raw + BigInt(natural(length)));
  if (total.raw > 67108864n) refuse('inventory', 'Original inventory exceeds its connected byte bound.');
  total.names = checked(total.names + BigInt(bytes));
  total.components += components; total.codeUnits += path.length;
}
interface StoragePlan extends Readonly<Counts> {
  readonly output: number;
  readonly central: number;
  readonly library: number;
  readonly nodes: number;
}
function planInput(input: OriginalArchiveInput): StoragePlan {
  if (!input || input.kind !== 'connected') refuse('inventory', 'A connected inventory is required.');
  const declared = {entries: natural(input.entries), raw: natural(input.rawBytes), names: natural(input.archiveNameBytes)};
  if (!declared.entries || declared.entries > 100064 || declared.raw > 67108864) refuse('inventory', 'Original inventory exceeds its connected bounds.');
  const total = counts();
  input.describe({file: (path, length) => describeRow(total, path, false, length), directory: path => describeRow(total, path, true, 0)});
  if (total.entries !== declared.entries || total.raw !== BigInt(declared.raw) || total.names !== BigInt(declared.names)) refuse('inventory', 'Original metadata does not match its declared inventory.');
  const n = BigInt(total.entries), c = checkedOutputCapacity(n, total.names, total.raw), d = checkedCentralDirectoryCapacity(n, total.names);
  // Source-visible allocation volume, not VM/RSS or a cumulative observer grant.
  const l = checked(3n * total.raw + c + 4n * total.names + 512n * n + 1024n);
  return Object.freeze({...total, output: allocationLength(c), central: allocationLength(d), library: allocationLength(l), nodes: total.components + 1});
}
type FileStorage = {kind: 'waiting'} | {kind: 'copied'; bytes: Uint8Array<ArrayBuffer>};
type Entry = {kind: 'file'; path: string; length: number; storage: FileStorage} | {kind: 'directory'; path: string};
type NodeKind = 'implicit' | 'file' | 'directory';
interface TrieNode {spelling: string; kind: NodeKind; children: Map<string, TrieNode>;}
interface Snapshot {entries: Map<string, Entry>; plan: StoragePlan;}

function snapshotInput(input: OriginalArchiveInput, plan: StoragePlan): Snapshot {
  const entries = new Map<string, Entry>();
  const root: TrieNode = {spelling: '', kind: 'implicit', children: new Map()};
  const total = counts(); let nodes = 1, copies = 0;
  function add(path: string, directory: boolean, length: number): void {
    describeRow(total, path, directory, length);
    if (total.entries > plan.entries || total.components > plan.components || total.codeUnits > plan.codeUnits || total.raw > plan.raw || total.names > plan.names) refuse('inventory', 'Original metadata changed during description.');
    originalPath(path);
    let node = root;
    for (const component of path.split('/')) {
      if (node.kind === 'file') refuse('inventory', 'An original file cannot be an ancestor.');
      const parsed = parseRelativeArtifactPath(component);
      if (!parsed.ok) refuse('inventory', 'Invalid original path component.');
      const key = portableArtifactKey(parsed.value);
      let child = node.children.get(key);
      if (child && child.spelling !== component) refuse('inventory', 'Original path spellings collide.');
      if (!child) {
        if (nodes >= plan.nodes) refuse('inventory', 'Original namespace exceeds its checked node count.');
        child = {spelling: component, kind: 'implicit', children: new Map()};
        node.children.set(key, child); ++nodes;
      }
      node = child;
    }
    if (node.kind !== 'implicit' || (!directory && node.children.size)) refuse('inventory', 'Original namespace entries conflict.');
    node.kind = directory ? 'directory' : 'file';
    if (entries.size >= plan.entries || entries.has(path)) refuse('inventory', 'Original entry count or identity changed.');
    entries.set(path, directory ? {kind: 'directory', path} : {kind: 'file', path, length, storage: {kind: 'waiting'}});
  }
  try {
    input.describe({file: (path, length) => add(path, false, length), directory: path => add(path, true, 0)});
    if (total.entries !== plan.entries || total.raw !== plan.raw || total.names !== plan.names || total.components !== plan.components || total.codeUnits !== plan.codeUnits) refuse('inventory', 'Original metadata changed during description.');
    // The temporary domain copy and this private snapshot have a checked 2R
    // handoff lifetime. No retained inventory buffer is kept by this adapter.
    input.copyFiles({file(path, actualBytes) {
      const entry = entries.get(path);
      if (!entry || entry.kind !== 'file' || entry.storage.kind !== 'waiting' || !(actualBytes instanceof Uint8Array) || actualBytes.byteLength !== entry.length) refuse('inventory', 'Original snapshot rows do not match validated metadata.');
      const bytes = new Uint8Array(entry.length);
      if (bytes.byteOffset || bytes.buffer.byteLength !== entry.length) refuse('allocation', 'Original snapshot backing has an unexpected capacity.');
      bytes.set(actualBytes); entry.storage = {kind: 'copied', bytes}; ++copies;
    }});
    let files = 0;
    for (const entry of entries.values()) if (entry.kind === 'file') {
      ++files; if (entry.storage.kind !== 'copied') refuse('inventory', 'Original snapshot is missing a file.');
    }
    if (copies !== files) refuse('inventory', 'Original snapshot contains repeated files.');
    return {entries, plan};
  } catch (error) {entries.clear(); throw error;}
}

// Exact pinned STORE/ZIP64 recipe. No caller options or global configure.
const zipOptions = Object.freeze({
  level: 0, compressionMethod: 0, useWebWorkers: false, useCompressionStream: false,
  extendedTimestamp: false, ntfsTimestamp: false, useUnicodeFileNames: true,
  keepOrder: true, bufferedWrite: false, dataDescriptor: true, dataDescriptorSignature: true,
  zip64: true, usdz: false, passThrough: false,
});
type ActiveEncoding = {snapshot: Snapshot; writer: CheckedArchiveWriter; abort: AbortController};
type OperationState =
  | {kind: 'prepared' | 'scheduled'; snapshot: Snapshot}
  | ({kind: 'building'} & ActiveEncoding)
  | ({kind: 'retiring'; first: ArchiveFailure} & ActiveEncoding)
  | {kind: 'ready'; archive: ReadyArchive}
  | {kind: 'retired'}
  | {kind: 'failed'; first: ArchiveFailure};

class ArchiveOperation implements OriginalArchiveOperation {
  readonly [operationBrand] = true;
  #state: OperationState;
  #pending: Promise<void> = Promise.resolve();
  #delivery: {kind: 'unstarted'} | {kind: 'active'; receive: (event: OriginalArchiveEvent) => void} | {kind: 'retirement-queued' | 'closed'} = {kind: 'unstarted'};
  #pagehide: {kind: 'none'} | {kind: 'registered'; remove: () => void} = {kind: 'none'};
  constructor(token: typeof construction, snapshot: Snapshot) {
    if (token !== construction) throw new Error('Use the checked archive factory.');
    this.#state = {kind: 'prepared', snapshot};
    if (typeof globalThis.addEventListener === 'function' && typeof globalThis.removeEventListener === 'function') {
      const remove = globalThis.removeEventListener.bind(globalThis);
      const listener = () => this.retire();
      globalThis.addEventListener('pagehide', listener);
      this.#pagehide = {kind: 'registered', remove: () => remove('pagehide', listener)};
    }
  }
  whenSettled(): Promise<void> {return this.#pending;}
  #removePagehide(): void {
    const binding = this.#pagehide; this.#pagehide = {kind: 'none'};
    if (binding.kind === 'registered') binding.remove();
  }
  // Awaited library calls can synchronously trigger retire through their signal.
  #currentState(): OperationState {return this.#state;}
  #queueRetirement(): void {
    if (this.#delivery.kind !== 'active') return;
    const {receive} = this.#delivery;
    this.#delivery = {kind: 'retirement-queued'};
    // This chain retains the same encoding promise. Notification cannot run
    // until its library calls and finally cleanup have actually settled.
    this.#pending = this.#pending.then(() => {
      this.#delivery = {kind: 'closed'};
      this.#notify(receive, {kind: 'failed', operation: this, failure: {kind: 'retired', message: 'Original archive was retired.'}});
    });
  }
  #finishDelivery(): void {
    this.#removePagehide();
    if (this.#delivery.kind === 'active') this.#delivery = {kind: 'closed'};
  }
  retire(): void {
    this.#removePagehide();
    const previous = this.#state;
    if (previous.kind !== 'failed') this.#queueRetirement();
    switch (previous.kind) {
      case 'prepared': case 'scheduled': previous.snapshot.entries.clear(); this.#state = {kind: 'retired'}; break;
      case 'ready': previous.archive.dispose(); this.#state = {kind: 'retired'}; break;
      case 'building':
        this.#state = {...previous, kind: 'retiring', first: {kind: 'retired', message: 'Original archive was retired.'}};
        previous.writer.retire(); previous.abort.abort(); break;
      case 'retiring': case 'retired': case 'failed': break;
    }
  }
  start(receive: (event: OriginalArchiveEvent) => void): void {
    if (this.#delivery.kind !== 'unstarted') return;
    if (this.#state.kind === 'retired') {
      this.#delivery = {kind: 'active', receive}; this.#queueRetirement(); return;
    }
    if (this.#state.kind !== 'prepared') return;
    this.#delivery = {kind: 'active', receive};
    this.#state = {kind: 'scheduled', snapshot: this.#state.snapshot};
    this.#pending = Promise.resolve().then(() => this.#encode(receive));
  }
  #notify(receive: (event: OriginalArchiveEvent) => void, event: OriginalArchiveEvent): void {
    try {receive(event);} catch {this.retire();}
  }
  async #encode(receive: (event: OriginalArchiveEvent) => void): Promise<void> {
    if (this.#state.kind !== 'scheduled') return;
    const {snapshot} = this.#state;
    let writer: CheckedArchiveWriter;
    try {writer = new CheckedArchiveWriter(snapshot.plan.output);}
    catch (error) {
      snapshot.entries.clear(); const first = failure(error, 'allocation');
      this.#finishDelivery();
      this.#state = {kind: 'failed', first}; this.#notify(receive, {kind: 'failed', operation: this, failure: first}); return;
    }
    const abort = new AbortController();
    this.#state = {kind: 'building', snapshot, writer, abort};
    try {
      const zip = new ZipWriter(writer, {...zipOptions, lastModDate: new Date(1980, 0, 1)});
      for (const entry of snapshot.entries.values()) {
        if (abort.signal.aborted) refuse('retired', 'Original archive was retired.');
        if (entry.kind === 'directory') await zip.add(entry.path + '/', undefined, {directory: true, signal: abort.signal});
        else {
          if (entry.storage.kind !== 'copied') refuse('inventory', 'Original snapshot is incomplete.');
          await zip.add(entry.path, new Uint8ArrayReader(entry.storage.bytes), {signal: abort.signal});
        }
      }
      const bytes = await zip.close(undefined, {zip64: true});
      if (abort.signal.aborted) refuse('retired', 'Original archive was retired.');
      if (zip.hasCorruptedEntries || zip.warnings?.length || bytes.buffer.byteLength !== snapshot.plan.output) refuse('encoding', 'Original archive encoding did not finish cleanly.');
      const archive = new ReadyArchive(construction, bytes, snapshot.plan, () => this.#finishDelivery());
      this.#state = {kind: 'ready', archive}; this.#notify(receive, {kind: 'ready', operation: this, archive});
    } catch (error) {
      this.#removePagehide();
      const previous = this.#currentState();
      if (previous.kind === 'retiring') this.#state = {kind: 'retired'};
      else {
        const first = failure(error, 'encoding'); this.#state = {kind: 'failed', first};
        this.#finishDelivery();
        this.#notify(receive, {kind: 'failed', operation: this, failure: first});
      }
    } finally {snapshot.entries.clear(); writer.dispose();}
  }
}

type ReadyState = {kind: 'ready'; bytes: Uint8Array<ArrayBuffer>; plan: StoragePlan; finished: () => void} | {kind: 'retired'};
class ReadyArchive implements ReadyOriginalArchive {
  readonly [readyBrand] = true;
  #state: ReadyState;
  constructor(token: typeof construction, bytes: Uint8Array<ArrayBuffer>, plan: StoragePlan, finished: () => void) {
    if (token !== construction) throw new Error('Only actual successful encoding creates archive output.');
    this.#state = {kind: 'ready', bytes, plan, finished};
  }
  requestDownload(): ArchiveDownloadResult {
    if (this.#state.kind !== 'ready') return {kind: 'retired'};
    const {bytes, finished} = this.#state;
    // Consume before Blob/link callbacks can reenter. Output never leaves TS.
    this.#state = {kind: 'retired'};
    finished();
    try {requestOriginalArchiveDownload(bytes); return {kind: 'download-requested'};}
    catch (error) {return {kind: 'failed', failure: failure(error, 'encoding')};}
  }
  dispose(): void {
    const previous = this.#state; this.#state = {kind: 'retired'};
    if (previous.kind === 'ready') previous.finished();
  }
}


/** Storage factory only. The real caller has already checked Visit/revision. */
export function createOriginalsArchive(input: OriginalArchiveInput): ArchiveStart {
  try {return {kind: 'prepared', operation: new ArchiveOperation(construction, snapshotInput(input, planInput(input)))};}
  catch (error) {return {kind: 'refused', failure: failure(error, error instanceof RangeError ? 'allocation' : 'inventory')};}
}
export function prepareOriginalsArchive(operation: OriginalArchiveOperation, receive: (event: OriginalArchiveEvent) => void): void {
  if (!(operation instanceof ArchiveOperation)) refuse('inventory', 'Unknown archive operation.');
  operation.start(receive);
}
