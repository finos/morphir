import assert from 'node:assert/strict';
import {readFileSync,readdirSync,realpathSync,lstatSync} from 'node:fs';
import {join} from 'node:path';
import {hash} from './identity.mjs';
import {isWithin} from './paths.mjs';
export const coreCommit='417988f6e19738a7f683ce19a6cf5aaf52c96965';
export const coreSourceSha256='5438bf99976daf54091564ea9c504bfb5ab9dc493e4f6736a7a4df33b6a99f69';
export type CoreSelection='stable'|'llvm-nightly';
export function checkedCore(home: string,compilerVersion: string,selection: CoreSelection='stable',check: ()=>void=()=>{}) {
  check();
  if(selection==='llvm-nightly')assert.equal(compilerVersion,'0.10.15+1e9f6672d-nightly','execution.unverified_llvm_pin');
  // Every lane compiles with the toolchain's own core, as consumers do.
  assert.ok(!process.env.MOON_CORE_OVERRIDE?.trim(),'execution.core_override_forbidden: Unset MOON_CORE_OVERRIDE');
  const core=realpathSync(join(home,'lib/core'));
  const version=readFileSync(join(core,'moon.mod'),'utf8').match(/^\s*version\s*=\s*"([^"]+)"/m)?.[1];
  assert.equal(version,compilerVersion,'execution.core_version: Matching core version required');
  if(selection==='llvm-nightly')return core;
  const paths: string[]=[];
  function walk(relative: string) {
    for(const entry of readdirSync(join(core,relative),{withFileTypes:true})) {
      check();
      const path=relative?relative+'/'+entry.name:entry.name;
      if(path==='_build')continue;
      if(entry.isDirectory())walk(path);
      else if(entry.isSymbolicLink()) {
        // The Unix installer keeps upstream's README link; Windows has a copy. Both count as the file.
        const target=realpathSync(join(core,path));
        assert.ok(isWithin(core,target)&&lstatSync(target).isFile(),'execution.core_source_entry');paths.push(path);
      }
      else {assert.ok(entry.isFile(),'execution.core_source_entry');paths.push(path);}
    }
  }
  walk('');paths.sort();
  assert.equal(hash(paths.map(path=>{check();return path+'\0'+hash(readFileSync(join(core,path)))+'\n';}).join('')),coreSourceSha256,'execution.core_source_identity');
  return core;
}
