import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,realpathSync,writeFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {observations} from './process-fixture.mts';
const preload=fileURLToPath(new URL('./preload.cts',import.meta.url));
test('real terminal-owner idle-stdin POSIX cancellation and actual child status', {skip: process.platform==='win32' ? 'This probe uses POSIX delivery; genuine Windows console remains mandatory in packaged qualification' : false},async()=>{
const root=realpathSync(mkdtempSync(join(tmpdir(),'morphir-terminal-probe-')));
try {
 for(const [signal,kind,status] of [['SIGINT',1,130],['SIGTERM',2,143]] as const) {
  const events=join(root,signal+'.jsonl'),config=join(root,signal+'.json');
  writeFileSync(config,JSON.stringify({mode:'observe',events}));
  const child=spawn(process.execPath,['--require',preload,fileURLToPath(new URL('./fixtures/terminal-worker-target.mts',import.meta.url)),'worksheet'],{env:{...process.env,MORPHIR_MOONX_TEST_CONFIG:config},stdio:['pipe','pipe','pipe']});
  const output: Buffer[]=[],errors: Buffer[]=[];child.stdout.on('data',x=>output.push(x));child.stderr.on('data',x=>errors.push(x));
  const closed=new Promise<{code:number|null;sig:NodeJS.Signals|null}>((done,reject)=>{child.once('error',reject);child.once('close',(code,sig)=>done({code,sig}));});
  const watchdog=setTimeout(()=>child.kill('SIGKILL'),15000);
  try {
   const deadline=Date.now()+10000;let observed;
   for(;;) {
    const rows=observations(events);
    observed=rows.find(r=>r.event==='stdin-read-starting');if(observed)break;
    assert.ok(Date.now()<deadline,Buffer.concat(errors).toString());await new Promise(r=>setTimeout(r,10));
   }
   assert.equal(observed.sigintListeners,1);assert.equal(observed.sigtermListeners,1);
   child.kill(signal);const result=await closed;
   assert.equal(result.code,status);assert.equal(result.sig,null);
   assert.deepEqual(JSON.parse(Buffer.concat(output).toString()),{read:-1,kind});
   assert.equal(Buffer.concat(errors).length,0);
   const rows=observations(events);
   assert.deepEqual(rows.filter(r=>r.event==='node-signal').map(r=>r.signal),[signal]);assert.equal(rows.find(r=>r.event==='node-exit')?.code,status);
  } finally {clearTimeout(watchdog);if(child.exitCode===null&&child.signalCode===null){child.kill('SIGKILL');await closed;}}
 }
 console.log('Actual terminal-worker source with observation preload: idle-open stdin readiness, real parent SIGINT130/SIGTERM143 and observed delivered identities passed. This is probe qualification, not packaged Moonx proof.');
}finally{rmSync(root,{recursive:true,force:true});}

});
