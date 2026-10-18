import type {Target, RequestOptions} from './api.mjs';
import type {AssemblyResult, AssemblyIdentity, PackagePin, PackageEvidence, PackageImport, Optimization} from './assembly.mjs';
import {sha256, AssemblyFailure} from './assembly.mjs';

export type ManifestEncoding = 'ion' | 'json';
export interface ExecutionProfile { readonly id: string; readonly sha256: string; }
export type ArtifactOrigin =
  | {readonly kind:'moonbit-source'; readonly sha256:string}
  | {readonly kind:'morphir-model'; readonly id:string; readonly revision:string; readonly sha256:string};
export interface ModelOrigin { readonly id:string; readonly revision:string; readonly bytes:Uint8Array<ArrayBuffer>; }
/** Local draft schema. It is independent of the draft Morphir IR format 4.0.0. */
export interface ArtifactManifest {
  readonly schema:'morphir-assembly-artifact-v1-draft';
  readonly root:PackagePin;
  readonly identity:AssemblyIdentity;
  readonly packages:readonly PackageEvidence[];
  readonly origin:ArtifactOrigin;
  readonly artifact:{readonly sha256:string; readonly size:number; readonly target:Target};
  readonly invocation:{readonly abi:'core-wasm'; readonly profile:ExecutionProfile;
    readonly exports:readonly string[]; readonly imports:readonly WebAssembly.ModuleImportDescriptor[]};
  readonly optimization:Optimization;
}
export interface SavedArtifact {
  readonly wasm:Uint8Array<ArrayBuffer>;
  readonly manifest:Uint8Array<ArrayBuffer>;
  readonly encoding:ManifestEncoding;
}
export interface PreparedArtifact extends SavedArtifact { readonly record:ArtifactManifest; readonly metadataIon:string; }
// DOM typings expose Tag but omit it from WebAssembly.ImportValue.
export type ArtifactImports=Record<string,Record<string,WebAssembly.ImportValue|WebAssembly.Tag>>;
export interface ArtifactHost {
  readonly targets:readonly Target[];
  readonly profiles:readonly ExecutionProfile[];
  readonly encodings:readonly ManifestEncoding[];
  readonly imports?:ArtifactImports;
}
export interface LoadedArtifact {
  readonly manifest:ArtifactManifest;
  readonly metadataIon:string;
  invoke(name:string, args?:readonly (number|bigint)[]):unknown;
  dispose():void;
}
export interface ArtifactTransaction {
  write(name:'model.wasm'|'manifest.ion'|'manifest.json', bytes:Uint8Array<ArrayBuffer>):Promise<void>;
  /** Atomically exposes the completed set. Must not overwrite an existing publication. */
  commit():Promise<void>;
  abort():Promise<void>;
}
export interface ArtifactStore { begin():Promise<ArtifactTransaction>; }

