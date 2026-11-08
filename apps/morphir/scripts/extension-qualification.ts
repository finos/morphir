// Qualification of published and fixture extensions on the CLI's worker host.
//
//   node apps/morphir/scripts/extension-qualification.ts --suite <suite> --evidence <dir>
//     --native <morphir executable> --npm-entry <unpacked package/bin/morphir.js>
//     [--python <Python 3.12 or later>] [--portable <directory with model.wasm>]
//     [--native-guest <MoonBit guest executable>]
//
// Suites: elm (task 7.1), python (7.2 and 7.7), moonbit-native and moonbit-portable (7.3),
// conformance (7.4, with the shared generic kit), model-line (7.8: avro, openapi and rust on
// MEP 0.2.0-draft.1). `scripts/extension-qualification.mbtx` builds the inputs and
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

/**
 * How long one command may run before the driver kills it: the probe and the
 * operation session each have the session deadline. A CLI that finished its
 * work and did not exit by itself fails its row here.
 */
const exitBoundMs = 2 * sessionDeadlineMs;

function run(cli: Cli, args: string[], cwd: string, timeout = 240000): Run {
  const started = performance.now();
  const child: SpawnSyncReturns<string> = spawnSync(cli.command, [...cli.prefix, ...args],
    { cwd, env: cli.env, encoding: 'utf8', timeout, killSignal: 'SIGKILL', maxBuffer: 64 * 1024 * 1024 });
  const elapsedMs = Math.round(performance.now() - started);
  const result: Run = { status: child.status, stdout: child.stdout ?? '', stderr: child.stderr ?? '', elapsedMs };
  if (args.includes('--json')) {
    try { result.report = JSON.parse(result.stdout); } catch { /* the assertion below names it */ }
    assert.ok(result.report, `${cli.name} ${args.join(' ')} exited ${result.status} after ${elapsedMs} ms (bound ${timeout} ms); stdout is not one JSON document:\n${result.stdout}\n${result.stderr}`);
  }
  return result;
}

/** Runs one command in JSON mode and checks its exit status and report. */
function command(cli: Cli, args: string[], cwd: string, expected: number): any {
  return timedCommand(cli, args, cwd, expected).report;
}

/** As `command`, and also returns the command's wall-clock duration. */
function timedCommand(cli: Cli, args: string[], cwd: string, expected: number, timeout?: number): { report: any; elapsedMs: number } {
  const result = run(cli, [...args, '--json'], cwd, timeout);
  const tail = `${result.stdout}\n${result.stderr.slice(-4000)}`;
  assert.equal(result.status, expected,
    `${cli.name} ${args.join(' ')} exited ${result.status} after ${result.elapsedMs} ms (session deadline ${sessionDeadlineMs} ms):\n${tail}`);
  assert.equal(result.report.profile, 'morphir/command-result', tail);
  assert.equal(result.report.contractVersion, '0.1.0', tail);
  assert.equal(result.report.exitCode, expected, tail);
  assert.equal(result.report.state, expected === 0 ? 'succeeded' : 'failed', tail);
  return { report: result.report, elapsedMs: result.elapsedMs };
}

/**
 * As `command`, and the CLI must exit by itself within `exitBoundMs`. A command
 * that started a worker must report that it stopped, and an operation session
 * must report an acknowledged shutdown.
 */
function boundedCommand(cli: Cli, args: string[], cwd: string, expected: number): any {
  const { report, elapsedMs } = timedCommand(cli, args, cwd, expected, exitBoundMs);
  assert.ok(elapsedMs < exitBoundMs, `${cli.name} ${args.join(' ')} took ${elapsedMs} ms of the ${exitBoundMs} ms bound`);
  const lifecycle = report.result?.lifecycle;
  if (lifecycle) {
    // Describe is a probe: it ends with morphir.exit and has no operation session to shut down.
    if (args[1] !== 'describe') assert.equal(lifecycle.shutdown, 'acknowledged', `${args.join(' ')}: shutdown`);
    assert.equal(lifecycle.workerStopped, true, `${args.join(' ')}: worker stopped`);
  }
  return report;
}

// ---------------------------------------------------------------------------
// Receipts

