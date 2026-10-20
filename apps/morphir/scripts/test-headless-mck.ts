// Build explicit CLI/Workbench producers and delegate every verdict to the
// maintained shared MCK. This does not implement a compatibility checker.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sourceSnapshot } from './headless-source-snapshot.ts';
import { headlessEnvironment } from './headless-environment.ts';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const runner = process.env.MORPHIR_MCK_BIN;
assert.ok(runner, 'Set MORPHIR_MCK_BIN to the maintained parent Rust executable');
const build = resolve(repo, '.dev/headless-parity-build');
const evidence = resolve(repo, process.env.MORPHIR_WORKBENCH_EVIDENCE ?? '.dev/headless-parity-actual');
mkdirSync(evidence, { recursive: true });
const kit = join(repo, 'apps/morphir-workbench/fixtures/headless-parity/v1/draft.12');
const hash = (path: string) => createHash('sha256').update(readFileSync(path)).digest('hex');
function checked(program: string, args: string[], env = process.env) {
  const child = spawnSync(program, args, { cwd: repo, env, stdio: 'inherit', timeout: 180_000 });
  assert.equal(child.error, undefined);
  assert.equal(child.signal, null);
  assert.equal(child.status, 0, `${program} ${args.join(' ')}`);
}
const started = new Date().toISOString();
const before = sourceSnapshot(repo);
const runnerHash = hash(runner);
const kitHash = hash(join(kit, 'cases.json'));
checked('bun', ['build', '--check', '--target=node', '--tsconfig-override=tsconfig.node.json',
  `--outdir=${build}/adapter`, 'apps/morphir/scripts/headless-mck.ts']);
checked('moon', ['build', 'apps/morphir-workbench/mck/json-frame', '--target', 'js', '--target-dir', build]);
const framing = join(build, 'js/debug/build/finos/morphir-workbench/mck/json-frame/json-frame.js');
const adapter = join(build, 'adapter/headless-mck.js');
const lanes: { producer: string; target: string; artifact: string; artifactSha256: string; report: string; reportSha256: string }[] = [];
for (const target of ['js', 'native']) {
  checked('moon', ['build', 'apps/morphir', '--target', target, '--target-dir', build]);
  checked('moon', ['build', `apps/morphir-workbench/mck/capabilities/${target}`, '--target', target, '--target-dir', build]);
  const extension = target === 'js' ? '.js' : '.exe';
  const cli = join(build, `${target}/debug/build/morphir/morphir/morphir${extension}`);
  const workbench = join(build, `${target}/debug/build/finos/morphir-workbench/mck/capabilities/${target}/${target}${extension}`);
  for (const [producer, artifact] of [['primary-cli', cli], ['workbench-shared-policy', workbench]] as const) {
    const artifactHash = hash(artifact);
    const report = join(evidence, `${producer}-${target}-draft12.json`);
    const env = headlessEnvironment(join(evidence, `${producer}-${target}-environment`), {
      MORPHIR_HEADLESS_TARGET: target, MORPHIR_HEADLESS_CLI: cli, MORPHIR_WORKBENCH_MCK_JSON: framing,
    });
    const command = producer === 'primary-cli' ? [process.execPath, adapter] : target === 'js' ? [process.execPath, artifact] : [artifact];
    checked(runner, ['--no-banner', 'mck', 'workbench', 'run', '--kit', kit, '--report', report,
      '--adapter', command[0]!, ...command.slice(1).flatMap(arg => ['--adapter-arg', arg]),
      '--timeout', '35000', '--session-timeout', '180000'], env);
    checked(runner, ['--no-banner', 'mck', 'workbench', 'check', '--kit', kit, '--report', report], env);
    assert.equal(hash(artifact), artifactHash, 'Producer changed during qualification');
    lanes.push({ producer, target, artifact, artifactSha256: artifactHash, report, reportSha256: hash(report) });
  }
}
const after = sourceSnapshot(repo);
assert.equal(after.sha256, before.sha256, 'Source changed during build/qualification; rerun on the final source');
assert.equal(hash(runner), runnerHash, 'Shared runner changed during qualification');
assert.equal(hash(join(kit, 'cases.json')), kitHash, 'Independent corpus changed during qualification');
writeFileSync(join(evidence, 'provenance.json'), JSON.stringify({
  kind: 'actual-built-producer-qualification', profile: 'workbench/0.1.0-draft.12',
  operation: 'run-capability-policy', scope: 'nine fixed execute/JSON-argument cases; local scheme only',
  started, completed: new Date().toISOString(),
  gitHead: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repo, encoding: 'utf8' }).trim(),
  source: before, runner: { path: runner, sha256: runnerHash },
  kit: { path: kit, sha256: kitHash }, adapter: { path: adapter, sha256: hash(adapter) },
  framing: { path: framing, sha256: hash(framing) }, lanes,
  budgets: { frameBytes: 2097152, childOutputBytes: 2097152, childTimeoutMs: 30000, exchangeTimeoutMs: 35000, sessionTimeoutMs: 180000 },
}, null, 2) + '\n');
console.log('Actual built primary CLI and Workbench policy producers independently qualified on JS/native against nine frozen cases; source and artifact digests retained.');
