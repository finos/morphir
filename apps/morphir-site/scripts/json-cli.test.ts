import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const app = fileURLToPath(new URL('../', import.meta.url));
const repo = fileURLToPath(new URL('../../../', import.meta.url));

function finite(value: unknown): void {
  if (typeof value === 'number') assert.ok(Number.isFinite(value));
  else if (value !== null && typeof value === 'object') Object.values(value).forEach(finite);
}

function run(exe: string, args: string[], cwd: string, status = 0) {
  const child = spawnSync(exe, args, { cwd, env: { ...process.env }, encoding: 'utf8',
    input: 'unused stdin\n', timeout: 30_000, maxBuffer: 4 * 1024 * 1024 });
  assert.ifError(child.error);
  assert.equal(child.signal, null);
  assert.equal(child.status, status, JSON.stringify({ exe, args, ...child }));
  return child;
}

function machine(exe: string, args: string[], cwd: string, command: string, status = 0, stderr = '') {
  const child = run(exe, args, cwd, status);
  assert.match(child.stdout, /^[^\r\n]+\n$/u, 'one compact JSON document followed by LF');
  const value = JSON.parse(child.stdout);
  finite(value);
  assert.equal(value.profile, 'morphir/command-result');
  assert.equal(value.contractVersion, '0.1.0');
  assert.equal(value.command, `morphir.site.${command}`);
  assert.equal(value.exitCode, status);
  assert.equal(value.state, status === 0 ? 'succeeded' : 'failed');
  assert.equal(Object.hasOwn(value, 'result'), status === 0);
  assert.equal(Object.hasOwn(value, 'error'), status !== 0);
  assert.ok(Array.isArray(value.diagnostics));
  for (const diagnostic of value.diagnostics) {
    assert.ok(['warning', 'error'].includes(diagnostic.severity));
    assert.equal(typeof diagnostic.message, 'string');
    assert.ok(diagnostic.message.length > 0);
  }
  if (status !== 0) {
    assert.equal(typeof value.error.code, 'string');
    assert.equal(typeof value.error.message, 'string');
    assert.ok(value.error.message.length > 0);
  }
  assert.equal(child.stderr, stderr);
  return value;
}

function snapshot(root: string, includeDirectories = false): Record<string, string> {
  const files: Record<string, string> = {};
  function visit(dir: string) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === '.git') continue;
      const path = join(dir, entry.name);
      if (entry.isDirectory()) {
        if (includeDirectories) files[`${relative(root, path).replaceAll('\\', '/')}/`] = '';
        visit(path);
      }
      else files[relative(root, path).replaceAll('\\', '/')] = readFileSync(path).toString('hex');
    }
  }
  visit(root);
  return files;
}

