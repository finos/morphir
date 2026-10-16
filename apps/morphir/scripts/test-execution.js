import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,existsSync,mkdirSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {capabilities} from '../build-provider/capabilities.mjs';
const repo=fileURLToPath(new URL('../../../',import.meta.url));
const app=join(repo,'apps/morphir');
const home=process.env.MOON_HOME;
const npmCli=process.env.npm_execpath || (process.platform==='win32'?join(dirname(process.execPath),'node_modules/npm/bin/npm-cli.js'):null);
const npm=(args,cwd)=>execFileSync(npmCli?process.execPath:'npm',npmCli?[npmCli,...args]:args,{cwd,encoding:'utf8',maxBuffer:4*1024*1024});
assert.ok(home,'Supply pinned MOON_HOME');
const moon=join(home,'bin/moon');
const root=mkdtempSync(join(tmpdir(),'morphir-execution-test-'));
const run=(program,args,expected=0)=>{
  const result=spawnSync(program,args,{cwd:repo,encoding:'utf8',timeout:180000,maxBuffer:4*1024*1024});
  assert.equal(result.error,undefined);assert.equal(result.status,expected,result.stderr+'\n'+result.stdout);return result;
};
try {
  const fixture=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-moonbit/acceptance']).stdout);
  const model=join(root,'model.json'), suite=join(root,'calls.ion'), binary=join(root,'calls.ionb');
  writeFileSync(model,fixture.invocationIR);writeFileSync(binary,Buffer.from(fixture.invocationSuite));
  writeFileSync(suite,'{profile:"morphir-invocations-v1",calls:[{id:"subtract",entry:"calls:main#subtract",arguments:[9007199254741035,9007199254740993]},{id:"boolean",entry:"calls:main#boolean",arguments:[false]},{id:"unit",entry:"calls:main#unit",arguments:[morphir_unit::null]}]}');
  const helper=join(app,'build-provider/execution.mjs');
  const dependencies=['finos/morphir-sdk=pkgs/morphir-sdk','finos/morphir-execution=pkgs/morphir-execution','moonrockz/ion=.mooncakes/moonrockz/ion','moonbitlang/x=.mooncakes/moonbitlang/x','moonbitlang/async=.mooncakes/moonbitlang/async'].flatMap(v=>['--dependency',v]);
  const options=['--home',home,...dependencies];
  const targets=['js','wasm-gc',...(['darwin','linux'].includes(process.platform)?['native']:[])];
  const llvmHome=process.env.MORPHIR_LLVM_HOME, llvmPin=process.env.MORPHIR_LLVM_PIN;
  assert.equal(Boolean(llvmHome),Boolean(llvmPin),'Supply both MORPHIR_LLVM_HOME and MORPHIR_LLVM_PIN');
  if(llvmHome)targets.push('llvm');
  const targetOptions=target=>target==='llvm'?['--home',llvmHome,'--toolchain-pin',llvmPin,...dependencies]:options;
  run(moon,['build','--target','js']);run(moon,['build','--target','native']);
  const js=join(repo,'_build/js/debug/build/morphir/morphir/morphir.js');
  const native=join(repo,'_build/native/debug/build/morphir/morphir/morphir.exe');
  for(const [program,prefix] of [[process.execPath,[js]],[native,[]]]) {
    for(const target of targets) {
    const log=join(root,(prefix.length?'node':'native')+'-'+target+'.ionb');
    const result=JSON.parse(run(program,[...prefix,'verify',model,'--suite',suite,'--execution-helper',helper,...targetOptions(target),'--target',target,'--log-file',log,'--json']).stdout);
    assert.equal(result.successful,true);assert.equal(result.calls[0].actual.value,'42');assert.equal(result.calls[1].actual.value,false);assert.equal(result.calls[2].actual.type,'unit');
    assert.deepEqual([...readFileSync(log).subarray(0,4)],[0xe0,1,0,0xea]);
    assert.equal(result.target,target);assert.equal(result.evidence.capability.backend,target==='native'?'c':target);
    assert.equal(result.evidence.capability.protocol,'morphir-invocations-v1/ion-binary');
    assert.ok(!existsSync(result.evidence.executable),'Disposed session retains executable');
    }
    const dry=join(root,'dry-log');
    const plan=JSON.parse(run(program,[...prefix,'verify',model,'--suite',suite,'--dry-run','--log-file',dry,'--json']).stdout);
    assert.equal(plan.dryRun,true);assert.ok(!existsSync(dry));
    const invalid=join(root,'invalid.ion');writeFileSync(invalid,'{profile:"morphir-invocations-v1",calls:[{id:"x",entry:"calls:main#private",arguments:[]}]}');
    assert.match(run(program,[...prefix,'verify',model,'--suite',invalid,'--execution-helper',helper,...options,'--json'],2).stderr,/entry_not_public_or_supported/);
  }
  const lines=run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',helper,...options,'--log-file',join(root,'events.jsonl'),'--log-format','json-lines','--json-lines']).stdout.trim().split('\n').map(JSON.parse);
  assert.ok(lines.length>0);assert.ok(lines.every(l=>l.profile!=='morphir-observation-v1'));
  const events=readFileSync(join(root,'events.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  assert.ok(events.some(e=>e.stage==='invoke'));
  const call=events.find(e=>e.stage==='call');assert.ok(call);
  assert.match(call.trace_id,/^[a-f0-9]{32}$/);assert.match(call.span_id,/^[a-f0-9]{16}$/);
  assert.equal(call.parent_id,events.find(e=>e.stage==='invoke'&&e.signal==='started').span_id);
  assert.equal(call.correlation.call_id,'subtract');assert.equal(call.correlation.attempt_id,'1');
  assert.equal(call.correlation.target,'js');assert.ok(call.duration_seconds>=0);assert.ok(events.every(e=>!JSON.stringify(e).includes('9007199254741035')));
  // A failing optional sink cannot alter parity or result framing.
  const failedSink=JSON.parse(run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',helper,...options,'--log-file',join(root,'absent','log.ionb'),'--json']).stdout);
  assert.equal(failedSink.successful,true);
  assert.match(run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',helper,...options,'--target','llvm','--json'],2).stderr,/unsupported_target/);
  assert.match(run(process.execPath,[js,'verify',model,'--suite',binary,'--telemetry-adapter','opentelemetry','--json'],2).stderr,/adapter_unavailable/);
  if(llvmHome) {
    const dryLLVM=JSON.parse(run(process.execPath,[js,'verify',model,'--suite',binary,'--target','llvm','--toolchain-pin',llvmPin,'--dry-run','--json']).stdout);
    assert.equal(dryLLVM.target,'llvm');assert.equal(dryLLVM.capabilityVerification,'deferred');
    const badPin=join(root,'bad-pin.json'),pin=JSON.parse(readFileSync(llvmPin,'utf8'));
    writeFileSync(badPin,JSON.stringify({...pin,compilerIdentity:'0'.repeat(64)}));
    assert.match(run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',helper,'--home',llvmHome,'--toolchain-pin',badPin,...dependencies,'--target','llvm','--json'],2).stderr,/compiler_identity/);
  }
  const unverifiedPin=join(root,'unverified-pin.json');
  for(const targets of [['js'],['js','llvm']]) {
    writeFileSync(unverifiedPin,JSON.stringify({profile:'morphir-toolchain-pin-v1',compilerVersion:'0.10.15+1e9f6672d-nightly',compilerIdentity:'a'.repeat(64),coreIdentity:'b'.repeat(64),platform:'darwin',arch:'arm64',targets}));
    assert.match(run(process.execPath,[js,'verify',model,'--suite',suite,'--target','js','--toolchain-pin',unverifiedPin,'--dry-run','--json'],2).stderr,/unverified_(stable|llvm)_pin/);
  }
  // Corrupt one real driver's typed result to prove the CLI mismatch exit status.
  const wrapper=join(root,'capture.mjs'),capture=join(root,'captured.json');
  writeFileSync(wrapper,`import {readFileSync,writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';import {spawnSync} from 'node:child_process';
const request=JSON.parse(readFileSync(process.argv[2],'utf8'));
if(request.operation==='build')writeFileSync(${JSON.stringify(capture)},JSON.stringify(request));
const result=spawnSync(process.execPath,[${JSON.stringify(helper)},process.argv[2]],{encoding:'utf8',maxBuffer:4194304});
if(result.status===0&&request.operation==='invoke') {
 const file=join(dirname(process.argv[2]),'outcomes.ionb'),bytes=readFileSync(file);
 const at=bytes.indexOf(Buffer.from([0x21,42]));if(at<0)throw Error('Expected exact Ion integer 42');
 bytes[at+1]=43;writeFileSync(file,bytes);
}
process.stdout.write(result.stdout);process.stderr.write(result.stderr);process.exitCode=result.status;
`);
  const brokenTrace=join(root,'broken-trace.mjs');
  writeFileSync(brokenTrace,`import {readFileSync,writeFileSync} from 'node:fs';import {dirname,join} from 'node:path';import {spawnSync} from 'node:child_process';
const request=JSON.parse(readFileSync(process.argv[2],'utf8'));
const result=spawnSync(process.execPath,[${JSON.stringify(helper)},process.argv[2]],{encoding:'utf8',maxBuffer:4194304});
if(result.status===0&&request.operation==='invoke') {
 const path=join(dirname(process.argv[2]),'outcomes.ionb'), bytes=readFileSync(path), at=bytes.indexOf(Buffer.from(request.traceparent));
 if(at<0)throw Error('Expected propagated trace');bytes[at+3]=bytes[at+3]===49?50:49;writeFileSync(path,bytes);
}
process.stdout.write(result.stdout);process.stderr.write(result.stderr);process.exitCode=result.status;
`);
  const failedTrace=JSON.parse(run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',brokenTrace,...options,'--log-file',join(root,'broken-trace.jsonl'),'--log-format','json-lines','--json'],1).stdout);
  assert.equal(failedTrace.successful,false);assert.match(failedTrace.failure.cause,/outcome_identity/);
  assert.deepEqual(failedTrace.terminals.map(t=>t.id),['subtract']);assert.ok(failedTrace.terminals.every(t=>t.status==='failed'));
  const mismatch=JSON.parse(run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',wrapper,...options,'--json'],1).stdout);
  assert.equal(mismatch.successful,false);assert.equal(mismatch.calls[0].actual.value,'43');assert.equal(mismatch.calls[0].expected.value,'42');
  // Reuse a single retained executable for different runtime argument values.
  const lease=join(root,'reuse');mkdirSync(lease);
  const requestPath=join(lease,'request.json');
  const buildRequest={...JSON.parse(readFileSync(capture,'utf8')),leaseId:'reuse'};
  writeFileSync(requestPath,JSON.stringify(buildRequest));
  const built=JSON.parse(run(process.execPath,[helper,requestPath]).stdout);
  const executableBefore=readFileSync(built.executable);
  let attempt=0;
  for(const input of [fixture.invocationSuite,fixture.invocationSuite2]) {
    attempt++;
    const bytes=Buffer.from(input);writeFileSync(join(lease,'suite.ionb'),bytes);
    writeFileSync(requestPath,JSON.stringify({operation:'invoke',target:'js',attemptId:String(attempt),leaseId:'reuse',timeout:120000,suiteIdentity:createHash('sha256').update(bytes).digest('hex'),traceparent:'00-'+ '1'.repeat(32)+'-'+ '2'.repeat(16)+'-01'}));
    const receipt=JSON.parse(run(process.execPath,[helper,requestPath]).stdout);
    assert.equal(receipt.attemptId,String(attempt));
    assert.equal(receipt.traceparent,'00-'+ '1'.repeat(32)+'-'+ '2'.repeat(16)+'-01');
    assert.ok(readFileSync(join(lease,'outcomes.ionb')).includes(Buffer.from([0x21,42])));
    assert.deepEqual(readFileSync(built.executable),executableBefore);
  }
  const invoke={operation:'invoke',target:'js',attemptId:'3',leaseId:'reuse',timeout:120000,suiteIdentity:createHash('sha256').update(readFileSync(join(lease,'suite.ionb'))).digest('hex')};
  const helperCall=(request,expected=1)=>{writeFileSync(requestPath,JSON.stringify(request));return run(process.execPath,[helper,requestPath],expected);};
  assert.match(helperCall({...invoke,leaseId:'wrong'}).stderr,/wrong_lease/);
  assert.match(helperCall({...invoke,target:'native'}).stderr,/wrong_target/);
  assert.match(helperCall({...invoke,attemptId:'1'}).stderr,/wrong_attempt/);
  assert.match(helperCall({...invoke,traceparent:'00-'+ '0'.repeat(32)+'-'+ '1'.repeat(16)+'-01'}).stderr,/invalid_trace_context/);
  assert.match(helperCall(buildRequest).stderr,/already_built/);
  writeFileSync(built.executable,Buffer.concat([executableBefore,Buffer.from('changed')]));
  assert.match(helperCall(invoke).stderr,/changed_executable/);writeFileSync(built.executable,executableBefore);
  const statePath=join(lease,'session.json'), state=JSON.parse(readFileSync(statePath,'utf8'));
  writeFileSync(statePath,JSON.stringify({...state,evidence:{...state.evidence,capability:{...state.evidence.capability,arch:'wrong'}}}));
  assert.match(helperCall(invoke).stderr,/arch_mismatch/);writeFileSync(statePath,JSON.stringify(state));
  const wrong=join(lease,'wrong.js');writeFileSync(wrong,'');
  writeFileSync(statePath,JSON.stringify({...state,evidence:{...state.evidence,executable:wrong,executableIdentity:createHash('sha256').update(readFileSync(wrong)).digest('hex')}}));
  assert.match(helperCall(invoke).stderr,/missing_output/);
  writeFileSync(statePath,JSON.stringify(state));
  // A supervisor timeout cannot turn an incomplete invocation into success.
  const hung=join(lease,'hung.js');writeFileSync(hung,'while(true){}');
  writeFileSync(statePath,JSON.stringify({...state,evidence:{...state.evidence,executable:hung,executableIdentity:createHash('sha256').update(readFileSync(hung)).digest('hex')}}));
  assert.match(helperCall({...invoke,timeout:50}).stderr,/execution.deadline/);
  writeFileSync(statePath,JSON.stringify(state));
  const wasmCapability=capabilities({compilerHome:home,timeout:120000}).targets.find(c=>c.target==='wasm-gc');
  const moduleBytes=parts=>Buffer.from([0,97,115,109,1,0,0,0,...parts.flat()]);
  const section=(id,body)=>[id,body.length,...body], str=s=>[s.length,...Buffer.from(s)];
  const missing=join(lease,'missing.wasm');
  writeFileSync(missing,moduleBytes([section(1,[1,0x60,0,0]),section(2,[1,...str('bad'),...str('foo'),0,0])]));
  const wasmState=artifact=>({...state,evidence:{...state.evidence,target:'wasm-gc',capability:wasmCapability,executable:artifact,executableIdentity:createHash('sha256').update(readFileSync(artifact)).digest('hex')}});
  writeFileSync(statePath,JSON.stringify(wasmState(missing)));
  assert.match(helperCall({...invoke,target:'wasm-gc'}).stderr,/missing_import/);
  const loop=join(lease,'loop.wasm');
  writeFileSync(loop,moduleBytes([
    section(1,[2,0x60,0,1,0x7c,0x60,0,0]),
    section(2,[1,...str('morphir_execution_v1'),...str('monotonic'),0,0]),
    section(3,[1,1]),section(7,[1,...str('_start'),0,1]),
    section(10,[1,7,0,0x03,0x40,0x0c,0,0x0b,0x0b]),
  ]));
  writeFileSync(statePath,JSON.stringify(wasmState(loop)));
  assert.match(helperCall({...invoke,target:'wasm-gc',timeout:250}).stderr,/execution.deadline/);
  writeFileSync(statePath,JSON.stringify(state));
  rmSync(join(lease,'workspace'),{recursive:true});
  assert.match(helperCall(invoke).stderr,/ENOENT/);
  rmSync(lease,{recursive:true});
  // Install the actual packed CLI, including its process helpers.
  const packed=JSON.parse(npm(['pack','--json','--pack-destination',root],app))[0];
  const install=join(root,'install');mkdirSync(install);
  npm(['install','--ignore-scripts','--no-audit','--no-fund','--offline','--prefix',install,join(root,packed.filename)],repo);
  const installed=join(install,'node_modules/@morphir/morphir');
  for(const target of targets) {
  const output=JSON.parse(run(process.execPath,[join(installed,'bin/morphir.js'),'verify',model,'--suite',binary,'--execution-helper',join(installed,'build-provider/execution.mjs'),...targetOptions(target),'--target',target,'--json']).stdout);
  assert.equal(output.calls[0].actual.value,'42');assert.equal(output.successful,true);
  }
  console.log(JSON.stringify({successful:true,hosts:['native','node','installed-npm'],targets,llvm:llvmHome?'explicit-pin':'not-selected',exactIntegers:true,bool:true,unit:true,ionLogs:true,jsonLines:true,dryRun:true,failedSink:true,cleanup:true,mismatchExit:true,driverReuse:true}));
} finally {rmSync(root,{recursive:true,force:true});}
