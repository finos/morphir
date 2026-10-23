// Current artifacts only. No historical Git sources, shell stubs or acquisition.
// Run: mise exec -- bun test tools/packaged-host-command-json.test.ts
import {afterAll, expect, test} from 'bun:test';
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {delimiter, dirname, join, resolve} from 'node:path';
import {tmpdir} from 'node:os';

const repo = resolve(import.meta.dir, '..');
const evidence = join(repo, '.dev/json-packaged-host/current-tests');
const sandbox = realpathSync(mkdtempSync(join(tmpdir(), 'morphir-packaged-json-')));
const home = process.env.MOON_HOME;
if (!home) throw new Error('MOON_HOME must select the pinned toolchain');
const suffix = process.platform === 'win32' ? '.exe' : '';
const tool = (name: string) => join(home, 'bin', name + suffix);
const env: NodeJS.ProcessEnv = {...process.env, MOON_HOME: home, PATH: join(home, 'bin') + delimiter + process.env.PATH};
delete env.GITHUB_SHA;
const receipts: unknown[] = [];
const artifacts = new Map<string, string>();
const names = ['moonbit-extension', 'wasm-host-check', 'workbench-cef-extract', 'workbench-packaged-targets'];
mkdirSync(evidence, {recursive: true});
function command(program: string, args: string[], options: Record<string, unknown> = {}) {
  const started = performance.now();
  const result = spawnSync(program, args, {cwd: repo, env, encoding: 'utf8', timeout: 60000, ...options});
  if (result.error) throw result.error;
  const receipt = {program, args, status: result.status, signal: result.signal, stdout: result.stdout, stderr: result.stderr, elapsedMs: performance.now() - started};
  receipts.push(receipt);
  return receipt;
}
function artifact(name: string) {
  if (artifacts.has(name)) return artifacts.get(name)!;
  const source = ['fixture', 'wasmoon-cli'].includes(name) ? join(evidence, name + '.mbtx') : join(repo, 'scripts', name + '.mbtx');
  const built = command(tool('moon'), ['run', source, '--build-only', '--target', 'native', '--target-dir', join(evidence, 'build', name)]);
  expect(built.status).toBe(0);
  const path = JSON.parse(built.stdout).artifacts_path[0];
  artifacts.set(name, path);
  return path as string;
}
function run(name: string, args: string[], options: Record<string, unknown> = {}) {
  return command(artifact(name), args, options);
}
function completion(receipt: ReturnType<typeof command>, status = 0) {
  expect(receipt.status).toBe(status);
  expect(receipt.signal).toBe(null);
  const value = JSON.parse(receipt.stdout);
  expect(receipt.stdout).toBe(JSON.stringify(value) + '\n');
  expect(value).toMatchObject({profile: 'morphir/command-result', contractVersion: '0.1.0', state: status === 0 ? 'succeeded' : 'failed', exitCode: status, diagnostics: []});
  if (status === 0) expect(value.error).toBeUndefined();
  else {expect(value.result).toBeUndefined(); expect(value.error.message.length).toBeGreaterThan(0);}
  return value;
}
function put(path: string, value: string) {mkdirSync(dirname(path), {recursive: true}); writeFileSync(path, value);}