const fail = (message:string):never => { throw new AssemblyFailure('input',message); };
const check = (signal?:AbortSignal) => { if (signal?.aborted) throw new DOMException('Cancelled','AbortError'); };
const bridge = () => import(new URL('./dist/bridge.mjs',import.meta.url).href) as Promise<typeof import('./bridge.mjs')>;
const object = (value:unknown, keys:readonly string[]):Record<string,unknown> => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fail('Expected manifest object');
  const result = value as Record<string,unknown>;
  if (Object.keys(result).length !== keys.length || keys.some(k => !Object.hasOwn(result,k))) return fail('Unknown or missing manifest field');
  return result;
};
const text = (value:unknown):string => typeof value === 'string' && value.length > 0 ? value : fail('Expected nonempty manifest text');
const digest = (value:unknown):string => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value) ? value : fail('Invalid manifest digest');
const list = (value:unknown):unknown[] => Array.isArray(value) ? value : fail('Expected manifest array');
const pin = (value:unknown):PackagePin => { const p=object(value,['name','sha256']);return {name:text(p.name),sha256:digest(p.sha256)}; };
const profile = (value:unknown):ExecutionProfile => { const p=object(value,['id','sha256']);return {id:text(p.id),sha256:digest(p.sha256)}; };
const target = (value:unknown):Target => value === 'wasm' || value === 'wasm-gc' ? value : fail('Invalid manifest target');
const optimization = (value:unknown):Optimization => value === 'optimized' || value === 'unoptimized' ? value : fail('Invalid manifest optimization');
function identity(value:unknown):AssemblyIdentity {
  const p=object(value,['compilerVersion','coreSha256','sdkSha256']);
  return {compilerVersion:text(p.compilerVersion),coreSha256:digest(p.coreSha256),sdkSha256:digest(p.sdkSha256)};
}
function evidence(value:unknown):PackageEvidence {
  const p=object(value,['pin','role','dependencies','form','optimization']);
  const role=p.role === 'core' || p.role === 'sdk' || p.role === 'library' ? p.role : fail('Invalid package role');
  const form=p.form === 'source' || p.form === 'prebuilt' ? p.form : fail('Invalid package form');
  const dependencies:PackageImport[]=list(p.dependencies).map(value => {
    const d=object(value,['name','pin']);return {name:text(d.name),pin:pin(d.pin)};
  });
  return {pin:pin(p.pin),role,form,dependencies,optimization:optimization(p.optimization)};
}
function importDescriptor(value:unknown):WebAssembly.ModuleImportDescriptor {
  const p=object(value,['module','name','kind']);
  const kind=p.kind === 'function' || p.kind === 'global' || p.kind === 'memory' || p.kind === 'table' || p.kind === 'tag' ? p.kind : fail('Unsupported Wasm import kind');
  return {module:typeof p.module === 'string' ? p.module : fail('Invalid import module'),
    name:typeof p.name === 'string' ? p.name : fail('Invalid import name'),kind};
}
function origin(value:unknown):ArtifactOrigin {
  if (value && typeof value === 'object' && 'kind' in value && value.kind === 'moonbit-source') {
    const p=object(value,['kind','sha256']); return {kind:'moonbit-source',sha256:digest(p.sha256)};
  }
  const p=object(value,['kind','id','revision','sha256']);
  if (p.kind !== 'morphir-model') return fail('Invalid model origin');
  return {kind:'morphir-model',id:text(p.id),revision:text(p.revision),sha256:digest(p.sha256)};
}
async function manifest(value:unknown):Promise<ArtifactManifest> {
  const p=object(value,['schema','root','identity','packages','origin','artifact','invocation','optimization']);
  if (p.schema !== 'morphir-assembly-artifact-v1-draft') return fail('Unknown draft manifest schema');
  const a=object(p.artifact,['sha256','size','target']);
  if (typeof a.size !== 'number' || !Number.isSafeInteger(a.size) || a.size <= 0) return fail('Invalid Wasm byte length');
  const i=object(p.invocation,['abi','profile','exports','imports']);
  if (i.abi !== 'core-wasm') return fail('Unsupported artifact ABI');
  const exports=list(i.exports).map(text);
  if (!exports.length || exports.some(e => !/^[A-Za-z_][A-Za-z0-9_]*$/.test(e)) || new Set(exports).size !== exports.length) return fail('Invalid retained exports');
  const result:ArtifactManifest={schema:p.schema,root:pin(p.root),identity:identity(p.identity),packages:list(p.packages).map(evidence),origin:origin(p.origin),
    artifact:{sha256:digest(a.sha256),size:a.size,target:target(a.target)},
    invocation:{abi:i.abi,profile:profile(i.profile),exports,imports:list(i.imports).map(importDescriptor)},optimization:optimization(p.optimization)};
  const decision:{order?:string[];error?:string}=JSON.parse((await bridge()).plan(JSON.stringify({root:result.root,
    packages:result.packages.map(p => ({pin:p.pin,dependencies:p.dependencies}))})));
  if (!decision.order || decision.error || JSON.stringify(decision.order) !== JSON.stringify(result.packages.map(p => p.pin.name))) return fail('Invalid manifest dependency graph/order');
  if (result.packages.some(p => p.form === 'source' && p.optimization !== result.optimization)) return fail('Inconsistent source optimization setting');
  if (result.origin.kind === 'moonbit-source' && result.origin.sha256 !== result.root.sha256) return fail('Source origin differs from root pin');
  const imports=result.invocation.imports.map(i => [i.module,i.name]);
  if (new Set(imports.map(i => JSON.stringify(i))).size !== imports.length) return fail('Duplicate Wasm import');
  return result;
}

