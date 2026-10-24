import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { EOL, tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const scmPath = 'pkgs/morphir-sdk-spec/sdk.scm';
const dataPath = 'pkgs/morphir-sdk-spec/sdk_data.mbt';
const bindingsPath = 'pkgs/morphir-sdk/conformance/bindings.json';

function finite(value: unknown) {
  if (typeof value === 'number') assert.ok(Number.isFinite(value));
  else if (value !== null && typeof value === 'object') Object.values(value).forEach(finite);
}

const receipts: unknown[] = [];
const builds: unknown[] = [];
const artifacts: Record<string, { path: string; sha256: string | null }> = {};
const sourcePaths = [
  'pkgs/morphir-typing-tools/sdkgen/main.mbt',
  'pkgs/morphir-typing-tools/schemedocs/main.mbt',
  'pkgs/morphir-typing-tools/scripts/json-cli.test.mts',
  '.github/workflows/headless-cli.yml', 'moon.mod.json', 'moon.mod',
  'tools/moonbit-core-pin.json',
];
function sha256(path: string) {
  return existsSync(path) ? createHash('sha256').update(readFileSync(path)).digest('hex') : null;
}
function probe(exe: string, args: string[]) {
  const child = spawnSync(exe, args, { cwd: repo, encoding: 'utf8', timeout: 10_000, maxBuffer: 64 * 1024 });
  return { status: child.status, signal: child.signal, error: child.error?.message,
    stdout: child.stdout?.slice(0, 16_384), stderr: child.stderr?.slice(0, 16_384) };
}
// Provenance is opt-in and bounded to this consumer, its mains and the owning
// workflow. The dirty source hashes distinguish local evidence from HEAD.
const provenance = process.env.TYPING_JSON_RECEIPT ? {
  source: Object.fromEntries(sourcePaths.map(path => [path, sha256(join(repo, path))])),
  currentGit: { head: probe('git', ['rev-parse', 'HEAD']),
    status: probe('git', ['status', '--short', '--', ...sourcePaths]) },
  candidate: { sha: process.env.GITHUB_SHA ?? null, ref: process.env.GITHUB_REF ?? null,
    runId: process.env.GITHUB_RUN_ID ?? null, runAttempt: process.env.GITHUB_RUN_ATTEMPT ?? null },
  env: Object.fromEntries(['CI', 'RUNNER_OS', 'MOON_HOME', 'TYPING_JSON_RECEIPT',
    'TYPING_JSON_NATIVE_ARTIFACT_DIR'].map(key => [key, process.env[key] ?? null])),
  toolchain: { moon: probe('moon', ['version', '--all']), bun: probe('bun', ['--version']),
    node: { version: process.version, executable: process.execPath },
    core: { pin: JSON.parse(readFileSync(join(repo, 'tools/moonbit-core-pin.json'), 'utf8')),
      installedManifestSha256: process.env.MOON_HOME ? sha256(join(process.env.MOON_HOME, 'lib/core/moon.mod')) : null } },
} : undefined;

function retain(primaryFailure = false) {
  const path = process.env.TYPING_JSON_RECEIPT;
  if (!path) return;
  try {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify({ platform: process.platform, arch: process.arch,
      node: process.version, provenance, builds, artifacts, receipts }, null, 2) + '\n');
  } catch (error) {
    // A receipt write must not replace the command's primary failure.
    if (!primaryFailure) throw error;
    console.error('Could not retain typing JSON receipt:', error);
  }
}

function run(exe: string, args: string[], cwd: string, status = 0) {
  const child = spawnSync(exe, args, { cwd, env: { ...process.env }, input: Buffer.from('unused stdin\n'), timeout: 30_000, maxBuffer: 4 * 1024 * 1024 });
  receipts.push({ exe, args, status: child.status, signal: child.signal,
    error: child.error?.message,
    stdoutHex: child.stdout?.toString('hex'), stderrHex: child.stderr?.toString('hex') });
  retain(Boolean(child.error || child.signal || child.status !== status || child.stderr?.length));
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  assert.equal(child.status, status, JSON.stringify({ exe, args, ...child }));
  assert.equal(child.stderr.length, 0);
  return { ...child, stdoutBytes: child.stdout, stdout: new TextDecoder('utf-8', { fatal: true }).decode(child.stdout) };
}

