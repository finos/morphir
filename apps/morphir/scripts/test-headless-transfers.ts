/** Actual installed SDK producer -> authenticated Rust host -> primary CLI ->
 * current ContentPublisher. Expected bytes predate these CLI observations. */
import assert from 'node:assert/strict';
import {spawn, type ChildProcess} from 'node:child_process';
import {once} from 'node:events';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,readdirSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {headlessEnvironment} from './headless-environment.ts';
const repo=fileURLToPath(new URL('../../../',import.meta.url));
const build=resolve(process.env.MORPHIR_HEADLESS_BUILD??join(repo,'_build'));
const target=process.argv[2]??process.env.MORPHIR_HEADLESS_TARGET??'js';
const profile=process.env.MORPHIR_HEADLESS_PROFILE??'debug';
const binary=resolve(process.env.MORPHIR_HEADLESS_BINARY??join(build,target,profile,'build/morphir/morphir',target==='native'?'morphir.exe':target==='js'?'morphir.js':'morphir.wasm'));
const launcher=resolve(process.env.MORPHIR_HEADLESS_LAUNCHER??join(repo,'apps/morphir/bin/morphir.js'));
const helper=resolve(process.env.MORPHIR_TRANSFER_HELPER??join(repo,'apps/morphir/build-provider/transfers.mjs'));
const connectedHelper=resolve(process.env.MORPHIR_CONNECTED_HELPER??join(repo,'apps/morphir/build-provider/connected.mjs'));
const fixture=process.env.MORPHIR_WORKBENCH_ARTIFACT_HOST;
const portable=target==='wasm'||target==='wasm-gc';
const node=process.execPath;
const runner=process.env.MORPHIR_HEADLESS_WASM_RUNNER??join(repo,'pkgs/morphir-host/runners/wasm.mjs');
const executable=target==='native'?binary:node;
const prefix=target==='native'?[]:target==='js'?[launcher]:[runner,binary];
const digest=(bytes:Uint8Array)=>createHash('sha256').update(bytes).digest('hex');
const scenarios=['download','binary','nul-text','digest','length','profile','stale-session','collision','cancel','cancel-after-release','timeout','timeout-before-generation','producer-lost'] as const;
const root=mkdtempSync(join(tmpdir(),'morphir-connected-transfers-'));
mkdirSync(join(root,'tmp'));
let host:ChildProcess|undefined;
function launch(args:string[],input?:string,selectedHelper=helper){
 const child=spawn(executable,[...prefix,...args,'--provider','workbench-http','--json'],{cwd:root,
  env:headlessEnvironment(join(root,'cli-environment'),{MORPHIR_HEADLESS_BINARY:binary,MORPHIR_TRANSFER_HELPER:selectedHelper,MORPHIR_CONNECTED_HELPER:connectedHelper,
   TMPDIR:join(root,'tmp'),TMP:join(root,'tmp'),TEMP:join(root,'tmp')}),stdio:['pipe','pipe','pipe']});
 let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);
 const done=new Promise<{code:number|null,signal:NodeJS.Signals|null,stdout:string,stderr:string}>(r=>child.once('close',(code,signal)=>r({code,signal,stdout,stderr})));
 child.once('error',()=>{});if(input!==undefined)child.stdin.end(input);else child.stdin.end();return{child,done};
}
try{
 if(!portable&&process.platform!=='win32'&&!process.env.MORPHIR_TRANSFER_SCENARIO){
  // Every retained/hung/lost case owns a fresh real host. A deliberately held
  // remote dispatch cannot contaminate the next fixture's producer capacity.
  for(const name of scenarios){
   const child=spawn(process.execPath,[fileURLToPath(import.meta.url),target],{
    env:headlessEnvironment(join(root,'scenario-environment'),{
     MORPHIR_TRANSFER_SCENARIO:name,MORPHIR_HEADLESS_BINARY:binary,MORPHIR_HEADLESS_LAUNCHER:launcher,
     MORPHIR_HEADLESS_WASM_RUNNER:runner,MORPHIR_TRANSFER_HELPER:helper,MORPHIR_CONNECTED_HELPER:connectedHelper,MORPHIR_WORKBENCH_ARTIFACT_HOST:fixture,
    }),stdio:'inherit',
   });
   const [code,signal]=await once(child,'exit');
   assert.equal(signal,null);assert.equal(code,0,`${name} isolated actual-host fixture`);
  }
 }
 else if(portable){const help=await launch(['connected','artifacts','--help']).done;assert.equal(help.code,0);const unavailable=await launch(['connected','artifacts','-','--connection','unused','--output','out'],'{}').done;assert.equal(unavailable.code,2);assert.match(unavailable.stdout+unavailable.stderr,/runtime_unavailable/);console.log(`${target} connected artifacts help/refusal passed`);}
 else if(process.platform==='win32'){
  const result=await launch(['connected','artifacts','-','--connection','unused','--output','saved'],'{}').done;
  assert.equal(result.signal,null);assert.equal(result.code,2);
  assert.equal(JSON.parse(result.stdout).error,target==='native'?'connected.runtime_unavailable':'connected.private_file_permissions_unavailable');
  assert.deepEqual(readdirSync(join(root,'tmp')),[]);assert.ok(!existsSync(join(root,'saved')));
  console.log(`${target} Windows connected artifact effect explicitly unavailable: passed`);
 }
 else{
  assert.ok(fixture,'Select exact real ui_artifact_process binary with MORPHIR_WORKBENCH_ARTIFACT_HOST');
  host=spawn(fixture,['--artifact-process-host',join(root,'host'),'download'],{
   cwd:root,env:headlessEnvironment(join(root,'host-environment')),stdio:['ignore','pipe','pipe']});
  let diagnostic='';host.stderr!.on('data',d=>diagnostic=(diagnostic+d).slice(-16384));
  const startup=await new Promise<Record<string,unknown>>((resolve,reject)=>{let text='';const deadline=setTimeout(()=>reject(new Error('Actual artifact host startup deadline')),20000);host!.once('error',reject);host!.once('exit',()=>reject(new Error('Actual artifact host failed: '+diagnostic)));host!.stdout!.on('data',d=>{text+=d;const end=text.indexOf('\n');if(end>=0){clearTimeout(deadline);resolve(JSON.parse(text.slice(0,end)));}});});
  const launchFile=join(root,'launch.txt'),connection=join(root,'connection.json');writeFileSync(launchFile,String(startup.launchUrl),{mode:0o600});
  const setup=await launch(['connected','connect',launchFile,'--connection',connection,'--connection-scope','artifacts']).done;
  assert.equal(setup.code,0,setup.stdout+setup.stderr);assert.equal(setup.signal,null);
  const credential=readFileSync(connection,'utf8');const secrets=[new URL(String(startup.launchUrl)).searchParams.get('token')!,JSON.parse(credential).cookie.split('=')[1]];
  const request={providerId:'playground',target:'artifact-process-fixture',irVersion:'4.0.0',ir:{},options:{}};
  const input=join(root,'request.json');writeFileSync(input,JSON.stringify(request));
  const events=()=>existsSync(join(String(startup.stateDirectory),'events'))?readFileSync(join(String(startup.stateDirectory),'events'),'utf8').trim().split('\n'):[];
  const assertClean=(result:{stdout:string,stderr:string})=>{for(const secret of secrets)assert.ok(!result.stdout.includes(secret)&&!result.stderr.includes(secret),'No terminal secret disclosure');assert.deepEqual(readdirSync(join(root,'tmp')),[],'Owned helper scratch removed');assert.equal(host!.exitCode,null,'CLI does not terminate selected host');};
  const selected=process.env.MORPHIR_TRANSFER_SCENARIO;
  for(const scenario of scenarios){
   if(selected&&selected!==scenario)continue;
   let diagnosticResult:Awaited<ReturnType<typeof launch>['done']>|undefined;
   try {
   const output='saved-'+scenario;const options=scenario==='timeout'?{fixtureMode:'hang'}:scenario==='cancel'?{fixtureMode:'binary'}:scenario==='producer-lost'?{fixtureMode:'lost'}:{fixtureMode:['binary','nul-text'].includes(scenario)?scenario:'download'};
   writeFileSync(input,JSON.stringify({...request,options}));let selectedHelper=helper;
   if(scenario==='timeout-before-generation'){
    selectedHelper=join(root,'slow-manifest-helper.mjs');
    // Exercise the real deadline before dispatch, independently of host speed.
    // The real fetch still observes the command's aborted signal.
    writeFileSync(selectedHelper,`import{readFileSync}from'node:fs';import{setTimeout}from'node:timers/promises';import{transferCommand as actualTransfer}from ${JSON.stringify(pathToFileURL(helper).href)};const fetch=globalThis.fetch;globalThis.fetch=async(...args)=>{await setTimeout(200);return fetch(...args);};export const transferCommand=actualTransfer;if(process.argv[2]==='--morphir-transfer-v1'){const result=await actualTransfer(JSON.parse(readFileSync(process.argv[3],'utf8')));console.log(JSON.stringify(result.report));process.exitCode=result.code;}`);
   }
   if(scenario==='digest'||scenario==='length'||scenario==='cancel-after-release'){
    selectedHelper=join(root,scenario+'-helper.mjs');
    const mutation=scenario==='digest'?"report.files.at(-1).sha256='0'.repeat(64)":scenario==='length'?"report.files.at(-1).byteLength++":'';
    const module=`import {readFileSync,existsSync} from 'node:fs';import{pathToFileURL}from'node:url';import{transferCommand}from ${JSON.stringify(pathToFileURL(helper).href)};export async function transferCommandMutant(raw,core,interrupted){const result=await transferCommand(raw,core,interrupted);const {report}=result;if(result.code===0){${mutation}}return result;}export{transferCommandMutant as transferCommand};if(process.argv[2]==='--morphir-transfer-v1'){const result=await transferCommandMutant(JSON.parse(readFileSync(process.argv[3],'utf8')));console.log(JSON.stringify(result.report));process.exitCode=result.code;}`;
    // Alias avoids exporting an imported binding twice under the same name.
    const forward=scenario==='cancel-after-release'?"await actualTransfer(raw,core,()=>Boolean(interrupted?.())||existsSync(raw.scratch+'/file-0'))":'await actualTransfer(raw,core,interrupted)';
    writeFileSync(selectedHelper,module.replace('import{transferCommand}from','import{transferCommand as actualTransfer}from').replace('await transferCommand(raw,core,interrupted)',forward));
   }
   if(scenario==='profile'||scenario==='stale-session'){
    const changed=JSON.parse(credential);if(scenario==='profile')changed.descriptor={...changed.descriptor,contractVersion:'0.1.0-draft.999'};else changed.sessionId='another-session';writeFileSync(connection,JSON.stringify(changed));
   }
   if(scenario==='collision'){mkdirSync(join(root,output,'artifacts'),{recursive:true});writeFileSync(join(root,output,'artifacts','keep.txt'),'existing');}
   const before=events().filter(e=>e.startsWith('generate ')).length;
   const invocation=launch(['connected','artifacts',scenario==='download'?'-':input,'--connection',connection,'--output',output,'--timeout',scenario==='timeout-before-generation'?'100':scenario==='timeout'?'5000':'120000'],scenario==='download'?JSON.stringify({...request,options}):undefined,selectedHelper);
   let interruptedAt=0;
   if(scenario==='cancel'){
    const deadline=Date.now()+15000;while(events().filter(e=>e.startsWith('generate ')).length===before){assert.ok(Date.now()<deadline,'Generation starts before interrupt');await new Promise(r=>setTimeout(r,20));}interruptedAt=Date.now();invocation.child.kill('SIGINT');
   }
   const result=await invocation.done;diagnosticResult=result;if(interruptedAt)assert.ok(Date.now()-interruptedAt<5000,'Interrupted CLI owns and closes its socket before deadline');assert.equal(result.signal,null);assertClean(result);const report=JSON.parse(result.stdout);
   if(['download','binary','nul-text'].includes(scenario)){
    assert.equal(result.code,0,result.stdout+result.stderr);assert.equal(report.observation,'published');assert.equal(report.publication,'cli');assert.equal(report.cleanup.kind,'released');
    const directory=join(root,output,'artifacts');
    const expected=scenario==='download'?['indexed.bin','original.txt','empty.bin']:Array.from({length:4},(_,i)=>`file-${i}.${scenario==='binary'?'bin':'txt'}`);
    assert.deepEqual(readdirSync(directory).sort(),expected.sort());
    for(const [index,name]of expected.entries()){
     const bytes=readFileSync(join(directory,name));const summary=report.files.find((f:{path:string})=>f.path===name);assert.equal(summary.byteLength,bytes.length);assert.equal(summary.sha256,digest(bytes));
     if(name==='indexed.bin'){assert.equal(bytes.length,1048833);assert.equal(digest(bytes),'fa651153f54c6b07a3b2d6543fdd2601cf423ebe8e5a5e0d278437e6ac5565e0');for(let i=0;i<bytes.length;i++)assert.equal(bytes[i],i%256^Math.floor(i/65536)%256);}
     else if(name==='original.txt')assert.deepEqual(bytes,Buffer.from('\ufeffOriginal\r\nline two\r\n'));
     else if(name==='empty.bin')assert.equal(bytes.length,0);
     else{assert.equal(bytes.length,16777216);if(scenario==='nul-text')assert.equal(bytes.some(b=>b!==0),false);else{const hashes=['728f52a85b49e21b090f8aab42eac87b30f1c82bdb3a3890627bc244de6756b0','d42312f945214c8f55c283c08415efdddb975c664bc7ae4b129a6c37b79b87c8','75e9210fb9b010ccd02fc3b824d482d6f1646aa3a5765baba3034423eb1550f7','d5f3e8e4c2a22852ec5d5aa01c92f7ad149031ea896fd3fd70887f425fc30d27'];assert.equal(digest(bytes),hashes[index]);}}
    }
   }else if(scenario==='collision'){assert.equal(result.code,2);assert.equal(readFileSync(join(root,output,'artifacts','keep.txt'),'utf8'),'existing');}
   else{assert.notEqual(result.code,0,result.stdout);assert.ok(!existsSync(join(root,output,'artifacts')),'Failure cannot publish a prefix');if(['digest','length'].includes(scenario))assert.equal(report.cleanup.kind,'released','Local publication refusal preserves confirmed remote release');if(scenario==='cancel')assert.equal(result.code,130);if(scenario==='cancel-after-release'){assert.equal(result.code,130);assert.equal(report.stopReason,'sigint');assert.equal(report.cleanup.kind,'released');}if(scenario==='timeout'||scenario==='timeout-before-generation'){assert.equal(result.code,1);assert.equal(report.stopReason,'timeout');}}
   const after=events().filter(e=>e.startsWith('generate ')).length;
   if(scenario==='timeout')assert.ok(after-before<=1,'A deadline may expire before dispatch, but cannot duplicate generation');
   else assert.equal(after-before,['collision','profile','stale-session','timeout-before-generation'].includes(scenario)?0:1,'Expected real producer invocation count');
   if(scenario==='timeout-before-generation')assert.equal(report.cleanup.kind,'not-connected');
   writeFileSync(connection,credential);
   if(scenario==='cancel'){
    assert.equal(report.cleanup.kind,'connection-closed','A lost in-flight generation has no confirmed release');
    assert.equal(report.cleanup.reason,'pending-exchange');
   }
   if(scenario==='producer-lost'){
    const pids=events().filter(e=>e.startsWith('generate ')).slice(before).map(e=>Number(e.split(' ')[1]));
    const end=Date.now()+5000;for(const pid of pids){for(;;){let alive=true;try{process.kill(pid,0);}catch{alive=false;}if(!alive)break;assert.ok(Date.now()<end,'Owned producer process joined after connection close');await new Promise(r=>setTimeout(r,20));}}
   }
   console.log(`${target} connected artifacts ${scenario}: passed`);
   } catch (error) {
    if (scenario==='timeout') {
     // Failure-only summary before the existing finally disposes this fixture.
     // No raw command output, credentials, request bodies or generation IDs.
     try {
      const object=(value:unknown):Record<string,unknown>|undefined=>value!==null&&typeof value==='object'&&!Array.isArray(value)?value as Record<string,unknown>:undefined;
      const selected=(value:unknown,allowed:readonly string[])=>typeof value==='string'&&allowed.includes(value)?value:value===undefined?'absent':'unrecognized';
      let raw:Record<string,unknown>|undefined;
      if(diagnosticResult&&diagnosticResult.stdout.length<=1048576){try{raw=object(JSON.parse(diagnosticResult.stdout));}catch{}}
      const cleanup=object(raw?.cleanup);
      const recorded=events(),tail=recorded.slice(-64);
      const eventCounts=Object.fromEntries(['start','generate','shutdown','exit'].map(kind=>[kind,tail.filter(line=>new RegExp('^'+kind+' [0-9]+$').test(line)).length]));
      let safeStderr=diagnostic;
      for(const secret of secrets)if(secret)safeStderr=safeStderr.split(secret).join('[redacted]');
      safeStderr=safeStderr.replace(/https?:\/\/[^\s"'<>]+/gi,'[redacted-url]')
       .replace(/\b(?:authorization|cookie|set-cookie)\b\s*[:=][^\r\n]*/gi,'[redacted-header]')
       .replace(/morphir_session_[A-Za-z0-9_-]{1,128}=[A-Za-z0-9_-]+/g,'[redacted-cookie]')
       .replace(/[A-Za-z0-9_-]{16,}/g,'[redacted-long-token]').slice(-4096);
      console.error(JSON.stringify({diagnostic:'headless-transfer-timeout-v1',scenario,target,timeoutMs:5000,
       result:diagnosticResult?{code:diagnosticResult.code,signal:diagnosticResult.signal,stdoutCharacters:diagnosticResult.stdout.length,stderrCharacters:diagnosticResult.stderr.length}:{kind:'not-settled'},
       report:{observation:selected(raw?.observation,['not-published','discarded','generation-failed','verified','published','refused','helper-lost','cleanup-unconfirmed']),
        stopReason:selected(raw?.stopReason,['sigint','timeout','cancel-file']),
        error:selected(raw?.error,['transfer.transport_unavailable','transfer.invalid_request','transfer.provider_changed','transfer.profile_unavailable','transfer.verification_failed','transfer.producer_failed','connected.session_changed','connected.offer_changed','transfer.scratch_cleanup_failed']),
        cleanup:{kind:selected(cleanup?.kind,['not-connected','not-retained','released','connection-closed']),reason:selected(cleanup?.reason,['pending-exchange','unknown-retention','release-failed']),
         generationId:cleanup&&Object.hasOwn(cleanup,'generationId')?cleanup.generationId===null?'null':typeof cleanup.generationId==='string'?'present':'unrecognized':'absent'}},
       events:{totalLines:recorded.length,inspectedLast:tail.length,counts:eventCounts,unrecognizedInTail:tail.filter(line=>!/^(start|generate|shutdown|exit) [0-9]+$/.test(line)).length},
       timing:{kind:'stage-timings-not-captured-by-existing-fixture'},
       host:{exitCode:host!.exitCode,signal:host!.signalCode,stderrTail:safeStderr}}));
     } catch {try{console.error('{"diagnostic":"headless-transfer-timeout-v1","summary":"unavailable"}');}catch{}}
    }
    throw error;
   }
  }
  console.log(JSON.stringify({producerHost:fixture,sha256:digest(readFileSync(fixture)),target}));
 }
}finally{if(host&&host.exitCode===null&&host.signalCode===null){host.kill('SIGTERM');await once(host,'exit');}rmSync(root,{recursive:true,force:true});}