/** Ion metadata is parsed and written by moonrockz/ion, without JSON coercion. */
export async function prepareArtifact(assembly:AssemblyResult, executionProfile:ExecutionProfile,
  options:RequestOptions & {encoding?:ManifestEncoding; metadataIon?:string; model?:ModelOrigin} = {}):Promise<PreparedArtifact> {
  const snapshot=structuredClone({assembly,executionProfile,encoding:options.encoding ?? 'ion',metadata:options.metadataIon ?? 'null',model:options.model});
  check(options.signal);
  const {artifact}=snapshot.assembly;
  const module=await WebAssembly.compile(artifact.bytes);
  const functions=new Set(WebAssembly.Module.exports(module).filter(e => e.kind === 'function').map(e => e.name));
  if (snapshot.assembly.exports.some(e => !functions.has(e.split(':').at(-1)!))) return fail('Missing retained artifact export');
  check(options.signal);
  const record=await manifest({schema:'morphir-assembly-artifact-v1-draft',root:snapshot.assembly.root,identity:snapshot.assembly.identity,
    packages:snapshot.assembly.packages,origin:snapshot.model ? {kind:'morphir-model',id:snapshot.model.id,revision:snapshot.model.revision,sha256:await sha256(snapshot.model.bytes)} :
      {kind:'moonbit-source',sha256:snapshot.assembly.root.sha256},
    artifact:{sha256:await sha256(artifact.bytes),size:artifact.bytes.length,target:artifact.target},
    invocation:{abi:'core-wasm',profile:snapshot.executionProfile,exports:snapshot.assembly.exports.map(e => e.split(':').at(-1)!),
      imports:WebAssembly.Module.imports(module)},optimization:snapshot.assembly.optimization});
  check(options.signal);
  const encoded:{bytes?:number[];error?:string}=JSON.parse((await bridge()).encode_manifest(JSON.stringify(record),snapshot.metadata,snapshot.encoding));
  if (!encoded.bytes || encoded.error) return fail(encoded.error ?? 'Manifest encoding failed');
  const saved={wasm:artifact.bytes,manifest:new Uint8Array(encoded.bytes),encoding:snapshot.encoding};
  const decoded=await decodeManifest(saved);
  check(options.signal);
  return {...saved,record:decoded.record,metadataIon:decoded.metadataIon};
}
export async function decodeManifest(saved:Pick<SavedArtifact,'manifest'|'encoding'>):Promise<{record:ArtifactManifest;metadataIon:string}> {
  const bytes=saved.manifest.slice(); const encoding=saved.encoding;
  if (encoding !== 'ion' && encoding !== 'json') return fail('Unsupported manifest encoding');
  const decoded:unknown=JSON.parse((await bridge()).decode_manifest(bytes,encoding));
  if (decoded && typeof decoded === 'object' && 'error' in decoded) return fail(text(decoded.error));
  const value=object(decoded,['build','metadataIon']);
  return {record:await manifest(value.build),metadataIon:text(value.metadataIon)};
}

/** The store owns atomic visibility; abort must remove only its private staging. */
export async function publishArtifact(store:ArtifactStore, artifact:SavedArtifact, {signal}:RequestOptions = {}):Promise<void> {
  const snapshot=structuredClone(artifact);
  // Refuse corrupt/inconsistent bytes before opening a publication transaction.
  const {record}=await decodeManifest(snapshot);
  if (snapshot.wasm.length !== record.artifact.size || await sha256(snapshot.wasm) !== record.artifact.sha256)
    throw new AssemblyFailure('integrity','Artifact digest/size mismatch');
  const module=await WebAssembly.compile(snapshot.wasm);
  verifyModule(module,record);
  check(signal);
  const transaction=await store.begin();
  try {
    check(signal); await transaction.write('model.wasm',snapshot.wasm);
    check(signal); await transaction.write(snapshot.encoding === 'ion' ? 'manifest.ion' : 'manifest.json',snapshot.manifest);
    check(signal); await transaction.commit();
  } catch (error) {
    try { await transaction.abort(); } catch (cleanup) { throw new AggregateError([error,cleanup],'Publication failed and staging cleanup failed'); }
    throw error;
  }
}

