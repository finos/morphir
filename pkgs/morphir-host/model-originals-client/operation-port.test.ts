import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {openConsumerOperationPort} from './operation-port.ts';

test('ordinary launches do not create an operation observer',()=>{
  assert.equal(openConsumerOperationPort('outer', {}),undefined);
});

test('business preparation failures poison before writing and later hooks do not construct data',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const result=await socketRun(`const outer=openConsumerOperationPort('outer');let called=0;
  console.log(outer.emit(()=>{called++;throw Error('local preparation failed');}));
  console.log(outer.emit(()=>{called++;throw Error('must not run');}));
  console.log(outer.finish({kind:'in-process'}),called);`);
 assert.equal(result.code,0,result.stderr);
 assert.equal(result.stdout.trim(),'faulted\nfaulted\nfaulted 1');
 assert.deepEqual(result.frames[0]!.map(frame=>frame.kind),['open']);
});

import {createServer,createConnection,type Socket} from 'node:net';
import {spawn,execFileSync} from 'node:child_process';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const moduleUrl=new URL('./operation-port.ts',import.meta.url).href;
let launcherDirectory:string|undefined;
async function actualNonblockingLauncher():Promise<string>{
 if(!launcherDirectory){
  launcherDirectory=await mkdtemp(join(tmpdir(),'morphir-port-exec-'));
  // Node child_process normalizes stdio-slot sockets to blocking. The real
  // Rust launcher inherits actual O_NONBLOCK UnixStream owners, not stdio slots.
  // Restore that precise pre-exec ABI in this test-only launcher.
  execFileSync('cc',['-x','c','-o',join(launcherDirectory,'exec'),'-'],{input:`
   #include <fcntl.h>
   #include <unistd.h>
   int main(int argc,char **argv){
    if(argc<2)return 90;
    for(int fd=3;fd<=4;fd++){
     int flags=fcntl(fd,F_GETFL);if(flags<0||fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0)return 91;
     if(!(fcntl(fd,F_GETFL)&O_NONBLOCK))return 92;
    }
    execvp(argv[1],argv+1);return 93;
   }`});
 }
 return join(launcherDirectory,'exec');
}
after(async()=>{if(launcherDirectory)await rm(launcherDirectory,{recursive:true});});
async function socketRun(body:string,options:{ack?:(frame:Record<string,unknown>,role:number)=>Buffer|null; timeoutMs?:number; deadlineStart?:'before-spawn'|'after-module-import'; env?:Record<string,string>;fragmentAck?:boolean;pauseReadMs?:number;closeOnKind?:string}={}){
 const launcher=await actualNonblockingLauncher();
 const dir=await mkdtemp(join(tmpdir(),'morphir-port-')),path=join(dir,'socket');
 const server=createServer();await new Promise<void>(resolve=>server.listen(path,resolve));
 const accepted:Socket[]=[];const producer:Socket[]=[];
 for(let i=0;i<2;i++){
  const peer=new Promise<Socket>(resolve=>server.once('connection',resolve));
  const socket=createConnection(path);await new Promise<void>(resolve=>socket.once('connect',resolve));
  producer.push(socket);accepted.push(await peer);
 }
 const frames:Record<string,unknown>[][]=[[],[]];
 for(const [role,socket]of accepted.entries()){
  let pending=Buffer.alloc(0);
  if(options.pauseReadMs){socket.pause();setTimeout(()=>socket.resume(),options.pauseReadMs);}
  socket.on('error',()=>{});socket.on('data',(bytes:Buffer)=>{
   pending=Buffer.concat([pending,bytes]);
   while(pending.length>=4&&pending.length>=4+pending.readUInt32BE()){
    const length=pending.readUInt32BE(),frame=JSON.parse(pending.subarray(4,4+length).toString('utf8')) as Record<string,unknown>;
    pending=pending.subarray(4+length);frames[role]!.push(frame);
    if(options.closeOnKind===frame.kind){socket.destroy();return;}
    const ack=options.ack?options.ack(frame,role):Buffer.from(JSON.stringify({kind:'retained',version:'0.1.0-draft.1',sequence:frame.sequence}));
    if(ack){const header=Buffer.alloc(4);header.writeUInt32BE(ack.length);
     if(options.fragmentAck){const framed=Buffer.concat([header,ack]);let cursor=0;const timer=setInterval(()=>{if(socket.destroyed||cursor===framed.length){clearInterval(timer);return;}socket.write(framed.subarray(cursor,cursor+1));cursor++;},1);}
     else{socket.write(header);socket.write(ack);}}
   }
  });
 }
 const now=process.hrtime.bigint();
 const env={...process.env,MORPHIR_PRIVATE_CONSUMER_OUTER_FD:'3',MORPHIR_PRIVATE_CONSUMER_HELPER_FD:'4',
  MORPHIR_PRIVATE_CONSUMER_VERSION:'0.1.0-draft.1',MORPHIR_PRIVATE_CONSUMER_CLOCK_VERSION:'0.1.0-draft.1',
  MORPHIR_PRIVATE_CONSUMER_CLOCK_DOMAIN:'darwin-mach-continuous-nanoseconds',MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS:String(now),
  MORPHIR_PRIVATE_CONSUMER_END_NS:String(now+BigInt(options.timeoutMs??2000)*1000000n),
  MORPHIR_PRIVATE_CONSUMER_TIMEBASE_NUMER:'125',MORPHIR_PRIVATE_CONSUMER_TIMEBASE_DENOM:'3',...options.env};
 // The short withheld-ACK control starts its one deadline after loading the
 // test module, before the factory sees either endpoint. Process startup and
 // TypeScript parsing must not decide whether this I/O control reaches Open.
 // No opened producer is extended and both roles still receive the SAME end.
 const deadlineSetup=options.deadlineStart==='after-module-import'
  ? `const at=process.hrtime.bigint();process.env.MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS=String(at);process.env.MORPHIR_PRIVATE_CONSUMER_END_NS=String(at+${BigInt(options.timeoutMs??2000)*1000000n}n);`:'';
 const child=spawn(launcher,[process.execPath,'--input-type=module','-e',`import {openConsumerOperationPort} from ${JSON.stringify(moduleUrl)};${deadlineSetup}${body}`],{env,stdio:['ignore','pipe','pipe',producer[0]!,producer[1]!]});
 for(const socket of producer)socket.destroy();
 let stdout='',stderr='';child.stdout!.setEncoding('utf8').on('data',text=>{stdout+=text;});child.stderr!.setEncoding('utf8').on('data',text=>{stderr+=text;});
 const timer=setTimeout(()=>child.kill('SIGKILL'),5000);
 const code=await new Promise<number|null>(resolve=>child.once('close',resolve));clearTimeout(timer);
 for(const socket of accepted)socket.destroy();await new Promise<void>(resolve=>server.close(()=>resolve()));await rm(dir,{recursive:true});
 return{code,stdout,stderr,frames};
}
test('actual inherited endpoints synchronously retain Open and healthy Close without running producer event loop',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const result=await socketRun(`let ticked=false;setTimeout(()=>{ticked=true;},0);const outer=openConsumerOperationPort('outer');const helper=openConsumerOperationPort('transfer-helper');console.log(helper.finish({kind:'not-applicable'}),outer.finish({kind:'in-process'}),ticked);`);
 assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'retained retained false');
 assert.deepEqual(result.frames.map(frames=>frames.map(frame=>frame.kind)),[['open','close'],['open','close']]);
 assert.equal(result.frames[0]![1]!.attemptedHooks,0);
});

