import { workbenchError } from '../../../types/data.ts';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,statSync,openSync,readSync,fstatSync,closeSync,constants} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {supervised} from './supervision.mjs';
import {fileIdentity,hash} from './identity.mjs';
function evaluatorIdentity(path: string) {
  const fd=openSync(path,constants.O_RDONLY|constants.O_NONBLOCK);
  try {
    const before=fstatSync(fd);
    assert.ok(before.isFile()&&before.size>0&&before.size<=512*1024*1024,'conformance.binary_limit');
    const digest=createHash('sha256'),buffer=Buffer.alloc(65536);
    for(let remaining=before.size;remaining>0;) {
      const n=readSync(fd,buffer,0,Math.min(buffer.length,remaining),null);
      assert.ok(n>0,'conformance.changed_evaluator');remaining-=n;digest.update(buffer.subarray(0,n));
    }
    const after=fstatSync(fd);
    assert.ok(before.size===after.size&&before.mtimeMs===after.mtimeMs&&before.ctimeMs===after.ctimeMs,'conformance.changed_evaluator');
    return digest.digest('hex');
  } finally {closeSync(fd);}
}
try {
  if(process.argv[2]==='--identity') {
    process.stdout.write(JSON.stringify({binaryIdentity:evaluatorIdentity(resolve(process.argv[3]!))}));
  } else {
    const path=resolve(process.argv[2]!);
    assert.ok(statSync(path).isFile()&&statSync(path).size<=16*1024*1024,'conformance.request_limit');
    const request=JSON.parse(readFileSync(path,'utf8'));
    const program=resolve(request.program);
    assert.equal(request.profile,'morphir-rust-evaluator-worker-v1');
    assert.ok(typeof request.input==='string'&&Buffer.byteLength(request.input)<=8388608,'conformance.request_limit');
    assert.ok(Number.isInteger(request.timeout)&&request.timeout>0&&request.timeout<=300000);
    assert.equal(evaluatorIdentity(program),request.binaryIdentity,'conformance.changed_evaluator');
    assert.equal(fileIdentity(fileURLToPath(import.meta.url)),request.helperIdentity,'conformance.changed_helper');
    // Keep the JSON input opaque: parsing classic numeric literals in JavaScript
    // could round them. JSON is an explicit opt-out local to the Rust provider.
    const input=join(dirname(path),'evaluation.json');
    writeFileSync(input,request.input,{flag:'wx'});
    const result=await supervised(program,['eval','--request',input,'--json'],{
      cwd:dirname(path),timeout:request.timeout,cancelFile:request.cancelFile,limit:1048576,
    });
    assert.ok(result.code===0||result.code===1,'conformance.evaluator_exit: '+result.stderr.slice(0,512));
    const report=JSON.parse(result.stdout);
    assert.equal(fileIdentity(input),hash(request.input),'conformance.changed_request');
    assert.equal(evaluatorIdentity(program),request.binaryIdentity,'conformance.changed_evaluator');
    process.stdout.write(JSON.stringify({profile:'morphir-rust-evaluator-result-v1',requestIdentity:hash(request.input),binaryIdentity:request.binaryIdentity,helperIdentity:request.helperIdentity,report}));
  }
} catch(cause) {const error=workbenchError(cause);process.stderr.write(String(error.message).slice(0,1024)+'\n');process.exitCode=1;}