// A native MoonBit child fixture works on each native CI host. It records the
// process boundary and simulates only finite child responses, never acquisition.
put(join(evidence, 'fixture.mbtx'), `import {
  "moonbitlang/async@0.22.4", "moonbitlang/async@0.22.4/fs", "moonbitlang/async@0.22.4/stdio",
  "moonbitlang/core/env", "moonbitlang/core/json", "moonbitlang/core/string", "moonbitlang/x@0.5.5/sys",
}
async fn main {
  let args = @env.args()[1:].to_owned()
  let path = @env.get_env_var("FIXTURE_RECORD").unwrap()
  let records = if @fs.exists(path) { match @fs.read_file(path).json() { Array(values) => values; _ => fail("records") } } else { [] }
  let record : Json = { "argv": args, "cwd": @fs.realpath("."), "sentinel": @env.get_env_var("FIXTURE_SENTINEL").unwrap_or(""), "path": @env.get_env_var("PATH").unwrap_or(""), "protonNoUpdate": @env.get_env_var("PROTON_NO_UPDATE_CHECK").unwrap_or("") }
  records.push(record)
  @fs.write_file(path, Json::array(records).stringify())
  let stop = @string.parse_int(@env.get_env_var("FIXTURE_FAIL_AT").unwrap_or("0"))
  if stop == records.length() { @sys.exit(@string.parse_int(@env.get_env_var("FIXTURE_EXIT").unwrap_or("23"))) }
  match args {
    ["rev-parse", "HEAD"] => println("candidate")
    ["status", ..] => ()
    ["--print", _] => println(@env.get_env_var("FIXTURE_HOST").unwrap_or("unsupported:host"))
    ["-cjf", archive, "-C", _, "probe.txt"] => @fs.write_file(archive, "archive fixture")
    ["-xjf", _, "-C", destination] => @fs.write_file(destination + "/probe.txt", "CEF archive probe\\n")
    _ => { @stdio.stdout.write("fixture stdout\\n"); @stdio.stderr.write("fixture stderr\\n") }
  }
}
`);
const bin = join(sandbox, 'bin');
mkdirSync(bin);
const record = join(sandbox, 'children.json');
function fixtureEnv(extra: Record<string, string> = {}) {
  rmSync(record, {force: true});
  return {...env, PATH: bin + delimiter + env.PATH, FIXTURE_RECORD: record, FIXTURE_SENTINEL: 'literal 😀 --json', ...extra};
}
function children() {return existsSync(record) ? JSON.parse(readFileSync(record, 'utf8')) : [];}
function installFixture() {
  for (const name of ['moon', 'bun', 'git', 'tar', 'cmake']) copyFileSync(artifact('fixture'), join(bin, name + suffix));
  for (const path of ['morphir-extension.exe', 'acceptance/acceptance.exe']) {
    const destination = join(sandbox, '_build/native/release/build/finos/morphir-extension', path);
    mkdirSync(dirname(destination), {recursive: true}); copyFileSync(artifact('fixture'), destination);
  }
}

test('owned JSON help and syntax errors have one stdout value and no effects', () => {
  for (const name of names) {
    const options = {cwd: sandbox, env: {...env, PATH: ''}};
    const help = run(name, ['--help', '--json'], options);
    expect(completion(help).result.render_help).toContain('Usage:');
    expect(help.stderr).toBe('');
    completion(run(name, ['--json', '--unknown'], options), 1);
    completion(run(name, ['--help', '--json', '--'], options), 1);
  }
}, 60000);

test('extension build, bundle and test preserve child argv, order, cwd and inherited environment', () => {
  installFixture();
  const guest = join(sandbox, '_build/native/release/build/finos/morphir-extension/morphir-extension.exe');
  const output = 'bundle space/雪';
  for (const mode of ['build', 'bundle', 'test']) {
    const scoped = fixtureEnv({MORPHIR_MEP_HOST: join(bin, 'bun' + suffix), MORPHIR_MEP_PLATFORM: 'darwin-arm64', MORPHIR_MEP_BUNDLE: output, MORPHIR_MEP_EVIDENCE: '--json'});
    const receipt = run('moonbit-extension', [mode, '--json'], {cwd: sandbox, env: scoped});
    const result = completion(receipt).result;
    const calls = children();
    expect(calls.length).toBe(mode === 'build' ? 1 : mode === 'bundle' ? 2 : 4);
    expect(calls.every((c: any) => c.cwd === sandbox && c.sentinel === 'literal 😀 --json')).toBe(true);
    expect(calls[mode === 'test' ? 2 : 0].argv).toEqual(['build', '--target', 'native', '--release', 'apps/morphir-extension', ...(mode === 'test' ? ['apps/morphir-extension/acceptance'] : [])]);
    expect(receipt.stderr).toContain('fixture stdout\nfixture stderr\n');
    if (mode === 'build') expect(result.guestPath).toBe(guest);
    if (mode === 'bundle') {expect(result.bundlePath).toBe(output); expect(calls[1].argv.slice(-2)).toEqual(['--output', output]);}
    if (mode === 'test') {expect(result.passed).toBe(true); expect(calls[3].argv).toEqual([guest, sandbox, '--json']);}
    const normal = run('moonbit-extension', [mode], {cwd: sandbox, env: fixtureEnv(scoped)});
    expect(normal.status).toBe(0);
    expect(normal.stdout).toBe('fixture stdout\n'.repeat(calls.length) + (mode === 'build' ? guest + '\n' : ''));
    expect(normal.stderr).toBe('fixture stderr\n'.repeat(calls.length));
  }
  for (const code of [1, 23, 130]) {
    const failure = run('moonbit-extension', ['test', '--json'], {cwd: sandbox, env: fixtureEnv({FIXTURE_FAIL_AT: '2', FIXTURE_EXIT: String(code)})});
    completion(failure, code); expect(children().length).toBe(2);
  }
  completion(run('moonbit-extension', ['bundle', '--json'], {cwd: sandbox, env: fixtureEnv()}), 1);
  expect(children().length).toBe(1);
}, 60000);

