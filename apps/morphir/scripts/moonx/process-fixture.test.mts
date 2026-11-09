import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {mkdtempSync,realpathSync,writeFileSync,appendFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {start,finish,cleanup,waitControlLine,waitObservation,observations,gone,sleep,recoveryProblems} from './process-fixture.mts';
test('bounded process recovery and LF-complete records',async()=>{
const root=realpathSync(mkdtempSync(join(tmpdir(),'morphir-process-recovery-')));
try {
 const partial=join(root,'partial.jsonl');
 writeFileSync(partial,'{"event":"node-started","pid":123');assert.deepEqual(observations(partial),[]);
 appendFileSync(partial,'}\n');assert.deepEqual(observations(partial),[{event:'node-started',pid:123}]);
 const events=join(root,'child.jsonl');
 const childSource=`require('node:fs').appendFileSync(${JSON.stringify(events)},JSON.stringify({event:'node-started',pid:process.pid})+'\\n');setInterval(()=>{},1000);`;
 const parent=join(root,'parent.cjs');
 writeFileSync(parent,`require('node:child_process').spawn(process.execPath,['-e',${JSON.stringify(childSource)}],{stdio:'inherit',detached:true});setInterval(()=>{},1000);`);
 const run=start(process.execPath,[parent],root,process.env,events);
 try {
  const child=await waitObservation(run,events,'node-started');
  const exited=once(run.child,'exit');run.child.kill('SIGKILL');await exited;
  assert.equal(run.settled(),false,'Orphan retains inherited pipes after launcher exit');
  assert.equal(gone(child.pid),false);
  const started=performance.now();await cleanup(run);
  assert.ok(performance.now()-started<3000,'Recovery has a bounded wait');
  assert.equal(run.settled(),true);
  const deadline=Date.now()+3000;while(!gone(child.pid)){assert.ok(Date.now()<deadline);await sleep(10);}
  assert.deepEqual(recoveryProblems,[]);
 }finally{await cleanup(run);}
 const release=join(root,'release-control');
 const partialProgram=join(root,'partial-control.cjs');
 writeFileSync(partialProgram,`const fs=require('node:fs');fs.writeSync(1,'CONTROL_ADDR=127.0.0.1:');const poll=setInterval(()=>{if(fs.existsSync(${JSON.stringify(release)})){clearInterval(poll);fs.writeSync(1,'54321\\n');process.exit(0);}},10);`);
 const partialRun=start(process.execPath,[partialProgram],root,process.env);
 try {
  const deadline=Date.now()+5000;while(!Buffer.concat(partialRun.stdout).toString().includes('CONTROL_ADDR=')){assert.ok(Date.now()<deadline);await sleep(10);}
  let resolved=false;const control=waitControlLine(partialRun,'CONTROL_ADDR=').then(value=>{resolved=true;return value;});
  await sleep(30);assert.equal(resolved,false,'An unterminated control fragment is not a record');
  writeFileSync(release,'release');assert.equal(await control,'127.0.0.1:54321');assert.equal((await finish(partialRun)).code,0);
 }finally{await cleanup(partialRun);}
 const hiddenEvents=join(root,'hidden-child.jsonl');
 const hiddenSource=`require('node:fs').appendFileSync(${JSON.stringify(hiddenEvents)},JSON.stringify({event:'node-started',pid:process.pid})+'\\n');setInterval(()=>{},1000);`;
 const hiddenParent=join(root,'hidden-parent.cjs');
 writeFileSync(hiddenParent,`require('node:child_process').spawn(process.execPath,['-e',${JSON.stringify(hiddenSource)}],{stdio:'inherit',detached:true});setInterval(()=>{},1000);`);
 // Withhold descendant observations from the watchdog to model a missed PID.
 const hidden=start(process.execPath,[hiddenParent],root,process.env,undefined,10000);
 let hiddenPid: number|undefined;
 try {
  hiddenPid=(await waitObservation(hidden,hiddenEvents,'node-started')).pid;
  const started=performance.now();
  await assert.rejects(finish(hidden),/exceeded 10000 milliseconds/);
  assert.ok(performance.now()-started<12000,'finish fails even while unknown descendant holds pipes');
  const recoveryStarted=performance.now();await cleanup(hidden);
  assert.ok(performance.now()-recoveryStarted<4000);
  assert.equal(recoveryProblems.length,1);const recovery = recoveryProblems[0];assert.ok(recovery);assert.match(recovery,/pipes did not close/);
 } finally {
  if(hiddenPid!==undefined&&!gone(hiddenPid))process.kill(hiddenPid,'SIGKILL');
  await cleanup(hidden);recoveryProblems.length=0;
 }
 console.log('Deadline regression: missed descendant held pipes; finish rejected on timeout and recovery returned within its bound. Fault child explicitly removed afterward.');
 console.log('Process recovery regression: real orphan-held pipes reproduced; descendant-first bounded cleanup reaped the child. Partial observation records remain unread until LF.');
}finally{rmSync(root,{recursive:true,force:true});}

});
