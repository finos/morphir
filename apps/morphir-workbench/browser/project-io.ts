// File and network access of the project editor. Replies are JSON text so the MoonBit side parses them at the
// boundary; nothing here throws.

/** A file of a folder selection or drop: a browser `File`, or the same shape built from a dropped entry. */
export interface FolderEntryFile {
  name: string;
  webkitRelativePath: string;
  size: number;
  arrayBuffer(): Promise<ArrayBuffer>;
}

export interface FolderFile { path: string; content: string }
export type FolderRead = { ok: true; files: FolderFile[]; skipped: number } | { ok: false; message: string };
export interface Limits { files: number; bytes: number }

/** The parts of a `FileSystemEntry` (and its file and directory subtypes) that a drop reads. */
export interface DroppedEntry {
  isFile: boolean;
  isDirectory: boolean;
  name: string;
  fullPath: string;
  file?(success: (file: { name: string; size: number; arrayBuffer(): Promise<ArrayBuffer> }) => void, failure?: (error: unknown) => void): void;
  createReader?(): { readEntries(success: (entries: DroppedEntry[]) => void, failure?: (error: unknown) => void): void };
}
export interface DroppedItem { webkitGetAsEntry?(): DroppedEntry | null }

const message = (error: unknown, fallback: string) => error instanceof Error ? error.message : fallback;

export async function fetchText(path: string, receive: (reply: string) => void): Promise<void> {
  try {
    const response = await fetch(path);
    if (!response.ok) {
      receive(JSON.stringify({ ok: false, message: `${path}: HTTP ${response.status}` }));
      return;
    }
    receive(JSON.stringify({ ok: true, text: await response.text() }));
  } catch (error) {
    receive(JSON.stringify({ ok: false, message: `${path}: ${message(error, 'network error')}` }));
  }
}

export const LIMITS: Limits = { files: 2000, bytes: 16 * 1024 * 1024 };
const FILE_LIMIT = 1024 * 1024;
const TOOL_FOLDERS = new Set(['.git', 'node_modules', 'elm-stuff', '_build']);

function inToolFolder(path: string): boolean {
  return path.split('/').slice(0, -1).some(segment => TOOL_FOLDERS.has(segment));
}

/**
 * Reads the text files of a folder selection. Returns `{ ok: true, files: [{path, content}], skipped }` or
 * `{ ok: false, message }`. Files over 1 MiB, files that are not UTF-8 text and files in tool folders are skipped
 * and counted. Nothing is read once a limit would be crossed.
 */
export async function readFiles(fileList: ArrayLike<FolderEntryFile> | Iterable<FolderEntryFile>, limits: Limits = LIMITS): Promise<FolderRead> {
  const entries = Array.from(fileList).map(file => ({ file, path: file.webkitRelativePath || file.name }));
  const candidates = entries.filter(entry => !inToolFolder(entry.path));
  let skipped = entries.length - candidates.length;
  if (candidates.length > limits.files) {
    return { ok: false, message: `Select a folder with at most ${limits.files.toLocaleString('en-US')} files.` };
  }
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const files: FolderFile[] = [];
  let total = 0;
  for (const { file, path } of candidates) {
    if (file.size > FILE_LIMIT) { skipped++; continue; }
    // The guard comes before the read, so no read crosses the limit; only text counts towards it.
    if (total + file.size > limits.bytes) {
      return { ok: false, message: `Select a folder with at most ${Math.round(limits.bytes / 1048576 * 100) / 100} MiB of text.` };
    }
    try {
      files.push({ path, content: decoder.decode(await file.arrayBuffer()) });
      total += file.size;
    } catch {
      skipped++;
    }
  }
  return { ok: true, files, skipped };
}

/**
 * Opens the folder picker and reports the files as JSON text. A cancelled picker reports `{ ok: false, cancelled: true }`
 * where the browser signals cancellation; older browsers report nothing.
 */
