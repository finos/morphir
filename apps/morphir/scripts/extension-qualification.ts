// Qualification of published and fixture extensions on the CLI's worker host.
//
//   node apps/morphir/scripts/extension-qualification.ts --suite <suite> --evidence <dir>
//     --native <morphir executable> --npm-entry <unpacked package/bin/morphir.js>
//     [--python <Python 3.12 or later>] [--portable <directory with model.wasm>]
//     [--native-guest <MoonBit guest executable>]
//
// Suites: elm (task 7.1), python (7.2), moonbit-native and moonbit-portable (7.3),
// conformance (7.4, with the shared generic kit). `scripts/extension-qualification.mbtx` builds the inputs and
// runs this file; run that script, not this file, from mise.
//
// Every downloaded file goes into a new, empty directory and is used only after
// its SHA-256 equals the pin in `apps/morphir/fixtures/qualification/published.json`.
// Each operation becomes one receipt row that names the extension, its version,
// the CLI, the platform, the operation, the result and the guest digest. The
// receipt is written to `<evidence>/<suite>.json`; nothing is written to stdout.
// Progress goes to stderr. The exit status is 0 when every row passed or is a
// recorded known failure, and 1 otherwise.

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync, type SpawnSyncReturns } from 'node:child_process';
import {
  chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync,
  renameSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { delimiter, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const repository = realpathSync(fileURLToPath(new URL('../../../', import.meta.url)));
const fixtures = join(repository, 'apps/morphir/fixtures');
const published = JSON.parse(readFileSync(join(fixtures, 'qualification/published.json'), 'utf8'));

/** A SHA-256 digest as 64 lower-case hexadecimal digits. */
type Sha256 = string & { readonly __sha256: unique symbol };
/** A release platform, for example `aarch64-apple-darwin`. */
type Platform = string & { readonly __platform: unique symbol };
type CliName = 'native' | 'npm';
type RowResult = 'passed' | 'failed' | 'known-failure';

const sha256 = (path: string) => createHash('sha256').update(readFileSync(path)).digest('hex') as Sha256;
const log = (message: string) => process.stderr.write(`${message}\n`);

/** The release platform of this machine. */
export function hostPlatform(): Platform {
  const arch = ({ arm64: 'aarch64', x64: 'x86_64' } as Record<string, string>)[process.arch];
  assert.ok(arch, `No release platform for ${process.arch}`);
  if (process.platform === 'darwin') return `${arch}-apple-darwin` as Platform;
  if (process.platform === 'win32') return `${arch}-pc-windows-msvc` as Platform;
  const report = process.report?.getReport?.() as { header?: { glibcVersionRuntime?: string } } | undefined;
  return `${arch}-unknown-linux-${report?.header?.glibcVersionRuntime ? 'gnu' : 'musl'}` as Platform;
}

// ---------------------------------------------------------------------------
// Downloads

const downloads = join(repository, '.dev/extension-qualification/downloads');

/**
 * Returns a verified local copy of one pinned file. A file already verified in
 * the cache directory named by its digest is hashed again and reused. Otherwise
 * the file is downloaded into a new, empty directory and moved into the cache
 * only when its SHA-256 equals the pin.
 */
function fetchPinned(url: string, filename: string, expected: Sha256): string {
  const cached = join(downloads, expected, filename);
  if (existsSync(cached) && sha256(cached) === expected) return realpathSync(cached);
  mkdirSync(downloads, { recursive: true });
  const fresh = mkdtempSync(join(downloads, 'download-'));
  const target = join(fresh, filename);
  log(`download ${url}`);
  const curl = spawnSync('curl', ['--fail', '--silent', '--show-error', '--location', '--proto', '=https',
    '--proto-redir', '=https', '--retry', '3', '--connect-timeout', '30', '--max-time', '900',
    '--max-filesize', String(512 * 1024 * 1024), '--output', target, url], { stdio: ['ignore', 'inherit', 'inherit'] });
  assert.equal(curl.status, 0, `download failed: ${url}`);
  const actual = sha256(target);
  if (actual !== expected) {
    rmSync(fresh, { recursive: true, force: true });
    assert.fail(`${filename}: SHA-256 ${actual} differs from the pin ${expected}`);
  }
  rmSync(join(downloads, expected), { recursive: true, force: true });
  renameSync(fresh, join(downloads, expected));
  return realpathSync(cached);
}

const releaseUrl = (repo: string, tag: string, filename: string) =>
  `https://github.com/${repo}/releases/download/${encodeURIComponent(tag)}/${filename}`;

function fetchRelease(section: { repository: string; tag: string }, asset: { filename: string; sha256: string }) {
  return fetchPinned(releaseUrl(section.repository, section.tag, asset.filename), asset.filename, asset.sha256 as Sha256);
}

/** The shared MCK runner of the pinned finos/morphir release, unpacked in a new directory. */
function mckRunner(platform: Platform): { runner: string; archiveSha256: Sha256 } {
  const asset = published.mck.runners[platform];
  assert.ok(asset, `No pinned MCK runner for ${platform}`);
  const archive = fetchRelease(published.mck, asset);
  const unpacked = join(dirname(archive), 'unpacked');
  if (!existsSync(unpacked)) {
    const fresh = mkdtempSync(join(dirname(archive), 'unpack-'));
    // Windows: the system bsdtar reads .zip; a GNU tar earlier on PATH (Git Bash) does not.
    const tarProgram = process.platform === 'win32'
      ? join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'tar.exe') : 'tar';
    const tar = spawnSync(tarProgram, ['-xf', archive, '-C', fresh], { stdio: ['ignore', 'inherit', 'inherit'] });
    assert.equal(tar.status, 0, `cannot unpack ${archive}`);
    renameSync(fresh, unpacked);
  }
  const name = process.platform === 'win32' ? 'morphir.exe' : 'morphir';
  const found = findFile(unpacked, name);
  assert.ok(found, `${archive} holds no ${name}`);
  return { runner: found, archiveSha256: asset.sha256 };
}

function findFile(root: string, name: string): string | undefined {
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isFile() && entry.name === name) return path;
    if (entry.isDirectory()) {
      const found = findFile(path, name);
      if (found) return found;
    }
  }
  return undefined;
}

interface SharedKit { path: string; sha256: Sha256; value: any }

/** A shared MEP kit at the pinned finos/morphir revision. */
function kit(name: 'guest-moonbit-bool' | 'guest-generic-json' | 'guest-python-json'): SharedKit {
  const pin = published.mck.kits[name];
  const url = `https://raw.githubusercontent.com/${published.mck.repository}/${published.mck.sourceRevision}/${pin.path}`;
  const path = fetchPinned(url, `${name}.json`, pin.sha256);
  return { path, sha256: pin.sha256, value: JSON.parse(readFileSync(path, 'utf8')) };
}

// ---------------------------------------------------------------------------
// The two CLIs

interface Cli {
  name: CliName;
  command: string;
  prefix: string[];
  /**
   * The environment of every run. On Unix the native CLI's PATH is one new,
   * empty directory, so no `node` can be on it, wherever the host installs
   * Node; the npm CLI's PATH is Node's directory, then `/usr/bin` and `/bin`.
   */
  env: NodeJS.ProcessEnv;
  build: { commit: string; dirty: boolean; programSha256: Sha256; entrySha256?: Sha256; node?: string };
}

function baseEnvironment(home: string, path: string[], isolated = false): NodeJS.ProcessEnv {
  if (process.platform === 'win32') {
    const root = process.env.SystemRoot ?? 'C:\\Windows';
    return {
      SystemRoot: root, SystemDrive: process.env.SystemDrive ?? 'C:', ComSpec: join(root, 'System32', 'cmd.exe'),
      PATHEXT: process.env.PATHEXT ?? '.COM;.EXE;.BAT;.CMD', PATH: [...path, join(root, 'System32')].join(delimiter),
      TEMP: home, TMP: home, USERPROFILE: home, APPDATA: home, LOCALAPPDATA: home,
    };
  }
  return { PATH: (isolated ? path : [...path, '/usr/bin', '/bin']).join(delimiter), HOME: home };
}

/** Checks that the native PATH is isolated (Unix: only empty directories) and says what the no-Node check found. */
function nodeCheckDetail(env: NodeJS.ProcessEnv): string {
  if (process.platform !== 'win32') {
    for (const entry of (env.PATH ?? '').split(delimiter)) {
      assert.deepEqual(readdirSync(entry), [], `the native PATH entry ${entry} is not an empty directory`);
    }
  }
  const entries = (env.PATH ?? '').split(delimiter).map(entry => `${entry} (${existsSync(entry) ? readdirSync(entry).length : 0} entries)`);
  const probe = process.platform === 'win32' ? 'where.exe node.exe' : "/bin/sh -c 'command -v node'";
  return `native PATH: ${entries.join(delimiter)}; ${probe} finds no node there and finds node on the npm CLI PATH`;
}