interface Row {
  extension: string;
  version: string;
  /** `mck` is the shared kit runner; `worker` is a session that this driver holds directly with the guest's worker. */
  cli: CliName | 'mck' | 'worker';
  platform: Platform;
  operation: string;
  result: RowResult;
  guestSha256: Sha256;
  descriptorSha256?: Sha256;
  /** The agreed model tuple, `profile/codec/envelope/IR`, when the row negotiated one. */
  tuple?: string;
  /** Wall-clock time of the row. */
  elapsedMs?: number;
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
    const started = performance.now();
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
    row.elapsedMs = Math.round(performance.now() - started);
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

/** The JSON model tuple of one operation at one IR major, as the published model-line extensions claim it. */
const jsonModelTuple = (operation: string, ir: string) => ({
  operation, profile: 'morphir-ir', codec: 'morphir-json', envelopeVersion: '0.1.0-draft.1', irVersion: `${ir}.0.0`,
});

/** Model tuples in a stable order, so that a comparison does not read the claim's order. */
const sortedTuples = (tuples: object[]) => tuples.map(item => JSON.stringify(item, Object.keys(item).sort())).sort();

/** The agreed tuple of a command report, for the receipt row. */
function tupleLabel(report: any): string {
  const { profile, codec, envelopeVersion, irVersion } = report.result.negotiated.tuple;
  return `${profile}/${codec}/${envelopeVersion}/${irVersion}`;
}

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

/**
 * Python extension 0.4.1 and 0.4.2: extism-kernel-v1 WASM workers (task 7.2);
 * 0.5.0 and 0.6.0: the model line. The suite keeps every qualified release.
 */
function pythonSuite(context: Context) {
  for (const version of ['0.6.0', '0.5.0']) {
    for (const runtime of ['wasm', 'process'] as const) pythonModelGuest(context, version, runtime);
  }
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
 * Python extension 0.5.0 (bead morphir-ukvn.5.64.36.23) and 0.6.0 (bead
 * morphir-ukvn.5.64.36.28) on the model line: each claims MEP 0.2.0-draft.1 and
 * 0.1 and JSON tuples at IR 3.0.0 and 4.0.0, as a WASM worker and as a process
 * worker. Compile and generate at each IR version, from both CLIs;
 * `formatVersion` of the published model follows the tuple.
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
  const tuple = jsonModelTuple;
  for (const ir of ['3', '4']) {
    ledger.step({ ...base, cli: 'worker', operation: `mep-0.1-compile-and-generate-ir${ir}` }, () => {
      const host = runtime === 'wasm' ? wasmWorker(context, artifact) : { program: artifact, args: [] };
      const text = readFileSync(join(fixtures, 'extism-python/v1/single/rules.py'), 'utf8');
      const [compiled] = mep01Session(context, host, [{ method: 'morphir.frontend.compile', params: {
        languageId: 'python', sources: { documents: [{ uri: 'rules.py', languageId: 'python', version: 0, text }] },
        package: { name: 'acme/rules' }, options: { typesOnly: false, irVersion: ir },
      } }]);
      assert.equal(compiled?.result?.success, true, JSON.stringify(compiled).slice(0, 2000));
      assert.equal(compiled.result.ir.formatVersion, Number(ir));
      const [generated, model] = mep01Session(context, host, [
        { method: 'morphir.backend.generate', params: { ir: compiled.result.ir, target: 'python', options: {} } },
        { method: 'morphir.backend.generateModel', params: { target: 'python' } },
      ]);
      assertNoModelMethod(model);
      return { detail: `formatVersion ${ir}; ${mep01Note}`, outputs: mep01Artifacts(generated).outputs };
    });
  }
  const results: Record<string, Record<string, Record<string, Sha256>>> = {};
  for (const cli of context.clis) {
    const directory = mkdtempSync(join(context.scratch, `python-${version}-${runtime}-${cli.name}-`));
    cpSync(join(fixtures, 'extism-python/v1/acme'), join(directory, 'src/acme'), { recursive: true });
    const mine: Record<string, Record<string, Sha256>> = {};
    results[cli.name] = mine;
    ledger.step({ ...base, cli: cli.name, operation: 'describe' }, () => {
      const result = described(boundedCommand(cli, ['extension', 'describe', '--extension-pin', pin], directory, 0), 'morphir-python', version, runtime);
      assert.equal(result.worker.descriptorSha256, descriptorAsset.sha256);
      assert.deepEqual([...result.claims.protocolVersions].sort(), ['0.1', '0.2.0-draft.1']);
      assert.deepEqual(sortedTuples(result.claims.modelTuples), sortedTuples(['morphir.frontend.compileModel', 'morphir.backend.generateModel']
        .flatMap(operation => ['3', '4'].map(ir => tuple(operation, ir)))));
      return { detail: `model tuples ${result.claims.modelTuples.length}` };
    });
    for (const ir of ['3', '4']) {
      const model = `model-v${ir}`, generated = `generated-v${ir}`, again = `again-v${ir}`;
      const compiled = ledger.step({ ...base, cli: cli.name, operation: `compile-model-ir${ir}` }, () => {
        const report = boundedCommand(cli, ['extension', 'compile', 'src', '--package', 'acme/rules', '--ir-version', ir,
          '--output', model, '--extension-pin', pin], directory, 0);
        assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
        assert.deepEqual(report.result.negotiated.tuple, tuple('morphir.frontend.compileModel', ir));
        assert.deepEqual(report.result.output.files.map((file: { path: string }) => file.path), ['model-envelope.json', 'model.json']);
        const envelope = JSON.parse(readFileSync(join(directory, model, 'model-envelope.json'), 'utf8'));
        assert.equal(envelope.irVersion, `${ir}.0.0`);
        const formatVersion = JSON.parse(readFileSync(join(directory, model, 'model.json'), 'utf8')).formatVersion;
        assert.equal(formatVersion, Number(ir));
        mine[model] = treeDigests(join(directory, model));
        return { tuple: tupleLabel(report), outputs: outputs(join(directory, model), report.result.output.files), detail: `formatVersion ${formatVersion}` };
      });
      if (!compiled) continue;
      const generatedOk = ledger.step({ ...base, cli: cli.name, operation: `generate-model-ir${ir}` }, () => {
        const report = boundedCommand(cli, ['extension', 'generate', join(model, 'model-envelope.json'), '--ir-version', ir,
          '--output', generated, '--extension-pin', pin], directory, 0);
        assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
        assert.deepEqual(report.result.negotiated.tuple, tuple('morphir.backend.generateModel', ir));
        mine[generated] = treeDigests(join(directory, generated));
        return { tuple: tupleLabel(report), outputs: outputs(join(directory, generated), report.result.output.files) };
      });
      if (!generatedOk) continue;
      // Plain IR goes on the model line too: the host wraps the bytes of model.json.
      ledger.step({ ...base, cli: cli.name, operation: `generate-plain-ir${ir}` }, () => {
        const plain = `plain-v${ir}`;
        const report = boundedCommand(cli, ['extension', 'generate', join(model, 'model.json'), '--output', plain,
          '--extension-pin', pin], directory, 0);
        assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
        assert.deepEqual(report.result.negotiated.tuple, tuple('morphir.backend.generateModel', ir));
        assert.deepEqual(treeDigests(join(directory, plain)), mine[generated], 'plain IR and its envelope generate differently');
        mine[plain] = treeDigests(join(directory, plain));
        return { tuple: tupleLabel(report), outputs: outputs(join(directory, plain), report.result.output.files) };
      });
      ledger.step({ ...base, cli: cli.name, operation: `consumer-ir${ir}` }, () => {
        assert.ok(python, 'no Python 3.12 or later for the consumer check; pass --python');
        const check = spawnSync(python, ['-I', join(repository, 'apps/morphir/scripts/extension-qualification-consumer.py'),
          join(directory, generated)], { encoding: 'utf8', timeout: 60000 });
        assert.equal(check.status, 0, `${check.stdout}\n${check.stderr}`);
        return { detail: check.stdout.trim() };
      });
      ledger.step({ ...base, cli: cli.name, operation: `recompile-generated-ir${ir}` }, () => {
        boundedCommand(cli, ['extension', 'compile', generated, '--package', 'acme/rules', '--ir-version', `${ir}.0.0`,
          '--output', again, '--extension-pin', pin], directory, 0);
        assert.deepEqual(JSON.parse(readFileSync(join(directory, again, 'model.json'), 'utf8')),
          JSON.parse(readFileSync(join(directory, model, 'model.json'), 'utf8')));
      });
      ledger.step({ ...base, cli: cli.name, operation: `refuse-ir-version-mismatch-ir${ir}` }, () => {
        const report = boundedCommand(cli, ['extension', 'generate', join(model, 'model-envelope.json'), '--ir-version', ir === '3' ? '4' : '3',
          '--output', `mismatch-v${ir}`, '--extension-pin', pin], directory, 2);
        assert.equal(report.error.code, 'extension.ir_version_mismatch');
        assert.equal(existsSync(join(directory, `mismatch-v${ir}`)), false);
      });
    }
    ledger.step({ ...base, cli: cli.name, operation: 'default-ir' }, () => {
      const report = boundedCommand(cli, ['extension', 'compile', 'src', '--package', 'acme/rules', '--output', 'default',
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
        const report = boundedCommand(cli, ['extension', 'compile', 'src', '--package', 'acme/rules', ...flags,
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

/** One generate target of a model-line extension, and what its output must hold. */
interface ModelLineTarget {
  id: string;
  /** The output files of the input model, sorted. */
  files: string[];
  /** Checks the generated directory, and says what it found. */
  check: (output: string) => string;
}

/** A model input of generate: the file names in the working directory. */
interface GenerateInput { label: string; plain: string; envelope: string }

/**
 * The two forms of the same model, written in a new directory: plain IR, and an
 * envelope around those bytes. The IR stays text: its integer literals can be
 * larger than a JavaScript number.
 */
function writeModelForms(directory: string, stem: string, ir: string, irVersion: string, modelId: string): GenerateInput {
  const plain = `${stem}.json`, envelope = `${stem}-envelope.json`;
  writeFileSync(join(directory, plain), ir);
  writeFileSync(join(directory, envelope), JSON.stringify(modelEnvelope(ir, irVersion, modelId)));
  return { label: stem, plain, envelope };
}

/**
 * Generate of one IR 4 model from one CLI: the plain IR file, which the host
 * wraps for `morphir.backend.generateModel`, then an independent envelope around
 * the same IR, which must generate the same files.
 */
function generateRows(context: Context, cli: Cli, base: Omit<Row, 'result' | 'platform' | 'cli' | 'operation'>, pin: string,
  directory: string, mine: Record<string, Record<string, Sha256>>, input: GenerateInput, target: ModelLineTarget, targetFlag: string[]) {
  const { ledger } = context;
  const suffix = `${input.label}-${target.id}`;
  const generateFrom = (file: string, output: string) => {
    assert.equal(JSON.parse(readFileSync(join(directory, input.plain), 'utf8')).formatVersion, 4, 'the input is IR 4');
    const report = boundedCommand(cli, ['extension', 'generate', file, ...targetFlag, '--output', output, '--extension-pin', pin], directory, 0);
    assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
    assert.deepEqual(report.result.negotiated.tuple, jsonModelTuple('morphir.backend.generateModel', '4'));
    assert.deepEqual(report.result.output.files.map((file: { path: string }) => file.path).sort(), target.files, 'the generated files');
    return report;
  };
  const plainOutput = `plain-${suffix}`, envelopeOutput = `envelope-${suffix}`;
  ledger.step({ ...base, cli: cli.name, operation: `generate-plain-ir4-${suffix}` }, () => {
    const report = generateFrom(input.plain, plainOutput);
    const detail = target.check(join(directory, plainOutput));
    mine[plainOutput] = treeDigests(join(directory, plainOutput));
    return { tuple: tupleLabel(report), detail: `formatVersion 4; ${detail}`, outputs: outputs(join(directory, plainOutput), report.result.output.files) };
  });
  ledger.step({ ...base, cli: cli.name, operation: `generate-envelope-ir4-${suffix}` }, () => {
    const report = generateFrom(input.envelope, envelopeOutput);
    const digests = treeDigests(join(directory, envelopeOutput));
    assert.deepEqual(digests, mine[plainOutput], 'plain IR and its envelope generate differently');
    mine[envelopeOutput] = digests;
    return { tuple: tupleLabel(report), detail: 'the same files as the plain IR', outputs: outputs(join(directory, envelopeOutput), report.result.output.files) };
  });
}

/**
 * Checks the legacy MEP 0.1 fallback of one command (bead
 * morphir-ukvn.5.64.36.31): the guest claims both lines and no model tuple that
 * matches, so the command runs on MEP 0.1 with the legacy method, warns with
 * `extension.legacy_mep_fallback` and has no negotiated tuple. Returns the warning.
 */
function legacyFallback(report: any, method: string): string {
  assert.equal(report.result.protocolVersion, '0.1');
  assert.equal(report.result.negotiated?.tuple, undefined, 'MEP 0.1 has no model tuple');
  const warning = report.diagnostics.find((item: { code?: string }) => item.code === 'extension.legacy_mep_fallback');
  assert.ok(warning, `no extension.legacy_mep_fallback warning: ${JSON.stringify(report.diagnostics)}`);
  assert.equal(warning.severity, 'warning');
  assert.equal(warning.data.operation, method);
  assert.equal(warning.data.protocolVersion, '0.1');
  return warning.message;
}

/**
 * IR 3 for a guest whose tuples are IR 4.0.0 only and whose backend claims IR 3
 * on MEP 0.1: plain IR 3 and an IR 3 envelope generate on MEP 0.1 with the
 * fallback warning, and give the same files. `--ir-version 3` on an IR 4 model is
 * still a mismatch.
 */
function ir3FallbackRows(context: Context, cli: Cli, base: Omit<Row, 'result' | 'platform' | 'cli' | 'operation'>, pin: string,
  directory: string, mine: Record<string, Record<string, Sha256>>, irInput: GenerateInput, targetFlag: string[],
  ir3: GenerateInput | undefined, check?: (output: string) => string) {
  const { ledger } = context;
  if (ir3) {
    const suffix = `${ir3.label}${targetFlag.length ? `-${targetFlag[1]}` : ''}`;
    for (const [form, file] of [['plain', ir3.plain], ['envelope', ir3.envelope]] as const) {
      const output = `${form}-${suffix}`;
      ledger.step({ ...base, cli: cli.name, operation: `generate-${form}-ir3-legacy-fallback-${suffix}` }, () => {
        assert.equal(JSON.parse(readFileSync(join(directory, ir3.plain), 'utf8')).formatVersion, 3, 'the input is IR 3');
        const report = boundedCommand(cli, ['extension', 'generate', file, ...targetFlag, '--output', output, '--extension-pin', pin], directory, 0);
        const warning = legacyFallback(report, 'morphir.backend.generate');
        assert.ok(report.result.output.files.length > 0, 'no files');
        const digests = treeDigests(join(directory, output));
        if (form === 'envelope') assert.deepEqual(digests, mine[`plain-${suffix}`], 'plain IR 3 and its envelope generate differently');
        mine[output] = digests;
        const checked = check ? `; ${check(join(directory, output))}` : '';
        return { detail: `formatVersion 3; MEP 0.1 with the warning: ${warning}${checked}`, outputs: outputs(join(directory, output), report.result.output.files) };
      });
    }
  }
  ledger.step({ ...base, cli: cli.name, operation: 'refuse-ir-version-mismatch' }, () => {
    const report = boundedCommand(cli, ['extension', 'generate', irInput.plain, ...targetFlag, '--ir-version', '3', '--output', 'mismatch', '--extension-pin', pin], directory, 2);
    assert.equal(report.error.code, 'extension.ir_version_mismatch');
    assert.equal(existsSync(join(directory, 'mismatch')), false);
    return { detail: report.error.message };
  });
}

/**
 * Envelopes that are wrong in one way each, around valid IR 4: the owners'
 * `a_wrong_envelope_is_refused` tests, through the CLI. The host refuses what it
 * can check; the guest refuses a digest or a `formatVersion` that disagrees. No
 * refusal publishes a file.
 */
function wrongEnvelopeRows(context: Context, cli: Cli, base: Omit<Row, 'result' | 'platform' | 'cli' | 'operation'>, pin: string,
  directory: string, ir: string, targetFlag: string[]) {
  const envelope = () => modelEnvelope(ir, '4.0.0', 'urn:morphir:qualification:wrong');
  const cases: { operation: string; model: unknown; status: number; code: string; message?: RegExp }[] = [
    { operation: 'refuse-envelope-version', model: { ...envelope(), envelopeVersion: '0.2.0' }, status: 2, code: 'extension.input_invalid' },
    { operation: 'refuse-envelope-profile', model: { ...envelope(), profile: 'morphir-model' }, status: 2, code: 'extension.tuple_unavailable' },
    { operation: 'refuse-envelope-ion-tuple', model: { ...envelope(), profile: 'morphir-model', payload: { ...envelope().payload, codec: 'ion-binary' } }, status: 2, code: 'extension.tuple_unavailable' },
    { operation: 'refuse-envelope-length', model: { ...envelope(), payload: { ...envelope().payload, decodedByteLength: 1 } }, status: 2, code: 'extension.request_limit' },
    { operation: 'refuse-envelope-digest', model: { ...envelope(), payload: { ...envelope().payload, sha256: '1'.repeat(64) } }, status: 1, code: 'extension.guest_error', message: /digest_mismatch/ },
    { operation: 'refuse-envelope-format-version', model: modelEnvelope(withFormatVersion(ir, 3), '4.0.0', 'urn:morphir:qualification:wrong'), status: 1, code: 'extension.guest_error', message: /unsupported_ir_version/ },
  ];
  for (const { operation, model, status, code, message } of cases) {
    context.ledger.step({ ...base, cli: cli.name, operation }, () => {
      const file = `${operation}.json`;
      writeFileSync(join(directory, file), JSON.stringify(model));
      const report = boundedCommand(cli, ['extension', 'generate', file, ...targetFlag, '--output', operation, '--extension-pin', pin], directory, status);
      assert.equal(report.error.code, code, report.error.message);
      if (message) assert.match(report.error.message, message);
      assert.equal(existsSync(join(directory, operation)), false);
      assert.equal(existsSync(join(directory, `${operation}.morphir-partial`)), false);
      return { detail: report.error.message };
    });
  }
}

/** The IR 4 pricing model that the repository owns and no extension compiled, with LF line endings on every checkout. */
const pricingIr = () => readFileSync(join(repository, 'apps/morphir-workbench/fixtures/typed-pricing.json'), 'utf8').replace(/\r\n/g, '\n');

/** The same text with another `formatVersion`. */
function withFormatVersion(ir: string, formatVersion: number): string {
  const changed = ir.replace(/"formatVersion"\s*:\s*\d+/, `"formatVersion": ${formatVersion}`);
  assert.equal(JSON.parse(changed).formatVersion, formatVersion);
  return changed;
}

/** The new, empty working directory of one extension and CLI, with the pricing model at IR 4 and the owner's model at IR 3. */
function modelLineDirectory(context: Context, id: string, cli: Cli) {
  const directory = mkdtempSync(join(context.scratch, `${id}-${cli.name}-`));
  const ir = pricingIr();
  assert.equal(JSON.parse(ir).formatVersion, 4);
  return {
    directory,
    pricing: writeModelForms(directory, 'pricing', ir, '4.0.0', 'urn:morphir:qualification:pricing'),
    classicIr3: writeModelForms(directory, 'classic-ir3', ownerGolden('classic-schema-library-v3.json'), '3.0.0', 'urn:morphir:qualification:classic-ir3'),
  };
}

/** The goldens of the release's own tests, with the line endings that the release's tests read. */
const ownerGolden = (name: string) => readFileSync(join(fixtures, 'morphir-extensions/v1', name), 'utf8').replace(/\r\n/g, '\n');

/** A check that each generated file equals its golden file, by exact text. */
function goldenCheck(goldens: Record<string, string>): (output: string) => string {
  return output => {
    for (const [path, name] of Object.entries(goldens)) {
      assert.equal(readFileSync(join(output, path), 'utf8'), ownerGolden(name), `${path} differs from the golden ${name}`);
    }
    return `equal to the release's goldens: ${Object.values(goldens).join(', ')}`;
  };
}

/** One generate case of a backend: the input model and the target. */
interface BackendCase { input: 'pricing' | 'customer'; target: ModelLineTarget }

const avroCases: BackendCase[] = [{
  input: 'customer',
  target: {
    id: 'avro',
    files: ['examples/customer/domain/Customer.avsc'],
    check: goldenCheck({ 'examples/customer/domain/Customer.avsc': 'canonical-customer.avsc' }),
  },
}, {
  // The owner has no golden for this model: its Decimal fields must still give records.
  input: 'pricing',
  target: {
    id: 'avro',
    files: ['pricing/quotes/Quote.avsc', 'pricing/quotes/Status.avsc'],
    check: output => {
      const quote = JSON.parse(readFileSync(join(output, 'pricing/quotes/Quote.avsc'), 'utf8'));
      assert.equal(quote.type, 'record');
      assert.equal(quote.name, 'Quote');
      assert.equal(quote.namespace, 'pricing.quotes');
      return `Quote record with ${quote.fields.length} fields`;
    },
  },
}];

// 0.3.0 refused the Decimal fields of the pricing model with JSC003; 0.4.0 projects them (finos/morphir-extensions#20).
const openapiCases: BackendCase[] = [{
  input: 'pricing',
  target: { id: 'openapi', files: ['openapi.json'], check: goldenCheck({ 'openapi.json': 'typed-pricing.openapi-3.1.json' }) },
}, {
  input: 'pricing',
  target: {
    id: 'json-schema',
    files: ['quotes.Quote.schema.json', 'quotes.Status.schema.json'],
    check: goldenCheck({
      'quotes.Quote.schema.json': 'typed-pricing.quotes.Quote.schema.json',
      'quotes.Status.schema.json': 'typed-pricing.quotes.Status.schema.json',
    }),
  },
}];

/** Downloads one WASM release of the model line and writes its pin. */
function modelLinePin(context: Context, section: any) {
  const module = fetchRelease(section, section.module);
  const descriptor = fetchRelease(section, section.descriptor);
  const pin = writePin(join(context.scratch, `${section.tag.replaceAll('/', '-')}-pin.json`),
    wasmPin(module, 'extism-kernel-v1', `${section.repository} ${section.tag}`, descriptor));
  return pin;
}

/** Describe of one model-line WASM release: the identity, the protocol claim and the tuple claim. */
function describeRow(context: Context, cli: Cli, base: Omit<Row, 'result' | 'platform' | 'cli' | 'operation'>, pin: string, directory: string,
  id: string, section: any, tuples: object[], targets: string[], languages: object[]) {
  context.ledger.step({ ...base, cli: cli.name, operation: 'describe' }, () => {
    const result = described(boundedCommand(cli, ['extension', 'describe', '--extension-pin', pin], directory, 0), id, section.version, 'wasm');
    assert.equal(result.worker.runtime.abi, 'extism-kernel-v1');
    assert.equal(result.worker.descriptorSha256, section.descriptor.sha256);
    assert.deepEqual([...result.claims.protocolVersions].sort(), ['0.1', '0.2.0-draft.1']);
    assert.deepEqual(sortedTuples(result.claims.modelTuples), sortedTuples(tuples));
    assert.deepEqual(result.claims.targets, targets);
    assert.deepEqual(result.claims.languages, languages);
    return { detail: `claims MEP ${result.claims.protocolVersions.join(', ')}; ${tuples.length} model tuples at IR 4.0.0; targets ${targets.join(', ')}` };
  });
}

/** A published backend on the model line (avro, openapi): generate of the pricing model at IR 4, and the IR 3 refusals. */
function backendGuest(context: Context, section: any, id: string, cases: BackendCase[]) {
  const { ledger } = context;
  const pin = modelLinePin(context, section);
  const base = { extension: id, version: section.version, guestSha256: section.module.sha256 as Sha256, descriptorSha256: section.descriptor.sha256 as Sha256 };
  const tuples = [jsonModelTuple('morphir.backend.generateModel', '4')];
  const results: Record<string, Record<string, Record<string, Sha256>>> = {};
  for (const cli of context.clis) {
    const { directory, pricing, classicIr3 } = modelLineDirectory(context, id, cli);
    const customer = writeModelForms(directory, 'customer', ownerGolden('canonical-customer-v4.json'), '4.0.0', 'urn:morphir:qualification:customer');
    const mine: Record<string, Record<string, Sha256>> = {};
    results[cli.name] = mine;
    const targets = [...new Set(cases.map(item => item.target.id))];
    describeRow(context, cli, base, pin, directory, id, section, tuples, targets, []);
    const flag = (target: string) => targets.length > 1 ? ['--target', target] : [];
    for (const { input, target } of cases) {
      generateRows(context, cli, base, pin, directory, mine, input === 'pricing' ? pricing : customer, target, flag(target.id));
    }
    for (const target of targets) ir3FallbackRows(context, cli, base, pin, directory, mine, pricing, flag(target), classicIr3);
    wrongEnvelopeRows(context, cli, base, pin, directory, ownerGolden('canonical-customer-v4.json'), flag(targets[0]!));
    if (targets.length > 1) {
      ledger.step({ ...base, cli: cli.name, operation: 'refuse-missing-target' }, () => {
        const report = boundedCommand(cli, ['extension', 'generate', pricing.plain, '--output', 'no-target', '--extension-pin', pin], directory, 2);
        assert.equal(report.error.code, 'extension.input_invalid');
        assert.equal(existsSync(join(directory, 'no-target')), false);
        return { detail: report.error.message };
      });
    }
  }
  sameOutputRow(context, base, results);
  mep01BackendRows(context, base, section, targets0(cases));
}

/** The first case of each target, with an IR 4 input that has a golden. */
const targets0 = (cases: BackendCase[]) => [...new Map(cases.map(item => [item.target.id, item] as const)).values()];

/** The recorded npm result must equal the native result. */
function sameOutputRow(context: Context, base: Omit<Row, 'result' | 'platform' | 'cli' | 'operation'>,
  results: Record<string, Record<string, Record<string, Sha256>>>) {
  const { native: nativeOutputs, npm: npmOutputs } = results;
  if (nativeOutputs && npmOutputs) {
    context.ledger.step({ ...base, cli: 'npm', operation: 'same-output-as-native' }, () => {
      assert.deepEqual(npmOutputs, nativeOutputs);
      return { detail: `${Object.keys(nativeOutputs).length} output directories` };
    });
  }
}

/**
 * One call of a direct MEP session. `ir` is exact IR text for `params.ir`: a
 * JSON round trip in JavaScript rounds large integer literals.
 */
type Mep01Call = { method: string; params: unknown; ir?: string };
/** A request has a positive `id`, and a notification has none. */
type Mep01Message = Mep01Call & { id?: number };

/** What a direct MEP session reads and writes on the worker's stdio: Content-Length frames. */
function mepFrame({ ir, ...message }: Mep01Message): Buffer {
  const text = JSON.stringify({ jsonrpc: '2.0', ...message });
  const body = Buffer.from(ir === undefined ? text : text.replace('"params":{', () => `"params":{"ir":${ir},`));
  return Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body]);
}

function mepFrames(bytes: Buffer): any[] {
  const messages: any[] = [];
  let rest = bytes;
  while (rest.length > 0) {
    const end = rest.indexOf('\r\n\r\n');
    assert.ok(end > 0, 'a MEP frame has no header');
    const length = /Content-Length: (\d+)/i.exec(rest.subarray(0, end).toString());
    assert.ok(length, 'a MEP frame has no Content-Length');
    const stop = end + 4 + Number(length[1]);
    assert.ok(stop <= rest.length, 'a MEP frame is cut short');
    messages.push(JSON.parse(rest.subarray(end + 4, stop).toString()));
    rest = rest.subarray(stop);
  }
  return messages;
}

/**
 * One session that offers only MEP 0.1, directly to the guest. The CLI's own
 * commands put a guest that claims the model line on that line, with no fall back
 * (bead morphir-ukvn.5.64.36.31), so this path has no CLI command. The worker is
 * `morphir extension worker` of the native CLI for a WASM module and the executable
 * itself for a process worker. The npm CLI has no worker mode for this.
 * Returns the answer of each call, by id.
 */
function mep01Session(context: Context, host: { program: string; args: string[] }, calls: Mep01Call[]): any[] {
  const native = context.clis.find(cli => cli.name === 'native')!;
  const initialize = { id: 1, method: 'morphir.initialize', params: { protocolVersions: ['0.1'], host: { kind: 'cli', name: 'morphir-qualification', version: '0.0.0' } } };
  const shutdownId = calls.length + 2;
  const messages: Mep01Message[] = [
    initialize,
    { method: 'morphir.initialized', params: {} },
    ...calls.map((call, index) => ({ id: index + 2, ...call })),
    { id: shutdownId, method: 'morphir.shutdown', params: {} },
    { method: 'morphir.exit', params: {} },
  ];
  const started = performance.now();
  const child = spawnSync(host.program, host.args, { input: Buffer.concat(messages.map(mepFrame)), env: native.env, cwd: context.scratch,
    timeout: exitBoundMs, killSignal: 'SIGKILL', maxBuffer: 64 * 1024 * 1024 });
  const elapsedMs = Math.round(performance.now() - started);
  assert.equal(child.status, 0, `the worker exited ${child.status} after ${elapsedMs} ms of the ${exitBoundMs} ms bound: ${child.stderr?.toString().slice(-2000)}`);
  const answers = new Map(mepFrames(child.stdout).map(answer => [answer.id, answer]));
  assert.equal(answers.get(1)?.result?.protocolVersion, '0.1', 'the session agrees on MEP 0.1');
  assert.equal(answers.get(1).result.capabilities.modelTransport, undefined, 'MEP 0.1 has no model transport');
  assert.deepEqual(answers.get(shutdownId)?.result, {}, 'shutdown');
  return calls.map((_, index) => answers.get(index + 2));
}

/** The worker of one WASM module for a direct session. */
function wasmWorker(context: Context, module: string): { program: string; args: string[] } {
  return workerModeHost(context, 'extism-kernel-v1', module, context.scratch);
}

/** The artifacts of a successful MEP 0.1 generate, by path, with their digests for the row. */
function mep01Artifacts(answer: any) {
  assert.equal(answer?.result?.success, true, JSON.stringify(answer).slice(0, 2000));
  const artifacts = answer.result.artifacts as { path: string; content: string }[];
  assert.ok(artifacts.length > 0, 'no artifacts');
  return {
    texts: Object.fromEntries(artifacts.map(artifact => [artifact.path, artifact.content])),
    outputs: artifacts.map(artifact => {
      const bytes = Buffer.from(artifact.content);
      return { path: artifact.path, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') as Sha256 };
    }),
  };
}

/** The model method of the other line must be refused on MEP 0.1. */
const assertNoModelMethod = (answer: any) => assert.equal(answer?.error?.code, -32013, JSON.stringify(answer).slice(0, 2000));

const mep01Note = 'a direct session, MEP 0.1 only; the CLI commands use the model line for this guest (bead morphir-ukvn.5.64.36.31)';

/** MEP 0.1 of a backend, where it keeps that line: the owner's IR 3 fixture, and IR 4 to the same golden as the model line. */
function mep01BackendRows(context: Context, base: Omit<Row, 'result' | 'platform' | 'cli' | 'operation'>, section: any, cases: BackendCase[]) {
  const { ledger } = context;
  const module = fetchRelease(section, section.module);
  const generate = (ir: string, target: string) => ({ method: 'morphir.backend.generate', params: { target, options: {} }, ir });
  for (const { input, target } of cases) {
    ledger.step({ ...base, cli: 'worker', operation: `mep-0.1-generate-ir3-${target.id}` }, () => {
      const ir = ownerGolden('classic-schema-library-v3.json');
      assert.equal(JSON.parse(ir).formatVersion, 3);
      const [answer, model] = mep01Session(context, wasmWorker(context, module), [generate(ir, target.id),
        { method: 'morphir.backend.generateModel', params: { target: target.id } }]);
      assertNoModelMethod(model);
      return { detail: `formatVersion 3; ${mep01Note}`, outputs: mep01Artifacts(answer).outputs };
    });
    ledger.step({ ...base, cli: 'worker', operation: `mep-0.1-generate-ir4-${target.id}` }, () => {
      const ir = input === 'pricing' ? pricingIr() : ownerGolden('canonical-customer-v4.json');
      const [answer] = mep01Session(context, wasmWorker(context, module), [generate(ir, target.id)]);
      const { texts, outputs } = mep01Artifacts(answer);
      assert.deepEqual(Object.keys(texts).sort(), target.files);
      const output = mkdtempSync(join(context.scratch, 'mep01-'));
      for (const [path, text] of Object.entries(texts)) {
        mkdirSync(dirname(join(output, path)), { recursive: true });
        writeFileSync(join(output, path), text);
      }
      return { detail: `formatVersion 4; ${target.check(output)}; ${mep01Note}`, outputs };
    });
  }
}

/**
 * The Rust extension 0.4.0 on the model line: compile and generate at IR 4, on
 * the golden files of its own release (apps/morphir/fixtures/rust-extension/v1).
 * The generated crate is the golden `generated-lib.rs`, because the frontend's
 * source subset has no module declarations and cannot compile it back.
 */
function rustGuest(context: Context) {
  const { ledger } = context;
  const section = published.rust;
  const id = 'morphir-rust';
  const pin = modelLinePin(context, section);
  const base = { extension: id, version: section.version, guestSha256: section.module.sha256 as Sha256, descriptorSha256: section.descriptor.sha256 as Sha256 };
  const root = join(fixtures, 'rust-extension/v1');
  const fixture = (name: string) => readFileSync(join(root, name), 'utf8');
  const goldenIr = fixture('compiled-ir-v4.json');
  const goldenCrate = fixture('generated-lib.rs');
  const target: ModelLineTarget = {
    id: 'rust',
    files: ['lib.rs'],
    check: output => {
      assert.equal(readFileSync(join(output, 'lib.rs'), 'utf8'), goldenCrate, 'lib.rs differs from the golden crate');
      return 'lib.rs equals the release\'s golden crate';
    },
  };
  const tuples = ['morphir.frontend.compileModel', 'morphir.backend.generateModel'].map(operation => jsonModelTuple(operation, '4'));
  const compileFlags = ['--package', 'acme/example'];
  const results: Record<string, Record<string, Record<string, Sha256>>> = {};
  for (const cli of context.clis) {
    const { directory, pricing } = modelLineDirectory(context, id, cli);
    writeFileSync(join(directory, 'models.rs'), fixture('models.rs'));
    const golden4 = writeModelForms(directory, 'golden', goldenIr, '4.0.0', 'urn:morphir:qualification:rust-golden');
    const mine: Record<string, Record<string, Sha256>> = {};
    results[cli.name] = mine;
    describeRow(context, cli, base, pin, directory, id, section, tuples, ['rust'], [{ id: 'rust', fileExtensions: ['.rs'] }]);
    const compiled = ledger.step({ ...base, cli: cli.name, operation: 'compile-model-ir4' }, () => {
      const report = boundedCommand(cli, ['extension', 'compile', 'models.rs', ...compileFlags, '--ir-version', '4',
        '--output', 'model', '--extension-pin', pin], directory, 0);
      assert.equal(report.result.protocolVersion, '0.2.0-draft.1');
      assert.deepEqual(report.result.negotiated.tuple, jsonModelTuple('morphir.frontend.compileModel', '4'));
      assert.deepEqual(report.result.output.files.map((file: { path: string }) => file.path), ['model-envelope.json', 'model.json']);
      const envelope = JSON.parse(readFileSync(join(directory, 'model/model-envelope.json'), 'utf8'));
      assert.equal(envelope.irVersion, '4.0.0');
      assert.equal(envelope.payload.sha256, sha256(join(directory, 'model/model.json')), 'model.json is the envelope payload');
      const ir = JSON.parse(readFileSync(join(directory, 'model/model.json'), 'utf8'));
      assert.equal(ir.formatVersion, 4);
      assert.deepEqual(ir, JSON.parse(goldenIr), 'the compiled IR differs from the release\'s golden IR');
      mine.model = treeDigests(join(directory, 'model'));
      return { tuple: tupleLabel(report), detail: 'formatVersion 4; the IR equals the release\'s golden IR', outputs: outputs(join(directory, 'model'), report.result.output.files) };
    });
    ledger.step({ ...base, cli: cli.name, operation: 'default-ir' }, () => {
      const report = boundedCommand(cli, ['extension', 'compile', 'models.rs', ...compileFlags, '--output', 'default', '--extension-pin', pin], directory, 0);
      assert.deepEqual(report.result.negotiated.tuple, jsonModelTuple('morphir.frontend.compileModel', '4'));
      assert.equal(JSON.parse(readFileSync(join(directory, 'default/model.json'), 'utf8')).formatVersion, 4);
      return { tuple: tupleLabel(report), detail: 'no flag: the only agreed tuple has IR 4.0.0' };
    });
    const compiled3 = ledger.step({ ...base, cli: cli.name, operation: 'compile-ir3-legacy-fallback' }, () => {
      const report = boundedCommand(cli, ['extension', 'compile', 'models.rs', ...compileFlags, '--ir-version', '3',
        '--output', 'compile-ir3', '--extension-pin', pin], directory, 0);
      const warning = legacyFallback(report, 'morphir.frontend.compile');
      // MEP 0.1 writes that line's layout.
      assert.deepEqual(report.result.output.files.map((file: { path: string }) => file.path), ['morphir-ir.json']);
      assert.equal(JSON.parse(readFileSync(join(directory, 'compile-ir3/morphir-ir.json'), 'utf8')).formatVersion, 3);
      mine.compileIr3 = treeDigests(join(directory, 'compile-ir3'));
      return { detail: `formatVersion 3; MEP 0.1 with the warning: ${warning}`, outputs: outputs(join(directory, 'compile-ir3'), report.result.output.files) };
    });
    const rustIr3 = compiled3
      ? writeModelForms(directory, 'rust-ir3', readFileSync(join(directory, 'compile-ir3/morphir-ir.json'), 'utf8'), '3.0.0', 'urn:morphir:qualification:rust-ir3')
      : undefined;
    ledger.step({ ...base, cli: cli.name, operation: 'refuse-multi-document' }, () => {
      mkdirSync(join(directory, 'two'));
      for (const name of ['first.rs', 'second.rs']) writeFileSync(join(directory, 'two', name), 'pub struct Marker;\n');
      const report = boundedCommand(cli, ['extension', 'compile', 'two', ...compileFlags, '--output', 'multi', '--extension-pin', pin], directory, 2);
      assert.equal(report.error.code, 'extension.capability_unavailable');
      assert.match(report.error.message, /multiDocument/);
      assert.equal(existsSync(join(directory, 'multi')), false);
      return { detail: report.error.message };
    });
    generateRows(context, cli, base, pin, directory, mine, golden4, target, []);
    if (compiled) {
      generateRows(context, cli, base, pin, directory, mine,
        { label: 'compiled', plain: 'model/model.json', envelope: 'model/model-envelope.json' }, target, []);
    }
    ledger.step({ ...base, cli: cli.name, operation: 'generate-plain-ir4-pricing-rust' }, () => {
      const report = boundedCommand(cli, ['extension', 'generate', pricing.plain, '--output', 'pricing-rust', '--extension-pin', pin], directory, 0);
      return { tuple: tupleLabel(report) };
    }, {
      match: /RS_NAME/,
      finding: 'morphir-rust refuses the pricing model with RS_NAME: the module scalars has the values SDK and sdk, which map to one Rust identifier; no host cause; bead morphir-ukvn.5.64.36.30',
    });
    ir3FallbackRows(context, cli, base, pin, directory, mine, golden4, [], rustIr3, target.check);
    wrongEnvelopeRows(context, cli, base, pin, directory, goldenIr, []);
  }
  sameOutputRow(context, base, results);
  rustMep01Rows(context, base, section, fixture('models.rs'), goldenIr, goldenCrate);
}

/** MEP 0.1 of the Rust extension: compile and generate at IR 3 and 4, with the same crate from both. */
function rustMep01Rows(context: Context, base: Omit<Row, 'result' | 'platform' | 'cli' | 'operation'>, section: any, source: string, goldenIr: string, goldenCrate: string) {
  const { ledger } = context;
  const module = fetchRelease(section, section.module);
  const compile = (ir: string) => ({ method: 'morphir.frontend.compile', params: {
    languageId: 'rust', sources: { documents: [{ uri: 'models.rs', languageId: 'rust', version: 0, text: source }] },
    package: { name: 'acme/example' }, options: { typesOnly: false, irVersion: ir },
  } });
  for (const ir of ['3', '4']) {
    ledger.step({ ...base, cli: 'worker', operation: `mep-0.1-compile-and-generate-ir${ir}` }, () => {
      const [compiled] = mep01Session(context, wasmWorker(context, module), [compile(ir)]);
      assert.equal(compiled?.result?.success, true, JSON.stringify(compiled).slice(0, 2000));
      assert.equal(compiled.result.ir.formatVersion, Number(ir));
      if (ir === '4') assert.deepEqual(compiled.result.ir, JSON.parse(goldenIr), 'the compiled IR differs from the release\'s golden IR');
      const [generated, model] = mep01Session(context, wasmWorker(context, module), [
        { method: 'morphir.backend.generate', params: { ir: compiled.result.ir, target: 'rust', options: {} } },
        { method: 'morphir.backend.generateModel', params: { target: 'rust' } },
      ]);
      assertNoModelMethod(model);
      const { texts, outputs } = mep01Artifacts(generated);
      assert.equal(texts['lib.rs'], goldenCrate, 'lib.rs differs from the golden crate');
      return { detail: `formatVersion ${ir}; lib.rs equals the release's golden crate; ${mep01Note}`, outputs };
    });
  }
}

/**
 * The published extensions of the model line that have no suite of their own
 * language (task 7.8, bead morphir-ukvn.5.64.36.28): avro 0.4.0, openapi 0.5.0
 * and rust 0.4.0, each one WASM module (`extism-kernel-v1`).
 */
function modelLineSuite(context: Context) {
  backendGuest(context, published.avro, 'morphir-avro', avroCases);
  backendGuest(context, published.openapi, 'morphir-openapi', openapiCases);
  rustGuest(context);
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
const jsonEnvelope = (plainIr: unknown) => modelEnvelope(JSON.stringify(plainIr), '4.0.0', 'urn:morphir:mck:bool');

/** A Morphir JSON model envelope around exact IR text, independent of the host's own wrapping of plain IR. */
function modelEnvelope(ir: string, irVersion: string, modelId: string) {
  const bytes = Buffer.from(ir);
  const digest = createHash('sha256').update(bytes).digest('hex');
  return {
    envelopeVersion: '0.1.0-draft.1', modelId, revision: `sha256:${digest}`, irVersion,
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
  elm: elmSuite, python: pythonSuite, conformance: conformanceSuite, 'model-line': modelLineSuite,
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
