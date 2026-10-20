// Capture real application evidence and delegate qualification/rejection to the
// single maintained upstream MCK, including its local_models report validator.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sourceSnapshot } from './headless-source-snapshot.ts';
import { headlessEnvironment } from './headless-environment.ts';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const target = process.argv[2] ?? 'js'; assert.ok(['js', 'native'].includes(target));
const runner = process.env.MORPHIR_MCK_BIN;
assert.ok(runner, 'Set MORPHIR_MCK_BIN to the maintained upstream Rust executable');
const cliBuild = resolve(repo, process.env.MORPHIR_HEADLESS_BUILD ?? '.dev/build-model-cli');
const profile = process.env.MORPHIR_HEADLESS_PROFILE ?? 'debug';
const binary = resolve(process.env.MORPHIR_HEADLESS_BINARY ?? join(cliBuild, `${target}/${profile}/build/morphir/morphir/morphir${target === 'js' ? '.js' : '.exe'}`));
const launcher = resolve(process.env.MORPHIR_HEADLESS_LAUNCHER ?? binary);
const build = resolve(repo, process.env.MORPHIR_MODEL_MCK_BUILD ?? '.dev/headless-model-mck');
const evidence = resolve(repo, process.env.MORPHIR_MODEL_MCK_EVIDENCE ?? '.dev/headless-model-mck-evidence');
mkdirSync(evidence, { recursive: true });
const kit = join(repo, 'apps/morphir-workbench/fixtures/headless-parity/v1/draft.29');
const hash = (path: string) => createHash('sha256').update(readFileSync(path)).digest('hex');
const corpus = JSON.parse(readFileSync(join(kit, 'cases.json'), 'utf8')) as {
  formatVersion: string; cases: { id: string; input: { source: { hex: string } } }[];
};
assert.equal(corpus.formatVersion, '0.1.0-draft.29');
assert.equal(corpus.cases.length, 32);
assert.ok(corpus.cases.every(test => typeof test.input.source.hex === 'string'), 'This adapter qualifies only captured local model bytes');
function checked(program: string, args: string[], env = process.env, succeeds = true) {
  const child = spawnSync(program, args, { cwd: repo, env, encoding: 'utf8', timeout: 180_000, maxBuffer: 4 * 1024 * 1024 });
  assert.equal(child.error, undefined); assert.equal(child.signal, null);
  if (succeeds) assert.equal(child.status, 0, child.stderr + child.stdout);
  else assert.ok(child.status !== null && child.status !== 0, 'Shared checker accepted tampered/incomplete report');
  return { status: child.status, stdout: child.stdout, stderr: child.stderr };
}
const framing = resolve(process.env.MORPHIR_WORKBENCH_MCK_JSON ?? join(build, 'core/js/debug/build/finos/morphir-workbench/mck/json-frame/json-frame.js'));
const sourceBefore = sourceSnapshot(repo);
if (!process.env.MORPHIR_WORKBENCH_MCK_JSON)
  checked('moon', ['build', 'apps/morphir-workbench/mck/json-frame', '--target', 'js', '--target-dir', join(build, 'core')]);
checked('bun', ['build', '--check', '--target=node', '--tsconfig-override=tsconfig.node.json',
  `--outdir=${build}/adapter`, 'apps/morphir/scripts/headless-model-mck.ts']);
const adapter = join(build, 'adapter/headless-model-mck.js');
const sources = [binary, launcher, runner, framing, adapter, join(kit, 'cases.json'),
  join(repo, 'apps/morphir/scripts/headless-model-mck.ts'), join(repo, 'apps/morphir/scripts/test-headless-model-mck.ts')];
const before = [...new Set(sources)].map(path => ({ path, sha256: hash(path) }));
const started = new Date().toISOString();
const report = join(evidence, `primary-cli-${target}-draft29.json`);
const raw = join(evidence, `primary-cli-${target}-raw.jsonl`); writeFileSync(raw, '');
const env = headlessEnvironment(join(evidence, `${target}-environment`), {
  MORPHIR_HEADLESS_TARGET: target, MORPHIR_HEADLESS_BINARY: binary,
  MORPHIR_HEADLESS_LAUNCHER: launcher, MORPHIR_WORKBENCH_MCK_JSON: framing, MORPHIR_MODEL_MCK_RAW: raw,
});
const run = checked(runner, ['--no-banner', 'mck', 'workbench', 'run', '--kit', kit, '--report', report,
  '--adapter', process.execPath, '--adapter-arg', adapter, '--timeout', '35000', '--session-timeout', '180000'], env);
