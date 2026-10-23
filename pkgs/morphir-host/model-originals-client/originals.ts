import {parse, format} from '@std/semver';
import {parseArtifactFrame, integer, ExactJsonNumber, type ExactJson} from '../artifact-client/artifact-client/artifact-wire.ts';
import {parseRelativeArtifactPath} from '../artifact-client/artifact-client/artifact-path.ts';
import {unicode17Nfc, unicode17Nfkc, unicode9FullDefaultCaseFold} from '../artifact-client/artifact-client/artifact-unicode.ts';
import type {ModelOriginalsSession, ModelOriginalsProject, ModelOriginalsCaptureExchange} from './session.ts';

export const ORIGINALS_PROFILE = 'morphir/workbench/model-originals';
export const ORIGINALS_VERSION = '0.1.0-draft.1';
const byteLimit = 67108864, entryLimit = 100064;
const encoder = new TextEncoder();
export class OriginalsFailure extends Error {
  readonly code: string;
  constructor(code: string) { super(code); this.code = code; }
}
function fail(code = 'originals.invalid_frame'): never { throw new OriginalsFailure(code); }
type ObjectValue = ReadonlyMap<string, ExactJson>;
function object(value: ExactJson | undefined): ObjectValue {
  if (!(value instanceof Map)) fail();
  return value;
}
function fields(value: ExactJson | undefined, names: string[]): ObjectValue {
  const result = object(value);
  if (result.size !== names.length || names.some(name => !result.has(name))) fail();
  return result;
}
function text(value: ExactJson | undefined): string { if (typeof value !== 'string') fail(); return value; }
function list(value: ExactJson | undefined): readonly ExactJson[] { if (!Array.isArray(value)) fail(); return value; }
function count(value: ExactJson | undefined, max: number, min = 0): number {
  if (value === undefined) fail();
  return integer(value, min, max);
}
function identity(value: ExactJson | undefined, maximum = 128): string {
  const result = text(value);
  if (!result || result.length > maximum || encoder.encode(result).length > maximum || /[\u0000-\u001f\u007f-\u009f]/.test(result)) fail();
  return result;
}
function hash(value: ExactJson | undefined): string {
  const result = text(value); if (!/^[0-9a-f]{64}$/.test(result)) fail(); return result;
}
function equal(value: unknown, expected: unknown): void { if (value !== expected) fail('originals.binding_changed'); }
function prefix(value: ObjectValue): void {
  equal(value.get('profile'), ORIGINALS_PROFILE); equal(value.get('contractVersion'), ORIGINALS_VERSION);
}
export interface Binding {sessionId: string; source: {providerId: string; locator: string}; projectId: string;}
/** A business boundary, after release validation and the final active check.
 * The optional observer receives literal exchange bytes without transport or
 * source authority. It cannot prevent application completion by throwing.
 */
export interface ReleaseAccepted {
  readonly captureId: string;
  readonly binding: Readonly<{sessionId:string;source:Readonly<{providerId:string;locator:string}>;projectId:string}>;
  readonly exchange: ModelOriginalsCaptureExchange;
}
function binding(value: ExactJson | undefined, expected: Binding): void {
  const root = fields(value, ['sessionId','source','projectId']);
  const source = fields(root.get('source'), ['providerId','locator']);
  equal(identity(root.get('sessionId')), expected.sessionId);
  equal(identity(source.get('providerId')), expected.source.providerId);
  equal(identity(source.get('locator'),4096), expected.source.locator);
  equal(identity(root.get('projectId'),12288), expected.projectId);
}
export function originalPath(value: ExactJson | undefined, maxDepth = 256): string {
  const result = text(value), parts = result.split('/');
  if (!result || result.length > 8000 || encoder.encode(result).length > 16000 || [...result].length > 4000 || parts.length > maxDepth ||
      parts.some(part => !parseRelativeArtifactPath(part).ok)) fail('originals.invalid_path');
  return result;
}
export type Root = {kind: 'file' | 'directory'; path: string};
export type Entry = {kind: 'directory'; entryId: string; path: string} |
  {kind: 'file'; entryId: string; path: string; byteLength: number; sha256: string};
