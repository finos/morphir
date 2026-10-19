import type { ModelCodec, ModelTreeFile, ModelSource, WorkRequest, WorkResult } from './contracts.ts';

const byteLimit = 16 * 1024 * 1024;
const pathUnitLimit = 1024 * 1024;
export const modelFileAccept = '.json,.yaml,.yml,.ion,.ionb,application/json,application/yaml,text/yaml';
const modelCodecs: readonly ModelCodec[] = ['morphir-json', 'morphir-yaml', 'ion-text', 'ion-binary'];
export type ModelImportFailure = 'oversized' | 'unreadable' | 'invalid-name' | 'unsupported-codec';
export type ModelFileSelection =
  | { readonly kind: 'selected'; readonly filename: string; readonly codec: ModelCodec; readonly contentBase64: string }
  | { readonly kind: 'selected-tree'; readonly files: readonly ModelTreeFile[] }
  | { readonly kind: 'cancelled' }
  | { readonly kind: 'refused'; readonly reason: ModelImportFailure };
export interface ModelFile { readonly name: string; readonly size: number; arrayBuffer(): Promise<ArrayBuffer>; readonly webkitRelativePath?: string; }

function filename(value: string): boolean {
  return value !== '.' && value !== '..' && [...value].length > 0 && [...value].length <= 256 && !/[/\\\u0000-\u001f\u007f]/.test(value);
}
function codec(name: string): ModelCodec | null {
  const suffix = name.toLowerCase().split('.').at(-1);
  return suffix === 'yaml' || suffix === 'yml' ? 'morphir-yaml' : suffix === 'json' ? 'morphir-json' : suffix === 'ion' ? 'ion-text' : suffix === 'ionb' ? 'ion-binary' : null;
}
function base64(bytes: Uint8Array): string {
  const chunks: string[] = [];
  for (let offset = 0; offset < bytes.length; offset += 32768) {
    chunks.push(String.fromCharCode(...bytes.subarray(offset, offset + 32768)));
  }
  return btoa(chunks.join(''));
}

/** Capture the original bytes before decoding; a parser view never replaces them. */
export async function readModelFile(file: ModelFile, selection?: ModelCodec): Promise<ModelFileSelection> {
  const name = file.name, size = file.size;
  if (!filename(name)) return { kind: 'refused', reason: 'invalid-name' };
  const selectedCodec = selection ?? codec(name);
  if (!selectedCodec || !modelCodecs.includes(selectedCodec)) return { kind: 'refused', reason: 'unsupported-codec' };
  if (!Number.isSafeInteger(size) || size < 0 || size > byteLimit) return { kind: 'refused', reason: 'oversized' };
  try {
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.length > byteLimit) return { kind: 'refused', reason: 'oversized' };
    if (bytes.length !== size) return { kind: 'refused', reason: 'unreadable' };
    return { kind: 'selected', filename: name, codec: selectedCodec, contentBase64: base64(bytes) };
  } catch { return { kind: 'refused', reason: 'unreadable' }; }
}

/** The already captured request binds successful inspection to exactly its input. */
export function captureOriginalRequest(request: WorkRequest): ((result: WorkResult) => WorkResult) | null {
  if (request.operation === 'inspect' && request.sourceTree !== undefined) {
    validateModelTreeInput(request.sourceTree);
    const files = request.sourceTree.map(file => ({ path: file.path, contentBase64: file.contentBase64 }));
    return result => {
      if (!result.success) return result;
      if (typeof result.sourceFormatVersion !== 'string') throw new Error('The model inspector did not report its input format version.');
      return { ...result, modelSource: { kind: 'original-tree', codec: 'morphir-yaml', formatVersion: result.sourceFormatVersion, files, directories: [] } };
    };
  }
  if (request.operation !== 'inspect' || request.sourceFilename === undefined) return null;
  const name = request.sourceFilename, selectedCodec = request.sourceCodec, bytes = request.sourceBase64;
  if (!filename(name) || !modelCodecs.includes(selectedCodec as ModelCodec) || typeof bytes !== 'string' || bytes.length > 22369624) {
    throw new Error('The captured model file is invalid.');
  }
  return result => {
    if (!result.success) return result;
    if (typeof result.sourceFormatVersion !== 'string') throw new Error('The model inspector did not report its input format version.');
    const modelSource: ModelSource = { kind: 'original-file', filename: name, codec: selectedCodec as ModelCodec,
      formatVersion: result.sourceFormatVersion, contentBase64: bytes };
    return { ...result, modelSource };
  };
}

export interface ModelInput {
  type: string;
  accept: string;
  webkitdirectory?: boolean;
  readonly files: ArrayLike<ModelFile> | null;
  addEventListener(type: string, listener: () => void): void;
  click(): void;
  remove(): void;
}