test('Wasm setup keeps collected child data off stdout and preserves first failure status', () => {
  const receipt = run('wasm-host-check', ['setup', '--json'], {cwd: sandbox, env: fixtureEnv()});
  expect(completion(receipt).result.steps).toEqual([{exitCode: 0}, {exitCode: 0}]);
  expect(children().map((c: any) => c.argv)).toEqual([
    ['install', '--frozen-lockfile', '--cwd', 'tests/wasm-host'],
    ['run', '--cwd', 'tests/wasm-host', 'playwright', 'install', 'chromium'],
  ]);
  expect(receipt.stderr).not.toContain('fixture stdout');
  const normal = run('wasm-host-check', ['setup'], {cwd: sandbox, env: fixtureEnv()});
  expect(normal.stdout).toBe(''); expect(normal.stderr).toContain('fixture stderr');
  for (const code of [23, 130]) {
    completion(run('wasm-host-check', ['setup', '--json'], {cwd: sandbox, env: fixtureEnv({FIXTURE_FAIL_AT: '2', FIXTURE_EXIT: String(code)})}), code);
    expect(children().length).toBe(2);
  }
}, 60000);

test('CEF exact tar slots stay literal, preserve scoped extraction environment and reject bad digests', () => {
  const destination = join(sandbox, 'CEF destination 雪'); mkdirSync(destination);
  const archive = join(destination, '--json.tar.bz2'); writeFileSync(archive, 'bounded archive fixture');
  const hash = createHash('sha256').update(readFileSync(archive)).digest('hex');
  const scoped = () => fixtureEnv({MORPHIR_CEF_CMAKE: join(bin, 'cmake' + suffix), MORPHIR_CEF_ARCHIVE_SHA256: hash});
  const receipt = run('workbench-cef-extract', ['-xjf', archive, '-C', destination, '--json'], {cwd: sandbox, env: scoped()});
  expect(completion(receipt).result).toEqual({archive, destination, sha256: hash, extracted: true});
  expect(children()[0].argv).toEqual(['-E', 'tar', 'xjf', archive]);
  expect(children()[0].cwd).toBe(destination); expect(children()[0].sentinel).toBe('literal 😀 --json');
  if (process.platform !== 'win32') expect(children()[0].path).toBe(scoped().PATH);
  const normal = run('workbench-cef-extract', ['-xjf', archive, '-C', destination], {cwd: sandbox, env: scoped()});
  expect(normal.status).toBe(0); expect(normal.stdout).toBe("fixture stdout\nExtracting pinned CEF archive with CMake's archive engine\n");
  completion(run('workbench-cef-extract', ['-xjf', archive, '-C', destination, '--json'], {cwd: sandbox, env: {...scoped(), MORPHIR_CEF_ARCHIVE_SHA256: '0'.repeat(64)}}), 1);
  expect(children()).toEqual([]);
  for (const code of [23, 130]) completion(run('workbench-cef-extract', ['-xjf', archive, '-C', destination, '--json'], {cwd: sandbox, env: {...scoped(), FIXTURE_FAIL_AT: '1', FIXTURE_EXIT: String(code)}}), code);
  for (const operand of ['', '--', '--json', '--help', '雪']) {
    completion(run('workbench-cef-extract', ['-xjf', operand, '-C', destination, '--json'], {cwd: sandbox, env: scoped()}), 1);
    expect(children()).toEqual([]);
  }
}, 60000);

