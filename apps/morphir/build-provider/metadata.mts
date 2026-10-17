import type { BinaryLike } from 'node:crypto';
import { workbenchError } from '../../../types/data.ts';
interface MetadataRequest { profile: string; invocation: string; projectScope: string; service: string; serviceSha256: string; input: string; inputSha256: string; output: string; receipt: string; budgetMs: number; cancelFile: string; }
// Host-owned control-plane adapter. Model frames remain raw binary files and
// buffers; JSON is confined to this explicitly selected process-ABI bridge.
import {openSync,readSync,closeSync,fstatSync,lstatSync,readFileSync,writeFileSync,existsSync,constants} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,dirname,isAbsolute,join} from 'node:path';
import {supervisedBytes} from './supervision.mjs';

const hash=(bytes: BinaryLike)=>createHash('sha256').update(bytes).digest('hex');
const control=resolve(process.argv[2]||''),root=dirname(control);
let request: MetadataRequest | null=null,quiescent=true;
function refuse(code: string){throw Error(code);}
function check(test: unknown,code: string): asserts test{if(!test)refuse(code);}
function regular(path: string,limit: number) {
  const stat=lstatSync(path);
  check(stat.isFile()&&stat.size<=limit,'metadata.restore_input_limit');
}
function pin(path: string,deadline: number) {
  regular(path,536870912);
  const fd=openSync(path,constants.O_RDONLY|(constants.O_NONBLOCK||0)|(constants.O_NOFOLLOW||0)),digest=createHash('sha256'),buffer=Buffer.alloc(65536);
  try {
    let total=0;
    while(true) {
      check(performance.now()<deadline,'execution.deadline');
      const count=readSync(fd,buffer,0,buffer.length,null);
      if(!count)break;
      total+=count;check(total<=536870912,'metadata.restore_identity_limit');
      digest.update(buffer.subarray(0,count));
    }
    check(fstatSync(fd).isFile(),'metadata.restore_input_limit');
    return digest.digest('hex');
  } finally {closeSync(fd);}
}
function receipt(fields: Record<string, string | number | boolean>) {
  const value={profile:'morphir-metadata-receipt-v1',invocation:request!.invocation,projectScope:request!.projectScope,quiescent,...fields};
  writeFileSync(request!.receipt,JSON.stringify(value),{flag:'wx',mode:0o600});
  return value;
}
try {
  check(process.argv.length===3,'metadata.restore_invalid_control');
  regular(control,16384);
  const value: MetadataRequest=JSON.parse(readFileSync(control,'utf8'));
  const allowed=['profile','invocation','projectScope','service','serviceSha256','input','inputSha256','output','receipt','budgetMs','cancelFile'];
  check(Object.keys(value).length===allowed.length&&Object.keys(value).every(k=>allowed.includes(k)),'metadata.restore_invalid_control');
  check(value.profile==='morphir-metadata-exchange-v1'&&/^[A-Za-z0-9_-]{1,128}$/.test(value.invocation)&&/^[a-f0-9]{64}$/.test(value.projectScope),'metadata.restore_invalid_control');
  for(const key of ['serviceSha256','inputSha256'] as const)check(/^[a-f0-9]{64}$/.test(value[key]),'metadata.restore_invalid_control');
  check(Number.isInteger(value.budgetMs)&&value.budgetMs>=6001&&value.budgetMs<=600000,'metadata.restore_invalid_control');
  check(typeof value.cancelFile==='string'&&(!value.cancelFile||isAbsolute(value.cancelFile)),'metadata.restore_invalid_control');
  for(const key of ['service','input','output','receipt'] as const)check(typeof value[key]==='string'&&isAbsolute(value[key])&&!value[key].includes('\0'),'metadata.restore_invalid_control');
  check(resolve(value.input)===join(root,'request.ionb')&&resolve(value.output)===join(root,'response.ionb')&&resolve(value.receipt)===join(root,'receipt.json'),'metadata.restore_invalid_control');
  for(const key of ['input','output','receipt'] as const)value[key]=resolve(value[key]);
  check(!existsSync(value.output)&&!existsSync(value.receipt),'metadata.restore_invalid_control');
  request=value;
  const deadline=performance.now()+request.budgetMs;
  check(!request.cancelFile||!existsSync(request.cancelFile),'execution.cancelled');
  check(pin(request.service,deadline)===request.serviceSha256,'metadata.restore_executable_changed');
  regular(request.input,4194304);
  const input=readFileSync(request.input);
  check(input.length<=4194304&&hash(input)===request.inputSha256,'metadata.restore_request_changed');
  const timeout=Math.floor(deadline-performance.now()-6000);
  check(timeout>0,'execution.deadline');
  quiescent=false;
  let result;
  try {
    result=await supervisedBytes(request.service,[],{cwd:root,timeout,input,cancelFile:request.cancelFile,env:{PATH:process.env.PATH,...(process.platform==='win32'?{SystemRoot:process.env.SystemRoot}:{})}});
    quiescent=true;
  } catch(cause) {const error=workbenchError(cause);
    quiescent=!error.message.includes('execution.tree_termination_failed')&&!error.message.includes('execution.tree_termination_unavailable');
    throw error;
  }
  if(result.code!==0||result.signal) {
    const serviceCode=result.stderr.trim();
    const codes=['invalid_arguments','input_failed','invalid_frame','invalid_request','release_mismatch','response_limit','authentication_failed','projection_unsupported','output_failed'].map(s=>'metadata.restore_'+s);
    refuse(codes.includes(serviceCode)?serviceCode:'metadata.restore_service_failed');
  }
  check(pin(request.service,deadline)===request.serviceSha256,'metadata.restore_executable_changed');
  check(performance.now()<deadline,'execution.deadline');
  writeFileSync(request.output,result.stdout,{flag:'wx',mode:0o600});
  const complete=receipt({result:'succeeded',serviceSha256:request.serviceSha256,responseSha256:hash(result.stdout),responseBytes:result.stdout.length});
  process.stdout.write(JSON.stringify(complete));
} catch(cause) {const error=workbenchError(cause);
  // No service stderr, payload, trust material or provider-selected path enters
  // diagnostics. An unknown teardown result stays explicit in the receipt.
  const match=/^(metadata\.restore_[a-z_]+|execution\.(?:cancelled|deadline|response_limit|diagnostic_limit|tree_termination_failed|tree_termination_unavailable|input_failed|spawn_failed))(?::|;|$)/.exec(error.message||'');
  const code=match?.[1]||'metadata.restore_transport_failed';
  if(request) {
    try {receipt({result:'refused',code});} catch {}
  }
  process.stderr.write(code+(quiescent?'':'; execution.tree_termination_failed')+'\n');
  process.exitCode=1;
}
