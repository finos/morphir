import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { extensionCommand, helperModules, type ExtismPin } from './extism.mjs';

// These peers exercise the immutable helper boundary, not MEP compatibility.
// The real Python bundle acceptance belongs to the CLI integration suite.
const root = realpathSync(mkdtempSync(join(tmpdir(), 'morphir-extism-helper-test-')));
const previousTemporary = process.env.TMPDIR;
mkdirSync(join(root,'snapshots'));
process.env.TMPDIR = join(root,'snapshots');
const digest = (bytes: Buffer | string) => createHash('sha256').update(bytes).digest('hex');
const fileDigest = (path: string) => digest(readFileSync(path));
const source = dirname(fileURLToPath(import.meta.url));
const revision = 'a'.repeat(40);
const quote = (value: string) => "'" + value.replaceAll("'", "'\\''") + "'";
const snapshots = () => readdirSync(tmpdir()).filter(name => name.startsWith('morphir-extism-') && !name.startsWith('morphir-extism-helper-test-')).sort();
const initialSnapshots = snapshots();
let serial = 0;

function fixture(body: string) {
  const directory = join(root, String(++serial));
  const artifact = join(directory, 'bundle'), helper = join(directory, 'helper'), work = join(directory, 'work');
  for (const path of [artifact, helper, work]) mkdirSync(path, {recursive:true});
  for (const name of helperModules) copyFileSync(join(source, name), join(helper,name));
  writeFileSync(join(artifact,'guest.wasm'), Buffer.from([0,97,115,109,1,0,0,0]));
  const wasmSha256 = fileDigest(join(artifact,'guest.wasm'));
  writeFileSync(join(artifact,'release.json'), JSON.stringify({schemaVersion:'2.0.0-draft.2',shortId:'fixture',extensionId:'fixture',version:'1.0.0',
    artifacts:[{runtime:'wasm',filename:'guest.wasm',sha256:wasmSha256,claims:{}}]}));
  const host = join(directory, 'host');
  const prelude = 'let input="";process.stdin.setEncoding("utf8");process.stdin.on("data",b=>input+=b);process.stdin.on("end",()=>{const request=JSON.parse(input);';
  writeFileSync(host, '#!/bin/sh\nexec ' + quote(process.execPath) + ' -e ' + quote(prelude + body + '});') + '\n'); chmodSync(host,0o500);
  const modules = Object.fromEntries(helperModules.map(name => [name,fileDigest(join(helper,name))]));
  const pin: ExtismPin = {contractVersion:'0.1.0',binding:'extism-wasm',executionProfile:'morphir/extism-mep-0.1/v1',
    host:{executable:host,sha256:fileDigest(host),sourceRevision:revision}, runtime:{executable:process.execPath,version:process.version,sha256:fileDigest(process.execPath)},
    helper:{root:helper,modules}, artifact:{directory:artifact,descriptorSha256:fileDigest(join(artifact,'release.json')),wasmSha256,extensionId:'fixture',version:'1.0.0'},origin:'test peer'};
  const requestFile = join(directory,'request.json'), responseFile = join(directory,'response.json');
  const config = {profile:'morphir/cli/extism-services',contractVersion:'0.1.0',pin,requestFile,responseFile,workDirectory:work,timeout:10000,cancelFile:''};
  const writeRequest = (extra: Record<string,unknown> = {}) => writeFileSync(requestFile,JSON.stringify({operation:'extism.describe',pin,workDirectory:work,timeout:10000,...extra}));
  writeRequest();
  return {directory,config,pin,writeRequest,responseFile,requestFile,work,artifact,helper,host};
}
const reply = 'process.stdout.write(JSON.stringify({profile:"morphir/native-services",contractVersion:"0.1.0",sourceRevision:request.pin.host.sourceRevision,state:"succeeded",result:{pin:request.pin,work:process.cwd(),environment:Object.keys(process.env)}}));';