test('three actual business facts retain exact UTF8 operands and independent per-role counters',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const result=await socketRun(`const outer=openConsumerOperationPort('outer'),helper=openConsumerOperationPort('transfer-helper');
  console.log(helper.emit({kind:'release-accepted',requestId:'18446744073709551615',captureId:'capture',binding:{sessionId:'s',providerId:'p',sourceLocator:'workspace:x',projectId:'project'},requestSha256:'a'.repeat(64),replySha256:'b'.repeat(64)}));
  console.log(helper.finish({kind:'not-applicable'}));
  console.log(outer.emit({kind:'destination-commit-finished',path:{kind:'unix-bytes',bytes:{kind:'utf8',text:'/tmp/模型'}},policy:'create',outcome:'returned'}));
  console.log(outer.emit({kind:'scratch-cleanup-finished',path:{kind:'unix-bytes',bytes:{kind:'utf8',text:'/tmp/scratch'}},outcome:'raised'}));
  console.log(outer.finish({kind:'in-process'}));`);
 assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'retained\nretained\nretained\nretained\nretained');
 assert.deepEqual(result.frames.map(items=>items.map(item=>item.sequence)),[[0,1,2,3],[0,1,2]]);
 assert.deepEqual(result.frames.map(items=>{const last=items.at(-1)!;return[last.attemptedHooks,last.startedFactFrames,last.retainedBusinessFacts];}),[[2,2,2],[1,1,1]]);
 assert.equal(JSON.stringify(result.frames[0]![1]!.fact).includes('模型'),true);
 assert.equal(result.frames.flat().length,7);
});

