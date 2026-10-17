import type { Capability, CapabilityRequest, LinkedRuntime, Runtime } from './contracts.mjs';
import { workbenchError } from '../../../types/data.ts';
import assert from 'node:assert/strict';
import {readFileSync,existsSync,realpathSync,accessSync,constants} from 'node:fs';
import {resolve,join,delimiter} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {release,version as osVersion} from 'node:os';
import {hash,fileIdentity,treeIdentity} from './identity.mjs';
export const stableVersion='0.10.15+943464bfa';
export function run(program: string,args: string[],timeout=10000) {
  const result=spawnSync(program,args,{encoding:'utf8',timeout,maxBuffer:1048576,env:{...process.env,MOONBIT_NEW_NATIVE:'0'}});
  assert.ok(!result.error,result.error?.message);assert.equal(result.status,0,result.stderr);return result.stdout+result.stderr;
}
export function command(name: string) {
  const names=process.platform==='win32'?[name,name+'.exe']:[name];
  for(const dir of (process.env.PATH||'').split(delimiter))for(const base of names) {
    const path=resolve(dir,base);try {accessSync(path,constants.X_OK);return realpathSync(path);}catch{}
  }
  throw Error('execution.missing_program: '+name);
}
export function compilerIdentity(home: string) {
  return hash(Buffer.concat(['moonc','moon'].map(name=>readFileSync(join(home,'bin',name+(process.platform==='win32'?'.exe':''))))));
}
export function capabilities(request: CapabilityRequest) {
  assert.ok(Number.isInteger(request.timeout)&&request.timeout>0&&request.timeout<=600000);
  const timeout=Math.min(request.timeout,10000), home=realpathSync(request.compilerHome), pin=request.toolchainPin;
  const version=pin?.compilerVersion||stableVersion;
  if(pin) {
    assert.equal(pin.profile,'morphir-toolchain-pin-v1');assert.equal(pin.platform,process.platform);assert.equal(pin.arch,process.arch);
    assert.match(pin.compilerIdentity,/^[a-f0-9]{64}$/);assert.match(pin.coreIdentity,/^[a-f0-9]{64}$/);
    assert.ok(Array.isArray(pin.targets)&&pin.targets.length&&pin.targets.every(t=>['js','wasm-gc','native','llvm'].includes(t)));
    assert.equal(new Set(pin.targets).size,pin.targets.length,'execution.duplicate_target');
    if(pin.targets.includes('llvm')) {
      assert.deepEqual(pin.targets,['llvm'],'execution.mixed_compiler_targets');
      assert.equal(version,'0.10.15+1e9f6672d-nightly','execution.unverified_llvm_pin');
      for(const key of ['compilerArchiveIdentity','coreArchiveIdentity'])assert.match(pin.acquisition?.[key]||'',/^[a-f0-9]{64}$/);
      for(const key of ['compilerUrl','coreUrl'])assert.ok(pin.acquisition?.[key]?.startsWith('https://cli.moonbitlang.com/'));
    } else {
      assert.equal(version,stableVersion,'execution.unverified_stable_pin');
    }
  }
  const moonc=join(home,'bin',process.platform==='win32'?'moonc.exe':'moonc');
  assert.ok(run(moonc,['-v'],timeout).startsWith('v'+version+' '),'execution.compiler_version');
  const core=join(home,'lib/core');assert.equal(readFileSync(join(core,'moon.mod'),'utf8').match(/^\s*version\s*=\s*"([^"]+)"/m)?.[1],version,'execution.core_version');
  const compiler=compilerIdentity(home), coreHash=treeIdentity(core,{core:true});
  if(pin) {assert.equal(compiler,pin.compilerIdentity,'execution.compiler_identity');assert.equal(coreHash,pin.coreIdentity,'execution.core_identity');}
  const allowed=pin?.targets||['js','wasm-gc','native'];
  const descriptors: Capability[]=[], unavailable: { target: string; reason: string }[]=[];
  for(const target of allowed) {
    try {
      if(target==='llvm')assert.ok(process.platform==='darwin'&&process.arch==='arm64','execution.unverified_llvm_host');
      let runtime: Runtime={kind:'node',path:process.execPath,identity:fileIdentity(process.execPath),version:process.version};
      let toolchain=null;
      if(target==='wasm-gc') {
        // Small module containing a struct type. Detect actual GC support rather than a Node version claim.
        assert.ok(WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,95,1,127,0])),'execution.wasm_gc_unavailable');
        const runner=fileURLToPath(new URL('./wasm-gc.mjs',import.meta.url));
        runtime={...runtime,kind:'node-wasm-gc',runner,runnerIdentity:fileIdentity(runner)};
      }
      if(target==='native'||target==='llvm') {
        // Native lanes currently require the audited POSIX compiler-driver and linker contract.
        assert.ok(['darwin','linux'].includes(process.platform),'execution.native_host_unavailable');
        const launcher=command('cc'), launcherVersion=run(launcher,['--version'],timeout);
        const installed=launcherVersion.match(/^InstalledDir: (.+)$/m)?.[1];
        const cc=launcher,compilerProgram=installed&&existsSync(join(installed,'clang'))?realpathSync(join(installed,'clang')):cc;
        const compilerVersion=run(cc,['--version'],timeout);
        const ldName=run(cc,['-print-prog-name=ld'],timeout).trim();
        const ld=ldName.includes('/')?realpathSync(ldName):command(ldName);
        toolchain={cc,driverIdentity:fileIdentity(cc),compilerProgram,compilerIdentity:fileIdentity(compilerProgram),compilerVersion,linker:ld,linkerIdentity:fileIdentity(ld),linkerVersion:run(ld,process.platform==='darwin'?['-v']:['--version'],timeout)};
        const system={platform:process.platform,arch:process.arch,release:release(),version:osVersion()};
        runtime={kind:'native-process',version:release(),identity:hash(JSON.stringify(system)),system,dependencies:[]};
        runtime.inputs=['lib/runtime','include'].map(name=>({path:join(home,name),identity:treeIdentity(join(home,name))}));
        for(const name of ['libmoonbitrun.o','runmain.o','libbacktrace.a','moonbit_simdutf.o']) {
          const path=join(home,'lib',name);if(existsSync(path))runtime.dependencies!.push({path,identity:fileIdentity(path)});
        }
      }
      const bundle=join(core,'_build',target,'release/bundle/prelude/prelude.mi');
      assert.ok(existsSync(bundle),'execution.core_bundle_unavailable');
      descriptors.push({target,backend:target==='native'?'c':target,compile:true,run:true,protocol:'morphir-invocations-v1/ion-binary',platform:process.platform,arch:process.arch,requiredImports:target==='wasm-gc'?['morphir_execution_v1']:[],runtime,toolchain});
    } catch(cause) {const error=workbenchError(cause); unavailable.push({target,reason:String(error.message).slice(0,512)});}
  }
  return {profile:'morphir-execution-capabilities-v1',compilerVersion:version,compilerIdentity:compiler,coreIdentity:coreHash,targets:descriptors,unavailable};
}
export function assertRuntime(descriptor: Capability) {
  assert.equal(descriptor.platform,process.platform,'execution.host_mismatch');assert.equal(descriptor.arch,process.arch,'execution.arch_mismatch');
  const r=descriptor.runtime;
  if(r.system)assert.equal(hash(JSON.stringify({platform:process.platform,arch:process.arch,release:release(),version:osVersion()})),r.identity,'execution.changed_system_runtime');
  if(r.path)assert.equal(fileIdentity(r.path),r.identity,'execution.changed_runtime');
  if(r.runner)assert.equal(fileIdentity(r.runner),r.runnerIdentity,'execution.changed_runner');
  for(const d of r.dependencies||[])assert.equal(fileIdentity(d.path),d.identity,'execution.changed_runtime_dependency');
  for(const d of r.inputs||[])assert.equal(treeIdentity(d.path),d.identity,'execution.changed_runtime_input');
  const t=descriptor.toolchain;
  if(t) {assert.equal(fileIdentity(t.cc),t.driverIdentity,'execution.changed_c_driver');assert.equal(fileIdentity(t.compilerProgram),t.compilerIdentity,'execution.changed_c_compiler');assert.equal(fileIdentity(t.linker),t.linkerIdentity,'execution.changed_linker');}
}

export function linkedRuntime(executable: string) {
  const paths=process.platform==='darwin'
    ?run('/usr/bin/otool',['-L',executable]).split('\n').slice(1).map(line=>line.trim().split(' ')[0]).filter((path): path is string => !!path)
    :run(command('ldd'),[executable]).split('\n').map(line=>line.match(/(?:=> )?(\/[^ ]+)/)?.[1]).filter((path): path is string => !!path);
  return paths.map(path=>existsSync(path)?{path,identity:fileIdentity(path),kind:'file'}:{path,kind:'system-shared-cache',systemVersion:osVersion()});
}
export function assertLinkedRuntime(dependencies: LinkedRuntime[]) {
  for(const d of dependencies) {
    if(d.kind==='file')assert.equal(fileIdentity(d.path),d.identity,'execution.changed_linked_runtime');
    else {assert.equal(d.kind,'system-shared-cache');assert.equal(d.systemVersion,osVersion(),'execution.changed_shared_cache');}
  }
}
