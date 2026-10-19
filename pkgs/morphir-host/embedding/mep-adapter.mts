import {loadArtifact} from './artifacts.mjs';
import type {SavedArtifact,ExecutionProfile,LoadedArtifact} from './artifacts.mjs';
import {sha256} from './assembly.mjs';
import {verifyWasmMemory} from './wasm-memory.mjs';

export const mepLimits=Object.freeze({request:16777216,response:16777216,header:8192,memoryPages:4096,timeoutMs:10000});
const contract='morphir/mep-bytes-v1/v1-draft\ncore-wasm; wasm32; one-defined-unshared-memory; maximum<=4096-pages; strict-utf8; request<=16777216; response<=16777216\nimports morphir_bytes_v1.input_len:()->i32,input_byte:(i32)->i32,output_byte:(i32)->()\nexport handle:()->i32; positive=exact-response-bytes; 0=exit-no-output; -2=notification-no-output; -1=infrastructure-failure\nMEP JSON-RPC bodies; sequential; one-owned-request; copied-output; persistent-session; exit-terminal; trap-terminal; dispose-idempotent; wire-cancellation=unsupported\n';
export async function mepExecutionProfile():Promise<ExecutionProfile> {
  return {id:'morphir/mep-bytes-v1/v1-draft',sha256:await sha256(new TextEncoder().encode(contract))};
}
export type MepExchange={readonly kind:'response';readonly bytes:Uint8Array<ArrayBuffer>}|{readonly kind:'notification'}|{readonly kind:'exit'};
export interface MepAdapter {
  readonly manifest:LoadedArtifact['manifest'];
  exchange(request:Uint8Array<ArrayBuffer>):MepExchange;
  dispose():void;
}
export async function loadMepAdapter(saved:SavedArtifact):Promise<MepAdapter> {
  const snapshot=structuredClone(saved);
  verifyWasmMemory(snapshot.wasm,mepLimits.memoryPages);
  let state:'ready'|'busy'|'closed'|'failed'|'disposed'='ready';
  let input:Uint8Array<ArrayBuffer>=new Uint8Array(),output:Uint8Array<ArrayBuffer>=new Uint8Array();let length=0;
  const busy=()=>{if(state!=='busy')throw new Error('MEP callback outside exchange');};
  const imports={morphir_bytes_v1:{
    input_len:()=>{busy();return input.length;},
    input_byte:(index:number)=>{busy();if(!Number.isInteger(index)||index<0||index>=input.length)throw new RangeError('MEP input index');return input[index]!;},
    output_byte:(byte:number)=>{busy();if(!Number.isInteger(byte)||byte<0||byte>255||length===mepLimits.response)throw new RangeError('MEP output byte or limit');output[length++]=byte;},
  }};
  // loadArtifact checks the manifest against the actual module before it runs.
  const loaded=await loadArtifact(snapshot,{targets:['wasm'],profiles:[await mepExecutionProfile()],encodings:['ion','json'],imports});
  const expected=new Set(['input_len','input_byte','output_byte']);
  if(loaded.manifest.invocation.imports.some(i=>i.module!=='morphir_bytes_v1'||i.kind!=='function'||!expected.has(i.name))) {
    loaded.dispose();throw new Error('Unexpected MEP host service');
  }
  return {manifest:loaded.manifest,
    exchange(request) {
      if(state!=='ready')throw new Error(`MEP adapter is ${state}`);
      if(!(request instanceof Uint8Array)||request.length>mepLimits.request)throw new RangeError('MEP request limit');
      new TextDecoder('utf-8',{fatal:true}).decode(request);
      input=request.slice();output=new Uint8Array(mepLimits.response);length=0;state='busy';
      try {
        const result=loaded.invoke('handle');
        if(result===0 && length===0){state='closed';return {kind:'exit'};}
        if(result===-2 && length===0){state='ready';return {kind:'notification'};}
        if(typeof result!=='number'||!Number.isInteger(result)||result<=0||result!==length)throw new Error('Invalid MEP guest outcome');
        const bytes=output.slice(0,length);new TextDecoder('utf-8',{fatal:true}).decode(bytes);
        state='ready';return {kind:'response',bytes};
      } catch(error){state='failed';loaded.dispose();throw error;}
      finally {input=new Uint8Array();output=new Uint8Array();length=0;}
    },
    dispose(){if(state==='busy')throw new Error('Cannot dispose during MEP exchange');state='disposed';loaded.dispose();},
  };
}
