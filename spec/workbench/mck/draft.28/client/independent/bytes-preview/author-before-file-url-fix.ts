/**
 * Static case authoring from the approved contract, never a compatibility runner.
 * No production/adapter imports, executions, outputs or observed-to-expected path.
 */
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const own = resolve(process.argv[2] ?? dirname(new URL(import.meta.url).pathname));
const parent = resolve(own, '../../..');
const foundation = resolve(dirname(new URL(import.meta.url).pathname), 'foundation/byte-recipes.json');
const catalog = JSON.parse(await readFile(foundation, 'utf8'));
const sha = (bytes: Uint8Array | string) => createHash('sha256').update(bytes).digest('hex');
const copy = <T>(value: T): T => structuredClone(value);
const measure = (bytes: Uint8Array) => ({ byteLength: bytes.length, sha256: sha(bytes) });
const textMeasure = (text: string) => ({ utf16Length: text.length, utf8: measure(Buffer.from(text, 'utf8')) });
const NONE = { kind: 'none' };
const EMPTY_HASH = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const INVALID_PREVIEW = 'Text preview unavailable: this file contains invalid UTF-8. Download preserves the original bytes.';
const STALE = 'These generated files are no longer available. Recompile to download them.';
const SELECTION = 'The download selection differs from the verified file inventory.';
const REFERENCE = 'A generated file reference is stale, duplicated or belongs to another output.';
const PATH = 'A generated file reference differs from its verified path.';
const PROFILE = 'morphir/workbench/artifacts';
const VERSION = '0.1.0-draft.1';
type Recipe = { kind: 'hex'; hex: string } | { kind: 'repeat-u8'; length: number; byte: number }
  | { kind: 'cycle-u8'; length: number } | { kind: 'chunk-indexed-u8'; length: number; seed: number };
type FileSpec = { path: string; kind: 'binary' | 'utf8-text'; content: Recipe; immutableId?: string };
type File = FileSpec & { bytes: Buffer; measured: any; preview: any };

function construct(recipe: Recipe): Buffer {
  if (recipe.kind === 'hex') return Buffer.from(recipe.hex, 'hex');
  if (recipe.kind === 'repeat-u8') return Buffer.alloc(recipe.length, recipe.byte);
  const bytes = Buffer.alloc(recipe.length);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = recipe.kind === 'cycle-u8' ? i % 256 : (i % 256) ^ ((Math.floor(i / 65536) + recipe.seed) % 256);
  }
  return bytes;
}

function fixed(id: string, path: string, kind: 'binary' | 'utf8-text' = 'binary'): FileSpec {
  const entry = catalog.recipes.find((item: any) => item.id === id);
  if (!entry) throw new Error('Missing independent recipe ' + id);
  const source = entry.recipe;
  const content: Recipe = source.kind === 'hex' ? { kind: 'hex', hex: source.hex }
    : source.kind === 'cycle-u8' ? { kind: 'cycle-u8', length: source.length }
    : { kind: 'chunk-indexed-u8', length: source.length, seed: source.seed };
  return { path, kind, content, immutableId: id };
}

function prefix(text: string, limit: number): string {
  let result = text.slice(0, limit);
  const final = result.charCodeAt(result.length - 1);
  if (final >= 0xd800 && final <= 0xdbff) result = result.slice(0, -1);
  return result;
}

function file(spec: FileSpec): File {
  const bytes = construct(spec.content);
  const measured = measure(bytes);
  if (spec.immutableId) {
    const entry = catalog.recipes.find((item: any) => item.id === spec.immutableId);
    if (entry.sha256 !== measured.sha256 || entry.byteLength !== measured.byteLength) throw new Error('Immutable recipe disagreement');
  }
  let preview: any;
  if (spec.kind === 'binary') preview = { kind: 'binary', prefix: measure(bytes.subarray(0, 65536)) };
  else {
    try {
      const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
      preview = { kind: text.length <= 65536 ? 'text' : 'text-prefix', text: textMeasure(prefix(text, 65536)) };
    } catch { preview = { kind: 'invalid-utf8' }; }
  }
  return { ...spec, bytes, measured, preview };
}

