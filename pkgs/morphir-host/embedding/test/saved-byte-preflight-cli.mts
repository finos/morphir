import {loadByteAdapter} from '../byte-adapter.mjs';
import {readDirectoryArtifact} from '../node-artifacts.mjs';
import {preflight} from './saved-byte-preflight.mts';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const [directory,profile]=process.argv.slice(2);
if(!directory || (profile !== 'bytes-v1' && profile !== 'bytes-diagnostics-v1'))throw new Error('Supply artifact and exact profile');
await preflight(await readDirectoryArtifact(directory),profile,loadByteAdapter);
if(profile==='bytes-diagnostics-v1') {
  const temporary=await mkdtemp(join(tmpdir(),'morphir-byte-logs-'));
  try {
    for(const explicit of [false,true]) {
      const log=explicit?join(temporary,'selected','outside-default.jsonl'):join(temporary,'.morphir','logs','codec-adapter.jsonl');
      const args=[fileURLToPath(new URL('../node-byte-adapter-cli.mjs',import.meta.url)),resolve(directory),profile,...(explicit?[log]:[])];
      const result=spawnSync(process.execPath,args,{cwd:temporary,env:{...process.env,PATH:''},encoding:'utf8',input:'{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.26"}\n{"id":2,"op":"exit"}\n'});
      if(result.status!==0 || result.stdout.trim().split('\n').length!==1)throw new Error('Diagnostic process failed: '+result.stderr);
      const event=JSON.parse((await readFile(log,'utf8')).trim());
      if(event.kind!=='response-bytes' || event.bytes!==new TextEncoder().encode(result.stdout.trim()).length)throw new Error('Diagnostic log path/event mismatch');
    }
  } finally {await rm(temporary,{recursive:true,force:true});}
}
console.log('Fresh Node saved-artifact lifecycle and profile preflight passed');