/** Whether `node` can be found on the PATH of an environment. */
function nodeVisible(env: NodeJS.ProcessEnv): boolean {
  const probe = process.platform === 'win32'
    ? spawnSync('where.exe', ['node.exe'], { env, encoding: 'utf8' })
    : spawnSync('/bin/sh', ['-c', 'command -v node'], { env, encoding: 'utf8' });
  return probe.status === 0;
}

function gitBuild() {
  const git = (args: string[]) => spawnSync('git', args, { cwd: repository, encoding: 'utf8' }).stdout.trim();
  return { commit: git(['rev-parse', 'HEAD']), dirty: git(['status', '--porcelain']) !== '' };
}

function clis(native: string, npmEntry: string, home: string): Cli[] {
  const build = gitBuild();
  // The native CLI needs no program from PATH: it starts its workers by path.
  const emptyPath = join(home, '..', 'native-path');
  mkdirSync(emptyPath);
  return [
    { name: 'native', command: native, prefix: [], env: baseEnvironment(home, [emptyPath], true),
      build: { ...build, programSha256: sha256(native) } },
    { name: 'npm', command: process.execPath, prefix: [npmEntry], env: baseEnvironment(home, [dirname(process.execPath)]),
      build: { ...build, programSha256: sha256(process.execPath), entrySha256: sha256(npmEntry), node: process.version } },
  ];
}

interface Run { status: number | null; stdout: string; stderr: string; elapsedMs: number; report?: any }

/** The CLI's session deadline: the driver passes no `--timeout`, so the CLI default applies. */
const sessionDeadlineMs = 60000;

function run(cli: Cli, args: string[], cwd: string, timeout = 240000): Run {
  const started = performance.now();
  const child: SpawnSyncReturns<string> = spawnSync(cli.command, [...cli.prefix, ...args],
    { cwd, env: cli.env, encoding: 'utf8', timeout, killSignal: 'SIGKILL', maxBuffer: 64 * 1024 * 1024 });
  const elapsedMs = Math.round(performance.now() - started);
  const result: Run = { status: child.status, stdout: child.stdout ?? '', stderr: child.stderr ?? '', elapsedMs };
  if (args.includes('--json')) {
    try { result.report = JSON.parse(result.stdout); } catch { /* the assertion below names it */ }
    assert.ok(result.report, `${cli.name} ${args.join(' ')}: stdout is not one JSON document:\n${result.stdout}\n${result.stderr}`);
  }
  return result;
}

/** Runs one command in JSON mode and checks its exit status and report. */
function command(cli: Cli, args: string[], cwd: string, expected: number): any {
  return timedCommand(cli, args, cwd, expected).report;
}

/** As `command`, and also returns the command's wall-clock duration. */
function timedCommand(cli: Cli, args: string[], cwd: string, expected: number): { report: any; elapsedMs: number } {
  const result = run(cli, [...args, '--json'], cwd);
  const tail = `${result.stdout}\n${result.stderr.slice(-4000)}`;
  assert.equal(result.status, expected,
    `${cli.name} ${args.join(' ')} exited ${result.status} after ${result.elapsedMs} ms (session deadline ${sessionDeadlineMs} ms):\n${tail}`);
  assert.equal(result.report.profile, 'morphir/command-result', tail);
  assert.equal(result.report.contractVersion, '0.1.0', tail);
  assert.equal(result.report.exitCode, expected, tail);
  assert.equal(result.report.state, expected === 0 ? 'succeeded' : 'failed', tail);
  return { report: result.report, elapsedMs: result.elapsedMs };
}

// ---------------------------------------------------------------------------
// Receipts

interface Row {
  extension: string;
  version: string;
  cli: CliName | 'mck';
  platform: Platform;
  operation: string;
  result: RowResult;
  guestSha256: Sha256;
  descriptorSha256?: Sha256;
  outputs?: { path: string; bytes: number; sha256: Sha256 }[];
  detail?: string;
  finding?: string;
}

/**
 * A failure that is recorded and explained, not hidden. The row is
 * `known-failure` while the operation fails with a message that matches; an
 * operation that passes instead fails the row, so the expectation is removed.
 */
interface KnownFailure { match: RegExp; finding: string }

class Ledger {
  readonly rows: Row[] = [];
  readonly platform: Platform;
  constructor(platform: Platform) { this.platform = platform; }

  step(base: Omit<Row, 'result' | 'platform'>, body: () => Partial<Row> | void, known?: KnownFailure): boolean {
    const row: Row = { ...base, platform: this.platform, result: 'passed' };
    try {
      Object.assign(row, body() ?? {});
      if (known) {
        row.result = 'failed';
        row.detail = `passed, but it is recorded as a known failure (${known.finding}); remove the expectation`;
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      row.detail = message.slice(0, 4000);
      if (known && known.match.test(message)) {
        row.result = 'known-failure';
        row.finding = known.finding;
      } else row.result = 'failed';
    }
    this.rows.push(row);
    log(`${row.result.padEnd(13)} ${row.extension} ${row.version} ${row.cli} ${row.operation}${row.result === 'passed' ? '' : `: ${row.finding ?? row.detail?.split('\n')[0]}`}`);
    return row.result === 'passed';
  }
}

function outputs(directory: string, files: { path: string; bytes: number; sha256: string }[]) {
  for (const file of files) assert.equal(sha256(join(directory, file.path)), file.sha256, `${file.path} digest`);
  return files.map(file => ({ path: file.path, bytes: file.bytes, sha256: file.sha256 as Sha256 }));
}

function treeDigests(root: string): Record<string, Sha256> {
  const result: Record<string, Sha256> = {};
  const walk = (directory: string) => {
    for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) walk(path);
      else result[relative(root, path).split('\\').join('/')] = sha256(path);
    }
  };
  walk(root);
  return result;
}

function writePin(path: string, pin: Record<string, unknown>) {
  writeFileSync(path, `${JSON.stringify(pin, null, 2)}\n`);
  return path;
}

function processPin(artifact: string, platform: Platform, origin: string, descriptor?: string) {
  return {
    contractVersion: '0.2.0',
    artifact: { path: artifact, sha256: sha256(artifact) },
    runtime: { kind: 'process', platform, args: [] },
    ...(descriptor ? { descriptor: { path: descriptor, sha256: sha256(descriptor) } } : {}),
    origin,
  };
}

function wasmPin(artifact: string, abi: string, origin: string, descriptor?: string) {
  return {
    contractVersion: '0.2.0',
    artifact: { path: artifact, sha256: sha256(artifact) },
    runtime: { kind: 'wasm', abi },
    ...(descriptor ? { descriptor: { path: descriptor, sha256: sha256(descriptor) } } : {}),
    origin,
  };
}

/** Checks the describe report against the expected identity and worker kind. */
function described(report: any, id: string, version: string, kind: 'process' | 'wasm') {
  assert.equal(report.command, 'extension.describe');
  assert.equal(report.result.worker.kind, kind);
  assert.deepEqual(report.result.extension, { id, version });
  return report.result;
}

// ---------------------------------------------------------------------------
// Suites

interface Context {
  ledger: Ledger;
  platform: Platform;
  clis: Cli[];
  scratch: string;
  python?: string;
  portable?: string;
  nativeGuest?: string;
  notes: Record<string, unknown>;
}

/**
 * The Elm extensions (task 7.1): the native executables of `v0.4.1`, of
 * elm-classic `v0.5.1` (MEP 0.1) and of elm-classic `v0.6.0` (MEP
 * 0.2.0-draft.1, the model line) as process workers, and the
 * `v0.5.0-preview.2` WASM module (`morphir-bytes-v1`, the model line).
 */
function elmSuite(context: Context) {
  elmProcessGuest(context, published.elm, 'morphir-elm', legacyLine, {
    match: /Invalid morphir\.frontend\.compile parameters/,
    finding: 'Elm 0.4.1 requires package.exposedModules (cli2/mep/protocol.ts); the MEP Smithy model makes it optional and the host, which conforms, does not send it; follow-up bead morphir-ukvn.5.64.36.16 (finos/morphir-elm), fixed in elm-classic 0.5.1',
  });
  const classic = published.elmClassic;
  elmProcessGuest(context, { repository: classic.repository, version: '0.5.1', ...classic.releases['0.5.1'] },
    'morphir-elm-classic', legacyLine);
  elmProcessGuest(context, { repository: classic.repository, version: '0.6.0', ...classic.releases['0.6.0'] },
    'morphir-elm-classic', modelLine);
  elmWasmGuest(context);
}

