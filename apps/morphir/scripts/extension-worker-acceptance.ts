import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

/** How to start one CLI: the native executable, or Node with the npm entry. */
export interface CliInvocation { command: string; prefix: readonly string[] }

const sha256 = (path: string) => createHash('sha256').update(readFileSync(path)).digest('hex');

let guest: string | undefined;

/** The native MoonBit guest of apps/morphir-extension, built once per run. */
function nativeGuest(workspace: string): string {
  if (guest) return guest;
  execFileSync('moon', ['build', 'apps/morphir-extension', '--target', 'native', '--release'],
    { cwd: workspace, stdio: ['ignore', 2, 2] });
  guest = join(workspace, '_build/native/release/build/finos/morphir-extension/morphir-extension.exe');
  assert.ok(existsSync(guest), guest);
  return guest;
}

/** The release platform of this host, in the form of a pin runtime. */
function hostPlatform(): string {
  const arch = ({ arm64: 'aarch64', x64: 'x86_64' } as Record<string, string>)[process.arch];
  assert.ok(arch, `No release platform for ${process.arch}`);
  if (process.platform === 'darwin') return `${arch}-apple-darwin`;
  const report = process.report?.getReport?.() as { header?: { glibcVersionRuntime?: string } } | undefined;
  return `${arch}-unknown-linux-${report?.header?.glibcVersionRuntime ? 'gnu' : 'musl'}`;
}

/** The pinned Python extension release, an extism-kernel-v1 WASM guest. */
const python = { version: '0.4.2', sha256: '10acafa0f0282c5240e9620a5f2bb21629cc7580b9add528e7b77c7e54db22b5' };

/**
 * The Python extension module. It is read from MORPHIR_PYTHON_EXTENSIONS, or
 * from the download directory of `mise run test:wasm-workers`, and downloaded
 * there when it is missing. The SHA-256 is always checked.
 */
function pythonGuest(workspace: string): string {
  const root = process.env.MORPHIR_PYTHON_EXTENSIONS || join(workspace, '.dev/wasm-workers/python');
  const file = join(root, python.version, `morphir-python-binding-${python.version}.wasm`);
  if (!existsSync(file) || sha256(file) !== python.sha256) {
    mkdirSync(join(root, python.version), { recursive: true });
    execFileSync('curl', ['--fail', '--silent', '--show-error', '--location', '--output', file,
      `https://github.com/finos/morphir-python/releases/download/extension%2Fpython%2Fv${python.version}/morphir-python-binding-${python.version}.wasm`],
    { stdio: ['ignore', 2, 2] });
  }
  assert.equal(sha256(file), python.sha256, file);
  return file;
}

function pin(artifact: string, extra: Record<string, unknown> = {}) {
  return {
    contractVersion: '0.2.0',
    artifact: { path: artifact, sha256: sha256(artifact) },
    runtime: { kind: 'process', platform: hostPlatform(), args: [] },
    origin: 'finos/morphir-moonbit apps/morphir-extension (local build)',
    ...extra,
  };
}

type Report = {
  state: string; exitCode: number; command: string;
  result?: Record<string, any>; error?: { code: string; message: string };
};

/**
 * Runs describe, compile and generate on the CLI's worker host with the native
 * MoonBit guest, as a process worker, in fresh output directories. The native
 * CLI runs with a PATH that has no Node. Windows is qualified in its own
 * deliberate run (tasks 2.3 and 7.5).
 */
