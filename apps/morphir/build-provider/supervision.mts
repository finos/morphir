import type { SuperviseOptions, SupervisedResult } from './contracts.mjs';
import { workbenchError } from '../../../types/data.ts';
import {spawn,spawnSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {windowsJob} from './windows-job.mjs';

// One owned process group per command. Never resolve on `error` before `close`:
// AbortSignal's early rejection otherwise allows disposal while children run.
export function supervised(program: string,args: string[],options: SuperviseOptions): Promise<SupervisedResult<string>> {
  return supervise(program,args,options,false) as Promise<SupervisedResult<string>>;
}

// Model payloads use a separate byte channel. The text API keeps its original
// combined one-MiB cap; binary stdout has a fixed 16-MiB cap and diagnostics an
// independent 64-KiB cap. Both paths share tree ownership and quiescence checks.
export function supervisedBytes(program: string,args: string[],{cwd,env,timeout,cancelFile='',input}: SuperviseOptions): Promise<SupervisedResult<Buffer>> {
  return supervise(program,args,{cwd,env,timeout,cancelFile,input},true) as Promise<SupervisedResult<Buffer>>;
}

async function supervise(program: string,args: string[],{cwd,env,timeout,cancelFile='',limit=1048576,input}: SuperviseOptions,binary: boolean) {
  if(!Number.isInteger(timeout)||timeout<1||timeout>600000||!Number.isInteger(limit)||limit<1||limit>1048576)throw Error('execution.supervision_limit');
  if(input!==undefined&&(!Buffer.isBuffer(input)||input.length>4194304))throw Error('execution.input_limit');
  if(cancelFile && existsSync(cancelFile))throw Error('execution.cancelled');
  const job=process.platform==='win32'?windowsJob(program,args,{cwd,env,timeout}):null;
  const child=spawn(job?.program||program,job?.args||args,{cwd,env:job?.env||env,detached:process.platform!=='win32',stdio:[input===undefined?'ignore':'pipe','pipe','pipe'],windowsHide:true});
  type Closed = [number | null, NodeJS.Signals | null];
  const closed=new Promise<Closed>(resolve=>child.once('close',(code, signal)=>resolve([code, signal])));
  let reason='',treeError='',spawnError: Error | null=null,size=0,outputSize=0,diagnosticSize=0,termination: Promise<void> | null=null;const out: Buffer[]=[],err: Buffer[]=[];
  let unconfirmed: (result: Closed) => void = () => {};
  const treeFailure=new Promise<Closed>(resolve=>{unconfirmed=resolve;});
  function killTree() {
    if(!child.pid||termination)return;
    if(process.platform==='win32') {
      termination=(async()=>{
        try {job!.stop();}catch {treeError ||= 'execution.tree_termination_failed';child.kill('SIGKILL');}
        let timer: ReturnType<typeof setTimeout> | undefined;
        await Promise.race([closed,new Promise<void>(resolve=>{timer=setTimeout(()=>{treeError ||= 'execution.tree_termination_failed';child.kill('SIGKILL');resolve();},5000);})]);
        clearTimeout(timer);
      })();
    } else {
      try {process.kill(-child.pid!,'SIGKILL');}catch(cause){const e=workbenchError(cause);if(e.code!=='ESRCH'&&e.code!=='EPERM')treeError ||= 'execution.tree_termination_failed';}
      termination=(async()=>{
        // `close` only awaits the direct child. Confirm the owned process group
        // is gone before callers may dispose files still used by descendants.
        const deadline=performance.now()+500;
        while(true) {
          try {process.kill(-child.pid!,0);}catch(cause){const e=workbenchError(cause);if(e.code==='ESRCH')return;if(e.code!=='EPERM'){treeError ||= 'execution.tree_termination_failed';return;}}
          // Orphan zombies can retain a group ID until the OS reaper runs, but
          // have no executing code or open files. Confirm there are no live
          // members rather than treating unreapable grandchildren as runners.
          const listing=spawnSync('ps',['-eo','pid=,pgid=,stat='],{encoding:'utf8',timeout:100,killSignal:'SIGKILL',maxBuffer:1048576});
          if(!listing.error&&listing.status===0) {
            const members=listing.stdout.trim().split('\n').map(line=>line.trim().split(/\s+/)).filter(parts=>Number(parts[1])===child.pid);
            if(members.every(parts=>parts[2]?.startsWith('Z')))return;
          }
          if(performance.now()>=deadline){treeError ||= 'execution.tree_termination_failed';return;}
          await new Promise(resolve=>setTimeout(resolve,5));
        }
      })();
    }
    termination.then(()=>{
      if(treeError) {
        // An unkillable process cannot keep the supervisor alive. Return a
        // failure marker, never a completion receipt; the host retains scratch.
        for(const stream of child.stdio)stream?.destroy();
        child.unref();unconfirmed([-1,null]);
      }
    });
  }
  const stop=(code: string)=>{reason ||= code;killTree();};
  const signal=()=>stop('execution.cancelled');
  process.on('SIGTERM',signal);process.on('SIGINT',signal);
  const timer=setTimeout(()=>stop('execution.deadline'),timeout);
  const poll=cancelFile?setInterval(()=>{if(existsSync(cancelFile))stop('execution.cancelled');},10):null;
  const collect=(destination: Buffer[],data: Buffer)=>{
    if(binary) {
      if(destination===out) {
        outputSize+=data.length;
        if(outputSize>16777216){stop('execution.response_limit');return;}
      } else {
        diagnosticSize+=data.length;
        if(diagnosticSize>65536){stop('execution.diagnostic_limit');return;}
      }
    } else {
      size+=data.length;
      if(size>limit){stop('execution.diagnostic_limit');return;}
    }
    destination.push(data);
  };
  child.stdout!.on('data',data=>collect(out,data));child.stderr!.on('data',data=>collect(err,data));
  child.on('error',error=>{spawnError=error;});
  // Reclaim descendants at parent exit even when their inherited pipes would
  // otherwise postpone `close` indefinitely. Still await `close` and the group.
  if(process.platform!=='win32')child.once('exit',killTree);
  if(child.stdin) {
    // A failed or cancelled exporter may close stdin before the batch is sent.
    child.stdin.on('error',()=>stop('execution.input_failed'));
    child.stdin.end(input);
  }
  try {
    let [code,signal]=await Promise.race([closed,treeFailure]);
    // A command may exit while a descendant is still alive with closed pipes.
    // Reclaim the group on successful exit too, before returning its evidence.
    if(process.platform!=='win32')killTree();
    if(termination)await termination;
    if(job) {
      try {const receipt=job.complete();code=receipt.exitCode;reason ||= receipt.reason;}
      catch {treeError ||= 'execution.tree_termination_failed';}
    }
    const spawnFailure = spawnError as Error | null;
    if(reason||treeError) {
      const causes=[reason,spawnFailure?'execution.spawn_failed: '+spawnFailure.message:'',treeError].filter(Boolean);
      // Keep a worker's original bounded diagnostic alongside the unconfirmed
      // tree marker. Neither stderr nor a worker failure becomes model output.
      const diagnostic=job&&treeError?Buffer.concat(err).toString('utf8').slice(0,1024):'';
      throw Error(causes.join('; ')+(diagnostic?'\n'+diagnostic:''));
    }
    if(spawnFailure)throw Error('execution.spawn_failed: '+spawnFailure.message);
    return {code,signal,stdout:binary?Buffer.concat(out):Buffer.concat(out).toString('utf8'),stderr:Buffer.concat(err).toString('utf8')};
  } finally {
    clearTimeout(timer);if(poll)clearInterval(poll);
    process.removeListener('SIGTERM',signal);process.removeListener('SIGINT',signal);
  }
}
