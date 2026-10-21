/** Application-test collector only. These observations issue no runner authority,
 * verdict, source grant or full-profile qualification. The actual CLI owns its
 * original application result and cleanup, including after a withheld ACK. */
import {spawn,execFileSync,type ChildProcess} from 'node:child_process';
import {createServer,createConnection,type Socket} from 'node:net';
import {mkdtemp,rm} from 'node:fs/promises';
import {realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {StringDecoder} from 'node:string_decoder';

export interface ObservedOriginalsOptions {
 dropAckKind?:'destination-commit-finished'|'release-accepted';
 endMs?:number;
 target?:'js'|'native';
}
export interface ObservedOriginalsResult {
 code:number|null;stdout:string;stderr:string;frames:Record<string,unknown>[][];
}
const version='0.1.0-draft.1',selectorPrefix='MORPHIR_PRIVATE_CONSUMER_';
const selectorNames=['OUTER_FD','HELPER_FD','VERSION','CLOCK_DOMAIN','CLOCK_VERSION','CLOCK_AT_NS','END_NS','TIMEBASE_NUMER','TIMEBASE_DENOM'];
const payloadLimit=131072*6+512,outputLimit=1048576,clockLimit=6148914691236517166n;
const decoder=new TextDecoder('utf-8',{fatal:true});

/** The source-owned caller selects an actual canonical publish and its target.
 * The nine selectors are fixture outputs, never caller authority or routing. */
export async function runObservedOriginals(executable:string,args:string[],cwd:string,env:NodeJS.ProcessEnv,
 options:ObservedOriginalsOptions={}):Promise<ObservedOriginalsResult>{
 if(process.platform!=='darwin'||process.arch!=='arm64')throw Error('Operation observation fixture requires Darwin arm64');
 for(const name of selectorNames)if(env[selectorPrefix+name]!==undefined)throw Error('Caller observation selector collision: '+name);
 const endMs=options.endMs??(options.dropAckKind?1000:5000);
 if(!Number.isInteger(endMs)||endMs<1||endMs>10000)throw Error('Operation fixture fixed-end range');
 const native=options.target?options.target==='native':realpathSync(executable)!==realpathSync(process.execPath);
 const directory=await mkdtemp(join(tmpdir(),'morphir-observe-'));
 const server=createServer(),producer:Socket[]=[],collector:Socket[]=[],ends:Promise<void>[]=[];
 const frames:Record<string,unknown>[][]=[[],[]];
 let child:ChildProcess|undefined,closed:Promise<number|null>|undefined,stopTimer:ReturnType<typeof setTimeout>|undefined;
 let forceTimer:ReturnType<typeof setTimeout>|undefined,retainedDirectory=false,helperStarted=!native,failure:Error|undefined;
 let forceKilled=false,stdout='',stderr='',outputBytes=0;
 const stdoutDecoder=new StringDecoder('utf8'),stderrDecoder=new StringDecoder('utf8');
 const revoke=()=>{for(const socket of collector)socket.destroy();};
 const fail=(error:unknown)=>{
  failure??=error instanceof Error?error:Error(String(error));revoke();
  // End protocol I/O first, then request genuine application cancellation.
  // Its C owner still has to consume the real helper wait and dispose outputs.
  if(child?.exitCode===null&&child.signalCode===null)child.kill('SIGINT');
 };
 try{
  // Node child_process normalizes descriptors supplied as stdio slots. This
  // test-only exec restores the actual runner's O_NONBLOCK inherited-fd ABI,
  // then execs the unchanged selected program/argv; it is not a CLI wrapper.
  const preexec=join(directory,'exec');
  execFileSync('cc',['-x','c','-o',preexec,'-'],{timeout:10000,input:`
   #include <fcntl.h>
   #include <unistd.h>
   int main(int argc,char **argv){
    if(argc<2)return 90;
    for(int fd=3;fd<=4;fd++){
     int flags=fcntl(fd,F_GETFL);if(flags<0||fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0)return 91;
    }
    execvp(argv[1],argv+1);return 93;
   }`});
  await new Promise<void>((resolve,reject)=>{server.once('error',reject);server.listen(join(directory,'socket'),resolve);});
  for(let role=0;role<2;role++){
   const accepted=new Promise<Socket>(resolve=>server.once('connection',resolve));
   const socket=createConnection(join(directory,'socket'));producer.push(socket);
   await new Promise<void>((resolve,reject)=>{socket.once('connect',resolve);socket.once('error',reject);});
   const peer=await accepted;collector.push(peer);
   ends.push(new Promise<void>(resolve=>{peer.once('end',resolve);peer.once('close',()=>resolve());}));
  }
  type State={pending:Buffer;blocked?:Record<string,unknown>;poisoned:boolean;closed:boolean;sequence:number};
  const states:State[]=[0,1].map(()=>({pending:Buffer.alloc(0),poisoned:false,closed:false,sequence:0}));
  const acknowledge=(role:number,frame:Record<string,unknown>)=>{
   const state=states[role]!;if(state.poisoned||failure)return;
   const fact=frame.fact as Record<string,unknown>|undefined;
   if(frame.kind==='fact'&&fact?.kind===options.dropAckKind){state.poisoned=true;return;}
   const payload=Buffer.from(JSON.stringify({kind:'retained',version,sequence:frame.sequence}),'utf8');
   const header=Buffer.alloc(4);header.writeUInt32BE(payload.length);
   // The immutable frame already belongs to frames[role] before any ACK bytes.
   collector[role]!.write(Buffer.concat([header,payload]));
  };
  const pump=(role:number)=>{
   const state=states[role]!;
   while(!failure&&!state.blocked&&state.pending.length>=4){
    const length=state.pending.readUInt32BE();
    if(length<1||length>payloadLimit)throw Error('Operation fixture frame bound');
    if(state.pending.length<4+length)return;
    if(state.closed)throw Error('Operation fixture bytes after Close');
    const body=state.pending.subarray(4,4+length);state.pending=state.pending.subarray(4+length);
    const frame:unknown=JSON.parse(decoder.decode(body));
    if(!frame||typeof frame!=='object'||Array.isArray(frame))throw Error('Operation fixture envelope');
    const item=frame as Record<string,unknown>;
    if(item.version!==version||item.sequence!==state.sequence||!Number.isInteger(item.sequence))throw Error('Operation fixture version/sequence');
    if(!['open','fact','helper-started','close'].includes(item.kind as string)||state.sequence===0&&item.kind!=='open'||state.sequence!==0&&item.kind==='open')throw Error('Operation fixture control order');
    if(frames[role]!.length>=(role===0?(native?5:4):3)||frames[0]!.length+frames[1]!.length>=8)throw Error('Operation fixture frame count');
    if(item.kind==='helper-started'&&(!native||role!==0||helperStarted))throw Error('Operation fixture delegation order');
    // Pure transport framing checks are deliberately not a replacement for the
    // maintained checker. Business facts remain uninterpreted test DATA here.
    frames[role]!.push(item);state.sequence++;
    if(item.kind==='close')state.closed=true;
    if(item.kind==='open'&&role===1&&!helperStarted){state.blocked=item;return;}
    acknowledge(role,item);
    if(item.kind==='helper-started'){
     helperStarted=true;const helper=states[1]!;
     if(helper.blocked){const retained=helper.blocked;delete helper.blocked;acknowledge(1,retained);pump(1);}
    }
   }
  };
  for(const [role,socket]of collector.entries()){
   socket.on('error',error=>{if(!failure)fail(error);});
   socket.on('data',(data:Buffer)=>{
    try{
     const state=states[role]!;
     if(state.pending.length+data.length>payloadLimit+4)throw Error('Operation fixture receive bound');
     state.pending=Buffer.concat([state.pending,data]);pump(role);
    }catch(error){fail(error);}
   });
  }
  const at=process.hrtime.bigint(),end=at+BigInt(endMs)*1000000n;
  if(failure)throw failure;
  if(end>clockLimit)throw Error('Operation fixture selected clock horizon');
  const observedEnvironment={...env,
   MORPHIR_PRIVATE_CONSUMER_OUTER_FD:'3',MORPHIR_PRIVATE_CONSUMER_HELPER_FD:'4',
   MORPHIR_PRIVATE_CONSUMER_VERSION:version,MORPHIR_PRIVATE_CONSUMER_CLOCK_VERSION:version,
   MORPHIR_PRIVATE_CONSUMER_CLOCK_DOMAIN:'darwin-mach-continuous-nanoseconds',
   MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS:String(at),MORPHIR_PRIVATE_CONSUMER_END_NS:String(end),
   MORPHIR_PRIVATE_CONSUMER_TIMEBASE_NUMER:'125',MORPHIR_PRIVATE_CONSUMER_TIMEBASE_DENOM:'3'};
  child=spawn(preexec,[executable,...args],{cwd,env:observedEnvironment,detached:true,stdio:['ignore','pipe','pipe',producer[0]!,producer[1]!]});
  closed=new Promise<number|null>(resolve=>child!.once('close',resolve));
  child.once('error',fail);
  for(const socket of producer)socket.destroy();
  child.stdout!.on('data',(data:Buffer)=>{outputBytes+=data.length;if(outputBytes>outputLimit)fail(Error('Operation fixture output bound'));else stdout+=stdoutDecoder.write(data);});
  child.stderr!.on('data',(data:Buffer)=>{outputBytes+=data.length;if(outputBytes>outputLimit)fail(Error('Operation fixture output bound'));else stderr+=stderrDecoder.write(data);});
  stopTimer=setTimeout(()=>{
   fail(Error('Operation fixture watchdog: genuine application completion missing'));
   if(child?.exitCode!==null||child.signalCode!==null)retainedDirectory=true;
   forceTimer=setTimeout(()=>{
    if(!child||child.exitCode!==null||child.signalCode!==null)return;
    forceKilled=true;retainedDirectory=true;
    // This owns only the actual outer group. The separate C helper group is
    // never inferred from a PID string, and cleanup is explicitly incomplete.
    if(child.pid){try{process.kill(-child.pid,'SIGKILL');}catch{child.kill('SIGKILL');}}
   },1000);
  },25000);
  const code=await closed;stdout+=stdoutDecoder.end();stderr+=stderrDecoder.end();
  // Physical peer EOF follows actual owners/process lifetime, not logical Close.
  await Promise.all(ends);
  clearTimeout(stopTimer);clearTimeout(forceTimer);
  if(states.some(state=>state.pending.length!==0||state.blocked))failure??=Error('Operation fixture incomplete physical frame/delegation');
  if(forceKilled)throw Error('Operation fixture forced outer death; helper cleanup incomplete; retained '+directory);
  if(failure)throw retainedDirectory?Error(failure.message+'; helper cleanup incomplete; retained '+directory):failure;
  return{code,stdout,stderr,frames};
 }finally{
  clearTimeout(stopTimer);clearTimeout(forceTimer);
  for(const socket of [...producer,...collector])socket.destroy();
  if(child&&child.exitCode===null&&child.signalCode===null){
   child.kill('SIGINT');if(closed)await closed;
  }
  if(server.listening)await new Promise<void>(resolve=>server.close(()=>resolve()));
  if(!retainedDirectory)await rm(directory,{recursive:true,force:true});
 }
}
