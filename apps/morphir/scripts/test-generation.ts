import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { once } from 'node:events';
import { runInNewContext } from 'node:vm';
import { includeDependencyPath } from '../build-provider/paths.mts';
import { headlessEnvironment } from './headless-environment.ts';

interface Report {
  operation: string; successful: boolean; unitId: string; committed: string[];
  projects: { id: string; root: string }[];
  artifactDetails: { path: string; source: string; encoding: string }[];
  validated: { target: string; receipt: string }[];
  diagnostics: { code?: string; path: string; message: string }[];
  publicationError: string | null;
}
const repo = fileURLToPath(new URL('../../../', import.meta.url));
const target = process.argv[2] ?? 'js';
assert.ok(['js', 'native', 'wasm', 'wasm-gc'].includes(target));
const build = resolve(repo, process.env.MORPHIR_GENERATION_BUILD ?? process.env.MORPHIR_HEADLESS_BUILD ?? '.dev/generation-build');
const profile = process.env.MORPHIR_GENERATION_PROFILE ?? process.env.MORPHIR_HEADLESS_PROFILE ?? 'debug';
const cli = resolve(process.env.MORPHIR_GENERATION_BINARY ?? process.env.MORPHIR_HEADLESS_BINARY ?? join(build, `${target}/${profile}/build/morphir/morphir/morphir${target === 'js' ? '.js' : target === 'native' ? '.exe' : '.wasm'}`));
const cliDigest = createHash('sha256').update(readFileSync(cli)).digest('hex');
const runner = resolve(process.env.MORPHIR_GENERATION_LAUNCHER ?? process.env.MORPHIR_HEADLESS_LAUNCHER ??
  (target === 'js' || target === 'native' ? cli : join(repo, 'pkgs/morphir-host/runners/wasm.mjs')));
const launcherDigest = createHash('sha256').update(readFileSync(runner)).digest('hex');
const fixtures = join(repo, 'apps/morphir/fixtures/generation/v1');
const expected = JSON.parse(readFileSync(join(fixtures, 'expected.json'), 'utf8')) as { moduleName: string; expectedResult: string; checkpointUnitId: string; mepUnitId: string };
const root = mkdtempSync(join(tmpdir(), 'morphir-generation-'));
// The maintained process provider verifies this workspace's corrected compiler
// core. It is an explicit toolchain fixture, separate from CLI configuration.
const env = headlessEnvironment(root, { MOON_CORE_OVERRIDE: process.env.MOON_CORE_OVERRIDE });
if (target === 'wasm' || target === 'wasm-gc') {
  try {
    const run = (args: string[], status: number) => {
      const child = spawnSync(process.execPath, [runner, cli, 'generate', ...args], {
        cwd: root, env, encoding: 'utf8', timeout: 30_000, maxBuffer: 1024 * 1024,
      });
      assert.equal(child.error, undefined); assert.equal(child.signal, null);
      assert.equal(child.status, status, child.stderr + child.stdout);
      return child;
    };
    assert.match(run(['--help'], 0).stdout, /generate/);
    mkdirSync(join(root, 'out')); writeFileSync(join(root, 'out/sentinel'), 'unchanged');
    for (const model of ['model.json', 'checkpoint.ion']) {
      const refused = JSON.parse(run([join(fixtures, model), '--output', 'out', '--json'], 2).stdout) as { error: string; committed: unknown[] };
      assert.match(refused.error, target === 'wasm' ? /generate.host_unavailable/ : /observability.clock_capability_required/);
      assert.deepEqual(refused.committed, []);
      assert.deepEqual(readdirSync(join(root, 'out')), ['sentinel']);
      assert.equal(readFileSync(join(root, 'out/sentinel'), 'utf8'), 'unchanged');
    }
    const evidence = resolve(process.env.MORPHIR_GENERATION_EVIDENCE ?? join(repo, '.dev/generation-evidence')); mkdirSync(evidence, { recursive: true });
    writeFileSync(join(evidence, `${target}-report.json`), JSON.stringify({
      fixtureVersion: '1.0.0', target, help: true, generationSupported: false, unchangedOnRefusal: true,
      refusal: target === 'wasm' ? 'generate.host_unavailable' : 'observability.clock_capability_required',
      cliSha256: cliDigest, launcher: runner, launcherSha256: launcherDigest,
    }, null, 2) + '\n');
    console.log(`Generation ${target}: help and explicit effect refusal before publication passed.`);
  } finally { rmSync(root, { recursive: true, force: true }); }
  process.exit(0);
}
const core: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; morphirGenerationFixture?: (source: string) => string } = { TextEncoder, TextDecoder };
const verifier = resolve(process.env.MORPHIR_GENERATION_VERIFIER ?? join(build, `js/${profile}/build/finos/morphir-engine/acceptance/retained-generation/retained-generation.js`));
const verifierDigest = createHash('sha256').update(readFileSync(verifier)).digest('hex');
runInNewContext(readFileSync(verifier, 'utf8'), core);
assert.ok(core.morphirGenerationFixture);
const fixture = (request: unknown): unknown => JSON.parse(core.morphirGenerationFixture!(JSON.stringify(request)));
const digest = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
const evidence = resolve(process.env.MORPHIR_GENERATION_EVIDENCE ?? join(repo, '.dev/generation-evidence')); mkdirSync(evidence, { recursive: true });
const reports: { name: string; report: Report }[] = [];
let blockedStdinSigint: { status: 'passed'; exitStatus: 130; noPublication: true; noLogs: true } |
  { status: 'not-run'; reason: string } = {
    status: 'not-run', reason: 'Windows requires a real console control-event harness; process.kill(SIGINT) terminates the process',
  };
