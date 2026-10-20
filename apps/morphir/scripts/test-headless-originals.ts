/** Real declaration-capable compiler -> authenticated host -> built CLI -> current publisher. */
import assert from 'node:assert/strict';
import {spawn,spawnSync,type ChildProcess,type SpawnSyncReturns} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,readdirSync,existsSync,statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve,relative} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const repo=fileURLToPath(new URL('../../../',import.meta.url));
const target=process.argv[2]??'js';
const hostBinary=process.env.MORPHIR_MODEL_ORIGINALS_HOST;
const portable=target==='wasm'||target==='wasm-gc';
const root=mkdtempSync(join(tmpdir(),'morphir-headless-originals-'));
const cliBinary=process.env.MORPHIR_HEADLESS_BINARY??join(repo,'_build/native/debug/build/morphir/morphir/morphir.exe');
const launcher=process.env.MORPHIR_HEADLESS_LAUNCHER??join(repo,'apps/morphir/bin/morphir.js');
const executable=target==='native'?cliBinary:process.execPath;
const prefix=target==='native'?[]:portable?[join(repo,'pkgs/morphir-host/runners/wasm.mjs'),cliBinary]:[launcher];
let host:ChildProcess|undefined;
function digest(bytes:Uint8Array){return createHash('sha256').update(bytes).digest('hex');}
async function cli(cwd:string,args:string[],helper?:string,interruptOnWrite=false){
 const child=spawn(executable,[...prefix,...args,'--provider','workbench-http','--json'],{cwd,env:{...process.env,
  MORPHIR_CONNECTED_HELPER:process.env.MORPHIR_CONNECTED_HELPER??join(repo,'apps/morphir/build-provider/connected.mjs'),MORPHIR_ORIGINALS_HELPER:helper??process.env.MORPHIR_ORIGINALS_HELPER??join(repo,'apps/morphir/build-provider/originals.mjs'),TMPDIR:join(root,'tmp')},stdio:['ignore','pipe','pipe']});
 let stdout='',stderr='';child.stdout.on('data',bytes=>stdout+=bytes);child.stderr.on('data',bytes=>stderr+=bytes);
 let timer:ReturnType<typeof setInterval>|undefined;
 if(interruptOnWrite)timer=setInterval(()=>{
  for(const name of readdirSync(join(root,'tmp'))){
   const part=join(root,'tmp',name,'part-0');
   if(existsSync(part)&&readdirSync(part).length){child.kill('SIGINT');clearInterval(timer);break;}
  }
 },5);
 const code=await new Promise<number|null>((resolve,reject)=>{child.once('error',reject);child.once('close',resolve);});
 clearInterval(timer);
 return{code,stdout,stderr,report:JSON.parse(stdout)};
}
function inventory(path:string,base=path):{path:string;kind:'file'|'directory';sha256?:string;length?:number}[]{
 const entries=[];for(const name of readdirSync(path).sort()){
  const full=join(path,name),relativePath=relative(base,full).replaceAll('\\','/');
  if(statSync(full).isDirectory()){entries.push({path:relativePath,kind:'directory' as const});entries.push(...inventory(full,base));}
  else {const bytes=readFileSync(full);entries.push({path:relativePath,kind:'file' as const,sha256:digest(bytes),length:bytes.length});}
 }return entries.sort((a,b)=>Buffer.compare(Buffer.from(a.path),Buffer.from(b.path)));
}
try{
 mkdirSync(join(root,'tmp'));
 if(portable||process.platform==='win32'){
  const help=await cli(root,['connected','originals','--help']);assert.equal(help.code,0);
  const request=join(root,'selection.json');writeFileSync(request,'{}');
  const result=await cli(root,['connected','originals',request,'--connection','unused','--output','saved']);
  assert.equal(result.code,2);assert.match(result.stdout+result.stderr,/runtime_unavailable|private_file_permissions_unavailable/);
  assert.ok(!existsSync(join(root,'saved')));assert.deepEqual(readdirSync(join(root,'tmp')),[]);
  console.log(`${target}: connected originals help and explicit unavailable effects passed`);
 }else{
 assert.ok(hostBinary,'Select the exact actual host binary with MORPHIR_MODEL_ORIGINALS_HOST');
 for(const layout of ['single-file','document-tree'])for(const representation of (layout==='single-file'?['json','yaml','ion','ion-binary']:['json','yaml','ion'])){
  const format=representation==='ion-binary'?'ion':representation;
  if(process.env.MORPHIR_ORIGINALS_CASE&&process.env.MORPHIR_ORIGINALS_CASE!==layout+'-'+representation)continue;
  const cwd=join(root,layout+'-'+representation);mkdirSync(join(cwd,'models'),{recursive:true});
  writeFileSync(join(cwd,'models/api.gleam'),'pub type Answer { Answer }\n');
  writeFileSync(join(cwd,'morphir.toml'),`[project]\nname='acme/originals'\nversion='1.0.0'\nsource_directory='models'\nexposed_modules=['api']\n[frontend]\nlanguage='gleam'\n[ir]\nlayout='${layout}'\nformat='${format}'\n`);
  const compile:SpawnSyncReturns<string>=spawnSync(hostBinary,['compile','--json'],{cwd,encoding:'utf8',timeout:60000});
  assert.equal(compile.status,0,compile.stdout+compile.stderr);
  const record=JSON.parse(readFileSync(join(cwd,'.morphir/out/compile.json'),'utf8'));
  assert.deepEqual(record.morphirModelOriginals,{contractVersion:'0.1.0-draft.1',companions:[]});
  const destination=join(cwd,'.morphir/out/compile.dest');
  // Fixture preparation precedes launching the host; no live compile/reader is mutated.
  // The genuine compile record/declaration is unchanged. These are exact source
  // byte-transfer controls, not a binary compiler-writer or semantic-reader claim.
  if(representation==='ion-binary')writeFileSync(join(destination,record.ir.path),readFileSync(join(repo,'apps/morphir-workbench/fixtures/headless-parity/v1/originals/model.ionb')));
  if(layout==='single-file'&&format==='yaml'){
   const primary=join(destination,record.ir.path),text=readFileSync(primary,'utf8');
   writeFileSync(primary,'\ufeff# exact original\r\n'+text.replaceAll('\r\n','\n').replaceAll('\n','\r\n'));
  }
  if(layout==='document-tree'){
   const primary=record.ir.path;mkdirSync(join(destination,primary,'empty'),{recursive:true});
   writeFileSync(join(destination,primary,'opaque.bin'),Buffer.from([0,255,128,0,13,10]));
   writeFileSync(join(destination,primary,'empty.bin'),Buffer.alloc(0));
   writeFileSync(join(destination,primary,'nul-bytes.txt'),Buffer.from('text\0with\0NUL\r\n'));
   const existing=inventory(destination).filter(item=>item.kind==='file'&&(item.path===primary||item.path.startsWith(primary+'/'))).reduce((sum,item)=>sum+item.length!,0);
   const large=Buffer.alloc(format==='json'?67108864-existing:1048833);for(let i=0;i<large.length;i++)large[i]=i%256^Math.floor(i/65536)%256;
   writeFileSync(join(destination,primary,'large.bin'),large);
  }
  // Only the actual declared primary is an original. Compiler parse outputs
  // elsewhere in compile.dest are private bookkeeping, not implicit companions.
  const expected=inventory(destination).filter(item=>item.path===record.ir.path||item.path.startsWith(record.ir.path+'/'));
  let diagnostic='';host=spawn(hostBinary,['ui','--no-open','--preview-model-originals',cwd],{cwd,stdio:['ignore','pipe','pipe']});
  const launch=await new Promise<string>((resolve,reject)=>{
   const timeout=setTimeout(()=>reject(new Error('Actual host startup timeout')),20000);
   const read=(bytes:Buffer)=>{diagnostic+=bytes;const found=/http:\/\/127\.0\.0\.1:\d+\/launch\?token=[A-Za-z0-9_-]{43}/.exec(diagnostic);if(found){clearTimeout(timeout);resolve(found[0]);}};
   host!.stderr!.on('data',read);host!.stdout!.on('data',read);host!.once('error',reject);host!.once('exit',()=>reject(new Error('Host exited before startup')));
  });
  const launchFile=join(cwd,'launch.txt'),connection=join(cwd,'connection.json'),selection=join(cwd,'selection.json');writeFileSync(launchFile,launch,{mode:0o600});
  const connected=await cli(cwd,['connected','connect',launchFile,'--connection',connection,'--connection-scope','models']);
  assert.equal(connected.code,0,connected.stdout+connected.stderr);assert.ok(connected.report.sources.length);
  const offered=connected.report.sources[0],source={providerId:offered.providerId,locator:offered.locator};writeFileSync(selection,JSON.stringify({source}));
  const listed=await cli(cwd,['connected','originals',selection,'--list','--connection',connection]);
  assert.equal(listed.code,0,listed.stdout+listed.stderr);assert.equal(listed.report.observation,'discovered');assert.ok(listed.report.projects.length);
  writeFileSync(selection,JSON.stringify({source,projectId:listed.report.projects[0].projectId}));
  const result=await cli(cwd,['connected','originals',selection,'--connection',connection,'--output','saved']);
  assert.equal(result.code,0,result.stdout+result.stderr);assert.equal(result.report.observation,'published');assert.equal(result.report.representation,'original-bytes');assert.equal(result.report.cleanup.kind,'released');
  assert.deepEqual(inventory(join(cwd,'saved/originals')),expected);
  if(layout==='document-tree'&&format==='json')assert.equal(result.report.sourceByteLength,67108864,'Exact inclusive original-set boundary');
  const cookie=JSON.parse(readFileSync(connection,'utf8')).cookie.split('=')[1];
  for(const value of [connected,listed,result]){assert.ok(!value.stdout.includes(cookie)&&!value.stderr.includes(cookie));assert.ok(!value.stdout.includes(new URL(launch).searchParams.get('token')!));}
  assert.deepEqual(readdirSync(join(root,'tmp')),[],'All owned scratch removed');
  const duplicate=await cli(cwd,['connected','originals',selection,'--connection',connection,'--output','saved']);assert.equal(duplicate.code,2);assert.deepEqual(inventory(join(cwd,'saved/originals')),expected);
  if(layout==='document-tree'&&format==='json'){
   const credential=readFileSync(connection,'utf8');
   for(const fault of ['session','profile']){
    const changed=JSON.parse(credential);if(fault==='session')changed.sessionId='foreign';else changed.descriptor.contractVersion='0.1.0-draft.999';
    writeFileSync(connection,JSON.stringify(changed));
    const refused=await cli(cwd,['connected','originals',selection,'--connection',connection,'--output','bad-'+fault]);
    assert.equal(refused.code,2);assert.ok(!existsSync(join(cwd,'bad-'+fault,'originals')));writeFileSync(connection,credential);
   }
   const cancel=join(cwd,'cancel');writeFileSync(cancel,'cancel');
   const cancelled=await cli(cwd,['connected','originals',selection,'--connection',connection,'--output','cancelled','--cancel-file',cancel]);
   assert.equal(cancelled.code,130);assert.ok(!existsSync(join(cwd,'cancelled/originals')));
   const signalled=await cli(cwd,['connected','originals',selection,'--connection',connection,'--output','signalled'],undefined,true);
   assert.equal(signalled.code,130,signalled.stdout+signalled.stderr);assert.ok(!existsSync(join(cwd,'signalled/originals')));
   assert.deepEqual(readdirSync(join(root,'tmp')),[],'SIGINT cleanup ignores the latched acquisition interruption');
   for(const fault of ['bytes','interrupt','late-cancel']){
    const wrapper=join(cwd,'helper-'+fault+'.mjs');
    const mutation=fault==='bytes'?`if(value.code===0){const manifest=JSON.parse(readFileSync(join(raw.scratch,'inventory.json'),'utf8'));const index=manifest.entries.findLastIndex(item=>item.kind==='file');writeFileSync(join(raw.scratch,'part-'+Math.floor(index/65536),'file-'+index),Buffer.from('changed'));}`:fault==='late-cancel'?`if(value.code===0)writeFileSync(raw.cancelFile,'cancel after acknowledged release');`:'';
    const interrupt=fault==='interrupt'?`()=>Boolean(interrupted?.())||(existsSync(join(raw.scratch,'part-0'))&&readdirSync(join(raw.scratch,'part-0')).length>0)`:'interrupted';
    writeFileSync(wrapper,`import{readFileSync,writeFileSync,existsSync,readdirSync}from'node:fs';import{join}from'node:path';import{originalsCommand as actual}from${JSON.stringify(pathToFileURL(join(repo,'apps/morphir/build-provider/originals.mjs')).href)};export async function originalsCommand(raw,core,interrupted){const value=await actual(raw,core,${interrupt});${mutation}return value;}if(process.argv[2]==='--morphir-originals-v1'){const value=await originalsCommand(JSON.parse(readFileSync(process.argv[3],'utf8')));console.log(JSON.stringify(value.report));process.exitCode=value.code;}`);
    const refused=await cli(cwd,['connected','originals',selection,'--connection',connection,'--output','bad-'+fault,...(fault==='late-cancel'?['--cancel-file',join(cwd,'late-cancel')]:[])],wrapper);
    assert.equal(refused.code,fault==='bytes'?1:130,refused.stdout+refused.stderr);
    assert.ok(!existsSync(join(cwd,'bad-'+fault,'originals')),'No prefix published after late corruption/interruption');
    if(fault==='bytes')assert.equal(refused.report.cleanup.kind,'released');
    assert.deepEqual(readdirSync(join(root,'tmp')),[]);
   }
   // A failed attempt closes only its socket and does not terminate the host.
   const recovery=await cli(cwd,['connected','originals',selection,'--connection',connection,'--output','recovered']);assert.equal(recovery.code,0,recovery.stdout+recovery.stderr);assert.deepEqual(inventory(join(cwd,'recovered/originals')),expected);
   console.log(`${target}: stale session/profile, pre-cancel, late corruption, active interruption and recovery passed`);
  }
  host.kill('SIGTERM');await new Promise(resolve=>host!.once('exit',resolve));host=undefined;
  console.log(`${target}: ${layout} ${representation} actual-host exact originals, discovery, release and collision passed`);
 }
 }
}finally{host?.kill('SIGTERM');rmSync(root,{recursive:true,force:true});}