function machine(exe: string, args: string[], cwd: string, command: string, status = 0) {
  const child = run(exe, args, cwd, status);
  assert.equal(child.stdoutBytes.includes(13), false, 'raw JSON stdout has no CR');
  assert.notDeepEqual(child.stdoutBytes.subarray(0, 3), Buffer.from([0xef, 0xbb, 0xbf]), 'no UTF-8 BOM');
  assert.match(child.stdout, /^[^\r\n]+\n$/u, 'one compact JSON document followed by LF');
  const value = JSON.parse(child.stdout);
  assert.deepEqual(child.stdoutBytes, Buffer.from(JSON.stringify(value) + '\n'), 'exact compact JSON plus LF bytes');
  finite(value);
  assert.equal(value.profile, 'morphir/command-result');
  assert.equal(value.contractVersion, '0.1.0');
  assert.equal(value.command, `morphir.${command}`);
  assert.equal(value.exitCode, status);
  assert.equal(value.state, status === 0 ? 'succeeded' : 'failed');
  assert.equal(Object.hasOwn(value, 'result'), status === 0);
  assert.equal(Object.hasOwn(value, 'error'), status !== 0);
  assert.ok(Array.isArray(value.diagnostics));
  for (const diagnostic of value.diagnostics) {
    assert.equal(diagnostic.severity, 'error');
    assert.equal(typeof diagnostic.message, 'string');
    assert.ok(diagnostic.message.length > 0);
  }
  if (status !== 0) {
    assert.equal(typeof value.error.code, 'string');
    assert.equal(typeof value.error.message, 'string');
    assert.ok(value.error.message.length > 0);
  }
  return value;
}

// Include directories as well as file bytes, so no-effect checks detect mkdir too.
function snapshot(root: string) {
  const files: Record<string, string | null> = {};
  function visit(dir: string) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      const key = relative(root, path).replaceAll('\\', '/');
      if (entry.isDirectory()) {
        files[`${key}/`] = null;
        visit(path);
      } else files[key] = readFileSync(path).toString('hex');
    }
  }
  visit(root);
  return files;
}