function invoke(args: string[], status = 0, input?: string, cwd = root) {
  const child = spawnSync(target === 'native' ? cli : process.execPath,
    [...(target === 'js' ? [runner] : []), 'generate', ...args], {
    cwd, env, encoding: 'utf8', input, timeout: 150_000, maxBuffer: 8 * 1024 * 1024,
  });
  assert.equal(child.error, undefined);
  assert.equal(child.signal, null);
  assert.equal(child.status, status, `${args.join(' ')}\n${child.stderr}\n${child.stdout}`);
  return child;
}
function run(name: string, args: string[], status = 0) {
  const child = invoke([...args, '--json'], status);
  assert.equal(/warning: observability (sink unavailable|dropped)/.test(child.stderr), false,
    `${name}: shared logging sink failed despite a completed generation command`);
  const report = JSON.parse(child.stdout) as Report;
  reports.push({ name, report });
  return report;
}
function snapshot(directory: string): [string, string][] {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? snapshot(join(directory, entry.name)).map(([path, hash]): [string, string] => [entry.name + '/' + path, hash])
    : [[entry.name, digest(readFileSync(join(directory, entry.name)))]] as [string, string][]).sort();
}
function retainEvidence(sidecars: Map<string, Buffer>, qualification: Record<string, unknown>) {
  assert.equal(digest(readFileSync(cli)), cliDigest, 'CLI artifact changed during qualification');
  assert.equal(digest(readFileSync(runner)), launcherDigest, 'Launcher changed during qualification');
  assert.equal(digest(readFileSync(verifier)), verifierDigest, 'Sidecar verifier changed during qualification');
  writeFileSync(join(evidence, `${target}-report.json`), JSON.stringify({
    fixtureVersion: '1.0.0', target, cliSha256: cliDigest,
    launcher: runner, launcherSha256: launcherDigest, verifier, verifierSha256: verifierDigest, expected, reports,
    fixtureDigests: ['expected.json', 'model.json', 'model.yaml', 'checkpoint.ion', 'mep.ion'].map(name => ({ name, sha256: digest(readFileSync(join(fixtures, name))) })),
    blockedStdinSigint, unchangedOnRefusal: true,
    logging: { defaultIonPerSource: true, rotations: 3, explicitUnicodeJsonLines: true,
      stderrJsonLines: true, explicitSinkPreservesDefault: true, directoryRefusalPreservesResult: true,
      directoryLinkRefusalPreservesTarget: true },
    sidecarDigests: [...sidecars].map(([name, bytes]) => ({ name, sha256: digest(bytes) })),
    ...qualification,
  }, null, 2) + '\n');
}
try {
  if (process.platform !== 'win32') {
  // Hold stdin open so SIGINT arrives during capture, before parsing, logging
  // or publication. Bare JS artifacts need the production owned worker host.
  let interruptLauncher = runner;
  if (target === 'js' && runner === cli) {
    interruptLauncher = join(root, 'interrupt-launcher.mjs');
    writeFileSync(interruptLauncher,
      `import {terminalWorker} from ${JSON.stringify(pathToFileURL(join(repo, 'pkgs/morphir-host/runners/terminal-worker.mjs')).href)};\n` +
      `if (!terminalWorker(new URL(import.meta.url),process.argv.slice(2))) await import(${JSON.stringify(pathToFileURL(cli).href)});\n`);
  }
  const blocked = spawn(target === 'native' ? cli : process.execPath,
    [...(target === 'js' ? [interruptLauncher] : []), 'generate', '-', '--model-format', 'json', '--output', 'cancelled-stdin', '--json'],
    { cwd: root, env, stdio: ['pipe', 'pipe', 'pipe'] });
  let blockedOut = '', blockedError = '';
  blocked.stdout.on('data', bytes => { blockedOut += bytes; if (blockedOut.length > 65536) blocked.kill('SIGKILL'); });
  blocked.stderr.on('data', bytes => { blockedError += bytes; if (blockedError.length > 65536) blocked.kill('SIGKILL'); });
  const guard = setTimeout(() => blocked.kill('SIGKILL'), 10_000);
  try {
    const closed = once(blocked, 'close');
    // Exceed pipe capacity while remaining below the model byte limit. Drain
    // proves the child is consuming stdin, avoiding a race with native startup.
    if (!blocked.stdin.write(Buffer.alloc(1024 * 1024, 32))) await once(blocked.stdin, 'drain');
    blocked.kill('SIGINT');
    const [code, signal] = await closed;
    assert.equal(signal, null, blockedError);
    assert.equal(code, 130, blockedOut + blockedError);
    const cancelled = JSON.parse(blockedOut) as { successful: boolean; error: string; committed: unknown[] };
    assert.equal(cancelled.successful, false); assert.equal(cancelled.error, 'Cancelled');
    assert.deepEqual(cancelled.committed, []);
    assert.equal(existsSync(join(root, 'cancelled-stdin')), false);
    assert.equal(existsSync(join(root, '.morphir/logs')), false);
    blockedStdinSigint = { status: 'passed', exitStatus: 130, noPublication: true, noLogs: true };
  } finally {
    clearTimeout(guard);
    if (blocked.exitCode === null && blocked.signalCode === null) { blocked.kill('SIGKILL'); await once(blocked, 'close'); }
    blocked.stdin.destroy();
  }
  }
  for (const name of ['checkpoint', 'mep']) {
    const source = readFileSync(join(fixtures, name + '.ion'), 'utf8');
    const bytes = fixture({ op: 'binary', source }) as number[];
    writeFileSync(join(root, name + '.ionb'), Buffer.from(bytes));
  }
  const variants = [
    ['json', join(fixtures, 'model.json'), 'workbench'], ['yaml', join(fixtures, 'model.yaml'), 'workbench'],
    ['checkpoint-text', join(fixtures, 'checkpoint.ion'), expected.checkpointUnitId], ['checkpoint-binary', join(root, 'checkpoint.ionb'), expected.checkpointUnitId],
    ['mep-text', join(fixtures, 'mep.ion'), expected.mepUnitId], ['mep-binary', join(root, 'mep.ionb'), expected.mepUnitId],
  ] as const;
  const sidecars = new Map<string, Buffer>();
  const defaultLog = join(root, '.morphir/logs/execution.ionb');
  const previousLogs: Buffer[] = [];
  for (const [name, model, identity] of variants) {
    const out = 'out-' + name;
    const report = run(name, [model, '--output', out]);
    assert.equal(report.operation, 'generate'); assert.equal(report.successful, true);
    assert.equal(report.unitId, identity); assert.equal(report.projects[0]?.id, expected.moduleName);
    assert.equal(report.validated.length, 0);
    assert.ok(report.artifactDetails.every(a => a.source === model));
    // Every source must flush a fresh Ion batch and retain exactly three older
    // batches. Checking only after all sources hid a missing native sink.
    assert.ok(existsSync(defaultLog), `${name}: default execution log is missing`);
    const log = readFileSync(defaultLog);
    assert.ok(log.length > 4);
    assert.deepEqual([...log.subarray(0, 4)], [224, 1, 0, 234]);
    for (let i = 0; i < Math.min(previousLogs.length, 3); i++) {
      assert.deepEqual(readFileSync(defaultLog + '.' + (i + 1)), previousLogs[i]);
    }
    assert.equal(existsSync(defaultLog + '.4'), false);
    previousLogs.unshift(log);
    const sidecar = readFileSync(join(root, out, 'compile.dest/model/symbols.10n'));
    assert.deepEqual([...sidecar.subarray(0, 4)], [224, 1, 0, 234]);
    sidecars.set(name, sidecar);
    if (name.startsWith('checkpoint') || name.startsWith('mep')) {
      const source = readFileSync(join(fixtures, name.startsWith('mep') ? 'mep.ion' : 'checkpoint.ion'), 'utf8');
      const checked = fixture({ op: 'inspect', source, bytes: [...sidecar] }) as { preservedSourceContext: boolean; unitId: string };
      assert.equal(checked.preservedSourceContext, true);
      assert.equal(checked.unitId, JSON.stringify(identity));
    }
    writeFileSync(join(evidence, `${target}-${name}-symbols.ionb`), sidecar);
  }
  assert.deepEqual(sidecars.get('checkpoint-text'), sidecars.get('checkpoint-binary'));
  assert.deepEqual(sidecars.get('mep-text'), sidecars.get('mep-binary'));
  assert.deepEqual(sidecars.get('json'), sidecars.get('yaml'));
  assert.ok(readFileSync(defaultLog).length > 4);
  const logDirectory = join(root, 'logs with spaces-\u65e5\u672c'); mkdirSync(logDirectory);
  const explicitLog = join(logDirectory, 'generate.jsonl');
  const logged = invoke([join(fixtures, 'model.json'), '--output', 'logged', '--log-file', explicitLog, '--log-format', 'json-lines', '--json']);
  assert.equal(/warning: observability/.test(logged.stderr), false, 'Explicit JSONL sink failed');
  const explicitRecords = readFileSync(explicitLog, 'utf8').trim().split('\n').map(line => JSON.parse(line));
  assert.ok(explicitRecords.length > 0);
  const stderrLog = invoke([join(fixtures, 'model.json'), '--output', 'stderr-logged', '--log-file', '@stderr', '--log-format', 'json-lines', '--json']);
  assert.equal((JSON.parse(stderrLog.stdout) as Report).successful, true);
  assert.ok(stderrLog.stderr.trim().split('\n').map(line => JSON.parse(line)).length > 0);
  assert.deepEqual(readFileSync(defaultLog), previousLogs[0], 'Explicit sinks changed the default log');
  const blockedLogs = join(root, 'blocked-logs'); mkdirSync(blockedLogs);
  writeFileSync(join(blockedLogs, '.morphir'), 'keep');
  const unavailableLog = invoke([join(fixtures, 'model.json'), '--output', 'generated', '--json'], 0, undefined, blockedLogs);
  assert.equal((JSON.parse(unavailableLog.stdout) as Report).successful, true);
  assert.match(unavailableLog.stderr, /warning: observability sink unavailable/);
  assert.equal(readFileSync(join(blockedLogs, '.morphir'), 'utf8'), 'keep');
  const linkedLogs = join(root, 'linked-logs'), externalLogs = join(root, 'external-logs');
  mkdirSync(linkedLogs); mkdirSync(externalLogs);
  // Junctions exercise Windows reparse-point refusal without symlink privilege.
  symlinkSync(externalLogs, join(linkedLogs, '.morphir'), process.platform === 'win32' ? 'junction' : 'dir');
  const linkedLog = invoke([join(fixtures, 'model.json'), '--output', 'generated', '--json'], 0, undefined, linkedLogs);
  assert.equal((JSON.parse(linkedLog.stdout) as Report).successful, true);
  assert.match(linkedLog.stderr, /warning: observability sink unavailable/);
  assert.deepEqual(readdirSync(externalLogs), [], 'Refused log directory link changed its target');
  const model = join(fixtures, 'model.json'), rich = join(fixtures, 'checkpoint.ion');
  const renamed = run('explicit-semantic-identity', [model, '--unit-id', 'provided:identity', '--output', 'explicit-id']);
  assert.equal(renamed.unitId, 'provided:identity');
  const retained = run('retained-envelope-identity', [rich, '--unit-id', 'provided:identity', '--output', 'retained-id']);
  assert.equal(retained.unitId, expected.checkpointUnitId);
  const out = join(root, 'out-checkpoint-text');
  const before = snapshot(out);
  for (const [args, code] of [
    [[rich, '--target', 'elm'], 'data.lossy_conversion'],
    [[rich, '--target', 'unknown'], 'generation.unsupported_target'],
    [[rich, '--model-format', 'unknown'], 'data.unknown_codec'],
    [[rich, '--backend-option', 'ignored=true'], 'generate.unsupported_option'],
    [[rich, '--backend-option', 'naming="readable"', '--backend-option', 'naming="legacy-hex"'], 'generate.duplicate_option'],
    [[rich, '--validation', 'required', '--build-target', 'unsupported'], 'build.unsupported_target'],
  ] as [string[], string][]) {
    const refused = JSON.parse(invoke([...args, '--output', out, '--json'], 2).stdout) as { error: string; committed: unknown[] };
    assert.ok(refused.error.includes(code), refused.error);
    assert.deepEqual(refused.committed, []);
    assert.deepEqual(snapshot(out), before, 'Refusal changed existing publication');
  }
  const missing = run('required-provider-missing', [rich, '--output', out, '--validation', 'required'], 1);
  assert.match(missing.publicationError ?? '', /build.provider_required/);
  assert.deepEqual(missing.committed, []); assert.deepEqual(snapshot(out), before);
  if (target === 'native' && process.platform === 'win32') {
    const refused = JSON.parse(invoke([rich, '--output', out, '--validation', 'required', '--build-target', 'js',
      '--build-provider', 'process', '--build-node', process.execPath,
      '--build-helper', resolve(process.env.MORPHIR_GENERATION_HELPER ?? join(repo, 'apps/morphir/build-provider/library-build.mjs')),
      '--home', process.env.MOON_HOME ?? repo, '--sdk', join(repo, 'pkgs/morphir-sdk'), '--json'], 2).stdout) as { error: string; committed: unknown[] };
    assert.match(refused.error, /build.provider_required/); assert.deepEqual(refused.committed, []);
    assert.deepEqual(snapshot(out), before, 'Unsupported native process replaced existing artifacts');
    const stdin = JSON.parse(invoke(['-', '--model-format', 'json', '--output', 'stdin', '--json'], 0, readFileSync(model, 'utf8')).stdout) as Report;
    assert.equal(stdin.successful, true);
    writeFileSync(join(root, 'cancel'), 'cancel');
    invoke([rich, '--output', out, '--cancel-file', join(root, 'cancel'), '--json'], 130);
    assert.deepEqual(snapshot(out), before);
    retainEvidence(sidecars, {
      generationSupported: true, sourceOnly: true,
      buildUnsupported: { code: 'build.provider_required', reason: 'Native Windows process/temp adapter is unavailable; use Node' },
      consumer: { status: 'not-run', reason: 'Required native process provider is unavailable' },
    });
    console.log('Generation native Windows: six source-only inputs, sidecars/logs, stdin, cancellation file and unchanged-on-process-refusal passed; console SIGINT and required-build consumer remain unqualified.');
  } else {
  const elmReport = run('elm', [model, '--target', 'elm', '--output', 'elm']);
  assert.equal(elmReport.successful, true);
  const elmRoot = join(root, 'elm/compile.dest/model');
  assert.match(readFileSync(join(elmRoot, 'src/Generated/Main.elm'), 'utf8'), /answer/);
  const elm = process.platform === 'win32' ? join(repo, 'pkgs/morphir-elm/scripts/node_modules/@elm_binaries/win32_x64/elm.exe') : join(repo, 'pkgs/morphir-elm/scripts/node_modules/.bin/elm');
  const elmBuilt = spawnSync(elm, ['make', 'src/Generated/Main.elm', '--output=' + (process.platform === 'win32' ? 'NUL' : '/dev/null'), '--report=json'], {
    cwd: elmRoot, env: { ...env, ELM_HOME: process.env.ELM_HOME ?? join(homedir(), '.elm') }, encoding: 'utf8', timeout: 120_000,
  });
  assert.equal(elmBuilt.error, undefined); assert.equal(elmBuilt.status, 0, elmBuilt.stderr);
  const home = process.env.MOON_HOME ?? execFileSync('mise', ['where', 'http:moonbit'], { cwd: repo, encoding: 'utf8' }).trim();
  const helper = resolve(process.env.MORPHIR_GENERATION_HELPER ?? join(repo, 'apps/morphir/build-provider/library-build.mjs'));
  const buildArgs = [rich, '--output', out, '--validation', 'required', '--build-target', 'js', '--build-provider', 'process', '--build-helper', helper, '--build-node', process.execPath, '--home', home, '--sdk', join(repo, 'pkgs/morphir-sdk')];
  const required = run('required-build', buildArgs);
  assert.equal(required.successful, true); assert.equal(required.validated.length, 1);
  assert.ok(existsSync(join(out, 'compile.dest/model/build-receipt.ionb')));
  const builtSnapshot = snapshot(out);
  const failingBuild = buildArgs.slice(); failingBuild[failingBuild.indexOf('--sdk') + 1] = join(root, 'absent-sdk');
  run('required-build-fails', failingBuild, 1);
  assert.deepEqual(snapshot(out), builtSnapshot, 'Failed compiler replaced existing artifacts');
  const consumer = join(root, 'consumer'); mkdirSync(consumer);
  const excluded = new Set(['_build', '.mooncakes', '.git', 'node_modules']);
  cpSync(join(repo, 'pkgs/morphir-sdk'), join(root, 'sdk'), { recursive: true, filter: path => includeDependencyPath(join(repo, 'pkgs/morphir-sdk'), path, excluded) });
  cpSync(join(out, 'compile.dest/model'), join(root, 'generated'), { recursive: true });
  writeFileSync(join(root, 'moon.work'), 'members=["./generated","./sdk","./consumer"]\n');
  writeFileSync(join(consumer, 'moon.mod'), `name="generation-consumer"\nversion="0.1.0"\nimport { "${expected.moduleName}@0.0.0", "finos/morphir-sdk@0.1.0" }\n`);
  writeFileSync(join(consumer, 'moon.pkg'), `pkgtype(kind: "executable")\nimport { "${expected.moduleName}" @model, "finos/morphir-sdk/integer" }\n`);
  writeFileSync(join(consumer, 'main.mbt'), 'fn main raise { println(@integer.to_string(@model.answer())) }\n');
  const invoked = spawnSync(join(home, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon'), ['run', 'consumer', '--target', target], {
    cwd: root, env: { ...env, MOON_HOME: home }, encoding: 'utf8', timeout: 120_000, maxBuffer: 8 * 1024 * 1024,
  });
  assert.equal(invoked.error, undefined); assert.equal(invoked.status, 0, invoked.stderr);
  assert.equal(invoked.stdout.trim(), expected.expectedResult);
  const stdin = JSON.parse(invoke(['-', '--model-format', 'json', '--output', 'stdin', '--json'], 0, readFileSync(model, 'utf8')).stdout) as Report;
  assert.equal(stdin.successful, true);
  writeFileSync(join(root, 'cancel'), 'cancel');
  invoke([rich, '--output', out, '--cancel-file', join(root, 'cancel'), '--json'], 130);
  assert.deepEqual(snapshot(out), builtSnapshot);
  retainEvidence(sidecars, {
    generationSupported: true, sourceOnly: true, requiredBuild: true,
    consumerResult: invoked.stdout.trim(), elmCompiled: true,
  });
  console.log(`Generation ${target}: six model inputs, retained sidecars, Elm compiler, required MoonBit build, consumer ${expected.expectedResult}, cancellation and unchanged-on-refusal passed.`);
  }
} finally { rmSync(root, { recursive: true, force: true }); }
