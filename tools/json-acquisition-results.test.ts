// Current-candidate regression, no historical Git objects or acquisition tools.
// Run: bun test tools/json-acquisition-results.test.ts
import { test, expect, afterAll } from 'bun:test';
import { spawnSync, type SpawnSyncOptionsWithStringEncoding } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, join, delimiter } from 'node:path';
import { tmpdir } from 'node:os';

const repo = resolve(import.meta.dir, '..');
const evidence = join(repo, '.dev/json-acquisition-results');
const selectedHome = process.env.MOON_HOME;
if (!selectedHome) throw new Error('MOON_HOME must select the pinned MoonBit toolchain');
const home = selectedHome;
type Options = Omit<SpawnSyncOptionsWithStringEncoding, 'encoding'>;
type Receipt = { program: string; args: string[]; status: number | null; signal: NodeJS.Signals | null; stdout: string; stderr: string };
function tool(name: string) {
  const windows = join(home, 'bin', name + '.exe');
  return process.platform === 'win32' && existsSync(windows) ? windows : join(home, 'bin', name);
}
const env: NodeJS.ProcessEnv = { ...process.env, MOON_HOME: home, PATH: join(home, 'bin') + delimiter + process.env.PATH };
delete env.GITHUB_ENV;
delete env.MOON_CORE_OVERRIDE;
const isolated = mkdtempSync(join(tmpdir(), 'morphir-json-current-'));
mkdirSync(evidence, { recursive: true });
const receipts: Receipt[] = [];
const artifacts = new Map<string, string>();
const names = ['artifact-client-source', 'headless-host', 'mck-release', 'moonbit-core', 'llvm-setup', 'native-otel-setup', 'decimal'];
function command(program: string, args: string[], options: Options = {}): Receipt {
  const result = spawnSync(program, args, { cwd: repo, env, encoding: 'utf8', timeout: 60000, ...options });
  if (result.error) throw result.error;
  const receipt = { program, args, status: result.status, signal: result.signal, stdout: result.stdout, stderr: result.stderr };
  receipts.push(receipt);
  return receipt;
}
function artifact(name: string): string {
  if (artifacts.has(name)) return artifacts.get(name)!;
  const source = name === 'decimal' ? 'tests/fixtures/core-pin/decimal.mbtx' : `scripts/${name}.mbtx`;
  const built = command(tool('moon'), ['run', '--build-only', '--target', 'wasm', '--target-dir', join(evidence, 'current-build', name), join(repo, source)]);
  expect(built.status).toBe(0);
  const path = JSON.parse(built.stdout).artifacts_path[0];
  artifacts.set(name, path);
  return path;
}
function run(name: string, args: string[], options: Options = {}) {
  return command(tool('moonrun'), [artifact(name), '--', ...args], options);
}
function completion(receipt: Receipt, state: 'succeeded' | 'failed' = 'succeeded') {
  expect(receipt.status).toBe(state === 'succeeded' ? 0 : 1);
  expect(receipt.signal).toBe(null);
  const value = JSON.parse(receipt.stdout);
  expect(receipt.stdout).toBe(JSON.stringify(value) + '\n');
  expect(value).toMatchObject({ profile: 'morphir/command-result', contractVersion: '0.1.0', state, exitCode: receipt.status, diagnostics: [] });
  if (state === 'succeeded') expect(value.error).toBeUndefined();
  else { expect(value.result).toBeUndefined(); expect(value.error.message.length).toBeGreaterThan(0); }
  return value;
}

test('all seven JSON help commands frame one value without filesystem or child effects', () => {
  for (const name of names) {
    const reserved = name === 'headless-host' || name === 'mck-release';
    const args = reserved ? ['--json', '--', '--help'] : ['--json', '--help'];
    const receipt = run(name, args, { cwd: isolated, env: { ...env, PATH: '', GITHUB_ENV: join(isolated, 'absent', 'env') } });
    expect(completion(receipt).result.render_help).toContain('Usage:');
    expect(receipt.stderr).toBe('');
  }
}, 60000);

test('syntax and domain failures produce one failure completion with the actual exit status', () => {
  for (const [name, args] of [
    ['artifact-client-source', ['check', '--json', '--unknown']],
    ['headless-host', ['checkout', '--json', '--']],
    ['mck-release', ['--json', '--', '--self-test', '--json']],
    ['moonbit-core', ['check', '--json', '--unknown']],
    ['llvm-setup', ['--json', '--unknown']],
    ['native-otel-setup', ['--json', '--unknown']],
    ['decimal', ['--json', '--unknown']],
  ] as [string, string[]][]) completion(run(name, args, { cwd: isolated, env: { ...env, PATH: '' } }), 'failed');
}, 60000);

test('flag-shaped, empty and Unicode acquisition operands remain literal', () => {
  for (const path of ['', '--', '--json', '--help', '雪 $`; path']) {
    // A missing path fails before Git, Cargo, curl, or another child can start.
    const receipt = run('headless-host', [path, '--json'], { cwd: isolated, env: { ...env, PATH: '' } });
    completion(receipt, 'failed');
  }
  const literal = run('mck-release', ['--self-test', '--json'], { cwd: isolated, env: { ...env, PATH: '' } });
  expect(literal.status).toBe(1);
  expect(literal.stdout + literal.stderr).toContain('--self-test');
  expect(literal.stdout).not.toContain('"profile":"morphir/command-result"');
}, 60000);

test('core result retains the default trimmed-path consumer and decimal reports actual checks', () => {
  const defaultCore = run('moonbit-core', ['check']);
  expect(defaultCore.status).toBe(0);
  expect(completion(run('moonbit-core', ['check', '--json'])).result.corePath).toBe(defaultCore.stdout.trim());
  expect(completion(run('decimal', ['--json'])).result).toEqual({ passed: true, digitCounts: [3149, 3150, 3151, 5983, 10000] });
}, 60000);

test('portable same-file publication fixtures cover receipts, one append, and write refusal', () => {
  // These fixture tests call the production publication functions with local
  // paths and data. They do not run the acquisition/self-test workflows.
  for (const name of ['headless-host', 'mck-release']) {
    const result = command(tool('moon'), ['test', join(repo, `scripts/${name}.mbtx`)]);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain('failed: 0');
  }
}, 60000);

afterAll(() => {
  writeFileSync(join(evidence, 'current-test-receipts.json'), JSON.stringify({ host: { platform: process.platform, arch: process.arch }, bun: Bun.version, moonHome: home, receipts }, null, 2) + '\n');
  rmSync(isolated, { recursive: true, force: true });
});
