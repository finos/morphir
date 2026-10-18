import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, rm, readdir, writeFile, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import type {ArtifactHost, ArtifactStore, SavedArtifact} from '../artifacts.mjs';
import {prepareArtifact, decodeManifest, loadArtifact, publishArtifact} from '../artifacts.mjs';
import {pinPackage, assemblyIdentity, executeAssembly, sha256} from '../assembly.mjs';
import {compilerVersion} from '../index.mjs';
import {createInProcessToolchain} from '../node.mts';
import {createDirectoryArtifactStore, readDirectoryArtifact} from '../node-artifacts.mjs';

const profile={id:'test/core-scalar-v1',sha256:'a'.repeat(64)};
const host:ArtifactHost={targets:['wasm','wasm-gc'],profiles:[profile],encodings:['ion','json']};
async function fixture(imported=false) {
  const tools=createInProcessToolchain();
  try {
    const entry=await pinPackage({name:'artifact/example',role:'library',dependencies:[],input:{kind:'source',files:[['main.mbt',imported ?
      'fn tick() -> Int32 = "host" "tick"\nlet started : Int32 = tick()\npub fn answer() -> Int32 { started + 41 }' :
      'pub fn answer() -> Int32 { 42 }\npub fn hidden() -> Int32 { 9 }']]}});
    const packages=[entry];
    return await executeAssembly(tools,{root:entry.pin,packages,identity:await assemblyIdentity(compilerVersion,packages),target:'wasm',exports:['answer']});
  } finally {tools.dispose();}
}
async function rewritten(saved:SavedArtifact, change:(record:Record<string,unknown>)=>void):Promise<SavedArtifact> {
  const {record,metadataIon}=await decodeManifest(saved);
  const value=JSON.parse(JSON.stringify(record)) as Record<string,unknown>;change(value);
  const codec=await import(new URL('../dist/bridge.mjs',import.meta.url).href) as typeof import('../bridge.mjs');
  const encoded=JSON.parse(codec.encode_manifest(JSON.stringify(value),metadataIon,saved.encoding)) as {bytes:number[]};
  return {...saved,manifest:new Uint8Array(encoded.bytes)};
}

test('binary Ion manifest preserves annotations, exact integers, decimals, binary and graph/model identity',async () => {
  const assembly=await fixture();
  const model=new TextEncoder().encode('{"version":"4.0.0-draft","distribution":"fixture"}');
  const saved=await prepareArtifact(assembly,profile,{model:{id:'fixture',revision:'r1',bytes:model},
    metadataIon:'source::{integer:123456789012345678901234567890, decimal:1.2300, binary:{{AAEC/w==}}, typed:null.int, repeated:1, repeated:2}'});
  assert.equal(saved.encoding,'ion');
  assert.deepEqual([...saved.manifest.slice(0,4)],[0xe0,0x01,0x00,0xea]);
  const decoded=await decodeManifest(saved);
  assert.equal(decoded.record.artifact.sha256,await sha256(saved.wasm));
  assert.equal(decoded.record.origin.kind,'morphir-model');
  assert.equal(decoded.record.origin.sha256,await sha256(model));
  assert.deepEqual(decoded.record.packages,assembly.packages);
  assert.match(decoded.metadataIon,/source::/);
  assert.match(decoded.metadataIon,/123456789012345678901234567890/);
  assert.match(decoded.metadataIon,/1\.2300/);
  assert.match(decoded.metadataIon,/AAEC\/w==/);
  assert.match(decoded.metadataIon,/null\.int/);
  assert.match(decoded.metadataIon,/repeated: 1, repeated: 2/);
  const loaded=await loadArtifact(saved,host);
  assert.equal(loaded.invoke('answer'),42);
  assert.throws(()=>loaded.invoke('hidden'),/Undeclared/);
  // The public description cannot mutate the invocation contract captured by the loader.
  (loaded.manifest.invocation.exports as string[]).push('hidden');
  assert.throws(()=>loaded.invoke('hidden'),/Undeclared/);
  loaded.dispose();assert.throws(()=>loaded.invoke('answer'),/disposed/);
});

