import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { exerciseJsonCommandCoverage } from './json-command-coverage.ts';

const repository = fileURLToPath(new URL('../../../', import.meta.url));
const binary = resolve(process.env.MORPHIR_HEADLESS_BINARY ?? join(repository, '_build/native/debug/build/finos/morphir/morphir.exe'));
const root = mkdtempSync(join(tmpdir(), 'morphir-embedded-compile-'));
const invoke = (args: string[], status = 0) => {
  const child = spawnSync(binary, args, { cwd: root, encoding: 'utf8', timeout: 30000,
    env: { ...process.env, HOME: join(root, 'home'), MORPHIR_HOME: join(root, 'morphir-home') } });
  assert.equal(child.status, status, `${JSON.stringify(args)}\n${child.stdout}\n${child.stderr}`);
  return { report: args.includes('--json') || args.includes('--json-lines') ? JSON.parse(child.stdout) : undefined, stdout: child.stdout, stderr: child.stderr };
};
try {
  exerciseJsonCommandCoverage((args, status = 0) => invoke(args, status));
  mkdirSync(join(root, 'boolean/src'), { recursive: true });
  writeFileSync(join(root, 'boolean/morphir.toml'), '[project]\nname="BooleanModel"\nmodule_prefix="App"\n');
  writeFileSync(join(root, 'boolean/src/Main.mbt'), 'pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }');
  const options = ['--language', 'moonbit', '--provider', 'finos/morphir-moonbit-frontend', '--profile', 'moonbit-model-stable-v1'];
  const compiled = invoke(['compile', 'boolean', ...options, '--json']).report;
  assert.equal(compiled.profile, 'morphir/command-result');
  assert.equal(compiled.command, 'compile');
  assert.equal(compiled.state, 'succeeded');
  assert.equal(compiled.result.frontends[0].provider, 'finos/morphir-moonbit-frontend');
  const artifact = compiled.result.artifactDetails[0];
  assert.equal(artifact.format, 'ion-binary');
  const model = join(root, 'boolean', artifact.path);
  assert.deepEqual([...readFileSync(model).subarray(0, 4)], [0xe0, 1, 0, 0xea]);
  assert.ok(existsSync(join(root, 'boolean/.morphir/logs/frontend.ionb')));
  const text = invoke(['compile', '--input', 'boolean/src/Main.mbt', ...options, '--file', '--package', 'acme/boolean', '--output', 'text-out', '--model-format', 'ion-text', '--json']).report;
  assert.equal(text.state, 'succeeded');
  invoke(['compile', 'boolean/src/Main.mbt', ...options, '--output', 'logged-out', '--log-file', join(root, 'compile.jsonl'), '--log-format', 'json-lines', '--json']);
  assert.ok(readFileSync(join(root, 'compile.jsonl'), 'utf8').trim().split('\n').every(line => JSON.parse(line)));
  const ion = readFileSync(join(root, 'boolean', text.result.artifactDetails[0].path), 'utf8');
  assert.match(ion, /morphir_moonbit_frontend/);
  assert.match(ion, /moonbit-parser-position-v1/);
  assert.match(ion, /acme/);
  assert.match(ion, /boolean/);
  const loss = invoke(['compile', 'boolean', ...options, '--output', 'loss-out', '--model-format', 'morphir-json', '--json'], 1);
  assert.equal(loss.report.state, 'failed');
  assert.equal(loss.report.result, undefined);
  assert.match(loss.stderr, /loss|metadata/i);
  assert.equal(existsSync(join(root, 'boolean/loss-out')), false);
  for (const extra of [['--types-only'], ['--version', '3'], ['--provider', 'unknown']]) {
    // Replace the provider control instead of repeating a single-valued option.
    const selected = extra[0] === '--provider' ? ['--language', 'moonbit'] : options;
    const failure = invoke(['compile', 'boolean', ...selected, ...extra, '--output', 'refused', '--json'], 1).report;
    assert.equal(failure.state, 'failed');
    assert.equal(failure.result, undefined);
    assert.equal(existsSync(join(root, 'boolean/refused')), false);
  }
  writeFileSync(join(root, 'boolean/src/Broken.mbt'), 'pub fn broken(');
  // File selection excludes the invalid sibling.
  assert.equal(invoke(['compile', 'boolean/src/Main.mbt', ...options, '--output', 'selected', '--json']).report.state, 'succeeded');
  const broken = invoke(['compile', 'boolean', ...options, '--output', 'broken-out', '--json'], 1);
  assert.equal(broken.report.state, 'failed');
  assert.match(broken.stderr, /Broken.mbt.*frontend/);
  assert.equal(existsSync(join(root, 'boolean/broken-out')), false);
  assert.deepEqual(readFileSync(model).subarray(0, 4), Buffer.from([0xe0, 1, 0, 0xea]));

  cpSync(join(repository, 'pkgs/morphir-elm/conformance/projects/modules'), join(root, 'elm'), { recursive: true });
  const elmOptions = ['--language', 'elm', '--provider', 'finos/morphir-elm'];
  const elm = invoke(['compile', 'elm', ...elmOptions, '--json']).report;
  assert.equal(elm.state, 'succeeded');
  assert.equal(elm.result.frontends[0].profile, 'library-origins');
  assert.equal(elm.result.frontends[0].provider, 'finos/morphir-elm');
  const elmJson = invoke(['compile', 'elm', ...elmOptions, '--profile', 'library', '--model-format', 'morphir-json', '--output', 'json-out', '--version', '4', '--json']).report;
  assert.equal(elmJson.state, 'succeeded');
  const json = JSON.parse(readFileSync(join(root, 'elm', elmJson.result.artifactDetails[0].path), 'utf8'));
  assert.equal(json.formatVersion, 4);
  // Existing run retains its success schema and provider defaults.
  const existing = invoke(['run', 'elm', '--json']).report;
  assert.equal(existing.successful, true);
  assert.equal(existing.profile, undefined);
  const generated = invoke(['generate', model, '--output', 'generated', '--target', 'moonbit', '--json']).report;
  assert.equal(generated.successful, true);
  mkdirSync(join(root, 'workspace'));
  writeFileSync(join(root, 'workspace/morphir.toml'), '[workspace]\nmembers=["one","two"]\n');
  for (const [name, content] of [['one', 'pub fn ready() -> Bool { true }'], ['two', 'pub fn broken(']] as const) {
    mkdirSync(join(root, `workspace/${name}/src`), { recursive: true });
    writeFileSync(join(root, `workspace/${name}/morphir.toml`), `[project]\nname="${name === 'one' ? 'Core' : 'Other'}"\n`);
    writeFileSync(join(root, `workspace/${name}/src/Main.mbt`), content);
  }
  const selected = invoke(['compile', 'workspace', '--project', 'Core', '--package', 'acme/selected', '--model-format', 'ion-text', ...options, '--json']).report;
  assert.equal(selected.state, 'succeeded');
  assert.equal(selected.result.frontends.length, 1);
  assert.match(selected.result.frontends[0].source, /one\/src\/Main.mbt/);
  const selectedModel = readFileSync(join(root, 'workspace', selected.result.artifactDetails[0].path), 'utf8');
  assert.match(selectedModel, /acme/);
  assert.match(selectedModel, /selected/);
  mkdirSync(join(root, 'empty/src'), { recursive: true });
  writeFileSync(join(root, 'empty/morphir.toml'), '[project]\nname="empty"\n');
  const empty = invoke(['compile', 'empty', ...options, '--json'], 1);
  assert.match(empty.report.error.message, /compile.no_sources/);
  assert.equal(existsSync(join(root, 'empty/.morphir/out')), false);
  writeFileSync(join(root, 'workspace/one/morphir.toml'), '[project]\nname="one"\n[ir]\nformat_version=3\n');
  assert.equal(invoke(['compile', 'workspace', '--project', 'one', ...options, '--version', '4.0.0', '--json']).report.state, 'succeeded');
  console.log('embedded compile acceptance passed: Boolean/Elm, file selection, exact retained model, origins, checked JSON, refusals, diagnostics, run/generate compatibility');
} finally { rmSync(root, { recursive: true, force: true }); }