export function exerciseExtensionWorker(cli: CliInvocation, workspace: string, label: string) {
  if (process.platform === 'win32') return;
  const artifact = nativeGuest(workspace);
  const directory = mkdtempSync(join(tmpdir(), `morphir-extension-worker-${label}-`));
  try {
    const put = (name: string, value: unknown) =>
      writeFileSync(join(directory, name), typeof value === 'string' ? value : JSON.stringify(value));
    put('pin.json', pin(artifact));
    put('main.mbt', 'pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }\n');
    const env: NodeJS.ProcessEnv = { PATH: '/usr/bin:/bin', HOME: directory };
    if (label !== 'native') env.PATH = `${join(process.execPath, '..')}:/usr/bin:/bin`;
    const run = (args: string[], expected: number) => {
      const result = spawnSync(cli.command, [...cli.prefix, ...args],
        { cwd: directory, env, encoding: 'utf8', timeout: 120000 });
      assert.equal(result.status, expected, `${label} ${JSON.stringify(args)}:\n${result.stdout}\n${result.stderr}`);
      return result;
    };
    // stdout holds exactly one JSON document in JSON mode.
    const report = (args: string[], expected: number): Report => JSON.parse(run([...args, '--json'], expected).stdout);

    const described = report(['extension', 'describe', '--extension-pin', 'pin.json'], 0);
    assert.equal(described.state, 'succeeded');
    assert.equal(described.command, 'extension.describe');
    assert.equal(described.result!.worker.kind, 'process');
    assert.equal(described.result!.extension.id, 'morphir-moonbit');
    assert.ok(described.result!.claims.operations.includes('morphir.frontend.compileModel'));
    assert.match(run(['extension', 'describe', '--extension-pin', 'pin.json'], 0).stdout, /^morphir-moonbit 0\.1\.0: process worker/);

    const compiled = report(['extension', 'compile', 'main.mbt', '--package', 'acme/rules', '--output', 'model',
      '--extension-pin', 'pin.json'], 0);
    assert.equal(compiled.state, 'succeeded');
    assert.equal(compiled.exitCode, 0);
    assert.equal(compiled.result!.protocolVersion, '0.2.0-draft.1');
    // The CLI offers Ion, then JSON. The MoonBit guest supports both, so it
    // agrees on both and the session uses Ion.
    assert.equal(compiled.result!.negotiated.tuple.codec, 'ion-binary');
    assert.equal(compiled.result!.negotiated.limits.maxDepth, 128);
    assert.equal(compiled.result!.lifecycle.shutdown, 'acknowledged');
    assert.deepEqual(compiled.result!.output.files.map((file: { path: string }) => file.path), ['model-envelope.json', 'model.ionb']);
    for (const file of compiled.result!.output.files) {
      assert.equal(file.sha256, sha256(join(directory, 'model', file.path)));
    }
    assert.equal(existsSync(join(directory, 'model.morphir-partial')), false);

    const generated = report(['extension', 'generate', 'model/model-envelope.json', '--output', 'generated',
      '--extension-pin', 'pin.json'], 0);
    assert.equal(generated.state, 'succeeded');
    const files = generated.result!.output.files.map((file: { path: string }) => file.path);
    assert.ok(files.includes('library.mbt') && files.includes('mep/source-model.ionb'), JSON.stringify(files));

    // Refusals before an operation exit 2 and publish nothing.
    assert.equal(report(['extension', 'compile', 'main.mbt', '--package', 'acme/rules', '--output', 'model',
      '--extension-pin', 'pin.json'], 2).error!.code, 'extension.output_exists');
    assert.equal(report(['extension', 'describe', '--extension-pin', 'pin.json', '--node', 'node'], 2).error!.code,
      'extension.option_retired');
    put('old-pin.json', { contractVersion: '0.1.0-draft.1', binding: 'core-wasm-process', origin: 'old' });
    const retired = report(['extension', 'describe', '--extension-pin', 'old-pin.json'], 2);
    assert.equal(retired.error!.code, 'extension.pin_retired');
    assert.match(retired.error!.message, /0\.2\.0[\s\S]*https:\/\/github\.com\/finos\/morphir-moonbit\/blob\/main\/apps\/morphir\/docs\/extension\.md#migrate-a-pin/);
    assert.equal(retired.result, undefined);

    // A descriptor whose claims differ from the live describe is refused.
    put('release.json', { schemaVersion: '2.0.0-draft.2', artifacts: [{ sha256: sha256(artifact), claims: {
      extension: { id: 'morphir-moonbit', version: '9.9.9' }, protocolVersions: ['0.1'], capabilities: {} } }] });
    put('drift-pin.json', pin(artifact, { descriptor: { path: join(directory, 'release.json'), sha256: sha256(join(directory, 'release.json')) } }));
    const drift = report(['extension', 'describe', '--extension-pin', 'drift-pin.json'], 2);
    assert.equal(drift.error!.code, 'extension.claims_mismatch');

    // A guest that writes to stderr leaves stdout as one JSON object; the
    // tail is in the report.
    const noisy = join(directory, 'noisy-guest');
    writeFileSync(noisy, `#!/bin/sh\necho "noisy guest diagnostic" >&2\nexec ${JSON.stringify(artifact)} "$@"\n`);
    chmodSync(noisy, 0o755);
    put('noisy-pin.json', pin(noisy));
    const loud = report(['extension', 'compile', 'main.mbt', '--package', 'acme/rules', '--output', 'noisy-model',
      '--extension-pin', 'noisy-pin.json'], 0);
    assert.match(loud.result!.stderr.text, /noisy guest diagnostic/);

    // A cancel file stops the command with 130 and nothing is published.
    put('cancel', '');
    const cancelled = report(['extension', 'generate', 'model/model-envelope.json', '--output', 'cancelled',
      '--extension-pin', 'pin.json', '--cancel-file', 'cancel'], 130);
    assert.equal(cancelled.error!.code, 'extension.cancelled');
    assert.equal(existsSync(join(directory, 'cancelled')), false);
    assert.equal(existsSync(join(directory, 'cancelled.morphir-partial')), false);
    console.log(`Extension worker host acceptance passed: ${label}`);
  } finally { rmSync(directory, { recursive: true, force: true }); }
  exerciseExtismWorker(cli, workspace, label);
}

/** How long one Python command may take before the process counts as hung. */
const extismCommandBound = 30000;

/**
 * Runs describe and compile with the Python extension, an extism-kernel-v1
 * WASM guest, as a real process of each CLI. The npm CLI runs the guest in a
 * Node worker thread. Each command must exit with its status within
 * `extismCommandBound`: before the fix the npm CLI reported
 * extension.cancelled and then never exited (morphir-ukvn.5.64.36.11).
 */
export function exerciseExtismWorker(cli: CliInvocation, workspace: string, label: string) {
  const artifact = pythonGuest(workspace);
  const directory = mkdtempSync(join(tmpdir(), `morphir-extism-worker-${label}-`));
  try {
    writeFileSync(join(directory, 'pin.json'), JSON.stringify({
      contractVersion: '0.2.0',
      artifact: { path: artifact, sha256: python.sha256 },
      runtime: { kind: 'wasm', abi: 'extism-kernel-v1' },
      origin: `finos/morphir-python extension/python/v${python.version}`,
    }));
    const fixture = join(workspace, 'apps/morphir/fixtures/extism-python/v1/acme');
    mkdirSync(join(directory, 'src/acme'), { recursive: true });
    for (const name of readdirSync(fixture)) copyFileSync(join(fixture, name), join(directory, 'src/acme', name));
    const env: NodeJS.ProcessEnv = { PATH: '/usr/bin:/bin', HOME: directory };
    if (label !== 'native') env.PATH = `${join(process.execPath, '..')}:/usr/bin:/bin`;
    const report = (args: string[], expected: number): Report => {
      const started = Date.now();
      const result = spawnSync(cli.command, [...cli.prefix, ...args, '--json'], {
        cwd: directory, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
        timeout: extismCommandBound, killSignal: 'SIGKILL',
      });
      const elapsed = Date.now() - started;
      assert.ok(result.signal === null && elapsed < extismCommandBound,
        `${label} ${JSON.stringify(args)} did not exit within ${extismCommandBound} ms (signal ${result.signal}):\n${result.stdout}\n${result.stderr}`);
      assert.equal(result.status, expected, `${label} ${JSON.stringify(args)}:\n${result.stdout}\n${result.stderr}`);
      return JSON.parse(result.stdout);
    };

    const described = report(['extension', 'describe', '--extension-pin', 'pin.json', '--timeout', '15000'], 0);
    assert.equal(described.state, 'succeeded');
    assert.equal(described.result!.worker.kind, 'wasm');
    assert.equal(described.result!.worker.runtime.abi, 'extism-kernel-v1');
    assert.deepEqual(described.result!.extension, { id: 'morphir-python', version: python.version });

    const compiled = report(['extension', 'compile', 'src', '--package', 'acme/rules', '--ir-version', '3',
      '--output', 'model', '--extension-pin', 'pin.json'], 0);
    assert.equal(compiled.state, 'succeeded');
    assert.equal(compiled.result!.lifecycle.shutdown, 'acknowledged');
    assert.equal(compiled.result!.lifecycle.workerStopped, true);
    assert.deepEqual(compiled.result!.output.files.map((file: { path: string }) => file.path), ['morphir-ir.json']);
    for (const file of compiled.result!.output.files) {
      assert.equal(file.sha256, sha256(join(directory, 'model', file.path)));
    }
    console.log(`Extism worker acceptance passed: ${label}`);
  } finally { rmSync(directory, { recursive: true, force: true }); }
}