function root(value: ExactJson | undefined): Root {
  const item = fields(value,['kind','path']);
  if (item.get('kind') !== 'file' && item.get('kind') !== 'directory') fail();
  return {kind: item.get('kind') as Root['kind'], path: originalPath(item.get('path'),128)};
}
function entry(value: ExactJson): Entry {
  const item = object(value), kind = item.get('kind');
  if (kind !== 'file' && kind !== 'directory') fail();
  fields(item,kind === 'file' ? ['kind','entryId','path','byteLength','sha256'] : ['kind','entryId','path']);
  const shared = {entryId: identity(item.get('entryId')), path: originalPath(item.get('path'))};
  return kind === 'file' ? {kind,...shared,byteLength:count(item.get('byteLength'),byteLimit),sha256:hash(item.get('sha256'))} : {kind,...shared};
}
export interface Capture {
  captureId: string; roots: Root[]; entryCount: number; fileCount: number; directoryCount: number;
  sourceByteLength: number; sha256: string; sourceFormatVersion: {status:'not-reported'} | {status:'reported';release:string};
}
function result(exchange: ModelOriginalsCaptureExchange): ObjectValue {
  const envelope = fields(parseArtifactFrame(exchange.reply),['jsonrpc','id','result']);
  equal(envelope.get('jsonrpc'),'2.0');
  const id = envelope.get('id');
  if (!(id instanceof ExactJsonNumber) || id.lexeme !== exchange.requestId) fail();
  return object(envelope.get('result'));
}
function captureEnvelope(exchange: ModelOriginalsCaptureExchange, expected: Binding): ObjectValue {
  const value = result(exchange); prefix(value);
  if (value.get('status') === 'unavailable') {
    fields(value,['profile','contractVersion','status','reason']);
    if (!['not_compiled','companions_undeclared','unsupported_representation'].includes(text(value.get('reason')))) fail();
    fail('originals.' + text(value.get('reason')));
  }
  fields(value,['profile','contractVersion','status','binding','captureId','coverage','origin','primary','companions','sourceFormatVersion','projection','inventory']);
  equal(value.get('status'),'ready'); binding(value.get('binding'),expected);
  const coverage = fields(value.get('coverage'),['kind','declaration']);
  equal(coverage.get('kind'),'complete'); equal(coverage.get('declaration'),ORIGINALS_VERSION);
  return value;
}
function captureBody(value: ObjectValue): Capture {
  const primary = root(value.get('primary')), companions = list(value.get('companions'));
  if (companions.length > 63) fail();
  const roots = [primary,...companions.map(root)];
  const key = (path: string) => unicode17Nfc(unicode9FullDefaultCaseFold(unicode17Nfkc(path)));
  const rootKeys = roots.map(item => key(item.path));
  for (let i=0;i<rootKeys.length;i++) for (let j=0;j<i;j++) {
    if (rootKeys[i] === rootKeys[j] || rootKeys[i]!.startsWith(rootKeys[j]!+'/') || rootKeys[j]!.startsWith(rootKeys[i]!+'/')) fail('originals.invalid_roots');
  }
  const origin = object(value.get('origin'));
  if (origin.get('kind') === 'compiled') {
    fields(origin,['kind','record']);
    const record = fields(origin.get('record'),['byteLength','sha256','schema','task','module','ir']);
    count(record.get('byteLength'),byteLimit); hash(record.get('sha256')); equal(count(record.get('schema'),1),1); equal(record.get('task'),'compile');
    const module = text(record.get('module')); if (module !== '') originalPath(module,128);
    const ir = fields(record.get('ir'),['path','layout','format','version']);
    equal(originalPath(ir.get('path'),128),primary.path);
    if (!['json','yaml','ion'].includes(text(ir.get('format'))) || !['v3','v4'].includes(text(ir.get('version')))) fail();
    equal(ir.get('layout'), primary.kind === 'file' ? 'single-file' : 'document-tree');
  } else {
    fields(origin,['kind','path']); equal(origin.get('kind'),'legacy-json'); equal(origin.get('path'),'morphir-ir.json');
    equal(primary.kind,'file'); equal(primary.path,'morphir-ir.json');
  }
  const sourceVersion = object(value.get('sourceFormatVersion'));
  let sourceFormatVersion: Capture['sourceFormatVersion'];
  if (sourceVersion.get('status') === 'not-reported') {
    fields(sourceVersion,['status']); sourceFormatVersion = {status:'not-reported'};
  } else {
    fields(sourceVersion,['status','release']); equal(sourceVersion.get('status'),'reported');
    const release = text(sourceVersion.get('release')), parsed = parse(release);
    if (format(parsed) !== release || parsed.prerelease?.length || parsed.build?.length ||
        [parsed.major,parsed.minor,parsed.patch].some(n=>n>4294967295)) fail();
    sourceFormatVersion = {status:'reported',release};
  }
  const inventory = fields(value.get('inventory'),['entryCount','fileCount','directoryCount','sourceByteLength','sha256']);
  const capture = {captureId:identity(value.get('captureId')),roots,sourceFormatVersion,
    entryCount:count(inventory.get('entryCount'),entryLimit),fileCount:count(inventory.get('fileCount'),entryLimit),
    directoryCount:count(inventory.get('directoryCount'),entryLimit),sourceByteLength:count(inventory.get('sourceByteLength'),byteLimit),sha256:hash(inventory.get('sha256'))};
  if (capture.entryCount !== capture.fileCount+capture.directoryCount) fail();
  return capture;
}
export function readCapture(exchange: ModelOriginalsCaptureExchange, expected: Binding): Capture {
  const value = captureEnvelope(exchange, expected);
  equal(fields(value.get('projection'),['status']).get('status'),'not-requested');
  return captureBody(value);
}
export type ProjectionUnavailableReason = 'unsupported_representation' | 'invalid_model' | 'decode_limit' | 'projection_limit' | 'capacity' | 'timeout';
type ProjectionDescriptor = Readonly<{kind:'available';byteLength:number;sha256:string;formatVersion:string}>
  | Readonly<{kind:'unavailable';reason:ProjectionUnavailableReason}>;
