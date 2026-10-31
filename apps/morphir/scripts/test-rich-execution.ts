import type { ConformanceReport, VerificationReport } from '../../../tests/cli-contracts.ts';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';

const repo=fileURLToPath(new URL('../../../',import.meta.url));
const home=process.env.MOON_HOME;
assert.ok(home,'Supply pinned MOON_HOME');
const root=mkdtempSync(join(tmpdir(),'morphir-rich-execution-'));
function run(program: string,args: string[],status=0) {
  const result=spawnSync(program,args,{cwd:repo,encoding:'utf8',timeout:180000,maxBuffer:8*1024*1024});
  assert.equal(result.error,undefined);
  assert.equal(result.status,status,result.stderr+'\n'+result.stdout);
  return result;
}
const moon=join(home,'bin/moon');
const cli=join(repo,'_build/js/debug/build/morphir/morphir/node/node.js');
const dependencies=['finos/morphir-sdk=pkgs/morphir-sdk','finos/morphir-execution=pkgs/morphir-execution','moonrockz/ion=.mooncakes/moonrockz/ion','moonbitlang/x=.mooncakes/moonbitlang/x','moonbitlang/async=.mooncakes/moonbitlang/async'].flatMap(v=>['--dependency',v]);
const llvmHome=process.env.MORPHIR_LLVM_HOME,llvmPin=process.env.MORPHIR_LLVM_PIN;
assert.equal(Boolean(llvmHome),Boolean(llvmPin),'Supply both MORPHIR_LLVM_HOME and MORPHIR_LLVM_PIN');
const targets=['js','wasm-gc',...(['darwin','linux'].includes(process.platform)?['native']:[]),...(llvmHome?['llvm']:[])];
const suite=join(repo,'pkgs/morphir-moonbit/fixtures/execution/pricing-suite.ion');
const helper=join(repo,'apps/morphir/build-provider/execution.mjs');
const receipts=process.env.MORPHIR_EXECUTION_RECEIPTS;
if(receipts)mkdirSync(receipts,{recursive:true});
try {
  const fixture=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-moonbit/acceptance']).stdout);
  const model=join(root,'pricing.json');writeFileSync(model,fixture.pricingIR);
  run(moon,['build','--target','js']);
  const call=(target: string,mode: string,extra: string[]=[]): VerificationReport=>JSON.parse(run(process.execPath,[cli,'verify',model,'--suite',suite,'--execution-helper',helper,'--home',target==='llvm'?llvmHome!:home,...(target==='llvm'?['--toolchain-pin',llvmPin!]:[]),...dependencies,'--target',target,'--build-mode',mode,...extra,'--json']).stdout);
  let baseline: VerificationReport | undefined;
  for(const target of targets)for(const mode of ['debug','release']) {
    const log=join(root,target+'-'+mode+'.jsonl');
    const report=call(target,mode,['--log-file',log,'--log-format','json-lines']);
    assert.equal(report.successful,true);assert.equal(report.calls.length,32);
    assert.equal(report.evidence.buildMode,mode);
    assert.equal(report.comparison.profile,'morphir-comparison-exact-v1');
    assert.equal(report.extensions.format,'ion-binary');
    assert.ok(!('traceparent' in report.invocationEvidence));
    const actual=report.calls.map(c=>c.actual);
    if(baseline)assert.deepEqual(actual,baseline.calls.map(c=>c.actual));else baseline=report;
    const byId=new Map(report.calls.map(c=>[c.id,c.actual]));
    assert.deepEqual(byId.get('failure'),{type:'model-error',code:'sdk.division_by_zero'});
    assert.deepEqual(byId.get('err'),{type:'result',case:'err',value:{type:'text',units:[110,111]}});
    assert.equal(byId.get('huge-int')!.value,'42');
    assert.equal(byId.get('float-negative-zero')!.bits,'9223372036854775808');
    assert.equal(byId.get('float-nan')!.bits,'9221120237041090626');
    assert.deepEqual(byId.get('upper-expansion'),{type:'character',units:[83,83]});
    assert.deepEqual(byId.get('isolated-surrogates'),{type:'text',units:[0,55296,65,57343]});
    const events=readFileSync(log,'utf8').trim().split('\n').map(line => JSON.parse(line));
    const failure=events.find(e=>e.stage==='call'&&e.details?.code==='sdk.division_by_zero');
    assert.equal(failure.details.entry,'pricing:results#failure');
    assert.ok(events.every(e=>!JSON.stringify(e).includes('12345678901234567890123456789012345')));
    assert.ok(events.every(e=>!JSON.stringify(e).includes('audit')));
    if(receipts)writeFileSync(join(receipts,target+'-'+mode+'.json'),JSON.stringify(report,null,2)+'\n');
  }
  const disabled=call('js','debug',['--telemetry-adapter','none']);
  assert.deepEqual(disabled.calls,baseline!.calls);
  assert.deepEqual(disabled.extensions,baseline!.extensions);
  for(const field of ['sourceIdentity','driverIdentity','manifestIdentity','compilerIdentity','coreIdentity'] as const)assert.equal(disabled.evidence[field],baseline!.evidence[field]);
  assert.equal(disabled.invocationEvidence.suiteIdentity,baseline!.invocationEvidence.suiteIdentity);
  const approximate=call('js','debug',['--comparison','approximate','--absolute-tolerance','0.000001']);
  assert.equal(approximate.successful,true);
  assert.equal(approximate.comparison.profile,'morphir-comparison-approximate-v1');
  const invalid=join(root,'invalid.ion');
  for(const [entry,args,code] of [
    ['quotes#total','morphir_value::{type:"record",fields:[]}','missing_record_field'],
    ['quotes#total','morphir_value::{type:"record",fields:[{name:"quantity",value:{type:"int",value:"1"}},{name:"price",value:{type:"decimal",coefficient:"1",exponent:0}},{name:"extra",value:{type:"unit"}}]}','extra_record_field'],
    ['quotes#total','morphir_value::{type:"record",fields:[{name:"quantity",value:{type:"int",value:"1"}},{name:"quantity",value:{type:"int",value:"1"}}]}','record_field'],
    ['quotes#status-amount','morphir_value::{type:"custom",owner:"other:main#status",tag:"pricing:quotes#approved",items:[]}','constructor_owner'],
    ['quotes#status-amount','morphir_value::{type:"custom",owner:"pricing:quotes#status",tag:"pricing:quotes#approved",items:[]}','constructor_arity'],
    ['quotes#captured','1','boundary_function'],
  ] as const) {
    writeFileSync(invalid,'{profile:"morphir-invocations-v1",calls:[{id:"invalid",entry:"pricing:'+entry+'",arguments:['+args+']}]}');
    const result=run(process.execPath,[cli,'verify',model,'--suite',invalid,'--dry-run','--json'],2);
    assert.match(result.stderr,new RegExp(code!));
  }
  assert.match(run(process.execPath,[cli,'verify',model,'--suite',suite,'--absolute-tolerance','1','--dry-run','--json'],2).stderr,/explicit_approximate_required/);
  console.log('Rich pricing parity: '+targets.join(', ')+'; debug/release; exact values, Ion extensions and telemetry isolation passed.');
} finally {rmSync(root,{recursive:true,force:true});}
