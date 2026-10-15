import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,existsSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {supervised} from './supervision.mjs';
import {windowsJob} from './windows-job.mjs';
import {isQuiescent} from './test-process-quiescence.mjs';
const root=mkdtempSync(join(tmpdir(),'morphir-supervision-'));
const windows=process.platform==='win32',allowance=windows?20000:1000;
async function until(test,timeout=allowance) {
  const deadline=performance.now()+timeout;
  while(!test()) {assert.ok(performance.now()<deadline,'condition completed within allowance');await new Promise(resolve=>setTimeout(resolve,10));}
}
function gone(pid) {try {process.kill(pid,0);return false;}catch(error){if(error.code==='ESRCH')return true;throw error;}}
try {
  for(const mode of ['deadline','cancelled','normal','normal-pipes',...(windows?['normal-detached']:[])]) {
    const pidFile=join(root,mode+'.pid'),cancelFile=join(root,mode+'.cancel');
    const descendant=`require('fs').writeFileSync(${JSON.stringify(pidFile)},String(process.pid));setInterval(()=>{},1000)`;
    const parent=`const {spawn}=require('child_process');spawn(process.execPath,['-e',${JSON.stringify(descendant)}],{stdio:${mode==='normal-pipes'?"'inherit'":"'ignore'"},detached:${mode==='normal-detached'}});${mode.startsWith('normal')?`const ready=setInterval(()=>{if(require('fs').existsSync(${JSON.stringify(pidFile)})){clearInterval(ready);process.exit(0);}},10)`:'setInterval(()=>{},1000)'}`;
    // Windows PowerShell and its C# compiler can cold-start slowly on hosted
    // runners. This case must reach model code before its deadline; a separate
    // one-millisecond case below covers deadline expiry during worker startup.
    const result=supervised(process.execPath,['-e',parent],{cwd:root,env:process.env,timeout:windows?(mode==='deadline'?15000:allowance):800,cancelFile});
    // Readiness, not elapsed time, proves cancellation actually interrupts a tree.
    if(mode==='cancelled'){await until(()=>existsSync(pidFile));writeFileSync(cancelFile,'');}
    if(mode.startsWith('normal'))assert.equal((await result).code,0);
    else await assert.rejects(result,new RegExp('execution.'+mode));
    assert.ok(existsSync(pidFile),'descendant actually started');
    const pid=Number(readFileSync(pidFile,'utf8'));
    assert.ok(isQuiescent(pid),'descendant quiescent before scratch disposal');
  }
  await assert.rejects(supervised(process.execPath,['-e',"process.stdout.write('x'.repeat(100000));setInterval(()=>{},1000)"],{timeout:allowance,limit:1000}),error=>error.message==='execution.diagnostic_limit');
  const argumentsToKeep=['','space here','quote"here','back\\slash','end\\','space end\\','雪😀','a\\\\"b'];
  const input=Buffer.from([0xe0,1,0,0xea,0,255,128,10,13]);
  const transport=await supervised(process.execPath,['-e',`const {createHash}=require('crypto');const chunks=[];process.stdin.on('data',x=>chunks.push(x));process.stdin.on('end',()=>{process.stdout.write(JSON.stringify({args:process.argv.slice(1),cwd:process.cwd(),env:process.env.MORPHIR_TEST_VALUE,hash:createHash('sha256').update(Buffer.concat(chunks)).digest('hex')}));process.stderr.write('separate diagnostic');process.exitCode=7;});`,...argumentsToKeep],{cwd:root,env:{...process.env,MORPHIR_TEST_VALUE:'value with spaces 雪'},timeout:allowance,input});
  assert.equal(transport.code,7);assert.equal(transport.stderr,'separate diagnostic');
  assert.deepEqual(JSON.parse(transport.stdout),{args:argumentsToKeep,cwd:realpathSync(root),env:'value with spaces 雪',hash:createHash('sha256').update(input).digest('hex')});
  if(windows) {
    const invalidExecutable=join(root,'invalid.exe');
    writeFileSync(invalidExecutable,'not a Windows executable');
    await assert.rejects(supervised(invalidExecutable,[],{timeout:allowance}),error=>error.message.includes('execution.tree_termination_failed')&&error.message.includes('execution.windows_job_failed:'));
    const pidFile=join(root,'owner-death.pid'),descendantFile=join(root,'owner-death-descendant.pid');
    const descendant=`require('fs').writeFileSync(${JSON.stringify(descendantFile)},String(process.pid));setInterval(()=>{},1000)`;
    const script=`require('fs').writeFileSync(${JSON.stringify(pidFile)},String(process.pid));require('child_process').spawn(process.execPath,['-e',${JSON.stringify(descendant)}],{stdio:'ignore',detached:true});setInterval(()=>{},1000)`;
    const module=fileURLToPath(new URL('./supervision.mjs',import.meta.url));
    const owner=spawn(process.execPath,['--input-type=module','-e',`import {supervised} from ${JSON.stringify(new URL('./supervision.mjs',import.meta.url).href)};await supervised(process.execPath,['-e',${JSON.stringify(script)}],{timeout:30000});`],{stdio:'ignore'});
    const closed=new Promise(resolve=>owner.once('close',resolve));
    try {
      assert.ok(existsSync(module));await until(()=>existsSync(pidFile)&&existsSync(descendantFile));
      owner.kill('SIGKILL');await closed;
      await until(()=>gone(Number(readFileSync(pidFile,'utf8'))),3000);
      await until(()=>gone(Number(readFileSync(descendantFile,'utf8'))),3000);
    } finally {owner.kill('SIGKILL');}
    const workerPidFile=join(root,'worker-death.pid'),workerDescendantFile=join(root,'worker-death-descendant.pid');
    const workerDescendant=`require('fs').writeFileSync(${JSON.stringify(workerDescendantFile)},String(process.pid));setInterval(()=>{},1000)`;
    const job=windowsJob(process.execPath,['-e',`require('fs').writeFileSync(${JSON.stringify(workerPidFile)},String(process.pid));require('child_process').spawn(process.execPath,['-e',${JSON.stringify(workerDescendant)}],{stdio:'ignore',detached:true});setInterval(()=>{},1000)`],{timeout:30000});
    const worker=spawn(job.program,job.args,{stdio:'ignore',windowsHide:true});
    const workerClosed=new Promise(resolve=>worker.once('close',resolve));
    try {
      await until(()=>existsSync(workerPidFile)&&existsSync(workerDescendantFile));
      worker.kill('SIGKILL');await workerClosed;
      await until(()=>gone(Number(readFileSync(workerPidFile,'utf8'))),3000);
      await until(()=>gone(Number(readFileSync(workerDescendantFile,'utf8'))),3000);
      assert.throws(()=>job.complete(),/execution.tree_termination_failed/,'no completion claim without a receipt');
      assert.ok(existsSync(job.args.at(-1)),'private state retained on unconfirmed termination');
    } finally {
      worker.kill('SIGKILL');
      // The test acts as the recovery operator after proving both processes gone.
      rmSync(dirname(job.args.at(-1)),{recursive:true,force:true});
    }
    await assert.rejects(supervised(process.execPath,['-e','throw Error("must not start")'],{timeout:1}),/execution.deadline/);
    process.env.MORPHIR_TEST_HOST_ONLY='must not enter model environment';
    try {
      const minimal=await supervised(process.execPath,['-e','process.stdout.write(process.env.MORPHIR_TEST_HOST_ONLY||"minimal environment")'],{env:{PATH:process.env.PATH},timeout:allowance});
      assert.equal(minimal.code,0);assert.equal(minimal.stdout,'minimal environment');
    } finally {delete process.env.MORPHIR_TEST_HOST_ONLY;}
  }
  if(process.platform!=='win32') {
    const pidFile=join(root,'denied.pid'),kill=process.kill;
    try {
      process.kill=(pid,...args)=>{if(pid<0)throw Object.assign(Error('denied'),{code:'EPERM'});return kill.call(process,pid,...args);};
      const started=performance.now();
      await assert.rejects(supervised(process.execPath,['-e',`require('fs').writeFileSync(${JSON.stringify(pidFile)},String(process.pid));setInterval(()=>{},1000)`],{timeout:300}),error=>error.message==='execution.deadline; execution.tree_termination_failed');
      assert.ok(performance.now()-started<2000,'unconfirmed termination is bounded');
      assert.ok(existsSync(pidFile),'real process remains for host recovery');
      kill.call(process,Number(readFileSync(pidFile,'utf8')),0);
    }finally {
      process.kill=kill;
      if(existsSync(pidFile))kill.call(process,-Number(readFileSync(pidFile,'utf8')),'SIGKILL');
    }
  }
  for(let i=0;i<12;i++)assert.equal((await supervised(process.execPath,['-e',''],{timeout:allowance})).code,0);
  assert.equal(process.listenerCount('SIGTERM'),0);assert.equal(process.listenerCount('SIGINT'),0);
  console.log('Process tree, cancellation, deadline, diagnostics and listener cleanup passed');
}finally{rmSync(root,{recursive:true,force:true});}

await import('./test-binary-supervision.mjs');
