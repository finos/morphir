import assert from 'node:assert/strict';
import {cpSync,existsSync,mkdirSync,readFileSync,readdirSync,rmSync,writeFileSync} from 'node:fs';
import {delimiter,join} from 'node:path';
import type {InstalledContext,ConformanceReport,VerificationReport,PipelineReport} from '../../../tests/cli-contracts.ts';
import {capabilities} from '../build-provider/capabilities.mts';
import {hash,treeIdentity} from '../build-provider/identity.mts';
import {fullCorpus,numericSourceProfile,integer,decimal,type NumericModel,type NumericValue,type TypedNumericModel} from './numeric-corpus.ts';
import {emitNumericConsumer,numericAliases,type NumericSymbol} from './numeric-consumer.ts';
import {assertNumericReference} from './numeric-reference.ts';
import {loadNumericBridge} from './numeric-bridge.ts';

export interface NumericEncoded { source: string; bytes: number[]; }
export interface NumericNativeReceipt {
  successful: boolean; execution: {id:string;actual:NumericValue;expected:NumericValue}[];
  coverage:{provider:string;calls:{id:string;actual:NumericValue;expected:NumericValue}[]}[]; roundtrip: NumericEncoded;
}
export interface NumericInspection {
  source:string;bytes:number[];metadata:{owner:string;source:string}[];jsonProjection:{accepted:boolean;code?:string};
}
export interface NumericBridge {
  inspect(bytes: Uint8Array): NumericInspection;
  augment(bytes: Uint8Array): NumericInspection;
  symbols(bytes: Uint8Array): {symbols:NumericSymbol[]};
  scheme(bytes: Uint8Array,suite: unknown): {values:NumericValue[]};
  cases(rows: unknown[]): NumericEncoded;
  conformance(bytes: Uint8Array): NumericNativeReceipt;
}

const stable='moonbit-model-stable-v1';
const sdkImports: Record<string,string>={
  math:'import { "finos/morphir-sdk/basics" @basics }\n',
  conversions:'import {\n  "finos/morphir-sdk" @sdk,\n  "finos/morphir-sdk/basics" @basics,\n  "finos/morphir-sdk/int" @int,\n  "finos/morphir-sdk/integer" @integer,\n}\n',
  decimal:'import { "finos/morphir-sdk/decimal" @decimal }\n',
};

interface Prepared {
  model: NumericModel; project: string; evidence: string; checkpoint: Buffer; checkpointFile: string;
  textFile: string; symbols: NumericSymbol[]; symbolsBytes: Buffer; generated: string; generatedTree: string;
  entry: (name: string) => string; exactCases?: string; approximate?: string; jsonProjection: {accepted:boolean;code?:string};
}

/**
 * Qualify every offered experimental numeric source entry through the packed npm CLI.
 * Authored rows are checked against Scheme, the independent evaluator, generated
 * execution on each required installed lane, and original and installed-generated
 * consumers compiled by the pinned MoonBit compiler.
 */
