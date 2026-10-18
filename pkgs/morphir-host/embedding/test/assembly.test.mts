import assert from 'node:assert/strict';
import {test} from 'node:test';
import type {AssemblyRequest, PackageAsset} from '../assembly.mjs';
import type {Request, Toolchain} from '../api.mjs';
import {assemblyIdentity, executeAssembly, pinPackage} from '../assembly.mjs';
import {compilerVersion} from '../index.mjs';
import {createInProcessToolchain, createNodeToolchain} from '../node.mts';

async function fixture(): Promise<AssemblyRequest> {
  const leaf = await pinPackage({name:'sample/leaf',role:'library',dependencies:[],input:{kind:'source',files:[['leaf.mbt',
    'pub fn double(n : Int32) -> Int32 { n * 2 }']]}});
  const middle = await pinPackage({name:'sample/middle',role:'library',dependencies:[{name:'math',pin:leaf.pin}],input:{kind:'source',files:[['middle.mbt',
    'pub fn value() -> Int32 { @math.double(20) }']]}});
  const root = await pinPackage({name:'sample/root',role:'library',dependencies:[{name:'lib',pin:middle.pin}],input:{kind:'source',files:[
    ['answer.mbt','pub fn answer() -> Int32 { @lib.value() + 2 }'],
    ['more.mbt','pub fn retained() -> Int32 { 7 }\npub fn unused() -> Int32 { 123456 }']]}});
  const unused = await pinPackage({name:'sample/unused',role:'library',dependencies:[],input:{kind:'source',files:[['unused.mbt',
    'pub fn unnecessary() -> Int32 { 19 }']]}});
  const packages = [root,unused,middle,leaf];
  return {root:root.pin,packages,identity:await assemblyIdentity(compilerVersion,packages),target:'wasm',exports:['answer','retained']};
}
function traced(toolchain: Toolchain) {
  const calls: Request[] = [];
  const wrapper: Toolchain = {...toolchain, request(request, options) { calls.push(request); return toolchain.request(request,options); }};
  return {wrapper,calls};
}

for (const [name,create] of [['in-process',createInProcessToolchain],['worker',createNodeToolchain]] as const) {
  test(`${name}: planned multi-file transitive/aliased graph links once and retains explicit exports`, async () => {
    const tools = create(); const {wrapper,calls} = traced(tools);
    try {
      for (const target of ['wasm','wasm-gc'] as const) {
        calls.length = 0;
        const request = {...await fixture(),target};
        const result = await executeAssembly(wrapper,request);
        assert.deepEqual(result.packages.map(p => p.pin.name),['sample/leaf','sample/middle','sample/root','sample/unused']);
        assert.equal(calls.filter(r => r.operation === 'build').length,4);
        const links = calls.filter(r => r.operation === 'link');
        assert.equal(links.length,1); assert.equal(links[0]!.cores.length,4);
        assert.equal((await tools.request({operation:'run',artifact:result.artifact,export:'answer'})).value,42);
        assert.equal((await tools.request({operation:'run',artifact:result.artifact,export:'retained'})).value,7);
        const middle = calls.find(r => r.operation === 'build' && r.package === 'sample/middle');
        assert.ok(middle?.operation === 'build'); assert.equal(middle.interfaces![0]![0],'sample/leaf:math');
        const root = calls.find(r => r.operation === 'build' && r.package === 'sample/root');
        assert.ok(root?.operation === 'build'); assert.equal(root.indirectInterfaces![0]![0],'sample/leaf');
      }
    } finally {tools.dispose();}
  });
}

test('graph, bytes, compiler and core/SDK compatibility refuse before any package build', async () => {
  const tools = createInProcessToolchain(); const {wrapper,calls} = traced(tools);
  try {
    const request = await fixture();
    const damaged = structuredClone(request.packages);
    const root = damaged[0]!;
    assert.equal(root.input.kind,'source');
    if (root.input.kind === 'source') (root.input.files as [string,string][])[0]![1] = 'pub fn changed() -> Int32 { 1 }';
    await assert.rejects(executeAssembly(wrapper,{...request,packages:damaged}),/content mismatch/);
    await assert.rejects(executeAssembly(wrapper,{...request,packages:request.packages.slice(0,-1)}),/MissingPackage/);
    await assert.rejects(executeAssembly(wrapper,{...request,identity:{...request.identity,compilerVersion:'other'}}),/provider mismatch/);
    await assert.rejects(executeAssembly(wrapper,{...request,identity:{...request.identity,coreSha256:'0'.repeat(64)}}),/Core\/SDK/);
    assert.equal(calls.filter(r => r.operation === 'build' || r.operation === 'link').length,0);
  } finally {tools.dispose();}
});

