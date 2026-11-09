import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync,mkdtempSync,readdirSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const entry=fileURLToPath(new URL('./qualification.mts',import.meta.url));
const environment=Object.fromEntries(Object.entries(process.env).filter(([name])=>!name.startsWith('MORPHIR_MOONX_')));
environment.NODE_OPTIONS='';
test('qualifier JSON help and error ownership respect the literal delimiter',()=>{
  for(const [args,status,json] of [
    [['--help','--json'],0,true],
    [['--json','--unknown'],2,true],
    [['--json'],1,true],
    [['--','--json'],2,false],
    [['--json','--','--json'],2,true],
  ] as const){
    const result=spawnSync(process.execPath,[entry,...args],{env:environment,encoding:'utf8',timeout:10000});
    assert.ifError(result.error);assert.equal(result.status,status,result.stderr);
    if(json){
      const document=JSON.parse(result.stdout);
      assert.equal(document.profile,'morphir/command-result');assert.equal(document.exitCode,status);
      assert.equal(result.stderr,'');
    }else{assert.equal(result.stdout,'');assert.ok(result.stderr);}
  }
});

test('qualifier refuses mismatched acquisition kinds and public versions before executing a tool',()=>{
  const root=realpathSync(mkdtempSync(join(tmpdir(),'morphir-moonx-kind-')));
  try{
    const bin=join(root,'bin');mkdirSync(bin);
    const extension=process.platform==='win32'?'.exe':'';
    const moonx=join(bin,'moonx'+extension),moonrun=join(bin,'moonrun'+extension);
    // Plain marker files cannot run; a bypassed guard would hit a different
    // failure instead of the required acquisition-identity refusal.
    writeFileSync(moonx,'not executable');writeFileSync(moonrun,'not executable');
    for(const [program,kind,prefix,message] of [
      [moonrun,'public',['finos/morphir/moonx@0.1.0','--'],'Public qualification must invoke stock Moonx'],
      [moonx,'public',['finos/morphir/moonx@0.2.0'],'Public qualification must use the exact Morphir coordinate and version'],
      [moonx,'archive',['finos/morphir/moonx@0.1.0'],'Archive qualification must invoke stock Moonrun'],
    ] as const){
      const result=spawnSync(process.execPath,[entry,'--json'],{encoding:'utf8',timeout:10000,env:{...environment,
        MORPHIR_MOONX_PROGRAM:program,MORPHIR_MOONX_COMPILER_HOME:root,MORPHIR_MOONX_KIND:kind,
        MORPHIR_MOONX_PREFIX_JSON:JSON.stringify(prefix),MORPHIR_MOONX_VERSION:'0.1.0',
      }});
      assert.ifError(result.error);assert.equal(result.status,1,result.stderr);
      const document=JSON.parse(result.stdout);assert.equal(document.error.code,'qualification_failed');
      assert.ok(document.error.message.includes(message),document.error.message);assert.equal(result.stderr,'');
    }
    assert.deepEqual(readdirSync(root),['bin'],'Refusals start no compiler or consumer workspace');
  }finally{rmSync(root,{recursive:true,force:true});}
});
