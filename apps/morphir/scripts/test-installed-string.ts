import type { InstalledContext, ConformanceReport, PipelineReport } from '../../../tests/cli-contracts.ts';
import assert from 'node:assert/strict';
import {mkdirSync,writeFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {join,delimiter} from 'node:path';
import {capabilities} from '../build-provider/capabilities.mts';
import {hash} from '../build-provider/identity.mts';

const profile='moonbit-model-stable-v1';
const corePin='0.10.16+b1a0e846e+tree:1886b2f93eff7365ccdbaed2c13abd33858841f8';

// Every advertised stable String type, operator and SDK call appears in one library.
const source=`/// Installed String qualification library. λ😀
pub fn greet(name : String) -> String { prefix() + name }
fn prefix() -> String { "Hello, " }
pub fn welcome(name : String, enabled : Bool) -> String { let greeting : String = greet(name); if enabled { greeting } else { "" } }
pub fn same(a : String, b : String) -> Bool { a == b }
pub fn differ(a : String, b : String) -> Bool { a != b }
pub fn before(a : String, b : String) -> Bool { a < b }
pub fn at_most(a : String, b : String) -> Bool { a <= b }
pub fn after(a : String, b : String) -> Bool { a > b }
pub fn at_least(a : String, b : String) -> Bool { a >= b }
pub fn count(s : String) -> Int32 { s.length() }
pub fn cut(s : String, start : Int32, end : Int32) -> String { s[start:end].to_owned() }
pub fn empty(s : String) -> Bool { s.is_empty() }
pub fn has(s : String, needle : String) -> Bool { s.contains(needle) }
pub fn starts(s : String, head : String) -> Bool { s.has_prefix(head) }
pub fn ends(s : String, tail : String) -> Bool { s.has_suffix(tail) }
pub fn grows(s : String) -> Bool { let a : String = s + s; let b : String = a + a; let c : String = b + b; let d : String = c + c; let e : String = d + d; let f : String = e + e; let g : String = f + f; let h : String = g + g; let i : String = h + h; let j : String = i + i; let k : String = j + j; k.is_empty() }
`;

type Arg = string | number | boolean | { units: number[] };
interface Row { id: string; fn: string; args: Arg[]; expected: Arg | { error: string } }

const units=(text: string)=>Array.from({length:text.length},(_,i)=>text.charCodeAt(i));
const ion=(value: Arg | { error: string }): string => {
  if(typeof value==='boolean')return String(value);
  if(typeof value==='string')return `morphir_value::{type:"text",units:[${units(value).join(',')}]}`;
  if(typeof value==='number')return `morphir_value::{type:"custom",owner:"morphir/SDK:int#int-32",tag:"morphir/SDK:int#int32",items:[{type:"int",value:"${value}"}]}`;
  if('error' in value)return `morphir_value::{type:"model-error",code:"${value.error}"}`;
  return `morphir_value::{type:"text",units:[${value.units.join(',')}]}`;
};
const moonbit=(value: Arg)=>typeof value==='string'?JSON.stringify(value):String(value);

// Hand-authored from the approved String semantics; the original compiler checks every value row.
const rows: Row[]=[
  {id:'greet-ascii',fn:'greet',args:['Morphir'],expected:'Hello, Morphir'},
  {id:'greet-supplementary',fn:'greet',args:['😀'],expected:'Hello, 😀'},
  {id:'greet-empty',fn:'greet',args:[''],expected:'Hello, '},
  {id:'welcome-combining',fn:'welcome',args:['é',true],expected:'Hello, é'},
  {id:'welcome-disabled',fn:'welcome',args:['x',false],expected:''},
  {id:'same-unnormalized',fn:'same',args:['é','é'],expected:false},
  {id:'same-supplementary',fn:'same',args:['😀','😀'],expected:true},
  {id:'differ',fn:'differ',args:['a','b'],expected:true},
  {id:'before-shortlex',fn:'before',args:['b','aa'],expected:true},
  {id:'before-utf16',fn:'before',args:['😀','a'],expected:true},
  {id:'at-most-empty',fn:'at_most',args:['',''],expected:true},
  {id:'after-shortlex',fn:'after',args:['aa','b'],expected:true},
  {id:'at-least-length',fn:'at_least',args:['😀',''],expected:true},
  {id:'count-utf16',fn:'count',args:['A😀é'],expected:5},
  {id:'count-empty',fn:'count',args:[''],expected:0},
  {id:'cut-pair',fn:'cut',args:['A😀é',1,3],expected:'😀'},
  {id:'cut-split-pair',fn:'cut',args:['A😀é',1,2],expected:''},
  {id:'cut-negative',fn:'cut',args:['A😀é',-100,2],expected:'A'},
  {id:'cut-combining',fn:'cut',args:['A😀é',3,99],expected:'é'},
  {id:'cut-int32-extremes',fn:'cut',args:['A😀é',-2147483648,2147483647],expected:'A😀é'},
  {id:'cut-reversed',fn:'cut',args:['A😀é',2147483647,-2147483648],expected:''},
  {id:'empty-true',fn:'empty',args:[''],expected:true},
  {id:'empty-combining',fn:'empty',args:['́'],expected:false},
  {id:'has-supplementary',fn:'has',args:['a😀b','😀'],expected:true},
  {id:'has-shared-high-surrogate',fn:'has',args:['😀','😁'],expected:false},
  {id:'has-empty-needle',fn:'has',args:['abc',''],expected:true},
  {id:'has-in-empty',fn:'has',args:['','a'],expected:false},
  {id:'starts-unnormalized',fn:'starts',args:['é','e'],expected:false},
  {id:'starts-combining',fn:'starts',args:['é','e'],expected:true},
  {id:'ends-supplementary',fn:'ends',args:['a😀','😀'],expected:true},
  {id:'ends-empty',fn:'ends',args:['',''],expected:true},
  {id:'ends-longer',fn:'ends',args:['abc','abcd'],expected:false},
  {id:'grows-empty',fn:'grows',args:[''],expected:true},
  {id:'grows-within-bound',fn:'grows',args:['a'],expected:false},
  // Source Strings cannot spell these inputs, so only the installed and Scheme lanes check them.
  {id:'has-lone-high',fn:'has',args:[{units:[55357]},''],expected:{error:'sdk.unrepresentable_text'}},
  {id:'empty-lone-low',fn:'empty',args:[{units:[56832]}],expected:{error:'sdk.unrepresentable_text'}},
  {id:'count-reversed-pair',fn:'count',args:[{units:[56832,55357]}],expected:{error:'sdk.unrepresentable_text'}},
  {id:'starts-truncated-pair',fn:'starts',args:['a',{units:[55357,97]}],expected:{error:'sdk.unrepresentable_text'}},
  {id:'grows-over-bound',fn:'grows',args:['a'.repeat(600)],expected:{error:'sdk.out_of_range'}},
];

// Called by the installed lifecycle gate, using its packed CLI and shipped helper.
export function testInstalledString({run,root,receipts,cli,helper,cwd,home,llvmHome,llvmPin,required,deps,pack}: InstalledContext) {
  const output=join(receipts,'moonbit-string');mkdirSync(output,{recursive:true});
  rmSync(join(output,'summary.json'),{force:true});
  const project=join(root,'string-project');mkdirSync(join(project,'src'),{recursive:true});
  const manifest='[project]\nname="StringQualification"\nmodule_prefix="App"\n[frontend]\nlanguage="moonbit"\nprofile="'+profile+'"\n[pipeline]\nbackend="checkpoint"\n';
  writeFileSync(join(project,'morphir.toml'),manifest);
  const sourcePath=join(project,'src/Main.mbt');writeFileSync(sourcePath,source);
  writeFileSync(join(output,'Main.mbt'),source);writeFileSync(join(output,'morphir.toml'),manifest);
  const call=(args: string[],status=0)=>run(process.execPath,[cli,...args],{cwd,status});
  const sourceCall=(args: string[],status=0)=>run(process.execPath,[cli,...args],{cwd:project,status});
  const compileDir=join(project,'.morphir/out/compile.dest');

  const plan: PipelineReport=JSON.parse(sourceCall(['run','.','--dry-run','--json']).stdout);
  const descriptor=plan.frontends[0]!;
  assert.equal(descriptor.profile,profile);assert.equal(descriptor.defaultProfile,true);
  assert.equal(descriptor.dependencies['moonbitlang/core/builtin'],corePin);
  const supported=descriptor.capabilities.supported??[];
  assert.ok(supported.some(s=>s.includes('is_empty, contains, has_prefix and has_suffix')),'Stable advertises the String predicates');
  assert.ok(!existsSync(compileDir),'Dry-run must not publish');

  const compiled: PipelineReport=JSON.parse(sourceCall(['run','.','--json']).stdout);
  assert.equal(compiled.successful,true);
  const checkpoint=join(output,'Main.ionb');
  const bytes=readFileSync(join(compileDir,'Main.ionb'));
  assert.deepEqual([...bytes.subarray(0,4)],[224,1,0,234]);writeFileSync(checkpoint,bytes);

  // Ion text carries the same source facts; checked Morphir JSON refuses to drop them.
  assert.equal(JSON.parse(sourceCall(['run','.','--checkpoint-format','ion-text','--json']).stdout).successful,true);
  const text=readFileSync(join(compileDir,'Main.ion'),'utf8');
  for(const token of [profile,'well-formed-utf16','utf16-shortlex','moonbit-source-string-index-v1','moonbit-source-binding-v1','String::contains','String::has_prefix','String::has_suffix','String::is_empty','string-method','pinned-implicit-string-to-stringview','1886b2f93eff7365ccdbaed2c13abd33858841f8','Installed String qualification library.'])assert.ok(text.includes(token),token);
  const textCheckpoint=join(output,'Main.ion');writeFileSync(textCheckpoint,text);
  // A future fact beside the frontend provenance must not prevent replay.
  const future=join(output,'Main-future.ion');
  const extended=text.replace('language: "moonbit"','language: "moonbit", future_fact: "retain-me"');
  assert.notEqual(extended,text,'Provenance language field present');
  writeFileSync(future,extended);
  const lossy: PipelineReport=JSON.parse(sourceCall(['run','.','--checkpoint-format','morphir-json','--json'],1).stdout);
  assert.match(lossy.diagnostics[0]!.message,/data.lossy_conversion/);assert.deepEqual(lossy.committed,[]);
  writeFileSync(join(output,'lossy-json.json'),JSON.stringify(lossy,null,2)+'\n');

  const generated: PipelineReport=JSON.parse(sourceCall(['run','.','--backend','moonbit','--validation','source-only','--json']).stdout);
  assert.equal(generated.successful,true);
  const library=readFileSync(join(compileDir,'Main/library.mbt'),'utf8');
  for(const token of ['@string.is_empty(','@string.contains(','@string.starts_with(','@string.ends_with(','@source_string.require_valid','@source_string.slice_owned','/// Installed String qualification library.'])assert.ok(library.includes(token),token);
  assert.equal((library.match(/^pub fn/gm)||[]).length,15,'Fifteen public wrappers');assert.equal((library.match(/^fn /gm)||[]).length,1,'One private helper');
  const symbols=readFileSync(join(compileDir,'Main/symbols.10n'));
  assert.deepEqual([...symbols.subarray(0,4)],[224,1,0,234]);
  writeFileSync(join(output,'library.mbt'),library);writeFileSync(join(output,'symbols.10n'),symbols);

  // Refusals keep the published checkpoint, which republishes byte for byte.
  assert.equal(JSON.parse(sourceCall(['run','.','--json']).stdout).successful,true);
  assert.deepEqual(readFileSync(join(compileDir,'Main.ionb')),bytes);
  const refusals: Record<string,string>={};
  for(const [id,body,code] of [
    ['case-conversion','pub fn f(s : String) -> String { s.to_upper() }','moonbit_frontend.unsupported_method'],
    ['deprecated-alias','pub fn f(s : String, p : String) -> Bool { s.starts_with(p) }','moonbit_frontend.unsupported_method'],
    ['wrong-signature','pub fn f(s : String) -> Bool { s.contains(1) }','moonbit_frontend.type_mismatch'],
    ['qualified-spelling','pub fn f(s : String, p : String) -> Bool { @string.contains(p, s) }','moonbit_frontend.unknown_binding'],
    ['unpromoted-type','pub fn f(s : String) -> Double { 1.0 }','moonbit_frontend.experimental_capability'],
  ] as const) {
    writeFileSync(sourcePath,body);
    const failure: PipelineReport=JSON.parse(sourceCall(['run','.','--json'],1).stdout);
    assert.equal(failure.successful,false);
    assert.match(failure.diagnostics[0]!.message,new RegExp('^'+code.replace('.','\\.')+':.*provider finos/morphir-moonbit-frontend; profile '+profile));
    assert.deepEqual(readFileSync(join(compileDir,'Main.ionb')),bytes);
    refusals[id]=code;
  }
  writeFileSync(sourcePath,source);

  const entry=(name: string)=>'string-qualification:app/main#'+name.replaceAll('_','-');
  const cases=join(output,'cases.ion');
  writeFileSync(cases,'{profile:"morphir-conformance-v1",version:"moonbit-string-installed-1",provenance:"Hand-authored stable String rows; value rows checked independently by the original compiler",cases:['+rows.map(r=>`{id:"${r.id}",entry:"${entry(r.fn)}",arguments:[${r.args.map(ion).join(',')}],expected:${ion(r.expected)}}`).join(',')+']}');
  const valueRows=rows.filter(r=>r.args.every(a=>typeof a!=='object')&&!(typeof r.expected==='object'));
  const original=join(root,'original-string');mkdirSync(original,{recursive:true});
  writeFileSync(join(original,'moon.mod'),'name="acceptance/original-string"\nversion="0.0.0"\n');
  writeFileSync(join(original,'moon.pkg'),'');writeFileSync(join(original,'Main.mbt'),source);
  writeFileSync(join(original,'original_test.mbt'),valueRows.map(r=>`///|\ntest "original ${r.id}" { assert_eq(${r.fn}(${r.args.map(a=>moonbit(a as string|number|boolean)).join(', ')}), ${moonbit(r.expected as string|number|boolean)}) }\n`).join('\n'));

  const verify=(model: string,target: string,mode: string,extra: string[]=[],status=0,suite=cases)=>call(['conform',model,'--unit-id','Main','--cases',suite,'--execution-helper',helper,'--home',target==='llvm'?llvmHome!:home,...(target==='llvm'?['--toolchain-pin',llvmPin!]:[]),...deps,'--target',target,'--build-mode',mode,...extra],status);
  const lanes=[];let baseline: ConformanceReport | undefined;
  for(const target of required)for(const mode of ['debug','release']) {
    const id=target+'-'+mode,compilerHome=target==='llvm'?llvmHome!:home;
    const toolchainPin=target==='llvm'?JSON.parse(readFileSync(llvmPin!,'utf8')):undefined;
    const capability=capabilities({compilerHome,toolchainPin,timeout:10000});
    assert.ok(capability.targets.some(t=>t.target===target),'Required original compiler lane unavailable: '+target);
    const env: NodeJS.ProcessEnv={...process.env,MOON_HOME:compilerHome,MOONBIT_NEW_NATIVE:'0',PATH:join(compilerHome,'bin')+delimiter+process.env.PATH};delete env.MOON_WORK;
    const oracle=run(join(compilerHome,'bin/moon'),['test','--frozen','--target',target,...(mode==='release'?['--release']:[])],{cwd:original,env});
    assert.match(oracle.stdout,new RegExp(`Total tests: ${valueRows.length}, passed: ${valueRows.length}, failed: 0`));
    writeFileSync(join(output,id+'-original.log'),oracle.stdout+'\n'+oracle.stderr);
    const receipt=join(output,id+'-receipt.ionb');
    const report: ConformanceReport=JSON.parse(verify(checkpoint,target,mode,['--receipt',receipt,'--json']).stdout);
    assert.equal(report.successful,true);assert.equal(report.execution.calls.length,rows.length);
    assert.equal(report.execution.evidence.buildMode,mode);assert.equal(report.execution.target,target);
    for(const provider of ['independent','scheme']) {
      const coverage=report.coverage.find(l=>l.provider===provider);assert.ok(coverage,provider);
      assert.equal(coverage.calls.length,rows.length);assert.ok(coverage.calls.every(c=>c.status==='matched'),provider+' '+id);
    }
    assert.ok(!existsSync(report.execution.evidence.executable!),'Execution lease disposed');
    assert.deepEqual([...readFileSync(receipt).subarray(0,4)],[224,1,0,234]);
    if(baseline)assert.deepEqual(report.execution.calls.map(c=>c.actual),baseline.execution.calls.map(c=>c.actual));else baseline=report;
    writeFileSync(join(output,id+'.json'),JSON.stringify(report,null,2)+'\n');
    lanes.push({target,mode,rows:rows.length,originalRows:valueRows.length,compilerIdentity:capability.compilerIdentity,coreIdentity:capability.coreIdentity,evidence:report.execution.evidence});
    console.log('Installed MoonBit String '+id+': '+rows.length+' independent/Scheme/generated rows and '+valueRows.length+' original rows passed');
  }
  assert.ok(baseline,'At least one required lane');
  const pairedTarget=required[0]!;
  // Ion text and an unknown future fact replay to the same generated results.
  for(const model of [textCheckpoint,future]) {
    const replay: ConformanceReport=JSON.parse(verify(model,pairedTarget,'debug',['--json']).stdout);
    assert.equal(replay.successful,true);
    assert.deepEqual(replay.execution.calls.map(c=>c.actual),baseline.execution.calls.map(c=>c.actual));
  }
  const privateCases=join(root,'string-private.ion');
  writeFileSync(privateCases,`{profile:"morphir-conformance-v1",version:"moonbit-string-private-1",provenance:"Private helper",cases:[{id:"private",entry:"${entry('prefix')}",arguments:[],expected:${ion('Hello, ')}}]}`);
  const privateFailure=verify(checkpoint,pairedTarget,'debug',['--json'],2,privateCases);
  assert.match(privateFailure.stderr,/entry_not_public_or_supported/);
  const cancellation=join(root,'string-cancel');writeFileSync(cancellation,'cancel');
  const cancelled: ConformanceReport=JSON.parse(verify(checkpoint,pairedTarget,'debug',['--cancel-file',cancellation,'--json'],130).stdout);
  assert.equal(cancelled.successful,false);assert.equal(cancelled.cancelled,true);
  assert.ok(cancelled.coverage.every(l=>l.calls.every(c=>c.status==='cancelled')));
  rmSync(cancellation);
  const bad=join(root,'string-wrong.ion');writeFileSync(bad,readFileSync(cases,'utf8').replace(`{id:"has-supplementary",entry:"${entry('has')}",arguments:[${ion('a😀b')},${ion('😀')}],expected:true}`,`{id:"has-supplementary",entry:"${entry('has')}",arguments:[${ion('a😀b')},${ion('😀')}],expected:false}`));
  const mismatch: ConformanceReport=JSON.parse(verify(checkpoint,pairedTarget,'debug',['--json'],1,bad).stdout);
  assert.equal(mismatch.successful,false);
  assert.equal(mismatch.coverage.find(l=>l.provider==='independent')!.calls.find(c=>c.id==='has-supplementary')!.status,'mismatch');
  const summary={
    profile:'morphir-installed-string-v1',package:pack.integrity,node:process.version,platform:process.platform,arch:process.arch,
    frontend:{profile,provider:descriptor.provider,dependencies:descriptor.dependencies},
    sourceIdentity:hash(source),manifestIdentity:hash(manifest),checkpointIdentity:hash(bytes),symbolsIdentity:hash(symbols),
    requiredTargets:required,lanes,rows:rows.length,originalRows:valueRows.length,
    coverage:{
      types:['String','Bool','Int32'],
      operators:['+','==','!=','<','<=','>','>='],
      calls:['String::length','String[start:end].to_owned','String::is_empty','String::contains','String::has_prefix','String::has_suffix'],
      boundaries:['empty','supplementary','combining','split-surrogate','negative-index','int32-extremes','malformed-utf16','size-bound'],
    },
    refusals,ionText:true,unknownFactReplay:true,lossyJsonRefused:true,privateEntryRefused:true,cancelled:true,mismatchRejected:true,
    unverified:['wasm (non-GC) is not offered by the installed execution helper; local typed-source lanes cover it'],
  };
  writeFileSync(join(output,'summary.json'),JSON.stringify(summary,null,2)+'\n');
  console.log('Installed MoonBit String: '+required.join(', ')+' debug/release; '+rows.length+' rows, '+valueRows.length+' original rows, refusals, Ion replay, cancellation and privacy passed.');
  return summary;
}
