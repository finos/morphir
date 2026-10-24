import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// CPU-only host qualification. Build each selected current target once and one
// native git/gh fixture; no shell shims, downloads, live API or historical builds.
// CI_EVIDENCE_JSON_TARGET=native|wasm|all (default all).
// CI_EVIDENCE_JSON_RECEIPTS selects the raw receipt directory, without binaries.
const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const selection = process.env.CI_EVIDENCE_JSON_TARGET ?? 'all';
assert.ok(['native', 'wasm', 'all'].includes(selection), `Unsupported CI_EVIDENCE_JSON_TARGET=${selection}`);
const targets: ('native' | 'wasm')[] = selection === 'all' ? ['native', 'wasm'] : [selection as 'native' | 'wasm'];
const receipts = resolve(repository, process.env.CI_EVIDENCE_JSON_RECEIPTS ?? '.dev/ci-evidence-json-delta/tests');
const scratch = realpathSync(mkdtempSync(join(tmpdir(), 'morphir evidence JSON λ ')));
const bin = join(scratch, 'bin');
const cwd = join(scratch, 'cwd space 雪');
const responsesFile = join(scratch, 'responses.json');
const journal = join(scratch, 'journal.jsonl');
const home = process.env.MOON_HOME;
const moon = home ? join(home, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon') : 'moon';
const moonrun = home ? join(home, 'bin', process.platform === 'win32' ? 'moonrun.exe' : 'moonrun') : 'moonrun';
const source = 'scripts/ci-evidence.mbtx';
const sourceBytes = readFileSync(join(repository, source));
const fixtureBytes = readFileSync(fileURLToPath(import.meta.url));
const sha256 = (bytes: string | Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const gitBlob = (bytes: Uint8Array) => createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
const startedAt = new Date().toISOString();
const builds: object[] = [];
const cases: object[] = [];
let sequence = 0;
let failure: unknown;
mkdirSync(receipts, { recursive: true });
mkdirSync(bin);
mkdirSync(join(cwd, '.github/workflows'), { recursive: true });
copyFileSync(join(repository, '.github/workflows/qualification.yml'), join(cwd, '.github/workflows/qualification.yml'));

// Remove Windows PATH aliases before applying the authoritative fixture PATH.
function fixtureEnvironment(env: NodeJS.ProcessEnv, windows = process.platform === 'win32'): NodeJS.ProcessEnv {
  return Object.fromEntries(Object.entries(env).filter(([key]) => !windows || key.toUpperCase() !== 'PATH' || key === 'PATH'));
}
assert.deepEqual(fixtureEnvironment({ Path: 'inherited', PATH: bin, KEEP: 'yes' }, true), { PATH: bin, KEEP: 'yes' });
const childEnv = fixtureEnvironment({ ...process.env, PATH: bin + delimiter + process.env.PATH,
  GITHUB_REPOSITORY: undefined, CI_MACOS_REQUESTED: undefined, GITHUB_OUTPUT: undefined,
  FIXTURE_JOURNAL: journal, FIXTURE_RESPONSES: responsesFile, FIXTURE_MARKER: 'inherited λ $;`' });
function persist() {
  writeFileSync(join(receipts, 'cases.json'), JSON.stringify({ host: `${process.platform}/${process.arch}`, selection,
    startedAt, finishedAt: new Date().toISOString(), source: { path: source, sha256: sha256(sourceBytes), blob: gitBlob(sourceBytes) },
    fixture: { sha256: sha256(fixtureBytes), blob: gitBlob(fixtureBytes) },
    toolchain: { moon, moonrun, moonHome: home, processCompatibilityVersion: process.version, executable: process.execPath, bun: process.versions.bun ?? null },
    environment: { PATH: childEnv.PATH, MOON_HOME: home }, builds, cases, ...(failure ? { failure: String(failure) } : {}) }, null, 2) + '\n');
}
function build(path: string, target: 'native' | 'wasm', name: string) {
  const destination = join(scratch, 'build', name);
  const args = ['build', path, '--target', target, '--target-dir', destination];
  const start = performance.now();
  const result = spawnSync(moon, args, { cwd: repository, timeout: 120_000, maxBuffer: 16 * 1024 * 1024 });
  const out = result.stdout ?? Buffer.alloc(0), err = result.stderr ?? Buffer.alloc(0);
  const id = `build-${name}`;
  writeFileSync(join(receipts, `${id}.stdout`), out);
  writeFileSync(join(receipts, `${id}.stderr`), err);
  const artifact = join(destination, basename(path), target, 'debug/build/single', `single.${target === 'native' ? 'exe' : 'wasm'}`);
  builds.push({ executable: moon, argv: args, cwd: repository, status: result.status, signal: result.signal,
    error: result.error?.message, stdout: `${id}.stdout`, stderr: `${id}.stderr`, milliseconds: performance.now() - start,
    artifact, artifactSha256: existsSync(artifact) ? sha256(readFileSync(artifact)) : null });
  persist();
  assert.ifError(result.error);
  assert.equal(result.status, 0, err.toString('utf8'));
  assert.ok(existsSync(artifact), artifact);
  return artifact;
}
const stubSource = `import {
  "moonbitlang/async@0.22.1", "moonbitlang/async@0.22.1/fs",
  "moonbitlang/async@0.22.1/stdio", "moonbitlang/core/env",
  "moonbitlang/core/json", "moonbitlang/x@0.5.5/sys",
}
async fn main {
  let argv = @env.args()
  let program = argv[0].replace(old="\\\\", new="/").split("/").last().unwrap().to_owned().replace(old=".exe", new="")
  let args = argv[1:].to_owned()
  let entry : Json = { "program": program, "args": args, "cwd": @fs.realpath("."), "expectedCwd": @fs.realpath(@env.get_env_var("FIXTURE_EXPECTED_CWD").unwrap()), "marker": @env.get_env_var("FIXTURE_MARKER").unwrap_or("") }
  @fs.write_file(@env.get_env_var("FIXTURE_JOURNAL").unwrap(), entry.stringify() + "\\n", append=true, create_mode=@fs.OpenOrCreate)
  guard @fs.read_file(@env.get_env_var("FIXTURE_RESPONSES").unwrap()).json() is Array(items) else { fail("Invalid responses") }
  for item in items {
    guard item is { "program": String(name), "args": wanted, "stdout": String(out), "stderr": String(err), "status": Number(status, ..), .. } else { fail("Invalid response") }
    if program == name && wanted == Json::array(args.map(Json::string)) {
      @stdio.stdout.write(out)
      @stdio.stderr.write(err)
      @sys.exit(status.to_int())
    }
  }
  @stdio.stderr.write("Unexpected fixture call " + entry.stringify() + "\\n")
  @sys.exit(99)
}
`;
type Response = { program: string; args: string[]; stdout: string; stderr: string; status: number };
const response = (program: string, args: string[], stdout: string, status = 0, stderr = ''): Response => ({ program, args, stdout, status, stderr });
const gitArgs = ['ls-tree', '-r', '-z', '--full-tree', 'HEAD'];
const listing = '100644 blob a1\tpkgs/λ file.mbt\0' + '100644 blob b2\tREADME.md\0';
const fingerprint = sha256('macos-evidence v1\nlanes macos\n100644 a1\tpkgs/λ file.mbt\n');
const sha = '47bcca94909f1749500b003c55680868b00d330e';
const artifactName = `macos-evidence-v1-${fingerprint}`;
const repo = 'finos/morphir-moonbit';
const issueArgs = ['issue', 'list', '--repo', repo, '--label', 'macos-breach', '--state', 'open', '--json', 'number', '--limit', '100'];
const artifactArgs = ['api', '--paginate', '--slurp', `repos/${repo}/actions/artifacts?name=${artifactName}&per_page=100`];
const runArgs = ['api', `repos/${repo}/actions/runs/501`];
const compareArgs = ['api', `repos/${repo}/compare/${sha}...refs/heads/main?per_page=1`, '--jq', '{status}'];
const git = response('git', gitArgs, listing);
const miss = [response('gh', issueArgs, '[]'), response('gh', artifactArgs, '[{"artifacts":[]}]')];
const evidence = { run: 501, artifact: 901, fingerprint, sha };
const hit = [response('gh', issueArgs, '[]'), response('gh', artifactArgs, JSON.stringify([{ artifacts: [{ id: 901, name: artifactName,
  expired: false, workflow_run: { id: 501, head_branch: 'main' } }] }])),
response('gh', runArgs, JSON.stringify({ id: 501, path: '.github/workflows/nightly-qualification.yml', event: 'schedule',
  head_branch: 'main', head_sha: sha, status: 'completed', conclusion: 'success',
  created_at: new Date(Date.now() - 3600_000).toISOString().replace(/\.\d{3}Z$/, 'Z'),
  repository: { full_name: repo, fork: false }, head_repository: { full_name: repo, fork: false } })),
response('gh', compareArgs, '{"status":"ahead"}')];
const recordArgs = (out = 'evidence space 雪.json') => ['record', '--fingerprint', fingerprint, '--sha', sha, '--run', '501', '--out', out];
const expectedRecord = { schema: 'macos-evidence-v1', lanes: 'macos', fingerprint, sha, run: 501 };
const decoder = new TextDecoder('utf-8', { fatal: true });
function jsonDocument(bytes: Buffer, legacyNewline: string, envelope: boolean) {
  assert.notDeepEqual([...bytes.subarray(0, 3)], [0xef, 0xbb, 0xbf], 'No UTF-8 BOM');
  const text = decoder.decode(bytes);
  const value = JSON.parse(text);
  const newline = envelope ? '\n' : legacyNewline;
  const body = text.slice(0, -newline.length);
  assert.ok(text.endsWith(newline) && !body.endsWith('\n'), 'Exactly one trailing newline');
  assert.ok(!body.includes('\r') && !body.includes('\n'), 'One compact JSON document');
  if (envelope) assert.ok(!bytes.includes(13), 'New envelopes have no CR');
  return value;
}
function qualify(target: 'native' | 'wasm', artifact: string) {
  const textNewline = target === 'native' && process.platform === 'win32' ? '\r\n' : '\n';
  const command = target === 'native' ? [artifact] : [moonrun, artifact, '--'];
  function invoke(label: string, args: string[], responses: Response[] = [], options: { env?: NodeJS.ProcessEnv; status?: number; json?: boolean; bare?: boolean; cwd?: string } = {}) {
    writeFileSync(responsesFile, JSON.stringify(responses));
    writeFileSync(journal, '');
    // Canonicalize both cwd identities in the native stub: Bun and MoonBit can
    // resolve Windows short-name aliases differently. Per-call cwd owns this env.
    const result = spawnSync(command[0]!, [...command.slice(1), ...args], { cwd: options.cwd ?? cwd, env: fixtureEnvironment({ ...childEnv, ...options.env, FIXTURE_EXPECTED_CWD: options.cwd ?? cwd }),
      timeout: 30_000, maxBuffer: 8 * 1024 * 1024 });
    const out = result.stdout ?? Buffer.alloc(0), err = result.stderr ?? Buffer.alloc(0);
    const callsBytes = readFileSync(journal);
    const calls = callsBytes.toString('utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
    const id = `${String(++sequence).padStart(3, '0')}-${target}-${label}`;
    writeFileSync(join(receipts, `${id}.stdout`), out);
    writeFileSync(join(receipts, `${id}.stderr`), err);
    writeFileSync(join(receipts, `${id}.children.jsonl`), callsBytes);
    cases.push({ id, target, executable: command[0], argv: [...command.slice(1), ...args], args, cwd: options.cwd ?? cwd,
      environment: { GITHUB_REPOSITORY: null, CI_MACOS_REQUESTED: null, GITHUB_OUTPUT: null, ...options.env },
      status: result.status, signal: result.signal, error: result.error?.message, stdout: `${id}.stdout`, stderr: `${id}.stderr`,
      children: `${id}.children.jsonl`, stdoutSha256: sha256(out), stderrSha256: sha256(err), childCount: calls.length });
    persist();
    assert.ifError(result.error);
    assert.equal(result.status, options.status ?? 0, `${id}: ${err.toString('utf8')} ${out.toString('utf8')}`);
    assert.equal(result.signal, null, id);
    for (const call of calls) {
      assert.equal(call.cwd, call.expectedCwd);
      assert.ok(responses.some(response => response.program === call.program && JSON.stringify(response.args) === JSON.stringify(call.args)), `Unexpected stub argv: ${JSON.stringify(call)}`);
      assert.equal(call.marker, childEnv.FIXTURE_MARKER);
      assert.ok(call.program === 'git' || call.program === 'gh');
    }
    const value = options.json ? jsonDocument(out, textNewline, !options.bare) : undefined;
    if (options.json && !options.bare) {
      assert.equal(value.profile, 'morphir/command-result');
      assert.equal(value.contractVersion, '0.1.0');
      assert.equal(value.exitCode, result.status);
      assert.deepEqual(value.diagnostics, []);
      assert.equal(value.state, result.status === 0 ? 'succeeded' : 'failed');
      assert.equal('result' in value, result.status === 0);
      assert.equal('error' in value, result.status !== 0);
      if (result.status !== 0) {
        assert.ok(['invalid-arguments', 'command-failed'].includes(value.error.code));
        assert.ok(value.error.message.length > 0);
      }
    }
    return { out, err, calls, value };
  }
  const prints = { lanes: 'macos', fingerprint, artifact: artifactName, inputs: 1 };
  assert.deepEqual(invoke('fingerprint-default', ['fingerprint'], [git]).out, Buffer.from(fingerprint + textNewline));
  assert.deepEqual(invoke('fingerprint-json', ['fingerprint', '--json'], [git], { json: true, bare: true }).value, prints);
  assert.deepEqual(invoke('fingerprint-root-json', ['--json', 'fingerprint'], [git], { json: true, bare: true }).value, prints);
  assert.deepEqual(invoke('fingerprint-duplicate-json', ['fingerprint', '--json', '--json'], [git], { json: true, bare: true }).value, prints);
  const lookupArgs = ['lookup', '--fingerprint', fingerprint, '--repo', repo];
  assert.equal(invoke('lookup-default', lookupArgs, miss).out.toString(), `run: no trusted evidence for ${artifactName}${textNewline}`);
  for (const [name, responses, answer] of [['miss', miss, null], ['hit', hit, evidence]] as const) {
    const r = invoke(`lookup-${name}`, [...lookupArgs, '--json'], [...responses], { json: true, bare: true });
    assert.deepEqual(r.value, { macos: answer ? 'reuse' : 'run', evidence: answer });
    assert.equal(r.calls.length, answer ? 4 : 2);
    const mode = invoke(`mode-${name}`, ['mode', '--requested', 'evidence', '--repo', repo, '--json'], [git, ...responses], { json: true, bare: true });
    assert.deepEqual(mode.value, { fingerprint, macos: answer ? 'reuse' : 'run', evidence: answer });
  }
  const fallback = invoke('lookup-retry-fallback', [...lookupArgs, '--json'], [response('gh', issueArgs, '', 7, 'fixture failure λ\n')], { json: true, bare: true });
  assert.deepEqual(fallback.value, { macos: 'run', evidence: null });
  assert.equal(fallback.calls.length, 2);
  assert.match(fallback.err.toString(), /::warning/);
  assert.equal(invoke('mode-default', ['mode', '--requested', 'run'], [git]).out.toString(), `macos=run for ${artifactName}${textNewline}`);
  for (const json of [false, true]) {
    const output = join(cwd, `github-output-${json}.txt`);
    writeFileSync(output, 'prefix\n');
    const r = invoke(`github-output-${json}`, ['mode', '--requested', 'run', '--github-output', ...(json ? ['--json'] : [])], [git], { json, bare: true, env: { GITHUB_OUTPUT: output } });
    assert.deepEqual(readFileSync(output), Buffer.from(`prefix\nfingerprint=${fingerprint}\nmacos=run\nevidence=\n`));
    assert.equal(r.calls.length, 1);
  }
  const textRecord = invoke('record-default', recordArgs(), [git]);
  const recordBytes = readFileSync(join(cwd, 'evidence space 雪.json'));
  assert.deepEqual(recordBytes, Buffer.from(JSON.stringify(expectedRecord) + '\n'));
  assert.equal(textRecord.out.toString(), `ci-evidence: wrote evidence space 雪.json for ${artifactName}${textNewline}`);
  for (const args of [[...recordArgs(), '--json'], ['--json', ...recordArgs()]]) {
    const r = invoke('record-json', args, [git], { json: true });
    assert.equal(r.value.command, 'ci.evidence.record');
    assert.deepEqual(r.value.result, { output: 'evidence space 雪.json', artifact: artifactName, evidence: expectedRecord });
    assert.deepEqual(readFileSync(join(cwd, 'evidence space 雪.json')), recordBytes);
    assert.equal(r.err.length, 0);
  }
  for (const literal of ['--json', '--help', '--', 'λ 雪 $;`']) {
    const args = [...recordArgs().slice(0, -2), `--out=${literal}`];
    const r = invoke('record-inline-literal', args, [git]);
    assert.equal(r.out.toString(), `ci-evidence: wrote ${literal} for ${artifactName}${textNewline}`);
    assert.deepEqual(readFileSync(join(cwd, literal)), recordBytes);
  }
  const defaultTest = invoke('self-test-default', ['--self-test']);
  assert.equal(defaultTest.calls.length, 0);
  assert.match(defaultTest.out.toString(), /argparse forms and refusals pass\r?\n$/);
  const jsonTest = invoke('self-test-json', ['--self-test', '--json'], [], { json: true });
  assert.deepEqual(jsonTest.value.result, { passed: true });
  assert.equal(jsonTest.value.command, 'ci.evidence.self-test');
  assert.deepEqual(jsonTest.err, defaultTest.out);
  assert.equal(jsonTest.calls.length, 0);
  const failedTest = invoke('self-test-missing-workflow', ['--json', '--self-test'], [], { json: true, status: 1, cwd: bin });
  assert.equal(failedTest.value.error.code, 'command-failed');
  assert.equal(failedTest.calls.length, 0);
  assert.equal(failedTest.err.toString(), 'ci-evidence: fingerprint cases pass' + textNewline);
  for (const args of [[], ['--bogus'], ['fingerprint', 'extra'], ['fingerprint', '--', '--json'],
    ['lookup', '--fingerprint', fingerprint, '--repo=--json'],
    ['mode', '--requested', 'run', '--requested', 'evidence']]) {
    const r = invoke('default-refusal', args, [], { status: 1 });
    assert.equal(r.calls.length, 0);
    assert.equal((target === 'native' ? r.out : r.err).length, 0);
    assert.match((target === 'native' ? r.err : r.out).toString(), /^(Failure\(|error:)/);
  }
  for (const args of [['--json', '--help'], ['--help', '--json'], ['--json', '-h'], ['help', '--json'],
    ...['fingerprint', 'lookup', 'mode', 'record'].flatMap(name => [[name, '--help', '--json'], ['--json', name, '-h'], ['help', name, '--json']])]) {
    const r = invoke('help-json', args, [], { json: true });
    assert.equal(r.value.command, 'ci.evidence.help');
    assert.match(r.value.result.help, /^Usage:/);
    assert.match(r.value.result.json, /contractVersion 0.1.0/);
    assert.equal(r.calls.length, 0);
    assert.equal(r.err.length, 0);
  }
  const invalid = [[], ['unknown'], ['--bogus'], ['lookup'], ['mode'], ['record'],
    ['fingerprint', '--bogus'], ['fingerprint', 'extra'], ['fingerprint', '--', '--json'],
    ['lookup', '--fingerprint'], ['lookup', '--fingerprint', ''], ['lookup', '--fingerprint', 'λ 雪', '--repo', repo],
    ['lookup', '--fingerprint', fingerprint, '--repo', '--help'],
    ['lookup', '--fingerprint', fingerprint, '--repo=--json'],
    ['lookup', '--fingerprint', fingerprint, '--repo', 'owner'],
    ['mode', '--requested', 'invalid'], ['mode', '--requested', ''],
    ['mode', '--requested', 'run', '--requested', 'evidence'],
    ['record', '--fingerprint', fingerprint, '--sha', 'HEAD', '--run', '501', '--out', 'x'],
    ['record', '--fingerprint', fingerprint, '--sha', sha, '--run', '-3', '--out', 'x'],
    ['record', '--fingerprint', fingerprint, '--sha', sha, '--run', '501', '--out'],
    [...recordArgs(), 'extra'], [...recordArgs(), '--run', '502'], ['help', 'unknown']];
  for (const args of invalid) {
    const r = invoke('refusal', ['--json', ...args], [], { json: true, status: 1 });
    assert.equal(r.calls.length, 0);
    assert.equal(r.err.length, 0);
  }
  for (const args of [['lookup', '--json'], ['record', '--json'], ['mode', '--requested', 'invalid', '--json'],
    ['fingerprint', '--bogus', '--json'], ['mode', '--requested', '--json'], [...recordArgs(), '--run', '502', '--json']]) {
    assert.equal(invoke('subcommand-refusal', args, [], { json: true, status: 1 }).calls.length, 0);
  }
  for (const [name, args, responses] of [
    ['git-status', ['fingerprint', '--json'], [response('git', gitArgs, '', 37, 'git fixture failure λ\n')]],
    ['git-malformed', ['fingerprint', '--json'], [response('git', gitArgs, 'bad record\0')]],
    ['empty-tree', ['fingerprint', '--json'], [response('git', gitArgs, '')]],
    ['record-mismatch', [...recordArgs(), '--json'], [response('git', gitArgs, listing.replace('a1', 'c3'))]],
    ['record-write', [...recordArgs('missing/output.json'), '--json'], [git]],
    ['record-empty-out', [...recordArgs(''), '--json'], [git]],
    ['mode-repo', ['mode', '--requested', 'evidence', '--json'], [git]],
    ['mode-output-env', ['mode', '--requested', 'run', '--github-output', '--json'], [git]],
    ['mode-output-write', ['mode', '--requested', 'run', '--github-output', '--json'], [git]],
  ] as [string, string[], Response[]][]) {
    const r = invoke(name, args, responses, { json: true, status: 1,
      ...(name === 'mode-output-write' ? { env: { GITHUB_OUTPUT: join(cwd, 'missing/output') } } : {}) });
    assert.equal(r.value.error.code, 'command-failed');
    assert.equal(r.calls.length, 1);
    assert.equal(r.err.length, 0);
  }
  const inherited = invoke('environment-defaults', ['mode', '--json'], [git], { json: true, bare: true,
    env: { CI_MACOS_REQUESTED: 'run', GITHUB_REPOSITORY: repo, FIXTURE_EXPECTED_CWD: bin } });
  assert.deepEqual(inherited.value, { fingerprint, macos: 'run', evidence: null });
}
try {
  const stubPath = join(scratch, 'executor.mbtx');
  writeFileSync(stubPath, stubSource);
  const stub = build(stubPath, 'native', 'executor');
  for (const name of ['git', 'gh']) copyFileSync(stub, join(bin, name + (process.platform === 'win32' ? '.exe' : '')));
  for (const target of targets) qualify(target, build(source, target, `ci-evidence-${target}`));
  console.log(`ci-evidence JSON presentation: ${cases.length} explicit-argv cases pass (${targets.join(', ')}); receipts ${receipts}`);
} catch (error) {
  failure = error;
  throw error;
} finally {
  persist();
  rmSync(scratch, { recursive: true, force: true });
}
