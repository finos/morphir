import type { Hash } from 'node:crypto';
import type { BuildEvidence, BuildRequest, Capability, Dependency, SourceMember, TreeOptions } from './contracts.mjs';
import { workbenchError } from '../../../types/data.ts';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {supervised} from './supervision.mjs';
import {readFileSync,writeFileSync,mkdirSync,readdirSync,cpSync,realpathSync,rmSync,existsSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {includeDependencyPath} from './paths.mjs';
import {treeIdentity} from './identity.mjs';
import {assertRuntime,stableVersion} from './capabilities.mjs';
import {checkedCore} from './core.mjs';
import {verifyCheckedDecimalRuntime} from './checked-decimal.mjs';

export async function buildLibrary(request: BuildRequest, requestPath: string, {driver=[], retain=false, capability=null}: { driver?: SourceMember[]; retain?: boolean; capability?: Capability | null } = {}): Promise<BuildEvidence> {
const workspace=join(dirname(requestPath),'workspace');
const compilerVersion=capability ? (request.toolchainPin?.compilerVersion||stableVersion) : stableVersion;
const semanticPin='bc99af69a8b24d391311fae3822a87eafef3c334';
const excluded=new Set(['.git','node_modules','.mooncakes','_build']);
const deadline=Date.now()+request.timeout;
const check=()=>{assert.ok(!request.cancelFile||!existsSync(request.cancelFile),'build.cancelled');assert.ok(Date.now()<deadline,'build.deadline');};
const selectedCore=checkedCore(realpathSync(request.compilerHome),compilerVersion,request.toolchainPin?.targets.includes('llvm')?'llvm-nightly':'stable',check);
const hash=(value: Parameters<Hash['update']>[0])=>createHash('sha256').update(value).digest('hex');
const tree=(root: string,options: TreeOptions={})=>treeIdentity(root,{...options,check});
async function execute(program: string,args: string[],cwd: string,home: string) {
  check();const env: NodeJS.ProcessEnv={...process.env,MOON_HOME:home,MOONBIT_NEW_NATIVE:"0"};
  delete env.MOON_WORK;
  for(const key of ['CC','CXX','CFLAGS','CPPFLAGS','LDFLAGS','MOONBIT_CC'])delete env[key];
  let result;
  try {result=await supervised(program,args,{cwd,env,timeout:Math.max(1,deadline-Date.now()),cancelFile:request.cancelFile});}
  catch(cause) { const error=workbenchError(cause);
    const codes: Record<string,string>={'execution.deadline':'build.deadline','execution.cancelled':'build.cancelled','execution.diagnostic_limit':'build.output_limit'};
    const [primary,...cleanup]=error.message.split('; ');
    throw Error([codes[primary!]||primary,...cleanup].join('; '));
  }
  check();assert.equal(result.code,0,`${program} ${args.join(' ')} failed: ${result.stderr}${result.stdout}`);
  return result.stdout;
}
function manifest(root: string,kind='moon.mod') {
  const text=readFileSync(join(root,kind),'utf8');
  const field=(name: string)=>{const m=text.match(new RegExp('^\\s*'+name+'\\s*=\\s*"([^"]+)"','m'));assert.ok(m,'Missing '+name);return m[1];};
  return {name:field('name'),version:field('version')};
}
function safePath(path: string) {
  assert.ok(typeof path==='string'&&path&& !path.includes('\\') && !path.includes(':') && !path.includes('\0'));
  assert.ok(path.split('/').every(p=>p&&p!=='.'&&p!=='..'),'Invalid member path');
}
try {
  assert.equal(request.contract,'moonbit-library-v1');assert.ok((capability?['native','js','wasm-gc','llvm']:['native','js','wasm','wasm-gc']).includes(request.target));
  assert.ok(Number.isInteger(request.timeout)&&request.timeout>=1&&request.timeout<=600000);
  assert.equal(hash(request.snapshot),request.sourceIdentity,'Source identity differs');
  const home=realpathSync(request.compilerHome);
  const moon=join(home,'bin',process.platform==='win32'?'moon.exe':'moon');
  const moonc=join(home,'bin',process.platform==='win32'?'moonc.exe':'moonc');
  const actualVersion=await execute(moonc,['-v'],dirname(requestPath),home);
  if(capability)assert.ok(actualVersion.startsWith('v'+compilerVersion+' '),'execution.compiler_version');
  else assert.ok(actualVersion.startsWith('v'+stableVersion+' '),'execution.compiler_version');
  if(capability) { assert.equal(capability.target,request.target);assertRuntime(capability); }
  const compilerIdentity=hash(Buffer.concat([readFileSync(moonc),readFileSync(moon)]));
  const coreIdentity=tree(selectedCore,{core:true});
  if(request.toolchainPin) { assert.equal(compilerIdentity,request.toolchainPin.compilerIdentity);assert.equal(coreIdentity,request.toolchainPin.coreIdentity); }
  mkdirSync(workspace);const project=join(workspace,'generated');mkdirSync(project);
  const snapshot=JSON.parse(request.snapshot);const seen=new Set();
  for(const [path,[encoding,content]] of snapshot) {
    safePath(path);assert.ok(!seen.has(path.toLowerCase()),'Duplicate source member');seen.add(path.toLowerCase());
    assert.ok(encoding==='text'||encoding==='binary');
    mkdirSync(dirname(join(project,path)),{recursive:true});
    if(encoding==='binary')assert.ok(Array.isArray(content)&&content.every(b=>Number.isInteger(b)&&b>=0&&b<=255));
    writeFileSync(join(project,path),encoding==='text'?content:Buffer.from(content));
  }
  assert.equal(manifest(project).name,request.projectId,'Generated manifest identity differs');
  const identities: (Dependency & { sourceIdentity: string })[]=[];const roots: { supplied: string; copied: string; sourceIdentity: string }[]=[];
  for(const [i,dependency] of request.dependencies.entries()) {
    const allowed: Record<string, string[]> = {
      'finos/morphir-sdk':['0.1.0','morphir-sdk-concrete-v1',semanticPin],
      'finos/morphir-execution':['0.1.0','morphir-invocations-v1','morphir-invocations-v1'],
      'moonrockz/ion':['0.6.0','ion-v1','ion-0.6.0'],
      'moonbitlang/x':['0.5.6','moonbit-x','x-0.5.6'],
      'moonbitlang/async':['0.22.7','moonbit-async','async-0.22.7'],
    };
    if(!driver.length)assert.equal(dependency.moduleName,'finos/morphir-sdk','Unaudited dependency contract');
    const expected=allowed[dependency.moduleName];assert.ok(expected,'Unaudited dependency contract');
    const sdkProfile=dependency.moduleName==='finos/morphir-sdk'?dependency.apiProfile:'';
    const sourceStrings=sdkProfile.includes('+moonbit-source-string-v1');
    const sourceInt32=sdkProfile.includes('+moonbit-source-int32-v1');
    const sourceInteger=sdkProfile.includes('+moonbit-source-integer-v1');
    const sourceFloat=sdkProfile.includes('+moonbit-source-float-v1');
    const sourceIndex=sdkProfile.includes('+moonbit-source-string-index-v1');
    const checkedDecimal=sdkProfile.includes('+decimal-checked-v1');
    if(dependency.moduleName==='finos/morphir-sdk') {
      expected[1]='morphir-sdk-concrete-v1'+(sourceStrings?'+moonbit-source-string-v1':'')+(sourceInt32?'+moonbit-source-int32-v1':'')+(sourceInteger?'+moonbit-source-integer-v1':'')+(sourceFloat?'+moonbit-source-float-v1':'')+(sourceIndex?'+moonbit-source-string-index-v1':'')+(checkedDecimal?'+decimal-checked-v1':'');
      assert.ok(!sourceIndex||sourceStrings,'build.missing_source_string_index_extension');
    }
    assert.deepEqual([dependency.version,dependency.apiProfile,dependency.semanticPin],expected);
    const supplied=request.suppliedDependencies[dependency.moduleName];assert.ok(supplied,'build.unresolved_dependency');
    const root=realpathSync(supplied);const info=manifest(root);
    assert.equal(info.name,dependency.moduleName);assert.equal(info.version,dependency.version);
    if(dependency.moduleName==='finos/morphir-sdk')assert.equal(JSON.parse(readFileSync(join(root,'conformance/bindings.json'),'utf8')).pin,dependency.semanticPin);
    if(sourceStrings) {
      const extensionPath=join(root,'conformance/moonbit_source_string_extension.json');
      assert.ok(existsSync(extensionPath),'build.missing_source_string_extension');
      const extension=JSON.parse(readFileSync(extensionPath,'utf8'));
      assert.equal(extension.profile,'morphir-moonbit-source-string-v1','build.missing_source_string_extension');
      assert.equal(extension.maxCodeUnits,1048576);
      assert.deepEqual(extension.bindings.map((binding: {fqName: string})=>binding.fqName),['morphir/moonbit-source:string#require-valid','morphir/moonbit-source:string#append-bounded']);
    }
    if(sourceInt32) {
      const path=join(root,'conformance/moonbit_source_int32_extension.json');
      assert.ok(existsSync(path),'build.missing_source_int32_extension');
      const extension=JSON.parse(readFileSync(path,'utf8'));
      assert.equal(extension.profile,'morphir-moonbit-source-int32-v1','build.missing_source_int32_extension');
      assert.match(extension.semantics,/modulo 2\^32/,'build.missing_source_int32_extension');
      assert.deepEqual(extension.bindings.map((binding: {fqName: string})=>binding.fqName),['morphir/moonbit-source:int32#normalize']);
    }
    if(sourceInteger) {
      const path=join(root,'conformance/moonbit_numeric_extension.json');
      assert.ok(existsSync(path),'build.missing_source_integer_extension');
      const extension=JSON.parse(readFileSync(path,'utf8'));
      assert.equal(extension.profile,'morphir-sdk-moonbit-numeric-v1','build.missing_source_integer_extension');
      assert.equal(extension.classicSemanticPin,semanticPin,'build.missing_source_integer_extension');
      assert.equal(extension.sourceRuntimeProfile,'morphir-moonbit-source-integer-v1','build.missing_source_integer_extension');
      assert.match(extension.sourceNormalization,/Modulo 2\^width/,'build.missing_source_integer_extension');
    }
    if(sourceFloat) {
      const path=join(root,'conformance/moonbit_float_extension.json');
      assert.ok(existsSync(path),'build.missing_source_float_extension');
      const extension=JSON.parse(readFileSync(path,'utf8'));
      assert.equal(extension.profile,'morphir-moonbit-source-float-v1','build.missing_source_float_extension');
      assert.equal(extension.classicSemanticPin,semanticPin,'build.missing_source_float_extension');
      assert.equal(extension.sourceType,'morphir/moonbit-source:float32#float32','build.missing_source_float_extension');
      assert.deepEqual(extension.bindings.slice(0,6).map((binding: {fqName: string})=>binding.fqName),['from-float64','round-boundary','add','subtract','multiply','divide'].map(name=>'morphir/moonbit-source:float32#'+name));
    }
    if(sourceIndex) {
      const path=join(root,'conformance/moonbit_source_string_index_extension.json');
      assert.ok(existsSync(path),'build.missing_source_string_index_extension');
      const extension=JSON.parse(readFileSync(path,'utf8'));
      assert.equal(extension.profile,'morphir-moonbit-source-string-index-v1','build.missing_source_string_index_extension');
      assert.equal(extension.indexUnit,'utf16-code-unit','build.missing_source_string_index_extension');
      assert.equal(extension.splitSurrogateBoundary,'inward','build.missing_source_string_index_extension');
      assert.deepEqual(extension.bindings.map((binding: {fqName: string})=>binding.fqName),['morphir/moonbit-source:string#length-int32','morphir/moonbit-source:string#slice-owned']);
    }
    if(checkedDecimal)verifyCheckedDecimalRuntime(root);
    const sourceIdentity=tree(root);const copied=join(workspace,'dependency'+i);
    cpSync(root,copied,{recursive:true,filter:path=>includeDependencyPath(root,path,excluded)});
    assert.equal(tree(copied),sourceIdentity,'Dependency copy differs');
    roots.push({supplied:root,copied,sourceIdentity});
    identities.push({...dependency,sourceIdentity});
  }
  if(driver.length) {
    const driverRoot=join(workspace,'driver');mkdirSync(driverRoot);const driverSeen=new Set();
    for(const [path,[encoding,content]] of driver) {
      safePath(path);assert.equal(encoding,'text');
      assert.ok(!driverSeen.has(path.toLowerCase()),'Duplicate driver member');driverSeen.add(path.toLowerCase());
      assert.ok(!path.split('/').includes('_build'),'Stale driver build outputs');
      mkdirSync(dirname(join(driverRoot,path)),{recursive:true});assert.ok(typeof content==='string');writeFileSync(join(driverRoot,path),content);
    }
  }
  // A frozen workspace supplies every module. No update/install/setup operation is used.
  writeFileSync(join(workspace,'moon.work'),'members='+JSON.stringify(['./generated',...(driver.length?['./driver']:[]),...roots.map((_,i)=>'./dependency'+i)])+'\n');
  const frozenSource=tree(project);
  assert.ok(!existsSync(join(project,'_build')),'Stale build outputs');
  const compilerOutput=join(workspace,'compiler-output');
  assert.ok(!existsSync(compilerOutput),'Stale compiler output directory');
  if(capability?.toolchain) {
    const pkg=join(workspace,'driver/main/moon.pkg');
    const original=readFileSync(pkg,'utf8');
    assert.ok(original.includes('options("native-stub": ["clock.c"])'),'execution.native_stub_contract');
    writeFileSync(pkg,original.replace('options("native-stub": ["clock.c"])','options("native-stub": ["clock.c"], link: {"native": {"cc": '+JSON.stringify(capability.toolchain.cc)+', "stub-cc": '+JSON.stringify(capability.toolchain.cc)+'}})'));
  }
  const frozenConfiguredDriver=driver.length?tree(join(workspace,'driver')):null;
  const buildMode=request.buildMode??'debug';
  assert.ok(['debug','release'].includes(buildMode),'execution.invalid_build_mode');
  await execute(moon,['build',...(buildMode==='release'?['--release']:[]),'--frozen','--target',request.target,'--target-dir',compilerOutput,...(driver.length?['driver/main']:[])],workspace,home);
  const interfaces: string[]=[];const executables: string[]=[];
  function outputFiles(root: string,relative='') {
    for(const entry of readdirSync(join(root,relative),{withFileTypes:true})) {
      const path=relative?relative+'/'+entry.name:entry.name;
      if(entry.isDirectory())outputFiles(root,path);
      else if(entry.isFile()) { if(entry.name.endsWith('.mi'))interfaces.push(path); if(path===request.target+'/'+buildMode+'/build/morphir-generated/driver/main/main.'+(request.target==='js'?'js':request.target==='wasm-gc'?'wasm':'exe'))executables.push(join(root,path)); }
    }
  }
  assert.ok(existsSync(compilerOutput),'No fresh compiler output');outputFiles(compilerOutput);
  const packageTail=request.projectId.split('/').at(-1);
  assert.ok(interfaces.some(path=>path===request.target+'/'+buildMode+'/build/'+packageTail+'.mi'||path.endsWith('/'+request.projectId+'/'+packageTail+'.mi')),'No fresh generated library interface: '+interfaces.join(', '));
  const buildIdentity=tree(compilerOutput);
  assert.equal(tree(project),frozenSource,'Generated source changed during build');
  if(driver.length)assert.equal(tree(join(workspace,'driver')),frozenConfiguredDriver,'Driver changed during build');
  assert.equal(hash(Buffer.concat([readFileSync(moonc),readFileSync(moon)])),compilerIdentity,'Compiler changed during build');
  assert.equal(tree(selectedCore,{core:true}),coreIdentity,'Core source changed during build');
  for(const dep of roots) {assert.equal(tree(dep.copied),dep.sourceIdentity,'Copied dependency changed');assert.equal(tree(dep.supplied),dep.sourceIdentity,'Supplied dependency changed');}
  check();
  const evidence: BuildEvidence={successful:true,frozen:true,leaseId:request.leaseId,projectId:request.projectId,contract:request.contract,sourceIdentity:request.sourceIdentity,target:request.target,compilerVersion,compilerIdentity,coreIdentity,buildIdentity,dependencies:identities};
  if(driver.length) { assert.equal(executables.length,1,'Expected one driver executable'); evidence.executable=executables[0]!; evidence.executableIdentity=hash(readFileSync(executables[0]!)); }
  if(capability) {evidence.buildMode=buildMode;assertRuntime(capability);evidence.capability=capability;evidence.configuredDriverIdentity=frozenConfiguredDriver;}
  return evidence;
} catch(cause) { const error=workbenchError(cause);
  throw error;
} finally {if(!retain)rmSync(workspace,{recursive:true,force:true});}
}
