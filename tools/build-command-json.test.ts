import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { appendFileSync, closeSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, openSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// The compiled fixture is portable TypeScript, with no shell or historical-source
// dependency. It journals the actual child argv/cwd/environment and publishes
// bounded data only for the decoder boundaries that these wrappers already own.
if (process.env.MORPHIR_BUILD_JSON_STUB === '1') {
  const args = process.argv.slice(2);
  const program = basename(process.execPath).replace(/\.exe$/, '');
  const journal = process.env.MORPHIR_BUILD_JSON_JOURNAL!;
  appendFileSync(journal, JSON.stringify({ program, executable: process.execPath, path: process.env.PATH, args, cwd: process.cwd(), marker: process.env.MORPHIR_BUILD_JSON_MARKER }) + '\n');
  const code = Number(process.env.MORPHIR_BUILD_JSON_CHILD_EXIT ?? '0');
  if (code) { process.stdout.write('child stdout\n'); process.stderr.write('child stderr\n'); process.exit(code); }
  if (process.env.MORPHIR_BUILD_JSON_TYPED_REFUSAL && program === 'moonc') {
    console.log('v0.10.18+6c83a7f62');
  } else if (process.env.MORPHIR_BUILD_JSON_TYPED_REFUSAL && program === 'git') {
    if (args[0] !== 'status') console.log('642fd13ea74bc46c3f5344844c9cca4ffbae368a');
  } else if (process.env.MORPHIR_BUILD_JSON_TYPED_REFUSAL && args.includes('pkgs/morphir-moonbit-frontend/typed-acceptance')) {
    console.log('{"models":null}');
  } else if (program === 'moon' && args.includes('scripts/moonbit-core.mbtx')) {
    console.log(process.cwd());
  } else if (program === 'moon' && args.includes('pkgs/morphir-host/assembly/qualification')) {
    console.log('{"generated":true}');
  } else if (program === 'moon' && args.includes('tree')) {
    console.log('{"packages":[]}');
  } else if (program === 'node' && args[0] === 'pkgs/morphir-host/embedding/test/generated.mts') {
    writeFileSync(join(args[1]!, 'report.json'), process.env.MORPHIR_BUILD_JSON_BAD_RECEIPT ? '{bad' : '{"profile":"fixture-assembly","variants":["saved","fresh"]}\n');
    console.log('child stdout');
  } else if (program === 'morphir-elm') {
    writeFileSync(args[args.indexOf('-o') + 1]!, '{ "fixture": true }\n');
    console.log('child stdout');
  } else { console.log('child stdout'); }
  process.stderr.write('child stderr\n');
  process.exit(0);
}

const root = fileURLToPath(new URL('../', import.meta.url));
const names = [
  'assembly-check', 'conformance-check', 'elm-elm-check', 'elm-make-check', 'elm-moonbit-check',
  'elm-parity-refresh', 'installed-lifecycle-check', 'installed-provider-check', 'moonbit-frontend-check',
  'native-telemetry-check', 'scheme-docs-check', 'scheme-docs-generate', 'scheme-elm-check',
  'scheme-moonbit-check', 'sdk-spec-check', 'sdk-spec-generate', 'typed-source-check', 'workbench-samples',
] as const;
type Name = typeof names[number];
type Invocation = { name: Name; args: string[]; exitCode: number | null; signal: string | number | null; stdout: string; stdoutHex: string; stderr: string; stderrHex: string; capture: 'pipe' | 'file'; command: string[]; cwd: string; timedOut: boolean; journalText: string; elapsedMs: number; journal: unknown[] };
mkdirSync(join(root, '.dev'), { recursive: true });
const scratch = mkdtempSync(join(root, '.dev/build-command-json-test-'));
const bin = join(scratch, 'bin');
mkdirSync(bin);
// Windows environment names are case-insensitive. Do not retain an inherited
// Path alongside PATH, or allow a missing fixture to fall through to host tools.
const fixtureEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toUpperCase() !== 'PATH'));
const receipt: Invocation[] = [];
const began = Date.now();
const sha = (path: string) => createHash('sha256').update(readFileSync(path)).digest('hex');
const builds: unknown[] = [];
const executables: Record<string, { path: string; sha256: string }> = {};
const provenance = { candidate: Bun.spawnSync(['git', 'rev-parse', 'HEAD'], { cwd: root }).stdout.toString().trim(), githubSha: process.env.GITHUB_SHA, githubHeadSha: process.env.GITHUB_HEAD_SHA, consumer: { path: fileURLToPath(import.meta.url), sha256: sha(fileURLToPath(import.meta.url)) }, bun: { version: Bun.version, path: process.execPath, sha256: sha(process.execPath) }, node: process.versions.node, moonHome: process.env.MOON_HOME };
let failure: unknown;
const extension = process.platform === 'win32' ? '.exe' : '';
const moon = process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin', `moon${extension}`) : `moon${extension}`;
const build = (argv: string[]) => {
  const started = Date.now();
  const p = Bun.spawnSync(argv, { cwd: root, env: process.env, timeout: 90_000 });
  builds.push({ argv, cwd: root, exitCode: p.exitCode, signal: p.signalCode ?? null, timedOut: p.exitedDueToTimeout, stdoutHex: p.stdout.toString('hex'), stderrHex: p.stderr.toString('hex'), elapsedMs: Date.now() - started });
  assert.equal(p.exitedDueToTimeout, false, `Build timed out: ${JSON.stringify(argv)}`);
  assert.equal(p.signalCode ?? null, null, `Build interrupted: ${JSON.stringify(argv)} (90s ceiling)`);
  assert.equal(p.exitCode, 0, p.stdout.toString() + p.stderr.toString());
};
const artifact = (name: Name) => join(root, 'scripts/_build', `${name}.mbtx/native/debug/build/single/single.exe`);
const fixture = (name: string) => {
  const cwd = join(scratch, name + ' space 😀');
  mkdirSync(cwd, { recursive: true });
  return cwd;
};
const invoke = (name: Name, args: string[], cwd: string, code = 0, overrides: Record<string, string | undefined> = {}, capture: 'pipe' | 'file' = 'pipe') => {
  const journal = join(cwd, 'journal.jsonl');
  writeFileSync(journal, '');
  const started = Date.now();
  const command = [artifact(name), ...args];
  const output = join(cwd, 'redirected-stdout.json');
  const fd = capture === 'file' ? openSync(output, 'w') : undefined;
  let p: ReturnType<typeof Bun.spawnSync>;
  let spawnFailure: unknown;
  try { p = Bun.spawnSync(command, {
    cwd,
    env: { ...fixtureEnv, PATH: bin,
      MORPHIR_BUILD_JSON_STUB: '1', MORPHIR_BUILD_JSON_JOURNAL: journal,
      MORPHIR_BUILD_JSON_CHILD_EXIT: String(code), MORPHIR_BUILD_JSON_MARKER: 'empty/--/😀', ...overrides },
    stdout: fd ?? 'pipe',
    stdin: new Uint8Array(),
    timeout: 90_000,
  });
  } catch (error) { spawnFailure = error; throw error; }
  finally {
    try { if (fd !== undefined) closeSync(fd); }
    catch (error) { throw new AggregateError(spawnFailure === undefined ? [error] : [spawnFailure, error], 'Descriptor cleanup failed; original failure retained'); }
  }
  const stdout = capture === 'file' ? readFileSync(output) : p.stdout!;
  const stderr = p.stderr!;
  const journalText = readFileSync(journal, 'utf8');
  const result: Invocation = { name, args, command, cwd, capture, timedOut: p.exitedDueToTimeout ?? false,
    exitCode: p.exitCode, signal: p.signalCode ?? null,
    stdout: stdout.toString(), stdoutHex: stdout.toString('hex'), stderr: stderr.toString(), stderrHex: stderr.toString('hex'), elapsedMs: Date.now() - started,
    journalText, journal: [] };
  receipt.push(result);
  assert.equal(p.exitedDueToTimeout, false, `${name} ${JSON.stringify(args)} timed out (90s ceiling)`);
  result.journal = journalText.split('\n').filter(Boolean).map(line => JSON.parse(line));
  for (const row of result.journal as { program: string; executable: string; path: string }[]) {
    assert.equal(row.path, bin, 'Fixture children inherit only the fixture PATH');
    const expected = row.program === 'morphir-elm'
      ? join(cwd, 'pkgs/morphir-elm/scripts/node_modules/.bin', 'morphir-elm' + extension)
      : join(bin, row.program + extension);
    assert.equal(row.executable, expected, 'Child resolved to its fixture executable');
    assert.equal(sha(row.executable), executables.stub!.sha256, 'Actual child is the compiled fixture');
  }
  return result;
};
const json = (p: Invocation, expected: number) => {
  assert.equal(p.exitCode, expected, JSON.stringify(p));
  assert.equal(p.signal, null, JSON.stringify(p));
  // Assert physical UTF-8 framing before parsing. Text decoding or JSON.parse
  // alone cannot establish the promised single LF byte on redirected stdout.
  const bytes = Buffer.from(p.stdoutHex, 'hex');
  assert.equal(bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])), false, 'No UTF-8 BOM');
  assert.equal(bytes.at(-2), 0x7d, 'Envelope ends with } followed by LF');
  assert.equal(bytes.at(-1), 0x0a, 'Envelope ends with LF');
  assert.equal(bytes.includes(0x0d), false, 'Envelope contains no physical CR');
  assert.equal(bytes.filter(byte => byte === 0x0a).length, 1, 'Envelope has one physical LF');
  assert.equal(new TextDecoder('utf-8', { fatal: true }).decode(bytes), p.stdout);
  assert.match(p.stdout, /^\{[^\n]*\}\n$/);
  const value = JSON.parse(p.stdout);
  assert.equal(p.stdout, JSON.stringify(value) + '\n', 'Exactly one compact JSON value plus LF');
  assert.equal(value.profile, 'morphir/command-result');
  assert.equal(value.contractVersion, '0.1.0');
  assert.equal(value.command, p.name.replaceAll('-', '.'));
  assert.equal(value.exitCode, expected);
  assert.equal(value.state, expected === 0 ? 'succeeded' : 'failed');
  assert.deepEqual(value.diagnostics, []);
  assert.equal('error' in value, expected !== 0);
  assert.equal('result' in value, expected === 0);
  return value;
};
const files = (cwd: string): Record<string, string> => {
  const result: Record<string, string> = {};
  const walk = (directory: string) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.name !== 'journal.jsonl') result[path.slice(cwd.length + 1)] = readFileSync(path).toString('base64');
    }
  };
  walk(cwd);
  return result;
};
const seedSamples = (cwd: string) => {
  for (const id of ['examples-tutorial', 'elm-rentals', 'records']) {
    const source = join(cwd, 'pkgs/morphir-elm/conformance/projects', id, 'src');
    mkdirSync(source, { recursive: true });
    writeFileSync(join(dirname(source), 'morphir.json'), '{"name":"fixture/😀","exposedModules":["Main"]}\n');
    writeFileSync(join(source, '--json.elm'), 'module Main exposing (..)\nvalue = "😀"\n');
  }
  mkdirSync(join(cwd, 'apps/morphir-workbench/assets'), { recursive: true });
};