/** What one Elm executable release claims and returns on its protocol line. */
interface ElmLine {
  /** The `protocolVersions` claim, as describe reports it (the host's order). */
  protocolVersions: string[];
  /** The model tuples claim of describe. */
  modelTuples: object[];
  /** Checks the compile report and the published model, and names it in the row detail. */
  compiled: (report: any, model: string) => string;
}

/** MEP 0.1: `morphir.frontend.compile` returns the IR as `morphir-ir.json`, format version 3. */
const legacyLine: ElmLine = {
  protocolVersions: ['0.1'],
  modelTuples: [],
  compiled: (report, model) => {
    assert.equal(report.result.protocolVersion, '0.1');
    assert.equal(report.result.negotiated?.tuple, undefined, 'MEP 0.1 has no model tuple');
    assert.equal(JSON.parse(readFileSync(join(model, 'morphir-ir.json'), 'utf8')).formatVersion, 3);
    return 'MEP 0.1 compile; morphir-ir.json formatVersion 3';
  },
};

/** The model tuple that elm-classic 0.6.0 claims for `morphir.frontend.compileModel`. */
const elmModelTuple = {
  operation: 'morphir.frontend.compileModel', profile: 'morphir-ir', codec: 'morphir-json',
  envelopeVersion: '0.1.0-draft.1', irVersion: '4.0.0',
};

/**
 * MEP 0.2.0-draft.1: the host offers Ion, then JSON (SES-3); the extension
 * agrees only on Morphir JSON, so the session uses that tuple, and
 * `morphir.frontend.compileModel` returns an IR 4.0.0 model envelope.
 */
const modelLine: ElmLine = {
  protocolVersions: ['0.1', '0.2.0-draft.1'],
  modelTuples: [elmModelTuple],
  compiled: (report, model) => {
    assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
    assert.equal(report.result.negotiated.protocolVersion, '0.2.0-draft.1');
    assert.deepEqual(report.result.negotiated.tuple, elmModelTuple);
    assert.deepEqual(report.result.output.files.map((file: { path: string }) => file.path).sort(),
      ['model-envelope.json', 'model.json']);
    assert.equal(existsSync(join(model, 'morphir-ir.json')), false, 'the model line writes no morphir-ir.json');
    const envelope = JSON.parse(readFileSync(join(model, 'model-envelope.json'), 'utf8'));
    assert.equal(envelope.envelopeVersion, elmModelTuple.envelopeVersion);
    assert.equal(envelope.profile, elmModelTuple.profile);
    assert.equal(envelope.irVersion, elmModelTuple.irVersion);
    assert.equal(envelope.payload.codec, elmModelTuple.codec);
    assert.equal(envelope.payload.sha256, sha256(join(model, 'model.json')), 'model.json is the envelope payload');
    const ir = JSON.parse(readFileSync(join(model, 'model.json'), 'utf8'));
    assert.equal(ir.formatVersion, 4, 'the model line returns IR 4.0.0, not format version 3');
    return `MEP 0.2.0-draft.1 compileModel; tuple ${elmModelTuple.profile}/${elmModelTuple.codec}/${elmModelTuple.irVersion}`;
  },
};

/** One Elm release of native executables: describe, the no-Node check and compile of the fixture. */
function elmProcessGuest(context: Context, elm: any, id: string, line: ElmLine, known?: KnownFailure) {
  const { ledger, platform } = context;
  const asset = elm.executables[platform];
  assert.ok(asset, `The Elm extension ${elm.version} has no executable for ${platform}`);
  const executable = fetchRelease(elm, asset);
  if (process.platform !== 'win32') chmodSync(executable, 0o755);
  const descriptor = fetchRelease(elm, elm.descriptor);
  const pin = writePin(join(context.scratch, `${id}-${elm.version}-pin.json`),
    processPin(executable, platform, `${elm.repository} ${elm.tag}`, descriptor));
  const base = { extension: id, version: elm.version, guestSha256: asset.sha256 as Sha256, descriptorSha256: elm.descriptor.sha256 as Sha256 };
  const compiled: Record<string, Record<string, Sha256>> = {};
  for (const cli of context.clis) {
    const directory = mkdtempSync(join(context.scratch, `${id}-${cli.name}-`));
    ledger.step({ ...base, cli: cli.name, operation: 'describe' }, () => {
      const result = described(command(cli, ['extension', 'describe', '--extension-pin', pin], directory, 0), id, elm.version, 'process');
      assert.equal(result.worker.descriptorSha256, elm.descriptor.sha256);
      assert.deepEqual(result.claims.protocolVersions, line.protocolVersions);
      assert.deepEqual(result.claims.modelTuples, line.modelTuples);
      return { detail: `claims MEP ${result.claims.protocolVersions.join(', ')}; languages ${JSON.stringify(result.claims.languages)}` };
    });
    if (cli.name === 'native') {
      ledger.step({ ...base, cli: cli.name, operation: 'environment-without-node' }, () => {
        assert.equal(nodeVisible(cli.env), false, `node is on the native run's PATH ${cli.env.PATH}`);
        // The same probe finds Node on the npm CLI's PATH, so it can see Node.
        const npm = context.clis.find(other => other.name === 'npm');
        assert.ok(!npm || nodeVisible(npm.env), 'the probe does not find Node even on the npm CLI PATH');
        return { detail: nodeCheckDetail(cli.env) };
      });
    }
    ledger.step({ ...base, cli: cli.name, operation: 'compile' }, () => {
      const report = command(cli, ['extension', 'compile', join(fixtures, 'elm-extension/v1/src'), '--package', 'acme/rules',
        '--output', 'model', '--extension-pin', pin], directory, 0);
      const detail = line.compiled(report, join(directory, 'model'));
      compiled[cli.name] = treeDigests(join(directory, 'model'));
      return { outputs: outputs(join(directory, 'model'), report.result.output.files), detail };
    }, known);
  }
  const { native: nativeOutputs, npm: npmOutputs } = compiled;
  if (nativeOutputs && npmOutputs) {
    ledger.step({ ...base, cli: 'npm', operation: 'same-output-as-native' }, () => assert.deepEqual(npmOutputs, nativeOutputs));
  }
}

/**
 * The Elm extension as one WASM module (`morphir-bytes-v1`): describe, compile
 * on the model line, generate Elm, and recompile the generated sources to the
 * same model. It names modules under the package name, so its fixture is
 * `Acme.Rules.Main` in the package `Acme.Rules`.
 */
function elmWasmGuest(context: Context) {
  const { ledger } = context;
  const elm = published.elmWasm;
  const module = fetchRelease(elm, elm.module);
  const descriptor = fetchRelease(elm, elm.descriptor);
  const pin = writePin(join(context.scratch, `morphir-elm-${elm.version}-pin.json`),
    wasmPin(module, 'morphir-bytes-v1', `${elm.repository} ${elm.tag}`, descriptor));
  const base = { extension: 'morphir-elm', version: elm.version, guestSha256: elm.module.sha256 as Sha256, descriptorSha256: elm.descriptor.sha256 as Sha256 };
  const results: Record<string, Record<string, Record<string, Sha256>>> = {};
  for (const cli of context.clis) {
    const directory = mkdtempSync(join(context.scratch, `morphir-elm-wasm-${cli.name}-`));
    const mine: Record<string, Record<string, Sha256>> = {};
    results[cli.name] = mine;
    ledger.step({ ...base, cli: cli.name, operation: 'describe' }, () => {
      const result = described(command(cli, ['extension', 'describe', '--extension-pin', pin], directory, 0), 'morphir-elm', elm.version, 'wasm');
      assert.equal(result.worker.runtime.abi, 'morphir-bytes-v1');
      assert.equal(result.worker.descriptorSha256, elm.descriptor.sha256);
      return { detail: `operations ${result.claims.operations.join(', ')}` };
    });
    const compiled = ledger.step({ ...base, cli: cli.name, operation: 'compile' }, () => {
      const { report, elapsedMs } = timedCommand(cli, ['extension', 'compile', join(fixtures, 'elm-extension/v1/package'),
        '--package', 'Acme.Rules', '--output', 'model', '--extension-pin', pin], directory, 0);
      assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
      assert.equal(report.result.negotiated.tuple.codec, 'morphir-json');
      mine.model = treeDigests(join(directory, 'model'));
      // A slow WASM runtime on one platform shows here before it reaches the deadline.
      return { outputs: outputs(join(directory, 'model'), report.result.output.files),
        detail: `compiled in ${elapsedMs} ms of the ${report.result.bounds?.deadlineMs ?? sessionDeadlineMs} ms session deadline` };
    });
    if (!compiled) continue;
    ledger.step({ ...base, cli: cli.name, operation: 'generate-and-recompile' }, () => {
      const report = command(cli, ['extension', 'generate', 'model/model-envelope.json', '--output', 'generated',
        '--extension-pin', pin], directory, 0);
      assert.ok(existsSync(join(directory, 'generated/src/Acme/Rules/Main.elm')));
      command(cli, ['extension', 'compile', 'generated/src', '--package', 'Acme.Rules', '--output', 'again',
        '--extension-pin', pin], directory, 0);
      assert.deepEqual(readFileSync(join(directory, 'again/model.json')), readFileSync(join(directory, 'model/model.json')));
      mine.generated = treeDigests(join(directory, 'generated'));
      return { outputs: outputs(join(directory, 'generated'), report.result.output.files) };
    });
  }
  const { native: nativeOutputs, npm: npmOutputs } = results;
  if (nativeOutputs && npmOutputs) {
    ledger.step({ ...base, cli: 'npm', operation: 'same-output-as-native' }, () => assert.deepEqual(npmOutputs, nativeOutputs));
  }
}

