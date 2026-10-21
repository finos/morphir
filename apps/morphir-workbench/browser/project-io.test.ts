import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchText, readDropped, readFiles, storage, type DroppedEntry, type FolderRead } from './project-io.ts';

// The tests replace browser globals with small fakes.
const globals = globalThis as unknown as { fetch: unknown; localStorage?: unknown };
const parse = (reply: string) => JSON.parse(reply) as { ok: boolean; message?: string; text?: string };
const filesOf = (found: FolderRead) => found.ok ? found.files : [];

test('fetchText reports text, HTTP errors and network errors without throwing', async () => {
  const replies: ReturnType<typeof parse>[] = [];
  globals.fetch = async (path: string) => path === 'ok' ? { ok: true, status: 200, text: async () => 'body' } : { ok: false, status: 404 };
  await fetchText('ok', r => replies.push(parse(r)));
  await fetchText('missing', r => replies.push(parse(r)));
  globals.fetch = async () => { throw new Error('offline'); };
  await fetchText('any', r => replies.push(parse(r)));
  assert.deepEqual(replies[0], { ok: true, text: 'body' });
  assert.equal(replies[1]?.ok, false);
  assert.match(replies[1]?.message ?? '', /404/);
  assert.match(replies[2]?.message ?? '', /offline/);
});

const LIMITS = { files: 2000, bytes: 16 * 1024 * 1024 };
interface FakeFile { name: string; webkitRelativePath: string; size: number; reads: number; arrayBuffer(): Promise<ArrayBuffer> }
const file = (path: string, bytes: ArrayLike<number>): FakeFile => ({
  name: path.split('/').pop() ?? path, webkitRelativePath: path, size: bytes.length, reads: 0,
  async arrayBuffer() { this.reads++; return Uint8Array.from(bytes).buffer; },
});
const text = (value: string) => [...new TextEncoder().encode(value)];

test('readFiles preserves binary and large files while omitting tool folders', async () => {
  const big = file('rentals/src/Big.elm', new Uint8Array(2 * 1024 * 1024).fill(97));
  const vendored = file('rentals/node_modules/x/y.elm', text('module Y'));
  const found = await readFiles([file('rentals/morphir.json', text('{}')), file('rentals/logo.png', [0xff, 0xfe, 0x00]), big, vendored], LIMITS);
  assert.equal(found.ok, true);
  const files = filesOf(found);
  assert.deepEqual(files.slice(0, 2), [{ path: 'rentals/morphir.json', content: '{}' }, { path: 'rentals/logo.png', content: { encoding: 'base64', content: '//4A' } }]);
  assert.equal(typeof files[2]!.content === 'string' && files[2]!.content.length, 2 * 1024 * 1024);
  assert.equal(found.ok && found.skipped, 1); assert.equal(big.reads, 1); assert.equal(vendored.reads, 0);
});

test('readFiles stops past the file limit before reading more', async () => {
  const many = Array.from({ length: 2001 }, (_, i) => file(`p/src/M${i}.elm`, text('module M')));
  const found = await readFiles(many, LIMITS);
  assert.equal(found.ok, false);
  assert.match(found.ok ? '' : found.message, /2,?000 files/);
  assert.equal(many.reduce((n, f) => n + f.reads, 0), 0);
});

test('readFiles stops past the byte limit before reading the file that crosses it', async () => {
  const a = file('p/a.elm', new Uint8Array(600 * 1024).fill(97)), b = file('p/b.elm', new Uint8Array(600 * 1024).fill(98));
  const found = await readFiles([a, b], { files: 2000, bytes: 1024 * 1024 });
  assert.equal(found.ok, false); assert.match(found.ok ? '' : found.message, /MiB/); assert.equal(b.reads, 0);
});