export async function testInstalledNumeric({run,root,receipts,cli,helper,home,llvmHome,llvmPin,required,deps,pack,repo}: InstalledContext) {
  assert.ok(repo,'Repository root required for numeric fixtures');
  const output=join(receipts,'moonbit-numeric');rmSync(output,{recursive:true,force:true});mkdirSync(output,{recursive:true});
  // The comparison policy is itself tested before it judges any observation.
  run(process.execPath,['--test',join(repo,'apps/morphir/scripts/numeric-reference.test.ts')],{cwd:repo});
  const moon=join(home,'bin/moon');
  const fixtures: {models: TypedNumericModel[]}=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-moonbit-frontend/typed-acceptance'],{cwd:repo}).stdout);
  const models=fullCorpus(fixtures);
  run(moon,['build','--target','js','pkgs/morphir-engine/acceptance/numeric-qualification'],{cwd:repo});
  const bridge=await loadNumericBridge(repo);
  // A private working directory keeps default execution logs apart from other gates.
  const cwd=join(root,'numeric-cwd');mkdirSync(cwd,{recursive:true});
  const call=(args: string[],status=0,where=cwd)=>run(process.execPath,[cli,...args],{cwd:where,status});
  const provider=(target: string,mode: string)=>['--execution-helper',helper,'--home',target==='llvm'?llvmHome!:home,...(target==='llvm'?['--toolchain-pin',llvmPin!]:[]),...deps,'--target',target,'--build-mode',mode];
  const manifest=(id: string,profile: string=numericSourceProfile)=>'[project]\nname="Numeric'+id+'"\nmodule_prefix="App"\n[frontend]\nlanguage="moonbit"\nprofile="'+profile+'"\n[pipeline]\nbackend="checkpoint"\n';

  const prepared: Prepared[]=[];
  for(const model of models) {
    const project=join(root,'numeric',model.id);mkdirSync(join(project,'src'),{recursive:true});
    const evidence=join(output,model.id);mkdirSync(evidence,{recursive:true});
    writeFileSync(join(project,'morphir.toml'),manifest(model.id));writeFileSync(join(project,'src/Main.mbt'),model.source);
    writeFileSync(join(evidence,'Main.mbt'),model.source);
    const sourceCall=(args: string[],status=0)=>call(args,status,project);
    const compileDir=join(project,'.morphir/out/compile.dest');
    const plan: PipelineReport=JSON.parse(sourceCall(['run','.','--dry-run','--json']).stdout);
    const descriptor=plan.frontends[0]!;
    assert.equal(descriptor.profile,numericSourceProfile);assert.equal(descriptor.defaultProfile,false,'Numeric capabilities stay experimental');
    assert.ok(descriptor.availableProfiles.includes(stable));
    assert.ok(!existsSync(compileDir),'Dry-run must not publish');

    const compiled: PipelineReport=JSON.parse(sourceCall(['run','.','--json']).stdout);
    assert.equal(compiled.successful,true);assert.equal(compiled.processed,1);assert.deepEqual(compiled.warnings,[]);
    assert.ok(!existsSync(join(project,'.morphir/logs')),'Default numeric compilation creates no logs');
    const checkpoint=readFileSync(join(compileDir,'Main.ionb'));
    assert.deepEqual([...checkpoint.subarray(0,4)],[224,1,0,234]);
    const checkpointFile=join(evidence,'Main.ionb');writeFileSync(checkpointFile,checkpoint);
    // Production codecs decode the primary checkpoint and keep its owned source facts.
    const inspected=bridge.inspect(checkpoint);
    assert.ok(inspected.metadata.length,'Numeric source facts must remain owned');
    assert.ok(inspected.source.includes(numericSourceProfile));

    assert.equal(JSON.parse(sourceCall(['run','.','--checkpoint-format','ion-text','--json']).stdout).successful,true);
    const text=readFileSync(join(compileDir,'Main.ion'),'utf8');
    assert.ok(text.includes(numericSourceProfile));
    const textFile=join(evidence,'Main.ion');writeFileSync(textFile,text);
    // Checked Morphir JSON keeps exact numeric observations or refuses the loss.
    const json: PipelineReport=JSON.parse(sourceCall(['run','.','--checkpoint-format','morphir-json','--json'],inspected.jsonProjection.accepted?0:1).stdout);
    if(inspected.jsonProjection.accepted)assert.equal(json.successful,true);
    else {
      assert.match(json.diagnostics[0]!.message,/data\.lossy_conversion/);assert.deepEqual(json.committed,[]);
      assert.equal(inspected.jsonProjection.code,'data.lossy_conversion');
    }
    writeFileSync(join(evidence,'morphir-json.json'),JSON.stringify(json,null,2)+'\n');

    const generation: PipelineReport=JSON.parse(sourceCall(['run','.','--backend','moonbit','--validation','source-only','--json']).stdout);
    assert.equal(generation.successful,true);
    const generated=join(compileDir,'Main');
    const symbolsBytes=readFileSync(join(generated,'symbols.10n'));
    assert.deepEqual([...symbolsBytes.subarray(0,4)],[224,1,0,234]);
    const symbols=bridge.symbols(symbolsBytes).symbols;
    // Wrapper ABI: one generated public wrapper per public source entry; helpers stay private.
    const publicSymbols=symbols.filter(s=>s.public);
    assert.deepEqual(new Set(publicSymbols.map(s=>s.fqname.split('#')[1]!)),new Set(model.entries));
    assert.equal(publicSymbols.length,model.entries.length);
    const library=readFileSync(join(generated,'library.mbt'),'utf8');
    for(const symbol of symbols)assert.match(library,new RegExp('^'+(symbol.public?'pub ':'')+'fn '+symbol.function+'\\b','m'),symbol.fqname);
    writeFileSync(join(evidence,'library.mbt'),library);writeFileSync(join(evidence,'symbols.10n'),symbolsBytes);
    const entry=(name: string)=>{
      const selected=publicSymbols.filter(s=>s.fqname.endsWith('#'+name));
      assert.equal(selected.length,1,'Exact public installed symbol required: '+name);return selected[0]!.fqname;
    };

    // Scheme evaluates the installed checkpoint for every row, including approximate math.
    const suite={profile:'morphir-invocations-v1',calls:model.rows.map(row=>({id:row.id,entry:entry(row.name),arguments:row.arguments.map(arg=>arg.value)}))};
    const scheme=bridge.scheme(checkpoint,suite).values;
    assert.equal(scheme.length,model.rows.length);
    scheme.forEach((value,i)=>assertNumericReference(value,model.rows[i]!.reference,model.id+' Scheme '+model.rows[i]!.id));
    const exact=model.rows.filter(row=>row.reference.kind==='exact');
    let exactCases: string | undefined;
    if(exact.length) {
      const cases=bridge.cases(exact.map(row=>{
        assert.ok(row.reference.kind==='exact');return {id:row.id,entry:entry(row.name),arguments:row.arguments.map(arg=>arg.value),expected:row.reference.expected};
      }));
      exactCases=join(evidence,'cases.ionb');writeFileSync(exactCases,Buffer.from(cases.bytes));writeFileSync(join(evidence,'cases.ion'),cases.source);
    }
    const approximateRows=suite.calls.filter((_,i)=>model.rows[i]!.reference.kind!=='exact');
    let approximate: string | undefined;
    if(approximateRows.length) {
      approximate=join(evidence,'categories-and-ulp.json');
      writeFileSync(approximate,JSON.stringify({profile:'morphir-invocations-v1',calls:approximateRows}));
    }
    prepared.push({model,project,evidence,checkpoint,checkpointFile,textFile,symbols,symbolsBytes,generated,generatedTree:treeIdentity(generated),entry,exactCases,approximate,jsonProjection:inspected.jsonProjection});
  }

  const lanes=[];
  const baseline=new Map<string,NumericValue>();
  for(const target of required)for(const mode of ['debug','release']) {
    const lane=target+'-'+mode,compilerHome=target==='llvm'?llvmHome!:home;
    const toolchainPin=target==='llvm'?JSON.parse(readFileSync(llvmPin!,'utf8')):undefined;
    const capability=capabilities({compilerHome,toolchainPin,timeout:10000});
    assert.ok(capability.targets.some(t=>t.target===target),'Required installed lane unavailable: '+target);
    let laneRows=0;
    for(const item of prepared) {
      const {model}=item;
      const actual=new Map<string,NumericValue>();
      if(item.exactCases) {
        const receipt=join(item.evidence,lane+'-receipt.ionb');
        const report: ConformanceReport=JSON.parse(call(['conform',item.checkpointFile,'--unit-id','Main','--cases',item.exactCases,...provider(target,mode),'--receipt',receipt,'--json']).stdout);
        const exact=model.rows.filter(row=>row.reference.kind==='exact').length;
        assert.equal(report.successful,true,model.id+' '+lane);assert.equal(report.execution.calls.length,exact);
        assert.equal(report.execution.target,target);assert.equal(report.execution.evidence.buildMode,mode);
        assert.ok(report.execution.terminals.every(t=>t.status==='succeeded'));
        for(const evaluator of ['independent','scheme']) {
          const coverage=report.coverage.find(l=>l.provider===evaluator);assert.ok(coverage,evaluator);
          assert.equal(coverage.calls.length,exact);assert.ok(coverage.calls.every(c=>c.status==='matched'),evaluator+' '+model.id+' '+lane);
        }
        assert.ok(!existsSync(report.execution.evidence.executable!),'Execution lease disposed');
        // Numeric programs need no host import beyond the execution protocol itself.
        assert.ok(report.execution.evidence.capability!.requiredImports.every(i=>i==='morphir_execution_v1'),'No implicit host grant');
        // Decode the primary Ion receipt; every execution and coverage call must equal the JSON view exactly.
        const native=bridge.conformance(readFileSync(receipt));
        assert.equal(native.successful,true);
        const triples=(calls: {id:string;actual:unknown;expected:unknown}[])=>calls.map(c=>({id:c.id,actual:c.actual,expected:c.expected}));
        assert.deepEqual(triples(native.execution),triples(report.execution.calls));
        assert.deepEqual(native.coverage.map(l=>({provider:l.provider,calls:triples(l.calls)})),report.coverage.map(l=>({provider:l.provider,calls:triples(l.calls)})));
        for(const c of native.execution) { assert.ok(!actual.has(c.id));actual.set(c.id,c.actual); }
        writeFileSync(join(item.evidence,lane+'-receipt.ion'),native.roundtrip.source);
        writeFileSync(join(item.evidence,lane+'.json'),JSON.stringify(report,null,2)+'\n');
      }
      if(item.approximate) {
        const execution: VerificationReport=JSON.parse(call(['execute',item.checkpointFile,'--unit-id','Main','--suite',item.approximate,...provider(target,mode),'--json']).stdout);
        assert.equal(execution.successful,true);assert.equal(execution.target,target);assert.equal(execution.evidence.buildMode,mode);
        assert.ok(execution.terminals.every(t=>t.status==='succeeded'));assert.ok(!existsSync(execution.evidence.executable!));
        for(const c of execution.calls) { assert.ok(!actual.has(c.id));actual.set(c.id,c.actual as NumericValue); }
        writeFileSync(join(item.evidence,lane+'-approximate.json'),JSON.stringify(execution,null,2)+'\n');
      }
      assert.deepEqual(new Set(actual.keys()),new Set(model.rows.map(row=>row.id)),'Every offered row executes exactly once: '+model.id);
      for(const row of model.rows) {
        const observed=actual.get(row.id)!;
        assertNumericReference(observed,row.reference,model.id+' '+lane+' '+row.id);
        // Exact rows produce the same native value on every lane.
        if(row.reference.kind==='exact') {
          const key=model.id+'/'+row.id,first=baseline.get(key);
          if(first)assert.deepEqual(observed,first,key+' '+lane);else baseline.set(key,observed);
        }
      }
      laneRows+=model.rows.length;
    }
    lanes.push({target,mode,rows:laneRows,compilerIdentity:capability.compilerIdentity,coreIdentity:capability.coreIdentity});
    console.log('Installed MoonBit numeric '+lane+': '+laneRows+' independent/Scheme/generated rows passed');
  }

  // Original source and installed-generated wrappers compile in one consumer on all four MoonBit targets.
  const workspace=join(root,'numeric-consumer');mkdirSync(workspace,{recursive:true});
  const members=[join(repo,'pkgs/morphir-sdk'),join(repo,'pkgs/morphir-execution'),'./consumer'];
  const imports=['"finos/morphir-sdk@0.1.0"','"finos/morphir-execution@0.1.0"'];
  const aliases=['"finos/morphir-sdk" @sdk','"finos/morphir-sdk/int" @int','"finos/morphir-sdk/integer" @integer','"finos/morphir-sdk/decimal" @decimal'];
  for(const item of prepared) {
    const id=item.model.id,alias=numericAliases(id);
    const original=join(workspace,'original-'+id),generated=join(workspace,'generated-'+id);
    mkdirSync(original,{recursive:true});
    writeFileSync(join(original,'moon.mod'),'name = "acceptance/'+id+'"\nversion = "0.0.0"\n'+(sdkImports[id]?'import { "finos/morphir-sdk@0.1.0" }\n':''));
    writeFileSync(join(original,'moon.pkg'),sdkImports[id]??'');writeFileSync(join(original,'original.mbt'),item.model.source);
    cpSync(item.generated,generated,{recursive:true});
    const module=readFileSync(join(generated,'moon.mod'),'utf8').match(/name\s*=\s*"([^"]+)"/)![1]!.replace(/[^/]+$/,'numeric-'+id);
    writeFileSync(join(generated,'moon.mod'),readFileSync(join(generated,'moon.mod'),'utf8').replace(/name\s*=\s*"[^"]+"/,'name = "'+module+'"'));
    members.push('./original-'+id,'./generated-'+id);
    imports.push(JSON.stringify('acceptance/'+id+'@0.0.0'),JSON.stringify(module+'@0.0.0'));
    aliases.push(JSON.stringify('acceptance/'+id)+' @'+alias.original,JSON.stringify(module)+' @'+alias.generated);
  }
  const consumer=join(workspace,'consumer');mkdirSync(consumer,{recursive:true});
  writeFileSync(join(workspace,'moon.work'),'members = ['+members.map(m=>JSON.stringify(m)).join(',')+']\n');
  writeFileSync(join(consumer,'moon.mod'),'name = "acceptance/consumer"\nversion = "0.0.0"\nimport {'+imports.join(',\n')+'}\n');
  writeFileSync(join(consumer,'moon.pkg'),'import {'+aliases.join(',\n')+'}\n');
  const emitted=emitNumericConsumer(prepared.map(item=>({model:item.model,symbols:item.symbols})));
  writeFileSync(join(consumer,'consumer_test.mbt'),emitted.source);writeFileSync(join(output,'consumer_test.mbt'),emitted.source);
  const env: NodeJS.ProcessEnv={...process.env,MOON_HOME:home,MOONBIT_NEW_NATIVE:'0',PATH:join(home,'bin')+delimiter+process.env.PATH};delete env.MOON_WORK;
  run(moon,['check','--target','native'],{cwd:workspace,env});
  const consumers=[];
  for(const mode of ['debug','release']) {
    const log=run(moon,['test','-p','acceptance/consumer','--frozen','--target','all',...(mode==='release'?['--release']:[])],{cwd:workspace,env});
    const passed=(log.stdout.match(new RegExp(`Total tests: ${emitted.tests}, passed: ${emitted.tests}, failed: 0`,'g'))||[]).length;
    assert.equal(passed,4,'Original and installed-generated consumers pass on native, js, wasm and wasm-gc '+mode);
    writeFileSync(join(output,'consumer-'+mode+'.log'),log.stdout+'\n'+log.stderr);
    consumers.push({mode,targets:['native','js','wasm','wasm-gc'],tests:emitted.tests});
    console.log('Installed MoonBit numeric consumers '+mode+': '+emitted.tests+' original/generated assertions passed on native, js, wasm and wasm-gc');
  }

  const paired=required[0]!;
  const conversions=prepared.find(item=>item.model.id==='conversions')!;
  const decimalModel=prepared.find(item=>item.model.id==='decimal')!;
  const conform=(item: Prepared,cases: string,extra: string[],status=0,model=item.checkpointFile)=>call(['conform',model,'--unit-id','Main','--cases',cases,...provider(paired,'debug'),...extra],status);
  const exactActual=(item: Prepared)=>item.model.rows.filter(row=>row.reference.kind==='exact').map(row=>baseline.get(item.model.id+'/'+row.id));
  // Ion text and an unknown future fact replay to the same exact observations.
  for(const item of prepared) {
    if(!item.exactCases)continue;
    const augmented=bridge.augment(item.checkpoint);
    assert.ok(augmented.metadata.some(m=>m.source.includes('future_numeric::{amount: 12.340')&&m.source.includes('null.int')),'Unknown metadata retained');
    const future=join(item.evidence,'Main-future.ionb');writeFileSync(future,Buffer.from(augmented.bytes));
    const formats=[['ion-text',item.textFile],['unknown-fact',future]] as const;
    const jsonReceipt=join(item.evidence,'replay-receipt.json');
    for(const [format,model] of formats) {
      const replay: ConformanceReport=JSON.parse(conform(item,item.exactCases,[...(format==='ion-text'?['--receipt',jsonReceipt,'--receipt-format','json']:[]),'--json'],0,model).stdout);
      assert.equal(replay.successful,true);
      assert.deepEqual(replay.execution.calls.map(c=>c.actual),exactActual(item));
    }
    // The checked JSON receipt keeps every exact integer, binary64 and Decimal observation.
    const checked: ConformanceReport=JSON.parse(readFileSync(jsonReceipt,'utf8'));
    assert.deepEqual(checked.execution.calls.map(c=>c.actual),exactActual(item));
  }

  // Refusals: rejected sources, inputs and capabilities publish nothing.
  const refusals: Record<string,string>={};
  const project=join(root,'numeric','refusals');mkdirSync(join(project,'src'),{recursive:true});
  const sourcePath=join(project,'src/Main.mbt');
  writeFileSync(join(project,'morphir.toml'),manifest('Refusals'));
  writeFileSync(sourcePath,'pub fn root(v : Double) -> Double { @basics.sqrt(v) }');
  assert.equal(JSON.parse(call(['run','.','--json'],0,project).stdout).successful,true);
  const published=join(project,'.morphir/out/compile.dest/Main.ionb'),kept=readFileSync(published);
  for(const [id,body,code,profile] of [
    ['stable-boundary','pub fn root(v : Double) -> Double { @basics.sqrt(v) }','moonbit_frontend.experimental_capability',stable],
    ['unsupported-function','pub fn angle(y : Double, x : Double) -> Double { @basics.atan2(y, x) }','moonbit_frontend.unknown_binding',numericSourceProfile],
    ['literal-overflow','pub fn big() -> Int32 { 2147483648 }','moonbit_frontend.invalid_literal',numericSourceProfile],
    ['unannotated-raise','pub fn rounded(v : Double) -> @integer.Integer { @basics.round(v) }','moonbit_frontend.error_contract',numericSourceProfile],
    ['function-budget',Array.from({length:65},(_,i)=>'pub fn f'+i+'(v : Double) -> Double { v }').join('\n'),'moonbit_frontend.declaration_count',numericSourceProfile],
  ] as const) {
    writeFileSync(join(project,'morphir.toml'),manifest('Refusals',profile));writeFileSync(sourcePath,body);
    const failure: PipelineReport=JSON.parse(call(['run','.','--json'],1,project).stdout);
    assert.equal(failure.successful,false);assert.deepEqual(failure.committed,[]);
    assert.match(failure.diagnostics[0]!.message,new RegExp('^'+code.replace('.','\\.')+':.*profile '+profile),id);
    assert.deepEqual(readFileSync(published),kept,'Refused source keeps the published checkpoint: '+id);
    refusals[id]=code;
  }
  const receipt=join(root,'numeric-refused-receipt.ionb');
  const refusedCases=(id: string,rows: {id:string;entry:string;arguments:NumericValue[];expected:NumericValue}[])=>{
    const file=join(output,id+'.ionb');writeFileSync(file,Buffer.from(bridge.cases(rows).bytes));return file;
  };
  // A Double argument cannot stand in for an Integer input.
  const badInput=refusedCases('bad-input',[{id:'bad-input',entry:conversions.entry('absolute'),arguments:[{type:'float64',bits:'0'}],expected:integer('0')}]);
  const badInputFailure=conform(conversions,badInput,['--receipt',receipt,'--json'],2);
  assert.match(badInputFailure.stderr,/^execution\.wrong_type:/);
  assert.deepEqual(JSON.parse(badInputFailure.stdout).committed,[]);assert.ok(!existsSync(receipt),'Bad input publishes no receipt');
  refusals['bad-input']='execution.wrong_type';
  // Without the SDK extension the generated build fails before any call runs.
  const withoutSdk=provider(paired,'debug'),sdk=withoutSdk.findIndex(arg=>arg.startsWith('finos/morphir-sdk='));
  assert.equal(withoutSdk[sdk-1],'--dependency');withoutSdk.splice(sdk-1,2);
  const missing=call(['conform',conversions.checkpointFile,'--unit-id','Main','--cases',conversions.exactCases!,...withoutSdk,'--receipt',receipt,'--json'],1);
  const unresolved: ConformanceReport=JSON.parse(missing.stdout);
  assert.equal(unresolved.successful,false);assert.equal(unresolved.execution.calls.length,0);
  assert.equal(unresolved.execution.failure!.cause.trim(),'execution.provider_failed: build.unresolved_dependency');
  assert.ok(unresolved.execution.terminals.every(t=>t.status==='failed'));
  assert.equal(bridge.conformance(readFileSync(receipt)).successful,false,'The receipt records the refusal');rmSync(receipt);
  refusals['missing-sdk-extension']='build.unresolved_dependency';
  // The 4096 decimal digit Integer budget refuses the value in every evaluator and generated code.
  const overBudget=integer('1'+'0'.repeat(4096));
  const budget=refusedCases('integer-budget',[{id:'integer-budget',entry:conversions.entry('absolute'),arguments:[overBudget],expected:{type:'model-error',code:'sdk.out_of_range'}}]);
  const budgetReport: ConformanceReport=JSON.parse(conform(conversions,budget,['--json']).stdout);
  assert.equal(budgetReport.successful,true);
  assert.deepEqual(budgetReport.execution.calls[0]!.actual,{type:'model-error',code:'sdk.out_of_range'});
  for(const evaluator of ['independent','scheme'])assert.equal(budgetReport.coverage.find(l=>l.provider===evaluator)!.calls[0]!.status,'matched');
  refusals['integer-budget']='sdk.out_of_range';
  const cancellation=join(root,'numeric-cancel');writeFileSync(cancellation,'cancel');
  const cancelled: ConformanceReport=JSON.parse(conform(decimalModel,decimalModel.exactCases!,['--cancel-file',cancellation,'--json'],130).stdout);
  assert.equal(cancelled.successful,false);assert.equal(cancelled.cancelled,true);
  assert.ok(cancelled.coverage.every(l=>l.calls.every(c=>c.status==='cancelled')));
  rmSync(cancellation);
  refusals.cancellation='cancelled';
  // A deliberately wrong Decimal expectation is reported, never repaired.
  const wrong=decimalModel.model.rows.find(row=>row.reference.kind==='exact'&&row.reference.expected.type==='decimal')!;
  const wrongCases=refusedCases('decimal-mismatch',[{id:wrong.id,entry:decimalModel.entry(wrong.name),arguments:wrong.arguments.map(a=>a.value),expected:decimal('999.5')}]);
  const mismatch: ConformanceReport=JSON.parse(conform(decimalModel,wrongCases,['--json'],1).stdout);
  assert.equal(mismatch.successful,false);
  assert.equal(mismatch.coverage.find(l=>l.provider==='independent')!.calls[0]!.status,'mismatch');

  // Observations stay off by default; --log uses .morphir/logs and --log-file overrides it.
  assert.ok(!existsSync(join(cwd,'.morphir')),'No default execution logs');
  const math=prepared.find(item=>item.model.id==='math')!;
  const observed: ConformanceReport=JSON.parse(conform(math,math.exactCases!,['--log','--json']).stdout);
  assert.equal(observed.successful,true);
  assert.deepEqual([...readFileSync(join(cwd,'.morphir/logs/execution.ionb')).subarray(0,4)],[224,1,0,234]);
  const explicit=join(root,'numeric-explicit.ionb');
  rmSync(join(cwd,'.morphir'),{recursive:true});
  assert.equal(JSON.parse(conform(math,math.exactCases!,['--log-file',explicit,'--json']).stdout).successful,true);
  assert.deepEqual([...readFileSync(explicit).subarray(0,4)],[224,1,0,234]);
  assert.ok(!existsSync(join(cwd,'.morphir')),'Explicit log path does not also write the default');
  const frontendLog=join(math.project,'.morphir/logs/frontend.ionb');
  assert.equal(JSON.parse(call(['run','.','--log','--json'],0,math.project).stdout).successful,true);
  assert.ok(existsSync(frontendLog),'Enabled frontend observations use the default log');
  writeFileSync(join(output,'observations.json'),JSON.stringify({defaultLogs:false,enabled:'.morphir/logs/execution.ionb',explicit:'--log-file',frontend:'.morphir/logs/frontend.ionb'},null,2)+'\n');
  assert.deepEqual(readdirSync(cwd),[]);

  const rows=prepared.reduce((n,item)=>n+item.model.rows.length,0);
  const summary={
    profile:'morphir-installed-numeric-v1',package:pack.integrity,node:process.version,platform:process.platform,arch:process.arch,
    sourceProfile:numericSourceProfile,stableBoundary:stable,promoted:false,
    models:prepared.map(item=>({id:item.model.id,entries:item.model.entries.length,rows:item.model.rows.length,
      exactRows:item.model.rows.filter(r=>r.reference.kind==='exact').length,
      sourceIdentity:hash(item.model.source),checkpointIdentity:hash(item.checkpoint),symbolsIdentity:hash(item.symbolsBytes),generatedTree:item.generatedTree,
      jsonProjection:item.jsonProjection})),
    entries:prepared.reduce((n,item)=>n+item.model.entries.length,0),rows,
    comparison:{decimal:'exact numerical value; observed coefficient and exponent retained in receipts',float64:'exact bits unless a row declares a finite ULP bound or a NaN/infinity category',approximateRows:'execute plus authored reference; conform stays exact'},
    requiredTargets:required,lanes,consumers,replays:['ion-text','unknown-fact','json-receipt'],refusals,observations:true,hostImports:['morphir_execution_v1'],
    unverified:[
      'wasm (non-GC) is not offered by the installed execution helper; installed-generated wrappers compile and pass on it in the consumer lane',
      'only the packed npm CLI distribution is installed; the source-built native CLI is covered by repository CLI tests',
    ],
  };
  writeFileSync(join(output,'summary.json'),JSON.stringify(summary,null,2)+'\n');
  console.log('Installed MoonBit numeric: '+prepared.length+' models, '+summary.entries+' entries, '+rows+' rows on '+required.join(', ')+' debug/release; consumers, replay, refusals and observations passed.');
  return summary;
}