/** Python extension 0.4.1 and 0.4.2: extism-kernel-v1 WASM workers (task 7.2); 0.5.0: the model line. */
function pythonSuite(context: Context) {
  for (const runtime of ['wasm', 'process'] as const) pythonModelGuest(context, '0.5.0', runtime);
  pythonLegacyGuests(context);
}

/** Python extension 0.4.1 and 0.4.2 claim only MEP 0.1, which stays their line. */
function pythonLegacyGuests(context: Context) {
  const { ledger } = context;
  const python = context.python;
  for (const version of ['0.4.1', '0.4.2']) {
    const release = published.python.releases[version];
    const section = { repository: published.python.repository, tag: release.tag };
    const module = fetchRelease(section, release.module);
    const descriptor = fetchRelease(section, release.descriptor);
    const pin = writePin(join(context.scratch, `python-${version}-pin.json`),
      wasmPin(module, 'extism-kernel-v1', `${published.python.repository} ${release.tag}`, descriptor));
    const base = { extension: 'morphir-python', version, guestSha256: release.module.sha256 as Sha256, descriptorSha256: release.descriptor.sha256 as Sha256 };
    const results: Record<string, Record<string, Record<string, Sha256>>> = {};
    for (const cli of context.clis) {
      const directory = mkdtempSync(join(context.scratch, `python-${version}-${cli.name}-`));
      cpSync(join(fixtures, 'extism-python/v1/acme'), join(directory, 'src/acme'), { recursive: true });
      cpSync(join(fixtures, 'extism-python/v1/single'), join(directory, 'single'), { recursive: true });
      const mine: Record<string, Record<string, Sha256>> = {};
      results[cli.name] = mine;
      ledger.step({ ...base, cli: cli.name, operation: 'describe' }, () => {
        const result = described(command(cli, ['extension', 'describe', '--extension-pin', pin], directory, 0), 'morphir-python', version, 'wasm');
        assert.equal(result.worker.runtime.abi, 'extism-kernel-v1');
        assert.equal(result.worker.descriptorSha256, release.descriptor.sha256);
        return { detail: `multiDocument ${result.claims.frontendFlags?.multiDocument ?? false}` };
      });
      if (version === '0.4.1') {
        for (const ir of ['3', '4']) {
          ledger.step({ ...base, cli: cli.name, operation: `compile-single-document-ir${ir}` }, () => {
            const report = command(cli, ['extension', 'compile', 'single/rules.py', '--package', 'acme/rules', '--ir-version', ir,
              '--output', `single-v${ir}`, '--extension-pin', pin], directory, 0);
            assert.equal(JSON.parse(readFileSync(join(directory, `single-v${ir}/morphir-ir.json`), 'utf8')).formatVersion, Number(ir));
            mine[`single-v${ir}`] = treeDigests(join(directory, `single-v${ir}`));
            return { outputs: outputs(join(directory, `single-v${ir}`), report.result.output.files) };
          });
        }
        ledger.step({ ...base, cli: cli.name, operation: 'refuse-multi-document' }, () => {
          const report = command(cli, ['extension', 'compile', 'src', '--package', 'acme/rules', '--ir-version', '3',
            '--output', 'multi', '--extension-pin', pin], directory, 2);
          assert.equal(report.error.code, 'extension.capability_unavailable');
          assert.match(report.error.message, /multiDocument/);
          assert.equal(existsSync(join(directory, 'multi')), false);
          assert.equal(existsSync(join(directory, 'multi.morphir-partial')), false);
          return { detail: report.error.message };
        });
        continue;
      }
      for (const ir of ['3', '4']) {
        const model = `model-v${ir}`, generated = `generated-v${ir}`, again = `again-v${ir}`;
        const compiled = ledger.step({ ...base, cli: cli.name, operation: `compile-ir${ir}` }, () => {
          const report = command(cli, ['extension', 'compile', 'src', '--package', 'acme/rules', '--ir-version', ir,
            '--output', model, '--extension-pin', pin], directory, 0);
          assert.equal(report.result.protocolVersion, '0.1');
          assert.equal(JSON.parse(readFileSync(join(directory, model, 'morphir-ir.json'), 'utf8')).formatVersion, Number(ir));
          mine[model] = treeDigests(join(directory, model));
          return { outputs: outputs(join(directory, model), report.result.output.files) };
        });
        if (!compiled) continue;
        const generatedOk = ledger.step({ ...base, cli: cli.name, operation: `generate-ir${ir}` }, () => {
          // MEP 0.1 generate takes the IR version from formatVersion and sends no options.irVersion.
          const report = command(cli, ['extension', 'generate', join(model, 'morphir-ir.json'), '--output', generated,
            '--extension-pin', pin], directory, 0);
          mine[generated] = treeDigests(join(directory, generated));
          return { outputs: outputs(join(directory, generated), report.result.output.files) };
        });
        if (!generatedOk) continue;
        ledger.step({ ...base, cli: cli.name, operation: `consumer-ir${ir}` }, () => {
          assert.ok(python, 'no Python 3.12 or later for the consumer check; pass --python');
          const check = spawnSync(python, ['-I', join(repository, 'apps/morphir/scripts/extension-qualification-consumer.py'),
            join(directory, generated)], { encoding: 'utf8', timeout: 60000 });
          assert.equal(check.status, 0, `${check.stdout}\n${check.stderr}`);
          return { detail: check.stdout.trim() };
        });
        ledger.step({ ...base, cli: cli.name, operation: `recompile-generated-ir${ir}` }, () => {
          command(cli, ['extension', 'compile', generated, '--package', 'acme/rules', '--ir-version', ir,
            '--output', again, '--extension-pin', pin], directory, 0);
          assert.deepEqual(JSON.parse(readFileSync(join(directory, again, 'morphir-ir.json'), 'utf8')),
            JSON.parse(readFileSync(join(directory, model, 'morphir-ir.json'), 'utf8')));
        });
        ledger.step({ ...base, cli: cli.name, operation: `refuse-ir-version-mismatch-ir${ir}` }, () => {
          const report = command(cli, ['extension', 'generate', join(model, 'morphir-ir.json'), '--ir-version', ir === '3' ? '4' : '3',
            '--output', `mismatch-v${ir}`, '--extension-pin', pin], directory, 2);
          assert.equal(report.error.code, 'extension.ir_version_mismatch');
          assert.equal(existsSync(join(directory, `mismatch-v${ir}`)), false);
        });
      }
    }
    const { native: nativeOutputs, npm: npmOutputs } = results;
    if (nativeOutputs && npmOutputs) {
      ledger.step({ ...base, cli: 'npm', operation: 'same-output-as-native' }, () => {
        assert.deepEqual(npmOutputs, nativeOutputs);
        return { detail: `${Object.keys(nativeOutputs).length} output directories` };
      });
    }
  }
}

/**
 * Python extension 0.5.0 on the model line (bead morphir-ukvn.5.64.36.23): it
 * claims MEP 0.2.0-draft.1 and 0.1 and JSON tuples at IR 3.0.0 and 4.0.0, as a
 * WASM worker and as a process worker. Compile and generate at each IR version,
 * from both CLIs; `formatVersion` of the published model follows the tuple.
 */
