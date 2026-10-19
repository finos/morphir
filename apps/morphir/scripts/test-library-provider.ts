import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,mkdirSync,writeFileSync,readdirSync,rmSync,chmodSync,cpSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,relative,sep} from 'node:path';
import {posix,win32} from 'node:path';
import {fileURLToPath} from 'node:url';
import {isWithin,includeDependencyPath} from '../build-provider/paths.mts';

// Windows drive/UNC and POSIX containment can be checked on every CI host.
for(const [paths,core] of [[posix,'/moon/lib/core'],[win32,'C:\\moon\\lib\\core'],[win32,'\\\\server\\share\\core']] as const) {
  assert.equal(isWithin(core!,paths!.join(core,'array','array.mi'),paths),true);
  assert.equal(isWithin(core!,paths!.join(core,'..','outside.mi'),paths),false);
  assert.equal(isWithin(core!,core+'-other'+paths!.sep+'array.mi',paths),false);
  assert.equal(isWithin(core!,core,paths),false);
  const excluded=new Set(['node_modules','.git','.mooncakes','_build']);
  for(const ancestor of excluded) {
    const sdk=paths!.join(core,ancestor,'sdk');
    assert.equal(includeDependencyPath(sdk,sdk,excluded,paths!),true);
    assert.equal(includeDependencyPath(sdk,paths!.join(sdk,'basics','basics.mbt'),excluded,paths!),true);
    assert.equal(includeDependencyPath(sdk,paths!.join(sdk,'..','outside.mbt'),excluded,paths!),false);
    for(const child of excluded) assert.equal(includeDependencyPath(sdk,paths!.join(sdk,child,'cache.mbt'),excluded,paths!),false);
  }
}
assert.equal(isWithin('C:\\moon\\lib\\core','D:\\moon\\lib\\core\\file.mi',win32),false);
assert.equal(isWithin('C:\\moon\\lib\\core','c:\\MOON\\lib\\CORE\\file.mi',win32),true);

