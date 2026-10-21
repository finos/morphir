import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync,readFileSync,realpathSync,symlinkSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {checkedCore,coreCommit,coreSourceSha256} from './core.mjs';
import {stableVersion} from './capabilities.mjs';
const root=mkdtempSync(join(tmpdir(),'morphir-core-pin-'));
const previous=process.env.MOON_CORE_OVERRIDE;
try {
  const pin=JSON.parse(readFileSync(new URL('../../../tools/moonbit-core-pin.json',import.meta.url),'utf8'));
  assert.equal(coreCommit,pin.coreCommit);assert.equal(coreSourceSha256,pin.sourceSha256);
  assert.equal(stableVersion,pin.compilerVersion);assert.equal(pin.sourceManifestVersion,pin.compilerVersion);
  delete process.env.MOON_CORE_OVERRIDE;
  const base=join(root,'home/lib/core');mkdirSync(base,{recursive:true});
  writeFileSync(join(base,'moon.mod'),`version="${stableVersion}"\n`);
  assert.throws(()=>checkedCore(join(root,'home'),stableVersion),/core_source_identity/);
  assert.throws(()=>checkedCore(join(root,'home'),'0.10.15+943464bfa'),/core_version/);
  assert.throws(()=>checkedCore(join(root,'home'),stableVersion,'llvm-nightly'),/unverified_llvm_pin/);
  const outside=join(root,'outside.mbt');writeFileSync(outside,'outside');
  // Windows needs Developer Mode or administrator rights for links; its installer writes a copy.
  let linked=true;
  try {symlinkSync(outside,join(base,'escape.mbt'));}
  catch(error) {if(process.platform!=='win32'||(error as NodeJS.ErrnoException).code!=='EPERM')throw error;linked=false;}
  if(linked) {
    assert.throws(()=>checkedCore(join(root,'home'),stableVersion),/core_source_entry/);
    rmSync(join(base,'escape.mbt'));
  }
  for(const value of [base,'x'])  {
    process.env.MOON_CORE_OVERRIDE=value;
    assert.throws(()=>checkedCore(join(root,'home'),stableVersion),/core_override_forbidden/);
  }
  for(const value of ['','   ']) {
    process.env.MOON_CORE_OVERRIDE=value;
    assert.throws(()=>checkedCore(join(root,'home'),stableVersion),/core_source_identity/);
  }
  delete process.env.MOON_CORE_OVERRIDE;
  writeFileSync(join(base,'moon.mod'),'version="0.10.15+1e9f6672d-nightly"\n');
  assert.equal(checkedCore(join(root,'home'),'0.10.15+1e9f6672d-nightly','llvm-nightly'),realpathSync(base),'the LLVM nightly carries its own core');
  const home=process.env.MOON_HOME;
  if(home)assert.equal(checkedCore(home,stableVersion),realpathSync(join(home,'lib/core')),'the installed toolchain core is the pinned stock core');
  console.log('Stock core version, source identity, link and override checks pass');
} finally {if(previous===undefined)delete process.env.MOON_CORE_OVERRIDE;else process.env.MOON_CORE_OVERRIDE=previous;rmSync(root,{recursive:true,force:true});}
