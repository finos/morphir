import { fileURLToPath } from 'node:url';
/** Reproduce static authored cases only. Never invokes a client or adapter. */
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
const source=dirname(fileURLToPath(import.meta.url));
if(!process.argv[2])throw new Error('Supply an owned ignored output directory.');
const output=resolve(process.argv[2]);
const sha=(bytes:Uint8Array|string)=>createHash('sha256').update(bytes).digest('hex');
for(const [folder,script] of [['initial','author-case.ts'],['bytes-preview','author-cases.ts'],['boundary-lifecycle','author-cases.ts']]){
 const target=resolve(output,folder!);await mkdir(target,{recursive:true});
 const result=Bun.spawnSync(['bun',resolve(source,folder!,script!),target]);
 if(result.exitCode!==0)throw new Error(result.stderr.toString());
}
const first=await readFile(resolve(output,'initial/first-case.json'));
const cases=[JSON.parse(first.toString())];
for(const folder of ['bytes-preview','boundary-lifecycle']){
 const manifest=JSON.parse(await readFile(resolve(source,folder,folder==='bytes-preview'?'authored-manifest.json':'manifest.json'),'utf8'));
 for(const entry of manifest.cases){const bytes=await readFile(resolve(output,folder,entry.path));if(sha(bytes)!==entry.caseSha256)throw new Error('Authored case differs '+entry.id);cases.push(JSON.parse(bytes.toString()));}
}
const reproduced=JSON.stringify({formatVersion:'0.1.0-draft.28',cases},null,2)+'\n';
const original=await readFile(resolve(source,'../cases.json'),'utf8');
if(reproduced!==original)throw new Error('Combined static corpus differs.');
const receipt={operation:'artifact-client',cases:cases.length,corpusSha256:sha(reproduced),adapterExecuted:false,expectedFromObservedOutput:false};
await writeFile(resolve(output,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify(receipt));
