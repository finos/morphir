import assert from 'node:assert/strict';
import {test} from 'node:test';
import {pinPackage,assemblyIdentity,executeAssembly} from '../assembly.mjs';
import {createInProcessToolchain} from '../node.mts';
import {compilerVersion} from '../index.mjs';
import {prepareArtifact} from '../artifacts.mjs';
import {byteExecutionProfile,loadByteAdapter,byteLimits} from '../byte-adapter.mjs';
import type {ByteProfile} from '../byte-adapter.mjs';
import {NdjsonFrames} from '../ndjson.mjs';
import {parseMoonRecipe} from '../node-recipe.mjs';
import {spawnSync} from 'node:child_process';

const input=new TextEncoder();
const source=`
fn input_len() -> Int32 = "morphir_bytes_v1" "input_len"
fn input_byte(i : Int32) -> Int32 = "morphir_bytes_v1" "input_byte"
fn output_byte(b : Int32) -> Unit = "morphir_bytes_v1" "output_byte"
fn diagnostic(n : Int32) -> Unit = "morphir_diagnostics_v1" "response_bytes"
pub fn handle() -> Int32 {
  let n = input_len()
  if n == 0 { return 0 }
  if input_byte(0) == 33 { return -1 }
  if input_byte(0) == 63 { output_byte(300); return 1 }
  if input_byte(0) == 35 { return 7 / (input_len() - 1) }
  if input_byte(0) == 64 { for _i in 0..<2097153 { output_byte(65) }; return 2097153 }
  for i in 0..<n { output_byte(input_byte(i)) }
  DIAGNOSTIC
  n
}`;
async function fixture(profile:ByteProfile) {
  const tools=createInProcessToolchain();
  try {
    const pkg=await pinPackage({name:'test/byte-host',role:'library',dependencies:[],input:{kind:'source',files:[['main.mbt',source.replace('DIAGNOSTIC',profile === 'bytes-v1'?'':'diagnostic(n)')]]}});
    const packages=[pkg];
    return await prepareArtifact(await executeAssembly(tools,{root:pkg.pin,packages,identity:await assemblyIdentity(compilerVersion,packages),target:'wasm',exports:['handle']}),await byteExecutionProfile(profile));
  } finally {tools.dispose();}
}

test('owned byte exchange retains Unicode/NUL, repeats, exits and disposes',async()=>{
  const saved=await fixture('bytes-v1');const adapter=await loadByteAdapter(saved,{profile:'bytes-v1'});
  const first=adapter.exchange(input.encode('hello 🌕\0é'));
  assert.equal(first.kind,'response');if(first.kind !== 'response')throw Error('response');
  assert.equal(new TextDecoder().decode(first.bytes),'hello 🌕\0é');
  for(let i=0;i<100;i++) assert.deepEqual(adapter.exchange(input.encode('repeat')), {kind:'response',bytes:input.encode('repeat')});
  assert.equal(new TextDecoder().decode(first.bytes),'hello 🌕\0é');
  assert.throws(()=>adapter.exchange(new Uint8Array(byteLimits.request+1)),/limit/);
  assert.throws(()=>adapter.exchange(new Uint8Array([0xff])),/encoded data/);
  assert.deepEqual(adapter.exchange(new Uint8Array(0)),{kind:'exit'});
  assert.throws(()=>adapter.exchange(input.encode('again')),/closed/);
  adapter.dispose();adapter.dispose();assert.throws(()=>adapter.exchange(input.encode('again')),/disposed/);
});

test('diagnostics profile needs explicit service and baseline refuses it',async()=>{
  const saved=await fixture('bytes-diagnostics-v1');
  await assert.rejects(loadByteAdapter(saved,{profile:'bytes-v1'}),/profile mismatch/);
  // Deliberately exercise malformed external input through the typed boundary.
  await assert.rejects(loadByteAdapter(saved,{profile:'bytes-diagnostics-v1',diagnostics:undefined} as never),/explicit service/);
  const events:unknown[]=[];const adapter=await loadByteAdapter(saved,{profile:'bytes-diagnostics-v1',diagnostics:event=>events.push(event)});
  adapter.exchange(input.encode('response'));assert.deepEqual(events,[{kind:'response-bytes',bytes:8}]);
  adapter.exchange(new Uint8Array(0));assert.equal(events.length,1);adapter.dispose();
});

test('guest infrastructure failure and host import violation are terminal and fresh hosts recover',async()=>{
  const saved=await fixture('bytes-v1');
  for(const request of ['!','?','#','@']) {
    const adapter=await loadByteAdapter(saved,{profile:'bytes-v1'});
    assert.throws(()=>adapter.exchange(input.encode(request)));
    assert.throws(()=>adapter.exchange(input.encode('reused')),/failed/);adapter.dispose();
    const fresh=await loadByteAdapter(saved,{profile:'bytes-v1'});assert.equal(fresh.exchange(input.encode('fresh')).kind,'response');fresh.dispose();
  }
});

test('framer preserves split multibyte UTF8, bounds bytes, handles exit and refuses partial final lines',async()=>{
  const seen:Uint8Array<ArrayBuffer>[]=[];const f=new NdjsonFrames(8);
  const accept=async(b:Uint8Array<ArrayBuffer>)=>{seen.push(b);return true;};
  const bytes=input.encode('🌕\nx\n');
  await f.push(bytes.slice(0,2),accept);await f.push(bytes.slice(2),accept);
  assert.deepEqual(seen.map(b=>new TextDecoder().decode(b)),['🌕','x']);f.finish();
  await assert.rejects(f.push(input.encode('123456789'),accept),/limit/);
  await f.push(input.encode('partial'),accept);assert.throws(()=>f.finish(),/Incomplete/);
  assert.equal(await f.push(input.encode('exit\nignored\n'),async()=>false),false);
});

test('recipe acquisition rejects unknown semantic compiler options rather than dropping them',()=>{
  const recipe='moonc build-package a.mbt -o a.core -pkg test/a -pkg-type library -target wasm';
  assert.equal(parseMoonRecipe(recipe)[0]!.name,'test/a');
  for(const extra of [' -unknown yes',' -target wasm',' -link-flags foo'])assert.throws(()=>parseMoonRecipe(recipe+extra));
  assert.throws(()=>parseMoonRecipe(recipe.replace('wasm','native')),/core-Wasm/);
  assert.throws(()=>parseMoonRecipe('sh -c echo'));
});

test('process bridge exits without response and awaits asynchronous cleanup without aborting stdin',()=>{
  const script=`import {serveByteAdapter} from ${JSON.stringify(new URL('../node-byte-adapter.mjs',import.meta.url).href)};
    await serveByteAdapter({exchange(){return {kind:'exit'};},async dispose(){await new Promise(done=>setImmediate(done));process.stderr.write('disposed');}});`;
  const result=spawnSync(process.execPath,['--input-type=module','-e',script],{input:'exit\nignored\n',encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);assert.equal(result.stdout,'');assert.equal(result.stderr,'disposed');
  const partial=spawnSync(process.execPath,['--input-type=module','-e',script],{input:'partial',encoding:'utf8'});
  assert.notEqual(partial.status,0);assert.match(partial.stderr,/Incomplete NDJSON line/);
});