test('explicit JSON manifest is checked and refuses lossy Ion metadata',async () => {
  const assembly=await fixture();
  const saved=await prepareArtifact(assembly,profile,{encoding:'json',metadataIon:'{source:"MoonBit", line:42}'});
  assert.equal(saved.encoding,'json');assert.equal((await loadArtifact(saved,host)).invoke('answer'),42);
  for (const metadataIon of ['note::1','{{AQID}}','123456789012345678901234567890','1.2300','null.int','{same:1,same:2}']) {
    await assert.rejects(prepareArtifact(assembly,profile,{encoding:'json',metadataIon}));
  }
});

test('integrity, schema, graph, profile, target, codec and import mismatches refuse before initialization',async () => {
  const saved=await prepareArtifact(await fixture(true),profile);
  let calls=0;
  const supplied={...host,imports:{host:{tick:()=>{calls++;return 1;}}}};
  const corrupt={...saved,wasm:saved.wasm.slice()};corrupt.wasm[corrupt.wasm.length-1]=corrupt.wasm.at(-1)!^1;
  await assert.rejects(loadArtifact(corrupt,supplied),/digest\/size/);
  await assert.rejects(loadArtifact(saved,{...supplied,profiles:[{...profile,sha256:'b'.repeat(64)}]}),/profile mismatch/);
  await assert.rejects(loadArtifact(saved,{...supplied,targets:['wasm-gc']}),/target/);
  await assert.rejects(loadArtifact(saved,{...supplied,encodings:['json']}),/encoding/);
  await assert.rejects(loadArtifact(saved,host),/host import/);
  await assert.rejects(loadArtifact(await rewritten(saved,r => {r.schema='future';}),supplied),/schema/);
  await assert.rejects(loadArtifact(await rewritten(saved,r => {r.packages=[];}),supplied),/dependency graph/);
  await assert.rejects(loadArtifact(await rewritten(saved,r => {r.invocation={...saved.record.invocation,imports:[]};}),supplied),/Actual Wasm imports/);
  await assert.rejects(loadArtifact({...saved,manifest:saved.manifest.slice(0,-1)},supplied));
  assert.equal(calls,0);
  const loaded=await loadArtifact(saved,supplied);
  assert.equal(loaded.invoke('answer'),42);assert.equal(calls,1);loaded.dispose();
});

test('partial writes and cancellation abort private staging and never commit',async () => {
  const saved=await prepareArtifact(await fixture(),profile);
  const controller=new AbortController();
  for (const mode of ['write-failure','cancel'] as const) {
    const events:string[]=[];
    const store:ArtifactStore={async begin(){events.push('begin');return {
      async write(name){events.push(name);if (mode === 'write-failure' && name === 'manifest.ion') throw new Error('Disk full');
        if (mode === 'cancel') controller.abort();},
      async commit(){events.push('commit');},async abort(){events.push('abort');},
    };}};
    await assert.rejects(publishArtifact(store,saved,mode === 'cancel' ? {signal:controller.signal} : {}));
    assert.equal(events.includes('commit'),false);assert.equal(events.at(-1),'abort');
  }
});

