import { workbenchError } from '../../../types/data.ts';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,existsSync,mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {isQuiescent} from './test-process-quiescence.mts';
const helper=fileURLToPath(new URL('./metadata.mjs',import.meta.url));
const hash=(bytes: Parameters<import('node:crypto').Hash['update']>[0])=>createHash('sha256').update(bytes).digest('hex');
const root=mkdtempSync(join(tmpdir(),'morphir-metadata-exchange-'));
const budget=process.platform==='win32'?30000:10000;
try {
  const payload=Buffer.from([224,1,0,234,0,128,255,13,10]);
  // Node without arguments evaluates stdin. This test-only child emits known
  // bytes; it qualifies opaque transport, not Ion semantics or authentication.
  const input=Buffer.from(`process.stdout.write(Buffer.from(${JSON.stringify([...payload])}));`);
  const base={profile:'morphir-metadata-exchange-v1',invocation:'test-operation',projectScope:'a'.repeat(64),service:process.execPath,serviceSha256:hash(readFileSync(process.execPath)),inputSha256:hash(input),budgetMs:budget,cancelFile:''};
  function run(name: string,changes={},source=input) {
    const directory=join(root,name);mkdirSync(directory);
    const request=join(directory,'control.json');
    writeFileSync(join(directory,'request.ionb'),source);
    writeFileSync(request,JSON.stringify({...base,inputSha256:hash(source),input:join(directory,'request.ionb').replaceAll('\\','/'),output:join(directory,'response.ionb').replaceAll('\\','/'),receipt:join(directory,'receipt.json').replaceAll('\\','/'),...changes}));
    return spawnSync(process.execPath,[helper,request],{encoding:'utf8',timeout:budget+1000});
  }
  const success=run('success');assert.equal(success.status,0,success.stderr);
  const receipt=JSON.parse(success.stdout);assert.equal(receipt.quiescent,true);assert.equal(receipt.invocation,base.invocation);
  assert.equal(receipt.responseSha256,hash(payload));assert.deepEqual(readFileSync(join(root,'success/response.ionb')),payload);
  const cancellation=join(root,'cancel');writeFileSync(cancellation,'');
  for(const [name,changes,code] of [
    ['wrong-pin',{serviceSha256:'b'.repeat(64)},'metadata.restore_executable_changed'],
    ['wrong-input',{inputSha256:'b'.repeat(64)},'metadata.restore_request_changed'],
    ['cancelled',{cancelFile:cancellation},'execution.cancelled'],
  ] as const) {
    const result=run(name,changes);assert.notEqual(result.status,0);assert.match(result.stderr,new RegExp(code!));
    assert.equal(result.stdout,'');assert.equal(existsSync(join(root,name!,'response.ionb')),false);
    assert.equal(JSON.parse(readFileSync(join(root,name!,'receipt.json'),'utf8')).quiescent,true);
  }
  const privateFailure=run('private-failure',{},Buffer.from("throw Error('private policy secret');"));
  assert.notEqual(privateFailure.status,0);assert.equal(privateFailure.stdout,'');
  assert.equal(privateFailure.stderr,'metadata.restore_service_failed\n');
  const knownFailure=run('known-failure',{},Buffer.from("process.stderr.write('metadata.restore_authentication_failed\\n');process.exitCode=1;"));
  assert.notEqual(knownFailure.status,0);assert.equal(knownFailure.stdout,'');
  assert.equal(knownFailure.stderr,'metadata.restore_authentication_failed\n');
  const pid=join(root,'descendant.pid');
  const source=Buffer.from(`const {spawn}=require('child_process');const fs=require('fs');const child=spawn(process.execPath,['-e',${JSON.stringify(`require('fs').writeFileSync(${JSON.stringify(pid)},String(process.pid));setInterval(()=>{},1000)`)}],{stdio:'ignore'});child.unref();const ready=setInterval(()=>{if(fs.existsSync(${JSON.stringify(pid)})){clearInterval(ready);process.stdout.write(Buffer.from(${JSON.stringify([...payload])}));}},10);`);
  const tree=run('tree',{},source);assert.equal(tree.status,0,tree.stderr);
  assert.equal(JSON.parse(tree.stdout).quiescent,true);
  assert.ok(isQuiescent(Number(readFileSync(pid,'utf8'))),'receipt requires descendant quiescence');
  console.log('Metadata exchange pins, bytes, receipts and cancellation passed');
} finally {rmSync(root,{recursive:true,force:true});}