function definition(id: string, files: File[], input?: any) {
  return {
    id,
    offer: { id: 'provider-client', status: 'available', capabilities: [{ name: PROFILE, version: VERSION }] },
    input: input ?? { sessionId: 'session-client', target: 'fixture', irVersion: '4', ir: { formatVersion: 4 }, options: {} },
    context: { sourceId: 'client-source', revision: id === 'A' ? 1 : 2, epoch: id === 'A' ? 1 : 2 },
    peer: { kind: 'ready', generationId: 'generation-' + id, producer: { id: 'artifact-fixture', version: '0.1.0' },
      artifacts: files.map((item, index) => ({ id: 'artifact-' + id + '-' + index, path: item.path, kind: item.kind, content: item.content })),
      diagnostics: [] },
    localFaults: [],
  };
}

// Each transition below is authored, not derived by executing a client.
// The fixed scope reads every file in order, hashes every file in order, then releases once.
class AuthoredCase {
  definitions: any[];
  files: Record<string, File[]>;
  actions: any[] = [];
  events: any[] = [];
  checkpoints: any[] = [];
  states: Record<string, any> = {};
  results: Record<string, any> = {};
  current: any = null;
  registry: any = { kind: 'empty' };
  views: Record<string, string> = {};
  nextEffect: Record<string, number> = {};
  nextWire: Record<string, number> = {};
  readWork = 0;
  observationWork = 0;
  rawWork = 0;
  constructor(id: string, files: Record<string, File[]>, inputs: Record<string, any> = {}) {
    this.id = id;
    this.files = files;
    this.definitions = Object.entries(files).map(([attempt, items]) => definition(attempt, items, inputs[attempt]));
    for (const item of this.definitions) {
      this.states[item.id] = { id: item.id, phase: 'not-started', pending: [], signalAborted: null, terminal: { kind: 'pending' }, closeCalls: 0 };
      this.nextEffect[item.id] = 0; this.nextWire[item.id] = 1;
    }
  }
  id: string;
  bytes(id: string): number { return this.files[id].reduce((sum, item) => sum + item.bytes.length, 0); }
  allBytes(): number { return Object.keys(this.files).reduce((sum, id) => sum + this.bytes(id), 0); }
  act(action: any, transition: () => void = () => {}, result: any = NONE) {
    this.actions.push(copy(action)); transition();
    this.checkpoints.push({ actionIndex: this.actions.length - 1, eventCount: this.events.length, label: action.action === 'observe' ? action.label : null,
      currentContext: copy(this.current), attempts: this.definitions.map(item => copy(this.states[item.id])), registry: copy(this.registry), actionResult: copy(result) });
  }
  context(id: string) { this.act({ action: 'set-current', context: this.definitions.find(item => item.id === id).context }, () => { this.current = this.definitions.find(item => item.id === id).context; }); }
  effect(id: string, kind: string, argument: any) {
    const index = this.nextEffect[id]++;
    this.events.push({ kind: 'effect', attempt: id, index, effect: kind, argument });
    this.states[id].pending = [{ index, effect: kind }];
    return index;
  }
  settled(id: string) {
    const pending = this.states[id].pending[0];
    this.events.push({ kind: 'settled', attempt: id, index: pending.index, settlement: 'resolved' });
    this.states[id].pending = [];
  }
  wire(id: string, method: string, params: any) {
    return { frame: { kind: 'text', source: JSON.stringify({ jsonrpc: '2.0', id: this.nextWire[id]++, method, params }) } };
  }
  deliver(id: string, kind: string, transition: () => void, value: any = { kind: 'peer' }) {
    const index = this.states[id].pending[0].index;
    this.act({ action: 'deliver', effect: { attempt: id, index, kind }, value }, () => { this.settled(id); transition(); });
  }
  begin(id: string, extras: any[] = []) {
    const d = this.definitions.find(item => item.id === id);
    this.context(id);
    this.act({ action: 'start', attempt: id }, () => {
      this.readWork += this.bytes(id); this.observationWork += this.bytes(id);
      this.states[id].phase = 'connecting'; this.states[id].signalAborted = false;
      this.effect(id, 'connect', { signalAborted: false });
    });
    for (const action of extras) this.act({ ...action, attempt: id });
    this.deliver(id, 'connect', () => {
      this.states[id].phase = 'initializing';
      this.effect(id, 'initialize', this.wire(id, 'morphir.session.initialize', { protocolVersion: 1, sessionId: d.input.sessionId }));
    }, { kind: 'connect' });
    this.deliver(id, 'initialize', () => {
      this.states[id].phase = 'generating';
      this.effect(id, 'generate', this.wire(id, 'morphir.artifacts.generate', { contractVersion: VERSION, providerId: d.offer.id,
        generation: { ir: d.input.ir, irVersion: d.input.irVersion, target: d.input.target, options: d.input.options } }));
    });
    const reads = this.files[id].flatMap((item, index) => Array.from({ length: Math.max(1, Math.ceil(item.bytes.length / 65536)) },
      (_, part) => ({ file: index, offset: part * 65536, length: Math.min(65536, item.bytes.length - part * 65536) })));
    // Conservative canonical-peer raw-response expansion, not observed bytes:
    // full manifest budget, small initialization/release wrappers, and 1KiB
    // metadata allowance per exact independently specified base64 chunk.
    this.rawWork += 131072 + 4096 + 256 + reads.reduce((sum, read) => sum + 4 * Math.ceil(read.length / 3) + 1024, 0);
    const requestRead = (read: any) => this.effect(id, 'read', this.wire(id, 'morphir.artifacts.read', {
      contractVersion: VERSION, generationId: d.peer.generationId, artifactId: d.peer.artifacts[read.file].id, offset: read.offset, maxBytes: 65536 }));
    this.deliver(id, 'generate', () => { this.states[id].phase = 'receiving'; requestRead(reads[0]); });
    this.act({ action: 'drain-reads', attempt: id, maxReads: reads.length }, () => {
      this.readWork += reads.length * 65536;
      for (let i = 0; i < reads.length; i++) {
        this.settled(id);
        if (i + 1 < reads.length) requestRead(reads[i + 1]);
      }
      this.states[id].phase = 'verifying';
      this.effect(id, 'digest', this.files[id][0].measured);
    });
    for (let index = 0; index < this.files[id].length; index++) {
      this.deliver(id, 'digest', () => {
        if (index + 1 < this.files[id].length) this.effect(id, 'digest', this.files[id][index + 1].measured);
        else {
          this.states[id].phase = 'releasing';
          this.effect(id, 'release', this.wire(id, 'morphir.artifacts.release', { contractVersion: VERSION, generationId: d.peer.generationId }));
        }
      }, { kind: 'digest', result: 'actual' });
    }
    const cleanup = { kind: 'released', generationId: d.peer.generationId };
    this.deliver(id, 'release', () => {
      this.events.push({ kind: 'close', attempt: id });
      Object.assign(this.states[id], { phase: 'finished', closeCalls: 1, terminal: { kind: 'verified', cleanup } });
      this.results[id] = { kind: 'verified', manifest: { profile: PROFILE, contractVersion: VERSION, sessionId: d.input.sessionId,
        providerId: d.offer.id, generationId: d.peer.generationId, producer: d.peer.producer, target: d.input.target, irVersion: d.input.irVersion, diagnostics: [] },
        inventory: this.files[id].map((item, index) => ({ id: 'file-' + index, path: item.path, declaredKind: item.kind, bytes: item.measured, preview: item.preview })), cleanup };
    });
  }
  viewEvidence(id: string, views: string) {
    const limit = Math.min(65536, Math.floor(1048576 / this.files[id].length));
    return this.files[id].map((item, index) => {
      let content = ''; let state = item.preview.kind;
      if (state === 'text' || state === 'text-prefix') {
        const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(item.bytes);
        const owner = prefix(text, 65536); content = prefix(owner, limit);
        if (state === 'text-prefix' || content.length < owner.length) state = 'text-prefix';
      } else if (state === 'invalid-utf8') content = INVALID_PREVIEW;
      return { file: 'file-' + index, path: item.path, binary: item.kind === 'binary', encoding: 'verified-bytes', byteLength: item.bytes.length,
        previewState: state, content: textMeasure(content), binaryPreview: item.kind === 'binary' ? measure(item.bytes.subarray(0, limit)) : null,
        reference: { views, file: 'file-' + index } };
    });
  }
  publish(id: string, views: string) {
    this.observationWork += this.bytes(id);
    this.act({ action: 'publish', attempt: id, views }, () => { this.views[views] = id; this.registry = { kind: 'published', views }; },
      { kind: 'published', views, artifacts: this.viewEvidence(id, views) });
  }
  select(views: string, indices: number[], mutations: any[] = []) { return { views, indices, mutations }; }
  download(views: any, complete: boolean, refusal?: string) {
    this.observationWork += this.allBytes();
    const files = views.indices.map((index: number) => this.files[this.views[views.views]][index]).map((item: File) => ({ path: item.path, bytes: item.measured }));
    this.act({ action: 'download', views, complete }, () => {}, refusal ? { kind: 'refused', operation: 'download', message: refusal } : { kind: 'download', files });
  }
  archive(views: any, refusal?: string) {
    this.observationWork += 3 * this.allBytes();
    const entries = views.indices.map((index: number) => this.files[this.views[views.views]][index]).map((item: File) => ({ path: item.path, bytes: item.measured }));
    const encodedByteLength = 22 + entries.reduce((sum: number, item: any) => sum + 76 + 2 * Buffer.byteLength(item.path) + item.bytes.byteLength, 0);
    this.act({ action: 'archive', views }, () => {}, refusal ? { kind: 'refused', operation: 'archive', message: refusal }
      : { kind: 'archive', archive: { encodedByteLength, entries } });
  }
  mutate(id: string, index: number) {
    this.observationWork += this.bytes(id);
    this.act({ action: 'mutate-copy', attempt: id, file: 'file-' + index, offset: 0, xor: 255 });
  }
  finish() {
    const attempts = this.definitions.map(d => ({
      id: d.id, capture: this.states[d.id].phase === 'construction-refused' ? null : { profile: PROFILE, contractVersion: VERSION, providerId: d.offer.id, sessionId: d.input.sessionId, target: d.input.target, irVersion: d.input.irVersion },
      phase: this.states[d.id].phase, result: this.results[d.id], closeCalls: this.states[d.id].closeCalls,
      effects: Object.fromEntries(['connect', 'initialize', 'generate', 'read', 'digest', 'release'].map(kind => [kind,
        this.events.filter(event => event.kind === 'effect' && event.attempt === d.id && event.effect === kind).length])),
    }));
    return { id: this.id, operation: 'artifact-client', format: 'json',
      input: { attempts: this.definitions, actions: this.actions }, expected: { status: 'ok', value: { events: this.events, checkpoints: this.checkpoints, attempts } } };
  }
}