export function pickFolder(receive: (reply: string) => void): void {
  const input = document.createElement('input');
  input.type = 'file';
  input.webkitdirectory = true;
  input.addEventListener('change', async () => {
    if (!input.files || input.files.length === 0) return;
    receive(JSON.stringify(await readFiles(input.files, LIMITS)));
  });
  input.addEventListener('cancel', () => {
    receive(JSON.stringify({ ok: false, cancelled: true, message: 'Folder selection cancelled' }));
  });
  input.click();
}

async function readEntries(directory: DroppedEntry): Promise<DroppedEntry[]> {
  const reader = directory.createReader?.();
  if (!reader) return [];
  const all: DroppedEntry[] = [];
  for (;;) {
    const batch = await new Promise<DroppedEntry[]>((resolve, reject) => reader.readEntries(resolve, reject));
    if (batch.length === 0) return all;
    all.push(...batch);
  }
}

// A dropped folder as File-like objects with their relative paths; stops past the file limit.
async function walk(entry: DroppedEntry, out: FolderEntryFile[], limits: Limits): Promise<void> {
  if (out.length > limits.files) return;
  if (entry.isFile && entry.file) {
    const read = entry.file.bind(entry);
    const file = await new Promise<{ name: string; size: number; arrayBuffer(): Promise<ArrayBuffer> }>((resolve, reject) => read(resolve, reject));
    out.push({
      name: file.name, webkitRelativePath: entry.fullPath.replace(/^\//, ''), size: file.size,
      arrayBuffer: () => file.arrayBuffer(),
    });
  } else if (entry.isDirectory && !TOOL_FOLDERS.has(entry.name)) {
    for (const child of await readEntries(entry)) await walk(child, out, limits);
  }
}

/**
 * Reads every dropped folder or file. All entries are taken from the items before the first await, because the
 * browser empties the items once the event handler yields.
 */
export async function readDropped(items: ArrayLike<DroppedItem> | Iterable<DroppedItem>, limits: Limits = LIMITS): Promise<FolderRead> {
  const entries = Array.from(items).map(item => item.webkitGetAsEntry?.()).filter((entry): entry is DroppedEntry => Boolean(entry));
  const out: FolderEntryFile[] = [];
  for (const entry of entries) await walk(entry, out, limits);
  return readFiles(out, limits);
}

/** Accepts a folder dropped on the element that matches `selector`, and reports it like `pickFolder`. */
export function watchDrop(selector: string, receive: (reply: string) => void): void {
  const target = (event: DragEvent) => event.target instanceof Element ? event.target.closest(selector) : null;
  document.addEventListener('dragover', event => {
    const zone = target(event);
    if (!zone) return;
    event.preventDefault();
    zone.classList.add('drop-active');
  });
  document.addEventListener('dragleave', event => target(event)?.classList.remove('drop-active'));
  document.addEventListener('drop', async event => {
    const zone = target(event);
    if (!zone) return;
    event.preventDefault();
    zone.classList.remove('drop-active');
    // The workspace that showed the drop zone, so the folder goes to it even if another opens while it is read.
    const workspace = zone.closest<HTMLElement>('[data-workspace]')?.dataset.workspace ?? '';
    try {
      receive(JSON.stringify({ ...await readDropped(event.dataTransfer?.items ?? [], LIMITS), workspace }));
    } catch (error) {
      receive(JSON.stringify({ ok: false, workspace, message: `The dropped folder could not be read: ${message(error, 'error')}` }));
    }
  });
}

/** Browser storage as a per-browser convenience: every call returns `null` or `false` instead of throwing. */
export const storage = {
  load(key: string): string | null {
    try { return globalThis.localStorage.getItem(key); } catch { return null; }
  },
  save(key: string, text: string): boolean {
    try { globalThis.localStorage.setItem(key, text); return true; } catch { return false; }
  },
  remove(key: string): boolean {
    try { globalThis.localStorage.removeItem(key); return true; } catch { return false; }
  },
  /** The stored keys that start with `prefix`; none when storage is unavailable. */
  keys(prefix: string): string[] {
    try {
      const found: string[] = [];
      for (let i = 0; i < globalThis.localStorage.length; i++) {
        const key = globalThis.localStorage.key(i);
        if (key?.startsWith(prefix)) found.push(key);
      }
      return found;
    } catch { return []; }
  },
};
