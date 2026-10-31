import type { Call, ConformanceReport, Coverage, VerificationReport } from '../../../tests/cli-contracts.ts';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';

const repo=fileURLToPath(new URL('../../../',import.meta.url));
const home=process.env.MOON_HOME;
assert.ok(home,'Supply pinned MOON_HOME');
const root=mkdtempSync(join(tmpdir(),'morphir-conformance-'));
const receipts=process.env.MORPHIR_CONFORMANCE_RECEIPTS;
if(receipts)mkdirSync(receipts,{recursive:true});
const moon=join(home,'bin/moon');
const cli=join(repo,'_build/js/debug/build/morphir/morphir/node/node.js');
const helper=join(repo,'apps/morphir/build-provider/execution.mjs');
const rustHelper=join(repo,'apps/morphir/build-provider/evaluator.mjs');
const dependencies=['finos/morphir-sdk=pkgs/morphir-sdk','finos/morphir-execution=pkgs/morphir-execution','moonrockz/ion=.mooncakes/moonrockz/ion','moonbitlang/x=.mooncakes/moonbitlang/x','moonbitlang/async=.mooncakes/moonbitlang/async'].flatMap(v=>['--dependency',v]);
const llvmHome=process.env.MORPHIR_LLVM_HOME,llvmPin=process.env.MORPHIR_LLVM_PIN;
const rust=process.env.MORPHIR_RUST_EVALUATOR,rustPin=process.env.MORPHIR_RUST_EVALUATOR_PIN;
assert.equal(Boolean(llvmHome),Boolean(llvmPin),'Supply both LLVM home and pin');
assert.equal(Boolean(rust),Boolean(rustPin),'Supply both Rust evaluator and pin');
const targets=['js','wasm-gc',...(['darwin','linux'].includes(process.platform)?['native']:[]),...(llvmHome?['llvm']:[])];
const cases=join(repo,'pkgs/morphir-moonbit/fixtures/execution/conformance-cases.ion');
const rustCases=join(repo,'pkgs/morphir-moonbit/fixtures/execution/rust-conformance-cases.ion');
const rustOptions=rust?['--rust-evaluator',rust,'--rust-evaluator-pin',rustPin!,'--rust-helper',rustHelper]:[];
function run(program: string,args: string[],status=0) {
  const result=spawnSync(program,args,{cwd:repo,encoding:'utf8',timeout:240000,maxBuffer:8*1024*1024});
  assert.equal(result.error,undefined);
  assert.equal(result.status,status,result.stderr+'\n'+result.stdout);
  return result;
}
function lane(report: ConformanceReport,name: string) {return report.coverage.find(l=>l.provider===name)!;}
const summary: { profile: string; targets: { target: string; mode: string; independent: string; scheme: string; rust: string }[]; rust: { status: string; reason?: string | null; scope?: string; evidence?: Record<string, import('../../../types/data.ts').Json> } }={profile:'morphir-conformance-summary-v1',targets:[] as { target: string; mode: string; independent: string; scheme: string; rust: string }[],rust:{status:rust?'configured':'unavailable',reason:rust?null:'missing explicit binary and pin'}};
try {
  const fixture=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-moonbit/acceptance']).stdout);
  const model=join(root,'conformance.json'),rustModel=join(root,'rust.json');
  writeFileSync(model,fixture.conformanceIR);writeFileSync(rustModel,fixture.rustConformanceIR);
  run(moon,['build','--target','js']);
  const invoke=(model: string,cases: string,target='js',mode='debug',extra: string[]=[],status=0)=>run(process.execPath,[cli,'conform',model,'--cases',cases,'--execution-helper',helper,'--home',target==='llvm'?llvmHome!:home,...(target==='llvm'?['--toolchain-pin',llvmPin!]:[]),...dependencies,'--target',target,'--build-mode',mode,...extra,'--json'],status);
  let baseline: ConformanceReport | undefined;
  for(const target of targets)for(const mode of ['debug','release']) {
    const receipt=join(receipts??root,target+'-'+mode+'.ionb');
    const report: ConformanceReport=JSON.parse(invoke(model,cases,target,mode,['--receipt',receipt,...rustOptions]).stdout);
    assert.equal(report.successful,true);
    assert.equal(report.execution.evidence.buildMode,mode);
    for(const name of ['independent','scheme']) {
      assert.equal(lane(report,name).calls.length,23);
      assert.ok(lane(report,name).calls.every(c=>c.status==='matched'&&c.matches===true));
    }
    const coverage=lane(report,'rust');
    assert.equal(coverage.calls.length,23);
    assert.ok(coverage.calls.every(c=>c.status===(rust?'unsupported':'unavailable')&&c.matches===null&&c.expected===null));
    const semantics=report.execution.calls.map(c=>c.actual);
    if(baseline)assert.deepEqual(semantics,baseline.execution.calls.map(c=>c.actual));else baseline=report;
    assert.deepEqual([...readFileSync(receipt).subarray(0,4)],[0xe0,1,0,0xea]);
    const row={target,mode,independent:'23 matched',scheme:'23 matched',rust:rust?'23 unsupported':'23 unavailable'};
    summary.targets.push(row);
    if(receipts)writeFileSync(join(receipts,target+'-'+mode+'.json'),JSON.stringify(report,null,2)+'\n');
  }
  const quiet: ConformanceReport=JSON.parse(invoke(model,cases,'js','debug',['--telemetry-adapter','none',...rustOptions]).stdout);
  const log=join(root,'observations.jsonl');
  const observed: ConformanceReport=JSON.parse(invoke(model,cases,'js','debug',['--log-file',log,'--log-format','json-lines',...rustOptions]).stdout);
  assert.deepEqual(quiet.coverage,observed.coverage);
  assert.deepEqual(quiet.execution.calls,observed.execution.calls);
  for(const field of ['sourceIdentity','driverIdentity','manifestIdentity','compilerIdentity','coreIdentity'] as const)assert.equal(quiet.execution.evidence[field],observed.execution.evidence[field]);
  assert.equal(quiet.execution.invocationEvidence.suiteIdentity,observed.execution.invocationEvidence.suiteIdentity);
  assert.ok(readFileSync(log,'utf8').trim().split('\n').map(line => JSON.parse(line)).length>0);
  const jsonCases=join(root,'cases.json'),jsonReceipt=join(root,'receipt.json');
  writeFileSync(jsonCases,JSON.stringify({profile:'morphir-conformance-v1',version:'json-optout-v1',provenance:'Direct literal 42, independently authored',cases:[{id:'literal',entry:'rust-conformance:main#answer',arguments:[],expected:{type:'int',value:'42'}}]}));
  const jsonReport: ConformanceReport=JSON.parse(invoke(rustModel,jsonCases,'js','debug',['--cases-format','json','--receipt',jsonReceipt,'--receipt-format','json']).stdout);
  assert.equal(jsonReport.successful,true);
  assert.deepEqual(JSON.parse(readFileSync(jsonReceipt,'utf8')),jsonReport);
  assert.equal(lane(jsonReport,'independent').calls[0]!.expected!.value,'42');
  const mutated=join(root,'wrong.ion');
  writeFileSync(mutated,readFileSync(cases,'utf8').replace('expected:18014398509481986','expected:18014398509481987'));
  const wrong: ConformanceReport=JSON.parse(invoke(model,mutated,'js','debug',[],1).stdout);
  assert.equal(wrong.successful,false);
  const disagreement=lane(wrong,'independent').calls.find(c=>c.id==='exact-add');
  assert.equal(disagreement!.status,'mismatch');assert.equal(disagreement!.mismatchPath,'');
  assert.ok(lane(wrong,'scheme').calls.every(c=>c.status==='matched'));
  writeFileSync(mutated,readFileSync(cases,'utf8').replace('coefficient:"425",exponent:-2}}]}}','coefficient:"426",exponent:-2}}]}}'));
  const nested: ConformanceReport=JSON.parse(invoke(model,mutated,'js','debug',[],1).stdout);
  assert.equal(lane(nested,'independent').calls.find(c=>c.id==='record-update')!.mismatchPath,'/price');
  const cancellation=join(root,'cancel');writeFileSync(cancellation,'cancel');
  const cancelled: ConformanceReport=JSON.parse(invoke(model,cases,'js','debug',['--cancel-file',cancellation],130).stdout);
  assert.equal(cancelled.successful,false);assert.equal(cancelled.cancelled,true);
  assert.ok(cancelled.execution.terminals.every(t=>t.status==='cancelled'));
  assert.ok(cancelled.coverage.every(l=>l.calls.every(c=>c.status==='cancelled')));
  const missing=invoke(rustModel,rustCases,'js','debug',['--require-evaluator','rust','--dry-run'],2);
  assert.match(missing.stderr,/evaluator_unavailable: rust/);
  assert.match(invoke(rustModel,rustCases,'js','debug',['--evaluators','scheme,scheme','--dry-run'],2).stderr,/evaluator_identity/);
  if(rust) {
    for(const mode of ['debug','release']) {
      const report: ConformanceReport=JSON.parse(invoke(rustModel,rustCases,'js',mode,[...rustOptions,'--require-evaluator','rust','--receipt',join(receipts??root,'rust-js-'+mode+'.ionb')]).stdout);
      assert.equal(report.successful,true);
      for(const name of ['independent','scheme','rust'])assert.ok(lane(report,name).calls.length===5&&lane(report,name).calls.every(c=>c.status==='matched'));
      assert.equal(lane(report,'rust').evidence.protocol,'1.1.0-draft.1');
      assert.equal(lane(report,'rust').evidence.conversion,'lossless-classic-v3-roundtrip');
      assert.equal(lane(report,'rust').calls.find(c=>c.id==='integer')!.expected!.value,'9007199254740993');
      summary.rust={status:'5 matched',scope:'sdk-free scalar literal and identity; JS debug/release',evidence:lane(report,'rust').evidence};
      if(receipts)writeFileSync(join(receipts,'rust-js-'+mode+'.json'),JSON.stringify(report,null,2)+'\n');
    }
    assert.match(invoke(model,cases,'js','debug',[...rustOptions,'--require-evaluator','rust','--dry-run'],2).stderr,/evaluator_unsupported: rust: exact-add/);
    const altered=join(root,'pin.json'),pin=JSON.parse(readFileSync(rustPin!,'utf8'));
    writeFileSync(altered,JSON.stringify({...pin,binaryIdentity:'0'.repeat(64)}));
    assert.match(invoke(rustModel,rustCases,'js','debug',['--rust-evaluator',rust,'--rust-evaluator-pin',altered,'--rust-helper',rustHelper,'--dry-run'],2).stderr,/rust_binary_identity/);
    writeFileSync(altered,JSON.stringify({...pin,protocol:'future'}));
    assert.match(invoke(rustModel,rustCases,'js','debug',['--rust-evaluator',rust,'--rust-evaluator-pin',altered,'--rust-helper',rustHelper,'--dry-run'],2).stderr,/rust_pin_profile/);
    for(const [source,replacement,reason] of [
      ['arguments:[9007199254740993]','arguments:[9223372036854775808]','rust_integer_range'],
      ['arguments:[morphir_value::{type:"text",units:[83,110,111,119,32,38634,32,55357,56832]}]','arguments:[morphir_value::{type:"text",units:[55296]}]','rust_unrepresentable_utf16'],
    ] as const) {
      writeFileSync(mutated,readFileSync(rustCases,'utf8').replace(source!,replacement!));
      assert.match(invoke(rustModel,mutated,'js','debug',[...rustOptions,'--require-evaluator','rust','--dry-run'],2).stderr,new RegExp(reason!));
    }
  }
  if(receipts)writeFileSync(join(receipts,'summary.json'),JSON.stringify(summary,null,2)+'\n');
  console.log('Independent conformance: '+targets.join(', ')+' debug/release; 23 independent + Scheme matches per lane. Rust: '+summary.rust.status+'. Disagreement and required-coverage gates passed.');
} finally {rmSync(root,{recursive:true,force:true});}
