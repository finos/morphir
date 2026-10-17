import { npmCli } from '../../../tests/npm.ts';
import type { Json } from '../../../types/data.ts';
import type { PipelineReport } from '../../../tests/cli-contracts.ts';
interface Client { id: string; program: string; prefix: string[]; }
interface MetadataEvent {
  profile: string; project: string; phase: string; outcome: string; operation: string;
  evidence: { native_revision: string; service_verified: boolean; profile_verified: boolean; service_sha256: string };
}
interface Grant {
  profile: string; workspace: string;
  runtime: { node: string; nodeSha256: string; helper: string; helperBundleSha256: string };
  projects: { project: string; service: string; serviceSha256: string; policy: string; lock: string; registry: string; state: string }[];
}
interface SignedBody { version: number; expires: string; keys: Record<string,{ keyval: { public: string } }>; }
interface Envelope { signed: SignedBody; signatures: { keyid: string; sig: string }[]; }
interface Lock { graph: { nodes: { contentDigest: string }[] }; evidence: { kind: string; path: string; digest: string }[]; }
type Scenario = ReturnType<typeof scenario>;
import assert from 'node:assert/strict';
import {spawnSync,spawn} from 'node:child_process';
import {createPrivateKey,createPublicKey,sign,verify} from 'node:crypto';
import {mkdirSync,writeFileSync,readFileSync,cpSync,existsSync,readdirSync,chmodSync,rmSync,realpathSync} from 'node:fs';
import {join,relative,delimiter,dirname,basename} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {hash,fileIdentity,treeIdentity,excluded} from '../build-provider/identity.mts';
import {includeDependencyPath} from '../build-provider/paths.mts';
import {capabilities} from '../build-provider/capabilities.mts';
import {isQuiescent} from '../build-provider/test-process-quiescence.mts';

// Invoked by installed-provider-check.mbtx. JSON is the explicit test-control
// bridge; the orchestrator validates binary Ion audit logs and writes the receipt.
const [selectedRoot,service,exporter,native,rustRevision,receipts,selectedRustCompiler,selectedServiceBuildMode]=process.argv.slice(2);
assert.ok([selectedRoot,service,exporter,native,rustRevision,receipts].every(Boolean));
assert.ok(['debug','release'].includes(selectedServiceBuildMode||'debug'));
if(selectedRustCompiler)assert.match(selectedRustCompiler,/^rustc \d+\.\d+\.\d+/);
const root=realpathSync(selectedRoot!);
const repo=fileURLToPath(new URL('../../../',import.meta.url));
const home=process.env.MOON_HOME;assert.ok(home,'Explicit pinned MOON_HOME required');
assert.ok(['linux','darwin'].includes(process.platform),'Only Unix installed lanes are selected');
const moon=join(home,'bin/moon');
const env: NodeJS.ProcessEnv={...process.env,MOON_HOME:home,MOONBIT_NEW_NATIVE:'0',PATH:join(home,'bin')+delimiter+process.env.PATH};
delete env.MOON_WORK;
function run(program: string,args: string[],{cwd=root,status=0}={}) {
  const result=spawnSync(program,args,{cwd,env,encoding:'utf8',timeout:240000,maxBuffer:16*1024*1024});
  assert.equal(result.error,undefined,String(result.error));
  assert.equal(result.status,status,result.stderr+'\n'+result.stdout);
  return result;
}
const jsonFile=(path: string,value: unknown)=>writeFileSync(path,JSON.stringify(value,null,2)+'\n');
const readJson=<T = Json>(path: string): T=>JSON.parse(readFileSync(path,'utf8'));
const pin=(path: string)=>'sha256:'+fileIdentity(path);
const npm=(args: string[],cwd: string)=>run(npmCli?process.execPath:'npm',npmCli?[npmCli,...args]:args,{cwd});
const pack=JSON.parse(npm(['pack','--json','--pack-destination',root],join(repo,'apps/morphir')).stdout)[0];
const installation=join(root,'installation');mkdirSync(installation);
npm(['install','--offline','--ignore-scripts','--no-audit','--no-fund','--prefix',installation,join(root,pack.filename)],root);
const installed=join(installation,'node_modules/@morphir/morphir');
assert.ok(!existsSync(join(installed,'scripts')),'Package does not depend on repository test scripts');
const helper=join(installed,'build-provider/metadata.mjs');
const bundleIdentity=(directory: string)=>hash(JSON.stringify(['WindowsJob.cs','metadata.mjs','supervision.mjs','windows-job.mjs','windows-job.ps1'].map(name=>[name,fileIdentity(join(directory,name))])));
const helperBundle=bundleIdentity(join(installed,'build-provider'));
const capability=capabilities({compilerHome:home,timeout:10000});
assert.match(capability.compilerIdentity,/^[a-f0-9]{64}$/);assert.match(capability.coreIdentity,/^[a-f0-9]{64}$/);
const template=readFileSync(join(repo,'apps/morphir/fixtures/authenticated-provider/main.ion'),'utf8');
const predicate='morphir://ir/pkg/morphir/naming?format=4.1.0';
const auditFiles: Json[]=[],checkpointFiles: Json[]=[],rows: Record<string, Json>[]= [];

