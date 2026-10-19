import {parentPort,workerData} from 'node:worker_threads';
import {loadMepAdapter} from './mep-adapter.mjs';

if(!parentPort)throw new Error('MEP worker requires a parent');
const port=parentPort;
try {
  const adapter=await loadMepAdapter(workerData);
  port.postMessage({kind:'ready',manifest:adapter.manifest});
  port.on('message',(request:Uint8Array<ArrayBuffer>)=>{
    try {
      const result=adapter.exchange(request);
      port.postMessage(result,result.kind==='response'?[result.bytes.buffer]:[]);
      if(result.kind==='exit'){adapter.dispose();port.close();}
    }catch(error){adapter.dispose();port.postMessage({kind:'failed',message:error instanceof Error?error.message:String(error)});port.close();}
  });
}catch(error){port.postMessage({kind:'failed',message:error instanceof Error?error.message:String(error)});port.close();}
