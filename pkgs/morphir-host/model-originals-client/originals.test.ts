import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {receiveOriginals,inventoryDigest,verifyInventory,type Capture,type Entry,type Hasher} from './originals.ts';
import type {ModelOriginalsSession,ModelOriginalsCaptureExchange,ModelOriginalsProject} from './session.ts';
const hash=():Hasher=>{const value=createHash('sha256');return{update(bytes){value.update(bytes);},hex(){return value.digest('hex');}};};
const original=Buffer.from('\ufeff# original\r\nformatVersion: 4\r\n');
const sha=createHash('sha256').update(original).digest('hex');
const entries:Entry[]=[{kind:'file',entryId:'source',path:'model.yaml',byteLength:original.length,sha256:sha},
  {kind:'directory',entryId:'notes',path:'notes'},{kind:'directory',entryId:'empty',path:'notes/empty'},
  {kind:'file',entryId:'sidecar',path:'notes/opaque.bin',byteLength:4,sha256:'054edec1d0211f624fed0cbca9d4f9400b0e491c43742af2c5b0abebf0c990d8'}];
// Fixed opaque bytes 00 01 02 03 and its independently pinned SHA-256.
const opaque=Buffer.from([0,1,2,3]);
test('inventory digest matches the independent parent wire49 golden',()=>{
 // finos/morphir 1fe76090691b3416c55619eb59689e2eec9a9cdd:
 // spec/workbench/model-originals/0.1.0-draft.1/acceptance/wire49.json.
 // Expected entries and hash are frozen upstream, not computed by this client.
 const golden:Entry[]=[
  {kind:'file',entryId:'entry-model',path:'morphir-ir.json',byteLength:116,sha256:'e01f985b80d1f5da9816984bfc2d9669bd4c0836254edbe0056d1aef1d06cf0f'},
  {kind:'directory',entryId:'entry-notes',path:'notes'},
  {kind:'directory',entryId:'entry-empty',path:'notes/empty'},
  {kind:'file',entryId:'entry-opaque',path:'notes/opaque.bin',byteLength:4,sha256:'3d1f57c984978ef98a18378c8166c1cb8ede02c03eeb6aee7e2f121dfeee3e56'},
 ];
 assert.equal(inventoryDigest(golden,hash()),'8ae541eb3e9c3da4ee65f45ec6d5a39d5431c1e0032d0756030dc7a8fa8466b2');
});
assert.equal(createHash('sha256').update(opaque).digest('hex'),entries[3]!.kind==='file'?entries[3]!.sha256:'');
const capture:Capture={captureId:'capture-A',roots:[{kind:'file',path:'model.yaml'},{kind:'directory',path:'notes'}],entryCount:4,fileCount:2,directoryCount:2,sourceByteLength:original.length+4,sha256:inventoryDigest(entries,hash()),sourceFormatVersion:{status:'reported',release:'4.0.0'}};
const binding={sessionId:'session-A',source:{providerId:'provider-A',locator:'workspace:orders'},projectId:'project-A'};
const shared={profile:'morphir/workbench/model-originals',contractVersion:'0.1.0-draft.1'};
const ready={...shared,status:'ready',binding,captureId:capture.captureId,coverage:{kind:'complete',declaration:shared.contractVersion},
 origin:{kind:'compiled',record:{byteLength:370,sha256:'0'.repeat(64),schema:1,task:'compile',module:'',ir:{path:'model.yaml',layout:'single-file',format:'yaml',version:'v4'}}},
 primary:capture.roots[0],companions:capture.roots.slice(1),sourceFormatVersion:capture.sourceFormatVersion,projection:{status:'not-requested'},
 inventory:{entryCount:4,fileCount:2,directoryCount:2,sourceByteLength:capture.sourceByteLength,sha256:capture.sha256}};