function scenario(client: Client,name: string,{before=()=>{},variant='compatible'}: { before?: (fixture: string) => void; variant?: string } = {}) {
  console.error(`[installed-provider] ${client.id}: ${name}`);
  const directory=join(root,client.id+'-'+name);mkdirSync(directory);
  const fixture=join(directory,'fixture');
  run(exporter!,[fixture,'--provision-test-trust','--variant',variant]);
  before(fixture);
  const revision=fileIdentity(join(fixture,'native.json'));
  const workspace=join(directory,'workspace');mkdirSync(workspace);
  writeFileSync(join(workspace,'morphir.toml'),'[workspace]\nmembers=["one","two"]\n');
  const grant: Grant={profile:'morphir-metadata-host-grants-v1',workspace,runtime:{node:process.execPath,nodeSha256:pin(process.execPath),helper,helperBundleSha256:'sha256:'+helperBundle},projects:[]};
  for(const project of ['one','two']) {
    const path=join(workspace,project);mkdirSync(join(path,'src'),{recursive:true});
    const paths={service: service!,policy:join(fixture,'trust-policy.json'),lock:join(fixture,'morphir.lock'),registry:join(fixture,'registry'),state:join(fixture,'test-state')};
    const manifest='[project]\nname='+JSON.stringify(project)+'\n[frontend]\nlanguage="ion-text"\n[pipeline]\nbackend="moonbit"\nvalidation="source-only"\n[metadata]\nprovider="shared-local-restore"\nassurance="portable"\n'+Object.entries(paths).map(([k,v])=>k+'='+JSON.stringify(relative(path,v!))).join('\n')+'\n[metadata.naming]\nrelease="example.com/morphir/naming@1.0.0"\n';
    writeFileSync(join(path,'morphir.toml'),manifest);
    writeFileSync(join(path,'src/main.ion'),template.replace('NATIVE_REVISION',revision));
    grant.projects.push({project,...paths,serviceSha256:pin(service!)}!);
  }
  const grants=join(directory,'grants.ion');jsonFile(grants,grant);
  const args=(extra: string[])=>[...client.prefix,'run','.','--all','--metadata-grants',grants,...extra,'--json'];
  const invoke=(extra: string[]=[],status=0)=>{
    const result=run(client.program,args(extra),{cwd:workspace,status});
    return JSON.parse(result.stdout) as PipelineReport;
  };
  const outputs=()=>treeIdentity(join(workspace,'.morphir/out'));
  const changeSource=(mutate: (source: string) => string)=>{
    for(const project of ['one','two']) {
      const path=join(workspace,project,'src/main.ion');writeFileSync(path,mutate(readFileSync(path,'utf8')));
    }
  };
  const changeConfig=(mutate: (source: string) => string)=>{
    for(const project of ['one','two']) {
      const path=join(workspace,project,'morphir.toml');writeFileSync(path,mutate(readFileSync(path,'utf8')));
    }
  };
  const saveGrant=()=>jsonFile(grants,grant);
  const accept=()=>{
    const report=invoke();assert.equal(report.successful,true);assert.equal(report.processed,2);
    assert.ok(!existsSync(join(workspace,'.morphir/logs')),'Logging is off by default');
    return report;
  };
  const refuse=(code: RegExp,extra: string[]=[],expectAudit=true,unconfirmed=false)=>{
    const before=outputs();const log=join(directory,'refused.jsonl');
    const report=invoke(['--log-file',log,'--log-format','json-lines',...extra],extra.includes('--cancel-file')?130:1);
    assert.equal(report.successful,false);assert.deepEqual(report.committed,[]);
    assert.match(JSON.stringify(report),code);assert.equal(outputs(),before,'Refusal preserves every published byte');
    const events: MetadataEvent[]=existsSync(log)?readFileSync(log,'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line)).filter(e=>e.profile==='morphir-metadata-invocation-v1'):[];
    if(expectAudit&&!extra.includes('--cancel-file'))assert.ok(events.some(e=>e.outcome==='refused'||e.outcome==='cancelled'),'Typed refusal audit evidence');
    if(!unconfirmed)assert.ok(events.filter(e=>e.phase==='cleanup').every(e=>e.outcome==='started'||e.outcome==='succeeded'));
    jsonFile(join(receipts!,client.id+'-'+name+'.json'),{report,audit:events});
    rows.push({client:client.id,case:name,refused:true,publicationPreserved:true,diagnostic:code.source,auditRecords:events.length});
    return events;
  };
  return {directory,fixture,workspace,revision,grant,saveGrant,args,invoke,outputs,changeSource,changeConfig,accept,refuse};
}

function seedOutputs(s: Scenario,positive: Scenario) {
  // Saved published artifacts are only the preservation oracle. Never copy a
  // trust database, authentication receipt, retained frame or provider response.
  mkdirSync(join(s.workspace,'.morphir'),{recursive:true});
  cpSync(join(positive.workspace,'.morphir/out'),join(s.workspace,'.morphir/out'),{recursive:true});
}

function freshlyAuthenticated(s: Scenario,audit: MetadataEvent[]) {
  const projects=[...new Set(audit.map(e=>e.project))];assert.equal(projects.length,2);
  return projects.map(project=>{
    const events=audit.filter(e=>e.project===project);
    const restored=events.filter(e=>e.phase==='restore'&&e.outcome==='succeeded');
    const decoded=events.filter(e=>e.phase==='decode'&&e.outcome==='succeeded');
    assert.equal(restored.length,1);assert.equal(decoded.length,1);
    assert.ok(events.indexOf(restored[0]!)<events.indexOf(decoded[0]!));
    assert.equal(decoded[0]!.evidence.native_revision,s.revision);
    assert.equal(decoded[0]!.evidence.service_verified,true);
    assert.equal(decoded[0]!.evidence.profile_verified,true);
    assert.equal(decoded[0]!.evidence.service_sha256,fileIdentity(service!));
    const refused=events.findIndex(e=>e.outcome==='refused');
    assert.ok(refused>events.indexOf(decoded[0]!),'Fresh authentication and decode precede refusal');
    return events;
  });
}

function contextImport(s: Scenario,reference: string,base='morphir://ir/pkg/morphir/naming?format=4.1.0&rev=sha256:'+s.revision+'#/distribution') {
  s.changeSource(text=>text.replace('$meta:', 'contextBase:'+JSON.stringify(base)+', $meta:')
    .replace("'@context': {targetNames:","'@context': ["+JSON.stringify(reference)+", {targetNames:")
    .replace("'@type': \"@json\"}}, '@graph'","'@type': \"@json\"}}], '@graph'"));
}

async function blockedRestore(client: Client,name: string,cancel: boolean,positive: Scenario) {
  const s=scenario(client,name);seedOutputs(s,positive);const before=s.outputs();
  const marker=join(s.directory,'restore-child.json'),stop=join(s.directory,'cancel');
  const wrapper=join(s.directory,'blocked-service.cjs');
  // The real service answers the probe. During restore it receives an incomplete
  // request and waits for EOF while an additional child remains live. No fake
  // authenticated response can be admitted, and the host must quiesce the tree.
  writeFileSync(wrapper,'#!/usr/bin/env node\n'+`
const fs=require('node:fs'),{spawn,spawnSync}=require('node:child_process');
const chunks=[];process.stdin.on('data',b=>chunks.push(b));process.stdin.on('end',()=>{
 const input=Buffer.concat(chunks);
 if(input.includes(Buffer.from('morphir_provider_capabilities_request_v1'))){
  const result=spawnSync(${JSON.stringify(service)},[],{input});
  process.stdout.write(result.stdout);process.stderr.write(result.stderr);process.exitCode=result.status;
 }else{
  const child=spawn(${JSON.stringify(service)},[],{stdio:['pipe','ignore','ignore']});
  child.stdin.write(input.subarray(0,4));
  const extra=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'});
  fs.writeFileSync(${JSON.stringify(marker)},JSON.stringify({service:child.pid,descendant:extra.pid,wrapper:process.pid}));
  setInterval(()=>{},1000);
 }
});\n`);chmodSync(wrapper,0o755);
  s.changeConfig(text=>text.replace(JSON.stringify(relative(join(s.workspace,'one'),service!)),JSON.stringify(relative(join(s.workspace,'one'),wrapper))));
  s.grant.projects.forEach(p=>{p.service=wrapper;p.serviceSha256=pin(wrapper);});s.saveGrant();
  const log=join(s.directory,'events.jsonl');
  const args=s.args(['--metadata-timeout','20000','--log-file',log,'--log-format','json-lines',...(cancel?['--cancel-file',stop]:[])]);
  const start=performance.now();
  const child=spawn(client.program,args,{cwd:s.workspace,env,stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='',pids: Record<string,number> | undefined;
  const done=new Promise<{ code: number | null; signal: NodeJS.Signals | null }>((resolve,reject)=>{child.on('error',reject);child.on('close',(code,signal)=>resolve({code,signal}));});
  child.stdout.on('data',bytes=>{stdout+=bytes;assert.ok(stdout.length<1024*1024);});
  child.stderr.on('data',bytes=>{stderr+=bytes;assert.ok(stderr.length<1024*1024);});
  const watchdog=setTimeout(()=>child.kill('SIGTERM'),35000);
  try {
    while(!existsSync(marker)&&performance.now()-start<18000&&child.exitCode===null)await new Promise(resolve=>setTimeout(resolve,20));
    assert.ok(existsSync(marker),'Real restore process reached the deliberate block: '+stderr);
    pids=readJson<Record<string,number>>(marker);
    if(cancel)writeFileSync(stop,'');
    const result=await done;assert.equal(result.signal,null,stderr);assert.equal(result.code,cancel?130:1,stdout+'\n'+stderr);
    assert.ok(performance.now()-start<30000,'Operation and cleanup remain bounded');
    const report=JSON.parse(stdout);assert.equal(report.successful,false);assert.deepEqual(report.committed,[]);
    assert.match(JSON.stringify(report),cancel?/Cancelled/:/execution\.deadline|metadata\.restore_deadline/);
    assert.equal(s.outputs(),before);
    for(const pid of Object.values(pids))assert.ok(isQuiescent(pid),'Blocked tree quiescent before return');
    const audit: MetadataEvent[]=readFileSync(log,'utf8').trim().split('\n').map(line => JSON.parse(line)).filter(e=>e.profile==='morphir-metadata-invocation-v1');
    assert.ok(audit.some(e=>e.phase==='restore'&&e.outcome==='started'));
    assert.ok(!audit.some(e=>e.phase==='restore'&&e.outcome==='succeeded'));
    assert.ok(audit.some(e=>e.phase==='cleanup'&&e.outcome==='succeeded'));
    jsonFile(join(receipts!,client.id+'-'+name+'.json'),{report,audit,elapsedMs:performance.now()-start});
    rows.push({client:client.id,case:name,testOnlyBlockingProxySha256:fileIdentity(wrapper),realServiceProbe:true,partialRestoreInput:true,publicationPreserved:true,descendantsQuiescent:true});
  } finally {
    clearTimeout(watchdog);
    if(!pids&&existsSync(marker))pids=readJson<Record<string,number>>(marker);
    // Only our explicitly recorded fixture children are eligible for emergency cleanup.
    if(pids)for(const pid of Object.values(pids))if(!isQuiescent(pid))try{process.kill(pid,'SIGKILL');}catch{}
    if(child.exitCode===null)child.kill('SIGKILL');
  }
}

function unconfirmedCleanup(client: Client,positive: Scenario) {
  const s=scenario(client,'unconfirmed-cleanup');seedOutputs(s,positive);
  const directory=join(s.directory,'fault-helper');cpSync(join(installed,'build-provider'),directory,{recursive:true});
  const helper=join(directory,'metadata.mjs'),marker=join(s.directory,'retained-scratch.json');
  const original=readFileSync(helper,'utf8'),needle=/\b(?:const|let|var) complete\s*=\s*receipt\(\{\s*result:\s*["\']succeeded["\'],/;
  assert.equal((original.match(new RegExp(needle.source,'g')) ?? []).length,1,'Fault injection is tied to the selected helper source');
  writeFileSync(helper,original.replace(needle,match=>`if(input.includes(Buffer.from('morphir_provider_snapshot_request_v1'))){quiescent=false;const marker=${JSON.stringify(marker)};const roots=existsSync(marker)?JSON.parse(readFileSync(marker,'utf8')):[];roots.push(root);writeFileSync(marker,JSON.stringify(roots));}\n  `+match));
  s.grant.runtime.helper=helper;s.grant.runtime.helperBundleSha256='sha256:'+bundleIdentity(directory);s.saveGrant();
  const audit=s.refuse(/metadata\.restore_cleanup_unconfirmed/,[],true,true);
  assert.ok(audit.some(e=>e.phase==='cleanup'&&e.outcome==='refused'));
  const scratchRoots=readJson<string[]>(marker).map(path=>realpathSync(path));assert.ok(scratchRoots.length>0);
  const ownedRoots=scratchRoots.map(scratch=>{
    const owned=dirname(scratch);
    assert.equal(basename(scratch),'restore');assert.match(basename(owned),/^morphir-toolchain-/);
    assert.equal(dirname(owned),realpathSync(tmpdir()));
    assert.ok(existsSync(join(scratch,'request.ionb')));assert.ok(existsSync(join(scratch,'response.ionb')),'Scratch retained even though real service completed');
    return owned;
  });
  Object.assign(rows.at(-1)!,{testOnlyHelperBundleSha256:bundleIdentity(directory),realSignedRestore:true,publicationBlocked:true,scratchRetained:true});
  // The test injected a false quiescence result after the real service ended.
  // Its positively identified scratch can now be removed by the test owner.
  for(const owned of ownedRoots)rmSync(owned,{recursive:true});
}

function compileConsumer(s: Scenario,client: Client) {
  for(const project of ['one','two']) {
    const workspace=join(s.directory,'consumer-'+project);mkdirSync(workspace);
    const sdk=join(repo,'pkgs/morphir-sdk');
    cpSync(sdk,join(workspace,'sdk'),{recursive:true,filter:path=>includeDependencyPath(sdk,path,excluded)});
    const source=join(s.workspace,'.morphir/out',project,'compile.dest/main');
    const generated=readFileSync(join(source,'library.mbt'),'utf8');
    assert.match(generated,/pub fn authenticated_ready\(/);assert.match(generated,/authenticated_ready\(\)/);
    assert.ok(!/pub fn ready\(/.test(generated),'Public source name is replaced by the admitted target name');
    cpSync(source,join(workspace,'library'),{recursive:true});
    assert.equal(treeIdentity(join(workspace,'library')),treeIdentity(source),'Consume exact generated files, including their original module identity');
    const manifest=readFileSync(join(source,'moon.mod'),'utf8');
    const module=manifest.match(/^name\s*=\s*"([^"]+)"/m)![1],version=manifest.match(/^version\s*=\s*"([^"]+)"/m)![1];
    mkdirSync(join(workspace,'consumer'));
    writeFileSync(join(workspace,'moon.work'),'members=["./sdk","./library","./consumer"]\n');
    writeFileSync(join(workspace,'consumer/moon.mod'),'name="qualification/consumer"\nversion="0.0.0"\nimport {'+JSON.stringify(module+'@'+version)+'}\n');
    writeFileSync(join(workspace,'consumer/moon.pkg'),'import {'+JSON.stringify(module)+' @model}\n');
    writeFileSync(join(workspace,'consumer/consumer_test.mbt'),'///|\ntest "independent signed API contract" {\n  assert_eq(@model.authenticated_ready(), true)\n  assert_eq(@model.copy(), true)\n  assert_eq(@model.wanted(), false)\n}\n');
    for(const target of ['js','native']) {
      console.error(`[installed-provider] ${client.id}: compile ${project} consumer for ${target}`);
      const result=run(moon,['test','consumer','--frozen','--target',target],{cwd:workspace});
      assert.match(result.stdout,/Total tests: 1, passed: 1, failed: 0/);
      writeFileSync(join(receipts!,basename(s.directory)+'-consumer-'+project+'-'+target+'.log'),result.stdout+'\n'+result.stderr);
    }
  }
}

// Independently sign ASCII/integer test metadata using the published fixture key.
// This helper only accepts the known test root; it cannot sign a selected user's registry.
function timestamp(fixture: string,mutate: (body: SignedBody) => void) {
  const path=join(fixture,'registry/metadata/timestamp.json');
  const envelope=readJson<Envelope>(path),root=readJson<Envelope>(join(fixture,'registry/metadata/1.root.json'));
  const key=createPrivateKey({key:Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),Buffer.alloc(32,42)]),format:'der',type:'pkcs8'});
  const publicKey=createPublicKey(key);const id=envelope.signatures[0]!.keyid;
  assert.equal(publicKey.export({format:'der',type:'spki'}).subarray(-32).toString('hex'),root.signed.keys[id]!.keyval.public);
  const canonical=(value: unknown)=>JSON.stringify(value,(_,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
  mutate(envelope.signed);
  const bytes=Buffer.from(canonical(envelope.signed));
  envelope.signatures[0]!.sig=sign(null,bytes,key).toString('hex');
  assert.ok(verify(null,bytes,publicKey,Buffer.from(envelope.signatures[0]!.sig,'hex')));
  const result=Buffer.from('\n '+canonical(envelope)+'\n');writeFileSync(path,result);
  return result;
}

for(const client of [{id:'npm',program:process.execPath,prefix:[join(installed,'bin/morphir.js')]},{id:'native',program:native!,prefix:[]}]) {
  const positive=scenario(client,'signed');positive.accept();compileConsumer(positive,client);
  const before=positive.outputs();
  assert.equal(positive.invoke(['--log']).successful,true);assert.equal(positive.outputs(),before);
  const binary=join(positive.workspace,'.morphir/logs/frontend.ionb');
  assert.deepEqual([...readFileSync(binary).subarray(0,4)],[224,1,0,234]);
  const retained=join(receipts!,client.id+'-audit.ionb');cpSync(binary,retained);
  auditFiles.push({path:retained,client:client.id,serviceSha256:fileIdentity(service!),revision:positive.revision,projects:2});
  const log=join(receipts!,client.id+'-audit.jsonl');
  assert.equal(positive.invoke(['--log-file',log,'--log-format','json-lines']).successful,true);assert.equal(positive.outputs(),before);
  const events: MetadataEvent[]=readFileSync(log,'utf8').trim().split('\n').map(line => JSON.parse(line)).filter(e=>e.profile==='morphir-metadata-invocation-v1');
  assert.equal(new Set(events.map(e=>e.operation)).size,2);assert.equal(new Set(events.map(e=>e.project)).size,2);
  const admitted=events.filter(e=>e.phase==='admission'&&e.outcome==='succeeded');assert.equal(admitted.length,2);
  assert.ok(admitted.every(e=>e.evidence.native_revision===positive.revision&&e.evidence.service_verified&&e.evidence.profile_verified));
  rows.push({client:client.id,case:'signed',projects:2,nativeRevision:positive.revision,independentConsumerTargets:['js','native'],loggingNeutral:true,binaryAudit:true});

  const cases: [string,(scenario: Scenario) => void,RegExp,boolean?][]=[
    ['revision',s=>s.changeSource(text=>text.replace(s.revision,'0'.repeat(64))),/metadata\.provider_revision_mismatch/],
    ['service-pin',s=>{s.grant.projects.forEach(p=>p.serviceSha256='sha256:'+'0'.repeat(64));s.saveGrant();},/metadata\.restore_executable_changed/],
    ['project-isolation',s=>{s.grant.projects.pop();s.saveGrant();},/metadata\.restore_project_not_granted/],
    ['release',s=>s.changeConfig(text=>text.replace('naming@1.0.0','naming@2.0.0')),/metadata\.restore_release_mismatch/],
    ['policy',s=>{const path=join(s.fixture,'trust-policy.json'),value=readJson<{publisherRules: {publicKeys: string[]}[]}>(path);value.publisherRules[0]!.publicKeys=['00'.repeat(32)];jsonFile(path,value);},/metadata\.restore_authentication_failed/],
    ['lock',s=>{const path=join(s.fixture,'morphir.lock'),value=readJson<Lock>(path);value.graph.nodes[0]!.contentDigest='sha256:'+'0'.repeat(64);jsonFile(path,value);},/metadata\.restore_authentication_failed/],
    ['payload',s=>{const bundle=readdirSync(join(s.fixture,'registry/bundles'))[0];const path=join(s.fixture,'registry/bundles',bundle!,'ir.json');writeFileSync(path,readFileSync(path,'utf8')+' ');},/metadata\.restore_authentication_failed/],
    ['context-bytes',s=>{const bundle=readdirSync(join(s.fixture,'registry/bundles'))[0];writeFileSync(join(s.fixture,'registry/bundles',bundle!,'contexts/schema.jsonld'),'{}');},/metadata\.restore_authentication_failed/],
    ['signature',s=>{const path=join(s.fixture,'registry/metadata/timestamp.json'),value=readJson<Envelope>(path);value.signatures[0]!.sig='00'.repeat(64);jsonFile(path,value);},/metadata\.restore_authentication_failed/],
    ['expired',s=>timestamp(s.fixture,body=>{body.version=2;body.expires='2000-01-01T00:00:00Z';}),/metadata\.restore_authentication_failed/],
    ['context-escape',s=>contextImport(s,'../outside.jsonld'),/metadata\.restore_invalid_response: Context path escapes retained inventory/],
    ['context-missing',s=>contextImport(s,'./contexts/missing.jsonld'),/metadata\.restore_invalid_response: Context path is absent from retained inventory/],
    ['context-digest',s=>contextImport(s,'morphir://context/sha256/'+'0'.repeat(64)),/metadata\.restore_invalid_response: Context digest is absent from retained inventory/],
    ['context-base',s=>contextImport(s,'./contexts/schema.jsonld','unknown://base'),/metadata\.restore_invalid_response: Unknown context base/],
    ['invalid-name',s=>s.changeSource(text=>text.replace('"authenticated_ready"','42')),/metadata\.invalid_string/,false],
    ['interrupted-state',s=>writeFileSync(join(s.fixture,'test-state/operation'),'interrupted'),/metadata\.restore_authentication_failed/],
  ];
  for(const [name,mutate,code,expectAudit=true] of cases) {
    const s=scenario(client,name);seedOutputs(s,positive);mutate!(s);const audit=s.refuse(code,[],expectAudit!);
    if(name==='revision')assert.equal(audit.filter(e=>e.phase==='restore'&&e.outcome==='succeeded').length,2,'A pin is checked after fresh restoration');
    console.log('Installed signed provider '+client.id+' '+name+' passed');
  }
  // Signatures establish provenance. Consumer declarations still require admission.
  for(const [variant,code] of [
    ['wrong-type',/metadata\.invalid_provider_type/],
    ['wrong-subject-role',/metadata\.invalid_provider_declaration/],
    ['wrong-object-form',/metadata\.invalid_provider_declaration/],
    ['wrong-interpreter',/metadata\.invalid_provider_declaration/],
  ] as const) {
    const s=scenario(client,variant!,{variant});seedOutputs(s,positive);
    const audit=s.refuse(code!);
    for(const events of freshlyAuthenticated(s,audit)) {
      const refused=events.filter(e=>e.phase==='admission'&&e.outcome==='refused');
      assert.equal(refused.length,1);
      assert.equal(refused[0]!.evidence.native_revision,s.revision);
      assert.equal(refused[0]!.evidence.service_verified,true);
      assert.equal(refused[0]!.evidence.profile_verified,true);
      assert.ok(!events.some(e=>e.phase==='admission'&&e.outcome==='succeeded'));
    }
    Object.assign(rows.at(-1)!,{signedVariant:variant,freshAuthentication:true,decodedNativeRevision:s.revision,semanticAdmissionRefused:true});
  }
  const ambiguous=scenario(client,'context-ambiguous',{variant:'ambiguous-contexts'});seedOutputs(ambiguous,positive);
  const contextBytes=readFileSync(join(ambiguous.fixture,'contexts/schema.jsonld'));
  assert.deepEqual(readFileSync(join(ambiguous.fixture,'contexts/alias.jsonld')),contextBytes);
  contextImport(ambiguous,'morphir://context/sha256/'+hash(contextBytes));
  const ambiguousAudit=ambiguous.refuse(/metadata\.restore_invalid_response: Ambiguous context digest: use an inventory-relative reference from its admitted base/);
  for(const events of freshlyAuthenticated(ambiguous,ambiguousAudit)) {
    assert.ok(events.some(e=>e.phase==='context'&&e.outcome==='refused'));
    assert.ok(!events.some(e=>e.phase==='admission'&&e.outcome==='succeeded'));
  }
  Object.assign(rows.at(-1)!,{signedVariant:'ambiguous-contexts',freshAuthentication:true,contextSha256:hash(contextBytes)});
  const relativeReferences=[];
  for(const path of ['schema.jsonld','alias.jsonld']) {
    const s=scenario(client,'context-relative-'+path,{variant:'ambiguous-contexts'});
    contextImport(s,'./contexts/'+path);
    s.accept();compileConsumer(s,client);relativeReferences.push('./contexts/'+path);
  }
  rows.push({client:client.id,case:'context-relative-disambiguation',signedVariant:'ambiguous-contexts',relativeReferences,admittedNativeBase:true,projects:2,independentConsumerTargets:['js','native']});

  const rollback=scenario(client,'rollback',{before:fixture=>{
    const newer=timestamp(fixture,body=>{body.version=2;});
    writeFileSync(join(fixture,'registry/metadata/2.timestamp.json'),newer);
    const path=join(fixture,'morphir.lock'),lock=readJson<Lock>(path),evidence=lock.evidence.find(e=>e.kind==='tuf-timestamp');
    evidence!.path='metadata/2.timestamp.json';evidence!.digest='sha256:'+hash(newer);jsonFile(path,lock);
  }});
  rollback.accept();
  cpSync(join(rollback.fixture,'registry/metadata/1.timestamp.json'),join(rollback.fixture,'registry/metadata/timestamp.json'));
  rollback.refuse(/metadata\.restore_authentication_failed/);

  const noFacts=scenario(client,'unused');noFacts.changeSource(text=>text.replace(predicate,'morphir://ir/pkg/other/metadata?format=4.1.0'));
  // A deliberately unusable service proves no probe/restore is needed for unknown facts.
  noFacts.grant.projects.forEach(p=>p.serviceSha256='sha256:'+'0'.repeat(64));noFacts.saveGrant();
  const trust=treeIdentity(join(noFacts.fixture,'test-state'));assert.equal(noFacts.invoke().successful,true);
  assert.equal(treeIdentity(join(noFacts.fixture,'test-state')),trust);
  const planning=scenario(client,'planning');
  const state=treeIdentity(join(planning.fixture,'test-state'));
  const dry=planning.invoke(['--dry-run','--log']);
  assert.equal(dry.boundaries.length,2);assert.ok(dry.boundaries.every(b=>b.readBytes===false));
  assert.equal(treeIdentity(join(planning.fixture,'test-state')),state);assert.ok(!existsSync(join(planning.workspace,'.morphir')));
  const listed=run(client.program!,[...client.prefix,'project','list','.','--json'],{cwd:planning.workspace});assert.ok(listed.stdout);
  assert.equal(treeIdentity(join(planning.fixture,'test-state')),state);assert.ok(!existsSync(join(planning.workspace,'.morphir')));
  rows.push({client:client.id,case:'no-facts-and-planning',noAcquisition:true,trustUnchanged:true});

  const rich=scenario(client,'ion');rich.changeSource(text=>text.replace('$meta:', 'opaque: qualification_rich_metadata::{amount:1.20,when:2026-10-15T00:00:00Z,bytes:{{AP8=}},nil:null.int}, $meta:'));
  for(const [format,extension] of [['ion-text','ion'],['ion-binary','ionb']] as const) {
    assert.equal(rich.invoke(['--backend','checkpoint','--checkpoint-format',format]).successful,true);
    const checkpoint=join(rich.workspace,'.morphir/out/one/compile.dest/main.'+extension);
    const retained=join(receipts!,client.id+'-metadata.'+extension);cpSync(checkpoint,retained);
    checkpointFiles.push({path:retained,format,client:client.id}!);
  }
  const checkpointHash=rich.outputs();
  const loss=rich.invoke(['--backend','checkpoint','--checkpoint-format','morphir-json'],1);
  assert.match(JSON.stringify(loss),/data\.lossy_conversion/);assert.deepEqual(loss.committed,[]);assert.equal(rich.outputs(),checkpointHash);
  rich.changeSource(text=>text.split(', metadata:')[0]+', metadata: []}\n');
  assert.equal(rich.invoke(['--backend','checkpoint','--checkpoint-format','morphir-json']).successful,true);
  const json=readJson(join(rich.workspace,'.morphir/out/one/compile.dest/main.json'));assert.ok(json);
  rows.push({client:client.id,case:'ion-and-json',richIonRetained:true,checkedJsonLossRefused:true,morphirJsonSupported:true,publicationPreserved:true});

  const cancelled=scenario(client,'cancelled');seedOutputs(cancelled,positive);
  const cancellation=join(cancelled.directory,'stop');writeFileSync(cancellation,'');
  cancelled.refuse(/Cancelled/,['--cancel-file',cancellation]);
  await blockedRestore(client,'cancel-during-restore',true,positive);
  await blockedRestore(client,'restore-deadline',false,positive);
  unconfirmedCleanup(client,positive);
}
assert.equal(rows.length,60,'Complete installed qualification coverage for both clients');
const summary={profile:'morphir-installed-authenticated-v1',rustRevision,packageIntegrity:pack.integrity,cliNativeSha256:fileIdentity(native!),cliJsSha256:fileIdentity(join(installed,'dist/morphir.js')),cliBuildMode:'release',nodeSha256:fileIdentity(process.execPath),node:process.version,platform:process.platform,arch:process.arch,serviceSha256:fileIdentity(service!),serviceBuildMode:selectedServiceBuildMode||'debug',rustCompiler:selectedRustCompiler||run('rustc',['--version']).stdout.trim(),fixtureExporterSha256:fileIdentity(exporter!),modelSha256:hash(template),helperBundleSha256:helperBundle,compilerIdentity:capability.compilerIdentity,coreIdentity:capability.coreIdentity,executionProfile:'local-library-mvp',profileVersion:'0.1.0-draft.1',assurance:'portable',rows,auditFiles,checkpointFiles,remaining:[],completeTask6:true};
jsonFile(join(receipts!,'bridge.json'),summary);
console.log('Installed signed provider checks passed for npm and native clients.');
