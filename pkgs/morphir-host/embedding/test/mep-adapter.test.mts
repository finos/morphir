import assert from 'node:assert/strict';
import {test} from 'node:test';
import {pinPackage,assemblyIdentity,executeAssembly} from '../assembly.mjs';
import {createInProcessToolchain} from '../node.mts';
import {compilerVersion} from '../index.mjs';
import {prepareArtifact} from '../artifacts.mjs';
import {mepExecutionProfile,loadMepAdapter,mepLimits} from '../mep-adapter.mjs';
import {loadNodeMepAdapter} from '../node-mep-adapter.mjs';
import {boundWasmMemory,verifyWasmMemory} from '../wasm-memory.mjs';
import {MepFrames} from '../mep-frames.mjs';

const encode=(value:string)=>new TextEncoder().encode(value);
const source=`
fn input_len() -> Int32 = "morphir_bytes_v1" "input_len"
fn input_byte(i : Int32) -> Int32 = "morphir_bytes_v1" "input_byte"
fn output_byte(b : Int32) -> Unit = "morphir_bytes_v1" "output_byte"
pub fn handle() -> Int32 {
  let n = input_len()
  if n == 0 { return 0 }
  if input_byte(0) == 33 { while input_len() > 0 {}; return -1 }
  if input_byte(0) == 35 { return 1 / (input_len() - 1) }
  if input_byte(0) == 126 { return -2 }
  if input_byte(0) == 63 { output_byte(300); return 1 }
  if input_byte(0) == 64 {
    for _ in 0..<16777217 { output_byte(120) }
    return 16777217
  }
  for i in 0..<n { output_byte(input_byte(i)) }
  n
}`;
async function fixture() {
  const tools=createInProcessToolchain();
  try {
    const pkg=await pinPackage({name:'test/mep-host',role:'library',dependencies:[],input:{kind:'source',files:[['main.mbt',source]]}});
    const packages=[pkg];
    const result=await executeAssembly(tools,{root:pkg.pin,packages,identity:await assemblyIdentity(compilerVersion,packages),target:'wasm',exports:['handle']});
    return prepareArtifact({...result,artifact:{...result.artifact,bytes:boundWasmMemory(result.artifact.bytes,mepLimits.memoryPages)}},await mepExecutionProfile());
  }finally{tools.dispose();}
}

test('MEP profile owns bytes, distinguishes notification and exit, and refuses closed sessions',async()=>{
  const saved=await fixture(),adapter=await loadMepAdapter(saved);
  const first=adapter.exchange(encode('hello 🌕\0é'));
  assert.equal(first.kind,'response');
  for(let i=0;i<100;i++)assert.equal(adapter.exchange(encode('repeat')).kind,'response');
  assert.deepEqual(first,{kind:'response',bytes:encode('hello 🌕\0é')});
  assert.deepEqual(adapter.exchange(encode('~')),{kind:'notification'});
  assert.equal(adapter.exchange(encode('after notification')).kind,'response');
  assert.throws(()=>adapter.exchange(new Uint8Array([0xff])),/encoded data/);
  assert.throws(()=>adapter.exchange(new Uint8Array(mepLimits.request+1)),/limit/);
  assert.deepEqual(adapter.exchange(new Uint8Array()),{kind:'exit'});
  assert.throws(()=>adapter.exchange(encode('again')),/closed/);
  adapter.dispose();adapter.dispose();assert.throws(()=>adapter.exchange(encode('again')),/disposed/);
});

test('MEP host treats traps and import violations as terminal; fresh sessions recover',async()=>{
  const saved=await fixture();
  for(const input of ['#','?','@']) {
    const adapter=await loadMepAdapter(saved);
    assert.throws(()=>adapter.exchange(encode(input)));
    assert.throws(()=>adapter.exchange(encode('again')),/failed/);adapter.dispose();
    const fresh=await loadMepAdapter(saved);assert.equal(fresh.exchange(encode('fresh')).kind,'response');fresh.dispose();
  }
  const foreign=await (async()=>{
    const tools=createInProcessToolchain();
    try {
      const pkg=await pinPackage({name:'test/foreign-import',role:'library',dependencies:[],input:{kind:'source',files:[['main.mbt','fn foreign() -> Int32 = "browser" "fetch"\npub fn handle() -> Int32 { foreign() }']]}});
      const packages=[pkg];return await executeAssembly(tools,{root:pkg.pin,packages,identity:await assemblyIdentity(compilerVersion,packages),target:'wasm',exports:['handle']});
    }finally{tools.dispose();}
  })();
  const other=await prepareArtifact(foreign,await mepExecutionProfile());
  // An unbounded module is rejected even before missing host imports are examined.
  await assert.rejects(loadMepAdapter(other),/finite maximum/);
  const bounded=await prepareArtifact({...foreign,artifact:{...foreign.artifact,bytes:boundWasmMemory(foreign.artifact.bytes,mepLimits.memoryPages)}},await mepExecutionProfile());
  await assert.rejects(loadMepAdapter(bounded),/Missing or incompatible host import: browser.fetch/);
});

