import { fileURLToPath } from 'node:url';
import {resolve,dirname} from 'node:path';
const output=resolve(process.argv[2] ?? dirname(fileURLToPath(import.meta.url)));
/** Independently authored from the reviewed operation semantics. This file
 * imports no production client or adapter and never reads an observed report.
 */
const empty='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const bytes={byteLength:0,sha256:empty};
const text={utf16Length:0,utf8:bytes};
const context={sourceId:'client-source',revision:1,epoch:1};
const cleanup={kind:'released',generationId:'generation-A'};
const pending={kind:'pending'};
const verified={kind:'verified',cleanup};
const request=(id:number,method:string,params:unknown)=>({kind:'text',source:JSON.stringify({jsonrpc:'2.0',id:id===5?4:id,method,params})});
const effect=(index:number,effect:string,argument:unknown)=>({kind:'effect',attempt:'A',index,effect,argument});
const settled=(index:number)=>({kind:'settled',attempt:'A',index,settlement:'resolved'});
const events=[
 effect(0,'connect',{signalAborted:false}),settled(0),
 effect(1,'initialize',{frame:request(1,'morphir.session.initialize',{protocolVersion:1,sessionId:'session-client'})}),settled(1),
 effect(2,'generate',{frame:request(2,'morphir.artifacts.generate',{contractVersion:'0.1.0-draft.1',providerId:'provider-client',generation:{ir:{formatVersion:4},irVersion:'4',target:'fixture',options:{}}})}),settled(2),
 effect(3,'read',{frame:request(3,'morphir.artifacts.read',{contractVersion:'0.1.0-draft.1',generationId:'generation-A',artifactId:'artifact-A',offset:0,maxBytes:65536})}),settled(3),
 effect(4,'digest',bytes),settled(4),
 effect(5,'release',{frame:request(5,'morphir.artifacts.release',{contractVersion:'0.1.0-draft.1',generationId:'generation-A'})}),settled(5),
 {kind:'close',attempt:'A'},
];
const view={file:'file-0',path:'empty.bin',binary:true,encoding:'verified-bytes',byteLength:0,previewState:'binary',content:text,binaryPreview:bytes,reference:{views:'views-A',file:'file-0'}};
const file={path:'empty.bin',bytes};
// Each row is an authored checkpoint, not the output of a controller model.
const states=[
 ['not-started',null,[],pending,0],
 ['connecting',false,[{index:0,effect:'connect'}],pending,0],
 ['initializing',false,[{index:1,effect:'initialize'}],pending,0],
 ['generating',false,[{index:2,effect:'generate'}],pending,0],
 ['receiving',false,[{index:3,effect:'read'}],pending,0],
 ['verifying',false,[{index:4,effect:'digest'}],pending,0],
 ['releasing',false,[{index:5,effect:'release'}],pending,0],
 ['finished',false,[],verified,1],
 ['finished',false,[],verified,1],
 ['finished',false,[],verified,1],
 ['finished',false,[],verified,1],
 ['finished',false,[],verified,1],
 ['finished',false,[],verified,1],
 ['finished',false,[],verified,1],
] as const;
const checkpoints=states.map(([phase,signalAborted,pending,terminal,closeCalls],actionIndex)=>({
 actionIndex,eventCount:[0,1,3,5,7,9,11,13,13,13,13,13,13,13][actionIndex],label:actionIndex===13?'released-original-empty-bytes':null,currentContext:context,
 attempts:[{id:'A',phase,pending,signalAborted,terminal,closeCalls}],
 registry:actionIndex>=8&&actionIndex<11?{kind:'published',views:'views-A'}:{kind:'empty'},
 actionResult:actionIndex===8?{kind:'published',views:'views-A',artifacts:[view]}:
 actionIndex===9?{kind:'download',files:[file]}:
 actionIndex===10?{kind:'archive',archive:{encodedByteLength:116,entries:[file]}}:
 actionIndex===12?{kind:'refused',operation:'download',message:'These generated files are no longer available. Recompile to download them.'}:{kind:'none'},
}));
const value={events,checkpoints,attempts:[{
 id:'A',capture:{profile:'morphir/workbench/artifacts',contractVersion:'0.1.0-draft.1',providerId:'provider-client',sessionId:'session-client',target:'fixture',irVersion:'4'},phase:'finished',
 result:{kind:'verified',manifest:{profile:'morphir/workbench/artifacts',contractVersion:'0.1.0-draft.1',sessionId:'session-client',providerId:'provider-client',generationId:'generation-A',producer:{id:'artifact-fixture',version:'0.1.0'},target:'fixture',irVersion:'4',diagnostics:[]},inventory:[{id:'file-0',path:'empty.bin',declaredKind:'binary',bytes,preview:{kind:'binary',prefix:bytes}}],cleanup},
 closeCalls:1,effects:{connect:1,initialize:1,generate:1,read:1,digest:1,release:1},
}]};
const input=await Bun.file(new URL('./first-input.json',import.meta.url)).json();
await Bun.write(resolve(output,'first-case.json'),JSON.stringify({id:'client-empty-original-bytes-and-stale-views',operation:'artifact-client',format:'json',input,expected:{status:'ok',value}},null,2)+'\n');
