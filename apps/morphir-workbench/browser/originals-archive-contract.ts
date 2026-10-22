// Shared bridge types must remain usable in the DOM-free worker project.
// Brands identify types; only the checked factory creates runtime operations.
export const operationBrand = Symbol('originals-archive-operation');
export const readyBrand = Symbol('originals-archive-ready');

export type ArchiveFailure = Readonly<{kind: 'inventory' | 'size' | 'allocation' | 'encoding' | 'retired'; message: string}>;
export interface OriginalArchiveMetadataSink {
  file(path: string, byteLength: number): void;
  directory(path: string): void;
}
export interface OriginalArchiveSnapshotSink {file(path: string, actualBytes: Uint8Array): void;}
export interface OriginalArchiveInput {
  readonly kind: 'connected';
  readonly entries: number;
  readonly rawBytes: number;
  readonly archiveNameBytes: number;
  readonly describe: (sink: OriginalArchiveMetadataSink) => void;
  readonly copyFiles: (sink: OriginalArchiveSnapshotSink) => void;
}
export interface OriginalArchiveOperation {
  readonly [operationBrand]: true;
  retire(): void;
  whenSettled(): Promise<void>;
}
export interface ReadyOriginalArchive {
  readonly [readyBrand]: true;
  requestDownload(): ArchiveDownloadResult;
  dispose(): void;
}
export type ArchiveStart =
  | Readonly<{kind: 'prepared'; operation: OriginalArchiveOperation}>
  | Readonly<{kind: 'refused'; failure: ArchiveFailure}>;
export type OriginalArchiveEvent =
  | Readonly<{kind: 'ready'; operation: OriginalArchiveOperation; archive: ReadyOriginalArchive}>
  | Readonly<{kind: 'failed'; operation: OriginalArchiveOperation; failure: ArchiveFailure}>;
export type ArchiveDownloadResult =
  | Readonly<{kind: 'download-requested'}>
  | Readonly<{kind: 'retired'}>
  | Readonly<{kind: 'failed'; failure: ArchiveFailure}>;
