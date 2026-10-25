import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../../../', import.meta.url));
const binary = resolve(process.env.MORPHIR_HEADLESS_BINARY ?? join(repository, '_build/native/debug/build/morphir/morphir/morphir.exe'));
const guest = resolve(process.env.MORPHIR_NATIVE_GUEST ?? join(repository, '_build/native/release/build/finos/morphir-extension/morphir-extension.exe'));
const adapter = resolve(process.env.MORPHIR_NATIVE_SERVICES ?? join(repository, '.dev/native-services/target/debug/morphir-moonbit-native-services'));
const helper = join(repository, 'apps/morphir/build-provider/native-services.mjs');
const fault = resolve(join(adapter, '../native-fault-fixture'));
const sha256 = (file: string) => createHash('sha256').update(readFileSync(file)).digest('hex');
const root = mkdtempSync(join(tmpdir(), 'morphir-native-prerequisites-'));
mkdirSync(join(root, 'temporary'));
const environment = { ...process.env, TMPDIR: join(root, 'temporary') };
const pin = { binding: 'native-process', contractVersion: '0.1.0',
  host: { executable: adapter, sha256: sha256(adapter), sourceRevision: 'ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409' },
  artifact: { executable: guest, sha256: sha256(guest), extensionId: 'morphir-moonbit', version: '0.1.0' },
  origin: 'independently built native MoonBit MEP fixture' };
const invoke = (args: string[], status = 0) => {
  const child = spawnSync(binary, args, { cwd: root, env: environment, encoding: 'utf8', timeout: 45000 });
  assert.equal(child.status, status, `${JSON.stringify(args)}\n${child.stdout}\n${child.stderr}`);
  return { report: JSON.parse(child.stdout), stderr: child.stderr };
};
try {
  writeFileSync(join(root, 'pin.json'), JSON.stringify(pin));
  writeFileSync(join(root, 'main.mbt'), 'pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }');
  const controls = ['--extension-pin', 'pin.json', '--extension-helper', helper];
  const described = invoke(['extension', 'describe', ...controls, '--json']).report;
  assert.equal(described.state, 'succeeded');
  assert.equal(described.result.session.extension.id, 'morphir-moonbit');
  assert.ok(existsSync(join(root, '.morphir/logs/execution.ionb')));
  invoke(['extension', 'describe', ...controls, '--log-file', join(root, 'native.jsonl'), '--log-format', 'json-lines', '--json']);
  assert.ok(readFileSync(join(root, 'native.jsonl'), 'utf8').trim().split('\n').every(line => JSON.parse(line)));
  const compiled = invoke(['extension', 'compile', 'main.mbt', '--package', 'example/boolean', '--output', 'model', ...controls, '--json']).report;
  assert.equal(compiled.state, 'succeeded');
  const generated = invoke(['extension', 'generate', 'model/model-envelope.json', '--target', 'moonbit', '--output', 'consumer', ...controls, '--json']).report;
  assert.equal(generated.state, 'succeeded');
  assert.equal(compiled.result.session.shutdown, 'acknowledged');
  assert.equal(generated.result.session.shutdown, 'acknowledged');
  const envelope = JSON.parse(readFileSync(join(root, 'model/model-envelope.json'), 'utf8'));
  const bytes = readFileSync(join(root, 'model/model.ionb'));
  assert.deepEqual(Buffer.from(envelope.payload.content, 'base64'), bytes);
  assert.equal(envelope.payload.sha256, sha256(join(root, 'model/model.ionb')));
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
  assert.notDeepEqual(compiled.result.session.negotiated.modelTransport.tuples, generated.result.session.negotiated.modelTransport.tuples);
  const savePin = (artifact: object, filename = 'fault.json') => {
    writeFileSync(join(root, filename), JSON.stringify({ ...pin, artifact }));
    return ['--extension-pin', filename, '--extension-helper', helper];
  };
  for (const mode of ['malformed', 'oversize', 'crash', 'wrong-tuple', 'wrong-context', 'wrong-digest', 'shutdown-hang']) {
    const options = savePin({ ...pin.artifact, executable: fault, sha256: sha256(fault), args: [mode] });
    const failure = invoke(['extension', 'compile', 'main.mbt', '--package', 'example/boolean', '--output', `failed-${mode}`, ...options, '--timeout', mode === 'shutdown-hang' ? '2000' : '10000', '--json'], 1);
    assert.equal(failure.report.state, 'failed', mode);
    assert.equal(existsSync(join(root, `failed-${mode}`)), false, mode);
    assert.equal(existsSync(join(root, `failed-${mode}.morphir-partial`)), false, mode);
    assert.deepEqual(readdirSync(join(root, 'temporary')), [], `${mode} cleaned all owned temporary directories`);
  }
  const badPin = savePin({ ...pin.artifact, sha256: '0'.repeat(64) });
  assert.match(invoke(['extension', 'describe', ...badPin, '--json'], 1).stderr, /identity_mismatch/);
  const diagnosticPin = savePin({ ...pin.artifact, executable: fault, sha256: sha256(fault), args: ['diagnostics'] });
  const diagnosed = invoke(['extension', 'describe', ...diagnosticPin, '--json']);
  assert.match(diagnosed.stderr, /native fixture diagnostic/);
  assert.equal(diagnosed.report.state, 'succeeded');
  const pidfile = join(root, 'pid');
  const opaque = ['operation-hang', pidfile, '--', '', '-opaque'];
  const hanging = savePin({ ...pin.artifact, executable: fault, sha256: sha256(fault), args: opaque });
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
  assert.equal(JSON.parse(stdout).exitCode, 130);
  assert.deepEqual(JSON.parse(readFileSync(pidfile + '.args.json', 'utf8')), opaque);
  assert.equal(existsSync(join(root, 'cancelled-model')), false);
  assert.throws(() => process.kill(Number(readFileSync(pidfile, 'utf8')), 0), /ESRCH/);
  assert.deepEqual(readdirSync(join(root, 'temporary')), []);
  const evidence = join(repository, '.dev/native-services');
  mkdirSync(evidence, { recursive: true });
  writeFileSync(join(evidence, 'native-invocation-evidence.json'), JSON.stringify({
    profile: 'morphir/cli/native-provider-acceptance', contractVersion: '0.1.0',
    platform: { os: process.platform, arch: process.arch }, pin,
    model: { modelId: envelope.modelId, revision: envelope.revision, codec: envelope.payload.codec,
      sha256: sha256(join(root, 'model/model.ionb')), bytes: bytes.length, envelopeSha256: sha256(join(root, 'model/model-envelope.json')) },
    compileNegotiation: compiled.result.session.negotiated, generateNegotiation: generated.result.session.negotiated,
    generatedFiles: generated.result.outputs, consumerStdout: smoke.stdout,
    tested: ['exact-model-and-envelope-bytes', 'distinct-tuples', 'malformed', 'oversize', 'crash', 'wrong-tuple', 'invalid-context', 'wrong-digest', 'shutdown-deadline', 'diagnostics', 'in-flight-cancellation', 'opaque-arguments', 'process-group-and-temporary-cleanup'],
    installedQualification: 'not-run',
  }, null, 2) + '\n');
  console.log('native acceptance passed: exact model/envelope, distinct tuples, framing, crash, contexts, integrity, shutdown, diagnostics, cancellation and cleanup');
} finally { rmSync(root, { recursive: true, force: true }); }