const accepted = checked(runner, ['--no-banner', 'mck', 'workbench', 'check', '--kit', kit, '--report', report], env);
interface RecordEvidence {
  caseId: string; observed?: { status: string; value?: Record<string, unknown> };
}
interface SavedReport { records: RecordEvidence[]; corpusHash: string; qualified: boolean }
const original = JSON.parse(readFileSync(report, 'utf8')) as SavedReport;
assert.equal(original.records.length, 32); assert.equal(original.qualified, true);
const refusals: { name: string; status: number | null; stdout: string; stderr: string }[] = [];
const mutations: [string, (value: SavedReport) => void][] = [
  ['tampered-normalized-ir', value => { value.records[0]!.observed!.value!.normalizedIr = '{}'; }],
  ['tampered-original-bytes', value => {
    const exported = value.records.find(record => record.observed?.value?.kind === 'original')!.observed!.value!;
    const hex = exported.hex as string; exported.hex = (hex.startsWith('00') ? 'ff' : '00') + hex.slice(2);
  }],
  ['missing-observation', value => { delete value.records[0]!.observed; }],
  ['incomplete-records', value => { value.records.pop(); }],
  ['wrong-corpus-digest', value => { value.corpusHash = '0'.repeat(64); }],
];
for (const [name, mutate] of mutations) {
  const altered = structuredClone(original); mutate(altered);
  const path = join(evidence, `${target}-${name}.json`); writeFileSync(path, JSON.stringify(altered) + '\n');
  refusals.push({ name, ...checked(runner, ['--no-banner', 'mck', 'workbench', 'check', '--kit', kit, '--report', path], env, false) });
}
// Author a source-bound positive boundary before observing the adapter. The
// existing JSON model plus trailing spaces is still the same valid model.
const boundaryBytes = Buffer.alloc(1024 * 1024, 32);
const fixedModel = Buffer.from(corpus.cases[0]!.input.source.hex, 'hex');
fixedModel.copy(boundaryBytes);
const boundaryKit = join(evidence, `source-boundary-${target}`);
mkdirSync(boundaryKit, { recursive: true });
const boundaryCorpus = {
  formatVersion: '0.1.0-draft.29', cases: [{
    id: 'one-mib-original', operation: 'export-model-original', format: 'json',
    input: { providerId: 'source-boundary', format: 'json', source: { hex: boundaryBytes.toString('hex') } },
    expected: { status: 'ok', value: { providerId: 'source-boundary', kind: 'original', format: 'json',
      hex: boundaryBytes.toString('hex'), byteLength: boundaryBytes.length,
      sha256: createHash('sha256').update(boundaryBytes).digest('hex') } },
  }],
};
writeFileSync(join(boundaryKit, 'cases.json'), JSON.stringify(boundaryCorpus) + '\n');
const boundaryReport = join(evidence, `${target}-source-boundary.json`);
checked(runner, ['--no-banner', 'mck', 'workbench', 'run', '--kit', boundaryKit, '--report', boundaryReport,
  '--adapter', process.execPath, '--adapter-arg', adapter, '--timeout', '35000', '--session-timeout', '180000'], env);
checked(runner, ['--no-banner', 'mck', 'workbench', 'check', '--kit', boundaryKit, '--report', boundaryReport], env);
const overflow = spawnSync(process.execPath, [adapter], { cwd: repo, env, encoding: 'utf8',
  input: ' '.repeat(3 * 1024 * 1024 + 1) + '\n', timeout: 30_000, maxBuffer: 4 * 1024 * 1024 });
assert.equal(overflow.error, undefined); assert.equal(overflow.signal, null); assert.equal(overflow.status, 1);
assert.match(overflow.stderr, /Oversize MCK frame/); assert.equal(overflow.stdout, '');
for (const file of before) assert.equal(hash(file.path), file.sha256, `${file.path} changed during qualification`);
const sourceAfter = sourceSnapshot(repo);
assert.equal(sourceAfter.sha256, sourceBefore.sha256, 'Source changed during build/qualification; rerun on the final source');
writeFileSync(join(evidence, `${target}-provenance.json`), JSON.stringify({
  kind: 'actual-cli-local-model-source-qualification', profile: 'workbench/0.1.0-draft.29',
  scope: '32 captured-source cases; inspect and exact original export; local offline profile only',
  started, completed: new Date().toISOString(), target,
  gitHead: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repo, encoding: 'utf8' }).trim(),
  source: sourceBefore,
  inputsAndTools: before, report: { path: report, sha256: hash(report) }, raw: { path: raw, sha256: hash(raw) },
  run, accepted, refusals,
  sourceBoundary: { sourceBytes: boundaryBytes.length, corpusSha256: hash(join(boundaryKit, 'cases.json')),
    reportSha256: hash(boundaryReport), oversizedFrameRefused: true },
  budgets: { frameBytes: 3145728, childOutputBytes: 3145728, childTimeoutMs: 30000, exchangeTimeoutMs: 35000, sessionTimeoutMs: 180000, maxOperations: 64 },
}, null, 2) + '\n');
console.log(`Model MCK ${target}: upstream checker qualified 32 actual inspect/export cases and rejected five tampered/incomplete reports.`);