test('package probe returns the written receipt and refuses failed children or failed publication', () => {
  put(join(sandbox, 'tools/packaged-targets-pin.json'), readFileSync(join(repo, 'tools/packaged-targets-pin.json'), 'utf8'));
  const receipt = run('workbench-packaged-targets', ['--probe-archive', '--json'], {cwd: sandbox, env: fixtureEnv()});
  const path = join(sandbox, '.dev/packaged-targets/archive-probe/archive-probe.json');
  expect(completion(receipt).result).toEqual(JSON.parse(readFileSync(path, 'utf8')));
  expect(children().length).toBe(2);
  completion(run('workbench-packaged-targets', ['--probe-archive', '--json'], {cwd: sandbox, env: fixtureEnv({FIXTURE_FAIL_AT: '2', FIXTURE_EXIT: '23'})}), 23);
  rmSync(path); mkdirSync(path);
  completion(run('workbench-packaged-targets', ['--probe-archive', '--json'], {cwd: sandbox, env: fixtureEnv()}), 1);
  expect(children()).toEqual([]);
  for (const operation of ['build', 'accept']) {
    completion(run('workbench-packaged-targets', [operation, 'linux-x64', '--json'], {cwd: sandbox, env: fixtureEnv()}), 1);
    expect(children().length).toBe(1); // actual selected platform is still required
  }
}, 60000);

test('package aggregate preserves literal directories, exact receipt identity and publication failure', () => {
  const pinsSource = readFileSync(join(repo, 'tools/packaged-targets-pin.json'), 'utf8');
  const pins = JSON.parse(pinsSource);
  const core = JSON.parse(readFileSync(join(repo, pins.toolchainPin), 'utf8'));
  put(join(sandbox, pins.toolchainPin), JSON.stringify(core));
  const checksSource = readFileSync(join(repo, 'scripts/workbench-packaged-targets.mbtx'), 'utf8').match(/let acceptance_checks : Json = (\[[\s\S]*?\n\])/ )?.[1];
  if (!checksSource) throw new Error('Current acceptance check declaration is missing');
  const checks = JSON.parse(checksSource.replace(/,\s*]/, ']'));
  const targets = pins.targets.map((pin: any) => ({
    profile: 'morphir/workbench/packaged-fallback', formatVersion: 1, target: pin.target, passed: true, checks,
    forcedCleanup: false, profileRemoved: true, quiescent: true, profiles: ['proton-cef-fixture'],
    profileCleanup: {after: 'normal-entry-exit-and-owned-process-quiescence', profileRemoved: true, maxAttempts: 4,
      retryDelayMs: 100, cleanupActor: 'none', appSelfRemoved: true, beforeCleanup: [], temporaryRetention: {kind: 'empty'}},
    entryExit: {code: 0, signal: null}, workersStarted: 8, workersClosed: 8,
    build: {profile: 'morphir/workbench/packaged-build', status: 'built', qualification: 'build-only', revision: 'candidate',
      target: pin.target, pinsSha256: createHash('sha256').update(pinsSource).digest('hex'), corePin: core,
      cefRequirements: {proton_version: pins.proton.version, platform: pin.cefPlatform, cef_archive: pin.cefArchive,
        cef_sha256: pin.cefSha256, layout_version: pins.proton.layoutVersion}},
    files: [{path: 'artifact.bin', sha256: createHash('sha256').update('').digest('hex')}],
  }));
  const matrixPath = join(sandbox, '.dev/packaged-targets/matrix.json');
  for (const directory of ['--json', '--', '資料 receipts 😀']) {
    for (const receipt of targets) put(join(sandbox, directory, 'packaged-' + receipt.target, 'acceptance.json'), JSON.stringify(receipt));
    const receipt = run('workbench-packaged-targets', ['aggregate', directory, '--json'], {cwd: sandbox, env: fixtureEnv()});
    const value = completion(receipt);
    expect(value.result).toEqual(JSON.parse(readFileSync(matrixPath, 'utf8')));
    expect(value.result.targets).toEqual(targets);
    const normal = run('workbench-packaged-targets', ['aggregate', directory], {cwd: sandbox, env: fixtureEnv()});
    expect(normal.status).toBe(0);
    expect(normal.stdout).toBe('Both actual target receipts pass on the same candidate; native operation enablement remains separate\n');
  }
  completion(run('workbench-packaged-targets', ['aggregate', '', '--json'], {cwd: sandbox, env: fixtureEnv()}), 1);
  rmSync(matrixPath); mkdirSync(matrixPath);
  completion(run('workbench-packaged-targets', ['aggregate', '--json', '--json'], {cwd: sandbox, env: fixtureEnv()}), 1);
  // A malformed input receipt also fails before a success value can be emitted.
  put(join(sandbox, '--json/packaged-linux-x64/acceptance.json'), '{"passed":false}');
  completion(run('workbench-packaged-targets', ['aggregate', '--json', '--json'], {cwd: sandbox, env: fixtureEnv()}), 1);
}, 60000);