type Mutate=(method:string,value:Record<string,unknown>,id:string)=>string|void;
function peer(mutate:Mutate=()=>{}):ModelOriginalsSession{
 let id=0;
 const exchange=(method:string,value:Record<string,unknown>)=>{const requestId=String(++id);const replacement=mutate(method,value,requestId);return{requestId,request:'',reply:replacement??JSON.stringify({jsonrpc:'2.0',id,result:value})};};
 return{sessionId:'session-A',sources:[],openSource:async()=>[],close(){},
  exchangeCapture:async()=>exchange('capture',structuredClone(ready)),
  async exchangeOriginals(method,params){
   const request=params as {startIndex:number;offset:number;target:{entryId:string}};
   if(method==='release')return exchange(method,{...shared,captureId:capture.captureId,status:'released'});
   if(method==='inventory')return exchange(method,{...shared,binding,captureId:capture.captureId,inventorySha256:capture.sha256,startIndex:request.startIndex,entries,next:{kind:'complete'}});
   const bytes=request.target.entryId==='source'?original:opaque;
   return exchange(method,{...shared,binding,captureId:capture.captureId,target:request.target,offset:request.offset,nextOffset:bytes.length,content:bytes.subarray(request.offset).toString('base64')});
  }};
}
async function receive(mutate?:Mutate){
 const files:Buffer[][]=[];let index=-1,released=false;
 const session=peer((method,value,id)=>{if(method==='release')released=true;return mutate?.(method,value,id);});
 const result=await receiveOriginals(session,{} as ModelOriginalsProject,binding,{
  inventory(){},begin(i){index=i;files[index]=[];},write(bytes){files[index]!.push(Buffer.from(bytes));},end(){},
 },hash,()=>true);
 return{result,files,released};
}
test('complete originals retain BOM/CRLF, opaque bytes and empty directories before confirmed release',async()=>{
 const value=await receive();assert.deepEqual(Buffer.concat(value.files[0]!),original);assert.deepEqual(Buffer.concat(value.files[3]!),opaque);assert.equal(value.released,true);assert.equal(value.result.entries[2]!.path,'notes/empty');
});
for(const [name,mutate]of Object.entries<Mutate>({
 'wrong capture binding':(method,value)=>{if(method==='capture')value.binding={...binding,projectId:'foreign'};},
 'semantic projection substituted':(method,value)=>{if(method==='capture')value.projection={status:'available'};},
 'incomplete inventory':(method,value)=>{if(method==='inventory')value.entries=entries.slice(0,3);},
 'inventory digest mismatch':(method,value)=>{if(method==='inventory')value.inventorySha256='0'.repeat(64);},
 'foreign retained owner':(method,value)=>{if(method==='read')value.captureId='other';},
 'rewound read offset':(method,value)=>{if(method==='read')value.offset=1;},
 'changed byte length':(method,value)=>{if(method==='read')value.nextOffset=1;},
 'changed bytes despite valid base64':(method,value)=>{if(method==='read')value.content=Buffer.alloc(original.length).toString('base64');},
 'noncanonical base64 pad bits':(method,value)=>{if(method==='read')value.content='AB==';},
 'mismatched release':(method,value)=>{if(method==='release')value.captureId='other';},
 'duplicate JSON member':(method,_value,id)=>{if(method==='inventory')return`{"jsonrpc":"2.0","id":${id},"result":{},"result":{}}`;},
 'rounded fractional count':(method,value,id)=>{if(method==='inventory')return JSON.stringify({jsonrpc:'2.0',id:Number(id),result:value}).replace('"startIndex":0','"startIndex":0.0000000000000000000001');},
}))test(name+' prevents verified completion',async()=>{await assert.rejects(receive(mutate));});
test('inventory path aliases, missing directories, and file ancestors refuse even with a self-consistent digest',()=>{
 for(const changed of [
  [...entries.slice(0,3),{...entries[3]!,path:'NOTES/opaque.bin'}],
  entries.filter(item=>item.path!=='notes'),
  [...entries.slice(0,1),{...entries[0]!,path:'model.yaml/child',entryId:'child'}],
 ])assert.throws(()=>verifyInventory(changed,{...capture,entryCount:changed.length,sha256:inventoryDigest(changed,hash())},hash()));
});