try {
  build([moon, 'version', '--all']);
  executables.moon = { path: Bun.which(moon) ?? moon, sha256: sha(Bun.which(moon) ?? moon) };
  // Build current artifacts once, then reuse them across every explicit argv fixture.
  for (const name of names) {
    build([moon, 'build', `scripts/${name}.mbtx`, '--target', 'native']);
    executables[name] = { path: artifact(name), sha256: sha(artifact(name)) };
  }
  const stub = join(bin, 'stub' + extension);
  const compiled = await Bun.build({ entrypoints: [fileURLToPath(import.meta.url)], compile: { outfile: stub }, target: 'bun' });
  builds.push({ kind: 'Bun.build', entrypoints: [fileURLToPath(import.meta.url)], outfile: stub, target: 'bun', success: compiled.success, logs: compiled.logs.map(log => log.message) });
  assert.ok(compiled.success, compiled.logs.map(log => log.message).join('\n'));
  executables.stub = { path: stub, sha256: sha(stub) };
  for (const name of ['moon', 'bun', 'node', 'moonc', 'git']) copyFileSync(stub, join(bin, name + extension));

  for (const name of names) {
    const cwd = fixture(name);
    const help = invoke(name, ['--json', '--help'], cwd);
    const value = json(help, 0);
    assert.match(value.result.render_help, /command-result 0\.1\.0/);
    assert.match(value.result.render_help, /error \{code,message\}/);
    assert.equal(help.stderr, '');
    assert.deepEqual(help.journal, []);
    assert.deepEqual(files(cwd), {});
    for (const args of [['--json', '--unknown'], ['--json', '--help=true']]) {
      const bad = invoke(name, args, cwd);
      assert.equal(json(bad, 2).error.code, 'invalid_arguments');
      assert.deepEqual(bad.journal, []);
      assert.deepEqual(files(cwd), {});
    }
  }

  const simple = names.filter(name => !['assembly-check', 'elm-parity-refresh', 'installed-provider-check', 'typed-source-check', 'workbench-samples'].includes(name));
  for (const name of simple) {
    const cwd = fixture(name);
    if (name.startsWith('sdk-spec-')) {
      mkdirSync(join(cwd, 'pkgs/morphir-sdk-spec'), { recursive: true });
      writeFileSync(join(cwd, 'pkgs/morphir-sdk-spec/sdk_data.mbt'), 'fixture 😀\n');
    }
    if (name.startsWith('scheme-docs-')) {
      mkdirSync(join(cwd, 'pkgs/morphir-scheme/chapter'), { recursive: true });
      writeFileSync(join(cwd, 'pkgs/morphir-scheme/chapter/docs_examples_test.mbt'), 'fixture 😀\n');
    }
    const plain = invoke(name, [], cwd);
    assert.equal(plain.exitCode, 0);
    assert.match(plain.stdout, /child stdout/);
    assert.match(plain.stderr, /child stderr/);
    const success = invoke(name, ['--json'], cwd);
    const result = json(success, 0).result;
    assert.equal(result.passed, true);
    if (name.startsWith('sdk-spec-') || name.startsWith('scheme-docs-')) {
      assert.equal(result.outputs.length, 1);
      assert.equal(result.outputs[0].bytes, Buffer.byteLength('fixture 😀\n'));
    }
    assert.equal(result.steps.length, success.journal.length);
    assert.ok(result.steps.every((step: { exitCode: number }) => step.exitCode === 0));
    assert.ok(!success.stdout.includes('child stdout'));
    assert.match(success.stderr, /child stdout/);
    assert.deepEqual(success.journal, plain.journal);
    for (const row of success.journal as { cwd: string; marker: string }[]) {
      assert.equal(row.cwd, cwd);
      assert.equal(row.marker, 'empty/--/😀');
    }
    for (const args of [ ['--', '--json'], ['--self-test'], ['--help'], ['', '😀', '--', '--json', '--flag=value'] ]) {
      const legacy = invoke(name, args, cwd);
      assert.equal(legacy.exitCode, 0);
      assert.equal(legacy.stdout, plain.stdout);
      assert.equal(legacy.stderr, plain.stderr);
      assert.deepEqual(legacy.journal, plain.journal);
    }
    const literal = invoke(name, ['--json', '--', '', '😀', '--', '--json', '--help', '--flag=value'], cwd);
    json(literal, 0);
    assert.deepEqual(literal.journal, plain.journal);
    for (const code of [23, 130]) {
      const failure = invoke(name, ['--json'], cwd, code);
      const hasRuntimeBuild = ['conformance-check', 'installed-lifecycle-check', 'moonbit-frontend-check', 'native-telemetry-check'].includes(name);
      json(failure, hasRuntimeBuild ? 1 : code);
      assert.equal(failure.journal.length, 1, 'Stop after the first failed child');
      const legacy = invoke(name, [], cwd, code);
      if (!hasRuntimeBuild) assert.equal(legacy.exitCode, code);
      else assert.notEqual(legacy.exitCode, 0, 'Default abort remains a failure');
    }
  }

  const assembly = fixture('assembly-check');
  const assemblyValue = json(invoke('assembly-check', ['--json'], assembly), 0);
  assert.deepEqual(assemblyValue.result.receipt, { profile: 'fixture-assembly', variants: ['saved', 'fresh'] });
  assert.equal(readFileSync(join(assembly, assemblyValue.result.reportPath), 'utf8'), '{"profile":"fixture-assembly","variants":["saved","fresh"]}\n');
  json(invoke('assembly-check', ['--json'], assembly, 23), 1);
  json(invoke('assembly-check', ['--json'], assembly, 0, { MORPHIR_BUILD_JSON_BAD_RECEIPT: '1' }), 1);
  json(invoke('sdk-spec-generate', ['--json'], fixture('sdk-missing-output')), 1);
  json(invoke('scheme-docs-generate', ['--json'], fixture('docs-missing-output')), 1);
  json(invoke('elm-parity-refresh', ['--json'], fixture('parity-missing-projects')), 1);

  const parity = fixture('elm-parity-refresh');
  seedSamples(parity);
  mkdirSync(join(parity, 'pkgs/morphir-engine/acceptance/elm'), { recursive: true });
  const make = join(parity, 'pkgs/morphir-elm/scripts/node_modules/.bin');
  mkdirSync(make, { recursive: true });
  copyFileSync(stub, join(make, 'morphir-elm' + extension));
  const parityValue = json(invoke('elm-parity-refresh', ['--json'], parity), 0);
  assert.deepEqual(parityValue.result.projects, ['elm-rentals', 'examples-tutorial', 'records']);
  assert.equal(parityValue.result.writtenFiles.length, 5);
  for (const path of parityValue.result.writtenFiles) assert.ok(existsSync(join(parity, path)));
  json(invoke('elm-parity-refresh', ['--json'], parity, 23), 23);

  const samples = fixture('workbench-samples');
  seedSamples(samples);
  const sampleValue = json(invoke('workbench-samples', ['--json'], samples), 0);
  assert.equal(sampleValue.result.samples.length, 3);
  assert.equal(sampleValue.result.writtenFiles.length, 4);
  const sampleBytes = files(samples);
  const legacySamples = invoke('workbench-samples', ['--', '--json'], samples);
  assert.equal(legacySamples.exitCode, 0);
  assert.equal(legacySamples.stdout, '');
  assert.deepEqual(files(samples), sampleBytes);
  const missingSamples = fixture('missing-samples');
  mkdirSync(join(missingSamples, 'apps/morphir-workbench/assets'), { recursive: true });
  json(invoke('workbench-samples', ['--json'], missingSamples), 1);

  for (const category of ['invalid-json', 'missing-fields', 'missing-source', 'empty-source']) {
    const cwd = fixture(category);
    seedSamples(cwd);
    const project = join(cwd, 'pkgs/morphir-elm/conformance/projects/examples-tutorial');
    if (category === 'invalid-json') writeFileSync(join(project, 'morphir.json'), '{bad');
    if (category === 'missing-fields') writeFileSync(join(project, 'morphir.json'), '{}');
    if (category === 'missing-source') rmSync(join(project, 'src'), { recursive: true });
    if (category === 'empty-source') rmSync(join(project, 'src/--json.elm'));
    json(invoke('workbench-samples', ['--json'], cwd), 1);
  }

  // Exercise a legacy abort at the real decoder boundary. Its signal/status is
  // observed, never assumed to be macOS SIGABRT 134 or portable across backends.
  const typedRefusal = fixture('typed-model-refusal');
  mkdirSync(join(typedRefusal, 'tools'), { recursive: true });
  copyFileSync(join(root, 'tools/moonbit-core-pin.json'), join(typedRefusal, 'tools/moonbit-core-pin.json'));
  writeFileSync(join(typedRefusal, 'moon.mod'), 'name = "fixture/core"\nversion = "0.10.18+6c83a7f62"\n');
  const refusalEnv = { MORPHIR_BUILD_JSON_TYPED_REFUSAL: '1' };
  const oldRefusal = invoke('typed-source-check', [], typedRefusal, 0, refusalEnv);
  assert.notEqual(oldRefusal.exitCode, 0);
  assert.ok(oldRefusal.stdout.includes('Expected array') || oldRefusal.stderr.includes('Expected array'));
  json(invoke('typed-source-check', ['--json'], typedRefusal, 0, refusalEnv), 1);

  // Refusal fixtures are not actual installed-provider or typed-consumer qualification.
  json(invoke('installed-provider-check', ['--json'], fixture('provider-build-failed'), 23), 1);
  json(invoke('installed-provider-check', ['--json'], fixture('provider-missing-home'), 0, { MOON_HOME: undefined }), 1);
  json(invoke('typed-source-check', ['--json'], fixture('typed-child-failed'), 23), 1);
  json(invoke('typed-source-check', ['--json'], fixture('typed-pin-refused')), 1);

  // Real OS descriptor redirection, reusing the current native executable and stub.
  // These four cases are additional to the original 218 pipe invocations.
  for (const [label, args, childCode, expected] of [
    ['help', ['--json', '--help'], 0, 0],
    ['syntax', ['--json', '--unknown'], 0, 2],
    ['completed', ['--json'], 0, 0],
    ['child-failure', ['--json'], 23, 23],
  ] as const) {
    const result = invoke('elm-elm-check', [...args], fixture(`redirected-${label}`), childCode, {}, 'file');
    const value = json(result, expected);
    assert.equal(result.capture, 'file');
    if (label === 'help' || label === 'syntax') {
      assert.equal(result.stderrHex, ''); assert.deepEqual(result.journal, []);
      if (label === 'help') assert.match(value.result.render_help, /command-result 0\.1\.0/);
      else assert.equal(value.error.code, 'invalid_arguments');
    } else {
      const steps = expected === 0 ? 2 : 1;
      assert.equal(result.journal.length, steps);
      const channels = 'child stdout\nchild stderr\n'.repeat(steps);
      assert.equal(result.stderr, channels);
      assert.equal(result.stderrHex, Buffer.from(channels).toString('hex'));
      if (expected === 0) {
        assert.equal(value.result.steps.length, 2);
        assert.ok(value.result.steps.every((step: { exitCode: number }) => step.exitCode === 0));
      }
      else assert.equal(value.error.code, 'child_failed');
      const child = result.journal[0] as { cwd: string; marker: string };
      assert.equal(child.cwd, result.cwd); assert.equal(child.marker, 'empty/--/😀');
    }
  }

  console.log(`${names.length} current native wrappers: JSON help/syntax, completed results, literal legacy tails, channels, argv/cwd/env and failure mapping passed`);
} catch (error) { failure = error; throw error; }
finally {
  const errors: unknown[] = [];
  try {
    const reportPath = process.env.MORPHIR_BUILD_JSON_TEST_RECEIPT;
    if (reportPath) {
      mkdirSync(dirname(resolve(reportPath)), { recursive: true });
      writeFileSync(resolve(reportPath), JSON.stringify({ platform: process.platform, arch: process.arch, bun: Bun.version, provenance, executables, builds, elapsedMs: Date.now() - began, failure: failure === undefined ? null : String(failure), counts: { pipe: receipt.filter(row => row.capture === 'pipe').length, redirectedFile: receipt.filter(row => row.capture === 'file').length }, invocations: receipt }, null, 2) + '\n');
    }
  } catch (error) { errors.push(error); }
  try { rmSync(scratch, { recursive: true, force: true }); } catch (error) { errors.push(error); }
  if (errors.length) throw new AggregateError(failure === undefined ? errors : [failure, ...errors], 'Receipt/cleanup failed; original failure retained');
}
