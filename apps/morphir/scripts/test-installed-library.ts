import type { Run, RunOptions, InstalledContext, ConformanceReport, Coverage, Observation, Frame, PipelineReport, LibraryFixtures, LibraryModel, NamingFixtures, NamingRow, Generated, Warning, Visibility, Consumer } from '../../../tests/cli-contracts.ts';
import assert from 'node:assert/strict';
import {mkdirSync,writeFileSync,readFileSync,existsSync,rmSync,cpSync} from 'node:fs';
import {join,delimiter} from 'node:path';
import {capabilities} from '../build-provider/capabilities.mts';
import {excluded,hash,treeIdentity} from '../build-provider/identity.mts';
import {includeDependencyPath} from '../build-provider/paths.mts';

const profile='moonbit-model-bool-library-v1';
const provider='finos/morphir-moonbit-frontend';

// The L1 fixture expectations are hand-authored, never computed from generated IR.
export function testInstalledLibrary({run,root,receipts,cli,helper,cwd,home,llvmHome,llvmPin,required,deps,pack,fixtures}: InstalledContext & { fixtures: LibraryFixtures }) {
  assert.equal(fixtures.profile,profile);assert.equal(fixtures.language,'moonbit');
  assert.equal(fixtures.parserVersion,'0.4.5');
  assert.deepEqual(fixtures.models.map(m=>m.id),['forward','shadow','diamond','zero','private','operators']);
  assert.equal(fixtures.models.reduce((n,m)=>n+m.entries.length,0),13);
  assert.equal(fixtures.models.reduce((n,m)=>n+m.entries.reduce((n,e)=>n+e.expected.length,0),0),42);
  const output=join(receipts,'moonbit-library');mkdirSync(output,{recursive:true});
  rmSync(join(output,'summary.json'),{force:true});
  const call=(args: string[],status=0,workdir=cwd)=>run(process.execPath,[cli,...args],{cwd:workdir,status});
  const compilers=new Map(required.map(target=>{
    const compilerHome=target==='llvm'?llvmHome!:home;
    const toolchainPin=target==='llvm'?JSON.parse(readFileSync(llvmPin!,'utf8')):undefined;
    const capability=capabilities({compilerHome,toolchainPin,timeout:10000});
    assert.ok(capability.targets.some(t=>t.target===target),'Required library lane unavailable: '+target);
    const env: NodeJS.ProcessEnv={...process.env,MOON_HOME:compilerHome,MOONBIT_NEW_NATIVE:'0',PATH:join(compilerHome,'bin')+delimiter+process.env.PATH};delete env.MOON_WORK;
    return [target,{compilerHome,capability,env}];
  }));
  const models=[],visibility: Visibility[]=[];
  for(const model of fixtures.models) {
    const project=join(root,'library-'+model.id);mkdirSync(join(project,'src'),{recursive:true});
    const artifact=join(output,model.id);mkdirSync(artifact,{recursive:true});
    const manifest='[project]\nname="Library'+model.id[0]!.toUpperCase()+model.id.slice(1)+'"\nmodule_prefix="App"\n[frontend]\nlanguage="moonbit"\nprofile="'+profile+'"\n[pipeline]\nbackend="checkpoint"\ncomponents=["json-identity"]\n';
    const sourcePath=join(project,'src/Main.mbt');writeFileSync(join(project,'morphir.toml'),manifest);
    writeFileSync(sourcePath,'pub fn broken(');
    const dry=JSON.parse(call(['run','.','--dry-run','--log','--json'],0,project).stdout);
    const descriptor=dry.frontends[0];
    assert.equal(descriptor.language,'moonbit');assert.equal(descriptor.provider,provider);
    assert.equal(descriptor.profile,profile);assert.equal(descriptor.defaultProfile,false);
    assert.equal(descriptor.evidence,'local-acceptance');assert.equal(descriptor.outputContract,'ir-unit');
    assert.equal(descriptor.capabilities.maxDocuments,1);assert.equal(descriptor.capabilities.incremental,false);
    assert.ok(!existsSync(join(project,'.morphir')),'Library dry-run must not read source or create logs/output');
    writeFileSync(sourcePath,model.source);writeFileSync(join(artifact,'Main.mbt'),model.source);
    writeFileSync(join(artifact,'morphir.toml'),manifest);
    const compiled=JSON.parse(call(['run','.','--json'],0,project).stdout);
    assert.equal(compiled.successful,true);assert.equal(compiled.processed,1);
    const published=join(project,'.morphir/out/compile.dest');
    const checkpoint=join(artifact,'Main.ionb'),bytes=readFileSync(join(published,'Main.ionb'));
    assert.deepEqual([...bytes.subarray(0,4)],[224,1,0,234]);writeFileSync(checkpoint,bytes);
    assert.ok(!existsSync(join(project,'.morphir/logs')),'Logs remain disabled by default');
    assert.equal(JSON.parse(call(['run','.','--checkpoint-format','ion-text','--json'],0,project).stdout).successful,true);
    const ion=readFileSync(join(published,'Main.ion'),'utf8');
    for(const token of ['morphir_moonbit_frontend',profile,'moonbit-parser-position-v1','metadata','provenance'])assert.ok(ion.includes(token),token);
    for(const entry of [...model.entries,...model.private])assert.ok(ion.includes(entry.original.replaceAll('_','-')),entry.original);
    writeFileSync(join(artifact,'Main.ion'),ion);
    assert.equal(JSON.parse(call(['run','.','--backend','moonbit','--validation','source-only','--json'],0,project).stdout).successful,true);
    const generated=readFileSync(join(published,'Main/library.mbt'),'utf8');
    const generatedSnapshot=join(artifact,'generated');
    cpSync(join(published,'Main'),generatedSnapshot,{recursive:true});
    assert.equal((generated.match(/^pub fn /gm)||[]).length,model.entries.length);
    assert.equal((generated.match(/^fn /gm)||[]).length,model.private.length);
    writeFileSync(join(artifact,'library.mbt'),generated);
    const symbols=readFileSync(join(published,'Main/symbols.10n'));
    assert.deepEqual([...symbols.subarray(0,4)],[224,1,0,234]);writeFileSync(join(artifact,'symbols.10n'),symbols);
    const canonical=(name: string)=>'library-'+model.id+':app/main#'+name.replaceAll('_','-');
    const invocation=(names: string[],file: string)=>{
      const suite=join(artifact,file);
      writeFileSync(suite,JSON.stringify({profile:'morphir-invocations-v1',calls:names.map(name=>({id:name,entry:canonical(name),arguments:[]}))}));
      return suite;
    };
    const rejectedEntries=[];
    for(const name of [...model.private.map(p=>p.original),'absent']) {
      const suite=invocation([name],'rejected-'+name+'.json');
      const rejection=JSON.parse(call(['execute',checkpoint,'--unit-id','Main','--suite',suite,'--dry-run','--json'],2).stdout);
      assert.match(rejection.error,/execution.entry_not_public_or_supported/);
      rejectedEntries.push(name);
    }
    const before=treeIdentity(published);
    const loss=JSON.parse(call(['run','.','--checkpoint-format','morphir-json','--json'],1,project).stdout);
    assert.match(loss.diagnostics[0].message,/data.lossy_conversion/);assert.deepEqual(loss.committed,[]);
    assert.equal(treeIdentity(published),before,'Lossy JSON rejection preserves all published artifacts');
    for(const [id,source,diagnostic] of [
      ['recursive','pub fn bad(x : Bool) -> Bool { bad(x) }',/moonbit_frontend\.recursive_call/],
      ['malformed','pub fn broken(',/moonbit_frontend\./],
      ['binding-type','pub fn bad() -> Bool { let x : Bool = 42; x }',/moonbit_frontend\./],
    ] as [string, string, RegExp][]) {
      writeFileSync(sourcePath,source!);
      const failure=JSON.parse(call(['run','.','--json'],1,project).stdout);
      assert.equal(failure.successful,false);assert.deepEqual(failure.committed,[]);
      assert.match(failure.diagnostics[0].message,diagnostic!);
      assert.match(failure.diagnostics[0].message,/provider finos\/morphir-moonbit-frontend; profile moonbit-model-bool-library-v1/);
      assert.equal(treeIdentity(published),before,'Rejected '+id+' preserves all published artifacts');
      writeFileSync(join(artifact,'rejected-'+id+'.json'),JSON.stringify(failure,null,2)+'\n');
    }
    writeFileSync(sourcePath,model.source);
    const rows=model.entries.flatMap(entry=>{
      assert.match(entry.original,/^[a-zA-Z_][a-zA-Z0-9_]*$/);
      assert.equal(entry.arguments.length,entry.expected.length);
      assert.equal(new Set(entry.arguments.map(args=>JSON.stringify(args))).size,entry.arguments.length);
      assert.equal(entry.arguments.length,2**entry.arguments[0]!.length,'Exhaustive Boolean rows');
      return entry.arguments.map((args,i)=>{
        assert.ok(args.every(a=>typeof a==='boolean'));assert.equal(typeof entry.expected[i],'boolean');
        return {id:entry.original+'-'+i,original:entry.original,entry:canonical(entry.original),arguments:args,expected:entry.expected[i]};
      });
    });
    const cases=join(artifact,'cases.ion');
    writeFileSync(cases,'{profile:"morphir-conformance-v1",version:"moonbit-library-bool-1",provenance:"Hand-authored exhaustive L1 Boolean rows; independently checked by the original compiler",cases:['+rows.map(r=>`{id:"${r.id}",entry:"${r.entry}",arguments:[${r.arguments}],expected:${r.expected}}`).join(',')+']}');
    const original=join(root,'library-original-'+model.id);mkdirSync(original);
    writeFileSync(join(original,'moon.mod'),'name="acceptance/library-original-'+model.id+'"\nversion="0.0.0"\n');
    writeFileSync(join(original,'moon.pkg'),'');writeFileSync(join(original,'Main.mbt'),model.source);
    writeFileSync(join(original,'original_test.mbt'),rows.map(r=>`///|\ntest "${r.id}" { assert_eq(${r.original}(${r.arguments.join(', ')}), ${r.expected}) }\n`).join('\n'));
    const verify=(target: string,mode: string,extra: string[]=[],status=0,suite=cases)=>call(['conform',checkpoint,'--unit-id','Main','--cases',suite,'--execution-helper',helper,'--home',target==='llvm'?llvmHome!:home,...(target==='llvm'?['--toolchain-pin',llvmPin!]:[]),...deps,'--target',target,'--build-mode',mode,...extra],status);
    const lanes=[];let baseline: ConformanceReport | undefined;
    for(const target of required)for(const mode of ['debug','release']) {
      const id=target+'-'+mode,{compilerHome,capability,env}=compilers.get(target)!;
      const oracle=run(join(compilerHome,'bin/moon'),['test','--frozen','--target',target,...(mode==='release'?['--release']:[])],{cwd:original,env});
      assert.match(oracle.stdout,new RegExp(`Total tests: ${rows.length}, passed: ${rows.length}, failed: 0`));
      writeFileSync(join(artifact,id+'-original.log'),oracle.stdout+'\n'+oracle.stderr);
      // All-private libraries compile but have no public execution rows.
      if(rows.length===0)continue;
      const report: ConformanceReport=JSON.parse(verify(target,mode,['--receipt',join(artifact,id+'.ionb'),'--json']).stdout);
      assert.equal(report.successful,true);assert.equal(report.execution.calls.length,rows.length);
      assert.equal(report.execution.evidence.buildMode,mode);assert.equal(report.execution.target,target);
      assert.equal(report.execution.evidence.compilerIdentity,capability.compilerIdentity);
      assert.equal(report.execution.evidence.coreIdentity,capability.coreIdentity);
      for(const evaluator of ['independent','scheme']) {
        const coverage=report.coverage.find(l=>l.provider===evaluator);assert.ok(coverage,evaluator);
        assert.equal(coverage.calls.length,rows.length);assert.ok(coverage.calls.every(c=>c.status==='matched'));
      }
      assert.deepEqual(report.execution.calls.map(c=>c.actual),rows.map(r=>({type:'bool',value:r.expected})));
      assert.ok(!existsSync(report.execution.evidence.executable!),'Library execution lease disposed');
      writeFileSync(join(artifact,id+'.json'),JSON.stringify(report,null,2)+'\n');
      lanes.push({target,mode,rows:rows.length,compilerIdentity:capability.compilerIdentity,coreIdentity:capability.coreIdentity,evidence:report.execution.evidence});
      if(target===required[0]&&mode==='debug')baseline=report;
      console.log('Installed MoonBit library '+model.id+' '+id+': '+rows.length+' original/independent/Scheme/generated rows passed');
    }
    let instrumentation;
    if(model.id==='forward') {
      const defaultLog=join(project,'.morphir/logs/frontend.ionb');
      assert.deepEqual(JSON.parse(call(['run','.','--log','--json'],0,project).stdout),compiled);
      assert.deepEqual(readFileSync(join(published,'Main.ionb')),bytes);
      assert.deepEqual([...readFileSync(defaultLog).subarray(0,4)],[224,1,0,234]);
      writeFileSync(join(artifact,'frontend.ionb'),readFileSync(defaultLog));
      const frontendLog=join(artifact,'frontend.jsonl');
      const framed=call(['run','.','--log-file',frontendLog,'--log-format','json-lines','--json-lines'],0,project).stdout.trim().split('\n').map(line => JSON.parse(line));
      assert.deepEqual(framed.filter(r=>r.type==='result').map(r=>r.data),[{successful:compiled.successful,processed:compiled.processed,publicationError:compiled.publicationError}]);
      const events=readFileSync(frontendLog,'utf8').trim().split('\n').map(line => JSON.parse(line));
      const stages=events.filter(r=>r.signal==='succeeded').map(r=>r.stage);
      assert.deepEqual(stages,['parse','profile-check','resolve','profile-check','lower','frontend']);
      assert.ok(!/\bdecide\b|\bdefault_ready\b|\bready\b|\ballowed\b|λ😀/.test(readFileSync(frontendLog,'utf8')));
      const failed=call(['run','.','--log-file',root,'--json'],0,project);
      assert.match(failed.stderr,/observability sink unavailable/);assert.deepEqual(JSON.parse(failed.stdout),compiled);
      assert.deepEqual(readFileSync(join(published,'Main.ionb')),bytes);
      const sourceStderr=call(['run','.','--log-file','@stderr','--log-format','text','--json'],0,project);
      assert.deepEqual(JSON.parse(sourceStderr.stdout),compiled);assert.match(sourceStderr.stderr,/morphir-observation-v1/);
      assert.equal(JSON.parse(call(['run','.','--frontend-profile','moonbit-model-bool-v1','--dry-run','--json'],0,project).stdout).frontends[0].defaultProfile,true);
      assert.ok(JSON.parse(call(['run','.','--frontend-provider','absent','--dry-run','--json'],2,project).stdout).error.includes('frontend.unknown_provider'));
      const target=required[0],quiet=JSON.parse(verify(target!,'debug',['--telemetry-adapter','none','--json']).stdout);
      const logged=JSON.parse(verify(target!,'debug',['--log-file',join(artifact,'execution.ionb'),'--json']).stdout);
      const failedSink=verify(target!,'debug',['--log-file',root,'--json']);assert.match(failedSink.stderr,/observability sink unavailable/);
      for(const report of [quiet,logged,JSON.parse(failedSink.stdout)]) {
        assert.equal(report.successful,true);assert.deepEqual(report.execution.calls,baseline!.execution.calls);
        for(const field of ['sourceIdentity','driverIdentity','manifestIdentity','compilerIdentity','coreIdentity'] as const)assert.equal(report.execution.evidence[field],baseline!.execution.evidence[field]);
        assert.equal(report.execution.invocationEvidence.suiteIdentity,baseline!.execution.invocationEvidence.suiteIdentity);
        assert.ok(!existsSync(report.execution.evidence.executable));
      }
      const dryLog=join(artifact,'dry.ionb'),dryReceipt=join(artifact,'dry-receipt.ionb');
      const executionDry=JSON.parse(verify(target!,'debug',['--dry-run','--log-file',dryLog,'--receipt',dryReceipt,'--json']).stdout);
      assert.equal(executionDry.dryRun,true);assert.equal(executionDry.calls.length,rows.length);
      assert.deepEqual(executionDry.entries,rows.map(r=>r.entry));
      assert.ok(!existsSync(dryLog));assert.ok(!existsSync(dryReceipt));
      const framedExecution=verify(target!,'debug',['--json-lines']).stdout.trim().split('\n').map(line => JSON.parse(line));
      assert.equal(framedExecution.filter(r=>r.type==='result').length,1);assert.equal(framedExecution.find(r=>r.type==='result').data.successful,true);
      assert.match(verify(target!,'debug').stdout,/independent decide-0: matched/);
      const mismatchCase=rows.find(r=>r.expected),bad=join(artifact,'wrong.ion');
      writeFileSync(bad,readFileSync(cases,'utf8').replace('expected:true','expected:false'));
      const mismatch: ConformanceReport=JSON.parse(verify(target!,'debug',['--json'],1,bad).stdout);
      assert.equal(mismatch.successful,false);
      assert.equal(mismatch.coverage.find(l=>l.provider==='independent')!.calls.find(c=>c.id===mismatchCase!.id)!.status,'mismatch');
      assert.ok(!existsSync(mismatch.execution.evidence.executable!));
      writeFileSync(join(artifact,'mismatch.json'),JSON.stringify(mismatch,null,2)+'\n');
      instrumentation={frontendStages:stages,frontendNeutral:true,executionNeutral:true,failedSinkNeutral:true,dryRun:true,stdoutFraming:true,mismatchRejected:true};
    }
    visibility.push({model,original,generated:generatedSnapshot,canonical});
    models.push({id:model.id,frontend:descriptor,sourceIdentity:hash(model.source),checkpointIdentity:hash(bytes),symbolsIdentity:hash(symbols),entries:model.entries.length,private:model.private.length,rows:rows.length,lanes,originalCompilerLanes:required.length*2,rejectedEntries,rejectedSources:3,lossyJsonRejected:true,publicationPreserved:true,...(instrumentation?{instrumentation}:{})});
  }
  const privacy=testCompilerPrivacy({run,root,output,visibility,compilers,deps});
  const summary={profile:'morphir-installed-library-v1',package:pack.integrity,requiredTargets:required,models,entries:13,rowsPerLane:42,publicLibraryLanes:required.length*2*5,allPrivateSourceCompiled:true,privacy};
  writeFileSync(join(output,'summary.json'),JSON.stringify(summary,null,2)+'\n');
  console.log('Installed MoonBit library: '+required.join(', ')+' debug/release; 6 libraries, 13 public entries, 42 exhaustive rows passed.');
  return summary;
}