await mkdir(resolve(own, 'cases'), { recursive: true });
const authored: any[] = [];
const coverage: any[] = [];
function record(c: AuthoredCase, family: string, requirement: string) {
  const value = c.finish();
  const inputBytes = Buffer.byteLength(JSON.stringify(value.input));
  const evidenceBytes = Buffer.byteLength(JSON.stringify(value.expected.value));
  if (inputBytes > 1048576 || evidenceBytes > 1048576 || c.readWork > 134217728 || c.observationWork > 134217728 || c.rawWork > 134217728 ||
      c.actions.length > 512 || c.events.length > 4096) throw new Error('Authored bound exceeded: ' + c.id);
  authored.push({ value, readWork: c.readWork, observationWork: c.observationWork, rawWorkUpperBound: c.rawWork, inputBytes, evidenceBytes });
  coverage.push({ id: c.id, family, requirement, adapterExecuted: false });
}
const make = (id: string, specs: FileSpec[]) => new AuthoredCase(id, { A: specs.map(file) });
const small = () => [fixed('utf8-bom-crlf', 'original.txt', 'utf8-text'), fixed('cycle-256', 'all.bin')].map(file);

// Byte and strict-preview family. All fixture recipes precede client execution.
{
  const c = make('client-original-mixed-bom-crlf-invalid-text', [
    fixed('empty-binary', 'empty.bin'), fixed('cycle-256', 'all.bin'),
    fixed('utf8-bom-crlf', 'original.txt', 'utf8-text'), fixed('nul-invalid-utf8', 'invalid.txt', 'utf8-text'),
  ]);
  c.begin('A'); c.publish('A', 'views-A'); c.download(c.select('views-A', [0, 1, 2, 3]), true); c.archive(c.select('views-A', [0, 1, 2, 3]));
  record(c, 'bytes', 'Mixed original empty/all-octet/BOM-CRLF/invalid-UTF8 bytes survive owner, downloads and ZIP.');
}
{
  const c = make('client-original-chunk-boundaries', [65535, 65536, 65537, 131073].map(n => fixed('cycle-' + n, 'file-' + n + '.bin')));
  c.begin('A'); record(c, 'bytes', 'Maximum-chunk policy crosses exact boundaries with all inventory reads before digests.');
}
for (const [id, recipe] of [['client-original-over-one-mib', 'indexed-1048833-0'], ['client-original-exact-sixteen-mib', 'indexed-16777216-0']]) {
  const c = make(id, [fixed(recipe, 'indexed.bin')]); c.begin('A');
  record(c, 'bytes', 'Retained owner bytes match an independently frozen indexed recipe without repeated large observations.');
}
{
  const c = make('client-original-exact-sixtyfour-mib', [0, 37, 83, 199].map((seed, i) => fixed('indexed-16777216-' + seed, 'part-' + i + '.bin')));
  c.begin('A'); record(c, 'bytes', 'Exact64MiB aggregate fits128MiB decoded/read work with four distinct file/chunk oracles.');
}
{
  const bytes = Buffer.concat([Buffer.alloc(65536, 97), Buffer.from([255])]);
  const c = make('client-preview-invalid-utf8-after-prefix', [{ path: 'invalid-suffix.txt', kind: 'utf8-text', content: { kind: 'hex', hex: bytes.toString('hex') } }]);
  c.begin('A'); c.publish('A', 'views-A'); c.download(c.select('views-A', [0]), false);
  record(c, 'preview', 'Invalid UTF8 beyond64KiB invalidates the whole preview while downloads preserve all original bytes.');
}
{
  const bytes = Buffer.from('a'.repeat(65535) + '😀');
  const c = make('client-preview-paired-character-at-prefix', [{ path: 'paired.txt', kind: 'utf8-text', content: { kind: 'hex', hex: bytes.toString('hex') } }]);
  c.begin('A'); c.publish('A', 'views-A'); c.download(c.select('views-A', [0]), false);
  record(c, 'preview', 'Prefix truncation removes a trailing high surrogate without changing downloadable original UTF8.');
}
{
  const c = make('client-preview-exact-and-oneover-text-units', [65536, 65537].map(n => ({ path: 'text-' + n + '.txt', kind: 'utf8-text' as const,
    content: { kind: 'repeat-u8' as const, byte: 97, length: n } })));
  c.begin('A'); c.publish('A', 'views-A');
  record(c, 'preview', 'Exact65536UTF16 text stays text; oneover is a bounded text-prefix.');
}
{
  const c = make('client-preview-equal-aggregate-allocation', Array.from({ length: 17 }, (_, i) => ({
    path: 'file-' + i + (i % 2 ? '.bin' : '.txt'), kind: i % 2 ? 'binary' as const : 'utf8-text' as const,
    content: { kind: 'repeat-u8' as const, byte: 65 + i, length: 65537 },
  })));
  c.begin('A'); c.publish('A', 'views-A');
  record(c, 'preview', 'Seventeen files each receive floor1048576/17 preview allocation, including raw binary and text-prefix evidence.');
}
// Capture uses the same independently specified successful transition trace.
{
  const c = new AuthoredCase('client-captures-caller-before-connect', { A: [file(fixed('empty-binary', 'empty.bin'))] });
  c.begin('A', [{ action: 'replace-caller', field: 'ir', value: { changed: true } }, { action: 'replace-caller', field: 'options', value: { changed: true } }]);
  record(c, 'capture', 'Post-start caller replacement cannot alter captured generation IR/options.');
}
{
  const c = make('client-captures-effect-functions-before-connect', [fixed('empty-binary', 'empty.bin')]);
  c.begin('A', [{ action: 'replace-effect-functions' }]);
  record(c, 'capture', 'Replacing effect function properties cannot redirect captured connection/hash/current functions.');
}
{
  const c = new AuthoredCase('client-captures-paired-unicode-input', { A: [file(fixed('empty-binary', 'empty.bin'))] },
    { A: { sessionId: 'session-client', target: 'fixture', irVersion: '4', ir: { '😀': ['π', '𐐀'] }, options: { literal: 'café😀' } } });
  c.begin('A'); record(c, 'capture', 'Paired supplementary Unicode keys/values are valid captured JSON.');
}
// Registry selection expectations use approved source-backed stable messages.
{
  const c = new AuthoredCase('client-registry-original-byte-copy-isolation', { A: small() });
  c.begin('A'); c.mutate('A', 0); c.publish('A', 'views-A'); c.download(c.select('views-A', [1]), false);
  c.download(c.select('views-A', [0, 1]), true); c.archive(c.select('views-A', [0, 1])); c.mutate('A', 1); c.download(c.select('views-A', [0, 1]), true);
  record(c, 'registry', 'Mutated owner byte copies do not change later original downloads or ZIP entries.');
}
{
  const c = new AuthoredCase('client-registry-clear-refuses-old-download-and-zip', { A: small() });
  c.begin('A'); c.publish('A', 'views-A'); c.act({ action: 'clear-registry' }, () => { c.registry = { kind: 'empty' }; });
  c.download(c.select('views-A', [0]), false, STALE); c.archive(c.select('views-A', [0, 1]), STALE);
  record(c, 'registry', 'Clearing registry invalidates original view references for both download and archive.');
}
{
  const c = new AuthoredCase('client-registry-renamed-path-refusal', { A: small() });
  c.begin('A'); c.publish('A', 'views-A'); c.download(c.select('views-A', [0], [{ kind: 'path', index: 0, path: 'renamed.txt' }]), false, PATH);
  c.archive(c.select('views-A', [0, 1], [{ kind: 'path', index: 1, path: 'renamed.bin' }]), PATH);
  record(c, 'registry', 'A valid byte reference cannot authorize a renamed path in a private view copy.');
}
{
  const c = new AuthoredCase('client-registry-duplicate-reference-refusal', { A: small() });
  c.begin('A'); c.publish('A', 'views-A'); c.download(c.select('views-A', [0, 0]), true, REFERENCE); c.archive(c.select('views-A', [0, 0]), REFERENCE);
  record(c, 'registry', 'An inventory-sized selection still refuses duplicate verified references.');
}
{
  const c = new AuthoredCase('client-registry-complete-and-single-selection-rules', { A: small() });
  c.begin('A'); c.publish('A', 'views-A'); c.download(c.select('views-A', [0]), true, SELECTION); c.archive(c.select('views-A', [0]), SELECTION);
  c.download(c.select('views-A', [0, 1]), false, SELECTION); c.download(c.select('views-A', [0]), false);
  record(c, 'registry', 'Complete archive/download requires whole inventory; single-file download requires exactly one selected file.');
}
{
  const c = new AuthoredCase('client-registry-replacement-refuses-old-owner', { A: small(), B: small() });
  c.begin('A'); c.begin('B'); c.publish('A', 'views-A'); c.publish('B', 'views-B');
  c.download(c.select('views-A', [0]), false, REFERENCE); c.archive(c.select('views-A', [0, 1]), REFERENCE);
  c.download(c.select('views-B', [0, 1]), true);
  record(c, 'registry', 'Registry replacement refuses old references even when both owners have identical paths and bytes.');
}
{
  const c = new AuthoredCase('client-registry-foreign-reference-refusal', { A: small(), B: small() });
  c.begin('A'); c.begin('B'); c.publish('A', 'views-A'); c.publish('B', 'views-B');
  const mutation = [{ kind: 'reference', index: 0, fromViews: 'views-A', fromIndex: 0 }];
  c.download(c.select('views-B', [0], mutation), false, REFERENCE); c.archive(c.select('views-B', [0, 1], mutation), REFERENCE);
  record(c, 'registry', 'Forged foreign reference is refused despite matching content, metadata and selected current view path.');
}
{
  const c = new AuthoredCase('client-registry-republication-does-not-merge-identities', { A: small() });
  c.begin('A'); c.publish('A', 'views-A'); c.publish('A', 'views-A-again');
  c.download(c.select('views-A', [0]), false, REFERENCE); c.download(c.select('views-A-again', [0, 1]), true);
  record(c, 'registry', 'Two publications of the same verified owner remain distinct view identities.');
}

