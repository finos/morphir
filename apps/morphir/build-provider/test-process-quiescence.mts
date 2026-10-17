import { workbenchError } from '../../../types/data.ts';
import {spawnSync} from 'node:child_process';

// A zombie has no executing code or open files. Container PID 1 may leave it
// unreaped, so kill(pid, 0) alone cannot establish the supervisor's contract.
export function isQuiescent(pid: number) {
  try {process.kill(pid,0);} catch(cause) {const error=workbenchError(cause);
    if(error.code==='ESRCH')return true;
    throw error;
  }
  if(process.platform==='win32')return false;
  const state=spawnSync('ps',['-p',String(pid),'-o','stat='],{encoding:'utf8',timeout:1000});
  if(state.error)throw state.error;
  if(state.status===1&&state.stdout.trim()==='')return true;
  if(state.status!==0)throw Error('Cannot establish process state: '+state.stderr);
  return state.stdout.trim().startsWith('Z');
}