function pythonModelGuest(context: Context, version: string, runtime: 'wasm' | 'process') {
  const { ledger, platform } = context;
  const python = context.python;
  const release = published.python.releases[version];
  const section = { repository: published.python.repository, tag: release.tag };
  const origin = `${published.python.repository} ${release.tag}`;
  const asset = runtime === 'wasm' ? release.module : release.executables[platform];
  assert.ok(asset, `The Python extension ${version} has no executable for ${platform}`);
  const artifact = fetchRelease(section, asset);
  if (runtime === 'process' && process.platform !== 'win32') chmodSync(artifact, 0o755);
  const descriptorAsset = runtime === 'wasm' ? release.descriptor : release.processDescriptor;
  const descriptor = fetchRelease(section, descriptorAsset);
  const pin = writePin(join(context.scratch, `python-${version}-${runtime}-pin.json`), runtime === 'wasm'
    ? wasmPin(artifact, 'extism-kernel-v1', origin, descriptor)
    : processPin(artifact, platform, origin, descriptor));
  const base = {
    extension: `morphir-python (${runtime})`, version,
    guestSha256: asset.sha256 as Sha256, descriptorSha256: descriptorAsset.sha256 as Sha256,
  };
  const tuple = (operation: string, ir: string) => ({
    operation, profile: 'morphir-ir', codec: 'morphir-json', envelopeVersion: '0.1.0-draft.1', irVersion: `${ir}.0.0`,
  });
  const results: Record<string, Record<string, Record<string, Sha256>>> = {};
  for (const cli of context.clis) {
    const directory = mkdtempSync(join(context.scratch, `python-${version}-${runtime}-${cli.name}-`));
    cpSync(join(fixtures, 'extism-python/v1/acme'), join(directory, 'src/acme'), { recursive: true });
    const mine: Record<string, Record<string, Sha256>> = {};
    results[cli.name] = mine;
    ledger.step({ ...base, cli: cli.name, operation: 'describe' }, () => {
      const result = described(command(cli, ['extension', 'describe', '--extension-pin', pin], directory, 0), 'morphir-python', version, runtime);
      assert.equal(result.worker.descriptorSha256, descriptorAsset.sha256);
      assert.deepEqual([...result.claims.protocolVersions].sort(), ['0.1', '0.2.0-draft.1']);
      return { detail: `model tuples ${result.claims.modelTuples.length}` };
    });
    for (const ir of ['3', '4']) {
      const model = `model-v${ir}`, generated = `generated-v${ir}`, again = `again-v${ir}`;
      const compiled = ledger.step({ ...base, cli: cli.name, operation: `compile-model-ir${ir}` }, () => {
        const report = command(cli, ['extension', 'compile', 'src', '--package', 'acme/rules', '--ir-version', ir,
          '--output', model, '--extension-pin', pin], directory, 0);
        assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
        assert.deepEqual(report.result.negotiated.tuple, tuple('morphir.frontend.compileModel', ir));
        assert.deepEqual(report.result.output.files.map((file: { path: string }) => file.path), ['model-envelope.json', 'model.json']);
        const envelope = JSON.parse(readFileSync(join(directory, model, 'model-envelope.json'), 'utf8'));
        assert.equal(envelope.irVersion, `${ir}.0.0`);
        const formatVersion = JSON.parse(readFileSync(join(directory, model, 'model.json'), 'utf8')).formatVersion;
        assert.equal(formatVersion, Number(ir));
        mine[model] = treeDigests(join(directory, model));
        return { outputs: outputs(join(directory, model), report.result.output.files), detail: `formatVersion ${formatVersion}` };
      });
      if (!compiled) continue;
      const generatedOk = ledger.step({ ...base, cli: cli.name, operation: `generate-model-ir${ir}` }, () => {
        const report = command(cli, ['extension', 'generate', join(model, 'model-envelope.json'), '--ir-version', ir,
          '--output', generated, '--extension-pin', pin], directory, 0);
        assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
        assert.deepEqual(report.result.negotiated.tuple, tuple('morphir.backend.generateModel', ir));
        mine[generated] = treeDigests(join(directory, generated));
        return { outputs: outputs(join(directory, generated), report.result.output.files) };
      });
      if (!generatedOk) continue;
      // Plain IR goes on the model line too: the host wraps the bytes of model.json.
      ledger.step({ ...base, cli: cli.name, operation: `generate-plain-ir${ir}` }, () => {
        const plain = `plain-v${ir}`;
        const report = command(cli, ['extension', 'generate', join(model, 'model.json'), '--output', plain,
          '--extension-pin', pin], directory, 0);
        assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
        assert.deepEqual(report.result.negotiated.tuple, tuple('morphir.backend.generateModel', ir));
        assert.deepEqual(treeDigests(join(directory, plain)), mine[generated], 'plain IR and its envelope generate differently');
        mine[plain] = treeDigests(join(directory, plain));
        return { outputs: outputs(join(directory, plain), report.result.output.files) };
      });
      ledger.step({ ...base, cli: cli.name, operation: `consumer-ir${ir}` }, () => {
        assert.ok(python, 'no Python 3.12 or later for the consumer check; pass --python');
        const check = spawnSync(python, ['-I', join(repository, 'apps/morphir/scripts/extension-qualification-consumer.py'),
          join(directory, generated)], { encoding: 'utf8', timeout: 60000 });
        assert.equal(check.status, 0, `${check.stdout}\n${check.stderr}`);
        return { detail: check.stdout.trim() };
      });
      ledger.step({ ...base, cli: cli.name, operation: `recompile-generated-ir${ir}` }, () => {
        command(cli, ['extension', 'compile', generated, '--package', 'acme/rules', '--ir-version', `${ir}.0.0`,
          '--output', again, '--extension-pin', pin], directory, 0);
        assert.deepEqual(JSON.parse(readFileSync(join(directory, again, 'model.json'), 'utf8')),
          JSON.parse(readFileSync(join(directory, model, 'model.json'), 'utf8')));
      });
      ledger.step({ ...base, cli: cli.name, operation: `refuse-ir-version-mismatch-ir${ir}` }, () => {
        const report = command(cli, ['extension', 'generate', join(model, 'model-envelope.json'), '--ir-version', ir === '3' ? '4' : '3',
          '--output', `mismatch-v${ir}`, '--extension-pin', pin], directory, 2);
        assert.equal(report.error.code, 'extension.ir_version_mismatch');
        assert.equal(existsSync(join(directory, `mismatch-v${ir}`)), false);
      });
    }
    ledger.step({ ...base, cli: cli.name, operation: 'default-ir' }, () => {
      const report = command(cli, ['extension', 'compile', 'src', '--package', 'acme/rules', '--output', 'default',
        '--extension-pin', pin], directory, 0);
      assert.deepEqual(report.result.negotiated.tuple, tuple('morphir.frontend.compileModel', '4'));
      assert.equal(JSON.parse(readFileSync(join(directory, 'default/model.json'), 'utf8')).formatVersion, 4);
      return { detail: 'no flag: the first agreed tuple has IR 4.0.0' };
    });
    for (const [operation, flags] of [
      ['refuse-unknown-ir', ['--ir-version', '5']],
      ['refuse-ion-at-ir3', ['--ir-version', '3', '--model-format', 'ion']],
    ] as [string, string[]][]) {
      ledger.step({ ...base, cli: cli.name, operation }, () => {
        const report = command(cli, ['extension', 'compile', 'src', '--package', 'acme/rules', ...flags,
          '--output', operation, '--extension-pin', pin], directory, 2);
        assert.equal(report.error.code, 'extension.tuple_unavailable');
        assert.equal(existsSync(join(directory, operation)), false);
        return { detail: report.error.message };
      });
    }
  }
  const { native: nativeOutputs, npm: npmOutputs } = results;
  if (nativeOutputs && npmOutputs) {
    ledger.step({ ...base, cli: 'npm', operation: 'same-output-as-native' }, () => {
      assert.deepEqual(npmOutputs, nativeOutputs);
      return { detail: `${Object.keys(nativeOutputs).length} output directories` };
    });
  }
}