test('invalid unused source diagnostics stop downstream linking; compiler recovers', async () => {
  const tools = createInProcessToolchain(); const {wrapper,calls} = traced(tools);
  try {
    const request = await fixture();
    const bad = await pinPackage({name:'sample/unused',role:'library',dependencies:[],input:{kind:'source',files:[['bad.mbt',
      'pub fn bad() -> Int32 { "wrong" }']]}});
    await assert.rejects(executeAssembly(wrapper,{...request,packages:[...request.packages.filter(p => p.name !== bad.name),bad]}),
      (error: unknown) => error instanceof Error && 'diagnostics' in error && Array.isArray(error.diagnostics) && error.diagnostics.length > 0);
    assert.equal(calls.filter(r => r.operation === 'link').length,0);
    assert.equal((await executeAssembly(tools,request)).artifact.target,'wasm');
  } finally {tools.dispose();}
});

test('verified prebuilt interface/core is reused, target/context mismatch is refused', async () => {
  const tools = createInProcessToolchain();
  try {
    const request = await fixture();
    const leaf = request.packages.find(p => p.name === 'sample/leaf')!;
    assert.ok(leaf.input.kind === 'source');
    const built = await tools.request({operation:'build',package:leaf.name,files:leaf.input.files.map(([p,s]) => [p,s])});
    assert.ok(built.successful && built.core && built.interface);
    const prebuilt = await pinPackage({...leaf,input:{kind:'prebuilt',interface:built.interface,core:built.core,
      identity:request.identity,target:'wasm',optimization:'optimized'}});
    const replace = async (packages: readonly PackageAsset[]) => {
      const result: PackageAsset[] = [prebuilt]; const pins = new Map([[leaf.name,prebuilt.pin]]);
      for (const name of ['sample/middle','sample/root','sample/unused']) {
        const old = packages.find(p => p.name === name)!;
        const asset = await pinPackage({...old,dependencies:old.dependencies.map(d => ({...d,pin:pins.get(d.pin.name) ?? d.pin}))});
        result.push(asset); pins.set(name,asset.pin);
      }
      return {packages:result,root:pins.get(request.root.name)!};
    };
    const replaced = await replace(request.packages);
    const result = await executeAssembly(tools,{...request,...replaced});
    assert.equal((await tools.request({operation:'run',artifact:result.artifact,export:'answer'})).value,42);
    assert.equal(result.packages[0]!.form,'prebuilt');
    await assert.rejects(executeAssembly(tools,{...request,...replaced,target:'wasm-gc'}),/Prebuilt context mismatch/);
    await assert.rejects(executeAssembly(tools,{...request,...replaced,optimization:'unoptimized'}),/Prebuilt context mismatch/);
  } finally {tools.dispose();}
});

test('cancellation between packages prevents the final link', async () => {
  const tools = createInProcessToolchain(); const controller = new AbortController();
  const calls: Request[] = [];
  const wrapper: Toolchain = {...tools,async request(request, options) {
    calls.push(request); const result = await tools.request(request,options);
    if (request.operation === 'build') controller.abort();
    return result;
  }};
  try {
    await assert.rejects(executeAssembly(wrapper,await fixture(),{signal:controller.signal}),{name:'AbortError'});
    assert.equal(calls.filter(r => r.operation === 'build').length,1);
    assert.equal(calls.filter(r => r.operation === 'link').length,0);
  } finally {tools.dispose();}
});

test('request mutation after entry cannot replace the sources being verified', async () => {
  const tools = createInProcessToolchain();
  try {
    const request = await fixture();
    const pending = executeAssembly(tools,request);
    const root = request.packages[0]!;
    if (root.input.kind === 'source') (root.input.files as [string,string][])[0]![1] = 'wrong';
    const result = await pending;
    assert.equal((await tools.request({operation:'run',artifact:result.artifact,export:'answer'})).value,42);
  } finally {tools.dispose();}
});
