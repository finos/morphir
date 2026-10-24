import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { extensionCommand } from '../build-provider/extension.mjs';

const supported = process.platform !== 'win32';
const modules = ['node-mep-cli.mjs', 'node-mep-stdio.mjs', 'node-mep-adapter.mjs', 'node-mep-worker.mjs',
  'mep-adapter.mjs', 'mep-frames.mjs', 'wasm-memory.mjs', 'node-artifacts.mjs', 'artifacts.mjs',
  'assembly.mjs', 'index.mjs', 'dist/bridge.mjs'];
const sha256 = (path: string) => createHash('sha256').update(readFileSync(path)).digest('hex');

/** A pinned stand-in runtime: `--version` answers like Node 24.22.0, and the
 * guest entry module is the per-test behaviour, pinned like every other byte. */
function fixture(guest: string, version = 'v24.22.0', pinnedVersion = 'v24.22.0') {
  const root = mkdtempSync(join(tmpdir(), 'morphir-extension-provider-'));
  const runtime = join(root, 'runtime');
  writeFileSync(runtime, `#!${process.execPath}\nif(process.argv[2]==='--version'){console.log('${version}');process.exit(0);}\nimport(require('node:url').pathToFileURL(process.argv[2]).href);\n`, { mode: 0o700 });
  const host = join(root, 'host'), artifact = join(root, 'artifact'), work = join(root, 'work');
  mkdirSync(join(host, 'dist'), { recursive: true }); mkdirSync(artifact); mkdirSync(work);
  for (const name of modules) writeFileSync(join(host, name), name === 'node-mep-cli.mjs' ? guest : `// ${name}\n`);
  writeFileSync(join(artifact, 'model.wasm'), Buffer.from([0, 97, 115, 109, 1, 0, 0, 0]));
  writeFileSync(join(artifact, 'manifest.ion'), Buffer.from([0xe0, 1, 0, 0xea]));
  const request = join(root, 'request.bin');
  writeFileSync(request, 'Content-Length: 2\r\n\r\n{}');
  const config = {
    profile: 'morphir/cli/extension-command', contractVersion: '0.1.0-draft.1',
    pin: {
      contractVersion: '0.1.0-draft.1', binding: 'core-wasm-process',
      executionProfile: { id: 'morphir/mep-bytes-v1/v1-draft', sha256: '6ed5e96fa9c7f7dcaa179efc88e517307463cfeddc5e2eeae854f0395e7a4ec6' },
      runtime: { name: 'node', version: pinnedVersion, executable: runtime, sha256: sha256(runtime) },
      host: { root: host, modules: Object.fromEntries(modules.map(name => [name, sha256(join(host, name))])) },
      artifact: { directory: artifact, wasmSha256: sha256(join(artifact, 'model.wasm')), manifestSha256: sha256(join(artifact, 'manifest.ion')) },
      origin: 'controlled process fixture',
    },
    requestFile: request, responseFile: join(root, 'response.bin'), workDirectory: work, timeout: 10000, cancelFile: '',
  };
  return { root, artifact, work, config, dispose: () => rmSync(root, { recursive: true, force: true }) };
}

test('extension pins every runtime, host and guest byte before launching the guest', { skip: !supported }, async () => {
  const f = fixture(`import {writeFileSync} from 'node:fs';writeFileSync(${JSON.stringify('started')},'yes');`);
  try {
    const wasm = await extensionCommand({ ...f.config, pin: { ...f.config.pin, artifact: { ...f.config.pin.artifact, wasmSha256: '0'.repeat(64) } } });
    assert.equal(wasm.state, 'refused'); assert.equal(wasm.error, 'extension.identity_mismatch');
    const host = structuredClone(f.config); host.pin.host.modules['dist/bridge.mjs'] = '0'.repeat(64);
    assert.equal((await extensionCommand(host)).error, 'extension.identity_mismatch');
    const missing = structuredClone(f.config); delete (missing.pin.host.modules as Record<string, string>)['index.mjs'];
    assert.equal((await extensionCommand(missing)).error, 'extension.incomplete_host_modules');
    const binding = await extensionCommand({ ...f.config, pin: { ...f.config.pin, binding: 'component-model' } });
    assert.equal(binding.error, 'extension.unsupported_binding');
    assert.equal(existsSync(join(f.work, 'started')), false);
    assert.equal(readdirSync(f.work).length, 0);
  } finally { f.dispose(); }
  const old = fixture('', 'v22.0.0');
  try {
    const result = await extensionCommand(old.config);
    assert.equal(result.state, 'refused'); assert.equal(result.error, 'extension.runtime_version_mismatch');
  } finally { old.dispose(); }
});

test('extension accepts the Node security patch and enforces its exact pin', { skip: !supported }, async () => {
  const patched = fixture('process.stdin.pipe(process.stdout);', 'v24.22.1', 'v24.22.1');
  try {
    const result = await extensionCommand(patched.config);
    assert.equal(result.state, 'exited', result.error ?? 'Extension execution failed');
    assert.deepEqual(readFileSync(patched.config.responseFile), readFileSync(patched.config.requestFile));
  } finally { patched.dispose(); }
  const mismatch = fixture('', 'v24.22.0', 'v24.22.1');
  try {
    const result = await extensionCommand(mismatch.config);
    assert.equal(result.state, 'refused');
    assert.equal(result.error, 'extension.runtime_version_mismatch');
  } finally { mismatch.dispose(); }
});

