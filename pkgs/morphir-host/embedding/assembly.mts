import type {Artifact, BuildRequest, Interface, RequestOptions, Target, Toolchain} from './api.mjs';

export interface PackagePin { readonly name: string; readonly sha256: string; }
export interface PackageImport { readonly name: string; readonly pin: PackagePin; }
export type PackageRole = 'library' | 'sdk' | 'core';
export type Optimization = 'optimized' | 'unoptimized';
export interface AssemblyIdentity {
  readonly compilerVersion: string;
  readonly coreSha256: string;
  readonly sdkSha256: string;
}
export type PackageInput =
  | { readonly kind: 'source'; readonly files: readonly (readonly [string, string])[] }
  | { readonly kind: 'prebuilt'; readonly interface: Uint8Array<ArrayBuffer>; readonly core: Uint8Array<ArrayBuffer>;
      readonly identity: AssemblyIdentity; readonly target: Target; readonly optimization: Optimization };
export interface PackageDescription {
  readonly name: string;
  readonly role: PackageRole;
  readonly dependencies: readonly PackageImport[];
  readonly input: PackageInput;
}
export interface PackageAsset extends PackageDescription { readonly pin: PackagePin; }
export interface AssemblyRequest {
  readonly root: PackagePin;
  readonly packages: readonly PackageAsset[];
  readonly identity: AssemblyIdentity;
  readonly target: Target;
  /** Every entry is a retained root in the selected package, including explicit indirect registrations. */
  readonly exports: readonly string[];
  readonly optimization?: Optimization;
}
export interface PackageEvidence {
  readonly pin: PackagePin;
  readonly role: PackageRole;
  readonly dependencies: readonly PackageImport[];
  readonly form: PackageInput['kind'];
}
export interface AssemblyResult {
  readonly artifact: Artifact;
  readonly root: PackagePin;
  readonly identity: AssemblyIdentity;
  readonly packages: readonly PackageEvidence[];
  readonly exports: readonly string[];
  readonly optimization: Optimization;
  readonly diagnostics: readonly {package: string; diagnostics: unknown[]}[];
}
export class AssemblyFailure extends Error {
  constructor(readonly code: 'graph' | 'integrity' | 'compatibility' | 'input' | 'compiler', message: string,
    readonly diagnostics: unknown[] = []) { super(message); this.name = 'AssemblyFailure'; }
}
const fail = (code: AssemblyFailure['code'], message: string): never => { throw new AssemblyFailure(code, message); };
const digestPattern = /^[0-9a-f]{64}$/;
const compare = (a: string, b: string) => a < b ? -1 : a > b ? 1 : 0;
const hex = (bytes: Uint8Array) => Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
export async function sha256(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)));
}
const hashValue = (value: unknown) => sha256(new TextEncoder().encode(JSON.stringify(value)));
const pinValue = (pin: PackagePin) => [pin.name, pin.sha256];
const identityValue = (identity: AssemblyIdentity) => [identity.compilerVersion, identity.coreSha256, identity.sdkSha256];
const importsValue = (deps: readonly PackageImport[]) => [...deps].sort((a,b) => compare(a.name,b.name))
  .map(d => [d.name, pinValue(d.pin)]);

function normalize(description: PackageDescription): PackageDescription {
  const entry = structuredClone(description);
  if (!['library','sdk','core'].includes(entry.role)) fail('input', `Invalid role for ${entry.name}`);
  if (entry.input.kind === 'source') {
    const seen = new Set<string>();
    if (!entry.input.files.length) fail('input', `No sources for ${entry.name}`);
    for (const [path, source] of entry.input.files) {
      if (!/^[A-Za-z0-9_./-]+\.mbt$/.test(path) || path.startsWith('/') ||
        path.split('/').some(part => !part || part === '.' || part === '..') || seen.has(path) || typeof source !== 'string')
        fail('input', `Invalid or duplicate source path in ${entry.name}: ${path}`);
      seen.add(path);
    }
  } else if (entry.input.kind === 'prebuilt') {
    if (!(entry.input.core instanceof Uint8Array) || !entry.input.core.length ||
      !(entry.input.interface instanceof Uint8Array) || !entry.input.interface.length) fail('input', `Empty prebuilt package: ${entry.name}`);
  } else fail('input', `Invalid package form: ${entry.name}`);
  return {...entry,dependencies:[...entry.dependencies].sort((a,b) => compare(a.name,b.name)),
    input:entry.input.kind === 'source' ? {...entry.input,files:[...entry.input.files].sort((a,b) => compare(a[0],b[0]))} : entry.input};
}

