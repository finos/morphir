import {readDirectoryArtifact} from './node-artifacts.mjs';
import {loadByteAdapter,byteLimits} from './byte-adapter.mjs';
import type {ByteExchange,ByteProfile} from './byte-adapter.mjs';
import {NdjsonFrames} from './ndjson.mjs';
import {once} from 'node:events';
import {mkdirSync,openSync,writeSync,closeSync} from 'node:fs';
import {dirname} from 'node:path';

/** Existing MCK executable boundary. No verdict, corpus or protocol rewriter. */
export async function serveByteAdapter(adapter:{exchange(request:Uint8Array<ArrayBuffer>):ByteExchange|Promise<ByteExchange>;dispose():void|Promise<void>}):Promise<void> {
  const frames=new NdjsonFrames(byteLimits.request);
  try {
    // The default iterator destroys stdin with AbortError on early return.
    // Browser disposal awaits I/O, so that otherwise becomes an uncaught error
    // during a successful MCK exit. Own shutdown explicitly instead.
    for await(const chunk of process.stdin.iterator({destroyOnReturn:false})) {
      const proceed=await frames.push(chunk,async request=>{
        const result=await adapter.exchange(request);
        if(result.kind === 'exit') return false;
        if(result.bytes.includes(10) || result.bytes.includes(13)) throw new Error('Guest response is not a single NDJSON frame');
        if(!process.stdout.write(Buffer.concat([result.bytes,Buffer.from('\n')]))) await once(process.stdout,'drain');
        return true;
      });
      if(!proceed)return;
    }
    frames.finish();
  } finally {frames.clear();process.stdin.destroy();await adapter.dispose();}
}

export async function runByteAdapter(directory:string, profile:ByteProfile, diagnosticsPath='.morphir/logs/codec-adapter.jsonl'):Promise<void> {
  let log:number|undefined;
  try {
    if(profile==='bytes-diagnostics-v1') {
      mkdirSync(dirname(diagnosticsPath),{recursive:true});log=openSync(diagnosticsPath,'a');
    }
    const host=profile === 'bytes-v1' ? {profile} as const : {profile,diagnostics:(event:unknown)=>{
      if(log===undefined)throw new Error('Diagnostics log is closed');
      writeSync(log,JSON.stringify(event)+'\n');
    }} as const;
    await serveByteAdapter(await loadByteAdapter(await readDirectoryArtifact(directory),host));
  } finally {if(log!==undefined)closeSync(log);}
}