/** Compile/inspect first; instantiate only after integrity and compatibility checks. */
export async function loadArtifact(saved:SavedArtifact, host:ArtifactHost, {signal}:RequestOptions = {}):Promise<LoadedArtifact> {
  const snapshot=structuredClone(saved);
  const policy={targets:[...host.targets],profiles:host.profiles.map(p => ({...p})),encodings:[...host.encodings]};
  // Snapshot supplied bindings while retaining host-owned function/resource identities.
  const imports:ArtifactImports=Object.fromEntries(Object.entries(host.imports ?? {}).map(([name,values]) => [name,{...values}]));
  check(signal);
  const {record,metadataIon}=await decodeManifest(snapshot);
  if (snapshot.wasm.length !== record.artifact.size || await sha256(snapshot.wasm) !== record.artifact.sha256)
    throw new AssemblyFailure('integrity','Artifact digest/size mismatch');
  if (!policy.targets.includes(record.artifact.target) || !policy.encodings.includes(snapshot.encoding) ||
    !policy.profiles.some(p => p.id === record.invocation.profile.id && p.sha256 === record.invocation.profile.sha256))
    throw new AssemblyFailure('compatibility','Host target, encoding or execution profile mismatch');
  // Compilation checks actual instruction/proposal support without executing code.
  check(signal);
  const module=await WebAssembly.compile(snapshot.wasm);
  const actual=verifyModule(module,record);
  for (const entry of actual) {
    const value=imports[entry.module]?.[entry.name];
    const valid=entry.kind === 'function' ? typeof value === 'function' : entry.kind === 'memory' ? value instanceof WebAssembly.Memory :
      entry.kind === 'table' ? value instanceof WebAssembly.Table : entry.kind === 'tag' ? typeof WebAssembly.Tag === 'function' && value instanceof WebAssembly.Tag :
        value instanceof WebAssembly.Global || typeof value === 'number' || typeof value === 'bigint';
    if (!valid) throw new AssemblyFailure('compatibility',`Missing or incompatible host import: ${entry.module}.${entry.name}`);
  }
  check(signal);
  // Every required binding was checked above, including real exception tags.
  let instance:WebAssembly.Instance|null=await WebAssembly.instantiate(module,imports as WebAssembly.Imports);
  let disposed=false;
  if (signal?.aborted) { disposed=true;check(signal); }
  return {manifest:structuredClone(record),metadataIon,
    invoke(name,args=[]) {
      if (disposed || !instance) throw new Error('Artifact disposed');
      if (!record.invocation.exports.includes(name)) throw new Error(`Undeclared artifact export: ${name}`);
      const fn=instance.exports[name];
      if (typeof fn !== 'function') throw new Error(`Missing artifact export: ${name}`);
      return fn(...args);
    },
    dispose() { disposed=true;instance=null; },
  };
}

function verifyModule(module:WebAssembly.Module, record:ArtifactManifest):WebAssembly.ModuleImportDescriptor[] {
  const actual=WebAssembly.Module.imports(module).map(importDescriptor);
  if (JSON.stringify(actual) !== JSON.stringify(record.invocation.imports)) throw new AssemblyFailure('compatibility','Actual Wasm imports differ from manifest');
  const exports=new Set(WebAssembly.Module.exports(module).filter(e => e.kind === 'function').map(e => e.name));
  if (record.invocation.exports.some(e => !exports.has(e))) throw new AssemblyFailure('compatibility','Actual Wasm exports differ from manifest');
  return actual;
}