test('binary bytes and paths count towards the same aggregate quota', async () => {
  const binary = Array.from({ length: 12 }, (_, i) => file(`p/assets/b${i}.bin`, new Uint8Array(100 * 1024).fill(255)));
  const source = file('p/src/Main.elm', text('module Main exposing (..)'));
  const found = await readFiles([...binary, source], { files: 2000, bytes: 1024 * 1024 });
  assert.equal(found.ok, false); assert.equal(source.reads, 0); assert.ok(binary.reduce((n, f) => n + f.reads, 0) < binary.length);
});

test('folder text retains BOM and CRLF and model sidecar tool names remain ordinary files', async () => {
  const found = await readFiles([file('p/morphir.toml', [0xef, 0xbb, 0xbf, ...text('[workspace]\r\nmembers=[]\r\n')]),
    file('p/models/node_modules/raw.bin', [0xff, 0x80])]);
  assert.equal(found.ok, true);
  assert.equal(filesOf(found)[0]?.content, '\ufeff[workspace]\r\nmembers=[]\r\n');
  assert.deepEqual(filesOf(found)[1]?.content, { encoding: 'base64', content: '/4A=' });
});

test('unreadable or changed file data refuses the copy instead of silently dropping it', async () => {
  const changed = file('p/value.bin', [1, 2]); changed.size = 1;
  const found = await readFiles([changed]); assert.equal(found.ok, false); assert.match(found.ok ? '' : found.message, /changed/);
});

test('storage reports failure instead of throwing', () => {
  globals.localStorage = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('quota'); }, removeItem() { throw new Error('denied'); } };
  assert.equal(storage.load('k'), null);
  assert.equal(storage.save('k', 'v'), false);
  assert.equal(storage.remove('k'), false);
  const data = new Map<string, string>();
  globals.localStorage = { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => data.set(k, v), removeItem: (k: string) => data.delete(k) };
  assert.equal(storage.save('k', 'v'), true);
  assert.equal(storage.load('k'), 'v');
  assert.equal(storage.remove('k'), true);
});

test('storage survives a missing localStorage', () => {
  delete globals.localStorage;
  assert.equal(storage.load('k'), null);
  assert.equal(storage.save('k', 'v'), false);
  assert.equal(storage.remove('k'), false);
});

test('readDropped takes every dropped entry before reading, so a second folder is not lost', async () => {
  const fileEntry = (fullPath: string, content: string): DroppedEntry => ({
    isFile: true, isDirectory: false, name: fullPath.split('/').pop() ?? fullPath, fullPath,
    file: ok => ok({ name: fullPath.split('/').pop() ?? fullPath, size: content.length, arrayBuffer: async () => new TextEncoder().encode(content).buffer as ArrayBuffer }),
  });
  const folder = (name: string, children: DroppedEntry[]): DroppedEntry => ({
    isFile: false, isDirectory: true, name, fullPath: '/' + name,
    createReader() {
      let done = false;
      return { readEntries: ok => { const batch = done ? [] : children; done = true; ok(batch); } };
    },
  });
  // The browser empties the items after the handler's first await; the fake does the same.
  let live = true;
  const items = [folder('a', [fileEntry('/a/one.elm', 'module A')]), folder('b', [fileEntry('/b/two.elm', 'module B')])]
    .map(entry => ({ webkitGetAsEntry: () => (live ? entry : null) }));
  const pending = readDropped(items);
  live = false;
  const found = await pending;
  assert.equal(found.ok, true);
  assert.deepEqual(filesOf(found).map(f => f.path).sort(), ['a/one.elm', 'b/two.elm']);
});

test('storage lists keys by prefix and reports none when storage is unavailable', () => {
  globals.localStorage = { get length(): number { throw new Error('denied'); }, key() { return null; } };
  assert.deepEqual(storage.keys('morphir-workbench.workspace.'), []);
  const keys = ['morphir-workbench.workspace.w2.intent.v1', 'other', 'morphir-workbench.workspace.w10.project.elm.v1'];
  globals.localStorage = { length: keys.length, key: (i: number) => keys[i] ?? null };
  assert.deepEqual(storage.keys('morphir-workbench.workspace.'), [keys[0], keys[2]]);
});
