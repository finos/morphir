import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { headlessEnvironment } from './headless-environment.ts';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const target = process.argv[2] ?? 'js';
assert.ok(['js', 'native', 'wasm', 'wasm-gc'].includes(target));
const build = resolve(repo, process.env.MORPHIR_HEADLESS_BUILD ?? '.dev/build-model-cli');
const profile = process.env.MORPHIR_HEADLESS_PROFILE ?? 'debug';
const binary = process.env.MORPHIR_HEADLESS_BINARY ?? join(build, target, `${profile}/build/morphir/morphir`, target === 'native' ? 'morphir.exe' : target === 'js' ? 'morphir.js' : 'morphir.wasm');
const launcher = process.env.MORPHIR_HEADLESS_LAUNCHER ?? binary;
const runner = process.env.MORPHIR_HEADLESS_WASM_RUNNER ?? join(repo, 'pkgs/morphir-host/runners/wasm.mjs');
const prefix = target === 'native' ? [] : target === 'js' ? [launcher] : [runner, binary];
const root = mkdtempSync(join(tmpdir(), 'morphir-headless-models-'));
const env = headlessEnvironment(join(root, 'cli-environment'));
const fixtureRoot = join(repo, 'apps/morphir-workbench/fixtures/headless-parity/v1');
const corpus = JSON.parse(readFileSync(join(fixtureRoot, 'draft.29/cases.json'), 'utf8'));
const suffixes: Record<string, string> = { json: 'json', yaml: 'yaml', 'ion-text': 'ion', 'ion-binary': 'ionb' };
const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
function invoke(args: string[], status: number, input?: Uint8Array) {
  // WASI Preview 1 exposes only this fixture's preopened working directory.
  // The other runners also accept absolute paths; keep that coverage there.
  const selected = target === 'wasm' ? args.map(arg => isAbsolute(arg) ? relative(root, arg) : arg) : args;
  const result = spawnSync(target === 'native' ? binary : process.execPath, [...prefix, ...selected], {
    cwd: root, env,
    input, encoding: 'utf8', timeout: 30_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, status, `${args.join(' ')}\n${result.stderr}\n${result.stdout}`);
  return JSON.parse(result.stdout);
}
try {
  let controls = 0;
  for (const test of corpus.cases) {
    // This binding captures explicit file/stdin bytes. A connected semantic
    // projection is a different source contract, qualified by its owner lane.
    if (typeof test.input.source?.hex !== 'string') continue;
    const bytes = Buffer.from(test.input.source.hex, 'hex');
    const suffix = suffixes[test.input.format] ?? 'unknown';
    const name = `model-${controls}.${suffix}`;
    writeFileSync(join(root, name), bytes);
    const args = ['model', test.operation === 'inspect-model' ? 'inspect' : 'export-original', name, '--model-format', test.input.format, '--json'];
    if (test.operation === 'inspect-model') {
      const report = invoke(args, test.expected.status === 'ok' ? 0 : 2);
      if (test.expected.status === 'ok') {
        for (const key of ['irVersion', 'distribution', 'packageName', 'modules', 'normalizedIr']) {
          assert.deepEqual(report[key], test.expected.value[key], `${test.id} ${key}`);
        }
        assert.equal(report.representation, 'normalized-ir');
        assert.equal(report.originalKind, 'captured-file');
      } else assert.equal(report.code, test.expected.code, test.id);
    } else {
      const output = `saved-${controls}`;
      const report = invoke([...args, '--output', output], 0);
      const saved = readFileSync(join(root, output, 'originals', name));
      assert.deepEqual(saved, bytes, test.id);
      assert.equal(hash(saved), test.expected.value.sha256, test.id);
      assert.equal(report.files[0].byteLength, test.expected.value.byteLength);
      assert.equal(report.kind, 'original');
      invoke([...args, '--output', output], 2);
      assert.deepEqual(readFileSync(join(root, output, 'originals', name)), bytes);
      invoke([...args, '--output', output, '--overwrite'], 0);
      mkdirSync(join(root, output, '.morphir-publish.lock'));
      invoke([...args, '--output', output, '--overwrite'], 1);
      assert.deepEqual(readFileSync(join(root, output, 'originals', name)), bytes);
    }
    controls++;
  }
  const treeFixture = join(fixtureRoot, 'yaml/literal42-tree');
  const expected = JSON.parse(readFileSync(join(treeFixture, 'expectation.json'), 'utf8'));
  const tree = join(root, 'tree');
  for (const file of expected.files) {
    const bytes = readFileSync(join(treeFixture, file.path));
    assert.equal(hash(bytes), file.sha256, 'frozen input provenance');
    mkdirSync(join(tree, file.path, '..'), { recursive: true });
    writeFileSync(join(tree, file.path), bytes);
  }
  const sidecar = Buffer.from([0, 255, 13, 10, 0]);
  writeFileSync(join(tree, 'opaque.bin'), sidecar);
  mkdirSync(join(tree, 'empty/nested'), { recursive: true });
  const inspected = invoke(['model', 'inspect', tree, '--json'], 0);
  assert.deepEqual(JSON.parse(inspected.normalizedIr), expected.expectedNormalizedIr);
  assert.equal(inspected.originalKind, 'captured-inventory');
  const exported = invoke(['model', 'export-original', tree, '--output', 'tree-save', '--json'], 0);
  assert.deepEqual(readFileSync(join(root, 'tree-save/originals/opaque.bin')), sidecar);
  assert.ok(statSync(join(root, 'tree-save/originals/empty/nested')).isDirectory());
  assert.ok(exported.directories.includes('empty/nested'));
  for (const file of expected.files) {
    assert.equal(hash(readFileSync(join(root, 'tree-save/originals', file.path))), file.sha256);
  }
  // Separate controls: unrelated root documents cannot change model semantics,
  // and capture/export must preserve their bytes even when their stems match.
  const rootSidecars = new Map([
    ['notes.json', Buffer.from('{ "formatVersion": 999, "note": "independent JSON" }\r\n')],
    ['notes.yaml', Buffer.from('# independent YAML notes\r\nnotes: [unfinished λ\r\n')],
  ]);
  for (const [path, bytes] of rootSidecars) writeFileSync(join(tree, path), bytes);
  const withSidecars = invoke(['model', 'inspect', tree, '--json'], 0);
  assert.deepEqual(JSON.parse(withSidecars.normalizedIr), expected.expectedNormalizedIr);
  assert.equal(withSidecars.normalizedIr, inspected.normalizedIr);
  assert.equal(withSidecars.originalKind, 'captured-inventory');
  const sidecarExport = invoke(['model', 'export-original', tree, '--output', 'sidecar-save', '--json'], 0);
  for (const [path, bytes] of rootSidecars) {
    assert.deepEqual(readFileSync(join(root, 'sidecar-save/originals', path)), bytes);
    assert.ok(sidecarExport.files.some((file: { path: string; byteLength: number }) =>
      file.path === `sidecar-save/originals/${path}` && file.byteLength === bytes.length));
  }
  for (const file of expected.files) {
    assert.equal(hash(readFileSync(join(root, 'sidecar-save/originals', file.path))), file.sha256);
  }
  writeFileSync(join(root, 'calls.json'), JSON.stringify({ profile: 'morphir-invocations-v1', calls: [{ id: 'answer', entry: expected.entry, arguments: [] }] }));
  const evaluated = invoke(['eval', tree, '--suite', join(root, 'calls.json'), '--json'], target === 'wasm' ? 2 : 0);
  if (target === 'wasm') assert.equal(evaluated.error, 'eval.interruption_unavailable');
  else assert.deepEqual(evaluated.terminalOutcomes.calls[0].outcome, expected.expectedOutcome);
  const yaml = readFileSync(join(fixtureRoot, 'originals/model.yaml'));
  invoke(['model', 'export-original', '-', '--model-format', 'yaml', '--filename', 'stdin.yaml', '--output', 'stdin-save', '--json'], 0, yaml);
  assert.deepEqual(readFileSync(join(root, 'stdin-save/originals/stdin.yaml')), yaml);
  invoke(['model', 'export-original', '-', '--model-format', 'yaml', '--filename', '../escape', '--output', 'refused', '--json'], 2, yaml);
  assert.equal(existsSync(join(root, 'refused')), false);
  invoke(['model', 'export-original', tree, '--output', '../escape', '--json'], 2);
  symlinkSync(tree, join(root, 'linked-output'), process.platform === 'win32' ? 'junction' : 'dir');
  invoke(['model', 'export-original', tree, '--output', 'linked-output', '--json'], 2);
  symlinkSync(tree, join(tree, 'loop'), process.platform === 'win32' ? 'junction' : 'dir');
  invoke(['model', 'inspect', tree, '--json'], 2);
  console.log(`Headless ${target}: ${controls} frozen local-model cases, exact file/stdin/tree export, sidecars/empty directories, collision/failed replacement and confinement passed.`);
} finally {
  rmSync(root, { recursive: true, force: true });
}