// Local faults are represented safely in source JSON, then applied privately
// by the scenario driver immediately before construction. Exact typed reasons
// are contract evidence; UI English is deliberately not a compatibility oracle.
for (const field of ['ir', 'options']) {
  for (const unit of ['high', 'low']) {
    for (const mode of ['value', 'key']) {
      const c = make('client-local-unicode-' + field + '-' + mode + '-' + unit, [fixed('empty-binary', 'empty.bin')]);
      const d = c.definitions[0];
      d.input.ir = { nested: { value: 'safe', key: 'safe' } };
      d.input.options = { nested: { value: 'safe', key: 'safe' } };
      d.localFaults = [{ kind: 'unpaired-surrogate-' + mode, field,
        path: [{ kind: 'member', key: 'nested' }, { kind: 'member', key: mode }], unit }];
      c.context('A');
      c.act({ action: 'start', attempt: 'A' }, () => {
        Object.assign(c.states.A, { phase: 'construction-refused', terminal: { kind: 'construction-refused' } });
        c.results.A = { kind: 'construction-refused', failure: { kind: 'input', reason: 'ill-formed-unicode' } };
      });
      record(c, 'local-input', 'Lone ' + unit + ' surrogate in ' + field + ' ' + mode + ' refuses construction before capture or any effect.');
    }
  }
  for (const value of ['nan', 'positive-infinity', 'negative-infinity']) {
    const c = make('client-local-nonfinite-' + field + '-' + value, [fixed('empty-binary', 'empty.bin')]);
    const d = c.definitions[0];
    d.input.ir = { nested: { number: 0 } }; d.input.options = { nested: { number: 0 } };
    d.localFaults = [{ kind: 'nonfinite-number', field, path: [{ kind: 'member', key: 'nested' }, { kind: 'member', key: 'number' }], value }];
    c.context('A');
    c.act({ action: 'start', attempt: 'A' }, () => {
      Object.assign(c.states.A, { phase: 'construction-refused', terminal: { kind: 'construction-refused' } });
      c.results.A = { kind: 'construction-refused', failure: { kind: 'input', reason: 'nonfinite-number' } };
    });
    record(c, 'local-input', value + ' in ' + field + ' refuses construction before capture or any effect.');
  }
}

