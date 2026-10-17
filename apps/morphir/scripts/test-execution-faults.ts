import type { VerificationReport } from '../../../tests/cli-contracts.ts';
import { workbenchError } from '../../../types/data.ts';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {isQuiescent} from '../build-provider/test-process-quiescence.mts';
const repo=fileURLToPath(new URL('../../../',import.meta.url));
const root=mkdtempSync(join(tmpdir(),'morphir-execution-faults-'));
const home=process.env.MOON_HOME;
assert.ok(home,'Supply pinned MOON_HOME');
const moon=join(home,'bin/moon');
let orphanPid: number | undefined;
async function recoverOrphan() {
  if(orphanPid===undefined)return;
  if(!isQuiescent(orphanPid))process.kill(-orphanPid,'SIGKILL');
  const deadline=performance.now()+2000;
  while(!isQuiescent(orphanPid)) {
    assert.ok(performance.now()<deadline,'recovery stopped the owned runner');
    await new Promise(resolve=>setTimeout(resolve,10));
  }
  orphanPid=undefined;
}
const run=(program: string,args: string[],{expected=0,fault=''}={})=>{
  const result=spawnSync(program,args,{cwd:repo,encoding:'utf8',timeout:180000,maxBuffer:4*1024*1024,env:{...process.env,MORPHIR_EXECUTION_FAULT:fault}});
  assert.equal(result.error,undefined);assert.equal(result.status,expected,result.stderr+'\n'+result.stdout);return result;
};
try {
  const fixture=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-moonbit/acceptance']).stdout);
  const model=join(root,'model.json'),suite=join(root,'calls.ion');
  writeFileSync(model,fixture.invocationIR);
  writeFileSync(suite,'{profile:"morphir-invocations-v1",calls:[{id:"subtract",entry:"calls:main#subtract",arguments:[5,3]},{id:"boolean",entry:"calls:main#boolean",arguments:[false]},{id:"unit",entry:"calls:main#unit",arguments:[morphir_unit::null]}]}');
  run(moon,['build','--target','js']);
  run(moon,['build','--target','native']);
  const helper=join(repo,'apps/morphir/build-provider/execution.mjs');
  const mutator=join(repo,'_build/js/debug/build/finos/morphir-host/acceptance/protocol-fault/protocol-fault.js');
  const wrapper=join(root,'fault.mjs'),leaseFile=join(root,'lease'),pidFile=join(root,'descendant.pid'),cancelFile=join(root,'cancel');
  writeFileSync(wrapper,`import {readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import {dirname,join} from 'node:path';import {spawn,spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
const path=process.argv[2],request=JSON.parse(readFileSync(path,'utf8')),root=dirname(path),fault=process.env.MORPHIR_EXECUTION_FAULT;
if(request.operation==='build')writeFileSync(${JSON.stringify(leaseFile)},root);
if(request.operation==='invoke') {
  if(fault==='helper-sigkill') {
    // The runner owns a separate process group, as in the real supervisor.
    const runner=spawn(process.execPath,['-e',"const fs=require('fs');fs.writeFileSync("+JSON.stringify(${JSON.stringify(pidFile)})+",String(process.pid));setInterval(()=>{fs.readFileSync("+JSON.stringify(path)+");},10)"],{detached:true,stdio:'ignore'});
    runner.unref();
    await new Promise((resolve,reject)=>{const deadline=Date.now()+2000;const poll=setInterval(()=>{try{readFileSync(${JSON.stringify(pidFile)});clearInterval(poll);resolve();}catch{if(Date.now()>deadline){clearInterval(poll);reject(Error('runner did not start'));}}},5);});
    process.kill(process.pid,'SIGKILL');
  }
  const statePath=join(root,'session.json'),state=JSON.parse(readFileSync(statePath,'utf8'));
  if(fault==='source'||fault==='dependency'){
    const source=join(root,fault==='source'?'workspace/generated/moon.mod':'workspace/dependency0/moon.mod');
    writeFileSync(source,readFileSync(source,'utf8')+'\\n// mutated');
  }
  if(['cancelled','deadline','diagnostics'].includes(fault)) {
    const runner=join(root,'fault-runner.cjs');
    const descendant="require('fs').writeFileSync("+JSON.stringify(${JSON.stringify(pidFile)})+",String(process.pid));setInterval(()=>{},1000)";
    const code=fault==='diagnostics'?"process.stderr.write('x'.repeat(1048577));setInterval(()=>{},1000)":
      "const fs=require('fs');require('child_process').spawn(process.execPath,['-e',"+JSON.stringify(descendant)+"],{stdio:'ignore'});"+
      (fault==='cancelled'?"const poll=setInterval(()=>{if(fs.existsSync("+JSON.stringify(${JSON.stringify(pidFile)})+")){fs.writeFileSync("+JSON.stringify(${JSON.stringify(cancelFile)})+",'');clearInterval(poll);}},5);":"")+"setInterval(()=>{},1000)";
    writeFileSync(runner,code);state.evidence.executable=runner;state.evidence.executableIdentity=createHash('sha256').update(code).digest('hex');
    writeFileSync(statePath,JSON.stringify(state));
    if(fault==='deadline'){request.timeout=400;writeFileSync(path,JSON.stringify(request));}
  }
}
const result=spawnSync(process.execPath,[${JSON.stringify(helper)},path],{encoding:'utf8',maxBuffer:4194304});
let stdout=result.stdout;
if(request.operation==='invoke'&&['tree-failure','cancel-tree-failure','outer-timeout'].includes(fault)&&result.status===0){
 result.status=fault==='outer-timeout'?124:1;result.stderr=(fault==='cancel-tree-failure'?'execution.cancelled':'execution.deadline')+'; execution.tree_termination_failed';
}
if(result.status===0&&request.operation==='invoke') {
  if(fault.startsWith('receipt-')){
    const receipt=JSON.parse(stdout),field=fault.slice(8);receipt[field]='wrong';stdout=JSON.stringify(receipt);
  }else if(fault==='absent'){unlinkSync(join(root,'outcomes.ionb'));}
  else {
    const changed=spawnSync(process.execPath,[${JSON.stringify(mutator)},join(root,'outcomes.ionb'),fault],{encoding:'utf8'});
    if(changed.status!==0)throw Error(changed.stderr);
  }
}
process.stdout.write(stdout);process.stderr.write(result.stderr);process.exitCode=result.status;
`);
  const dependencies=['finos/morphir-sdk=pkgs/morphir-sdk','finos/morphir-execution=pkgs/morphir-execution','moonrockz/ion=.mooncakes/moonrockz/ion','moonbitlang/x=.mooncakes/moonbitlang/x','moonbitlang/async=.mooncakes/moonbitlang/async'].flatMap(v=>['--dependency',v]);
  const js=join(repo,'_build/js/debug/build/morphir/morphir/morphir.js');
  const native=join(repo,'_build/native/debug/build/morphir/morphir/morphir.exe');
  const faults=['truncated','malformed','oversize','absent','missing','extra','duplicate','reordered','wrong-id','duration','value','wrong-suite','wrong-profile','wrong-trace','extensions','duplicate-field',
    ...['leaseId','target','attemptId','suiteIdentity','executableIdentity'].map(f=>'receipt-'+f),'source','dependency','diagnostics','tree-failure','cancel-tree-failure','outer-timeout'];
  const verified=[];
  for(const [host,program,prefix] of [['node',process.execPath,[js]],['native',native,[]]] as const) {
    if(process.env.MORPHIR_TEST_HOST&&process.env.MORPHIR_TEST_HOST!==host)continue;
    for(const fault of [...faults,...(process.platform==='win32'?[]:['cancelled','deadline','helper-sigkill'])]) {
      if(process.env.MORPHIR_TEST_FAULT&&process.env.MORPHIR_TEST_FAULT!==fault)continue;
      rmSync(cancelFile,{force:true});rmSync(pidFile,{force:true});
      const log=join(root,host+'-'+fault+'.jsonl');
      let result;
      try {
        result=run(program!,[...prefix,'verify',model,'--suite',suite,'--execution-helper',wrapper,'--home',home,...dependencies,'--target','js','--cancel-file',cancelFile,'--log-file',log,'--log-format','json-lines','--json'],{expected:1,fault});
      } finally {
        if(fault==='helper-sigkill'&&existsSync(pidFile))orphanPid=Number(readFileSync(pidFile,'utf8'));
      }
      const report: VerificationReport=JSON.parse(result.stdout);
      assert.equal(report.successful,false,host+': '+fault);
      assert.ok(report.failure,host+': '+fault);
      const treeFailure=fault.endsWith('tree-failure')||fault==='outer-timeout'||fault==='helper-sigkill';
      if(treeFailure)assert.match(report.failure.cleanup!,/execution.tree_cleanup_pending/);else assert.equal(report.failure.cleanup,null,host+': '+fault);
      assert.deepEqual(report.terminals.map(t=>t.id),['subtract','boolean','unit']);
      assert.ok(report.terminals.every(t=>t.status===(fault.startsWith('cancel')?'cancelled':'failed')));
      assert.ok(report.failure.cause.length<=512);
      const lease=readFileSync(leaseFile,'utf8');
      assert.equal(existsSync(lease),treeFailure,'only uncertain tree cleanup retains scratch');
      if(fault==='helper-sigkill') {
        assert.ok(!isQuiescent(orphanPid!),'real runner survives abrupt helper death');
        assert.ok(existsSync(join(lease,'request.json')),'runner input remains available for recovery');
        // The test acts as the operator, stopping the runner before deleting scratch.
        await recoverOrphan();
      }
      if(treeFailure)rmSync(lease,{recursive:true,force:true});
      if(['cancelled','deadline'].includes(fault)) {
        assert.ok(existsSync(pidFile),'real runner descendant started');
        const pid=Number(readFileSync(pidFile,'utf8'));
        assert.ok(isQuiescent(pid),'descendant quiescent before CLI completed');
        assert.match(report.failure.cause,fault==='cancelled'?/Cancelled/:/execution.deadline/);
      }
      const events=readFileSync(log,'utf8').trim().split('\n').map(line => JSON.parse(line));
      for(const started of events.filter(e=>e.signal==='started')) {
        const terminal=events.filter(e=>e.span_id===started.span_id&&['succeeded','failed','cancelled'].includes(e.signal));
        assert.equal(terminal.length,1,host+': '+fault+' '+started.stage);
        assert.equal(terminal[0].trace_id,started.trace_id);assert.equal(terminal[0].parent_id,started.parent_id);
      }
      verified.push(host+':'+fault);
    }
  }
  assert.ok(verified.length>0,'at least one selected fault was exercised');
  // Separate CLI processes overlap their sessions and drains without sharing a
  // global observer/provider. Each owns its lease, trace, sequence and log file.
  const concurrent=await Promise.all(Array.from({length:4},(_,i)=>new Promise<Record<string,unknown>>((resolve,reject)=>{
    const log=join(root,'concurrent-'+i+'.jsonl');
    const [program,prefix]=i%2?[native,[]]:[process.execPath,[js]];
    const child=spawn(program,[...prefix,'verify',model,'--suite',suite,'--execution-helper',helper,'--home',home,...dependencies,'--target','js','--log-file',log,'--log-format','json-lines','--json'],{cwd:repo,env:process.env});
    let stdout='',stderr='';const timer=setTimeout(()=>{child.kill('SIGKILL');reject(Error('concurrent CLI deadline'));},180000);
    child.stdout.on('data',b=>stdout+=b);child.stderr.on('data',b=>stderr+=b);child.once('error',reject);
    child.once('close',code=>{clearTimeout(timer);try {
      assert.equal(code,0,stderr);const report: VerificationReport=JSON.parse(stdout);assert.equal(report.successful,true);
      assert.ok(!existsSync(report.evidence.executable!));
      const events=readFileSync(log,'utf8').trim().split('\n').map(line => JSON.parse(line));
      const runs=new Set(events.map(e=>e.run_id)),traces=new Set(events.map(e=>e.trace_id));
      assert.equal(runs.size,1);assert.equal(traces.size,1);
      assert.ok(events.filter(e=>e.stage==='call').every(e=>e.correlation.lease_id===report.evidence.leaseId));
      resolve({run:[...runs][0],trace:[...traces][0],lease:report.evidence.leaseId});
    }catch(error){reject(error);}});
  })));
  for(const key of ['run','trace','lease'])assert.equal(new Set(concurrent.map(c=>c[key])).size,4,key+' is independently owned');
  console.log(JSON.stringify({successful:true,faults:verified.length,hosts:[...new Set(verified.map(v=>v.split(':')[0]))],processTrees:process.platform==='win32'?'not-tested':'posix',terminalStatuses:true,stageTerminals:true,failedLeasesDisposed:true,uncertainTreeCleanupRetainsScratch:true,concurrentContexts:4}));
} finally {
  await recoverOrphan();
  const capture=join(root,'lease');
  if(existsSync(capture))rmSync(readFileSync(capture,'utf8'),{recursive:true,force:true});
  rmSync(root,{recursive:true,force:true});
}
