import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {capabilities,stableVersion} from './capabilities.mjs';
const root=mkdtempSync(join(tmpdir(),'morphir-pin-test-'));
const pin={profile:'morphir-toolchain-pin-v1',platform:process.platform,arch:process.arch,
  compilerIdentity:'a'.repeat(64),coreIdentity:'b'.repeat(64),compilerVersion:'0.10.15+1e9f6672d-nightly'};
try {
  // There is no compiler in this directory. Version/target selection must reject
  // before attempting a compiler, hashing the core or advertising capabilities.
  for(const targets of [['js'],['wasm-gc'],['native'],['js','native']]) {
    assert.throws(()=>capabilities({compilerHome:root,timeout:1000,toolchainPin:{...pin,targets}}),/execution.unverified_stable_pin/);
  }
  for(const compilerVersion of [stableVersion,pin.compilerVersion]) {
    assert.throws(()=>capabilities({compilerHome:root,timeout:1000,toolchainPin:{...pin,compilerVersion,targets:['llvm','js']}}),/execution.mixed_compiler_targets/);
  }
  assert.throws(()=>capabilities({compilerHome:root,timeout:1000,toolchainPin:{...pin,compilerVersion:stableVersion,targets:['js','js']}}),/execution.duplicate_target/);
  console.log('Non-LLVM compiler versions, mixed targets and duplicate targets rejected before compiler effects');
} finally {rmSync(root,{recursive:true,force:true});}