test('site native mains preserve finite JSON, effects and literal arguments', { timeout: 180_000 }, async (t) => {
  // Match build.ts's release generator and site-build.yml/check:site's debug checker.
  // Each incremental build checks the current source once; all cases reuse these mains.
  const target = join(app, '_build');
  const tools = {
    generate: join(target, 'native/release/build/finos/morphir-site/generate/generate.exe'),
    check: join(repo, '_build/native/debug/build/finos/morphir-site/check/check.exe'),
  };
  for (const name of ['generate', 'check'] as const) {
    const args = name === 'generate'
      ? ['build', '--target', 'native', '--release', '--target-dir', target, name]
      : ['build', '--target', 'native', name];
    const start = performance.now();
    execFileSync('moon', args, { cwd: app, stdio: 'inherit', timeout: 120_000 });
    assert.ok(existsSync(tools[name]));
    t.diagnostic(`moon ${args.join(' ')}: ${(performance.now() - start).toFixed(0)} ms`);
  }
  const work = mkdtempSync(join(tmpdir(), 'morphir-site-json-'));
  t.after(() => rmSync(work, { recursive: true, force: true }));
  const empty = join(work, 'empty');
  mkdirSync(empty);

  await t.test('help and syntax are effect-free for both mains without inputs', () => {
    writeFileSync(join(empty, 'sentinel'), 'keep\n');
    const before = snapshot(empty, true);
    for (const name of ['generate', 'check'] as const) {
      const help = machine(tools[name], ['--json', '--help'], empty, name);
      assert.match(help.result.help, /--json/);
      assert.deepEqual(snapshot(empty, true), before);
      const failure = machine(tools[name], ['--json', '--unknown'], empty, name, 1);
      assert.equal(failure.error.code, 'syntax');
      assert.deepEqual(snapshot(empty, true), before);
    }
  });

  const fixture = join(work, 'fixture λ');
  mkdirSync(fixture);
  // Local Git only: the real generator invokes ls-files in this isolated repository.
  execFileSync('git', ['init', '-q', fixture], { env: { ...process.env }, timeout: 30_000 });
  cpSync(join(app, 'fixtures/content'), join(fixture, '--json'), { recursive: true });
  cpSync(join(app, 'assets'), join(fixture, 'assets'), { recursive: true });
  const out = join(work, 'site λ $;`');
  const args = ['--root', '--json', '--root', 'ignored', '--out', out, '--out', 'ignored', '--unknown', '--', '--main'];
  let expected: Record<string, string>;

  await t.test('generate matches default bytes, reserved prefix and one-level forwarding', () => {
    const text = run(tools.generate, args, fixture);
    assert.equal(text.stdout, `site: wrote ${out}\n`);
    assert.equal(text.stderr, '');
    expected = snapshot(out);
    assert.deepEqual(Object.keys(expected).sort(), [
      'assets/morphir-mark.svg', 'assets/site.css', 'blog/atom.xml', 'blog/first/index.html',
      'blog/index.html', 'docs/diagram/index.html', 'docs/guide/index.html', 'docs/index.html',
      'index.html', 'search-index.json',
    ]);
    assert.match(readFileSync(join(out, 'docs/guide/index.html'), 'utf8'), /<h2 id="install">Install<\/h2>/);
    rmSync(out, { recursive: true });
    const json = machine(tools.generate, ['--json', '--', ...args], fixture, 'generate');
    assert.equal(json.result.root, '--json');
    assert.equal(json.result.outputDirectory, out);
    assert.equal(json.result.mainBuild, true);
    assert.deepEqual([...json.result.writtenPaths].sort(), Object.keys(expected).sort());
    assert.deepEqual(snapshot(out), expected);
    rmSync(out, { recursive: true });
    const escaped = run(tools.generate, ['--forward-argv', '--', '--json', '--', ...args], fixture);
    assert.equal(escaped.stdout, text.stdout);
    assert.equal(escaped.stderr, text.stderr);
    assert.deepEqual(snapshot(out), expected);
    // An empty root is an operand, so it reaches domain validation rather than syntax/help.
    const before = snapshot(empty, true);
    const failure = machine(tools.generate, ['--json', '--', '--root', '', '--out', join(empty, 'unused')], fixture, 'generate', 1);
    assert.notEqual(failure.error.code, 'syntax');
    assert.deepEqual(snapshot(empty, true), before);
  });

  await t.test('check reports actual counts and invalid-site diagnostics without writes', () => {
    mkdirSync(join(out, 'try'));
    writeFileSync(join(out, 'try/index.html'), '<title>Try</title>');
    writeFileSync(join(out, 'assets/islands.js'), '');
    const args = ['--dir', out, '--config', join(fixture, '--json/site/site.json'), '--base', '/fixture/'];
    const before = snapshot(out);
    const text = run(tools.check, args, fixture);
    assert.equal(text.stderr, '');
    const forwarded = run(tools.check, ['--forward-argv', '--', '--json', '--', ...args], fixture);
    assert.equal(forwarded.stdout, text.stdout);
    assert.equal(forwarded.stderr, text.stderr);
    const json = machine(tools.check, ['--json', '--', ...args], fixture, 'check');
    assert.deepEqual(json.result, { directory: out, configPath: args[3], basePath: '/fixture/',
      pageCount: 6, fileCount: 12, passed: true });
    assert.deepEqual(snapshot(out), before);
    writeFileSync(join(out, 'docs/guide/index.html'), '<p>broken</p>');
    const invalid = snapshot(out);
    run(tools.check, args, fixture, 1);
    const failed = machine(tools.check, ['--json', '--', ...args], fixture, 'check', 1);
    assert.equal(failed.error.code, 'site.invalid');
    assert.ok(failed.diagnostics.length > 0);
    assert.deepEqual(snapshot(out), invalid);
  });

  await t.test('warnings stay out of JSON stdout and main draft refusal has no result', () => {
    rmSync(out, { recursive: true });
    writeFileSync(join(fixture, '--json/docs/draft.md'), '---\ndraft: true\n---\n# Draft\n');
    const args = ['--root', '--json', '--out', out];
    const warning = 'warning: docs/draft.md: draft page skipped\n';
    const text = run(tools.generate, args, fixture);
    assert.equal(text.stdout, `${warning}site: wrote ${out}\n`);
    assert.equal(text.stderr, '');
    const expected = snapshot(out);
    rmSync(out, { recursive: true });
    const json = machine(tools.generate, ['--json', '--', ...args], fixture, 'generate', 0, warning);
    assert.deepEqual(json.diagnostics, [{ severity: 'warning', message: 'docs/draft.md: draft page skipped' }]);
    assert.deepEqual(snapshot(out), expected);
    const failure = machine(tools.generate, ['--json', '--', ...args, '--main'], fixture, 'generate', 1);
    assert.equal(failure.error.code, 'site.invalid');
    assert.ok(failure.diagnostics.length > 0);
    assert.deepEqual(snapshot(out), expected);
  });
});