function readProjection(value: ExactJson | undefined): ProjectionDescriptor {
  const item = object(value);
  if (item.get('status') === 'unavailable') {
    fields(item,['status','reason']);
    const reason = text(item.get('reason'));
    if (!['unsupported_representation','invalid_model','decode_limit','projection_limit','capacity','timeout'].includes(reason)) fail();
    return {kind:'unavailable',reason:reason as ProjectionUnavailableReason};
  }
  fields(item,['status','codec','byteLength','sha256','formatVersion']);
  equal(item.get('status'),'available'); equal(item.get('codec'),'morphir-json');
  const release = text(item.get('formatVersion')), parsed = parse(release);
  if (format(parsed) !== release || parsed.prerelease?.length || parsed.build?.length ||
      [parsed.major,parsed.minor,parsed.patch].some(n=>n>4294967295)) fail();
  return {kind:'available',byteLength:count(item.get('byteLength'),byteLimit),sha256:hash(item.get('sha256')),formatVersion:release};
}
const verifiedProjection = Symbol('verified-projection');
/** Receiver-owned projection bytes. Neither construction nor a copy grants source authority. */
class OwnedVerifiedProjection {
  readonly #bytes: Uint8Array;
  readonly formatVersion: string;
  constructor(token: typeof verifiedProjection, bytes: Uint8Array, formatVersion: string) {
    if (token !== verifiedProjection) throw new Error('Only the projection receiver constructs verified bytes.');
    this.#bytes = bytes; this.formatVersion = formatVersion; Object.freeze(this);
  }
  copyBytes(): Uint8Array {return this.#bytes.slice();}
}
export type VerifiedProjection = OwnedVerifiedProjection;
// Capture the real private-field reader. A structural object, a changed public
// method or a prototype-shaped impostor cannot grant projection input ownership.
const copyOwnedProjection = OwnedVerifiedProjection.prototype.copyBytes;
export function copyVerifiedProjection(value: VerifiedProjection): Uint8Array {
  return copyOwnedProjection.call(value);
}
export type ReceivedProjection = Readonly<{kind:'verified';value:VerifiedProjection}>
  | Readonly<{kind:'unavailable';reason:ProjectionUnavailableReason}>
  | Readonly<{kind:'unusable';reason:'transfer-invalid'|'header-invalid'|'header-mismatch'}>;
export interface Hasher {update(bytes: Uint8Array): void; hex(): string;}
export interface OriginalSink {
  inventory(entries: readonly Entry[], capture: Capture): void;
  begin(index: number): void; write(bytes: Uint8Array): void; end(): void;
}
function u32(value: number): Uint8Array {const bytes=new Uint8Array(4);new DataView(bytes.buffer).setUint32(0,value);return bytes;}
function u64(value: number): Uint8Array {const bytes=new Uint8Array(8);new DataView(bytes.buffer).setBigUint64(0,BigInt(value));return bytes;}
export function inventoryDigest(entries: readonly Entry[], hasher: Hasher): string {
  hasher.update(encoder.encode(ORIGINALS_PROFILE+'/'+ORIGINALS_VERSION+'\0')); hasher.update(u32(entries.length));
  for (const item of entries) {
    const path=encoder.encode(item.path); hasher.update(Uint8Array.of(item.kind==='file'?1:0));hasher.update(u32(path.length));hasher.update(path);
    if (item.kind==='file') {hasher.update(u64(item.byteLength));hasher.update(Uint8Array.from(item.sha256.match(/../g)!,part=>parseInt(part,16)));}
  }
  return hasher.hex();
}
/** Whole-inventory validation is independent of page boundaries and wire IDs. */
export function verifyInventory(entries: readonly Entry[], capture: Capture, hasher: Hasher): void {
  if (entries.length !== capture.entryCount) fail('originals.incomplete_inventory');
  const ids=new Set<string>(), paths=new Map<string,Entry>(), spellings=new Map<string,string>();
  const key=(path:string)=>unicode17Nfc(unicode9FullDefaultCaseFold(unicode17Nfkc(path)));
  let previous: Uint8Array | undefined, total=0, files=0, directories=0;
  for (const item of entries) {
    const bytes=encoder.encode(item.path);
    if (previous) {
      let i=0;while(i<previous.length&&i<bytes.length&&previous[i]===bytes[i])i++;
      if(i===bytes.length || (i<previous.length && previous[i]!>=bytes[i]!))fail('originals.inventory_order');
    }
    previous=bytes;
    if(ids.has(item.entryId))fail('originals.duplicate_identity');ids.add(item.entryId);
    const parts=item.path.split('/'), keys:string[]=[], names:string[]=[];
    for (const part of parts) {
      keys.push(key(part));names.push(part);const identity=JSON.stringify(keys), spelling=names.join('/');
      const prior=spellings.get(identity);if(prior!==undefined&&prior!==spelling)fail('originals.path_alias');spellings.set(identity,spelling);
    }
    const identity=JSON.stringify(keys);if(paths.has(identity))fail('originals.path_alias');paths.set(identity,item);
    const owner=capture.roots.find(root=>root.path===item.path || root.kind==='directory'&&item.path.startsWith(root.path+'/'));
    if(!owner || parts.length-owner.path.split('/').length>128)fail('originals.outside_inventory');
    if(item.kind==='file'){files++;total+=item.byteLength;if(total>byteLimit)fail('originals.byte_limit');}else directories++;
  }
  for(const item of entries){
    const parts=item.path.split('/');
    for(let i=1;i<parts.length;i++){
      const ancestor=paths.get(JSON.stringify(parts.slice(0,i).map(key)));
      if(ancestor?.kind==='file')fail('originals.file_ancestor');
      if(capture.roots.some(root=>root.kind==='directory'&&(root.path===parts.slice(0,i).join('/')||parts.slice(0,i).join('/').startsWith(root.path+'/'))) && !ancestor)fail('originals.missing_directory');
    }
  }
  for(const root of capture.roots){const found=paths.get(JSON.stringify(root.path.split('/').map(key)));if(!found||found.kind!==root.kind||found.path!==root.path)fail('originals.missing_root');}
  if(files!==capture.fileCount||directories!==capture.directoryCount||total!==capture.sourceByteLength||entries.length-capture.roots.length>100000)fail('originals.inventory_totals');
  equal(inventoryDigest(entries,hasher),capture.sha256);
}
function retained(value: ObjectValue, expected: Binding, capture: Capture): void {
  prefix(value);binding(value.get('binding'),expected);equal(value.get('captureId'),capture.captureId);
}
async function receiveInventory(session: ModelOriginalsSession, expected: Binding, capture: Capture,
  makeHash:()=>Hasher, active:()=>void): Promise<Entry[]> {
  const entries:Entry[]=[];const pages:{start:number;length:number}[]=[];let metadata=0;
  for(;;){
    active();const startIndex=entries.length;
    const value=result(await session.exchangeOriginals('inventory',{captureId:capture.captureId,startIndex,maxEntries:256}));
    fields(value,['profile','contractVersion','binding','captureId','inventorySha256','startIndex','entries','next']);retained(value,expected,capture);
    equal(value.get('inventorySha256'),capture.sha256);equal(count(value.get('startIndex'),entryLimit),startIndex);
    const page=list(value.get('entries'));if(page.length>256||page.length>capture.entryCount-startIndex)fail();
    pages.push({start:startIndex,length:page.length});
    for(const raw of page){const item=entry(raw);metadata+=encoder.encode(item.path).length+encoder.encode(item.entryId).length+128;if(metadata>byteLimit)fail('originals.metadata_limit');entries.push(item);}
    const next=object(value.get('next'));
    if(next.get('kind')==='complete'){fields(next,['kind']);if(entries.length!==capture.entryCount)fail('originals.incomplete_inventory');break;}
    fields(next,['kind','startIndex']);equal(next.get('kind'),'more');equal(count(next.get('startIndex'),entryLimit),entries.length);
    if(!page.length||entries.length>=capture.entryCount)fail('originals.inventory_progress');
  }
  verifyInventory(entries,capture,makeHash());
  for(const page of pages){
    const fits=(length:number)=>{
      const end=page.start+length;
      const reply={profile:ORIGINALS_PROFILE,contractVersion:ORIGINALS_VERSION,binding:expected,captureId:capture.captureId,
        inventorySha256:capture.sha256,startIndex:page.start,entries:entries.slice(page.start,end),
        next:end===entries.length?{kind:'complete'}:{kind:'more',startIndex:end}};
      return encoder.encode(`{"jsonrpc":"2.0","id":18446744073709551615,"result":${JSON.stringify(reply)}}`).length<=131072;
    };
    let low=0,high=Math.min(256,entries.length-page.start);
    while(low<high){const mid=Math.ceil((low+high)/2);if(fits(mid))low=mid;else high=mid-1;}
    if(page.length!==low)fail('originals.noncanonical_pagination');
  }
  return entries;
}
type ReadTarget = Readonly<{kind:'original';entryId:string}> | Readonly<{kind:'semantic-projection'}>;
function readChunk(exchange: ModelOriginalsCaptureExchange, expected: Binding, capture: Capture,
  target: ReadTarget, offset: number, length: number): Uint8Array {
  const value=result(exchange);
  fields(value,['profile','contractVersion','binding','captureId','target','offset','nextOffset','content']);retained(value,expected,capture);
  const observed=fields(value.get('target'),target.kind==='original'?['kind','entryId']:['kind']);
  equal(observed.get('kind'),target.kind);
  if(target.kind==='original')equal(observed.get('entryId'),target.entryId);
  equal(count(value.get('offset'),byteLimit),offset);
  const next=count(value.get('nextOffset'),byteLimit),encoded=text(value.get('content'));
  if(encoded.length>87384||!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded))fail('originals.invalid_content');
  const binary=atob(encoded),bytes=Uint8Array.from(binary,c=>c.charCodeAt(0));
  if(btoa(binary)!==encoded||bytes.length!==Math.min(65536,length-offset)||next!==offset+bytes.length||next>length)fail('originals.invalid_chunk');
  return bytes;
}
async function receiveFiles(session: ModelOriginalsSession, expected: Binding, capture: Capture,
  entries: Entry[], sink: OriginalSink, makeHash:()=>Hasher, active:()=>void): Promise<void> {
  active();sink.inventory(entries,capture);
  for(const [index,item] of entries.entries()){
    if(item.kind!=='file')continue;
    active();sink.begin(index);const hasher=makeHash();let offset=0;
    do {
      active();const target={kind:'original',entryId:item.entryId};
      const exchange=await session.exchangeOriginals('read',{captureId:capture.captureId,target,offset,maxBytes:65536});
      const bytes=readChunk(exchange,expected,capture,{kind:'original',entryId:item.entryId},offset,item.byteLength);
      active();hasher.update(bytes);sink.write(bytes);offset+=bytes.length;
    }while(offset<item.byteLength);
    equal(hasher.hex(),item.sha256);sink.end();
  }
}
async function releaseCapture(session: ModelOriginalsSession, expected: Binding, capture: Capture,
  active:()=>void, accepted?: (value:ReleaseAccepted)=>void): Promise<void> {
  active();const exchange=await session.exchangeOriginals('release',{captureId:capture.captureId});
  const released=result(exchange);
  fields(released,['profile','contractVersion','captureId','status']);prefix(released);equal(released.get('captureId'),capture.captureId);equal(released.get('status'),'released');
  active();
  if(accepted){
    try{
      accepted(Object.freeze({captureId:capture.captureId,
        binding:Object.freeze({sessionId:expected.sessionId,source:Object.freeze({...expected.source}),projectId:expected.projectId}),
        exchange:Object.freeze({...exchange})}));
    }catch{/* Observation cannot change the accepted application result. */}
  }
}
/** Verify every original on the owning connection, then require release before publication. */
export async function receiveOriginals(session: ModelOriginalsSession, project: ModelOriginalsProject,
  expected: Binding, sink: OriginalSink, makeHash:()=>Hasher, current:()=>boolean,
  accepted?:(value:ReleaseAccepted)=>void): Promise<{capture:Capture;entries:Entry[]}> {
  const active=()=>{if(!current())fail('originals.cancelled');};
  active();const capture=readCapture(await session.exchangeCapture(project,{scope:'complete',semantic:'none'}),expected);
  const entries=await receiveInventory(session,expected,capture,makeHash,active);
  await receiveFiles(session,expected,capture,entries,sink,makeHash,active);
  await releaseCapture(session,expected,capture,active,accepted);
  return{capture,entries};
}
async function receiveProjection(session: ModelOriginalsSession, expected: Binding, capture: Capture,
  descriptor: ProjectionDescriptor, makeHash:()=>Hasher, active:()=>void,
  recognizeHeader:(actualBytes:Uint8Array)=>string): Promise<ReceivedProjection> {
  if(descriptor.kind==='unavailable')return descriptor;
  const owned=new Uint8Array(descriptor.byteLength),hasher=makeHash();
  let offset=0;
  do {
    active();const target={kind:'semantic-projection'} as const;
    // A real transport rejection remains a rejection. Only local validation of
    // a returned projection frame can leave verified originals usable.
    const exchange=await session.exchangeOriginals('read',{captureId:capture.captureId,target,offset,maxBytes:65536});
    active();
    let bytes:Uint8Array;
    try{bytes=readChunk(exchange,expected,capture,target,offset,descriptor.byteLength);}
    catch{return{kind:'unusable',reason:'transfer-invalid'};}
    owned.set(bytes,offset);hasher.update(bytes);offset+=bytes.length;
  }while(offset<descriptor.byteLength);
  if(hasher.hex()!==descriptor.sha256)return{kind:'unusable',reason:'transfer-invalid'};
  // The recognizer may retain or mutate its input. It never receives the
  // private backing whose digest was verified or the copy returned to callers.
  const headerInput=owned.slice();
  let actualVersion:string;
  try{actualVersion=recognizeHeader(headerInput);}
  catch{active();return{kind:'unusable',reason:'header-invalid'};}
  active();
  if(actualVersion!==descriptor.formatVersion)return{kind:'unusable',reason:'header-mismatch'};
  return{kind:'verified',value:new OwnedVerifiedProjection(verifiedProjection,owned,actualVersion)};
}
/** Complete originals remain independently verified when projection is unavailable
 * or unusable. No result is returned before strict release and final currentness.
 * The injected recognizer is a trusted pure dependency, not consumer authority.
 */
export async function receiveOriginalsWithProjection(session: ModelOriginalsSession, project: ModelOriginalsProject,
  expected: Binding, sink: OriginalSink, makeHash:()=>Hasher, current:()=>boolean,
  recognizeHeader:(actualBytes:Uint8Array)=>string,
  accepted?:(value:ReleaseAccepted)=>void): Promise<{capture:Capture;entries:Entry[];projection:ReceivedProjection}> {
  const active=()=>{if(!current())fail('originals.cancelled');};
  active();const value=captureEnvelope(await session.exchangeCapture(project,{scope:'complete',semantic:'projection'}),expected);
  const descriptor=readProjection(value.get('projection')),capture=captureBody(value);
  const entries=await receiveInventory(session,expected,capture,makeHash,active);
  await receiveFiles(session,expected,capture,entries,sink,makeHash,active);
  const projection=await receiveProjection(session,expected,capture,descriptor,makeHash,active,recognizeHeader);
  await releaseCapture(session,expected,capture,active,accepted);
  return{capture,entries,projection};
}
