import {loadArtifact} from './artifacts.mjs';
import type {SavedArtifact, ExecutionProfile, LoadedArtifact} from './artifacts.mjs';
import {sha256, AssemblyFailure} from './assembly.mjs';

export type ByteProfile = 'bytes-v1' | 'bytes-diagnostics-v1';
export const byteLimits = Object.freeze({request:3146752, response:2097152});
const baseContract = 'morphir/byte-adapter/v1-draft\ncore-wasm; target=wasm; utf8=strict; request<=3146752; response<=2097152\nimports morphir_bytes_v1.input_len:()->i32,input_byte:(i32)->i32,output_byte:(i32)->()\nexport handle:()->i32; 0=exit-no-output; positive=exact-response-bytes; -1=infrastructure-failure\nsequential; one-owned-request; output-in-order; exit-terminal; failure-terminal; dispose-idempotent\n';
/** Contract identity is separate from compiler, library and artifact identities. */
export async function byteExecutionProfile(kind:ByteProfile):Promise<ExecutionProfile> {
  if (kind !== 'bytes-v1' && kind !== 'bytes-diagnostics-v1') throw new TypeError('Unknown byte execution profile');
  const contract = kind === 'bytes-v1' ? baseContract : baseContract +
    'imports morphir_diagnostics_v1.response_bytes:(i32)->(); exactly-one-event-per-response; no-event-on-exit-or-failure\n';
  return {id:`morphir/${kind}/v1-draft`,sha256:await sha256(new TextEncoder().encode(contract))};
}
export type ByteExchange = {readonly kind:'response';readonly bytes:Uint8Array<ArrayBuffer>} | {readonly kind:'exit'};
export interface ByteAdapter {
  readonly manifest:LoadedArtifact['manifest'];
  exchange(request:Uint8Array<ArrayBuffer>):ByteExchange;
  dispose():void;
}
export interface ResponseDiagnostic { readonly kind:'response-bytes'; readonly bytes:number; }
/** Explicit service selection. Diagnostics are required only by their own profile. */
export type ByteHost = {readonly profile:'bytes-v1'} |
  {readonly profile:'bytes-diagnostics-v1';readonly diagnostics:(event:ResponseDiagnostic)=>void};

export async function loadByteAdapter(saved:SavedArtifact, host:ByteHost):Promise<ByteAdapter> {
  const snapshot=structuredClone(saved);
  const kind=host.profile;
  const diagnostics=kind === 'bytes-diagnostics-v1' ? host.diagnostics : undefined;
  if (kind === 'bytes-diagnostics-v1' && typeof diagnostics !== 'function')
    throw new AssemblyFailure('compatibility','Diagnostics profile requires an explicit service');
  const executionProfile=await byteExecutionProfile(kind);
  let state:'ready'|'busy'|'closed'|'failed'|'disposed'='ready';
  let input:Uint8Array<ArrayBuffer>=new Uint8Array(0);
  let output:Uint8Array<ArrayBuffer>=new Uint8Array(0);
  let length=0;
  let diagnosticSize:number|undefined;
  const integer=(value:number) => Number.isInteger(value);
  const busy=()=>{if (state !== 'busy') throw new Error('Byte host callback outside exchange');};
  const imports={morphir_bytes_v1:{
    input_len:()=>{busy();return input.length;},
    input_byte:(index:number)=>{busy();if (!integer(index) || index < 0 || index >= input.length) throw new RangeError('Byte input index');return input[index]!;},
    output_byte:(byte:number)=>{busy();if (!integer(byte) || byte < 0 || byte > 255 || length === byteLimits.response) throw new RangeError('Byte response limit or value');output[length++]=byte;},
  },...(diagnostics ? {morphir_diagnostics_v1:{response_bytes:(size:number)=>{
    busy();if (!integer(size) || size <= 0 || size !== length || diagnosticSize !== undefined) throw new Error('Invalid diagnostic event');
    diagnosticSize=size;
  }}} : {})};
  const loaded=await loadArtifact(snapshot,{targets:['wasm'],profiles:[executionProfile],encodings:['ion','json'],imports});
  return {manifest:loaded.manifest,
    exchange(request) {
      if (state !== 'ready') throw new Error(`Byte adapter is ${state}`);
      if (!(request instanceof Uint8Array) || request.length > byteLimits.request) throw new RangeError('Byte request limit');
      // Validate exact UTF-8 before invoking. Do not replace malformed sequences.
      new TextDecoder('utf-8',{fatal:true}).decode(request);
      input=request.slice();output=new Uint8Array(byteLimits.response);length=0;diagnosticSize=undefined;state='busy';
      try {
        const result=loaded.invoke('handle');
        if (result === 0 && length === 0 && diagnosticSize === undefined) {state='closed';return {kind:'exit'};}
        if (typeof result !== 'number' || !integer(result) || result <= 0 || result !== length ||
          (diagnostics ? diagnosticSize !== result : diagnosticSize !== undefined)) throw new Error('Invalid byte guest outcome');
        const bytes=output.slice(0,length);
        new TextDecoder('utf-8',{fatal:true}).decode(bytes);
        diagnostics?.({kind:'response-bytes',bytes:length});
        state='ready';return {kind:'response',bytes};
      } catch(error) {state='failed';loaded.dispose();throw error;}
      finally {input=new Uint8Array();output=new Uint8Array();length=0;diagnosticSize=undefined;}
    },
    dispose() {if(state==='busy') throw new Error('Cannot dispose during exchange');state='disposed';loaded.dispose();},
  };
}
