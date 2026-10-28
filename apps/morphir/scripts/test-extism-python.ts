import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {cpSync,existsSync,mkdirSync,mkdtempSync,readFileSync,readdirSync,realpathSync,rmSync,statSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository=fileURLToPath(new URL('../../../',import.meta.url));
const bundle=realpathSync(process.env.MORPHIR_EXTISM_BUNDLE??join(repository,'.dev/extism/python-bundle'));
const hostPinPath=process.env.MORPHIR_EXTISM_HOST_PIN??join(repository,'.dev/native-services/host-pin.json');
const hostPin=JSON.parse(readFileSync(hostPinPath,'utf8'));
const hostBuild=JSON.parse(readFileSync(join(dirname(hostPinPath),'evidence.json'),'utf8'));
assert.deepEqual(hostBuild.host,hostPin,'host build receipt must bind the invoked executable');
const python=process.env.MORPHIR_EXTISM_PYTHON;
assert.ok(python,'MORPHIR_EXTISM_PYTHON must name an independently installed matching morphir-tools Python API');
const runtime=realpathSync(process.execPath),sha=(p:string)=>createHash('sha256').update(readFileSync(p)).digest('hex');
const root=realpathSync(mkdtempSync(join(tmpdir(),'morphir-extism-python-')));
const source=join(repository,'apps/morphir/fixtures/extism-python/v1');
const descriptor=JSON.parse(readFileSync(join(bundle,'release.json'),'utf8'));
const wasm=descriptor.artifacts.find((a:{runtime:string})=>a.runtime==='wasm');
assert.equal(sha(join(bundle,wasm.filename)),wasm.sha256);
assert.equal(wasm.claims?.capabilities?.frontend?.multiDocument,true,'full qualification requires an explicitly multi-document Python bundle');
const native=resolve(process.env.MORPHIR_EXTISM_NATIVE??join(repository,'_build/native/debug/build/morphir/morphir/morphir.exe'));
const release=resolve(process.env.MORPHIR_EXTISM_RELEASE??join(repository,'_build/native/release/build/morphir/morphir/morphir.exe'));
const helpers=join(repository,'apps/morphir/build-provider');
const required=['extism.mjs','supervision.mjs','windows-job.mjs'];
const results:unknown[]=[];
const durations:number[]=[];
function run(program:string,args:string[],status=0,cwd=root){
 const started=performance.now();
 const child=spawnSync(program,args,{cwd,env:{...process.env,NODE_DISABLE_COMPILE_CACHE:'1',MORPHIR_HOME:join(root,'home'),TMPDIR:join(root,'temporary'),HTTP_PROXY:'http://127.0.0.1:9',HTTPS_PROXY:'http://127.0.0.1:9',ALL_PROXY:'http://127.0.0.1:9'},encoding:'utf8',timeout:120000,maxBuffer:20*1024*1024});
 durations.push(performance.now()-started);assert.equal(child.status,status,JSON.stringify(args)+'\n'+child.stdout+'\n'+child.stderr);return child;
}
try{
 mkdirSync(join(root,'temporary'));mkdirSync(join(root,'home'));mkdirSync(join(root,'retained'));
 cpSync(bundle,join(root,'retained/python'),{recursive:true});
 // No invocation uses the acquisition directory after the offline snapshot.
 const retained=join(root,'retained/python');
 cpSync(source,join(root,'src'),{recursive:true});
 const packed=run('npm',['pack','--ignore-scripts','--pack-destination',root],0,join(repository,'apps/morphir'));
 const tarball=join(root,packed.stdout.trim().split('\n').at(-1)!);
 mkdirSync(join(root,'npm'));run('tar',['-xzf',tarball,'-C',join(root,'npm')]);
 mkdirSync(join(root,'native-package'));cpSync(release,join(root,'native-package/morphir'));
 const launchers=[
  {name:'source-native',program:native,prefix:[] as string[],helper:helpers},
  {name:'source-js',program:runtime,prefix:[join(repository,'apps/morphir/bin/morphir.js')],helper:helpers},
  {name:'packaged-native',program:join(root,'native-package/morphir'),prefix:[] as string[],helper:join(root,'npm/package/build-provider')},
  {name:'packaged-npm',program:runtime,prefix:[join(root,'npm/package/bin/morphir.js')],helper:join(root,'npm/package/build-provider')},
 ];
 for(const launcher of launchers){
  const pin={contractVersion:'0.1.0',binding:'extism-wasm',executionProfile:'morphir/extism-mep-0.1/v1',host:hostPin,runtime:{executable:runtime,version:process.version,sha256:sha(runtime)},helper:{root:launcher.helper,modules:Object.fromEntries(required.map(n=>[n,sha(join(launcher.helper,n))]))},artifact:{directory:retained,descriptorSha256:sha(join(retained,'release.json')),wasmSha256:wasm.sha256,extensionId:descriptor.extensionId,version:descriptor.version},origin:'finos/morphir-python release '+descriptor.version};
  const pinFile=join(root,launcher.name+'.json');writeFileSync(pinFile,JSON.stringify(pin));
  const controls=['--extension-pin',pinFile,'--extension-helper',join(launcher.helper,'extism.mjs'),'--json'];
  const invoke=(args:string[],status=0)=>{const child=run(launcher.program,[...launcher.prefix,'extension',...args,...controls],status);const report=JSON.parse(child.stdout);assert.equal(report.profile,'morphir/command-result');assert.equal(report.exitCode,status);return {report,stderr:child.stderr};};
  const described=invoke(['describe']).report;assert.equal(described.result.session.extension.id,'morphir-python');assert.equal(described.result.session.provenance,'asserted');
  const help=JSON.parse(run(launcher.program,[...launcher.prefix,'extension','describe','--help','--json']).stdout);assert.ok(help.usage);
  run(launcher.program,[...launcher.prefix,'extension','describe','--unknown-extism-option','--json'],2);
  const cancel=join(root,launcher.name+'-cancel');writeFileSync(cancel,'');const cancelled=invoke(['describe','--cancel-file',cancel],130).report;assert.equal(cancelled.error.code,'execution.cancelled');assert.ok(!('result' in cancelled));
  const versions=[];
  for(const version of ['3','4']){
   const out=join(root,launcher.name+'-v'+version),generated=out+'-python',again=out+'-again';
   const compiled=invoke(['compile',join(root,'src'),'--package','acme/example','--ir-version',version,'--output',out]).report;
   assert.equal(compiled.result.session.negotiated.protocolVersion,'0.1');
   const model=JSON.parse(readFileSync(join(out,'morphir-ir.json'),'utf8'));assert.equal(model.formatVersion,Number(version));
   invoke(['generate',join(out,'morphir-ir.json'),'--ir-version',version,'--output',generated]);
   const parity=JSON.parse(run(python!,[join(repository,'apps/morphir/scripts/extism-python-api.py'),join(root,'src'),join(out,'morphir-ir.json'),generated,version,descriptor.version]).stdout);
   invoke(['compile',generated,'--package','acme/example','--ir-version',version,'--output',again]);
   assert.deepEqual(JSON.parse(readFileSync(join(again,'morphir-ir.json'),'utf8')),model);
   const invalid=invoke(['generate',join(out,'morphir-ir.json'),'--ir-version',version==='3'?'4':'3','--output',out+'-mismatch'],1).report;
   assert.equal(invalid.state,'failed');assert.ok(!('result' in invalid));assert.equal(existsSync(out+'-mismatch'),false);
   versions.push({version,parity,modelSha256:sha(join(out,'morphir-ir.json')),generated:readdirSync(generated)});
  }
  for(const args of [ ['compile',join(root,'src'),'--package','acme/example','--output',join(root,'missing')], ['compile',join(root,'src'),'--package','acme/example','--ir-version','3.1.0','--output',join(root,'unsupported')], ['compile',join(root,'src'),'--package','acme/example','--ir-version','3','--model-format','ion','--output',join(root,'ion')] ]) assert.equal(invoke(args,1).report.state,'failed');
  const bad={...pin,artifact:{...pin.artifact,wasmSha256:'0'.repeat(64)}};writeFileSync(pinFile,JSON.stringify(bad));assert.equal(invoke(['describe'],1).report.state,'failed');writeFileSync(pinFile,JSON.stringify(pin));
  writeFileSync(join(root,'broken.py'),'def broken(:\n');const diagnosed=invoke(['compile',join(root,'broken.py'),'--package','acme/example','--ir-version','3','--output',join(root,launcher.name+'-broken')],1);assert.ok(diagnosed.report.diagnostics.some((d:{code?:string})=>d.code?.startsWith('PY')));
  assert.deepEqual(readdirSync(join(root,'temporary')),[],'owned scratch was reaped and cleaned');
  results.push({name:launcher.name,programSha256:sha(launcher.program),entrypoint:launcher.prefix.map(p=>({file:p,sha256:sha(p)})),helpers:pin.helper.modules,versions});
 }
 const sourceFiles=['apps/morphir/extism.mbt','apps/morphir/extension.mbt','apps/morphir/arguments.mbt','apps/morphir/native-services/main.rs','apps/morphir/native-services/extism.rs','apps/morphir/native-services/extism_tests.rs','apps/morphir/native-services/Cargo.lock','apps/morphir/dist/morphir.js','apps/morphir/build-provider/extism.mts','apps/morphir/build-provider/test-extism.mts','apps/morphir/fixtures/extism-python/v1/acme/models.py','apps/morphir/fixtures/extism-python/v1/acme/rules.py','apps/morphir/scripts/extism-python-api.py','scripts/extism-python.mbtx'];
 const receipt={profile:'morphir/extism-python-qualification',contractVersion:'0.1.0',state:'succeeded',platform:process.platform,architecture:process.arch,node:process.version,runtimeSha256:sha(runtime),python:{executable:python,sha256:sha(python!)},host:hostPin,hostBuild:{sourceRevision:hostBuild.sourceRevision,sharedRustTree:hostBuild.sharedRustTree,target:hostBuild.target,rust:hostBuild.rust,moonbit:hostBuild.moonbit,cargoLockSha256:hostBuild.cargoLockSha256},hostBytes:statSync(hostPin.executable).size,bundle:{descriptorSha256:sha(join(bundle,'release.json')),wasmSha256:wasm.sha256,extensionId:descriptor.extensionId,version:descriptor.version,gitCommit:descriptor.gitCommit},checkDefinitionSha256:sha(fileURLToPath(import.meta.url)),sourceFiles:Object.fromEntries(sourceFiles.map(p=>[p,sha(join(repository,p))])),sourceRevision:spawnSync('git',['rev-parse','HEAD'],{cwd:repository,encoding:'utf8'}).stdout.trim(),elapsedCallsMs:durations,results};
 const reusablePin={contractVersion:'0.1.0',binding:'extism-wasm',executionProfile:'morphir/extism-mep-0.1/v1',host:hostPin,runtime:{executable:runtime,version:process.version,sha256:sha(runtime)},helper:{root:helpers,modules:Object.fromEntries(required.map(n=>[n,sha(join(helpers,n))]))},artifact:{directory:bundle,descriptorSha256:sha(join(bundle,'release.json')),wasmSha256:wasm.sha256,extensionId:descriptor.extensionId,version:descriptor.version},origin:'finos/morphir-python release '+descriptor.version};
 mkdirSync(join(repository,'.dev/extism'),{recursive:true});
 writeFileSync(join(repository,'.dev/extism/python-pin.json'),JSON.stringify(reusablePin,null,2)+'\n');
 const destination=join(repository,'.dev/extism/qualification.json');writeFileSync(destination,JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify(receipt));
}finally{rmSync(root,{recursive:true,force:true});}