test('wrong-role and repeated business hooks poison before another frame and finish cannot repair delivery',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const release=`{kind:'release-accepted',requestId:'1',captureId:'c',binding:{sessionId:'s',providerId:'p',sourceLocator:'w',projectId:'p'},requestSha256:'a'.repeat(64),replySha256:'b'.repeat(64)}`;
 for(const [role,body,kinds]of [
  ['outer',`const owner=openConsumerOperationPort('outer');console.log(owner.emit(${release}));`,['open']],
  ['transfer-helper',`const owner=openConsumerOperationPort('transfer-helper');console.log(owner.emit(${release}));console.log(owner.emit(${release}));`,['open','fact']],
 ]as const){
  const result=await socketRun(body+`console.log(owner.finish({kind:${JSON.stringify(role==='outer'?'in-process':'not-applicable')}}));`);
  assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim().endsWith('faulted\nfaulted'),true,result.stdout);
  assert.deepEqual(result.frames[role==='outer'?0:1]!.map(frame=>frame.kind),kinds);
 }
});

test('withheld ACK expires at the original end; later hooks and finish perform no further protocol IO',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const started=performance.now();
 const result=await socketRun(`const owner=openConsumerOperationPort('outer');const t=process.hrtime.bigint();console.log(owner.emit({kind:'scratch-cleanup-finished',path:{kind:'unix-bytes',bytes:{kind:'utf8',text:'/s'}},outcome:'returned'}),owner.finish({kind:'in-process'}),String(process.hrtime.bigint()-t));`,{ack:()=>null,timeoutMs:150,deadlineStart:'after-module-import'});
 assert.equal(result.code,0,result.stderr);const [first,second,elapsed]=result.stdout.trim().split(' ');
 assert.equal(first,'faulted');assert.equal(second,'faulted');assert.ok(BigInt(elapsed!)<10000000n,'poisoned calls must not wait again');
 assert.ok(performance.now()-started<1500);assert.deepEqual(result.frames[0]!.map(frame=>frame.kind),['open']);
});

test('malformed or mismatched ACK poisons the endpoint without a later Close',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 for(const ack of [Buffer.from('{"kind":"retained","version":"0.1.0-draft.1","sequence":1}'),
  Buffer.from('{"kind":"retained","version":"0.1.0-draft.1","sequence":0,"sequence":0}'),Buffer.from([0xff])]){
  const result=await socketRun(`const owner=openConsumerOperationPort('outer');console.log(owner.finish({kind:'in-process'}));`,{ack:()=>ack});
  assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'faulted');assert.equal(result.frames[0]!.length,1);
 }
});

test('invalid canonical launch metadata is nonthrowing and sends no frame',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 for(const [suffix,value]of Object.entries({OUTER_FD:'03',HELPER_FD:'3',VERSION:'v0.1.0-draft.1',CLOCK_DOMAIN:'monotonic',CLOCK_VERSION:'1',CLOCK_AT_NS:'-1',END_NS:'18446744073709551616',TIMEBASE_NUMER:'126',TIMEBASE_DENOM:'03'})){
  const result=await socketRun(`const owner=openConsumerOperationPort('outer');console.log(owner.finish({kind:'in-process'}));`,{env:{['MORPHIR_PRIVATE_CONSUMER_'+suffix]:value}});
  assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'faulted');assert.deepEqual(result.frames,[[],[]]);
 }
});

