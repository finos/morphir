import {readSync,writeSync,closeSync,fstatSync} from 'node:fs';

/** Private observation DATA. Endpoint possession never grants source authority. */
export type Retention='retained'|'faulted';
export type ProducerRole='outer'|'transfer-helper';
export type HelperCompletion={kind:'not-applicable'}|{kind:'in-process'};
export type LiteralOsOperand={kind:'unix-bytes';bytes:{kind:'utf8';text:string}|{kind:'hex';hex:string}};
export type ConsumerFact={kind:'release-accepted';requestId:string;captureId:string;
 binding:{sessionId:string;providerId:string;sourceLocator:string;projectId:string};requestSha256:string;replySha256:string}|
 {kind:'destination-commit-finished';path:LiteralOsOperand;policy:'create';outcome:'returned'|'raised'}|
 {kind:'scratch-cleanup-finished';path:LiteralOsOperand;outcome:'returned'|'raised'};
export interface ConsumerOperationPort {
  // Preparation belongs to the attempted hook. A poisoned endpoint must not
  // construct more facts, hash bytes or allocate an operand after failure.
  emit(fact:ConsumerFact|(()=>ConsumerFact)):Retention;
  finish(helper:HelperCompletion):Retention;
}
const version='0.1.0-draft.1',prefix='MORPHIR_PRIVATE_CONSUMER_';
const selectors=['OUTER_FD','HELPER_FD','VERSION','CLOCK_DOMAIN','CLOCK_VERSION','CLOCK_AT_NS','END_NS','TIMEBASE_NUMER','TIMEBASE_DENOM'] as const;
const maxClock=6148914691236517166n;
// One canonical publish per observed process. Consumed descriptor numbers stay
// claimed so stale launch metadata cannot adopt an unrelated recycled fd.
const claimedDescriptors=new Set<number>();
function shape(value:object,names:readonly string[]):void{
 if(value===null||Object.keys(value).length!==names.length||names.some(name=>!Object.hasOwn(value,name)))throw new Error('shape');
}
function text(value:string,max:number):void{
 if(typeof value!=='string'||value.length>max||Buffer.byteLength(value,'utf8')>max||/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(value))throw new Error('text');
}
function operand(path:LiteralOsOperand):void{
 shape(path,['kind','bytes']);if(path.kind!=='unix-bytes')throw new Error('operand');
 if(path.bytes.kind==='utf8'){shape(path.bytes,['kind','text']);text(path.bytes.text,131072);}
 else if(path.bytes.kind==='hex'){
  shape(path.bytes,['kind','hex']);if(typeof path.bytes.hex!=='string'||path.bytes.hex.length>262144||path.bytes.hex.length%2||!/^[0-9a-f]*$/.test(path.bytes.hex))throw new Error('hex');
 }else throw new Error('literal');
}
function validateFact(fact:ConsumerFact,role:ProducerRole):void{
 if(fact.kind==='release-accepted'){
  if(role!=='transfer-helper')throw new Error('role');
  shape(fact,['kind','requestId','captureId','binding','requestSha256','replySha256']);
  if(typeof fact.requestId!=='string'||fact.requestId.length>20||!/^(0|[1-9][0-9]*)$/.test(fact.requestId)||BigInt(fact.requestId)>18446744073709551615n)throw new Error('request');
  text(fact.captureId,128);shape(fact.binding,['sessionId','providerId','sourceLocator','projectId']);
  text(fact.binding.sessionId,128);text(fact.binding.providerId,128);text(fact.binding.sourceLocator,4096);text(fact.binding.projectId,12288);
  if(!/^[0-9a-f]{64}$/.test(fact.requestSha256)||!/^[0-9a-f]{64}$/.test(fact.replySha256))throw new Error('digest');
 }else{
  if(role!=='outer')throw new Error('role');
  if(fact.kind==='destination-commit-finished'){
   shape(fact,['kind','path','policy','outcome']);if(fact.policy!=='create')throw new Error('policy');
  }else if(fact.kind==='scratch-cleanup-finished')shape(fact,['kind','path','outcome']);
  else throw new Error('fact');
  operand(fact.path);if(fact.outcome!=='returned'&&fact.outcome!=='raised')throw new Error('outcome');
 }
}
function decimal(env:NodeJS.ProcessEnv,name:string,max:bigint):bigint{
 const value=env[prefix+name];if(typeof value!=='string'||value.length>20||!/^(0|[1-9][0-9]*)$/.test(value))throw new Error('integer');
 const result=BigInt(value);if(result>max)throw new Error('range');return result;
}
const inert:ConsumerOperationPort=Object.freeze({emit:()=> 'faulted' as const,finish:()=> 'faulted' as const});
class Endpoint implements ConsumerOperationPort {
 private fd:number;private end:bigint;private previous:bigint;private sequence=0;private faulted=false;private closed=false;
 private role:ProducerRole;private attempted=0;private started=0;private retained=0;
 private seen=new Set<ConsumerFact['kind']>();
 constructor(fd:number,at:bigint,end:bigint,role:ProducerRole){this.fd=fd;this.previous=at;this.end=end;this.role=role;}
 private check():void{
  const now=process.hrtime.bigint();if(now<this.previous||now>=this.end||now>maxClock)throw new Error('clock');this.previous=now;
 }
 private transfer(bytes:Buffer,write:boolean):void{
  let cursor=0;while(cursor<bytes.length){
   this.check();try{
    const count=write?writeSync(this.fd,bytes,cursor,bytes.length-cursor):readSync(this.fd,bytes,cursor,bytes.length-cursor,null);
    if(count<=0)throw new Error('eof');cursor+=count;
   }catch(error){const code=(error as NodeJS.ErrnoException).code;if(code!=='EINTR'&&code!=='EAGAIN'&&code!=='EWOULDBLOCK')throw error;}
  }
 }
 private frame(kind:'open'|'close'|'fact',extra:Record<string,unknown>={}):Retention{
  if(this.faulted||this.closed)return 'faulted';
  try{
   this.check();const body=Buffer.from(JSON.stringify({kind,version,sequence:this.sequence,...extra}),'utf8');
   // Closed operand shapes bound worst-case JSON escaping to six bytes per
   // operand byte plus the fixed envelope. This is not a runner policy grant.
   if(body.length>131072*6+512)throw new Error('frame bound');
   const header=Buffer.alloc(4);header.writeUInt32BE(body.length);if(kind==='fact')this.started++;
   this.transfer(header,true);this.transfer(body,true);
   const ack=Buffer.from(JSON.stringify({kind:'retained',version,sequence:this.sequence}),'utf8'),gotHeader=Buffer.alloc(4);
   this.transfer(gotHeader,false);if(gotHeader.readUInt32BE()!==ack.length)throw new Error('ack length');
   const got=Buffer.alloc(ack.length);this.transfer(got,false);if(!got.equals(ack))throw new Error('ack');this.check();this.sequence++;if(kind==='fact')this.retained++;return 'retained';
  }catch{this.faulted=true;return 'faulted';}
 }
 open():Retention{return this.frame('open');}
 emit(prepared:ConsumerFact|(()=>ConsumerFact)):Retention{
  this.attempted=Math.min(this.attempted+1,3);
  if(this.faulted||this.closed)return 'faulted';
  try{
   this.check();
   const fact=typeof prepared==='function'?prepared():prepared;
   validateFact(fact,this.role);
   if(this.seen.has(fact.kind)||this.attempted>(this.role==='outer'?2:1))throw new Error('duplicate');
   this.seen.add(fact.kind);return this.frame('fact',{fact});
  }catch{this.faulted=true;return 'faulted';}
 }
 finish(helper:HelperCompletion):Retention{
  if(!this.faulted&&!this.closed){
   try{shape(helper,['kind']);if(helper.kind!==(this.role==='outer'?'in-process':'not-applicable'))throw new Error('helper');}
   catch{this.faulted=true;}
  }
  const result=this.frame('close',{attemptedHooks:this.attempted,startedFactFrames:this.started,retainedBusinessFacts:this.retained,helper});
  if(!this.closed){this.closed=true;try{closeSync(this.fd);}catch{this.faulted=true;return 'faulted';}}
  return result;
 }
}
/** Called only at the static source-owned role entrypoint, never a caller role selector. */
export function openConsumerOperationPort(role:ProducerRole,env:NodeJS.ProcessEnv=process.env):ConsumerOperationPort|undefined{
 try{
  if(!selectors.some(name=>env[prefix+name]!==undefined))return undefined;
  if(role!=='outer'&&role!=='transfer-helper')throw new Error('role');
  if(process.platform!=='darwin'||process.arch!=='arm64'||env[prefix+'VERSION']!==version||env[prefix+'CLOCK_VERSION']!==version||
   env[prefix+'CLOCK_DOMAIN']!=='darwin-mach-continuous-nanoseconds')throw new Error('basis');
  const outer=decimal(env,'OUTER_FD',2147483647n),helper=decimal(env,'HELPER_FD',2147483647n);
  const at=decimal(env,'CLOCK_AT_NS',maxClock),end=decimal(env,'END_NS',maxClock);
  if(outer<3n||helper<3n||outer===helper||at>=end||decimal(env,'TIMEBASE_NUMER',4294967295n)!==125n||decimal(env,'TIMEBASE_DENOM',4294967295n)!==3n)throw new Error('metadata');
  // The reviewed runner sets O_NONBLOCK before inheritance. Stable Node fs has
  // no F_GETFL API; fstat validates the actual moved socket, not its flag bits.
  // In particular helper startup must never inspect or close the Outer fd: the
  // native child may already have closed it and reused that number.
  const fd=Number(role==='outer'?outer:helper);if(claimedDescriptors.has(fd)||!fstatSync(fd).isSocket())throw new Error('endpoint');
  claimedDescriptors.add(fd);
  const owner=new Endpoint(fd,at,end,role);owner.open();return owner;
 }catch{return inert;}
}