assert.ok(process.env.MOON_HOME,'Supply the complete pinned compiler/core home');
const helper=fileURLToPath(new URL('../build-provider/library-build.mjs',import.meta.url));
const root=mkdtempSync(join(tmpdir(),'morphir-provider-test-'));
const snapshot=JSON.stringify([
  ['library.mbt',['text','pub fn value() -> Int { 42 }\n']],
  ['moon.mod',['text','name="morphir-generated/test"\nversion="0.0.0"\n']],
  ['moon.pkg',['text','']],
]);
const base={timeout:120000,leaseId:'test-lease',projectId:'morphir-generated/test',contract:'moonbit-library-v1',snapshot,sourceIdentity:createHash('sha256').update(snapshot).digest('hex'),target:'native',compilerHome:process.env.MOON_HOME,suppliedDependencies:{},dependencies:[]};
let serial=0;
function run(patch: Record<string,unknown>={},expectedError?: RegExp) {
  const lease=join(root,'lease'+serial++);mkdirSync(lease);const path=join(lease,'request.json');
  writeFileSync(path,JSON.stringify({...base,...patch}));
  const env={...process.env};if(patch.compilerHome)env.MOON_CORE_OVERRIDE=join(String(patch.compilerHome),'lib/core');
  const result=spawnSync(process.execPath,[helper,path],{encoding:'utf8',env,timeout:180000,maxBuffer:2*1024*1024});
  assert.equal(result.error,undefined);
  assert.deepEqual(readdirSync(lease),['request.json'],'Provider leaked its workspace');
  if(expectedError) {assert.notEqual(result.status,0);assert.equal(result.stdout,'');assert.match(result.stderr,expectedError);}
  else {assert.equal(result.status,0,result.stderr);const evidence=JSON.parse(result.stdout);assert.equal(evidence.successful,true);assert.equal(evidence.sourceIdentity,base.sourceIdentity);assert.match(evidence.buildIdentity,/^[a-f0-9]{64}$/);return evidence;}
}
function fakeHome(behavior: string,version='0.1.0',compiler='0.10.15+943464bfa') {
  const home=join(root,'home'+serial++);mkdirSync(join(home,'bin'),{recursive:true});mkdirSync(join(home,'lib/core'),{recursive:true});
  assert.ok(process.env.MOON_CORE_OVERRIDE,'Supply the verified corrected core');
  cpSync(process.env.MOON_CORE_OVERRIDE,join(home,'lib/core'),{recursive:true,filter:path=>!relative(process.env.MOON_CORE_OVERRIDE!,path).split(sep).includes('_build')});
  if(version!=='0.1.0')writeFileSync(join(home,'lib/core/moon.mod'),`name="moonbitlang/core"\nversion="${version}"\n`);
  const tools={moonc:`console.log('v${compiler} (test)')`,moon:behavior};
  for(const [name,body] of Object.entries(tools)) {const path=join(home,'bin',name);writeFileSync(path,'#!/usr/bin/env node\n'+body+'\n');chmodSync(path,0o755);}
  return home;
}
const fresh=`import{mkdirSync,writeFileSync}from'node:fs';import{join}from'node:path';
const args=process.argv.slice(2);if(args[0]!=='build'||!args.includes('--frozen'))throw Error('Unexpected compiler operation');
const output=args[args.indexOf('--target-dir')+1];const path=join(output,'native/debug/build/morphir-generated/test');mkdirSync(path,{recursive:true});writeFileSync(join(path,'test.mi'),'test interface');`;
try {
  const targets=[];
  for(const target of ['native','js','wasm','wasm-gc']) {run({target});targets.push(target);}
  // Ancestor names do not exclude an explicitly supplied SDK root.
  const suppliedSdk=fileURLToPath(new URL('../../../pkgs/morphir-sdk/',import.meta.url));
  const dependency={moduleName:'finos/morphir-sdk',version:'0.1.0',apiProfile:'morphir-sdk-concrete-v1',semanticPin:'bc99af69a8b24d391311fae3822a87eafef3c334'};
  for(const profile of [
    'morphir-sdk-concrete-v1+moonbit-source-int32-v1',
    'morphir-sdk-concrete-v1+moonbit-source-string-v1+moonbit-source-string-index-v1',
    'morphir-sdk-concrete-v1+moonbit-source-string-v1+moonbit-source-int32-v1+moonbit-source-string-index-v1',
  ])run({dependencies:[{...dependency,apiProfile:profile}],suppliedDependencies:{'finos/morphir-sdk':suppliedSdk}});
  const excluded=new Set(['node_modules','.git','.mooncakes','_build']);
  for(const ancestor of excluded) {
    const sdk=join(root,'ancestor'+serial++,ancestor,'sdk');
    cpSync(suppliedSdk,sdk,{recursive:true,filter:path=>!relative(suppliedSdk,path).split(sep).some(part=>excluded.has(part))});
    for(const child of excluded) {mkdirSync(join(sdk,child),{recursive:true});writeFileSync(join(sdk,child,'broken.mbt'),'invalid source !');}
    run({dependencies:[dependency],suppliedDependencies:{'finos/morphir-sdk':sdk}});
  }
  run({timeout:1},/build.deadline/);
  run({sourceIdentity:'0'.repeat(64)},/Source identity differs/);
  if(process.platform!=='win32') {
    run({compilerHome:fakeHome('',undefined,'9.0.0')},/v0\\?\.10|did not match|match the regular expression/);
    run({compilerHome:fakeHome('','9.0.0')},/Corrected core version required/);
    run({compilerHome:fakeHome(`process.stdout.write('x'.repeat(1048577))`)},/build.output_limit/);
    run({compilerHome:fakeHome('')},/No fresh compiler output/);
    run({compilerHome:fakeHome(fresh+`writeFileSync('generated/moon.mod','name="changed"');`)},/Generated source changed/);
    run({compilerHome:fakeHome(fresh+`writeFileSync(join(process.env.MOON_HOME,'bin/moonc'),'changed compiler');`)},/Compiler changed/);
    run({compilerHome:fakeHome(fresh+`writeFileSync(join(process.env.MOON_HOME,'lib/core/moon.mod'),'changed core');`)},/Core source changed/);
  }
  const stale=JSON.parse(snapshot);stale.push(['_build/stale',['text','stale']]);const staleSnapshot=JSON.stringify(stale);
  run({snapshot:staleSnapshot,sourceIdentity:createHash('sha256').update(staleSnapshot).digest('hex')},/Stale build outputs/);
  run({dependencies:[{moduleName:'finos/morphir-sdk',version:'0.1.0',apiProfile:'morphir-sdk-concrete-v1',semanticPin:'bc99af69a8b24d391311fae3822a87eafef3c334'}]},/build.unresolved_dependency/);
  const missingExtension=join(root,'missing-source-string-extension');
  mkdirSync(join(missingExtension,'conformance'),{recursive:true});
  writeFileSync(join(missingExtension,'moon.mod'),'name="finos/morphir-sdk"\nversion="0.1.0"\n');
  writeFileSync(join(missingExtension,'conformance/bindings.json'),JSON.stringify({pin:'bc99af69a8b24d391311fae3822a87eafef3c334'}));
  run({dependencies:[{moduleName:'finos/morphir-sdk',version:'0.1.0',apiProfile:'morphir-sdk-concrete-v1+moonbit-source-string-v1',semanticPin:'bc99af69a8b24d391311fae3822a87eafef3c334'}],suppliedDependencies:{'finos/morphir-sdk':missingExtension}},/build.missing_source_string_extension/);
  console.log(JSON.stringify({successful:true,targets,deadline:true,identityChecks:true,outputLimit:true,staleOutputs:true,cleanup:true,sdkAncestors:true,pathPlatforms:['posix','win32-drive','win32-unc']}));
} finally {rmSync(root,{recursive:true,force:true});}
