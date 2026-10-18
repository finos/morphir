import assert from 'node:assert/strict';
import {readFileSync,readdirSync,realpathSync} from 'node:fs';
import {join} from 'node:path';
import {hash} from './identity.mjs';
export const coreCommit='a951c067f909286603efada85c379197d589dc61';
export const coreSourceSha256='08e98b8ae1089b5d8b68086e07441df0e44c7fb87d6464ac408825bd8e974af8';
export type CoreSelection='inherit-override'|'compiler-home';
export function checkedCore(home: string,compilerVersion: string,selection: CoreSelection='inherit-override',check: ()=>void=()=>{}) {
  check();
  if(selection==='compiler-home')assert.equal(compilerVersion,'0.10.15+1e9f6672d-nightly','execution.unverified_llvm_pin');
  const override=selection==='compiler-home'?undefined:process.env.MOON_CORE_OVERRIDE;
  if(selection==='inherit-override')assert.ok(override?.trim(),'execution.core_override_required');
  const core=realpathSync(override||join(home,'lib/core'));
  const version=readFileSync(join(core,'moon.mod'),'utf8').match(/^\s*version\s*=\s*"([^"]+)"/m)?.[1];
  if(!override){assert.equal(version,compilerVersion,'execution.core_version: Matching core version required');return core;}
  assert.equal(version,'0.1.0','execution.core_version: Corrected core version required');
  const paths: string[]=[];
  function walk(relative: string) {
    for(const entry of readdirSync(join(core,relative),{withFileTypes:true})) {
      check();
      const path=relative?relative+'/'+entry.name:entry.name;
      if(path==='_build')continue;
      if(entry.isDirectory())walk(path);
      else {assert.ok(entry.isFile(),'execution.core_source_entry');paths.push(path);}
    }
  }
  walk('');paths.sort();
  assert.equal(hash(paths.map(path=>{check();return path+'\0'+hash(readFileSync(join(core,path)))+'\n';}).join('')),coreSourceSha256,'execution.core_source_identity');
  return core;
}