function testCompilerPrivacy({run,root,output,visibility,compilers,deps}: { run: Run; root: string; output: string; visibility: Visibility[]; compilers: Map<string,{compilerHome: string; env: NodeJS.ProcessEnv}>; deps: string[] }) {
  const workspace=join(root,'library-visibility');mkdirSync(workspace);
  const sdk=deps.find(d=>d.startsWith('finos/morphir-sdk='))!.slice('finos/morphir-sdk='.length);
  cpSync(sdk,join(workspace,'sdk'),{recursive:true,filter:path=>includeDependencyPath(sdk,path,excluded)});
  const members=['./sdk','./consumer'],imports=[],aliases=[],probes=[];
  for(const {model,original,generated,canonical} of visibility)for(const [kind,path] of [['original',original],['generated',generated]] as const) {
    const directory=kind+'-'+model.id;cpSync(path!,join(workspace,directory),{recursive:true,filter:p=>includeDependencyPath(path!,p,excluded)});
    members.push('./'+directory);
    const manifest=readFileSync(join(path!,'moon.mod'),'utf8'),module=manifest.match(/^name\s*=\s*"([^"]+)"/m)![1];
    const version=manifest.match(/^version\s*=\s*"([^"]+)"/m)![1],alias=kind+'_'+model.id;
    imports.push(JSON.stringify(module+'@'+version));aliases.push(JSON.stringify(module)+' @'+alias);
    for(const symbol of model.private) {
      const name=symbol.original;
      if(kind==='generated')assert.match(readFileSync(join(path!,'library.mbt'),'utf8'),new RegExp('^fn '+name+'\\(', 'm'),'Private source spelling remains readable');
      assert.match(name,/^[a-zA-Z_][a-zA-Z0-9_]*$/);
      probes.push({model:model.id,kind,name,source:`pub fn probe() -> Unit { ignore(@${alias}.${name}) }\n`});
    }
  }
  const consumer=join(workspace,'consumer');mkdirSync(consumer);
  writeFileSync(join(consumer,'moon.mod'),'name="acceptance/library-consumer"\nversion="0.0.0"\nimport { '+imports.join(', ')+' }\n');
  writeFileSync(join(consumer,'moon.pkg'),'import { '+aliases.join(', ')+' }\n');
  writeFileSync(join(consumer,'main.mbt'),'pub fn baseline() -> Unit {}\n');
  writeFileSync(join(workspace,'moon.work'),'members='+JSON.stringify(members)+'\n');
  const lanes=[];
  for(const [target,{compilerHome,env}] of compilers)for(const mode of ['debug','release']) {
    const checked=run(join(compilerHome,'bin/moon'),['test','--frozen','--target',target,'-p','acceptance/library-consumer',...(mode==='release'?['--release']:[])],{cwd:workspace,env});
    assert.match(checked.stdout,/Total tests: 0, passed: 0, failed: 0/);
    writeFileSync(join(output,'visibility-'+target+'-'+mode+'.log'),checked.stdout+'\n'+checked.stderr);
    lanes.push({target,mode,generatedLibraries:6,allPrivateCompiled:true});
  }
  const {compilerHome,env}=compilers.values().next().value!;
  const check=()=>run(join(compilerHome,'bin/moon'),['check','--frozen','--target','js','./consumer'],{cwd:workspace,env,status:0});
  check();
  const probePath=join(consumer,'probe.mbt');
  for(const [index,probe] of probes.entries()) {
    writeFileSync(probePath,probe.source);
    const rejected=run(join(compilerHome,'bin/moon'),['check','--frozen','--target','js','./consumer'],{cwd:workspace,env,status:null});
    assert.ok((rejected.stdout+rejected.stderr).includes(probe.name),'Private compiler rejection identifies requested value');
    writeFileSync(join(output,'private-'+index+'.log'),rejected.stdout+'\n'+rejected.stderr);
  }
  rmSync(probePath);check();
  assert.equal(probes.length,16);
  return {lanes,privateAccess:probes.map(({model,kind,name})=>({model,kind,name,rejected:true})),restored:true};
}