test('worker timeout and disposal stop execution before rejecting and prevent reuse',async()=>{
  const saved=await fixture();
  const adapter=await loadNodeMepAdapter(saved,1000);
  assert.equal((await adapter.exchange(encode('fresh'))).kind,'response');
  const loop=adapter.exchange(encode('!'));
  await assert.rejects(adapter.exchange(encode('concurrent')),/busy/);
  await assert.rejects(loop,/timed out; worker stopped/);
  await assert.rejects(adapter.exchange(encode('again')),/failed/);await adapter.dispose();await adapter.dispose();
  const fresh=await loadNodeMepAdapter(saved);
  assert.equal((await fresh.exchange(encode('fresh'))).kind,'response');
  assert.deepEqual(await fresh.exchange(new Uint8Array()),{kind:'exit'});
  await assert.rejects(fresh.exchange(encode('again')),/closed/);await fresh.dispose();
});

test('Content-Length framing keeps split UTF8, zero bodies, notifications and coalesced frames',async()=>{
  const frames=new MepFrames(),seen:Uint8Array<ArrayBuffer>[]=[];
  const text=encode('🌕'),frame=Buffer.concat([Buffer.from(`Content-Length: ${text.length}\r\n\r\n`),text]);
  const accept=async(body:Uint8Array<ArrayBuffer>)=>{seen.push(body);return true;};
  for(const byte of frame)await frames.push(new Uint8Array([byte]),accept);
  await frames.push(encode('Content-Length: 0\r\n\r\nContent-Length: 1\r\n\r\nx'),accept);
  frames.finish();assert.deepEqual(seen,[text,new Uint8Array(),encode('x')]);
  assert.equal(await frames.push(encode('Content-Length: 1\r\n\r\nxContent-Length: 1\r\n\r\ny'),async()=>false),false);
  await assert.rejects(frames.push(frame,accept),/closed/);
  for(const value of ['Content-Length: 2\r\n\r\nx','Content-Length: 1\r\nContent-Length: 1\r\n\r\nx','Content-Length: 16777217\r\n\r\n','x'.repeat(8193),'Content-Length: -1\r\n\r\n','Other: yes\r\n\r\n']) {
    const decoder=new MepFrames();let failed=false;
    try{await decoder.push(encode(value),accept);decoder.finish();}catch{failed=true;}
    assert.equal(failed,true,value.slice(0,80));
  }
});

test('memory policy bounds real memory.grow and rejects shared, multiple, memory64 and malformed memories',async()=>{
  const header=[0,97,115,109,1,0,0,0];
  const raw=new Uint8Array([...header,5,3,1,0,1]);
  const bounded=boundWasmMemory(raw,2);verifyWasmMemory(bounded,2);
  // Export the bounded memory using the standard export-section encoding.
  const exported=new Uint8Array([...bounded,7,10,1,6,109,101,109,111,114,121,2,0]);
  const {instance}=await WebAssembly.instantiate(exported);
  const memory=instance.exports.memory as WebAssembly.Memory;
  assert.equal(memory.grow(1),1);assert.throws(()=>memory.grow(1),RangeError);
  assert.throws(()=>verifyWasmMemory(raw,2),/finite maximum/);
  assert.throws(()=>boundWasmMemory(raw,0),/policy/);
  assert.throws(()=>boundWasmMemory(new Uint8Array([...header,5,3,1,0,3]),2),/Initial memory/);
  for(const suffix of [[5,4,1,3,1,2],[5,3,1,4,1],[5,5,2,0,1,0,1],[5,9,1,0,1],[5,3,1,0,1,5,3,1,0,1]]) {
    assert.throws(()=>boundWasmMemory(new Uint8Array([...header,...suffix]),2));
  }
});