/** One picker/read owner. Retired callbacks can never publish another file. */
export class ModelImporter {
  #pending: { readonly id: string; readonly input: ModelInput } | null = null;
  readonly #input: () => ModelInput;
  constructor(input: () => ModelInput = () => document.createElement('input')) { this.#input = input; }
  start(id: string, receive: (reply: string) => void, selection?: ModelCodec): void { this.#start(id, receive, false, selection); }
  startTree(id: string, receive: (reply: string) => void): void { this.#start(id, receive, true); }
  #start(id: string, receive: (reply: string) => void, tree: boolean, selection?: ModelCodec): void {
    if (!/^[1-9][0-9]{0,9}$/.test(id) || Number(id) > 2147483647) throw new Error('Invalid model opening identity.');
    this.#pending?.input.remove();
    const pending = { id, input: this.#input() };
    this.#pending = pending;
    const finish = (reply: ModelFileSelection) => {
      if (this.#pending !== pending) return;
      this.#pending = null; pending.input.remove(); receive(JSON.stringify(reply));
    };
    pending.input.type = 'file'; pending.input.accept = modelFileAccept; pending.input.webkitdirectory = tree;
    pending.input.addEventListener('cancel', () => finish({ kind: 'cancelled' }));
    pending.input.addEventListener('change', () => {
      const file = pending.input.files?.[0];
      if (!file) { finish({ kind: 'cancelled' }); return; }
      const captured = tree ? readModelTree(pending.input.files!) : readModelFile(file, selection);
      void captured.then(finish, () => finish({ kind: 'refused', reason: 'unreadable' }));
    });
    try { pending.input.click(); } catch { finish({ kind: 'refused', reason: 'unreadable' }); }
  }
  cancel(id: string): void {
    if (this.#pending?.id !== id) return;
    const pending = this.#pending; this.#pending = null; pending.input.remove();
  }
  dispose(): void { if (this.#pending) this.cancel(this.#pending.id); }
}


function relativePath(path: string): boolean {
  return path.length > 0 && path.length <= 4096 && !/^[\\/]|[\\:\u0000-\u001f\u007f]/.test(path) && path.split('/').every(part => part !== '' && part !== '.' && part !== '..');
}

/** Bounds before request cloning or worker dispatch. */
export function validateModelTreeInput(files: readonly ModelTreeFile[]): void {
  if (!Array.isArray(files) || files.length === 0 || files.length > 4096) throw new Error('Model tree exceeds the file budget.');
  let total = 0;
  let pathUnits = 0;
  const paths = new Set<string>();
  for (const file of files) {
    if (!file || typeof file.path !== 'string' || !relativePath(file.path) || paths.has(file.path) || typeof file.contentBase64 !== 'string' || file.contentBase64.length > 22369624 ||
        !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(file.contentBase64)) throw new Error('Invalid captured model tree file.');
    if (file.path.length > pathUnitLimit - pathUnits) throw new Error('Model tree exceeds the path text budget.');
    pathUnits += file.path.length;
    paths.add(file.path);
    total += file.contentBase64.length / 4 * 3 - (file.contentBase64.endsWith('==') ? 2 : file.contentBase64.endsWith('=') ? 1 : 0);
    if (total > byteLimit) throw new Error('Model tree exceeds the source byte budget.');
  }
}

/** File-list capture preserves every returned file, including binary sidecars.
 * Browser folder pickers do not report empty directories. */
export async function readModelTree(input: ArrayLike<ModelFile>): Promise<ModelFileSelection> {
  if (input.length === 0 || input.length > 4096) return { kind: 'refused', reason: 'oversized' };
  const captured: { file: ModelFile; path: string; size: number }[] = [];
  const paths = new Set<string>();
  let total = 0;
  let pathUnits = 0;
  let root = '';
  for (let index = 0; index < input.length; index++) {
    const file = input[index]!;
    const full = file.webkitRelativePath ?? '';
    const split = full.indexOf('/');
    if (split < 1) return { kind: 'refused', reason: 'invalid-name' };
    const prefix = full.slice(0, split);
    if (root && root !== prefix) return { kind: 'refused', reason: 'invalid-name' };
    root = prefix;
    const pathLength = full.length - split - 1;
    if (pathLength < 1 || pathLength > 4096) return { kind: 'refused', reason: 'invalid-name' };
    if (pathLength > pathUnitLimit - pathUnits) return { kind: 'refused', reason: 'oversized' };
    const path = full.slice(split + 1), size = file.size;
    if (!relativePath(path) || paths.has(path)) return { kind: 'refused', reason: 'invalid-name' };
    if (!Number.isSafeInteger(size) || size < 0 || size > byteLimit - total) return { kind: 'refused', reason: 'oversized' };
    pathUnits += pathLength;
    paths.add(path); total += size; captured.push({ file, path, size });
  }
  if (!paths.has('manifest.yaml') && !paths.has('manifest.yml')) return { kind: 'refused', reason: 'unsupported-codec' };
  const files: ModelTreeFile[] = [];
  try {
    for (const entry of captured) {
      const data = new Uint8Array(await entry.file.arrayBuffer());
      if (data.length !== entry.size) return { kind: 'refused', reason: 'unreadable' };
      files.push({ path: entry.path, contentBase64: base64(data) });
    }
    return { kind: 'selected-tree', files };
  } catch { return { kind: 'refused', reason: 'unreadable' }; }
}