/** The v1 package pin covers content, role, exact imports and prebuilt context. */
async function contentDigest(entry: PackageDescription): Promise<string> {
  const input = entry.input;
  return hashValue(['morphir-assembly-package-v1', entry.name, entry.role, importsValue(entry.dependencies),
    input.kind === 'source' ? ['source', [...input.files].sort((a,b) => compare(a[0],b[0]))] :
      ['prebuilt', identityValue(input.identity), input.target, input.optimization, hex(input.interface), hex(input.core)]]);
}
export async function pinPackage(description: PackageDescription): Promise<PackageAsset> {
  const entry = normalize(description);
  const pin = {name: entry.name, sha256: await contentDigest(entry)};
  return {...entry, pin};
}

/** Exact set identities include every supplied core/SDK package, including unused ones. */
export async function assemblyIdentity(compilerVersion: string, packages: readonly PackageDescription[]): Promise<AssemblyIdentity> {
  const snapshot = structuredClone(packages);
  // Fingerprint actual assets without their context assertions. Including a
  // prebuilt core's own set identity here would create a circular content hash.
  const group = (role: PackageRole) => hashValue(['morphir-assembly-set-v1', role,
    snapshot.filter(p => p.role === role).sort((a,b) => compare(a.name,b.name)).map(p => [p.name,
      [...p.dependencies].sort((a,b) => compare(a.name,b.name)).map(d => [d.name,d.pin.name]),
      p.input.kind === 'source' ? ['source',[...p.input.files].sort((a,b) => compare(a[0],b[0]))] :
        ['prebuilt',hex(p.input.interface),hex(p.input.core)]] )]);
  return {compilerVersion, coreSha256: await group('core'), sdkSha256: await group('sdk')};
}
function sameIdentity(a: AssemblyIdentity, b: AssemblyIdentity): boolean {
  return JSON.stringify(identityValue(a)) === JSON.stringify(identityValue(b));
}
const active = (signal?: AbortSignal) => { if (signal?.aborted) throw new DOMException('Cancelled', 'AbortError'); };

