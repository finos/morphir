import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {performance} from 'node:perf_hooks';
const [artifact,input,output,identity,traceparent]=process.argv.slice(2);
assert.ok(artifact && input && output && identity && typeof traceparent==='string');
const bytes=readFileSync(input);assert.ok(bytes.length<=1048576,'execution.input_limit');
const module=await WebAssembly.compile(readFileSync(artifact));
const abi={
  input_length:()=>bytes.length,
  input_byte:(i: number)=>{assert.ok(i>=0&&i<bytes.length);return bytes[i]!;},
  trace_length:()=>traceparent.length,
  trace_char:(i: number)=>{assert.ok(i>=0&&i<traceparent.length);return traceparent.charCodeAt(i);},
  identity_length:()=>identity.length,
  identity_char:(i: number)=>{assert.ok(i>=0&&i<identity.length);return identity.charCodeAt(i);},
  output_begin:(size: number)=>{assert.ok(Number.isInteger(size)&&size>=0&&size<=1048576);assert.equal(out,null);out=Buffer.alloc(size);},
  output_byte:(i: number,b: number)=>{assert.ok(out&&i===written&&i<out.length&&b>=0&&b<=255);out[i]=b;written++;},
  monotonic:()=>performance.now()/1000,
};
let out: Buffer | null=null,written=0;
const imports=WebAssembly.Module.imports(module);
assert.ok(imports.length>0);
for(const imp of imports)assert.ok(imp.module==='morphir_execution_v1'&&imp.kind==='function'&&Object.hasOwn(abi,imp.name),'execution.missing_import: '+imp.module+'.'+imp.name);
const instance=await WebAssembly.instantiate(module,{morphir_execution_v1:abi});
assert.ok(typeof instance.exports._start==='function','execution.missing_entry');
instance.exports._start();
const outputBytes = out as Buffer | null;
assert.ok(outputBytes&&written===outputBytes.length,'execution.incomplete_output');writeFileSync(output,outputBytes);