try {
  const ok = fixture('process.stderr.write("separate diagnostic");' + reply);
  const success = await extensionCommand(ok.config);
  assert.equal(success.state,'exited',success.error ?? 'successful helper execution'); assert.equal(success.stderr,'separate diagnostic'); assert.equal(success.workDirectoryEmpty,true);
  const result = JSON.parse(readFileSync(ok.responseFile,'utf8')).result;
  assert.equal(result.work,ok.work); assert.ok(result.environment.includes('TMPDIR'));
  assert.ok(!result.environment.includes('PATH') && !result.environment.includes('HOME'),'user environment is not inherited');
  assert.notEqual(result.pin.host.executable,ok.pin.host.executable);
  assert.notEqual(result.pin.runtime.executable,ok.pin.runtime.executable);
  assert.notEqual(result.pin.helper.root,ok.pin.helper.root);
  assert.notEqual(result.pin.artifact.directory,ok.pin.artifact.directory);
  assert.equal(existsSync(result.pin.host.executable),false,'verified host storage is removed after the owned group exits');

  const opaque = fixture('process.stdout.write(JSON.stringify({profile:"morphir/native-services",contractVersion:"0.1.0",sourceRevision:request.pin.host.sourceRevision,result:{opaque:input}}));');
  const numericTokens='9007199254740993,-9007199254740993,1.2300,1e+30,-0';
  writeFileSync(opaque.requestFile,'{"operation":"extism.generate","pin":'+JSON.stringify(opaque.pin)+',"params":{"values":['+numericTokens+']},"timeout":10000,"workDirectory":'+JSON.stringify(opaque.work)+'}');
  assert.equal((await extensionCommand(opaque.config)).state,'exited');
  assert.ok(JSON.parse(readFileSync(opaque.responseFile,'utf8')).result.opaque.includes('"values":['+numericTokens+']'),'opaque IR retains exact large positive/negative integer, decimal and exponent tokens');
  const unsupportedRuntime = fixture(reply);
  const jsonApi = JSON as unknown as {rawJSON: unknown};
  const raw = jsonApi.rawJSON;
  try { jsonApi.rawJSON=undefined;assert.equal((await extensionCommand(unsupportedRuntime.config)).error,'extension.unsupported_runtime'); }
  finally {jsonApi.rawJSON=raw;}

  for (const kind of ['host','runtime','helper','descriptor','wasm'] as const) {
    const bad = fixture(reply);
    if (kind === 'host' || kind === 'runtime') bad.pin[kind].sha256 = '0'.repeat(64);
    else if (kind === 'helper') bad.pin.helper.modules['extism.mjs'] = '0'.repeat(64);
    else bad.pin.artifact[kind === 'descriptor' ? 'descriptorSha256' : 'wasmSha256'] = '0'.repeat(64);
    bad.writeRequest();
    const refused = await extensionCommand(bad.config);
    assert.equal(refused.state,'failed',kind); assert.equal(refused.error,'extension.integrity_mismatch',kind);
    assert.equal(existsSync(bad.responseFile),false);
  }
  const incomplete = fixture(reply);
  delete incomplete.pin.helper.modules['windows-job.mjs']; incomplete.writeRequest();
  assert.equal((await extensionCommand(incomplete.config)).error,'extension.incomplete_helper_modules');
  const unknown = fixture(reply);
  assert.equal((await extensionCommand({...unknown.config,pin:{...unknown.pin,unexpected:true}})).error,'extension.invalid_pin');

  const mismatched = fixture(reply);
  mismatched.writeRequest({pin:{...mismatched.pin,origin:'different request authority'}});
  assert.equal((await extensionCommand(mismatched.config)).error,'extension.invalid_request');
  const version = fixture(reply); version.pin.runtime.version = 'v0.0.0'; version.writeRequest();
  assert.equal((await extensionCommand(version.config)).error,'extension.runtime_version_mismatch');

  const traversal = fixture(reply);
  const descriptor = JSON.parse(readFileSync(join(traversal.artifact,'release.json'),'utf8'));
  descriptor.artifacts[0].filename = '../escape.wasm';
  writeFileSync(join(traversal.artifact,'release.json'),JSON.stringify(descriptor));
  traversal.pin.artifact.descriptorSha256=fileDigest(join(traversal.artifact,'release.json')); traversal.writeRequest();
  assert.equal((await extensionCommand(traversal.config)).error,'extension.unsafe_artifact');
  const symbolic = fixture(reply);
  const bytes = readFileSync(join(symbolic.artifact,'guest.wasm'));
  rmSync(join(symbolic.artifact,'guest.wasm'));writeFileSync(join(symbolic.directory,'outside.wasm'),bytes);
  symlinkSync(join(symbolic.directory,'outside.wasm'),join(symbolic.artifact,'guest.wasm'));
  assert.equal((await extensionCommand(symbolic.config)).error,'extension.unsafe_artifact');

  const replaced = fixture('const fs=require("node:fs");const old=request.original;fs.writeFileSync(old.wasm,"replacement");fs.writeFileSync(old.helper,"replacement");'
    + 'const data=fs.readFileSync(require("node:path").join(request.pin.artifact.directory,"guest.wasm"));'
    + 'if(data.toString("hex")!=="0061736d01000000")process.exit(7);' + reply);
  replaced.writeRequest({original:{wasm:join(replaced.artifact,'guest.wasm'),helper:join(replaced.helper,'extism.mjs')}});
  assert.equal((await extensionCommand(replaced.config)).state,'exited','replacing pinned source paths cannot change executed snapshots');

  const writes = fixture('require("node:fs").writeFileSync("guest-file","unwanted");' + reply);
  assert.equal((await extensionCommand(writes.config)).error,'extension.guest_wrote_files');
  assert.equal(existsSync(writes.responseFile),false);
  const oversized = fixture(reply);writeFileSync(oversized.requestFile,Buffer.alloc(4194305));
  assert.equal((await extensionCommand(oversized.config)).error,'extension.resource_limit');
  const exactRequest = fixture(reply);
  const requestBytes = readFileSync(exactRequest.requestFile);
  writeFileSync(exactRequest.requestFile,Buffer.concat([requestBytes,Buffer.alloc(4194304-requestBytes.length,32)]));
  assert.equal((await extensionCommand(exactRequest.config)).state,'exited','exact request byte ceiling remains accepted');
  for (const extra of [0,1]) {
    const descriptorBound = fixture(reply);
    const descriptorPath=join(descriptorBound.artifact,'release.json'), before=readFileSync(descriptorPath);
    writeFileSync(descriptorPath,Buffer.concat([before,Buffer.alloc(1048576+extra-before.length,32)]));
    descriptorBound.pin.artifact.descriptorSha256=fileDigest(descriptorPath);descriptorBound.writeRequest();
    const result=await extensionCommand(descriptorBound.config);
    assert.equal(extra ? result.error : result.state,extra ? 'extension.resource_limit' : 'exited');
  }
  const exactReply = fixture('const response={profile:"morphir/native-services",contractVersion:"0.1.0",sourceRevision:request.pin.host.sourceRevision,padding:""};'
    + 'response.padding="x".repeat(16777216-Buffer.byteLength(JSON.stringify(response)));process.stderr.write(Buffer.alloc(65536,120));process.stdout.write(JSON.stringify(response));');
  const exactResult=await extensionCommand(exactReply.config);
  assert.equal(exactResult.state,'exited',exactResult.error ?? 'exact output byte ceiling');assert.equal(exactResult.stderr.length,65536);
  assert.equal(readFileSync(exactReply.responseFile).length,16777216);
  const malformed = fixture('process.stdout.write("not JSON")');
  assert.equal((await extensionCommand(malformed.config)).error,'extension.invalid_result');
  const wrongRevision = fixture('process.stdout.write(JSON.stringify({profile:"morphir/native-services",contractVersion:"0.1.0",sourceRevision:"wrong"}))');
  assert.equal((await extensionCommand(wrongRevision.config)).error,'extension.invalid_result');

  for (const [body,error] of [
    ['process.stdout.write(Buffer.alloc(16777217));setInterval(()=>{},1000);','extension.resource_limit'],
    ['process.stderr.write(Buffer.alloc(65537));setInterval(()=>{},1000);','extension.resource_limit'],
    ['setInterval(()=>{},1000);','extension.timeout'],
    ['process.exit(9);','extension.host_failed'],
  ] as const) {
    const bad = fixture(body); if (error === 'extension.timeout') bad.config.timeout=350;
    const failure = await extensionCommand(bad.config);
    assert.equal(failure.error,error); assert.equal(failure.workDirectoryEmpty,true); assert.equal(existsSync(bad.responseFile),false);
  }
  const cancelled = fixture('setInterval(()=>{},1000);');
  const cancellation = join(cancelled.directory,'cancel');cancelled.config.cancelFile=cancellation;
  const timer=setTimeout(()=>writeFileSync(cancellation,''),350);
  try { const result=await extensionCommand(cancelled.config);assert.equal(result.state,'cancelled');assert.equal(result.error,'execution.cancelled');assert.equal(result.workDirectoryEmpty,true); }
  finally {clearTimeout(timer);}
  const signalled = fixture('require("node:fs").writeFileSync(request.started,"ready");setInterval(()=>{},1000);');
  const started=join(signalled.directory,'started');signalled.writeRequest({started});
  const control=join(signalled.directory,'control.json');writeFileSync(control,JSON.stringify(signalled.config));
  const copiedEntry=join(signalled.helper,'extism.mjs');
  const entryAlias=copiedEntry.startsWith('/private/var/') ? copiedEntry.slice('/private'.length) : copiedEntry;
  const processPeer=spawn(process.execPath,[entryAlias,'--morphir-extension-v1',control],{stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';processPeer.stdout.on('data',bytes=>stdout+=bytes);processPeer.stderr.on('data',bytes=>stderr+=bytes);
  const closed=new Promise<number|null>(done=>processPeer.once('close',code=>done(code)));
  try {
    const deadline=performance.now()+10000;
    while(!existsSync(started)) {assert.ok(performance.now()<deadline,'signal peer started');await new Promise(done=>setTimeout(done,10));}
    processPeer.kill('SIGINT');assert.equal(await closed,0);
    const signalReply=JSON.parse(stdout);assert.equal(signalReply.state,'cancelled');assert.equal(signalReply.error,'execution.cancelled');
    assert.equal(signalReply.workDirectoryEmpty,true);assert.equal(stderr,'');
  } finally {if(processPeer.exitCode===null&&processPeer.signalCode===null){processPeer.kill('SIGKILL');await closed;}}
  assert.deepEqual(snapshots(),initialSnapshots,'all helper-owned snapshots are cleaned after confirmed child termination');
  assert.equal(process.listenerCount('SIGINT'),0); assert.equal(process.listenerCount('SIGTERM'),0);
  console.log('Extism helper immutable closure, explicit pins, denied inheritance, byte limits, cancellation and cleanup passed');
} finally {
  if(previousTemporary === undefined) delete process.env.TMPDIR; else process.env.TMPDIR=previousTemporary;
  rmSync(root,{recursive:true,force:true});
}
