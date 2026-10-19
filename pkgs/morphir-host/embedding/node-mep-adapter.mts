import {Worker} from 'node:worker_threads';
import type {SavedArtifact,LoadedArtifact} from './artifacts.mjs';
import {mepLimits} from './mep-adapter.mjs';
import type {MepExchange} from './mep-adapter.mjs';

type Reply=MepExchange|{kind:'ready';manifest:LoadedArtifact['manifest']}|{kind:'failed';message:string};
/** A timeout or failure is terminal. Rejection waits until the worker has
 * stopped; callers never mistake an observation timeout for released resources.
 */
export async function loadNodeMepAdapter(saved:SavedArtifact,timeoutMs:number=mepLimits.timeoutMs):Promise<{
  readonly manifest:LoadedArtifact['manifest'];exchange(bytes:Uint8Array<ArrayBuffer>):Promise<MepExchange>;dispose():Promise<void>;
}> {
  if(!Number.isSafeInteger(timeoutMs)||timeoutMs<=0||timeoutMs>mepLimits.timeoutMs)throw new RangeError('Invalid MEP timeout');
  const worker=new Worker(new URL('./node-mep-worker.mjs',import.meta.url),{workerData:saved,execArgv:[],resourceLimits:{maxOldGenerationSizeMb:128}});
  let state:'loading'|'ready'|'busy'|'closed'|'failed'|'disposed'='loading';
  let termination:Promise<unknown>|undefined;
  let pending:{resolve:(reply:Reply)=>void;reject:(cause:Error)=>void;timer:ReturnType<typeof setTimeout>}|undefined;
  const terminate=()=>termination??=worker.terminate();
  const fail=async(cause:Error)=>{
    if(state==='disposed')return;
    state='failed';const p=pending;pending=undefined;if(p)clearTimeout(p.timer);
    try{await terminate();}catch(cleanup){cause=new AggregateError([cause,cleanup],'MEP termination failed');}
    p?.reject(cause);
  };
  worker.on('error',cause=>{void fail(cause);});
  worker.on('exit',code=>{if(state!=='closed'&&state!=='disposed'&&state!=='failed')void fail(new Error(`MEP worker exited: ${code}`));});
  worker.on('message',(reply:Reply)=>{
    if(reply.kind==='failed'){void fail(new Error(reply.message));return;}
    const p=pending;if(!p){void fail(new Error('Unsolicited MEP worker reply'));return;}
    clearTimeout(p.timer);pending=undefined;p.resolve(reply);
  });
  const wait=()=>new Promise<Reply>((resolve,reject)=>{
    pending={resolve,reject,timer:setTimeout(()=>{void fail(new Error('MEP call timed out; worker stopped'));},timeoutMs)};
  });
  try {
    const reply=await wait();
    if(reply.kind!=='ready')throw new Error('Missing MEP worker initialization');
    state='ready';
    return {manifest:reply.manifest,
      async exchange(bytes) {
        if(state!=='ready')throw new Error(`MEP worker is ${state}`);
        if(!(bytes instanceof Uint8Array)||bytes.length>mepLimits.request)throw new RangeError('MEP request limit');
        new TextDecoder('utf-8',{fatal:true}).decode(bytes);
        state='busy';const result=wait();
        try{worker.postMessage(bytes);}catch(error){void fail(error instanceof Error?error:new Error(String(error)));}
        const reply=await result;
        if(reply.kind==='ready'||reply.kind==='failed'){await fail(new Error('Invalid MEP worker reply'));throw new Error('Invalid MEP worker reply');}
        state=reply.kind==='exit'?'closed':'ready';
        if(reply.kind==='exit')await terminate();
        return reply;
      },
      async dispose(){state='disposed';const p=pending;pending=undefined;if(p){clearTimeout(p.timer);await terminate();p.reject(new Error('MEP adapter disposed'));}else await terminate();},
    };
  }catch(error){await terminate();throw error;}
}