/** The MoonBit guest, native (process) or portable (morphir-bytes-v1), with the shared kit (task 7.3). */
function moonbitSuite(context: Context, flavour: 'native' | 'portable') {
  const { ledger, platform } = context;
  const shared = kit('guest-moonbit-bool');
  const artifact = flavour === 'native' ? context.nativeGuest : context.portable && join(context.portable, 'model.wasm');
  assert.ok(artifact && existsSync(artifact), `No MoonBit ${flavour} guest; pass --${flavour === 'native' ? 'native-guest' : 'portable'}`);
  const guestSha256 = sha256(artifact);
  const pin = writePin(join(context.scratch, `moonbit-${flavour}-pin.json`), flavour === 'native'
    ? processPin(artifact, platform, 'finos/morphir-moonbit apps/morphir-extension (local build)')
    : wasmPin(artifact, 'morphir-bytes-v1', 'finos/morphir-moonbit mise run package:mep-extension (local build)'));
  const base = { extension: 'morphir-moonbit', version: '0.1.0', guestSha256 };
  const source = shared.value.source;
  const document = source.sources.documents[0];
  const results: Record<string, Record<string, Record<string, Sha256>>> = {};
  for (const cli of context.clis) {
    const directory = mkdtempSync(join(context.scratch, `moonbit-${flavour}-${cli.name}-`));
    mkdirSync(join(directory, 'src'));
    writeFileSync(join(directory, 'src/main.mbt'), document.text);
    writeFileSync(join(directory, 'json-envelope.json'), JSON.stringify(jsonEnvelope(shared.value.plainIr)));
    const mine: Record<string, Record<string, Sha256>> = {};
    results[cli.name] = mine;
    ledger.step({ ...base, cli: cli.name, operation: 'describe' }, () => {
      const result = described(command(cli, ['extension', 'describe', '--extension-pin', pin], directory, 0), 'morphir-moonbit', '0.1.0', flavour === 'native' ? 'process' : 'wasm');
      if (flavour === 'portable') assert.equal(result.worker.runtime.abi, 'morphir-bytes-v1');
    });
    if (cli.name === 'native' && flavour === 'native') {
      ledger.step({ ...base, cli: cli.name, operation: 'environment-without-node' }, () => {
        assert.equal(nodeVisible(cli.env), false);
        const npm = context.clis.find(other => other.name === 'npm');
        assert.ok(!npm || nodeVisible(npm.env), 'the probe does not find Node even on the npm CLI PATH');
        return { detail: nodeCheckDetail(cli.env) };
      });
    }
    const compiled = ledger.step({ ...base, cli: cli.name, operation: 'compile-kit-source' }, () => {
      const report = command(cli, ['extension', 'compile', 'src/main.mbt', '--package', source.package.name, '--output', 'model',
        '--extension-pin', pin], directory, 0);
      assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
      assert.equal(report.result.negotiated.tuple.codec, 'ion-binary');
      mine.model = treeDigests(join(directory, 'model'));
      return { outputs: outputs(join(directory, 'model'), report.result.output.files) };
    });
    if (compiled) {
      const generated = ledger.step({ ...base, cli: cli.name, operation: 'generate' }, () => {
        const report = command(cli, ['extension', 'generate', 'model/model-envelope.json', '--output', 'generated',
          '--extension-pin', pin], directory, 0);
        assert.deepEqual(readFileSync(join(directory, 'generated/mep/source-model.ionb')), readFileSync(join(directory, 'model/model.ionb')));
        mine.generated = treeDigests(join(directory, 'generated'));
        return { outputs: outputs(join(directory, 'generated'), report.result.output.files) };
      });
      if (generated) {
        ledger.step({ ...base, cli: cli.name, operation: 'kit-consumer' }, () => {
          const stdout = moonbitConsumer(directory, join(directory, 'generated'), shared.value);
          return { detail: stdout.trim() };
        });
      }
    }
    ledger.step({ ...base, cli: cli.name, operation: 'generate-kit-plain-ir' }, () => {
      const report = command(cli, ['extension', 'generate', 'json-envelope.json', '--output', 'json-generated',
        '--extension-pin', pin], directory, 0);
      for (const [name, text] of Object.entries(shared.value.expectedJsonArtifacts as Record<string, string>)) {
        assert.equal(readFileSync(join(directory, 'json-generated', name), 'utf8'), text, `${name} differs from the kit`);
      }
      return { outputs: outputs(join(directory, 'json-generated'), report.result.output.files) };
    });
    // Plain IR goes on the model line: the host wraps the file, and the guest
    // generates what it generates from the envelope of the same IR.
    ledger.step({ ...base, cli: cli.name, operation: 'generate-plain-ir4' }, () => {
      writeFileSync(join(directory, 'plain-ir4.json'), JSON.stringify(shared.value.plainIr));
      const report = command(cli, ['extension', 'generate', 'plain-ir4.json', '--output', 'plain-generated',
        '--extension-pin', pin], directory, 0);
      assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
      assert.deepEqual(report.result.negotiated.tuple, {
        operation: 'morphir.backend.generateModel', profile: 'morphir-ir', codec: 'morphir-json',
        envelopeVersion: '0.1.0-draft.1', irVersion: '4.0.0',
      });
      for (const [name, text] of Object.entries(shared.value.expectedJsonArtifacts as Record<string, string>)) {
        assert.equal(readFileSync(join(directory, 'plain-generated', name), 'utf8'), text, `${name} differs from the kit`);
      }
      return { outputs: outputs(join(directory, 'plain-generated'), report.result.output.files) };
    });
    // The guest claims IR 4.0.0 only, so plain IR 3 has no tuple and no fall back.
    ledger.step({ ...base, cli: cli.name, operation: 'refuse-plain-ir3' }, () => {
      writeFileSync(join(directory, 'plain-ir3.json'), JSON.stringify({ ...shared.value.plainIr, formatVersion: 3 }));
      const report = command(cli, ['extension', 'generate', 'plain-ir3.json', '--output', 'plain-refused',
        '--extension-pin', pin], directory, 2);
      assert.equal(report.error.code, 'extension.tuple_unavailable');
      assert.equal(existsSync(join(directory, 'plain-refused')), false);
      return { detail: report.error.message };
    });
  }
  const { native: nativeOutputs, npm: npmOutputs } = results;
  if (nativeOutputs && npmOutputs) {
    ledger.step({ ...base, cli: 'npm', operation: 'same-output-as-native' }, () => assert.deepEqual(npmOutputs, nativeOutputs));
  }
  mckGuestRun(context, flavour, artifact, shared, base);
}

/** A Morphir JSON model envelope around the kit's independent plain IR. */
function jsonEnvelope(plainIr: unknown) {
  const bytes = Buffer.from(JSON.stringify(plainIr));
  const digest = createHash('sha256').update(bytes).digest('hex');
  return {
    envelopeVersion: '0.1.0-draft.1', modelId: 'urn:morphir:mck:bool', revision: `sha256:${digest}`, irVersion: '4.0.0',
    profile: 'morphir-ir',
    payload: { codec: 'morphir-json', layout: 'single-document', decodedByteLength: bytes.length, sha256: digest, content: bytes.toString('base64') },
  };
}

/** Builds the generated library with the kit's consumer source and checks the kit's expected stdout. */
function moonbitConsumer(directory: string, generated: string, kitValue: any): string {
  const consumer = join(directory, 'consumer');
  mkdirSync(consumer);
  for (const [name, text] of Object.entries(kitValue.consumer.files as Record<string, string>)) writeFileSync(join(consumer, name), text);
  writeFileSync(join(directory, 'moon.work'), `members = ${JSON.stringify([generated, consumer, join(repository, 'pkgs/morphir-sdk')])}\n`);
  const moon = spawnSync('moon', ['-C', directory, 'run', '--target', 'native', 'consumer'], { encoding: 'utf8', timeout: 600000 });
  assert.equal(moon.status, 0, moon.stderr.slice(-4000));
  // A Windows console program ends its lines with CRLF; the kit states LF. Only
  // the line ending is normalized; the text must match exactly.
  const stdout = moon.stdout.replace(/\r\n/g, '\n');
  assert.equal(stdout, kitValue.consumer.expectedStdout);
  return stdout;
}

/**
 * Runs the shared MEP kit against the guest. The native guest is its own stdio
 * host. The portable guest is served by the native CLI's internal worker mode,
 * `morphir extension worker`, with the CLI's own build identity.
 */
function mckGuestRun(context: Context, flavour: 'native' | 'portable', artifact: string,
  shared: SharedKit, base: { extension: string; version: string; guestSha256: Sha256 }) {
  if (flavour === 'native') {
    sharedKitRun(context, 'shared-kit-direct', shared, base, () => ({ program: artifact, args: [], identityFiles: [artifact] }));
  } else {
    sharedKitRun(context, 'shared-kit-native-cli-worker-mode', shared, base, evidence => workerModeHost(context, 'morphir-bytes-v1', artifact, evidence));
  }
}

/** A guest module served by `morphir extension worker` of the native CLI, with the CLI's own build identity. */
function workerModeHost(context: Context, abi: string, artifact: string, evidence: string): SharedKitHost {
  const native = context.clis.find(cli => cli.name === 'native')!;
  const help = run(native, ['extension', 'worker', '--help', '--json'], evidence);
  const identity = JSON.parse(help.stdout).result.buildIdentity;
  assert.match(identity, /^[0-9a-f]{64}$/);
  return {
    program: native.command,
    args: ['extension', 'worker', '--abi', abi, '--module', artifact, '--build-identity', identity,
      '--request-bytes', String(4 * 1024 * 1024), '--response-bytes', String(16 * 1024 * 1024)],
    identityFiles: [native.command, artifact],
  };
}

