import type {loadByteAdapter as LoadByteAdapter} from '../byte-adapter.mjs';
import type {ByteProfile,ByteHost} from '../byte-adapter.mjs';
import type {SavedArtifact} from '../artifacts.mjs';

/** Same real saved-artifact failure and lifecycle checks on both concrete hosts. */
export async function preflight(saved:SavedArtifact, profile:ByteProfile, loadByteAdapter:typeof LoadByteAdapter):Promise<void> {
  const encode=(text:string)=>new TextEncoder().encode(text);
  const require=(condition:boolean,message:string)=>{if(!condition)throw new Error(message);};
  const refuses=(body:()=>unknown,message:string)=>{let failed=false;try{body();}catch{failed=true;}require(failed,message);};
  const asyncRefuses=async(body:()=>Promise<unknown>,message:string)=>{let failed=false;try{await body();}catch{failed=true;}require(failed,message);};
  const events:number[]=[];
  const host:ByteHost=profile === 'bytes-v1'?{profile}:{profile,diagnostics:event=>{events.push(event.bytes);}};
  if(profile==='bytes-diagnostics-v1') {
    await asyncRefuses(()=>loadByteAdapter(saved,{profile:'bytes-v1'}),'Baseline host accepted diagnostics artifact');
    await asyncRefuses(()=>loadByteAdapter(saved,{profile,diagnostics:undefined} as never),'Missing service accepted');
  }
  const capabilities=encode('{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.26"}');
  const adapter=await loadByteAdapter(saved,host);
  try {
    refuses(()=>adapter.exchange(new Uint8Array([0xff])),'Malformed UTF8 accepted');
    let retained:Uint8Array<ArrayBuffer>|undefined;
    for(let i=0;i<5;i++) {
      const value=adapter.exchange(capabilities);
      require(value.kind==='response','Missing capabilities');
      if(value.kind==='response') {
        require(JSON.parse(new TextDecoder().decode(value.bytes)).id===1,'Correlation changed');
        if(!retained)retained=value.bytes;
        require(new TextDecoder().decode(retained)===new TextDecoder().decode(value.bytes),'Retained host output changed');
      }
    }
    require(events.length===(profile==='bytes-v1'?0:5),'Diagnostic service event count mismatch');
    refuses(()=>adapter.exchange(encode('malformed JSON')),'Malformed request did not fail');
    refuses(()=>adapter.exchange(capabilities),'Failed guest reused');
  } finally {adapter.dispose();adapter.dispose();}
  refuses(()=>adapter.exchange(capabilities),'Disposed guest reused');
  const fresh=await loadByteAdapter(saved,host);
  try {
    require(fresh.exchange(capabilities).kind==='response','Fresh host did not recover');
    const before=events.length;
    require(fresh.exchange(encode('{"id":2,"op":"exit"}')).kind==='exit','Exit did not close');
    require(events.length===before,'Exit emitted diagnostics');
    refuses(()=>fresh.exchange(capabilities),'Closed guest reused');
  } finally {fresh.dispose();}
}