const receipts: any[] = [];
for (const item of authored) {
  const name = 'cases/' + item.value.id + '.json';
  const source = JSON.stringify(item.value) + '\n';
  const target = resolve(own, name);
  const prior = await readFile(target, 'utf8').catch((error: NodeJS.ErrnoException) => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  if (prior !== null && prior !== source) throw new Error('Refusing to rewrite a frozen case: ' + item.value.id);
  if (prior === null) await writeFile(target, source);
  receipts.push({ id: item.value.id, path: name, caseSha256: sha(source),
    inputSha256: sha(JSON.stringify(item.value.input)), expectedSha256: sha(JSON.stringify(item.value.expected)),
    inputBytes: item.inputBytes, evidenceBytes: item.evidenceBytes, readWorkBytes: item.readWork,
    observationWorkBytes: item.observationWork, rawResponseWorkUpperBound: item.rawWorkUpperBound });
}
await writeFile(resolve(own, 'coverage-matrix.json'), JSON.stringify({ status: 'independently authored; not adapter-qualified', cases: coverage }, null, 2) + '\n');
await writeFile(resolve(own, 'authored-manifest.json'), JSON.stringify({
  status: 'frozen independent expected cases before adapter execution', operation: 'artifact-client', draft: '0.1.0-draft.28',
  adapterExecuted: false, observedEvidenceRead: false, caseCount: receipts.length,
  totalReadWorkBytes: authored.reduce((sum, item) => sum + item.readWork, 0),
  totalObservationWorkBytes: authored.reduce((sum, item) => sum + item.observationWork, 0),
  totalRawResponseWorkUpperBound: authored.reduce((sum, item) => sum + item.rawWorkUpperBound, 0),
  sourceSha256: sha(await readFile(new URL(import.meta.url))),
  foundation: { path: foundation, sha256: sha(await readFile(foundation)) },
  approvedSources: [{"path":"../artifact-client-contract.html","sha256":"341ea2e47fd9c0e4d33fbb2b5f76e3c5e044021be2f2a1c7b4a0c7468ec6a8c1"},{"path":"../artifact-client-contract.types.ts","sha256":"e843ed694f01841bc5fccf68c748d4a87056a78ffc0bb047b0d637d7dce01997"},{"path":"../client-first-case.json","sha256":"7dd50da617c3e095c3bacfddc98d70e91a9b6078da701733bf742bd7f9a15571"}],
  fixedRegistryMessages: { source: 'apps/morphir-workbench/browser/artifact-registry.ts:48', approval: 'parent_qualification approved source-backed messages; no production outputs read' },
  archiveLength: 'Independent standard stored-ZIP envelope estimate; exact entries/hashes are normative, encoded container length is only structurally bounded by shared checker.',
  recipes: 'Whole-file immutable hashes crosschecked against preimplementation catalog. New preview hashes derive only from independently specified bytes and standard SHA256/UTF8.',
  cases: receipts,
}, null, 2) + '\n');
console.log(JSON.stringify({ cases: receipts.length, readWorkBytes: authored.reduce((sum, item) => sum + item.readWork, 0),
  observationWorkBytes: authored.reduce((sum, item) => sum + item.observationWork, 0),
  rawResponseWorkUpperBound: authored.reduce((sum, item) => sum + item.rawWorkUpperBound, 0),
  maximumEvidenceBytes: Math.max(...receipts.map(item => item.evidenceBytes)) }));
