import { npmCli } from '../../../tests/npm.ts';
import type { ConformanceReport, VerificationReport } from '../../../tests/cli-contracts.ts';
import type { RunOptions } from '../../../tests/cli-contracts.ts';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,existsSync,readdirSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {testInstalledFrontend} from './test-installed-frontend.ts';
import {testInstalledLibrary,testInstalledNaming} from './test-installed-library.ts';

const repo=fileURLToPath(new URL('../../../',import.meta.url));
const home=process.env.MOON_HOME;
assert.ok(home,'Explicit pinned MOON_HOME required');
const llvmHome=process.env.MORPHIR_LLVM_HOME,llvmPin=process.env.MORPHIR_LLVM_PIN;
assert.equal(Boolean(llvmHome),Boolean(llvmPin),'LLVM home and pin must be supplied together');
const required=(process.env.MORPHIR_REQUIRED_TARGETS||'js,wasm-gc,native').split(',');
assert.ok(required.every(t=>['js','wasm-gc','native','llvm'].includes(t)));
assert.equal(new Set(required).size,required.length);
assert.ok(!required.includes('llvm')||llvmHome,'Required LLVM lane needs explicit home and pin');
const root=mkdtempSync(join(tmpdir(),'morphir-installed-'));
const receipts=resolve(process.env.MORPHIR_INSTALLED_RECEIPTS||join(root,'receipts'));
mkdirSync(receipts,{recursive:true});
rmSync(join(receipts,'summary.json'),{force:true});
function run(program: string,args: string[],{cwd=repo,status=0,env=process.env}: RunOptions = {}) {
  const r=spawnSync(program,args,{cwd,env,encoding:'utf8',timeout:240000,maxBuffer:16*1024*1024});
  assert.equal(r.error,undefined);
  if(status===null)assert.ok(r.status!>0,r.stderr+'\n'+r.stdout);
  else assert.equal(r.status,status,r.stderr+'\n'+r.stdout);
  return r;
}
try {
  const moon=join(home,'bin/moon');
  const fixture=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-moonbit/acceptance']).stdout);
  const formats=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-engine/acceptance']).stdout);
  const app=join(repo,'apps/morphir');
  const npm=npmCli;
  const npmRun=(args: string[],cwd: string)=>run(npm?process.execPath:'npm',npm?[npm,...args]:args,{cwd});
  const pack=JSON.parse(npmRun(['pack','--json','--pack-destination',root],app).stdout)[0];
  const installation=join(root,'installation');mkdirSync(installation);
  npmRun(['install','--offline','--ignore-scripts','--no-audit','--no-fund','--prefix',installation,join(root,pack.filename)],root);
  const installed=join(installation,'node_modules/@morphir/morphir');
  const helper=join(installed,'build-provider/execution.mjs');
  const cwd=join(root,'empty-cwd');mkdirSync(cwd);
  const cli=join(installed,'bin/morphir.js');
  const dependencyPaths={
    'finos/morphir-sdk':join(repo,'pkgs/morphir-sdk'),
    'finos/morphir-execution':join(repo,'pkgs/morphir-execution'),
    'moonrockz/ion':join(repo,'.mooncakes/moonrockz/ion'),
    'moonbitlang/x':join(repo,'.mooncakes/moonbitlang/x'),
    'moonbitlang/async':join(repo,'.mooncakes/moonbitlang/async'),
  };
  const deps=Object.entries(dependencyPaths).flatMap(([name,path])=>['--dependency',name+'='+path]);
  for(const name of ['execution.mjs','evaluator.mjs','telemetry.mjs','wasm-gc.mjs','supervision.mjs','identity.mjs'])assert.ok(existsSync(join(installed,'build-provider',name)),name);
  assert.ok(!existsSync(join(installed,'scripts')),'No repository scripts in installed package');
  const naming=testInstalledNaming({run,root,receipts,cli,helper,cwd,home,llvmHome,llvmPin,required,deps,pack,fixtures:formats.naming,repo});
  if(process.argv.includes('--naming-only')) {
    console.log('Installed naming qualification passed.');
  } else {
  const cases=join(root,'cases.ion');writeFileSync(cases,readFileSync(join(repo,'pkgs/morphir-moonbit/fixtures/execution/conformance-cases.ion')));
  const models=[['morphir-json','model.json',fixture.conformanceIR],['ion-text','model.ion',formats.ionText],['ion-binary','model.ionb',Buffer.from(formats.ionBinary)]];
  for(const [,file,bytes]of models)writeFileSync(join(root,file),bytes);
  const invoke=(file: string,target: string,mode: string,extra: string[]=[],status=0)=>run(process.execPath,[cli,'conform',join(root,file),'--cases',cases,'--execution-helper',helper,'--home',target==='llvm'?llvmHome!:home,...(target==='llvm'?['--toolchain-pin',llvmPin!]:[]),...deps,'--target',target,'--build-mode',mode,...extra],{cwd,status});
  let baseline;
  const rows=[];
  for(const target of required)for(const mode of ['debug','release'])for(const [format,file]of models) {
    const id=[target,mode,format].join('-');
    const log=join(root,id+'.ionb');
    const report: ConformanceReport=JSON.parse(invoke(file,target,mode,['--receipt',join(receipts,id+'.ionb'),'--log-file',log,'--json']).stdout);
    assert.equal(report.successful,true);assert.equal(report.execution.target,target);
    assert.equal(report.execution.evidence.buildMode,mode);
    assert.equal(report.execution.evidence.capability!.backend,target==='native'?'c':target);
    assert.equal(report.execution.calls.length,23);
    assert.ok(report.coverage.filter(l=>l.required).every(l=>l.calls.length===23&&l.calls.every(c=>c.status==='matched')));
    const actual=report.execution.calls.map(c=>c.actual);
    if(baseline)assert.deepEqual(actual,baseline);else baseline=actual;
    assert.ok(!existsSync(report.execution.evidence.executable!),'Execution lease disposed');
    assert.deepEqual([...readFileSync(log).subarray(0,4)],[224,1,0,234]);
    writeFileSync(join(receipts,id+'.json'),JSON.stringify(report,null,2)+'\n');
    rows.push({target,mode,format,compilerIdentity:report.execution.evidence.compilerIdentity,coreIdentity:report.execution.evidence.coreIdentity,dependencies:report.execution.evidence.dependencies,driverIdentity:report.execution.evidence.driverIdentity,runtime:report.execution.evidence.capability!.runtime});
  }
  const dryLog=join(root,'dry.ionb'),dryReceipt=join(root,'dry-receipt.ionb');
  const dry=JSON.parse(invoke('model.ionb','js','debug',['--dry-run','--log-file',dryLog,'--receipt',dryReceipt,'--json']).stdout);
  assert.equal(dry.dryRun,true);assert.equal(dry.calls.length,23);assert.equal(dry.capabilityVerification,'deferred');
  assert.ok(!existsSync(dryLog));assert.ok(!existsSync(dryReceipt));
  assert.ok(!existsSync(join(cwd,'.morphir/logs')));
  const defaultObserved: ConformanceReport=JSON.parse(invoke('model.ionb','js','debug',['--log','--json']).stdout);
  assert.deepEqual(defaultObserved.execution.calls.map(c=>c.actual),baseline);
  assert.deepEqual([...readFileSync(join(cwd,'.morphir/logs/execution.ionb')).subarray(0,4)],[224,1,0,234]);
  const human=invoke('model.ion','js','debug',[]).stdout;
  assert.match(human,/independent exact-add: matched/);assert.match(human,/scheme record-update: matched/);
  const linesLog=join(root,'events.jsonl');
  const lines=invoke('model.json','js','debug',['--log-file',linesLog,'--log-format','json-lines','--json-lines']).stdout.trim().split('\n').map(line => JSON.parse(line));
  const result=lines.find(l=>l.type==='result').data;
  assert.equal(result.successful,true);assert.deepEqual(result.execution.calls.map((c: import('../../../tests/cli-contracts.ts').Call)=>c.actual),baseline);
  assert.ok(readFileSync(linesLog,'utf8').trim().split('\n').map(line => JSON.parse(line)).some(r=>r.stage==='call'));
  const stderr=invoke('model.json','js','debug',['--log-file','@stderr','--log-format','text','--json']);
  assert.equal(JSON.parse(stderr.stdout).successful,true);assert.match(stderr.stderr,/call .*morphir-observation-v1/);
  const bad=join(root,'wrong.ion');writeFileSync(bad,readFileSync(cases,'utf8').replace('expected:18014398509481986','expected:18014398509481987'));
  const mismatch=run(process.execPath,[cli,'conform',join(root,'model.ionb'),'--cases',bad,'--execution-helper',helper,'--home',home,...deps,'--json'],{cwd,status:1});
  const report: ConformanceReport=JSON.parse(mismatch.stdout);assert.equal(report.successful,false);
  assert.equal(report.coverage.find(l=>l.provider==='independent')!.calls.find(c=>c.id==='exact-add')!.status,'mismatch');
  const frontend=testInstalledFrontend({run,root,receipts,cli,helper,cwd,home,llvmHome,llvmPin,required,deps,pack});
  const libraryFixtures=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-moonbit-frontend/library-acceptance']).stdout);
  const library=testInstalledLibrary({run,root,receipts,cli,helper,cwd,home,llvmHome,llvmPin,required,deps,pack,fixtures:libraryFixtures});
  assert.deepEqual(readdirSync(cwd),['.morphir'],'Only explicitly enabled default logs in cwd');
  assert.deepEqual(readdirSync(join(cwd,'.morphir')),['logs']);
  writeFileSync(join(receipts,'summary.json'),JSON.stringify({profile:'morphir-installed-lifecycle-v1',package:pack.integrity,node:process.version,platform:process.platform,arch:process.arch,requiredTargets:required,rows,frontend,library,naming,formats:models.map(m=>m[0]),calls:23,dryRun:true,mismatchRejected:true,stdoutFraming:true,localSinks:['ion-binary','json-lines','stderr-text']},null,2)+'\n');
  console.log('Installed lifecycle: '+required.join(', ')+' debug/release, JSON + Ion text/binary, 23 calls; framing, sinks, dry-run and deliberate mismatch passed.');
  }
} finally {rmSync(root,{recursive:true,force:true});}