test('extension returns the guest bytes, exit status and diagnostics separately', { skip: !supported }, async () => {
  const f = fixture(`process.stdin.pipe(process.stdout);process.stderr.write('guest diagnostic');process.stdin.on('end',()=>{process.exitCode=3;});`);
  try {
    const result = await extensionCommand(f.config);
    assert.equal(result.state, 'exited'); assert.equal(result.exitCode, 3);
    assert.equal(result.stderr, 'guest diagnostic'); assert.equal(result.workDirectoryEmpty, true);
    assert.deepEqual(readFileSync(f.config.responseFile), readFileSync(f.config.requestFile));
    // The response file is never replaced.
    assert.equal((await extensionCommand(f.config)).state, 'failed');
  } finally { f.dispose(); }
});

test('extension reports guest files and runs only verified copies', { skip: !supported }, async () => {
  const writes = fixture(`import {writeFileSync} from 'node:fs';writeFileSync('escape.txt','x');`);
  try {
    const result = await extensionCommand(writes.config);
    assert.equal(result.state, 'exited'); assert.equal(result.workDirectoryEmpty, false);
  } finally { writes.dispose(); }
  // The guest receives private verified copies; replacing the pinned paths
  // during the run changes neither what executes nor the reported outcome.
  const staged = fixture(`import {appendFileSync,readFileSync} from 'node:fs';import {createHash} from 'node:crypto';
const [entry,artifact]=process.argv.slice(2);appendFileSync(ORIGINAL,'x');
const h=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
process.stdout.write(JSON.stringify({runtime:process.execPath,entry,artifact,wasm:h(artifact+'/model.wasm'),entryHash:h(entry)}));`);
  try {
    const guest = join(staged.root, 'host', 'node-mep-cli.mjs');
    writeFileSync(guest, readFileSync(guest, 'utf8').replace('ORIGINAL', JSON.stringify(join(staged.artifact, 'model.wasm'))));
    const pinned = structuredClone(staged.config);
    pinned.pin.host.modules['node-mep-cli.mjs'] = sha256(guest);
    const result = await extensionCommand(pinned);
    assert.equal(result.state, 'exited', result.error ?? "Extension execution failed"); assert.equal(result.exitCode, 0);
    const seen = JSON.parse(readFileSync(pinned.responseFile, 'utf8'));
    for (const path of [seen.entry, seen.artifact]) assert.ok(!path.startsWith(staged.root), path);
    assert.equal(seen.wasm, pinned.pin.artifact.wasmSha256);
    assert.equal(seen.entryHash, pinned.pin.host.modules['node-mep-cli.mjs']);
    assert.notEqual(sha256(join(staged.artifact, 'model.wasm')), pinned.pin.artifact.wasmSha256);
    // The private copies are removed once the guest's process group is gone.
    assert.equal(existsSync(seen.artifact), false);
  } finally { staged.dispose(); }
});

test('extension deadlines and cancellation stop the whole guest process group', { skip: !supported }, async () => {
  const guest = `import {spawn} from 'node:child_process';import {writeFileSync} from 'node:fs';
const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'});
writeFileSync(${JSON.stringify('../pids')},String(child.pid));setInterval(()=>{},1000);`;
  const alive = (pid: number) => { try { process.kill(pid, 0); return true; } catch { return false; } };
  const timed = fixture(guest);
  try {
    const result = await extensionCommand({ ...timed.config, timeout: 1500 });
    assert.equal(result.state, 'failed'); assert.match(result.error!, /execution.deadline/);
    assert.equal(alive(Number(readFileSync(join(timed.root, 'pids'), 'utf8'))), false);
  } finally { timed.dispose(); }
  const cancelled = fixture(guest);
  try {
    const cancel = join(cancelled.root, 'cancel');
    const timer = setInterval(() => { if (existsSync(join(cancelled.root, 'pids'))) writeFileSync(cancel, ''); }, 10);
    let result;
    try { result = await extensionCommand({ ...cancelled.config, cancelFile: cancel }); } finally { clearInterval(timer); }
    assert.equal(result.state, 'cancelled'); assert.equal(existsSync(cancelled.config.responseFile), false);
    assert.equal(alive(Number(readFileSync(join(cancelled.root, 'pids'), 'utf8'))), false);
    const before = await extensionCommand(cancelled.config, () => true);
    assert.equal(before.state, 'cancelled');
  } finally { cancelled.dispose(); }
});

test('extension bounds guest diagnostics and refuses malformed controls', { skip: !supported }, async () => {
  const noisy = fixture(`process.stderr.write('x'.repeat(65537));setInterval(()=>{},1000);`);
  try {
    const result = await extensionCommand(noisy.config);
    assert.equal(result.state, 'failed'); assert.match(result.error!, /execution.diagnostic_limit/);
  } finally { noisy.dispose(); }
  const f = fixture('');
  try {
    assert.equal((await extensionCommand({ ...f.config, extra: true })).error, 'extension.invalid_request');
    assert.equal((await extensionCommand({ ...f.config, timeout: 594001 })).error, 'extension.invalid_request');
    assert.equal((await extensionCommand({ ...f.config, pin: { ...f.config.pin, runtime: { ...f.config.pin.runtime, version: 'v24.22.2' } } })).error,
      'extension.unsupported_runtime');
    writeFileSync(join(f.work, 'stale'), '');
    assert.equal((await extensionCommand(f.config)).error, 'extension.invalid_request');
  } finally { f.dispose(); }
});
