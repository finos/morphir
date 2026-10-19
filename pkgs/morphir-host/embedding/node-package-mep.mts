import {readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {acquireMoonRecipe} from './node-recipe.mjs';
import {executeAssembly} from './assembly.mjs';
import {mepExecutionProfile,mepLimits} from './mep-adapter.mjs';
import {boundWasmMemory} from './wasm-memory.mjs';
import {createInProcessToolchain} from './node.mjs';
import {prepareArtifact,publishArtifact} from './artifacts.mjs';
import {createDirectoryArtifactStore} from './node-artifacts.mjs';
import {Worker,isMainThread} from 'node:worker_threads';

if(isMainThread) {
  // The real frontend includes the upstream parser and a much larger AST than
  // the codec adapter. Give the packaged compiler its own explicit build stack;
  // this has no effect on saved-artifact runtime requirements.
  const worker=new Worker(new URL(import.meta.url),{argv:process.argv.slice(2),execArgv:[],resourceLimits:{stackSizeMb:32}});
  await new Promise<void>((resolve,reject)=>{worker.once('error',reject);worker.once('exit',code=>code===0?resolve():reject(new Error(`MEP packaging worker exited: ${code}`)));});
}else {
const [directory,coreRoot,...extra]=process.argv.slice(2);
if(!directory||!coreRoot||extra.length)throw new Error('Supply publication root and checked core directory');
const root=resolve(directory);
const acquired=await acquireMoonRecipe(await readFile(join(root,'recipe.txt'),'utf8'),coreRoot,JSON.parse(await readFile(join(root,'core-graph.json'),'utf8')));
const entry=acquired.packages.find(p=>p.name==='finos/morphir-extension/portable');
if(!entry)throw new Error('Missing portable MEP entry package');
const toolchain=createInProcessToolchain();
try {
  // No installed compiler or undeclared build cache is consulted after acquisition.
  process.env.PATH='';delete process.env.MOON_HOME;
  const assembly=await executeAssembly(toolchain,{...acquired,root:entry.pin,target:'wasm',exports:['handle']});
  const bounded={...assembly,artifact:{...assembly.artifact,bytes:boundWasmMemory(assembly.artifact.bytes,mepLimits.memoryPages)}};
  const saved=await prepareArtifact(bounded,await mepExecutionProfile(),{metadataIon:'mep_extension::{protocol:"0.2.0-draft.1", envelope:"0.1.0-draft.1", ir:"4.0.0", irStatus:draft, language:"moonbit", binding:process, wasm:core}'});
  await publishArtifact(createDirectoryArtifactStore(join(root,'extension')),saved);
  await writeFile(join(root,'build-report.json'),JSON.stringify({artifactSha256:saved.record.artifact.sha256,bytes:saved.wasm.length,packages:saved.record.packages.length,identity:acquired.identity,profile:saved.record.invocation.profile,imports:saved.record.invocation.imports,memoryPages:mepLimits.memoryPages},null,2)+'\n');
  console.error(`Packaged MEP extension: ${saved.wasm.length} bytes, ${saved.record.packages.length} packages`);
} finally {toolchain.dispose();}
}