test('current Wasmoon main keeps its bare report and literal argv through an injected execution boundary', () => {
  const source = readFileSync(join(repo, 'tests/wasm-host/wasmoon.mbt'), 'utf8');
  const cli = source.slice(source.indexOf('///|\n#cfg(target="js")'));
  // Compile the production main/parser/prefix code with an execution adapter.
  // This is CLI qualification, not a component-engine or host capability claim.
  put(join(evidence, 'wasmoon-cli.mbtx'), `import {
    "moonbitlang/async@0.22.4", "moonbitlang/async@0.22.4/stdio", "moonbitlang/core/env",
    "moonbitlang/core/json", "moonbitlang/core/argparse", "moonbitlang/x@0.5.5/sys",
  }
  async fn execute(paths : ArrayView[String]) -> Json { { "paths": paths.to_owned() } }
  ${cli}`);
  for (const path of ['', '--', '--json', '--help', '資料/component 😀']) {
    const paths = [path, 'resources', 'callbacks'];
    const normal = run('wasmoon-cli', paths, {cwd: sandbox, env: {...env, PATH: ''}});
    expect(normal.status).toBe(0); expect(JSON.parse(normal.stdout)).toEqual({paths});
    for (const args of [[...paths, '--json'], ['--json', '--', ...paths]]) {
      const receipt = run('wasmoon-cli', args, {cwd: sandbox, env: {...env, PATH: ''}});
      expect(receipt.status).toBe(0); expect(receipt.stdout).toBe(JSON.stringify({paths}) + '\n');
      expect(receipt.stderr).toBe('');
    }
  }
  expect(completion(run('wasmoon-cli', ['--self-test', '--json'])).result.passed).toBe(true);
  expect(completion(run('wasmoon-cli', ['--help', '--json'])).result.render_help).toContain('Usage:');
  completion(run('wasmoon-cli', ['a', 'b', 'c', '--json', '--']), 1);
  completion(run('wasmoon-cli', ['--json', '--', 'a', 'b']), 1);
}, 60000);

afterAll(() => {
  writeFileSync(join(evidence, 'receipts.json'), JSON.stringify({host: {platform: process.platform, arch: process.arch}, bun: Bun.version, moonHome: home, receipts}, null, 2) + '\n');
  rmSync(sandbox, {recursive: true, force: true});
});
