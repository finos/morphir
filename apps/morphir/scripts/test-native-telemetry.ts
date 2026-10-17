import { npmCli } from '../../../tests/npm.ts';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
interface Invocation { code: number | null; stdout: string; stderr: string; milliseconds: number; }
interface Span { name: string; traceId: string; spanId: string; parentSpanId: string; startTimeUnixNano: string; endTimeUnixNano: string; }
interface Log { traceId: string; spanId: string; }
interface Point { attributes: { key: string; value: { stringValue: string } }[]; asInt: string; }
interface Metric { name: string; sum: { dataPoints: Point[] }; }
interface Payload {
  resourceSpans?: { scopeSpans: { spans: Span[] }[] }[];
  resourceLogs?: { scopeLogs: { logRecords: Log[] }[] }[];
  resourceMetrics?: { scopeMetrics: { metrics: Metric[] }[] }[];
}
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir,cpus,release} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createServer} from 'node:http';
import {performance} from 'node:perf_hooks';
const repo=fileURLToPath(new URL('../../../',import.meta.url));
const home=process.env.MOON_HOME,binary=process.env.MORPHIR_OTEL_BINARY,pin=process.env.MORPHIR_OTEL_PIN;
assert.ok(home&&binary&&pin,'Supply pinned compiler and explicit native adapter binary/pin');
const root=mkdtempSync(join(tmpdir(),'morphir-native-telemetry-'));
const receipts=resolve(process.env.MORPHIR_TELEMETRY_RECEIPTS||join(root,'receipts'));mkdirSync(receipts,{recursive:true});
function run(program: string,args: string[],cwd=repo) {
  const r=spawnSync(program,args,{cwd,encoding:'utf8',timeout:240000,maxBuffer:16*1024*1024});assert.equal(r.error,undefined);assert.equal(r.status,0,r.stderr);return r.stdout;
}
let server: Server | undefined;
try {
  const fixture=JSON.parse(run(join(home,'bin/moon'),['run','--target','js','pkgs/morphir-moonbit/acceptance']));
  const model=join(root,'model.json'),cases=join(root,'cases.ion');
  writeFileSync(model,fixture.conformanceIR);writeFileSync(cases,readFileSync(join(repo,'pkgs/morphir-moonbit/fixtures/execution/conformance-cases.ion')));
  const npm=npmCli;
  const npmRun=(args: string[],cwd: string)=>run(npm?process.execPath:'npm',npm?[npm,...args]:args,cwd);
  const pack=JSON.parse(npmRun(['pack','--json','--pack-destination',root],join(repo,'apps/morphir')))[0];
  const installation=join(root,'install');mkdirSync(installation);
  npmRun(['install','--offline','--ignore-scripts','--no-audit','--no-fund','--prefix',installation,join(root,pack.filename)],root);
  const app=join(installation,'node_modules/@morphir/morphir'),cli=join(app,'bin/morphir.js');
  const deps=['finos/morphir-sdk=pkgs/morphir-sdk','finos/morphir-execution=pkgs/morphir-execution','moonrockz/ion=.mooncakes/moonrockz/ion','moonbitlang/x=.mooncakes/moonbitlang/x','moonbitlang/async=.mooncakes/moonbitlang/async'].flatMap(v=>{const [name,path]=v.split('=');return ['--dependency',name+'='+join(repo,path!)];});
  const args=[cli,'conform',model,'--cases',cases,'--home',home,'--execution-helper',join(app,'build-provider/execution.mjs'),...deps,'--json'];
  const cwd=join(root,'empty-cwd');mkdirSync(cwd);
  const requests: { path?: string; body: Payload }[]=[];let hang=false;
  server=createServer(async(req,res)=>{
    const chunks: Buffer[]=[];let size=0;
    for await(const c of req){size+=c.length;assert.ok(size<4*1024*1024);chunks.push(c);}
    assert.equal(req.headers['content-type'],'application/json');assert.equal(req.headers['content-encoding'],undefined);
    assert.equal(req.headers['authorization'],undefined,'Ambient OTEL headers must not cross explicit adapter boundary');
    const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));requests.push({path:req.url,body});
    if(!hang){res.writeHead(200,{'content-type':'application/json'});res.end('{}');}
  });
  await new Promise<void>(r=>server!.listen(0,'127.0.0.1',r));
  const endpoint='http://127.0.0.1:'+(server.address() as AddressInfo).port;
  const otel=['--telemetry-adapter','opentelemetry-native','--otel-binary',resolve(binary),'--otel-pin',resolve(pin),'--otel-helper',join(app,'build-provider/telemetry.mjs'),'--otel-endpoint',endpoint,'--otel-protocol','http/json','--otel-flush-timeout','2000'];
  const invoke=(extra: string[])=>new Promise<Invocation>((resolve,reject)=>{
    let stdout='',stderr='';const started=performance.now();
    const child=spawn(process.execPath,[...args,...extra],{cwd,env:{...process.env,OTEL_EXPORTER_OTLP_ENDPOINT:'http://unselected.invalid',OTEL_EXPORTER_OTLP_HEADERS:'authorization=must-not-export'},stdio:['ignore','pipe','pipe']});
    const timer=setTimeout(()=>{child.kill('SIGKILL');reject(Error('CLI acceptance timeout'));},240000);
    child.stdout.on('data',c=>stdout+=c);child.stderr.on('data',c=>stderr+=c);
    child.on('error',reject);child.on('close',code=>{clearTimeout(timer);resolve({code,stdout,stderr,milliseconds:performance.now()-started});});
  });
  const quiet=await invoke(['--telemetry-adapter','none']);assert.equal(quiet.code,0,quiet.stderr);assert.equal(requests.length,0,'Default/disabled adapter sends nothing');
  const defaultResult=await invoke([]);assert.equal(defaultResult.code,0,defaultResult.stderr);assert.equal(requests.length,0,'Ambient OTEL variables cannot enable export');
  const dry=await invoke([...otel,'--dry-run']);assert.equal(dry.code,0,dry.stderr);assert.equal(JSON.parse(dry.stdout).dryRun,true);assert.equal(requests.length,0,'Dry-run sends nothing');
  const badPin=join(root,'bad-pin.json');writeFileSync(badPin,JSON.stringify({...JSON.parse(readFileSync(pin,'utf8')),binaryIdentity:'0'.repeat(64)}));
  const wrong=await invoke(otel.map(v=>v===resolve(pin)?badPin:v));assert.equal(wrong.code,2);assert.match(wrong.stderr,/native_adapter_identity/);assert.equal(requests.length,0,'Bad pin fails before export/build');
  const unsupported=await invoke(otel.map(v=>v==='http/json'?'grpc':v));assert.equal(unsupported.code,2);assert.match(unsupported.stderr,/native_adapter_configuration/);
  for(const invalidEndpoint of ['http://','https://?token=x','http://#fragment','http://:4318','http://host:','http://host:65536','http://host:abc','http://bad host','http://user@host','http://host/path','http://999.1.2.3']) {
    for(const extra of [[],['--dry-run']]) {
      const invalid=await invoke([...otel.map(v=>v===endpoint?invalidEndpoint:v),...extra]);
      assert.equal(invalid.code,2,invalidEndpoint);assert.match(invalid.stderr,/native_adapter_configuration/);assert.equal(requests.length,0);
    }
  }
  const observed=await invoke(otel);assert.equal(observed.code,0,observed.stderr);  assert.doesNotMatch(observed.stderr,/unavailable|failed|deadline/);
  assert.deepEqual(JSON.parse(observed.stdout).execution.calls,JSON.parse(quiet.stdout).execution.calls);
  assert.deepEqual(requests.map(r=>r.path),['/v1/traces','/v1/logs','/v1/metrics']);
  const spans=requests[0]!.body.resourceSpans!.flatMap(r=>r.scopeSpans.flatMap(s=>s.spans));
  const logs=requests[1]!.body.resourceLogs!.flatMap(r=>r.scopeLogs.flatMap(s=>s.logRecords));
  const metrics=requests[2]!.body.resourceMetrics!.flatMap(r=>r.scopeMetrics.flatMap(s=>s.metrics));
  assert.ok(spans.length>23&&logs.length>23);
  const callSpans=spans.filter(s=>s.name==='morphir.call');assert.equal(callSpans.length,23);
  const invokeSpan=spans.find(s=>s.name==='morphir.invoke');assert.ok(invokeSpan);
  for(const span of callSpans) {
    assert.equal(span.traceId,invokeSpan.traceId);assert.equal(span.parentSpanId,invokeSpan.spanId);
    assert.ok(BigInt(span.endTimeUnixNano)>=BigInt(span.startTimeUnixNano));
    assert.ok(logs.some(log=>log.traceId===span.traceId&&log.spanId===span.spanId));
  }
  const operations=metrics.find(m=>m.name==='morphir.operations');assert.ok(operations);
  const points=metrics.filter(m=>m.name==='morphir.operations').flatMap(m=>m.sum.dataPoints);
  const attrs=(p: Point)=>Object.fromEntries(p.attributes.map(a=>[a.key,a.value.stringValue]));
  assert.equal(points.filter(p=>attrs(p)['morphir.stage']==='call').reduce((n,p)=>n+Number(p.asInt),0),23);
  assert.ok(metrics.some(m=>m.name==='morphir.duration.sum'));
  assert.ok(!JSON.stringify(requests).includes('18014398509481986'),'No model payload capture');
  writeFileSync(join(receipts,'capture.json'),JSON.stringify(requests,null,2)+'\n');
  // Export loss is optional health, never semantic failure. The outer supervised
  // process supplies one allowance across all three sequential HTTP requests.
  requests.length=0;hang=true;
  const failed=await invoke([...otel.slice(0,-1),'200']);
  assert.equal(failed.code,0,failed.stderr);assert.match(failed.stderr,/exporter unavailable or flush deadline/);
  assert.deepEqual(JSON.parse(failed.stdout).execution.calls,JSON.parse(quiet.stdout).execution.calls);
  server.closeAllConnections();hang=false;
  const samples=[];
  for(let i=0;i<3;i++) {
    const disabled=await invoke(['--telemetry-adapter','none']);
    const enabled=await invoke(['--log-file',join(root,'benchmark-'+i+'.ionb')]);
    assert.equal(disabled.code,0,disabled.stderr);assert.equal(enabled.code,0,enabled.stderr);
    assert.deepEqual(JSON.parse(disabled.stdout).execution.calls,JSON.parse(enabled.stdout).execution.calls);
    samples.push({disabledMs:disabled.milliseconds,enabledMs:enabled.milliseconds,deltaMs:enabled.milliseconds-disabled.milliseconds});
  }
  const median=(a: number[])=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)];
  const center=median(samples.map(s=>s.deltaMs));
  const noise=median(samples.map(s=>Math.abs(s.deltaMs-center!)));
  const summary={profile:'morphir-native-telemetry-acceptance-v1',adapter:JSON.parse(readFileSync(pin,'utf8')),executionEvidence:JSON.parse(quiet.stdout).execution.evidence,protocol:'http/json',compression:false,spans:spans.length,logs:logs.length,callSpans:23,correlated:true,metrics:metrics.map(m=>m.name),flushAllowanceMs:200,failedExporterSemanticNeutral:true,benchmark:{workload:'23 sensitive conformance calls; fresh generated build/session per CLI; paired disabled versus native Ion local recording; no collector in timing',samples,medianDeltaMs:center,madDeltaMs:noise,budget:{status:'provisional baseline only',absoluteDeltaMs:Math.max(0,...samples.map(s=>s.deltaMs))+3*noise!,enforced:false,reason:'Repeat across CI hosts before turning observed spread into a regression threshold'},environment:{node:process.version,platform:process.platform,arch:process.arch,release:release(),cpu:cpus()[0]!.model,compilerHome:home}}};
  writeFileSync(join(receipts,'summary.json'),JSON.stringify(summary,null,2)+'\n');
  console.log('Installed native OTLP HTTP/JSON: correlated spans/logs, metric export, isolated environment, optional export failure and bounded flush passed. Paired instrumentation baseline recorded.');
} finally {if(server){server.closeAllConnections();server.close();}rmSync(root,{recursive:true,force:true});}
