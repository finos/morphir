import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { hostPlatform } from './extension-qualification.ts';

// The native MoonBit guest and the Rust fault peer of
// apps/morphir/native-services/fault-fixture.rs, run as process workers on the
// CLI's worker host with contract 0.2.0 pins. The fault peer frames with the
// shared morphir-host-native library and corrupts one boundary per mode.
const repository = fileURLToPath(new URL('../../../', import.meta.url));
const binary = resolve(process.env.MORPHIR_HEADLESS_BINARY ?? join(repository, '_build/native/debug/build/finos/morphir/morphir.exe'));
const guest = resolve(process.env.MORPHIR_NATIVE_GUEST ?? join(repository, '_build/native/release/build/finos/morphir-extension/morphir-extension.exe'));
const fixtures = resolve(process.env.MORPHIR_NATIVE_FIXTURES ?? join(repository, '.dev/native-services/target/fixture'));
const fault = join(fixtures, 'native-fault-fixture');
const sha256 = (file: string) => createHash('sha256').update(readFileSync(file)).digest('hex');
const root = mkdtempSync(join(tmpdir(), 'morphir-native-prerequisites-'));
mkdirSync(join(root, 'temporary'));
const environment = { ...process.env, TMPDIR: join(root, 'temporary') };
const platform = hostPlatform();
const workerPin = (path: string, args: string[] = []) => ({
  contractVersion: '0.2.0',
  artifact: { path, sha256: sha256(path) },
  runtime: { kind: 'process', platform, args },
  origin: 'independently built native MoonBit MEP fixture',
});
const pin = workerPin(guest);
const invoke = (args: string[], status = 0) => {
  const child = spawnSync(binary, args, { cwd: root, env: environment, encoding: 'utf8', timeout: 45000 });
  assert.equal(child.status, status, `${JSON.stringify(args)}\n${child.stdout}\n${child.stderr}`);
  const report = JSON.parse(child.stdout);
  assert.equal(report.profile, 'morphir/command-result');
  assert.equal(report.exitCode, status);
  return { report, stderr: child.stderr };
};
try {
  writeFileSync(join(root, 'pin.json'), JSON.stringify(pin));
  writeFileSync(join(root, 'main.mbt'), 'pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }');
  const controls = ['--extension-pin', 'pin.json'];
  const described = invoke(['extension', 'describe', ...controls, '--json']).report;
  assert.equal(described.state, 'succeeded');
  assert.equal(described.result.extension.id, 'morphir-moonbit');
  assert.equal(described.result.worker.artifact.sha256, pin.artifact.sha256);
  // --log-file and --log-format are removed; --log-level diagnostics go to
  // stderr and stdout stays one JSON document.
  assert.equal(invoke(['extension', 'describe', ...controls, '--log-level', 'debug', '--json']).report.state, 'succeeded');
  const compiled = invoke(['extension', 'compile', 'main.mbt', '--package', 'example/boolean', '--output', 'model', ...controls, '--json']).report;
  assert.equal(compiled.state, 'succeeded');
  const generated = invoke(['extension', 'generate', 'model/model-envelope.json', '--target', 'moonbit', '--output', 'consumer', ...controls, '--json']).report;
  assert.equal(generated.state, 'succeeded');
  assert.equal(compiled.result.lifecycle.shutdown, 'acknowledged');
  assert.equal(generated.result.lifecycle.shutdown, 'acknowledged');
  assert.equal(compiled.result.lifecycle.workerStopped, true);
  assert.equal(generated.result.lifecycle.workerStopped, true);
  const envelope = JSON.parse(readFileSync(join(root, 'model/model-envelope.json'), 'utf8'));
  const bytes = readFileSync(join(root, 'model/model.ionb'));
  assert.deepEqual(Buffer.from(envelope.payload.content, 'base64'), bytes);
  assert.equal(envelope.payload.sha256, sha256(join(root, 'model/model.ionb')));
  for (const file of compiled.result.output.files) assert.equal(file.sha256, sha256(join(root, 'model', file.path)));
  assert.deepEqual(readFileSync(join(root, 'consumer/mep/source-model.ionb')), bytes);
  assert.deepEqual(JSON.parse(readFileSync(join(root, 'consumer/mep/source-envelope.json'), 'utf8')), envelope);
  assert.deepEqual(readFileSync(join(root, 'consumer/mep/source-envelope.json')), readFileSync(join(root, 'model/model-envelope.json')));
  const moduleName = 'morphir-generated/p_6578616d706c652f626f6f6c65616e';
  assert.match(readFileSync(join(root, 'consumer/moon.mod'), 'utf8'), new RegExp(moduleName));
  mkdirSync(join(root, 'smoke'));
  writeFileSync(join(root, 'moon.work'), `members=${JSON.stringify([join(root, 'consumer'), join(root, 'smoke'), join(repository, 'pkgs/morphir-sdk')])}\n`);
  writeFileSync(join(root, 'smoke/moon.mod'), `name="native-prerequisite-consumer"\nversion="0.1.0"\nimport { "${moduleName}@0.0.0" }\n`);
  writeFileSync(join(root, 'smoke/moon.pkg'), `pkgtype(kind:"executable")\nimport { "${moduleName}" @model }\n`);
  writeFileSync(join(root, 'smoke/main.mbt'), 'fn main raise { let f = @model.eligible(); let g = f(true); println(g(false)); println(g(true)) }\n');
  const smoke = spawnSync('moon', ['-C', root, 'run', 'smoke', '--target', 'native'], { encoding: 'utf8', timeout: 120000 });
  assert.equal(smoke.status, 0, smoke.stderr);
  assert.equal(smoke.stdout, 'true\nfalse\n');
  assert.equal(compiled.result.negotiated.tuple.operation, 'morphir.frontend.compileModel');
  assert.equal(generated.result.negotiated.tuple.operation, 'morphir.backend.generateModel');
  const savePin = (args: string[], filename = 'fault.json') => {
    writeFileSync(join(root, filename), JSON.stringify(workerPin(fault, args)));
    return ['--extension-pin', filename];
  };
  // Each fault mode, with the exit status and error code that the report
  // contract documents (apps/morphir/docs/extension.md#report-and-exit-status).
  const faults: [string, number, string][] = [
    ['malformed', 1, 'extension.frame_invalid'],
    ['oversize', 1, 'extension.response_limit'],
    ['crash', 1, 'extension.describe_failed'],
    ['wrong-tuple', 2, 'extension.agreement_mismatch'],
    ['wrong-context', 1, 'extension.guest_error'],
    ['wrong-digest', 1, 'extension.result_invalid'],
    ['shutdown-hang', 124, 'extension.deadline'],
  ];
  // shutdown-hang gets the pid file and marks the shutdown request, so the
  // deadline is proven to stop a worker that hangs in shutdown.
  const hangPid = join(root, 'shutdown-pid');
  for (const [mode, status, code] of faults) {
    const args = mode === 'shutdown-hang' ? [mode, hangPid] : [mode];
    const failure = invoke(['extension', 'compile', 'main.mbt', '--package', 'example/boolean', '--output', `failed-${mode}`, ...savePin(args), '--timeout', mode === 'shutdown-hang' ? '5000' : '10000', '--json'], status);
    assert.equal(failure.report.state, 'failed', mode);
    assert.equal(failure.report.error.code, code, `${mode}: ${failure.report.error.message}`);
    assert.equal(existsSync(join(root, `failed-${mode}`)), false, mode);
    assert.equal(existsSync(join(root, `failed-${mode}.morphir-partial`)), false, mode);
    assert.deepEqual(readdirSync(join(root, 'temporary')), [], `${mode} cleaned all owned temporary directories`);
  }
  assert.ok(existsSync(`${hangPid}.shutdown`), 'the deadline passed while the worker hung in shutdown');
  assert.throws(() => process.kill(Number(readFileSync(hangPid, 'utf8')), 0), /ESRCH/);
  writeFileSync(join(root, 'bad-digest.json'), JSON.stringify({ ...pin, artifact: { ...pin.artifact, sha256: '0'.repeat(64) } }));
  const mismatch = invoke(['extension', 'describe', '--extension-pin', 'bad-digest.json', '--json'], 2);
  assert.equal(mismatch.report.error.code, 'extension.digest_mismatch');
  // Guest stderr reaches stderr and the report's tail; stdout stays one JSON
  // document. A successful probe does not relay it yet (bead morphir-c4va),
  // so compile checks the operation session's stderr.
  const diagnosed = invoke(['extension', 'compile', 'main.mbt', '--package', 'example/boolean', '--output', 'diagnosed', ...savePin(['diagnostics']), '--json']);
  assert.equal(diagnosed.report.state, 'succeeded');
  assert.match(diagnosed.stderr, /native fixture diagnostic/);
  assert.match(diagnosed.report.result.stderr.text, /native fixture diagnostic/);
  const pidfile = join(root, 'pid');
  const opaque = ['operation-hang', pidfile, '--', '', '-opaque'];
  const hanging = savePin(opaque);
  const cancelled = spawn(binary, ['extension', 'compile', 'main.mbt', '--package', 'example/boolean', '--output', 'cancelled-model', ...hanging, '--cancel-file', join(root, 'cancel'), '--json'], { cwd: root, env: environment, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '', stderr = '';
  cancelled.stdout.on('data', chunk => { stdout += chunk; });
  cancelled.stderr.on('data', chunk => { stderr += chunk; });
  const closed = new Promise<number | null>(resolve => cancelled.on('close', resolve));
  const deadline = Date.now() + 10000;
  while (!existsSync(pidfile) && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 20));
  assert.ok(existsSync(pidfile), 'native fault peer started before cancellation');
  writeFileSync(join(root, 'cancel'), '');
  assert.equal(await closed, 130, stderr);
  const cancelledReport = JSON.parse(stdout);
  assert.equal(cancelledReport.exitCode, 130);
  assert.equal(cancelledReport.error.code, 'extension.cancelled');
  assert.deepEqual(JSON.parse(readFileSync(pidfile + '.args.json', 'utf8')), opaque);
  assert.equal(existsSync(join(root, 'cancelled-model')), false);
  assert.throws(() => process.kill(Number(readFileSync(pidfile, 'utf8')), 0), /ESRCH/);
  assert.deepEqual(readdirSync(join(root, 'temporary')), []);
  const evidence = join(repository, '.dev/native-services');
  mkdirSync(evidence, { recursive: true });
  writeFileSync(join(evidence, 'native-invocation-evidence.json'), JSON.stringify({
    profile: 'morphir/cli/native-provider-acceptance', contractVersion: '0.2.0',
    platform: { os: process.platform, arch: process.arch, release: platform }, pin,
    model: { modelId: envelope.modelId, revision: envelope.revision, codec: envelope.payload.codec,
      sha256: sha256(join(root, 'model/model.ionb')), bytes: bytes.length, envelopeSha256: sha256(join(root, 'model/model-envelope.json')) },
    compileNegotiation: compiled.result.negotiated, generateNegotiation: generated.result.negotiated,
    generatedFiles: generated.result.output.files, consumerStdout: smoke.stdout,
    faults: Object.fromEntries(faults.map(([mode, status, code]) => [mode, { exitCode: status, code }])),
    tested: ['exact-model-and-envelope-bytes', 'distinct-tuples', 'malformed', 'oversize', 'crash', 'wrong-tuple', 'invalid-context', 'wrong-digest', 'shutdown-deadline', 'artifact-digest', 'diagnostics', 'in-flight-cancellation', 'opaque-arguments', 'process-group-and-temporary-cleanup'],
    installedQualification: 'not-run',
  }, null, 2) + '\n');
  console.log('native acceptance passed: exact model/envelope, distinct tuples, framing, crash, contexts, integrity, shutdown, diagnostics, cancellation and cleanup on the worker host');
} finally { rmSync(root, { recursive: true, force: true }); }
