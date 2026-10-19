import type { ModelCodec, ModelSource, WorkRequest, WorkResult } from './contracts.ts';

const byteLimit = 16 * 1024 * 1024;
export type ModelImportFailure = 'oversized' | 'unreadable' | 'invalid-name' | 'unsupported-codec';
export type ModelFileSelection =
  | { readonly kind: 'selected'; readonly filename: string; readonly codec: ModelCodec; readonly contentBase64: string }
  | { readonly kind: 'cancelled' }
  | { readonly kind: 'refused'; readonly reason: ModelImportFailure };
export interface ModelFile { readonly name: string; readonly size: number; arrayBuffer(): Promise<ArrayBuffer>; }

function filename(value: string): boolean {
  return value !== '.' && value !== '..' && [...value].length > 0 && [...value].length <= 256 && !/[/\\\u0000-\u001f\u007f]/.test(value);
}
function codec(name: string): ModelCodec | null {
  const suffix = name.toLowerCase().split('.').at(-1);
  return suffix === 'json' ? 'morphir-json' : suffix === 'ion' ? 'ion-text' : suffix === 'ionb' ? 'ion-binary' : null;
}
function base64(bytes: Uint8Array): string {
  const chunks: string[] = [];
  for (let offset = 0; offset < bytes.length; offset += 32768) {
    chunks.push(String.fromCharCode(...bytes.subarray(offset, offset + 32768)));
  }
  return btoa(chunks.join(''));
}

/** Capture the original bytes before decoding; a parser view never replaces them. */
export async function readModelFile(file: ModelFile): Promise<ModelFileSelection> {
  const name = file.name, size = file.size;
  if (!filename(name)) return { kind: 'refused', reason: 'invalid-name' };
  const selectedCodec = codec(name);
  if (!selectedCodec) return { kind: 'refused', reason: 'unsupported-codec' };
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
  if (request.operation !== 'inspect' || request.sourceFilename === undefined) return null;
  const name = request.sourceFilename, selectedCodec = request.sourceCodec, bytes = request.sourceBase64;
  if (!filename(name) || !['morphir-json', 'ion-text', 'ion-binary'].includes(selectedCodec ?? '') || typeof bytes !== 'string' || bytes.length > 22369624) {
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
  start(id: string, receive: (reply: string) => void): void {
    if (!/^[1-9][0-9]{0,9}$/.test(id) || Number(id) > 2147483647) throw new Error('Invalid model opening identity.');
    this.#pending?.input.remove();
    const pending = { id, input: this.#input() };
    this.#pending = pending;
    const finish = (reply: ModelFileSelection) => {
      if (this.#pending !== pending) return;
      this.#pending = null; pending.input.remove(); receive(JSON.stringify(reply));
    };
    pending.input.type = 'file'; pending.input.accept = '.json,.ion,.ionb,application/json';
    pending.input.addEventListener('cancel', () => finish({ kind: 'cancelled' }));
    pending.input.addEventListener('change', () => {
      const file = pending.input.files?.[0];
      if (!file) { finish({ kind: 'cancelled' }); return; }
      void readModelFile(file).then(finish, () => finish({ kind: 'refused', reason: 'unreadable' }));
    });
    try { pending.input.click(); } catch { finish({ kind: 'refused', reason: 'unreadable' }); }
  }
  cancel(id: string): void {
    if (this.#pending?.id !== id) return;
    const pending = this.#pending; this.#pending = null; pending.input.remove();
  }
  dispose(): void { if (this.#pending) this.cancel(this.#pending.id); }
}