test('directory store publishes a complete pair, refuses replacement and cleans incomplete transactions',async () => {
  const directory=await mkdtemp(join(tmpdir(),'morphir-artifacts-'));
  try {
    const saved=await prepareArtifact(await fixture(),profile);
    const path=join(directory,'published');
    const store=createDirectoryArtifactStore(path);
    const transaction=await store.begin();
    const entries=await readdir(directory);
    assert.equal(entries.length,2);assert.ok(entries.includes('published.publish.lock'));
    assert.ok(entries.some(n=>n.startsWith('.published-staging-')));
    await transaction.write('model.wasm',saved.wasm);
    await assert.rejects(transaction.commit(),/Incomplete/);
    await assert.rejects(readDirectoryArtifact(path));
    await transaction.abort();await transaction.abort();
    assert.deepEqual(await readdir(directory),[]);
    await publishArtifact(store,saved);
    assert.deepEqual((await readdir(path)).sort(),['manifest.ion','model.wasm']);
    const read=await readDirectoryArtifact(path);
    assert.equal((await loadArtifact(read,host)).invoke('answer'),42);
    await assert.rejects(publishArtifact(store,saved),/already exists/);
    assert.deepEqual(await readFile(join(path,'model.wasm')),Buffer.from(saved.wasm));
    assert.deepEqual(await readdir(directory),['published']);
    const competing=createDirectoryArtifactStore(join(directory,'competing'));
    const first=await competing.begin();
    await assert.rejects(competing.begin(),/EEXIST/);
    await first.abort();
    assert.deepEqual(await readdir(directory),['published']);
  } finally {await rm(directory,{recursive:true,force:true});}
});

test('a fresh process loads persisted artifacts with empty PATH and no installed compiler invocation',async () => {
  const directory=await mkdtemp(join(tmpdir(),'morphir-fresh-artifact-'));
  try {
    const path=join(directory,'saved');
    await publishArtifact(createDirectoryArtifactStore(path),await prepareArtifact(await fixture(),profile));
    const source=join(directory,'consume.mjs');
    await writeFile(source,`
      import {readDirectoryArtifact} from ${JSON.stringify(new URL('../node-artifacts.mjs',import.meta.url).href)};
      import {loadArtifact} from ${JSON.stringify(new URL('../artifacts.mjs',import.meta.url).href)};
      const artifact=await loadArtifact(await readDirectoryArtifact(${JSON.stringify(path)}),${JSON.stringify(host)});
      try { if(artifact.invoke('answer')!==42) throw new Error('Wrong saved result');console.log('fresh artifact passed'); }
      finally {artifact.dispose();}
    `);
    const env:NodeJS.ProcessEnv={...process.env,PATH:''};delete env.MOON_HOME;
    assert.equal(execFileSync(process.execPath,[source],{env,encoding:'utf8'}).trim(),'fresh artifact passed');
  } finally {await rm(directory,{recursive:true,force:true});}
});

test('a completed load request does not own the returned artifact lifetime',async () => {
  const controller=new AbortController();
  const saved=await prepareArtifact(await fixture(),profile);
  const loaded=await loadArtifact(saved,host,{signal:controller.signal});
  controller.abort();
  try {assert.equal(loaded.invoke('answer'),42);}
  finally {loaded.dispose();}
  await assert.rejects(loadArtifact(saved,host,{signal:controller.signal}),{name:'AbortError'});
});

test('exception-tag imports roundtrip and require a real host tag before instantiation',async () => {
  const assembly=await fixture();
  // Valid core Wasm: import a () -> () exception tag and export answer() = 42.
  const wasm=new Uint8Array([0,97,115,109,1,0,0,0,1,8,2,96,0,0,96,0,1,127,2,19,1,4,104,111,115,116,9,101,120,99,101,112,116,105,111,110,4,0,0,3,2,1,1,7,10,1,6,97,110,115,119,101,114,0,0,10,6,1,4,0,65,42,11]);
  const saved=await prepareArtifact({...assembly,artifact:{target:'wasm',bytes:wasm}},profile);
  assert.deepEqual(saved.record.invocation.imports,[{module:'host',name:'exception',kind:'tag'}]);
  await assert.rejects(loadArtifact(saved,{...host,imports:{host:{exception:()=>{}}}}),/host import/);
  const tag=new WebAssembly.Tag({parameters:[]});
  const loaded=await loadArtifact(saved,{...host,imports:{host:{exception:tag}}});
  try {assert.equal(loaded.invoke('answer'),42);}
  finally {loaded.dispose();}
});