/** What the shared runner launches, and the files that it pins by their exact bytes. */
interface SharedKitHost { program: string; args: string[]; identityFiles: string[] }

/** One `mck mep guest-run` of a shared kit, then `report-check` of its report, as one receipt row. */
function sharedKitRun(context: Context, operation: string, shared: SharedKit,
  base: { extension: string; version: string; guestSha256: Sha256 }, host: (evidence: string) => SharedKitHost) {
  const { ledger, platform } = context;
  const native = context.clis.find(cli => cli.name === 'native')!;
  const evidence = mkdtempSync(join(context.scratch, `mck-${operation}-`));
  ledger.step({ ...base, cli: 'mck', operation }, () => {
    const { runner, archiveSha256 } = mckRunner(platform);
    const report = join(evidence, 'report.json');
    const launched = host(evidence);
    const args = ['--no-banner', 'mck', 'mep', 'guest-run', '--kit', shared.path, '--expect-kit-sha256', shared.sha256, '--report', report,
      '--host', launched.program, ...launched.args.flatMap(value => ['--host-arg', value]),
      ...launched.identityFiles.flatMap(path => ['--identity-file', path])];
    const environment = process.platform === 'win32' ? { ...native.env } : { PATH: '', MOON_HOME: '', HOME: evidence };
    const guestRun = spawnSync(runner, args, { cwd: evidence, env: environment, encoding: 'utf8', timeout: 600000 });
    const observed = existsSync(report) ? JSON.parse(readFileSync(report, 'utf8')) : undefined;
    const cases = observed?.records?.map((record: { caseId: string }) => record.caseId) ?? [];
    const detail = `runner ${published.mck.tag} archive ${archiveSha256}; kit ${shared.sha256}; profile ${shared.value.profile}; ${cases.length} cases`;
    assert.equal(guestRun.status, 0, `${detail}; ${observed?.error ?? guestRun.stderr.slice(-2000)}; cases ${cases.join(', ')}`);
    const recheck = spawnSync(runner, ['--no-banner', 'mck', 'mep', 'report-check', '--kit', shared.path, report],
      { cwd: evidence, env: environment, encoding: 'utf8', timeout: 600000 });
    assert.equal(recheck.status, 0, recheck.stderr.slice(-2000));
    assert.equal(observed.qualified, true);
    assert.equal(observed.corpusSha256, shared.sha256);
    return { detail, outputs: [{ path: 'report.json', bytes: statSync(report).size, sha256: sha256(report) }] };
  });
}

/**
 * IR in the form that the generic kit compares: object members in any order
 * (`deepEqual` does not read their order) and the IR 3 `modules`, `types` and
 * `values` lists in any order. Everything else must be equal.
 */
export function irMeaning(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(irMeaning);
  if (value === null || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).map(([key, member]) => {
    const meaning = irMeaning(member);
    return [key, ['modules', 'types', 'values'].includes(key) && Array.isArray(meaning)
      ? [...meaning].sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right))) : meaning];
  }));
}

/**
 * The generic kit's source, malformed source and expected IR through the public
 * commands of one CLI. The npm CLI has no worker mode for the shared runner to
 * launch, so this comparison with the kit's expected output is its kit run; the
 * kit fixes no generated bytes, so generated files must compile back to that IR.
 */
function genericKitRows(context: Context, cli: Cli, shared: SharedKit, pin: string, directory: string,
  base: { extension: string; version: string; guestSha256: Sha256 }, mine: Record<string, Record<string, Sha256>>) {
  const { ledger } = context;
  const language = shared.value.languages['morphir-fixture-flags'];
  const expected = irMeaning(shared.value.expectedIrVersions['3.0.0']);
  const packageName: string = shared.value.package.name;
  const model = (path: string) => irMeaning(JSON.parse(readFileSync(join(directory, path, 'morphir-ir.json'), 'utf8')));
  const write = (folder: string, documents: { uri: string; text: string }[]) => {
    mkdirSync(join(directory, folder));
    for (const document of documents) writeFileSync(join(directory, folder, document.uri), document.text);
  };
  const profile = `${shared.value.profile} ${shared.sha256}`;
  write('kit-src', language.documents);
  const compiled = ledger.step({ ...base, cli: cli.name, operation: 'generic-kit-compile' }, () => {
    const report = command(cli, ['extension', 'compile', 'kit-src', '--package', packageName, '--ir-version', '3',
      '--output', 'kit-model', '--extension-pin', pin], directory, 0);
    assert.deepEqual(model('kit-model'), expected, 'the compiled IR differs from the kit');
    mine.kitModel = treeDigests(join(directory, 'kit-model'));
    return { detail: profile, outputs: outputs(join(directory, 'kit-model'), report.result.output.files) };
  });
  if (compiled) {
    ledger.step({ ...base, cli: cli.name, operation: 'generic-kit-generate-roundtrip' }, () => {
      const report = command(cli, ['extension', 'generate', 'kit-model/morphir-ir.json', '--output', 'kit-generated',
        '--extension-pin', pin], directory, 0);
      command(cli, ['extension', 'compile', 'kit-generated', '--package', packageName, '--ir-version', '3',
        '--output', 'kit-again', '--extension-pin', pin], directory, 0);
      assert.deepEqual(model('kit-again'), expected, 'the generated files compile to other IR');
      mine.kitGenerated = treeDigests(join(directory, 'kit-generated'));
      return { detail: profile, outputs: outputs(join(directory, 'kit-generated'), report.result.output.files) };
    });
  }
  ledger.step({ ...base, cli: cli.name, operation: 'generic-kit-independent-generate-roundtrip' }, () => {
    writeFileSync(join(directory, 'kit-ir3.json'), JSON.stringify(shared.value.expectedIrVersions['3.0.0']));
    const report = command(cli, ['extension', 'generate', 'kit-ir3.json', '--output', 'kit-independent',
      '--extension-pin', pin], directory, 0);
    command(cli, ['extension', 'compile', 'kit-independent', '--package', packageName, '--ir-version', '3',
      '--output', 'kit-independent-again', '--extension-pin', pin], directory, 0);
    assert.deepEqual(model('kit-independent-again'), expected, 'the generated files compile to other IR');
    mine.kitIndependent = treeDigests(join(directory, 'kit-independent'));
    return { detail: profile, outputs: outputs(join(directory, 'kit-independent'), report.result.output.files) };
  });
  write('kit-malformed', language.malformed);
  ledger.step({ ...base, cli: cli.name, operation: 'generic-kit-malformed-source' }, () => {
    const report = command(cli, ['extension', 'compile', 'kit-malformed', '--package', packageName, '--ir-version', '3',
      '--output', 'kit-refused', '--extension-pin', pin], directory, 1);
    assert.equal(report.error.code, 'extension.operation_unsuccessful');
    assert.equal(existsSync(join(directory, 'kit-refused')), false);
    return { detail: profile };
  });
}

