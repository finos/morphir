import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync,spawn} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,existsSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const preload=fileURLToPath(new URL('./preload.cts',import.meta.url));
test('preload transport, observation transparency and deliberate unresponsive fault',async()=>{
const root=realpathSync(mkdtempSync(join(tmpdir(),'morphir-preload-smoke-')));
try {
  const entry=join(root,'app.cjs'),events=join(root,'events.jsonl'),config=join(root,'config.json'),ran=join(root,'app-ran');
  writeFileSync(entry,`require('node:fs').writeFileSync(${JSON.stringify(ran)},'ran');`);
  writeFileSync(config,JSON.stringify({mode:'transport',events}));
  const input=Buffer.from(Array.from({length:1048576},(_,i)=>i%256));
  const args=['','Ω🙂','a\nb','--','--json','--moonx-help','x y'];
  const result=spawnSync(process.execPath,['--require',preload,entry,...args],{cwd:root,env:{...process.env,MORPHIR_MOONX_TEST_CONFIG:config},input,timeout:20000,maxBuffer:4*1024*1024});
  assert.ifError(result.error);assert.equal(result.status,23);assert.equal(result.signal,null);
  assert.deepEqual(result.stdout,input);
  assert.deepEqual(result.stderr,Buffer.from(Array.from({length:1792},(_,i)=>255-i%256)));
  const records=readFileSync(events,'utf8').trim().split('\n').map(line=>JSON.parse(line));
  assert.deepEqual(records[0].arguments,args);assert.equal(records[0].cwd,root);assert.equal(records[1].inputBytes,input.length);
  assert.equal(existsSync(ran),false);
  writeFileSync(config,JSON.stringify({mode:'observe',events}));
  const observed=join(root,'observed.mjs');
  writeFileSync(observed,`import {readFileSync,writeSync} from 'node:fs';process.on('SIGINT',()=>{});process.on('SIGTERM',()=>{});writeSync(1,readFileSync(0));writeSync(2,Buffer.from([0,255,10]));process.exit(23);`);
  const plain=spawnSync(process.execPath,[observed],{cwd:root,input,timeout:20000,maxBuffer:4*1024*1024});
  const withProbe=spawnSync(process.execPath,['--require',preload,observed],{cwd:root,env:{...process.env,MORPHIR_MOONX_TEST_CONFIG:config},input,timeout:20000,maxBuffer:4*1024*1024});
  assert.equal(withProbe.error,undefined,withProbe.stderr.toString());assert.equal(withProbe.status,plain.status);assert.deepEqual(withProbe.stdout,plain.stdout);assert.deepEqual(withProbe.stderr,plain.stderr);
  const readEvent=readFileSync(events,'utf8').trim().split('\n').map(line=>JSON.parse(line)).find(r=>r.event==='stdin-read-starting');
  assert.equal(readEvent.sigintListeners,1);assert.equal(readEvent.sigtermListeners,1);
  writeFileSync(config,JSON.stringify({mode:'unresponsive',events}));
  const blocked=spawn(process.execPath,['--require',preload,entry],{cwd:root,env:{...process.env,MORPHIR_MOONX_TEST_CONFIG:config},stdio:['pipe','pipe','pipe']});
  const closed=new Promise<void>((resolve,reject)=>{blocked.once('close',()=>resolve());blocked.once('error',reject);});
  try {
    const deadline=Date.now()+10000;
    while(!readFileSync(events,'utf8').includes('unresponsive-ready')) {assert.ok(Date.now()<deadline);await new Promise(r=>setTimeout(r,10));}
    if(process.platform!=='win32') {
      blocked.kill('SIGTERM');await new Promise(r=>setTimeout(r,100));assert.equal(blocked.exitCode,null);assert.equal(blocked.signalCode,null);
    }
  } finally {
    if(blocked.exitCode===null&&blocked.signalCode===null) blocked.kill('SIGKILL');
    let timer:ReturnType<typeof setTimeout>|undefined;
    try {
      await Promise.race([closed,new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new Error('Preload fixture cleanup deadline exceeded')),3000);})]);
    } finally {if(timer)clearTimeout(timer);}
  }
  console.log('Observation preload preserves real ESM read/stdout/stderr/status and records registered handlers. Deliberate non-responsive Node fault stays alive until forced cleanup.');
  console.log('Node preload fixture only: exact 1 MiB all-byte stdin/stdout, separate 1792 stderr bytes, opaque argv/cwd and child23 pass. No Moonx qualification claimed.');
} finally {rmSync(root,{recursive:true,force:true});}

});