test('actual partial socket writes and byte-fragmented ACK reads preserve a single outstanding UTF8 frame',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const result=await socketRun(`const owner=openConsumerOperationPort('outer');console.log(owner.emit({kind:'destination-commit-finished',path:{kind:'unix-bytes',bytes:{kind:'utf8',text:'/'+String.fromCharCode(1).repeat(131071)}},policy:'create',outcome:'returned'}));console.log(owner.finish({kind:'in-process'}));`,{fragmentAck:true,pauseReadMs:80});
 assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'retained\nretained');
 const path=(result.frames[0]![1]!.fact as {path:{bytes:{text:string}}}).path.bytes.text;
 assert.equal(Buffer.byteLength(path),131072);assert.deepEqual(result.frames[0]!.map(frame=>frame.sequence),[0,1,2]);
});

test('native transfer helper only closes its own moved fd, even when Outer descriptor number has been reused',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const result=await socketRun(`const fs=await import('node:fs');fs.closeSync(3);const reused=fs.openSync('/dev/null','r');if(reused!==3)throw new Error('fixture did not reuse3');const helper=openConsumerOperationPort('transfer-helper');console.log(helper.finish({kind:'not-applicable'}),fs.fstatSync(reused).isCharacterDevice());fs.closeSync(reused);`);
 assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'retained true');assert.deepEqual(result.frames[0],[]);assert.deepEqual(result.frames[1]!.map(frame=>frame.kind),['open','close']);
});

test('Close rejects the other role terminal shape before writing and remains nonthrowing',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const result=await socketRun(`const helper=openConsumerOperationPort('transfer-helper');console.log(helper.finish({kind:'in-process'}));`);
 assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'faulted');assert.deepEqual(result.frames[1]!.map(frame=>frame.kind),['open']);
});

test('collector EOF after caching a business frame poisons without any cleanup or Close observer traffic',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const result=await socketRun(`const owner=openConsumerOperationPort('outer');console.log(owner.emit({kind:'destination-commit-finished',path:{kind:'unix-bytes',bytes:{kind:'hex',hex:'2f746d70ff'}},policy:'create',outcome:'returned'}));console.log('application cleanup ran');console.log(owner.emit({kind:'scratch-cleanup-finished',path:{kind:'unix-bytes',bytes:{kind:'utf8',text:'/tmp/scratch'}},outcome:'returned'}),owner.finish({kind:'in-process'}));`,{closeOnKind:'fact'});
 assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'faulted\napplication cleanup ran\nfaulted faulted');
 assert.deepEqual(result.frames[0]!.map(frame=>frame.kind),['open','fact']);
});

test('unrepresentable business data faults before writing any business frame',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 for(const invalid of [
  `{kind:'scratch-cleanup-finished',path:{kind:'unix-bytes',bytes:{kind:'utf8',text:'/s'}},outcome:'returned',verdict:'pass'}`,
  `{kind:'scratch-cleanup-finished',path:{kind:'unix-bytes',bytes:{kind:'utf8',text:'x'.repeat(131073)}},outcome:'returned'}`,
  `{kind:'scratch-cleanup-finished',path:{kind:'unix-bytes',bytes:{kind:'hex',hex:'FF'}},outcome:'returned'}`,
  `{kind:'scratch-cleanup-finished',path:{kind:'unix-bytes',bytes:{kind:'utf8',text:String.fromCharCode(0xd800)}},outcome:'returned'}`,
 ]){
  const result=await socketRun(`const owner=openConsumerOperationPort('outer');console.log(owner.emit(${invalid}),owner.finish({kind:'in-process'}));`);
  assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'faulted faulted');assert.deepEqual(result.frames[0]!.map(frame=>frame.kind),['open']);
 }
});

test('a second factory call cannot duplicate or reclaim a consumed endpoint owner',{skip:process.platform!=='darwin'||process.arch!=='arm64'},async()=>{
 const result=await socketRun(`const fs=await import('node:fs');const owner=openConsumerOperationPort('outer');const duplicate=openConsumerOperationPort('outer');const a=duplicate.finish({kind:'in-process'}),b=owner.finish({kind:'in-process'});const reused=fs.openSync('/dev/null','r');if(reused!==3)throw new Error('fixture must reuse3');console.log(a,b);console.log(openConsumerOperationPort('outer').finish({kind:'in-process'}),fs.fstatSync(reused).isCharacterDevice());fs.closeSync(reused);`);
 assert.equal(result.code,0,result.stderr);assert.equal(result.stdout.trim(),'faulted retained\nfaulted true');assert.deepEqual(result.frames[0]!.map(frame=>frame.kind),['open','close']);
});
