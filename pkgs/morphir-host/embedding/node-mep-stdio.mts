import {once} from 'node:events';
import {readDirectoryArtifact} from './node-artifacts.mjs';
import {loadNodeMepAdapter} from './node-mep-adapter.mjs';
import {MepFrames} from './mep-frames.mjs';

/** Content-Length process binding. Importing this module does not start I/O. */
export async function runMepExtension(directory:string):Promise<void> {
  const adapter=await loadNodeMepAdapter(await readDirectoryArtifact(directory));
  const frames=new MepFrames();
  try {
    for await(const chunk of process.stdin.iterator({destroyOnReturn:false})) {
      const proceed=await frames.push(chunk,async body=>{
        const response=await adapter.exchange(body);
        if(response.kind==='exit')return false;
        if(response.kind==='response') {
          const header=Buffer.from(`Content-Length: ${response.bytes.length}\r\n\r\n`);
          if(!process.stdout.write(Buffer.concat([header,response.bytes])))await once(process.stdout,'drain');
        }
        return true;
      });
      if(!proceed)return;
    }
    frames.finish();
  }finally{frames.clear();process.stdin.destroy();await adapter.dispose();}
}
