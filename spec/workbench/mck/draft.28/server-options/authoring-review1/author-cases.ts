/** Independent static refusal expectations, before production fix/execution.
 * No host, adapter, or observed report is imported. SDK options are a named map.
 */
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const directory=resolve(process.argv[2]??dirname(fileURLToPath(import.meta.url)));
const profile='morphir/workbench/artifacts',version='0.1.0-draft.1';
const usage={event:'usage',invocations:0,reservedBytes:0,reservedGenerations:0,activeInvocations:0};
const values:[string,unknown][]=[['null',null],['boolean',true],['number',0],['string','preset'],['empty-array',[]],['nested-array',[{nested:1}]]];
const cases=values.map(([name,options])=>({id:'options-nonobject-'+name,operation:'artifact-server',format:'json',input:{fixture:{producer:{id:'artifact-fixture',version:'0.1.0'},offer:'exact',completion:'success',artifacts:[],diagnostics:[]},actions:[{action:'connect',connection:'c1',authentication:'valid'},{action:'initialize',connection:'c1'},{action:'generate',connection:'c1',generation:'g1',requestId:'2',params:JSON.stringify({contractVersion:version,providerId:'playground',generation:{ir:{formatVersion:4},irVersion:'4',target:'fixture',options}})},{action:'usage'},{action:'close',connection:'c1'},{action:'usage'}]},expected:{status:'ok',value:{sessionId:'session-fixture',providerId:'playground',events:[{event:'connected',connection:'c1',status:'accepted'},{event:'initialized',connection:'c1',status:'initialized'},{event:'generated',connection:'c1',generation:'g1',requestId:'2',reply:JSON.stringify({jsonrpc:'2.0',id:2,error:{code:-32602,message:'Invalid artifact request.',data:{profile,contractVersion:version,code:'artifacts.invalid_request'}}})},usage,{event:'closed',connection:'c1'},usage]}}}));
const text=JSON.stringify({formatVersion:'0.1.0-draft.28',cases},null,2)+'\n';
await mkdir(directory,{recursive:true});const target=resolve(directory,'cases.json');
const previous=await readFile(target,'utf8').catch(()=>null);if(previous!==null&&previous!==text)throw Error('Refusing to rewrite frozen options cases.');
await writeFile(target,text);
const sha=(text:string)=>createHash('sha256').update(text).digest('hex');
await writeFile(resolve(directory,'independence-receipt.json'),JSON.stringify({operation:'artifact-server',scope:'Artifact-only non-object option refusal before SDK invocation or host reservation.',cases:cases.length,corpusSha256:sha(text),expectedFromObservedOutput:false,authorSha256:sha(await readFile(fileURLToPath(import.meta.url),'utf8')),sources:['SDK GenerateRequest.options HashMap<String,Value>','ArtifactError::InvalidRequest / artifact_rpc_error maps INVALID_PARAMS before state.artifacts.begin'],caseHashes:cases.map(item=>({id:item.id,inputSha256:sha(JSON.stringify(item.input)),expectedSha256:sha(JSON.stringify(item.expected))}))},null,2)+'\n');console.log(JSON.stringify({cases:cases.length,sha256:sha(text)}));