test('typing native mains preserve finite JSON, generated bytes and failures', { timeout: 180_000 }, async (t) => {
  // Optional bounded Windows qualification reuses freshly built production
  // artifacts: DIR/sdkgen.exe and DIR/schemedocs.exe. No fixture executables.
  const artifactDir = process.env.TYPING_JSON_NATIVE_ARTIFACT_DIR;
  const executable = (name: string) => artifactDir ? join(artifactDir, `${name}.exe`) : join(repo, '_build/native/debug/build/finos/morphir-typing-tools', name, `${name}.exe`);
  const tools = { sdkgen: executable('sdkgen'), schemedocs: executable('schemedocs') };
  retain();
  for (const name of ['sdkgen', 'schemedocs'] as const) {
    // Exactly the native debug configuration of sdk-spec-check.mbtx and
    // scheme-docs-check.mbtx. One incremental build per main resolves current
    // source and reuses their outputs when called after the freshness wrappers.
    const args = ['build', `pkgs/morphir-typing-tools/${name}`, '--target', 'native'];
    const start = performance.now();
    if (!artifactDir) {
      const child = spawnSync('moon', args, { cwd: repo, timeout: 120_000, maxBuffer: 4 * 1024 * 1024 });
      builds.push({ exe: 'moon', args, status: child.status, signal: child.signal,
        error: child.error?.message, stdoutHex: child.stdout?.toString('hex'), stderrHex: child.stderr?.toString('hex') });
      artifacts[name] = { path: tools[name], sha256: sha256(tools[name]) };
      retain(Boolean(child.error || child.signal || child.status !== 0));
      if (child.stdout) process.stdout.write(child.stdout);
      if (child.stderr) process.stderr.write(child.stderr);
      assert.ifError(child.error);
      assert.equal(child.signal, null);
      assert.equal(child.status, 0, `moon ${args.join(' ')} failed`);
    } else {
      artifacts[name] = { path: tools[name], sha256: sha256(tools[name]) };
      retain(!existsSync(tools[name]));
    }
    assert.ok(existsSync(tools[name]));
    t.diagnostic(`${artifactDir ? 'reuse production artifact' : `moon ${args.join(' ')}`}: ${(performance.now() - start).toFixed(0)} ms`);
  }
  const work = mkdtempSync(join(tmpdir(), 'morphir-typing-json-'));
  t.after(() => rmSync(work, { recursive: true, force: true }));
  const empty = join(work, 'empty');
  mkdirSync(empty);
  writeFileSync(join(empty, 'sentinel'), 'keep\n');

  await t.test('both help/syntax boundaries are effect-free and keep syntax 2 versus domain 1', () => {
    const before = snapshot(empty);
    for (const name of ['sdkgen', 'schemedocs'] as const) {
      const help = machine(tools[name], ['--json', '--help'], empty, name);
      assert.match(help.result.help, /--json/);
      assert.deepEqual(snapshot(empty), before);
      for (const args of [['--json'], ['--json', 'unknown'], ['--json', 'generate', 'extra'], ['--json', '界'.repeat(24_500)]]) {
        const failure = machine(tools[name], args, empty, name, 2);
        assert.equal(failure.error.code, 'syntax');
        if (args.at(-1)!.length > 1_000) assert.ok(Buffer.byteLength(failure.error.message) > 72_000);
        assert.deepEqual(snapshot(empty), before);
      }
      let domain = empty;
      if (name === 'schemedocs') {
        // An invalid chapter gives a deterministic domain failure without
        // depending on host libc's missing-directory stderr diagnostic.
        domain = join(work, 'invalid-docs');
        mkdirSync(join(domain, 'pkgs/morphir-scheme'), { recursive: true });
        writeFileSync(join(domain, 'pkgs/morphir-scheme/README.mbt.md'), '# Missing harness\n');
      }
      const domainBefore = snapshot(domain);
      const failure = machine(tools[name], ['--json', 'generate'], domain, `${name}.generate`, 1);
      assert.equal(failure.error.code, `${name}.failed`);
      assert.deepEqual(snapshot(domain), domainBefore);
    }
  });

  await t.test('SDK bootstrap/generate/check use actual bytes and literal operands; stale check fails', () => {
    const root = join(work, 'sdk λ');
    mkdirSync(join(root, 'pkgs/morphir-sdk-spec'), { recursive: true });
    mkdirSync(join(root, 'pkgs/morphir-sdk/conformance'), { recursive: true });
    const bindings = JSON.stringify({ values: [{ fqName: 'morphir/SDK:basics#add', elmName: 'add',
      specification: 'vSpec "add" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")' }] });
    writeFileSync(join(root, bindingsPath), bindings);
    writeFileSync(join(root, '--json'), bindings);
    assert.equal(run(tools.sdkgen, ['bootstrap', '--json', '--help'], root).stdout,
      `wrote 1 values in 10 modules to --help${EOL}`);
    const expectedScm = readFileSync(join(root, '--help'));
    assert.match(expectedScm.toString(), /\(package "morphir\/SDK"/);
    rmSync(join(root, '--help'));
    const boot = machine(tools.sdkgen, ['--json', 'bootstrap', '--json', '--help'], root, 'sdkgen.bootstrap');
    assert.deepEqual(boot.result, { bindingsPath: '--json', writtenPaths: ['--help'], valueCount: 1, moduleCount: 10 });
    assert.deepEqual(readFileSync(join(root, '--help')), expectedScm);
    const unicode = ' λ😀 $;`.json';
    writeFileSync(join(root, unicode), bindings);
    const literal = machine(tools.sdkgen, ['--json', 'bootstrap', unicode, '--'], root, 'sdkgen.bootstrap');
    assert.equal(literal.result.bindingsPath, unicode);
    assert.deepEqual(literal.result.writtenPaths, ['--']);
    assert.deepEqual(readFileSync(join(root, '--')), expectedScm);
    const before = snapshot(root);
    for (const args of [['', 'unused'], ['--json', '']]) {
      const failed = machine(tools.sdkgen, ['--json', 'bootstrap', ...args], root, 'sdkgen.bootstrap', 1);
      assert.equal(failed.error.code, 'sdkgen.failed');
      assert.deepEqual(snapshot(root), before);
    }
    writeFileSync(join(root, scmPath), expectedScm);
    assert.equal(run(tools.sdkgen, ['generate'], root).stdout, `wrote ${dataPath}${EOL}`);
    const expectedData = readFileSync(join(root, dataPath));
    assert.match(expectedData.toString(), /let sdk_json : String =/);
    rmSync(join(root, dataPath));
    const generated = machine(tools.sdkgen, ['--json', 'generate'], root, 'sdkgen.generate');
    assert.deepEqual(generated.result, { sourcePath: scmPath, writtenPaths: [dataPath] });
    assert.deepEqual(readFileSync(join(root, dataPath)), expectedData);
    const current = snapshot(root);
    assert.equal(run(tools.sdkgen, ['check'], root).stdout, `sdk.scm matches 1 bindings; sdk_data.mbt is current${EOL}`);
    const checked = machine(tools.sdkgen, ['--json', 'check'], root, 'sdkgen.check');
    assert.deepEqual(checked.result, { bindingCount: 1, checkedPaths: [bindingsPath, scmPath, dataPath], passed: true });
    assert.deepEqual(snapshot(root), current);
    writeFileSync(join(root, dataPath), 'stale\n');
    const stale = snapshot(root);
    run(tools.sdkgen, ['check'], root, 1);
    const failed = machine(tools.sdkgen, ['--json', 'check'], root, 'sdkgen.check', 1);
    assert.equal(failed.error.code, 'sdkgen.differences');
    assert.deepEqual(failed.diagnostics, [{ severity: 'error',
      message: `${dataPath}: is stale; run \`mise run sdk-spec:generate\`` }]);
    assert.deepEqual(snapshot(root), stale);
  });

  await t.test('Scheme docs generate/check match default bytes, remove orphans and refuse drift', () => {
    const root = join(work, 'docs λ');
    const chapter = 'pkgs/morphir-scheme/λ/README.mbt.md';
    const examples = 'pkgs/morphir-scheme/λ/docs_examples_test.mbt';
    const procedures = 'pkgs/morphir-scheme/λ/docs_procedures_generated_wbtest.mbt';
    const orphan = 'pkgs/morphir-scheme/orphan/docs_examples_test.mbt';
    mkdirSync(join(root, 'pkgs/morphir-scheme/λ'), { recursive: true });
    mkdirSync(join(root, 'pkgs/morphir-scheme/orphan'));
    writeFileSync(join(root, chapter), '# Example\n\n```scheme\n(+ 1 2)\n;; => 3\n```\n\n## Built-in procedures\n\n| `car` | First item |\n');
    writeFileSync(join(root, 'pkgs/morphir-scheme/λ/docs_run_test.mbt'), '// fixture harness\n');
    writeFileSync(join(root, orphan), 'orphan\n');
    const text = run(tools.schemedocs, ['generate'], root);
    assert.match(text.stdout, /removed .*orphan\/docs_examples_test.mbt, which no chapter generates/);
    assert.equal(existsSync(join(root, orphan)), false);
    const expected = snapshot(root);
    assert.match(readFileSync(join(root, examples), 'utf8'), /1 checked examples; 0 notest blocks/);
    assert.match(readFileSync(join(root, examples), 'utf8'), /Value\("3"\)/);
    assert.equal(readFileSync(join(root, procedures), 'utf8'),
      `// GENERATED by \`mise run scheme-docs:generate\` from ${chapter}. Do not edit.\n\n///|\nlet documented_procedures : Array[String] = ["car"]\n`);
    rmSync(join(root, examples));
    rmSync(join(root, procedures));
    writeFileSync(join(root, orphan), 'orphan\n');
    const generated = machine(tools.schemedocs, ['--json', 'generate'], root, 'schemedocs.generate');
    assert.deepEqual(generated.result, { writtenPaths: [examples, procedures], removedPaths: [orphan] });
    assert.deepEqual(snapshot(root), expected);
    assert.equal(run(tools.schemedocs, ['check'], root).stdout, `scheme docs examples are current${EOL}`);
    const checked = machine(tools.schemedocs, ['--json', 'check'], root, 'schemedocs.check');
    assert.deepEqual(checked.result, { checkedPaths: [examples, procedures], passed: true });
    assert.deepEqual(snapshot(root), expected);
    writeFileSync(join(root, examples), 'stale\n');
    const stale = snapshot(root);
    run(tools.schemedocs, ['check'], root, 1);
    const failed = machine(tools.schemedocs, ['--json', 'check'], root, 'schemedocs.check', 1);
    assert.equal(failed.error.code, 'schemedocs.differences');
    assert.equal(failed.diagnostics.length, 1);
    assert.ok(failed.diagnostics[0].message.includes(chapter));
    assert.ok(failed.diagnostics[0].message.includes(`${examples} line 1`));
    assert.deepEqual(snapshot(root), stale);
  });
});
