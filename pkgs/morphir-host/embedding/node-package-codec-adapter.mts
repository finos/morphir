import {readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {acquireMoonRecipe} from './node-recipe.mjs';
import {executeAssembly} from './assembly.mjs';
import {byteExecutionProfile,loadByteAdapter} from './byte-adapter.mjs';
import {createInProcessToolchain} from './node.mjs';
import {prepareArtifact,publishArtifact} from './artifacts.mjs';
import {createDirectoryArtifactStore} from './node-artifacts.mjs';

const [directory,coreRoot]=process.argv.slice(2);
if(!directory || !coreRoot)throw new Error('Supply publication root and checked core directory');
const root=resolve(directory);
const acquired=await acquireMoonRecipe(await readFile(join(root,'recipe.txt'),'utf8'),coreRoot,JSON.parse(await readFile(join(root,'core-graph.json'),'utf8')));
const toolchain=createInProcessToolchain();
try {
  // Acquisition has finished; compile/link must use only the packaged provider.
  process.env.PATH='';delete process.env.MOON_HOME;
  const receipts=[];
  for(const profile of ['bytes-v1','bytes-diagnostics-v1'] as const) {
    const name=`finos/morphir-workbench/mck/${profile==='bytes-v1'?'packaged':'packaged-diagnostics'}`;
    const pkg=acquired.packages.find(p=>p.name===name);if(!pkg)throw new Error('Missing codec entry package');
    const result=await executeAssembly(toolchain,{...acquired,root:pkg.pin,target:'wasm',exports:['handle']});
    const contract=await byteExecutionProfile(profile);
    const saved=await prepareArtifact(result,contract,{metadataIon:'codec_adapter::{contract:"0.1.0-draft.26", scope:"offline production observations", language:"moonbit"}'});
    const events:unknown[]=[];
    const adapter=await loadByteAdapter(saved,profile==='bytes-v1'?{profile}:{profile,diagnostics:event=>events.push(event)});
    try {
      const request=new TextEncoder().encode('{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.26"}');
      const response=adapter.exchange(request);
      if(response.kind!=='response' || JSON.parse(new TextDecoder().decode(response.bytes)).contractVersion!=='0.1.0-draft.26')throw new Error('Packaged capabilities check failed');
    } finally {adapter.dispose();}
    await publishArtifact(createDirectoryArtifactStore(join(root,profile)),saved);
    receipts.push({profile,contract,bytes:saved.wasm.length,artifactSha256:saved.record.artifact.sha256,packages:saved.record.packages.length,identity:acquired.identity,events});
    console.error(`Packaged ${profile}: ${saved.wasm.length} bytes, ${acquired.packages.length} packages`);
  }
  // Explicit JSON diagnostic report, not the pipeline artifact representation.
  await writeFile(join(root,'build-report.json'),JSON.stringify(receipts,null,2)+'\n');
} finally {toolchain.dispose();}
