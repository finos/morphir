import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync,readFileSync,realpathSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {checkedCore,coreCommit,coreSourceSha256} from './core.mjs';
const root=mkdtempSync(join(tmpdir(),'morphir-core-pin-'));
const previous=process.env.MOON_CORE_OVERRIDE;
try {
  const pin=JSON.parse(readFileSync(new URL('../../../tools/moonbit-core-pin.json',import.meta.url),'utf8'));
  assert.equal(coreCommit,pin.coreCommit);assert.equal(coreSourceSha256,pin.sourceSha256);
  const base=join(root,'home/lib/core');mkdirSync(base,{recursive:true});
  writeFileSync(join(base,'moon.mod'),'version="0.10.15+943464bfa"\n');
  delete process.env.MOON_CORE_OVERRIDE;
  assert.throws(()=>checkedCore(join(root,'home'),'0.10.15+943464bfa'),/core_override_required/);
  process.env.MOON_CORE_OVERRIDE='';
  assert.throws(()=>checkedCore(join(root,'home'),'0.10.15+943464bfa'),/core_override_required/);
  process.env.MOON_CORE_OVERRIDE='   ';
  assert.throws(()=>checkedCore(join(root,'home'),'0.10.15+943464bfa'),/core_override_required/);
  const override=join(root,'forged');mkdirSync(override);
  writeFileSync(join(override,'moon.mod'),'version="0.1.0"\n');
  writeFileSync(join(override,'provenance.json'),JSON.stringify(pin));
  process.env.MOON_CORE_OVERRIDE=override;
  assert.throws(()=>checkedCore(join(root,'home'),'0.10.15+943464bfa'),/core_source_identity/);
  assert.throws(()=>checkedCore(join(root,'home'),'0.10.15+943464bfa','compiler-home'),/unverified_llvm_pin/);
  writeFileSync(join(base,'moon.mod'),'version="0.10.15+1e9f6672d-nightly"\n');
  assert.equal(checkedCore(join(root,'home'),'0.10.15+1e9f6672d-nightly','compiler-home'),realpathSync(base),'independent LLVM core ignores repository override');
  if(previous){process.env.MOON_CORE_OVERRIDE=previous;assert.equal(checkedCore(join(root,'home'),'0.10.15+943464bfa'),previous);}
  console.log('Corrected core selection, source identity and independent pin checks pass');
} finally {if(previous===undefined)delete process.env.MOON_CORE_OVERRIDE;else process.env.MOON_CORE_OVERRIDE=previous;rmSync(root,{recursive:true,force:true});}