/** Effects live here. The MoonBit planner validates the complete supplied set. */
export async function executeAssembly(toolchain: Toolchain, request: AssemblyRequest, options: RequestOptions = {}): Promise<AssemblyResult> {
  // Snapshot before the first await. Caller mutation cannot change verified assets.
  const snapshot = structuredClone(request);
  const {root, identity, target} = snapshot;
  const optimization = snapshot.optimization ?? 'optimized';
  const entries = snapshot.packages.map(p => ({...normalize(p), pin: p.pin}));
  active(options.signal);
  if (!['wasm','wasm-gc'].includes(target) || !['optimized','unoptimized'].includes(optimization) ||
    !identity.compilerVersion || !digestPattern.test(identity.coreSha256) || !digestPattern.test(identity.sdkSha256) ||
    !snapshot.exports.length || new Set(snapshot.exports).size !== snapshot.exports.length ||
    snapshot.exports.some(e => !/^[A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z_][A-Za-z0-9_]*)?$/.test(e)))
    fail('input', 'Invalid assembly target, identity, optimization or retention roots');
  const {plan} = await import(new URL('./dist/bridge.mjs', import.meta.url).href) as typeof import('./bridge.mjs');
  active(options.signal);
  const decision: {order?: string[]; error?: string} = JSON.parse(plan(JSON.stringify({root,
    packages: entries.map(p => ({pin: p.pin, dependencies: p.dependencies}))})));
  if (!decision.order || decision.error) fail('graph', decision.error ?? 'Invalid planner result');
  const byName = new Map(entries.map(p => [p.name,p]));
  for (const entry of entries) {
    if (entry.name !== entry.pin.name || await contentDigest(entry) !== entry.pin.sha256)
      fail('integrity', `Package content mismatch: ${entry.name}`);
    if (entry.input.kind === 'prebuilt' && (!sameIdentity(entry.input.identity, identity) ||
      entry.input.target !== target || entry.input.optimization !== optimization))
      fail('compatibility', `Prebuilt context mismatch: ${entry.name}`);
    active(options.signal);
  }
  if (!sameIdentity(await assemblyIdentity(identity.compilerVersion, entries), identity)) fail('compatibility', 'Core/SDK assembly set mismatch');
  const info = await toolchain.request({operation:'info'}, options);
  if (info.compilerVersion !== identity.compilerVersion || !info.targets.includes(target) ||
    !info.operations.includes('build') || !info.operations.includes('link')) fail('compatibility', 'Compiler provider mismatch');
  active(options.signal);
  const outputs = new Map<string, {interface: Uint8Array<ArrayBuffer>; core: Uint8Array<ArrayBuffer>}>();
  const diagnostics: {package: string; diagnostics: unknown[]}[] = [];
  const evidence: PackageEvidence[] = [];
  for (const name of decision.order!) {
    active(options.signal);
    const entry = byName.get(name)!;
    if (entry.input.kind === 'prebuilt') outputs.set(name, {interface:entry.input.interface, core:entry.input.core});
    else {
      const direct = new Set(entry.dependencies.map(d => d.pin.name));
      const reachable = new Set<string>();
      const work = [...direct];
      while (work.length) {
        const name = work.pop()!;
        if (reachable.has(name)) continue;
        reachable.add(name);
        work.push(...byName.get(name)!.dependencies.map(d => d.pin.name));
      }
      // moonc uses a virtual interface path plus ':localAlias', not the alias
      // alone. The encoded .mi still carries the real package identity.
      const interfaces: Interface[] = entry.dependencies.map(d => [`${d.pin.name}:${d.name}`, outputs.get(d.pin.name)!.interface]);
      const indirectInterfaces: Interface[] = [...reachable].filter(n => !direct.has(n) && byName.get(n)!.role !== 'core')
        .sort(compare).map(n => [n, outputs.get(n)!.interface]);
      const standardInterfaces: Interface[] = [...reachable].filter(n => byName.get(n)!.role === 'core' && !direct.has(n))
        .sort(compare).map(n => [n, outputs.get(n)!.interface]);
      const build: BuildRequest = {operation:'build',package:name,target,files:entry.input.files.map(([p,s]) => [p,s]),
        interfaces, indirectInterfaces, standardInterfaces, optimization};
      const output = await toolchain.request(build, options);
      active(options.signal);
      diagnostics.push({package:name,diagnostics:output.diagnostics});
      if (!output.successful || !output.core || !output.interface)
        throw new AssemblyFailure('compiler', `Package compilation failed: ${name}`, output.diagnostics);
      outputs.set(name, {core:output.core,interface:output.interface});
    }
    evidence.push({pin:entry.pin,role:entry.role,dependencies:entry.dependencies,form:entry.input.kind});
  }
  active(options.signal);
  const linked = await toolchain.request({operation:'link',package:root.name,target,
    cores:decision.order!.map(n => outputs.get(n)!.core),exports:[...snapshot.exports],optimization}, options);
  active(options.signal);
  // Check that the linker really retained the requested public API before publication.
  const module = await WebAssembly.compile(linked.artifact.bytes);
  const actual = new Set(WebAssembly.Module.exports(module).filter(e => e.kind === 'function').map(e => e.name));
  for (const entry of snapshot.exports) {
    const name = entry.split(':').at(-1)!;
    if (!actual.has(name)) fail('compiler', `Linker omitted retained export: ${name}`);
  }
  active(options.signal);
  return {artifact:linked.artifact,root,identity,packages:evidence,exports:snapshot.exports,optimization,diagnostics};
}