/** The SDK fixture guest: the shared generic kit and the local conformance check (task 7.4). */
function conformanceSuite(context: Context) {
  const { ledger } = context;
  const root = join(fixtures, 'sdk-guest');
  const receipt = JSON.parse(readFileSync(join(root, 'build-receipt.json'), 'utf8'));
  const artifact = join(root, receipt.artifact.path);
  const base = { extension: 'morphir-sdk-fixture', version: '0.1.0', guestSha256: sha256(artifact) };
  const shared = kit('guest-generic-json');
  context.notes.sharedKit = `The shared kit ${shared.value.profile} (${shared.sha256}) runs through morphir extension worker of the native CLI; both CLIs compare the kit's source, malformed source and expected IR through their public commands. The local checks stay.`;
  context.notes.hostChange = 'None: the guest runs on the worker host as it is on main.';
  sharedKitRun(context, 'shared-generic-kit-native-cli-worker-mode', shared, base, evidence => workerModeHost(context, 'extism-kernel-v1', artifact, evidence));
  ledger.step({ ...base, cli: 'native', operation: 'build-receipt' }, () => {
    assert.equal(base.guestSha256, receipt.artifact.sha256, 'the stored module differs from its build receipt');
    for (const [path, digest] of Object.entries(receipt.sources as Record<string, string>)) {
      assert.equal(sha256(join(root, path)), digest, `${path} differs from the build receipt`);
    }
    return { detail: `${receipt.sdk.crate} ${receipt.sdk.revision}; ${receipt.toolchain.rustc}; ${receipt.toolchain.target}` };
  });
  ledger.step({ ...base, cli: 'native', operation: 'imports' }, () => {
    const imports = wasmImports(readFileSync(artifact));
    assert.deepEqual(imports, receipt.imports);
    const modules = [...new Set(imports.map(name => name.slice(0, name.lastIndexOf('.'))))].sort();
    assert.deepEqual(modules, ['extism:host/env', 'extism:host/user', 'wasi_snapshot_preview1']);
    for (const name of ['morphir_get_workspace_info', 'morphir_cache_ir', 'morphir_get_cached_ir', 'morphir_log']) {
      assert.ok(imports.includes(`extism:host/user.${name}`), name);
    }
    return { detail: `${imports.filter(name => name.startsWith('wasi_')).length} WASI and 4 Morphir host function imports` };
  });
  const pin = writePin(join(context.scratch, 'sdk-fixture-pin.json'),
    wasmPin(artifact, 'extism-kernel-v1', 'finos/morphir-moonbit apps/morphir/fixtures/sdk-guest'));
  const results: Record<string, Record<string, Record<string, Sha256>>> = {};
  for (const cli of context.clis) {
    const directory = mkdtempSync(join(context.scratch, `sdk-${cli.name}-`));
    mkdirSync(join(directory, 'src'));
    writeFileSync(join(directory, 'src/rules.flags'), '# fixture\nready = true\nblockedNow = false\n');
    writeFileSync(join(directory, 'src/extra.flags'), 'enabled = true\n');
    writeFileSync(join(directory, 'src/ignored.txt'), 'not a claimed source file\n');
    const mine: Record<string, Record<string, Sha256>> = {};
    results[cli.name] = mine;
    ledger.step({ ...base, cli: cli.name, operation: 'describe-classify' }, () => {
      const result = described(command(cli, ['extension', 'describe', '--extension-pin', pin], directory, 0), 'morphir-sdk-fixture', '0.1.0', 'wasm');
      assert.equal(result.worker.runtime.abi, 'extism-kernel-v1');
      assert.deepEqual(result.claims.languages, [{ id: 'morphir-fixture-flags', fileExtensions: ['.flags'] }]);
      return { detail: `operations ${result.claims.operations.join(', ')}` };
    });
    ledger.step({ ...base, cli: cli.name, operation: 'compile-claimed-sources' }, () => {
      const report = command(cli, ['extension', 'compile', 'src', '--package', 'acme/flags', '--output', 'model',
        '--extension-pin', pin], directory, 0);
      const host = report.diagnostics.find((d: { code?: string }) => d.code === 'fixture.host');
      assert.ok(host, 'the guest reported no host observation');
      assert.deepEqual(JSON.parse(host.message), {
        cacheRoundTrip: true, morphirLog: true, wasiArguments: 0, wasiClock: true, wasiEnvironment: 0, wasiRandomSeed: true, workspaceRoot: true,
      });
      const ir = JSON.parse(readFileSync(join(directory, 'model/morphir-ir.json'), 'utf8'));
      const modules = ir.distribution[3].modules.map((module: any) => module[0]);
      assert.deepEqual(modules, [[['extra']], [['rules']]], 'the .txt file is not a claimed source');
      mine.model = treeDigests(join(directory, 'model'));
      return { detail: host.message, outputs: outputs(join(directory, 'model'), report.result.output.files) };
    });
    ledger.step({ ...base, cli: cli.name, operation: 'generate-and-recompile' }, () => {
      const report = command(cli, ['extension', 'generate', 'model/morphir-ir.json', '--output', 'generated',
        '--extension-pin', pin], directory, 0);
      assert.equal(readFileSync(join(directory, 'generated/rules.flags'), 'utf8'), 'ready = true\nblocked_now = false\n');
      command(cli, ['extension', 'compile', 'generated', '--package', 'acme/flags', '--output', 'again', '--extension-pin', pin], directory, 0);
      assert.deepEqual(readFileSync(join(directory, 'again/morphir-ir.json')), readFileSync(join(directory, 'model/morphir-ir.json')));
      mine.generated = treeDigests(join(directory, 'generated'));
      return { outputs: outputs(join(directory, 'generated'), report.result.output.files) };
    });
    ledger.step({ ...base, cli: cli.name, operation: 'guest-diagnostics' }, () => {
      writeFileSync(join(directory, 'broken.flags'), 'ready = maybe\n');
      const report = command(cli, ['extension', 'compile', 'broken.flags', '--package', 'acme/flags', '--output', 'broken',
        '--extension-pin', pin], directory, 1);
      assert.equal(report.error.code, 'extension.operation_unsuccessful');
      assert.ok(report.diagnostics.some((d: { code?: string }) => d.code === 'fixture.syntax'));
      assert.equal(existsSync(join(directory, 'broken')), false);
    });
    genericKitRows(context, cli, shared, pin, directory, base, mine);
  }
  const { native: nativeOutputs, npm: npmOutputs } = results;
  if (nativeOutputs && npmOutputs) {
    ledger.step({ ...base, cli: 'npm', operation: 'same-output-as-native' }, () => assert.deepEqual(npmOutputs, nativeOutputs));
  }
}

/** The names of the function imports of a WASM module, `module.name`, in order. */
export function wasmImports(bytes: Buffer): string[] {
  assert.deepEqual([...bytes.subarray(0, 4)], [0, 0x61, 0x73, 0x6d], 'not a WASM module');
  let offset = 8;
  const leb = () => {
    let result = 0, shift = 0, byte = 0;
    do { byte = bytes[offset++]!; result += (byte & 0x7f) * 2 ** shift; shift += 7; } while (byte & 0x80);
    return result;
  };
  const text = () => { const length = leb(); const value = bytes.subarray(offset, offset + length).toString('utf8'); offset += length; return value; };
  const names: string[] = [];
  while (offset < bytes.length) {
    const id = bytes[offset++];
    const size = leb();
    const end = offset + size;
    if (id === 2) {
      for (let count = leb(); count > 0; count--) {
        const module = text(), name = text();
        assert.equal(bytes[offset++], 0, `${module}.${name} is not a function import`);
        leb();
        names.push(`${module}.${name}`);
      }
    }
    offset = end;
  }
  return names;
}

// ---------------------------------------------------------------------------

const suites = {
  elm: elmSuite, python: pythonSuite, conformance: conformanceSuite,
  'moonbit-native': (context: Context) => moonbitSuite(context, 'native'),
  'moonbit-portable': (context: Context) => moonbitSuite(context, 'portable'),
} as const;
type SuiteName = keyof typeof suites;

export function main(args: string[]) {
  const { values } = parseArgs({
    args, strict: true, allowPositionals: false,
    options: Object.fromEntries(['suite', 'evidence', 'native', 'npm-entry', 'python', 'portable', 'native-guest']
      .map(name => [name, { type: 'string' as const }])),
  });
  const suite = values.suite as SuiteName;
  assert.ok(suite in suites, `--suite must be one of ${Object.keys(suites).join(', ')}`);
  const { evidence, native, 'npm-entry': npmEntry } = values;
  assert.ok(evidence && native && npmEntry, '--evidence, --native and --npm-entry are required');
  mkdirSync(evidence, { recursive: true });
  const platform = hostPlatform();
  const scratch = realpathSync(mkdtempSync(join(realpathSync(evidence), `${suite}-`)));
  const home = join(scratch, 'home');
  mkdirSync(home);
  const ledger = new Ledger(platform);
  const context: Context = {
    ledger, platform, scratch, clis: clis(realpathSync(native), realpathSync(npmEntry), home),
    python: values.python, portable: values.portable, nativeGuest: values['native-guest'], notes: {},
  };
  let error: string | undefined;
  try { suites[suite](context); } catch (failure) { error = failure instanceof Error ? failure.message : String(failure); log(error); }
  const failed = error !== undefined || ledger.rows.some(row => row.result === 'failed');
  const receipt = {
    profile: 'morphir/extension-qualification', contractVersion: '0.1.0', suite,
    state: failed ? 'failed' : 'passed', platform,
    cli: Object.fromEntries(context.clis.map(cli => [cli.name, cli.build])),
    ...(error ? { error } : {}), notes: context.notes, rows: ledger.rows,
  };
  const path = join(evidence, `${suite}.json`);
  writeFileSync(path, `${JSON.stringify(receipt, null, 2)}\n`);
  log(`${suite}: ${receipt.state}; receipt ${path}`);
  return failed ? 1 : 0;
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  process.exitCode = main(process.argv.slice(2));
}
