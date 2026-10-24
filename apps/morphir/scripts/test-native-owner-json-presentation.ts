/** Current native-owner artifacts only. Build the seven release packages first.
 * Run with Node, after building protocol-fault for JS as well.
 * Pass --protocol-fault-only to require only native + JS protocol-fault.
 * No historical Git objects, Rust, CEF, browser, service or network is used.
 */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { parseArgs } from 'node:util';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir, hostname, release } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const { values } = parseArgs({ options: { 'protocol-fault-only': { type: 'boolean', default: false } } });
const protocolFaultOnly = values['protocol-fault-only'];
const repo = resolve(fileURLToPath(new URL('../../../', import.meta.url)));
const build = join(repo, '_build/native/release/build/finos');
const names = ['acceptance', 'bridge-acceptance', 'files-acceptance', 'fixture', 'mck/native', 'workspace-acceptance', 'protocol-fault'] as const;
type Owner = typeof names[number];
const executable = (name: Owner) => name === 'protocol-fault'
  ? join(build, 'morphir-host/acceptance/protocol-fault/protocol-fault.exe')
  : join(build, 'morphir-workbench-native', name, name.split('/').at(-1) + '.exe');
const scratch = mkdtempSync(join(tmpdir(), 'morphir-native-owner-json-'));
const receipts: Record<string, unknown>[] = [];
let nativeEnvelopeByteChecks = 0;
let protocolFaultEnvelopeByteChecks = 0;
const receiptPath = process.env.NATIVE_OWNER_JSON_RECEIPT;
const rawInvocations: Record<string, unknown>[] = [];
const artifacts = new Map<string, unknown>();
const sha256 = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
function failure(error: unknown): unknown {
  return error instanceof Error ? { name: error.name, message: error.message, stack: error.stack,
    cause: error.cause === undefined ? undefined : failure(error.cause),
    errors: error instanceof AggregateError ? error.errors.map(failure) : undefined } : String(error);
}
function artifact(path: string) {
  if (!artifacts.has(path)) {
    try { const bytes = readFileSync(path); artifacts.set(path, { path, bytes: bytes.length, sha256: sha256(bytes) }); }
    catch (error) { artifacts.set(path, { path, error: failure(error) }); }
  }
  return artifacts.get(path);
}
function git(argv: string[]) {
  const result = spawnSync('git', argv, { cwd: repo, encoding: 'utf8', timeout: 5000 });
  return { command: ['git', ...argv], status: result.status, stdout: result.stdout, stderr: result.stderr,
    error: result.error && failure(result.error) };
}
const metadata = {
  startedAt: new Date().toISOString(), host: { hostname: hostname(), release: release(), platform: process.platform, arch: process.arch },
  node: { version: process.version, execPath: process.execPath, versions: process.versions },
  checkout: { repo, cwd: process.cwd(), command: [process.execPath, ...process.argv.slice(1)],
    environment: { PATH: process.env.PATH, MOON_HOME: process.env.MOON_HOME, CI: process.env.CI,
      GITHUB_SHA: process.env.GITHUB_SHA, GITHUB_WORKSPACE: process.env.GITHUB_WORKSPACE },
    head: git(['rev-parse', 'HEAD']), status: git(['status', '--porcelain']),
    sourceIdentity: 'Observed checkout only; artifact-to-source build provenance is unverified.' },
  consumer: artifact(fileURLToPath(import.meta.url)), sources: [] as unknown[],
};
let successful = false;
let primaryFailure: unknown;
let hasPrimaryFailure = false;
const secondaryFailures: unknown[] = [];
function summary() {
  return { successful, platform: process.platform, arch: process.arch, backend: 'native + Node JS protocol-fault',
    invocations: receipts.length, nativeEnvelopeByteChecks, protocolFaultEnvelopeByteChecks, protocolFaultOnly, faults: 15, receipts };
}
function retain() {
  if (!receiptPath) return;
  mkdirSync(dirname(resolve(receiptPath)), { recursive: true });
  writeFileSync(receiptPath, JSON.stringify({ ...summary(), metadata, artifacts: [...artifacts.values()],
    failure: hasPrimaryFailure ? failure(primaryFailure) : undefined, secondaryFailures: secondaryFailures.map(failure),
    rawInvocations, updatedAt: new Date().toISOString() }) + '\n');
}
function capture(program: string, argv: string[], cwd: string, result: { stdout?: Buffer | null; stderr?: Buffer | null; status: number | null; signal: NodeJS.Signals | null; error?: unknown }, argv0?: string) {
  if (!receiptPath) return;
  const raw = (bytes: Buffer | null | undefined) => bytes == null ? { unavailable: true } :
    { bytes: bytes.length, sha256: sha256(bytes), base64: bytes.toString('base64') };
  rawInvocations.push({ command: [program, ...argv], argv0, cwd, artifact: artifact(program),
    status: result.status, signal: result.signal, error: result.error === undefined ? undefined : failure(result.error),
    stdout: raw(result.stdout), stderr: raw(result.stderr) });
}
const consoleArgv = (argv: string[]) => argv.map(arg => Buffer.byteLength(arg) <= 4096 ? arg : `<${Buffer.byteLength(arg)} bytes; exact argv in receipt file>`);
function run(name: Owner, argv: string[], options: { input?: Buffer | string; cwd?: string; program?: string; env?: NodeJS.ProcessEnv; timeout?: number; argv0?: string } = {}) {
  const result = spawnSync(options.program ?? executable(name), argv, {
    argv0: options.argv0, cwd: options.cwd ?? repo, input: options.input ?? '', env: options.env ?? process.env,
    timeout: options.timeout ?? 30000, maxBuffer: 8 * 1024 * 1024,
  });
  capture(options.program ?? executable(name), argv, options.cwd ?? repo, result, options.argv0);
  receipts.push({ owner: name, argv: consoleArgv(argv), argv0: options.argv0, cwd: options.cwd ?? repo, status: result.status, signal: result.signal,
    stdoutBytes: result.stdout?.length, stderrBytes: result.stderr?.length,
    stdoutSha256: result.stdout && createHash('sha256').update(result.stdout).digest('hex'),
    stdoutTailHex: result.stdout?.subarray(-32).toString('hex'),
    stdout: result.stdout?.length <= 4096 ? result.stdout.toString("base64") : undefined,
    stderr: result.stderr?.length <= 16384 ? result.stderr.toString() : undefined, error: result.error?.message });
  if (!options.timeout) assert.equal(result.error, undefined, result.error?.message ?? "Child process failed");
  return { ...result, nativeProtocolFault: name === 'protocol-fault' && options.program === undefined };
}
function success(result: ReturnType<typeof run>) {
  assert.equal(result.status, 0, result.stderr.toString() + result.stdout.toString());
  assert.equal(result.signal, null);
}
type Output = { status: number | null; signal: NodeJS.Signals | null; stdout: Buffer; stderr: Buffer; nativeProtocolFault?: boolean };
function value(result: Output) {
  const source = result.stdout.toString();
  assert.ok(source.endsWith('\n'));
  const parsed = JSON.parse(source);
  assert.equal(source, JSON.stringify(parsed) + '\n', 'one compact JSON value plus LF');
  return parsed;
}
function envelope(result: Output, status = 0) {
  assert.equal(result.status, status, result.stderr.toString());
  const parsed = value(result);
  if (result.nativeProtocolFault || (typeof parsed.command === 'string' && parsed.command.startsWith('workbench.native.')
    && (status !== 0 || parsed.result?.render_help !== undefined))) {
    // Check pipe bytes explicitly, including BOM, invalid UTF-8 and CRLF.
    assert.equal(result.stdout[0], 0x7b, 'native envelope starts with {, without BOM');
    assert.equal(result.stdout.includes(0x0d), false, 'native envelope has no CR byte');
    assert.equal(result.stdout.at(-1), 0x0a, 'native envelope ends with LF');
    const source = new TextDecoder('utf-8', { fatal: true }).decode(result.stdout);
    assert.equal(parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed), true);
    assert.equal(source, JSON.stringify(parsed) + '\n', 'native compact object plus exactly one LF');
    assert.deepEqual(result.stdout, Buffer.from(JSON.stringify(parsed) + '\n', 'utf8'), 'exact native UTF-8 bytes');
    if (result.nativeProtocolFault) protocolFaultEnvelopeByteChecks++;
    else nativeEnvelopeByteChecks++;
  }
  assert.equal(parsed.profile, 'morphir/command-result');
  assert.equal(parsed.contractVersion, '0.1.0');
  assert.equal(parsed.exitCode, status);
  assert.equal(parsed.state, status === 0 ? 'succeeded' : 'failed');
  assert.deepEqual(parsed.diagnostics, []);
  assert.equal('result' in parsed, status === 0);
  assert.equal('error' in parsed, status !== 0);
  if (status !== 0) { assert.equal(typeof parsed.error.code, 'string'); assert.equal(typeof parsed.error.message, 'string'); }
  return parsed;
}
function events(result: ReturnType<typeof run>, terminalCode = 0) {
  const lines = result.stderr.toString().trim().split('\n').map(line => JSON.parse(line));
  assert.ok(result.stderr.length < 16384, 'bounded owner stderr');
  let prior = -1;
  for (const event of lines) {
    assert.equal(event.profile, 'morphir/command-event');
    assert.equal(event.contractVersion, '0.1.0');
    assert.ok(event.sequence > prior);
    prior = event.sequence;
  }
  assert.equal(lines[0].event, 'startup');
  assert.equal(lines.at(-1).event, 'terminal');
  assert.equal(lines.at(-1).exitCode, terminalCode);
  return lines;
}
// Windows limits the complete CreateProcess command line to 32,767 UTF-16
// units. Reserve quoting/path/prefix space and use three-byte UTF-8 there.
async function largeUnknownFault(js: string, checkpoint: string) {
  const count = process.platform === 'win32'
    ? Math.min(24000, 30000 - process.execPath.length - js.length - checkpoint.length)
    : 120000;
  const fault = (process.platform === 'win32' ? '界' : 'x').repeat(Math.max(0, count)) + '雪😀';
  assert.ok(Buffer.byteLength(fault) > 65536, 'paths must leave enough OS argv space for a failure above 64 KiB');
  const argv = [js, '--json', '--', checkpoint, fault];
  const before = readdirSync(scratch);
  const bytes = readFileSync(checkpoint);
  const native = run('protocol-fault', argv.slice(1), { cwd: scratch });
  assert.equal(envelope(native, 1).error.message, 'unknown fault: ' + fault, 'native normal exit flushes the full reason');
  assert.equal(native.stderr.length, 0);
  assert.deepEqual(readFileSync(checkpoint), bytes);
  const child = spawn(process.execPath, argv, { cwd: scratch, stdio: ['pipe', 'pipe', 'pipe'] });
  const stdout: Buffer[] = [], stderr: Buffer[] = [];
  // Hold stdin open and delay stdout consumption. Rejection must finish with
  // the entire failure after real pipe backpressure and without reading input.
  child.stdout.pause();
  child.stdout.on('data', (chunk: Buffer) => stdout.push(chunk));
  child.stderr.on('data', (chunk: Buffer) => stderr.push(chunk));
  const resume = setTimeout(() => child.stdout.resume(), 100);
  const timeout = setTimeout(() => child.kill('SIGKILL'), 10000);
  let status: number | null = null, signal: NodeJS.Signals | null = null;
  let spawnError: unknown;
  try {
    [status, signal] = await new Promise<[number | null, NodeJS.Signals | null]>((done, reject) => {
      child.on('error', reject);
      child.on('close', (code, exitSignal) => done([code, exitSignal]));
    });
  } catch (error) { spawnError = error; throw error; }
  finally {
    clearTimeout(resume); clearTimeout(timeout);
    capture(process.execPath, argv, scratch, { status, signal, error: spawnError, stdout: Buffer.concat(stdout), stderr: Buffer.concat(stderr) });
  }
  const result = { status, signal, stdout: Buffer.concat(stdout), stderr: Buffer.concat(stderr) };
  assert.equal(status, 1); assert.equal(signal, null); assert.equal(result.stderr.length, 0);
  assert.equal(envelope(result, 1).error.message, 'unknown fault: ' + fault, 'full unredacted CLI reason');
  assert.ok(result.stdout.length > 65536);
  assert.deepEqual(readFileSync(checkpoint), bytes, 'large refusal cannot mutate input');
  assert.deepEqual(readdirSync(scratch), before, 'large refusal has no filesystem effects');
  receipts.push({ owner: 'protocol-fault', backend: 'Node JS', largeUnknownFault: true,
    faultCodeUnits: fault.length, faultBytes: Buffer.byteLength(fault), stdoutBytes: result.stdout.length,
    stderrBytes: result.stderr.length, status, signal, backpressureDelayMs: 100, stdinHeldOpen: true });
}
// Ion 1.0 seed generated with the repository's pinned moonrockz/ion 0.5.0.
// It contains profile, suite_identity, calls one/two with value 42 and duration 0,
// traceparent and extensions. The test uses actual decoded/mutated binary files.
const seed = Buffer.from('4AEA6u7XgYPe04e+0Idwcm9maWxljo5zdWl0ZV9pZGVudGl0eYVjYWxsc4JpZIV2YWx1ZY6QZHVyYXRpb25fc2Vjb25kc4t0cmFjZXBhcmVudIpleHRlbnNpb25z3tOKjpNtb3JwaGlyLW91dGNvbWVzLXYxi4NhYmOMvqjeko2Db25ljiEqj0gAAAAAAAAAAN6SjYN0d2+OISqPSAAAAAAAAAAAkIV0cmFjZZGEa2VwdA==', 'base64');
try {
  retain(); // Initial metadata survives missing artifacts and later assertions.
  if (receiptPath) {
    const sourceList = git(['ls-files', 'pkgs/morphir-host/acceptance/protocol-fault', 'pkgs/morphir-workbench-native']);
    metadata.sources.push(sourceList);
    if (sourceList.status === 0) metadata.sources.push(...sourceList.stdout.trim().split('\n').filter(Boolean).map(path => artifact(join(repo, path))));
    for (const name of protocolFaultOnly ? ['protocol-fault'] as const : names) artifact(executable(name));
    artifact(join(repo, '_build/js/debug/build/finos/morphir-host/acceptance/protocol-fault/protocol-fault.js'));
  }
  for (const name of protocolFaultOnly ? ['protocol-fault'] as const : names) {
    assert.ok(existsSync(executable(name)), `Build current release artifact: ${name}`);
    const cwd = join(scratch, name.replaceAll('/', '-'));
    mkdirSync(cwd);
    const help = run(name, ['--json', '--help'], { cwd, input: 'must not be read' });
    success(help);
    const parsed = envelope(help);
    assert.match(parsed.result.render_help, /--json -- RAW/);
    assert.match(parsed.result.render_help, /--forward-argv -- RAW/);
    assert.match(parsed.result.render_help, /morphir\/command-result/);
    assert.match(parsed.result.render_help, /morphir\/command-event/);
    assert.equal(help.stderr.length, 0);
    assert.deepEqual(readdirSync(cwd), [], 'help has no filesystem effects');
  }
  const js = join(repo, '_build/js/debug/build/finos/morphir-host/acceptance/protocol-fault/protocol-fault.js');
  assert.ok(existsSync(js), 'Build current JS protocol-fault artifact');
  const faults = ['truncated', 'malformed', 'oversize', 'missing', 'extra', 'duplicate', 'reordered', 'wrong-id', 'duration', 'value', 'wrong-suite', 'wrong-profile', 'wrong-trace', 'extensions', 'duplicate-field'];
  for (const fault of faults) {
    const plain = join(scratch, fault + '-plain.ionb'), json = join(scratch, fault + '-json.ionb');
    writeFileSync(plain, seed); writeFileSync(json, seed);
    const oldMode = run('protocol-fault', [plain, fault, '--', '', '--json', '雪']);
    success(oldMode); assert.equal(oldMode.stdout.length, 0); assert.equal(oldMode.stderr.length, 0);
    const selected = run('protocol-fault', ['--json', '--', json, fault, '--', '', '--help', '--json', '雪']);
    const result = envelope(selected).result;
    assert.equal(selected.stderr.length, 0);
    assert.equal(result.fault, fault); assert.equal(result.path, json);
    assert.equal(result.bytesWritten, readFileSync(json).length);
    assert.deepEqual(readFileSync(json), readFileSync(plain), fault + ' unchanged artifact bytes');
    const jsPath = join(scratch, fault + '-js.ionb'); writeFileSync(jsPath, seed);
    const jsResult = run('protocol-fault', [js, '--json', '--', jsPath, fault], { program: process.execPath });
    assert.equal(envelope(jsResult).result.bytesWritten, readFileSync(jsPath).length);
    assert.deepEqual(readFileSync(jsPath), readFileSync(plain), fault + ' JS mutation bytes');
  }
  // Native and JS exercise the actual runtime-owned argv prefixes independently.
  for (const backend of ['native', 'js'] as const) {
    for (const path of ['--json', '--', '--help', '--forward-argv', process.platform === 'win32' ? 'spaces 雪 $ ; `' : 'spaces 雪 " $ ; `']) {
      writeFileSync(join(scratch, path), seed);
      const argv = ['--json', '--', path, 'malformed', '--', '', '--json'];
      const result = run('protocol-fault', backend === 'js' ? [js, ...argv] : argv, { cwd: scratch, program: backend === 'js' ? process.execPath : undefined });
      assert.equal(envelope(result).result.path, path);
      assert.deepEqual(readFileSync(join(scratch, path)), Buffer.from('not Ion'));
      // Legacy lone --json is a path, and the literal escape unwraps once.
      writeFileSync(join(scratch, path), seed);
      const raw = ['--forward-argv', '--', path, 'truncated'];
      success(run('protocol-fault', backend === 'js' ? [js, ...raw] : raw, { cwd: scratch, program: backend === 'js' ? process.execPath : undefined }));
      assert.deepEqual(readFileSync(join(scratch, path)), seed.subarray(0, -1));
    }
  }
  const untouched = join(scratch, 'untouched.ionb'); writeFileSync(untouched, seed);
  for (const argv of [[], ['missing'], ['', 'malformed'], [untouched, 'unknown'], [join(scratch, 'absent'), 'malformed'], [scratch, 'malformed']]) {
    envelope(run('protocol-fault', ['--json', '--', ...argv]), 1);
    assert.deepEqual(readFileSync(untouched), seed);
  }
  for (const bytes of [Buffer.from('not Ion'), Buffer.from([0xe0, 1, 0, 0xea, 0xd0])]) {
    const bad = join(scratch, 'invalid-codec.ionb'); writeFileSync(bad, bytes);
    envelope(run('protocol-fault', ['--json', '--', bad, 'wrong-id']), 1);
    assert.deepEqual(readFileSync(bad), bytes, 'codec/domain refusal preserves input');
  }
  const readOnly = join(scratch, 'read-only.ionb'); writeFileSync(readOnly, seed); chmodSync(readOnly, 0o400);
  try {
    envelope(run('protocol-fault', ['--json', '--', readOnly, 'malformed']), 1);
    assert.deepEqual(readFileSync(readOnly), seed, 'write failure cannot claim completion');
  } finally { chmodSync(readOnly, 0o600); }
  const empty = join(scratch, 'empty'); writeFileSync(empty, '');
  for (const backend of ['native', 'js'] as const) {
    const reasons: string[] = [];
    for (const [fault, reason] of [['unknown', 'unknown fault: unknown'], ['truncated', 'cannot truncate empty checkpoint']] as const) {
      const argv = ['--json', '--', empty, fault];
      const refused = run('protocol-fault', backend === 'js' ? [js, ...argv] : argv,
        { program: backend === 'js' ? process.execPath : undefined });
      const message = envelope(refused, 1).error.message;
      assert.equal(message, reason); reasons.push(message);
      assert.equal(refused.stderr.length, 0);
      assert.equal(readFileSync(empty).length, 0, 'each refusal preserves empty checkpoint');
    }
    assert.notEqual(reasons[0], reasons[1]);
  }
  await largeUnknownFault(js, untouched);
  assert.equal(readFileSync(empty).length, 0);
  if (!protocolFaultOnly) {
  // All three native protocol owners keep exact stdout bytes for real requests.
  const request = JSON.stringify({ operation: 'evaluate', executionMode: 'typed',
    source: readFileSync(join(repo, 'apps/morphir-workbench/fixtures/typed-pricing.json'), 'utf8'),
    entry: 'pricing:scalars#huge', arguments: [] });
  const header = Buffer.alloc(4); header.writeUInt32BE(Buffer.byteLength(request));
  const binary = Buffer.concat([header, Buffer.from(request)]);
  for (const name of ['fixture', 'bridge-acceptance'] as const) {
    const raw = name === 'fixture' ? [] : ['--morphir-native-worker'];
    const plain = run(name, raw, { input: binary }); success(plain); assert.ok(plain.stdout.length > 4);
    const json = run(name, ['--json', '--', ...raw], { input: binary }); success(json);
    assert.deepEqual(json.stdout, plain.stdout, name + ' exact binary stdout');
    assert.equal(json.stdout.readUInt32BE(), json.stdout.length - 4);
    events(json);
    const broken = run(name, ['--json', '--', ...raw], { input: Buffer.from([0, 0, 0, 0]) });
    assert.equal(broken.status, 1); assert.equal(broken.stdout.length, 0); events(broken, 1);
  }
  // Node supplies argv[0] independently of the executable path. A valid wire
  // request must dispatch before finite bridge acceptance creates a workspace.
  const argv0Cwd = join(scratch, 'argv0-worker'); mkdirSync(argv0Cwd);
  const reference = run('bridge-acceptance', ['--morphir-native-worker'], { input: binary }); success(reference);
  for (const argv of [[], ['--json', '--'], ['--forward-argv', '--'], ['--forward-argv', '--', '--json', '--help']]) {
    const result = run('bridge-acceptance', argv, { argv0: '--morphir-native-worker', cwd: argv0Cwd, input: binary });
    success(result); assert.deepEqual(result.stdout, reference.stdout);
    if (argv[0] === '--json') events(result); else assert.equal(result.stderr.length, 0);
    assert.deepEqual(readdirSync(argv0Cwd), [], 'argv[0] worker dispatch precedes finite filesystem effects');
  }
  const argv0Help = run('bridge-acceptance', ['--json', '--help'],
    { argv0: '--morphir-native-worker', cwd: argv0Cwd, input: binary });
  assert.ok(envelope(argv0Help).result.render_help); assert.equal(argv0Help.stderr.length, 0);
  assert.deepEqual(readdirSync(argv0Cwd), []);
  const negotiation = JSON.stringify({ id: 1, op: 'capabilities', suite: 'workbench', contractVersion: '0.1.0-draft.18' }) + '\n' + '{"op":"exit"}\n';
  const plainMck = run('mck/native', ['foreign', '--', '', '--json'], { input: negotiation }); success(plainMck);
  const jsonMck = run('mck/native', ['--json', '--', 'foreign', '--', '', '--json'], { input: negotiation }); success(jsonMck);
  assert.deepEqual(jsonMck.stdout, plainMck.stdout); events(jsonMck);
  const filesInput = JSON.stringify({ profile: 'morphir/workbench/workspace-files', contractVersion: '0.1.0-draft.1', operation: 'session.open' }) + '\n';
  const plainFiles = run('files-acceptance', [scratch], { input: filesInput }); success(plainFiles);
  const jsonFiles = run('files-acceptance', ['--json', '--', scratch], { input: filesInput }); success(jsonFiles);
  assert.deepEqual(jsonFiles.stdout, plainFiles.stdout); events(jsonFiles);
  for (const name of ['files-acceptance', 'mck/native'] as const) {
    for (const input of ['incomplete', 'x'.repeat(name === 'files-acceptance' ? 1048577 : 2097153)]) {
      const result = run(name, ['--json', '--', ...(name === 'files-acceptance' ? [scratch] : [])], { input });
      assert.equal(result.status, 1); assert.equal(result.stdout.length, 0);
      const diagnostic = events(result, 1).find(event => event.event === 'diagnostic');
      const expected = name === 'files-acceptance'
        ? (input === 'incomplete' ? 'Incomplete file frame' : 'File frame exceeds 1 MiB')
        : (input === 'incomplete' ? 'native owner MCK: incomplete NDJSON line' : 'native owner MCK: NDJSON line exceeds 2 MiB');
      assert.equal(diagnostic?.error.message, expected);
    }
  }
  const missingFolder = run('files-acceptance', ['--json', '--']);
  assert.equal(missingFolder.status, 1); assert.equal(missingFolder.stdout.length, 0); events(missingFolder, 1);
  // Fault identities remain owned by argv[0], including deliberate status 7.
  for (const fault of ['fault-crash', 'fault-after', 'fault-frame', 'fault-stderr', 'fault-hang', 'fault-memory', 'fault-trailing', 'fault-late-cancel']) {
    const program = join(scratch, fault + '.exe'); copyFileSync(executable('fixture'), program); chmodSync(program, 0o700);
    const limited = !['fault-crash', 'fault-after'].includes(fault);
    const plain = run('fixture', [], { program, input: binary, timeout: limited ? 1500 : undefined });
    const json = run('fixture', ['--json', '--'], { program, input: binary, timeout: limited ? 1500 : undefined });
    assert.equal(json.status, plain.status); assert.equal(json.signal, plain.signal);
    assert.deepEqual(json.stdout, plain.stdout, fault + ' deliberate wire bytes');
    if (!limited) { assert.equal(json.status, 7); events(json, 7); }
    if (fault === 'fault-stderr') assert.ok(json.stderr.includes(Buffer.alloc(70000, 'x')), 'deliberate corruption remains');
  }
  // Run existing acceptance operations against actual current worker artifacts.
  const acceptance = run('acceptance', [executable('fixture')]); success(acceptance);
  const acceptanceJson = run('acceptance', ['--json', '--', 'ignored', '--', executable('fixture')]); success(acceptanceJson);
  assert.deepEqual(acceptanceJson.stdout, acceptance.stdout); assert.ok(value(acceptanceJson).cases > 0);
  const bridge = run('bridge-acceptance', []); success(bridge);
  const bridgeJson = run('bridge-acceptance', ['--json', '--']); success(bridgeJson);
  assert.deepEqual(bridgeJson.stdout, bridge.stdout);
  // The real parent still launches its fixed sentinel and bounds child stderr.
  // A test wrapper opts each copied fault fixture into diagnostics while keeping
  // argv[0] fault identity and every wire byte owned by the original executable.
  const reportingFixture = join(scratch, 'reporting-fixture');
  const quoteFixture = (text: string) => "'" + text.replaceAll("'", "'\\''") + "'";
  writeFileSync(reportingFixture, `#!/bin/bash\nexec -a "$0" ${quoteFixture(executable('fixture'))} --json -- "$@"\n`);
  chmodSync(reportingFixture, 0o700);
  const parentWithEvents = run('acceptance', ['--json', '--', reportingFixture]); success(parentWithEvents);
  assert.deepEqual(parentWithEvents.stdout, acceptance.stdout, 'bounded events preserve parent worker outcomes');
  // A copied executable stub records actual child argv/cwd/env/stdin before exit.
  for (const code of [23, 130]) {
    const stub = join(scratch, 'stub-' + code), receipt = join(scratch, 'stub-' + code + '.json');
    const script = `const fs=require('node:fs');const chunks=[];process.stdin.on('data',b=>chunks.push(b));process.stdin.on('end',()=>{fs.writeFileSync(${JSON.stringify(receipt)},JSON.stringify({argv:process.argv.slice(1),cwd:process.cwd(),marker:process.env.NATIVE_OWNER_MARKER??null,stdin:Buffer.concat(chunks).length}));process.exit(${code});});`;
    const quote = (text: string) => "'" + text.replaceAll("'", "'\\''") + "'";
    writeFileSync(stub, `#!/bin/sh\nexec ${quote(process.execPath)} --input-type=commonjs -e ${quote(script)} -- "$@"\n`);
    chmodSync(stub, 0o700);
    const result = run('acceptance', ['--json', '--', 'ignored', '--', '', stub], { env: { ...process.env, NATIVE_OWNER_CAPTURE: receipt, NATIVE_OWNER_MARKER: '雪' } });
    envelope(result, 1); // Owner assertions historically fail with outer status 1.
    const captured = JSON.parse(readFileSync(receipt, 'utf8'));
    assert.deepEqual(captured.argv, ['--morphir-native-worker']);
    assert.equal(captured.cwd, repo); assert.equal(captured.marker, null, "production worker intentionally clears inherited env"); assert.ok(captured.stdin > 4);
  }
  envelope(run('acceptance', ['--json', '--', join(scratch, 'absent-worker')]), 1);
  const workspace = run('workspace-acceptance', []); success(workspace);
  const workspaceJson = run('workspace-acceptance', ['--json', '--']); success(workspaceJson);
  assert.deepEqual(workspaceJson.stdout, workspace.stdout);
  // Human-facing child progress must stay off JSON stdout; child argv stays raw.
  const childBin = join(scratch, 'bin'); mkdirSync(childBin);
  const order = join(scratch, 'child-order');
  const shellQuote = (text: string) => "'" + text.replaceAll("'", "'\\''") + "'";
  for (const [name, program] of [['ln', '/bin/ln'], ['mkfifo', '/usr/bin/mkfifo']] as const) {
    const stub = join(childBin, name);
    writeFileSync(stub, `#!/bin/sh\nprintf '${name} progress\\n'\nprintf '${name}\\n' >> ${shellQuote(order)}\nexec ${shellQuote(program)} "$@"\n`);
    chmodSync(stub, 0o700);
  }
  const progress = run('workspace-acceptance', ['--json', '--'], { env: { ...process.env, PATH: childBin + ':' + process.env.PATH } });
  success(progress); assert.deepEqual(progress.stdout, workspace.stdout);
  assert.equal(progress.stderr.toString(), 'ln progress\nmkfifo progress\n');
  assert.equal(readFileSync(order, 'utf8'), 'ln\nmkfifo\n');
  const fixturePath = join(scratch, 'workspace 雪');
  const generated = run('workspace-acceptance', ['--json', '--', 'fixture', fixturePath]);
  assert.equal(envelope(generated).result.filesWritten, 7);
  assert.ok(existsSync(join(fixturePath, 'rich/morphir-ir.10n')));
  assert.deepEqual(readFileSync(join(fixturePath, 'rich/morphir-ir.10n')), readFileSync(join(fixturePath, 'rich/morphir-ir.ionb')));
  envelope(run('workspace-acceptance', ['--json', '--', 'fixture', empty]), 1);
  const race = join(scratch, 'race'); mkdirSync(join(race, 'root/active'), { recursive: true }); mkdirSync(join(race, 'outside'));
  const raced = run('workspace-acceptance', ['--json', '--', 'race', race]);
  assert.equal(envelope(raced).result.iterations, 150);
  assert.deepEqual(readdirSync(join(race, 'root')), ['active']);
  envelope(run('workspace-acceptance', ['--json', '--', 'race', join(scratch, 'missing-race')]), 1);
  // Refuse finite bridge setup before launching a worker or creating a workspace.
  const blockedBridge = join(scratch, 'blocked-bridge'); mkdirSync(blockedBridge);
  writeFileSync(join(blockedBridge, '.dev'), 'preserve');
  const bridgeFailure = run('bridge-acceptance', ['--json', '--'], { cwd: blockedBridge });
  envelope(bridgeFailure, 1); assert.equal(bridgeFailure.signal, null); assert.equal(bridgeFailure.stderr.length, 0);
  assert.equal(readFileSync(join(blockedBridge, '.dev'), 'utf8'), 'preserve');
  assert.deepEqual(readdirSync(blockedBridge), ['.dev'], 'finite bridge refusal has no workspace effects');
  }
  successful = true;
  console.log(JSON.stringify(summary()));
} catch (error) {
  primaryFailure = error; hasPrimaryFailure = true;
} finally {
  try { rmSync(scratch, { recursive: true, force: true }); }
  catch (error) { secondaryFailures.push(error); }
  try { retain(); }
  catch (error) { secondaryFailures.push(error); }
}
if (hasPrimaryFailure) {
  if (secondaryFailures.length) throw new AggregateError([primaryFailure, ...secondaryFailures], 'Owner checks failed; receipt or cleanup also failed', { cause: primaryFailure });
  throw primaryFailure;
}
if (secondaryFailures.length) throw new AggregateError(secondaryFailures, 'Receipt or cleanup failed');