// Naming expectations come from the independently authored MoonBit fixture rows.
// The npm-installed CLI publishes every project consumed here. A simulated host
// supplies provider admission only for the explicit-capability library lane.
export function testInstalledNaming({run,root,receipts,cli,helper,cwd,home,llvmHome,llvmPin,required,deps,pack,fixtures,repo}: InstalledContext & { fixtures: NamingFixtures; repo: string }) {
  assert.equal(fixtures.frontendPolicy,'moonbit-readable-names-v1');
  assert.equal(fixtures.backendPolicy,'moonbit-readable-targets-v1');
  assert.deepEqual(fixtures.models.map(m=>m.id),['collision','initialisms','capture','parameters']);
  const output=join(receipts,'moonbit-naming');mkdirSync(output,{recursive:true});
  rmSync(join(output,'summary.json'),{force:true});
  const call=(args: string[],workdir=cwd,status=0)=>run(process.execPath,[cli,...args],{cwd:workdir,status});
  const compilers=new Map(required.map(target=>{
    const compilerHome=target==='llvm'?llvmHome!:home;
    const pin=target==='llvm'?JSON.parse(readFileSync(llvmPin!,'utf8')):undefined;
    const capability=capabilities({compilerHome,toolchainPin:pin,timeout:10000});
    assert.ok(capability.targets.some(t=>t.target===target),'Required naming lane unavailable: '+target);
    const env: NodeJS.ProcessEnv={...process.env,MOON_HOME:compilerHome,MOONBIT_NEW_NATIVE:'0',PATH:join(compilerHome,'bin')+delimiter+process.env.PATH};delete env.MOON_WORK;
    return [target,{compilerHome,capability,env}];
  }));
  const rowsFor=(model: {entries: import('../../../tests/cli-contracts.ts').FixtureEntry[]},prefix: string)=>model.entries.flatMap(e=>e.arguments.map((args,i)=>({id:e.original+'-'+i,original:e.original,entry:prefix+e.semantic,arguments:args,expected:e.expected[i]!})));
  const suiteFor=(directory: string,rows: NamingRow[])=>{
    const path=join(directory,'cases.ion');
    writeFileSync(path,'{profile:"morphir-conformance-v1",version:"moonbit-naming-1",provenance:"Hand-authored Boolean rows, checked with original source compiler",cases:['+rows.map(r=>`{id:"${r.id}",entry:"${r.entry}",arguments:[${r.arguments}],expected:${r.expected}}`).join(',')+']}');
    return path;
  };
  const originalFor=(id: string,source: string,rows: NamingRow[])=>{
    const path=join(root,'naming-original-'+id);mkdirSync(path);
    writeFileSync(join(path,'moon.mod'),`name="acceptance/naming-original-${id}"\nversion="0.0.0"\n`);
    writeFileSync(join(path,'moon.pkg'),'');writeFileSync(join(path,'Main.mbt'),source);
    writeFileSync(join(path,'original_test.mbt'),rows.map(r=>`///|\ntest "${r.id}" { assert_eq(${r.original}(${r.arguments.join(', ')}), ${r.expected}) }\n`).join('\n'));
    return path;
  };
  const qualified: unknown[]=[];
  const qualify=(id: string,checkpoint: string,directory: string,rows: NamingRow[],original: string)=>{
    const cases=suiteFor(directory,rows),lanes=[];
    for(const [target,{compilerHome,capability,env}] of compilers)for(const mode of ['debug','release']) {
      const oracle=run(join(compilerHome,'bin/moon'),['test','--frozen','--target',target,...(mode==='release'?['--release']:[])],{cwd:original,env});
      assert.match(oracle.stdout,new RegExp(`Total tests: ${rows.length}, passed: ${rows.length}, failed: 0`));
      writeFileSync(join(directory,target+'-'+mode+'-original.log'),oracle.stdout+'\n'+oracle.stderr);
      const report: ConformanceReport=JSON.parse(call(['conform',checkpoint,'--unit-id','Main','--cases',cases,'--execution-helper',helper,'--home',compilerHome,...(target==='llvm'?['--toolchain-pin',llvmPin!]:[]),...deps,'--target',target,'--build-mode',mode,'--telemetry-adapter','none','--json']).stdout);
      assert.equal(report.successful,true);
      assert.equal(report.execution.evidence.compilerIdentity,capability.compilerIdentity);
      assert.equal(report.execution.evidence.coreIdentity,capability.coreIdentity);
      assert.deepEqual(report.execution.calls.map(c=>c.actual),rows.map(r=>({type:'bool',value:r.expected})));
      for(const evaluator of ['independent','scheme']) {
        const coverage=report.coverage.find(l=>l.provider===evaluator);
        assert.equal(coverage!.calls.length,rows.length);assert.ok(coverage!.calls.every(c=>c.status==='matched'));
      }
      assert.ok(!existsSync(report.execution.evidence.executable!));
      writeFileSync(join(directory,target+'-'+mode+'.json'),JSON.stringify(report,null,2)+'\n');
      lanes.push({target,mode,rows:rows.length,evidence:report.execution.evidence});
      console.log('Installed naming '+id+' '+target+'-'+mode+': '+rows.length+' original/independent/Scheme/generated rows passed');
    }
    qualified.push({id,checkpointIdentity:hash(readFileSync(checkpoint)),rows:rows.length,lanes});
  };
  const consumers: Record<'readable' | 'legacy', Consumer[]>={readable:[],legacy:[]};
  const hexName=(fqname: string)=>'v_'+Buffer.from(fqname).toString('hex');
  const verifyArtifacts=(path: string,expected: Generated)=>{
    for(const artifact of expected.artifacts)assert.deepEqual(readFileSync(join(path,artifact.path)),typeof artifact.content==='string'?Buffer.from(artifact.content):Buffer.from(artifact.content),artifact.path);
  };
  const warningsFor=(report: PipelineReport)=>{
    assert.ok(report.warnings.every(w=>w.code&&w.fix&&w.locations.length));
    const keys=report.warnings.map(w=>JSON.stringify([w.code,w.locations]));
    assert.equal(new Set(keys).size,keys.length,'Checkpoint replay deduplicates warnings');
    // Resuming a checkpoint changes the input path, not the diagnostic identity.
    return report.warnings.map(({path,...warning})=>warning);
  };
  for(const model of fixtures.models) {
    const directory=join(output,model.id);mkdirSync(directory,{recursive:true});
    const project=join(root,'naming-'+model.id);mkdirSync(join(project,'src'),{recursive:true});
    const base='[project]\nname="Naming'+model.id[0]!.toUpperCase()+model.id.slice(1)+'"\nmodule_prefix="App"\n';
    const manifest=(language: string)=>base+'[frontend]\nlanguage="'+language+'"\n'+(language==='moonbit'?'profile="'+profile+'"\n':'')+'[pipeline]\nbackend="moonbit"\nvalidation="source-only"\ncomponents=["json-identity"]\n';
    const config=join(project,'morphir.toml');writeFileSync(config,manifest('moonbit'));
    writeFileSync(join(project,'src/Main.mbt'),model.source);
    const checkpoint=join(directory,'Main.ionb');
    const checkpointReport=JSON.parse(call(['run','.','--backend','checkpoint','--checkpoint-format','ion-binary','--json'],project).stdout);
    assert.equal(checkpointReport.successful,true);
    const checkpointBytes=readFileSync(join(project,'.morphir/out/compile.dest/Main.ionb'));
    assert.deepEqual(checkpointBytes,Buffer.from(model.checkpoints.binary),'Installed source checkpoint agrees with the pure adapter');
    writeFileSync(checkpoint,checkpointBytes);
    const report=JSON.parse(call(['run','.','--json'],project).stdout);
    assert.equal(report.successful,true);
    const warnings=warningsFor(report);
    assert.equal(warnings.length,['collision','parameters'].includes(model.id)?1:0);
    if(warnings.length) {
      assert.equal(warnings[0]!.code,'moonbit_frontend.name_normalization_collision');
      assert.ok(warnings[0]!.locations.every(l=>l.owner&&l.original&&l.allocated&&l.source.startLine>0));
      if(model.id==='collision')assert.match(warnings[0]!.fix,/is_ready_renamed_2/);
    }
    assert.ok(!existsSync(join(project,'.morphir/logs')),'Warnings require no logs');
    const published=join(project,'.morphir/out/compile.dest'),generated=join(published,'Main');
    verifyArtifacts(generated,model.generated);
    cpSync(generated,join(directory,'generated'),{recursive:true});
    const prefix='naming-'+model.id+':app/main#',rows=rowsFor(model,prefix);
    consumers.readable.push({id:model.id,path:join(directory,'generated'),module:model.generated.module,rows:rows.map(r=>({...r,function:r.original}))});
    const original=originalFor(model.id,model.source,rows!);
    qualify(model.id,checkpoint,directory,rows!,original);
    if(model.id==='collision') {
      writeFileSync(join(project,'src/Main.mbt'),model.source.split('\n').reverse().join('\n'));
      const reordered: PipelineReport=JSON.parse(call(['run','.','--json'],project).stdout);
      assert.equal(reordered.successful,true);
      assert.deepEqual(reordered.warnings[0]!.locations.map(l=>[l.original,l.allocated]),report.warnings[0].locations.map((l: { original: string; allocated: string })=>[l.original,l.allocated]));
      assert.deepEqual(readFileSync(join(generated,'library.mbt')),readFileSync(join(directory,'generated/library.mbt')),'Declaration order does not change public allocation');
      writeFileSync(join(project,'src/Main.mbt'),model.source);
      assert.equal(JSON.parse(call(['run','.','--json'],project).stdout).successful,true);
    }
    const before=treeIdentity(published),logged=JSON.parse(call(['run','.','--log','--json'],project).stdout);
    assert.deepEqual(logged,report);assert.equal(treeIdentity(published),before,'Logging is neutral for generated publication');
    if(warnings.length) {
      writeFileSync(config,manifest('moonbit').replace('[pipeline]\n','[pipeline]\nstrict_naming=true\n'));
      const rejected=JSON.parse(call(['run','.','--json'],project,1).stdout);
      assert.equal(rejected.successful,false);assert.deepEqual(rejected.committed,[]);assert.match(rejected.diagnostics[0].message,/naming.strict/);
      assert.equal(treeIdentity(published),before,'Strict source failure preserves prior publication');
      writeFileSync(join(directory,'strict-source.json'),JSON.stringify(rejected,null,2)+'\n');
    }
    rmSync(join(project,'src'),{recursive:true});mkdirSync(join(project,'src'));
    for(const [format,ext,key] of [['ion-text','ion','text'],['ion-binary','ionb','binary']] as const) {
      const bytes=key==='text'?model.opaqueCheckpoints[key]:Buffer.from(model.opaqueCheckpoints[key]);
      const input=join(project,'src/Main.'+ext);writeFileSync(input,bytes);writeFileSync(config,manifest(format!));
      const replay=JSON.parse(call(['run','.','--json'],project).stdout);
      assert.equal(replay.successful,true);assert.deepEqual(warningsFor(replay),warnings);
      verifyArtifacts(generated,model.opaqueGenerated);
      writeFileSync(config,manifest(format!).replace('backend="moonbit"','backend="checkpoint"'));
      const preserved=JSON.parse(call(['run','.','--checkpoint-format',format,'--json'],project).stdout);
      assert.equal(preserved.successful,true);assert.deepEqual(readFileSync(join(published,'Main.'+ext)),Buffer.from(bytes));
      const preservedTree=treeIdentity(published);
      const loss=JSON.parse(call(['run','.','--checkpoint-format','morphir-json','--json'],project,1).stdout);
      assert.match(loss.diagnostics[0].message,/data.lossy_conversion/);assert.equal(treeIdentity(published),preservedTree);
      if(warnings.length) {
        writeFileSync(config,manifest(format!).replace('[pipeline]\n','[pipeline]\nstrict_naming=true\n'));
        const strict=JSON.parse(call(['run','.','--json'],project,1).stdout);
        assert.equal(strict.successful,false);assert.match(strict.diagnostics[0].message,/naming.strict/);assert.deepEqual(strict.committed,[]);assert.equal(treeIdentity(published),preservedTree);
        writeFileSync(join(directory,'strict-'+format+'.json'),JSON.stringify(strict,null,2)+'\n');
      }
      rmSync(input);
    }
    writeFileSync(join(project,'src/Main.ionb'),Buffer.from(model.checkpoints.binary));
    writeFileSync(config,manifest('ion-binary')+'[backends.moonbit]\nnaming="legacy-hex"\n');
    assert.equal(JSON.parse(call(['run','.','--json'],project).stdout).successful,true);
    verifyArtifacts(generated,model.legacyGenerated);cpSync(generated,join(directory,'legacy'),{recursive:true});
    consumers.legacy.push({id:model.id,path:join(directory,'legacy'),module:model.legacyGenerated.module,rows:rows.map(r=>({...r,function:hexName(r.entry)}))});
    writeFileSync(join(directory,'warnings.json'),JSON.stringify(warnings,null,2)+'\n');
  }
  const historical: { files: Record<string,string>; entries: { original: string; semantic: string; expected: boolean }[]; package: string; module: string }=JSON.parse(readFileSync(join(repo,'apps/morphir/fixtures/naming/pre-readable.json'),'utf8'));
  for(const [file,expected] of Object.entries(historical.files))assert.equal(hash(readFileSync(join(repo,'apps/morphir/fixtures/naming',file))),expected);
  const oldDirectory=join(output,'historical');mkdirSync(oldDirectory,{recursive:true});
  const oldCheckpoint=join(oldDirectory,'Main.ion');writeFileSync(oldCheckpoint,readFileSync(join(repo,'apps/morphir/fixtures/naming/pre-readable.ion')));
  const oldSource=readFileSync(join(repo,'apps/morphir/fixtures/naming/pre-readable.mbt'),'utf8');
  const oldRows=rowsFor({entries:historical.entries.map(e=>({...e,arguments:[[]],expected:[e.expected]}))},historical.package+':'+historical.module+'#');
  qualify('historical',oldCheckpoint,oldDirectory,oldRows!,originalFor('historical',oldSource,oldRows!));
  const oldProject=join(root,'naming-historical');mkdirSync(join(oldProject,'src'),{recursive:true});
  writeFileSync(join(oldProject,'src/Main.ion'),readFileSync(oldCheckpoint));
  const oldConfig='[project]\nname="Historical"\n[frontend]\nlanguage="ion-text"\n[pipeline]\nbackend="moonbit"\nvalidation="source-only"\n';
  for(const style of ['readable','legacy'] as const) {
    writeFileSync(join(oldProject,'morphir.toml'),oldConfig+(style==='legacy'?'[backends.moonbit]\nnaming="legacy-hex"\n':''));
    assert.equal(JSON.parse(call(['run','.','--json'],oldProject).stdout).successful,true);
    const path=join(oldProject,'.morphir/out/compile.dest/Main'),snapshot=join(oldDirectory,style);cpSync(path,snapshot,{recursive:true});
    const manifest=readFileSync(join(path,'symbols.10n'));
    for(const row of oldRows)assert.ok(manifest.includes(Buffer.from(row.entry)),'Historical canonical identity is retained');
    const module=readFileSync(join(path,'moon.mod'),'utf8').match(/^name\s*=\s*"([^"]+)"/m)![1];
    consumers[style].push({id:'historical',path:snapshot,module: module!,rows:oldRows.map(r=>({...r,function:style==='legacy'?hexName(r.entry):r.original}))});
  }
  const requestDirectory=join(output,'requests');mkdirSync(requestDirectory,{recursive:true});
  const requestProject=join(root,'naming-requests');mkdirSync(join(requestProject,'src'),{recursive:true});
  const requestConfig=join(requestProject,'morphir.toml');
  const requestBase='[project]\nname="Requests"\n[frontend]\nlanguage="FORMAT"\n[pipeline]\nbackend="checkpoint"\ncomponents=["json-identity"]\n';
  for(const request of fixtures.requests) {
    const binary=request.format==='ion-binary',ext=binary?'ionb':'ion';
    const bytes=Buffer.from(request.checkpoint);
    const path=join(requestProject,'src/Main.'+ext);writeFileSync(path,bytes);
    writeFileSync(requestConfig,requestBase.replace('FORMAT',request.format));
    assert.equal(JSON.parse(call(['run','.','--checkpoint-format',request.format,'--json'],requestProject).stdout).successful,true);
    const published=join(requestProject,'.morphir/out/compile.dest');
    assert.deepEqual(readFileSync(join(published,'Main.'+ext)),bytes);
    const before=treeIdentity(published);
    writeFileSync(requestConfig,requestBase.replace('FORMAT',request.format).replace('backend="checkpoint"','backend="moonbit"\nvalidation="source-only"'));
    const refused=JSON.parse(call(['run','.','--json'],requestProject,1).stdout);
    assert.equal(refused.successful,false);assert.match(refused.diagnostics[0].message,/metadata.provider_unavailable/);assert.deepEqual(refused.committed,[]);assert.deepEqual(refused.projects,[]);
    assert.equal(treeIdentity(published),before,'Unavailable provider preserves published naming facts');
    writeFileSync(join(requestDirectory,'refused-'+request.format+'.json'),JSON.stringify(refused,null,2)+'\n');rmSync(path);
    for(const [style,key] of [['readable','generated'],['legacy','legacyGenerated']] as const) {
      const generated=request[key],snapshot=join(requestDirectory,style+'-'+ext);mkdirSync(snapshot,{recursive:true});
      for(const artifact of generated.artifacts)writeFileSync(join(snapshot,artifact.path),typeof artifact.content==='string'?artifact.content:Buffer.from(artifact.content));
      if(binary) {
        for(const artifact of generated.artifacts)assert.deepEqual(readFileSync(join(snapshot,artifact.path)),readFileSync(join(requestDirectory,style+'-ion',artifact.path)),'Both Ion restorations produce the same library');
        continue;
      }
      assert.ok(generated.manifest.includes('consumed_naming_facts'));assert.ok(generated.manifest.includes('provider_revision'));
      consumers[style].push({id:'requests',path:snapshot,module:generated.module,rows:[
        {id:'chosen',function:'chosen',arguments:[],expected:true},
        {id:'copy',function:style==='legacy'?hexName('example:main#copy'):'copy',arguments:[],expected:true},
        {id:'wanted',function:style==='legacy'?hexName('example:main#wanted'):'wanted',arguments:[],expected:false},
      ]});
    }
  }
  const consumerLanes=[];
  const sdk=deps.find(d=>d.startsWith('finos/morphir-sdk='))!.slice('finos/morphir-sdk='.length);
  for(const [style,libraries] of Object.entries(consumers)) {
    const workspace=join(root,'naming-consumers-'+style);mkdirSync(workspace);
    cpSync(sdk,join(workspace,'sdk'),{recursive:true,filter:path=>includeDependencyPath(sdk,path,excluded)});
    const members=['./sdk','./consumer'],imports=[],tests=[];
    for(const library of libraries) {
      const directory='model-'+library.id;cpSync(library.path,join(workspace,directory),{recursive:true});members.push('./'+directory);
      const alias='named_'+library.id;imports.push(JSON.stringify(library.module)+' @'+alias);
      for(const row of library.rows)tests.push(`///|\ntest "${library.id}-${row.id}" { assert_eq(@${alias}.${row.function}()${row.arguments.map(arg=>'('+arg+')').join('')}, ${row.expected}) }\n`);
    }
    assert.equal(tests.length,26);
    const consumer=join(workspace,'consumer');mkdirSync(consumer);
    writeFileSync(join(consumer,'moon.mod'),'name="acceptance/naming-consumer"\nversion="0.0.0"\nimport { '+libraries.map(l=>JSON.stringify(l.module+'@0.0.0')).join(', ')+' }\n');
    writeFileSync(join(consumer,'moon.pkg'),'import { '+imports.join(', ')+' }\n');writeFileSync(join(consumer,'consumer_test.mbt'),tests.join('\n'));
    writeFileSync(join(workspace,'moon.work'),'members='+JSON.stringify(members)+'\n');
    for(const [target,{compilerHome,env,capability}] of compilers)for(const mode of ['debug','release']) {
      const result=run(join(compilerHome,'bin/moon'),['test','--frozen','--target',target,'-p','acceptance/naming-consumer',...(mode==='release'?['--release']:[])],{cwd:workspace,env});
      assert.match(result.stdout,new RegExp(`Total tests: ${tests.length}, passed: ${tests.length}, failed: 0`));
      writeFileSync(join(output,'consumer-'+style+'-'+target+'-'+mode+'.log'),result.stdout+'\n'+result.stderr);
      consumerLanes.push({style,target,mode,rows:tests.length,compilerIdentity:capability.compilerIdentity,coreIdentity:capability.coreIdentity});
    }
  }
  const summary={profile:'morphir-installed-naming-v1',package:pack.integrity,frontendPolicy:fixtures.frontendPolicy,backendPolicy:fixtures.backendPolicy,requiredTargets:required,qualified,consumerLanes,historical,sourceRowsPerLane:20,historicalRowsPerLane:3,consumerRowsPerLane:26,checkpointFormats:['ion-text','ion-binary'],warningsWithoutLogs:true,loggingNeutral:true,strictPublicationPreserved:true,unknownMetadataPreserved:true,jsonLossRejected:true,requestedTargetHost:fixtures.provider,installedProviderUnavailable:true};
  writeFileSync(join(output,'summary.json'),JSON.stringify(summary,null,2)+'\n');
  return summary;
}
