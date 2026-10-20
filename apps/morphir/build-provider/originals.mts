import {openSync,closeSync,writeSync,writeFileSync,constants,lstatSync,existsSync,mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {openModelOriginalsSession,ModelOriginalsConnectionLimits,type ModelOriginalsSession} from '../../../pkgs/morphir-host/model-originals-client/session.ts';
import {receiveOriginals,OriginalsFailure,type Hasher} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';
import {originalsConnectionDescriptor} from '../../../pkgs/morphir-host/model-originals-client/selection.mts';
import {Refusal,refuse,closed,record,readBounded,decode,connection,context,authenticatedWebSocket} from '../../../pkgs/morphir-host/connection/node-session.mts';
import type {Core} from '../../../pkgs/morphir-host/execution-client/contracts.mts';
const profile='morphir/cli/originals-command',contractVersion='0.1.0';
interface Configuration {profile:typeof profile;contractVersion:typeof contractVersion;operation:'list'|'originals';source:string;connection:string;scratch:string;timeout:number;cancelFile:string;}
function configuration(raw:unknown):Configuration {
  if(!closed(raw,['profile','contractVersion','operation','source','connection','scratch','timeout','cancelFile']))refuse('originals.invalid_command');
  const value=raw as unknown as Configuration;
  if(value.profile!==profile||value.contractVersion!==contractVersion||!['list','originals'].includes(value.operation)||
      typeof value.source!=='string'||Buffer.byteLength(value.source)>1048576||typeof value.connection!=='string'||!value.connection||
      typeof value.scratch!=='string'||!value.scratch||typeof value.cancelFile!=='string'||!Number.isInteger(value.timeout)||value.timeout<1||value.timeout>600000)refuse('originals.invalid_command');
  if(process.platform==='win32'||!process.getuid)refuse('connected.private_file_permissions_unavailable');
  const scratch=lstatSync(value.scratch);if(!scratch.isDirectory()||(scratch.mode&0o077)!==0||scratch.uid!==process.getuid())refuse('originals.private_scratch_required');
  return value;
}
function hasher():Hasher {const hash=createHash('sha256');return {update(bytes){hash.update(bytes);},hex(){return hash.digest('hex');}};}
async function acquire(config:Configuration,core:Core,interrupted:()=>boolean):Promise<{code:number;report:object}> {
  const request=decode(core,config.source);
  if(!closed(request,config.operation==='list'?['source']:['source','projectId'])||!record(request)||!closed(request.source,['providerId','locator'])||!record(request.source)||
      typeof request.source.providerId!=='string'||typeof request.source.locator!=='string'||config.operation==='originals'&&typeof request.projectId!=='string')refuse('originals.invalid_selection');
  const selected=connection(core,config.connection);
  const requestedSource={providerId:request.source.providerId,locator:request.source.locator};
  const abort=new AbortController();let stop:'sigint'|'timeout'|'cancel-file'|null=null,session:ModelOriginalsSession|undefined,fd=-1;
  let cleanup:{kind:'not-connected'|'connection-closed'|'released'}={kind:'not-connected'};
  const started=performance.now();
  const requestStop=(reason:NonNullable<typeof stop>)=>{if(!stop){stop=reason;abort.abort();session?.close();}};
  const check=()=>{if(interrupted())requestStop('sigint');if(config.cancelFile&&existsSync(config.cancelFile))requestStop('cancel-file');if(performance.now()-started>=config.timeout)requestStop('timeout');return !stop;};
  const onInterrupt=()=>requestStop('sigint');process.on('SIGINT',onInterrupt);const watch=setInterval(check,20);
  const http=context(selected.origin,selected.cookie,Math.min(config.timeout,10000),abort.signal);
  const report=(observation:string,extra:object={})=>({profile,contractVersion,operation:config.operation,binding:'workbench-http',observation,stopReason:stop,cleanup,...extra});
  try {
    if(!check())return{code:130,report:report('not-published')};
    const manifest=await http.manifest(core);if(manifest.sessionId!==selected.sessionId)refuse('connected.session_changed');
    if(!isDeepStrictEqual(originalsConnectionDescriptor(manifest),selected.descriptor))refuse('connected.offer_changed');
    const opened=await openModelOriginalsSession(new URL(selected.origin),{limits:ModelOriginalsConnectionLimits.create({manifestBytes:131072}),signal:abort.signal,
      fetch:async(url,init)=>http.fetchFn(url.pathname,{headers:init.headers,signal:init.signal??undefined}),createSocket:()=>authenticatedWebSocket(selected)});
    if(opened.kind!=='ready')refuse('originals.profile_unavailable');session=opened.session;cleanup={kind:'connection-closed'};
    if(session.sessionId!==selected.sessionId)refuse('connected.session_changed');
    const source=session.sources.find(item=>item.providerId===requestedSource.providerId&&item.locator===requestedSource.locator);
    if(!source)refuse('originals.source_unavailable');
    const projects=await session.openSource(source);
    if(!check())refuse('originals.cancelled');
    if(config.operation==='list')return{code:0,report:report('discovered',{source:{providerId:source.providerId,locator:source.locator},projects:projects.map(item=>({projectId:item.projectId,name:item.name}))})};
    const project=projects.find(item=>item.projectId===request.projectId);if(!project)refuse('originals.project_unavailable');
    mkdirSync(join(config.scratch,'part-0'),{mode:0o700});mkdirSync(join(config.scratch,'part-1'),{mode:0o700});
    const value=await receiveOriginals(session,project,{sessionId:selected.sessionId,source:{providerId:source.providerId,locator:source.locator},projectId:project.projectId},{
      inventory(entries,capture){
        const bytes=JSON.stringify({capture,entries});if(Buffer.byteLength(bytes)>67108864)refuse('originals.metadata_limit');
        // Fixed-name cleanup remains bounded and usable after SIGINT. Do not
        // enumerate a directory through an interruptible acquisition reader.
        writeFileSync(join(config.scratch,'cleanup-count'),String(entries.length),{flag:'wx',mode:0o600});
        writeFileSync(join(config.scratch,'inventory.json'),bytes,{flag:'wx',mode:0o600});
      },
      begin(index){fd=openSync(join(config.scratch,'part-'+Math.floor(index/65536),'file-'+index),constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|(constants.O_NOFOLLOW||0),0o600);},
      write(bytes){let offset=0;while(offset<bytes.length){const count=writeSync(fd,bytes,offset,bytes.length-offset);if(!count)refuse('originals.local_write_failed');offset+=count;}},
      end(){closeSync(fd);fd=-1;},
    },hasher,check);
    cleanup={kind:'released'};
    if(!check())refuse('originals.cancelled');
    // Recheck session/offer currentness after release and before local publication.
    const current=await http.manifest(core);
    if(current.sessionId!==selected.sessionId||!isDeepStrictEqual(originalsConnectionDescriptor(current),selected.descriptor))refuse('connected.offer_changed');
    if(!check())refuse('originals.cancelled');
    return{code:0,report:report('verified',{inventorySha256:value.capture.sha256,fileCount:value.capture.fileCount,directoryCount:value.capture.directoryCount,sourceByteLength:value.capture.sourceByteLength})};
  }catch(error){
    return{code:stop==='timeout'?1:stop?130:error instanceof Refusal?2:1,report:report('not-published',{error:error instanceof Refusal||error instanceof OriginalsFailure?error.code:'originals.verification_failed'})};
  }finally{if(fd>=0)closeSync(fd);clearInterval(watch);process.off('SIGINT',onInterrupt);session?.close();http.close();}
}
export async function originalsCommand(raw:unknown,suppliedCore?:Core,interrupted:()=>boolean=()=>false):Promise<{code:number;report:object}> {
  try {
    const config=configuration(raw);let core=suppliedCore;
    if(!core){await import(new URL('../dist/connected-core.js',import.meta.url).href);core=(globalThis as typeof globalThis&{__morphirConnectedCore?:()=>Core}).__morphirConnectedCore?.();}
    if(!core)refuse('connected.validation_core_unavailable');return await acquire(config,core,interrupted);
  }catch(error){return{code:2,report:{profile,contractVersion,observation:'refused',cleanup:{kind:'not-connected'},error:error instanceof Refusal?error.code:'originals.invalid_command'}};}
}
if(process.argv[1]&&pathToFileURL(process.argv[1]).href===import.meta.url){
  let value;try{if(process.argv[2]!=='--morphir-originals-v1'||!process.argv[3]||process.argv.length!==4)refuse('originals.invalid_command');value=await originalsCommand(JSON.parse(readBounded(process.argv[3],4194304)));}
  catch{value={code:2,report:{profile,contractVersion,observation:'refused',cleanup:{kind:'not-connected'},error:'originals.invalid_command'}};}
  console.log(JSON.stringify(value.report));process.exitCode=value.code;
}
