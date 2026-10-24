// Current-candidate cross-process regression. Run with the repository's pinned
// MoonBit and Bun on PATH. Compile each script once, then reuse it.
// CI_JSON_TARGET=native also exercises the native byte writer on the current host.
// No historical objects, shell stubs, authentication, downloads or Rust builds.
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const root = resolve(import.meta.dir, '..');
const moon = Bun.which('moon'), moonrun = Bun.which('moonrun'), git = Bun.which('git');
assert(moon && moonrun && git, 'Pinned moon/moonrun and Git must be on PATH');
const scratch = realpathSync(mkdtempSync(join(tmpdir(), 'morphir-ci-json-')));
const started = performance.now();
const receipts = process.env.CI_JSON_RECEIPTS;
if (receipts) mkdirSync(receipts, { recursive: true });
const names = ['artifact', 'changes', 'gate', 'measure', 'mise-impact', 'native-build', 'provider-release', 'provider-tools', 'reuse'];
const target = process.env.CI_JSON_TARGET ?? 'wasm';
assert(target === 'wasm' || target === 'native', 'CI_JSON_TARGET must be wasm or native');
const artifacts = new Map<string, string>();
const builds: object[] = [];
const evidence: object[] = [];
let cases = 0;
type Result = { status: number; signal: string | null; out: string; err: string; bytes: Uint8Array };
async function processResult(argv: string[], cwd: string, env: Record<string, string | undefined>): Promise<Result> {
  const child = Bun.spawn(argv, { cwd, env, stdin: 'ignore', stdout: 'pipe', stderr: 'pipe' });
  const [stdout, err, status] = await Promise.all([new Response(child.stdout).arrayBuffer(), new Response(child.stderr).text(), child.exited]);
  assert.equal(child.signalCode, null, `Unexpected signal from ${argv[0]}: ${child.signalCode}`);
  const bytes = new Uint8Array(stdout);
  const out = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  return { out, err, status, signal: child.signalCode, bytes };
}
async function run(name: string, argv: string[], env: Record<string, string> = {}, cwd = scratch): Promise<Result> {
  const inherited = { ...process.env };
  for (const key of ['GITHUB_OUTPUT', 'MORPHIR_PROVIDER_RUST', 'GITHUB_REPOSITORY', 'CI_NEEDS', 'CI_INPUTS', 'CI_REQUIRED_JOBS', 'CI_MACOS_MODE', 'CI_MACOS_EVIDENCE', 'EVENT', 'GITHUB_REF']) delete inherited[key];
  // With no child executable available, help/parse-only cases cannot accidentally
  // acquire anything. The receipt cases explicitly restore PATH for local Git.
  const command = target === 'wasm' ? [moonrun!, artifacts.get(name)!, '--', ...argv] : [artifacts.get(name)!, ...argv];
  const result = await processResult(command, cwd, { ...inherited, PATH: scratch, ...env });
  const id = `${String(++cases).padStart(3, '0')}-${name}`;
  evidence.push({ id, name, command, cwd, argv, env, status: result.status, signal: result.signal, stdout: result.out, stderr: result.err });
  if (receipts) {
    writeFileSync(join(receipts, `${id}.stdout`), result.bytes);
    writeFileSync(join(receipts, `${id}.stderr`), result.err);
  }
  return result;
}
function json(result: Result, status = 0): any {
  assert.equal(result.status, status, result.err + result.out);
  assert.equal(result.bytes.at(-1), 0x0a, 'JSON must end with LF');
  assert.equal(result.bytes.at(-2), 0x7d, 'JSON must end with a closing object before LF');
  assert.equal(result.bytes.includes(0x0d), false, 'JSON must contain no CR bytes');
  assert.equal(result.bytes.filter(byte => byte === 0x0a).length, 1, 'JSON must have one physical LF');
  const data = JSON.parse(result.out);
  assert.equal(JSON.stringify(data) + '\n', result.out, 'Expected one compact JSON value and LF');
  return data;
}
function success(result: Result): any {
  const data = json(result);
  assert.equal(data.profile, 'morphir/command-result');
  assert.equal(data.contractVersion, '0.1.0');
  assert.equal(data.state, 'succeeded');
  assert.equal(data.exitCode, 0);
  assert.deepEqual(data.diagnostics, []);
  return data.result;
}
function failure(result: Result): any {
  const data = json(result, 1);
  assert.equal(data.profile, 'morphir/command-result');
  assert.equal(data.contractVersion, '0.1.0');
  assert.deepEqual(data.diagnostics, []);
  assert.equal(data.state, 'failed');
  assert.equal(data.exitCode, 1);
  assert(!('result' in data));
  assert.equal(typeof data.error.message, 'string');
  return data;
}
try {
  for (const name of names) {
    const command = [moon!, 'run', join(root, 'scripts', `ci-${name}.mbtx`), '--build-only', '--target', target, '--target-dir', join(scratch, 'build')];
    const compiled = await processResult(command, root, process.env);
    builds.push({ name, command, cwd: root, status: compiled.status, signal: compiled.signal, stdout: compiled.out, stderr: compiled.err });
    assert.equal(compiled.status, 0, compiled.err + compiled.out);
    const paths = JSON.parse(compiled.out).artifacts_path;
    assert.equal(paths.length, 1);
    artifacts.set(name, paths[0]);
  }
  for (const name of names) {
    const help = success(await run(name, ['--json', '--', '--help'], { GITHUB_OUTPUT: join(scratch, 'missing/output'), MORPHIR_PROVIDER_RUST: join(scratch, 'missing-rust') }));
    assert(help.help.includes('Usage:'), `${name} render_help missing`);
  }
  for (const [name, argv] of [
    ['artifact', []], ['changes', ['--unknown']], ['gate', ['--unknown']],
    ['measure', ['bad']], ['mise-impact', []], ['native-build', ['unsupported']],
    ['provider-release', ['extra']], ['provider-tools', []],
    ['reuse', ['push', '--sha=bad', '--before=bad']],
  ] as [string, string[]][]) failure(await run(name, ['--json', '--', ...argv]));
  for (const name of ['changes', 'gate', 'reuse']) {
    const help = await run(name, ['--help']);
    assert.equal(help.status, 0); assert(help.out.startsWith('Usage:'));
    failure(await run(name, ['--json', '--unknown']));
  }
  const test = await run('measure', ['--self-test', '--json']);
  assert.equal(success(test).passed, true);
  assert(test.err.includes('ci-measure: overlapping jobs'));

  assert.equal(success(await run('provider-tools', ['--json', '--', '--self-test'])).passed, true);
  failure(await run('gate', ['--receipt', '--json']));
  failure(await run('reuse', ['push', '--sha', '--json']));
  failure(await run('reuse', ['--json', 'push', '--sha', '--help']));

  // JSON help must pass the complete grammar, even when help precedes bad syntax.
  // These first three invocations reproduce the review's success-on-error defect.
  for (const [name, argv] of [
    ['reuse', ['push', '--json', '--unknown', '--help']],
    ['changes', ['--json', '--event', '--unknown', '--help']],
    ['gate', ['--json', '--unknown', '--help']],
    ['reuse', ['push', '--json', '--help', '--unknown']],
    ['changes', ['--json', '--help', '--event', '--unknown']],
    ['gate', ['--json', '--help', '--unknown']],
    ['reuse', ['--json', 'queue', '--unknown', '-h']],
    ['gate', ['--receipt', '--json', '--help']],
    ['gate', ['--json', '--help', '--receipt']],
    ['reuse', ['push', '--json', '--sha', '--help']],
    ['reuse', ['push', '--json', '--help', '--sha']],
    ['reuse', ['queue', '--json', '--base', '-h']],
    ['reuse', ['queue', '--json', '-h', '--base']],
    ['gate', ['--json', 'extra', '--help']],
    ['gate', ['--json', '--help', 'extra']],
    ['changes', ['--json', 'base', 'head', 'extra', '--help']],
    ['changes', ['--json', '--help', 'base', 'head', 'extra']],
    ['reuse', ['push', '--json', 'extra', '--help']],
    ['reuse', ['push', '--json', '--help', 'extra']],
    ['reuse', ['queue', '--json', 'extra', '-h']],
    ['changes', ['--json', '--self-test', '--event', '--help']],
    ['gate', ['--json', '--native', '--installed', '--help']],
    ['gate', ['--json', '--qualification-plan', '--qualification']],
    ['gate', ['--qualification-plan', '--json', '--receipt', 'x']],
    ['gate', ['--json', '--qualification-plan', '--native', '--help']],
    ['gate', ['--qualification-plan', '--json', '--unknown', '--help']],
    ['gate', ['--json', '--help', '--qualification-plan', '--receipt']],
    ['changes', ['--json', '--help', 'base']],
    ['reuse', ['push', '--json', '--sha=' + 'a'.repeat(40)]],
    ['reuse', ['queue', '--json', '--ref=ref']],
  ] as [string, string[]][]) {
    const malformed = await run(name, argv);
    const data = failure(malformed);
    assert.equal(data.command, 'ci.' + name);
    assert.equal(malformed.err, '', 'JSON syntax errors belong on stdout');
  }
  for (const name of ['changes', 'gate', 'reuse']) {
    const human = await run(name, ['--help']);
    for (const argv of [['--json', '--help'], ['--help', '--json'], ['-h', '--json'], ['--json', '--', '-h']]) {
      const rendered = await run(name, argv, { GITHUB_OUTPUT: join(scratch, 'missing/output') });
      assert.equal(success(rendered).help, human.out);
      assert.equal(rendered.err, '');
    }
    // The existing built-in human help short-circuits later tokens unchanged.
    const legacy = await run(name, ['--help', '--unknown']);
    assert.equal(legacy.status, 0); assert.equal(legacy.out, human.out);
  }
  for (const child of ['push', 'queue']) {
    const human = await run('reuse', [child, '--help']);
    assert.equal(human.status, 0);
    assert(human.out.startsWith('Usage: ci-reuse ' + child + ' '));
    for (const argv of [
      ['--json', child, '--help'], [child, '--json', '--help'],
      [child, '--help', '--json'], [child, '-h', '--json'],
      ['--json', '--', child, '--help'],
    ]) {
      const rendered = await run('reuse', argv, { GITHUB_REPOSITORY: 'fixture/repo' });
      assert.equal(success(rendered).help, human.out, 'Help must describe the selected child');
      assert.equal(rendered.err, '');
    }
  }
  for (const [name, argv] of [
    ['gate', ['--receipt=--json', '--help']],
    ['reuse', ['push', '--repo=--json', '--help']],
    ['reuse', ['queue', '--repo=--json', '-h']],
  ] as [string, string[]][]) {
    const literal = await run(name, argv);
    assert.equal(literal.status, 0); assert(literal.out.startsWith('Usage:'));
    const explicit = await run(name, ['--json', '--', ...argv]);
    assert.equal(success(explicit).help, literal.out);
  }

  // Fixed data operands remain literal, including flag-shaped values.
  for (const [name, argv] of [
    ['native-build', ['--json']], ['measure', ['--json']], ['measure', ['--json', '--logs']],
  ] as [string, string[]][]) {
    const literal = await run(name, argv);
    assert.equal(literal.status, 1);
    assert((literal.out + literal.err).includes('Failure('));
    assert(!literal.out.includes('morphir/command-result'));
  }
  for (const literal of ['', 'λ 雪', '--', '--json']) failure(await run('native-build', ['--json', '--', literal]));
  const pair = json(await run('mise-impact', ['--self-test', '--json']));
  assert.equal(pair.full, true); assert(!('contractVersion' in pair));
  const nested = json(await run('mise-impact', ['--json', '--', '--self-test', '--json']));
  assert.deepEqual(nested, pair, 'Reserved prefix must unwrap only once');

  const output = join(scratch, 'github-output');
  writeFileSync(output, 'existing=true\n');
  const selected = json(await run('changes', ['--event', '--json'], { EVENT: 'workflow_dispatch', GITHUB_OUTPUT: output }));
  assert.equal(typeof selected.code, 'boolean'); assert(!('contractVersion' in selected));
  const text = await run('changes', ['--event'], { EVENT: 'workflow_dispatch' });
  assert.equal(text.status, 0);
  assert.equal(readFileSync(output, 'utf8'), 'existing=true\n' + text.out);
  failure(await run('changes', ['--event', '--json'], { EVENT: 'workflow_dispatch', GITHUB_OUTPUT: join(scratch, 'missing/output') }));

  const gate = { CI_NEEDS: '{"lint":{"result":"success"}}', CI_REQUIRED_JOBS: '["lint"]' };
  assert.equal(success(await run('gate', ['--json'], gate)).passed, true);
  assert.equal((await run('gate', [], gate)).out, 'All selected checks passed; unselected checks may be skipped.\n');
  failure(await run('gate', ['--json'], { ...gate, CI_NEEDS: '{"lint":{"result":"skipped"}}' }));
  for (const [mode, inputs, jobs] of [
    ['native', { runner: 'macos-15' }, ['native-cli', 'mep-process']],
    ['installed', { lifecycle: true }, ['lifecycle']],
  ] as [string, object, string[]][]) {
    const needs = Object.fromEntries(jobs.map(j => [j, { result: 'success' }]));
    const result = success(await run('gate', ['--json', '--' + mode], { CI_NEEDS: JSON.stringify(needs), CI_INPUTS: JSON.stringify(inputs) }));
    assert.equal(result.mode, mode); assert.deepEqual(result.requiredJobs, jobs);
  }

  const hooks = join(scratch, 'empty-hooks'); mkdirSync(hooks);
  const gitResult = (args: string[]) => {
    const p = Bun.spawnSync([git!, '-c', 'user.name=CI fixture', '-c', 'user.email=ci@example.invalid', '-c', 'commit.gpgsign=false', '-c', `core.hooksPath=${hooks}`, ...args], { cwd: scratch });
    assert.equal(p.exitCode, 0, p.stderr.toString()); return p.stdout.toString().trim();
  };
  gitResult(['init', '-q']); writeFileSync(join(scratch, 'fixture.txt'), 'fixture\n');
  gitResult(['add', 'fixture.txt']); gitResult(['commit', '-qm', 'fixture']);
  const sha = gitResult(['rev-parse', 'HEAD']);
  const env = { ...gate, PATH: process.env.PATH!, GITHUB_SHA: sha, GITHUB_REPOSITORY: 'fixture/repo', GITHUB_RUN_ID: '42', GITHUB_RUN_ATTEMPT: '1', EVENT: 'workflow_dispatch', CI_SELECTION: '{}' };
  const receiptPath = join(scratch, 'receipt.json');
  const receipt = await run('gate', ['--json', '--receipt', receiptPath], env);
  assert.equal(json(receipt).profile, 'morphir-ci-receipt-v1');
  assert.equal(receipt.out, readFileSync(receiptPath, 'utf8') + '\n');
  const literalReceipt = await run('gate', ['--receipt=--json'], env);
  assert.equal(literalReceipt.status, 0);
  assert.equal(literalReceipt.out, 'All selected checks passed; unselected checks may be skipped.\n');
  assert.equal(JSON.parse(readFileSync(join(scratch, '--json'), 'utf8')).profile, 'morphir-ci-receipt-v1');
  // Qualification v2 has its own fixed jobs; the ordinary CI receipt stays v1.
  const baseJobs = ['plan', 'setup', 'native', 'installed', 'packaged'];
  const macosJobs = ['macos-setup', 'macos-native', 'macos-installed', 'macos-supervision', 'macos-headless'];
  type Needs = Record<string, { result: string }>;
  const qualificationNeeds = (mode: string): Needs => Object.fromEntries([
    ...baseJobs.map(job => [job, { result: 'success' }]),
    ...macosJobs.map(job => [job, { result: mode === 'run' ? 'success' : 'skipped' }]),
  ]);
  const macosEvidence = { run: 41, artifact: 123, fingerprint: 'a'.repeat(64), sha };
  const modeEnv = (mode: string, event = 'workflow_dispatch', ref = 'refs/heads/main') => ({
    CI_MACOS_MODE: mode, CI_MACOS_EVIDENCE: mode === 'reuse' ? JSON.stringify(macosEvidence) : '',
    EVENT: event, GITHUB_REF: ref,
  });
  const qualificationDir = join(scratch, '.dev/qualification');
  const qualificationPath = join(qualificationDir, 'receipt.ionb');
  const clearQualification = () => rmSync(qualificationDir, { recursive: true, force: true });
  const assertNoQualification = () => {
    assert.equal(existsSync(qualificationPath), false, 'Refusal must not write a qualification receipt');
    assert.equal(existsSync(qualificationDir), false, 'Refusal must not create the qualification directory');
  };
  async function qualify(mode: string, argv = ['--json', '--qualification']) {
    clearQualification();
    const needs = qualificationNeeds(mode);
    const result = await run('gate', argv, { ...env, ...modeEnv(mode), CI_NEEDS: JSON.stringify(needs) });
    const qualified = json(result);
    assert.equal(result.err, '');
    assert.deepEqual(qualified, {
      profile: 'morphir-ci-qualification-v2', revision: sha, repository: 'fixture/repo',
      runId: '42', runAttempt: '1', macos: mode, macosEvidence: mode === 'reuse' ? macosEvidence : null,
      requiredJobs: mode === 'run' ? [...baseJobs, ...macosJobs] : baseJobs, results: needs,
    });
    const ion = readFileSync(qualificationPath);
    assert.deepEqual([...ion.subarray(0, 4)], [0xe0, 0x01, 0x00, 0xea], 'Qualification must write binary Ion');
    assert(ion.includes(Buffer.from('morphir_ci_qualification_v2')), 'Ion must carry the v2 annotation');
    return result;
  }
  const qualifiedSkip = await qualify('skip');
  await qualify('run', ['--qualification', '--json']);
  await qualify('reuse', ['--json', '--', '--qualification']);

  // The plan is a bare object in both legacy and explicit JSON presentation.
  // Every case supplies the workflow event and macOS inputs, never ambient CI.
  const mergePaths = [
    ['pull_request', 'refs/pull/1/merge'], ['pull_request_target', 'refs/heads/main'],
    ['merge_group', 'refs/heads/gh-readonly-queue/main/pr-1-abc'], ['push', 'refs/heads/main'],
  ];
  for (const [event, ref] of mergePaths) {
    for (const argv of [['--qualification-plan'], ['--json', '--qualification-plan'], ['--qualification-plan', '--json'], ['--json', '--', '--qualification-plan']]) {
      clearQualification();
      const planned = await run('gate', argv, modeEnv('skip', event, ref));
      assert.deepEqual(json(planned), { macos: 'skip' }); assert.equal(planned.err, '');
      assertNoQualification();
    }
    for (const mode of ['run', 'reuse']) {
      clearQualification();
      const refused = await run('gate', ['--qualification-plan', '--json'], modeEnv(mode, event, ref));
      assert(failure(refused).error.message.includes('is not allowed'));
      assert.equal(refused.err, ''); assertNoQualification();
    }
  }
  for (const [event, ref, mode] of [
    ['workflow_dispatch', 'refs/heads/main', 'run'], ['schedule', 'refs/heads/main', 'run'],
    ['push', 'refs/tags/v1.0.0', 'run'], ['workflow_dispatch', 'refs/heads/main', 'reuse'],
    ['schedule', 'refs/heads/main', 'reuse'],
  ] as const) {
    const planned = await run('gate', ['--json', '--', '--qualification-plan'], modeEnv(mode, event, ref));
    assert.deepEqual(json(planned), { macos: mode }); assert.equal(planned.err, '');
    assertNoQualification();
  }
  for (const [inputs, message] of [
    [modeEnv('reuse', 'push', 'refs/tags/v1.0.0'), 'A release must run macOS'],
    [{ ...modeEnv('reuse'), CI_MACOS_EVIDENCE: '' }, 'needs CI_MACOS_EVIDENCE'],
    [{ ...modeEnv('run'), CI_MACOS_EVIDENCE: JSON.stringify(macosEvidence) }, 'only for macOS mode reuse'],
    [{ ...modeEnv('skip'), CI_MACOS_EVIDENCE: JSON.stringify(macosEvidence) }, 'only for macOS mode reuse'],
    [modeEnv('always'), 'Unknown macOS mode'],
    [{ ...modeEnv('reuse'), CI_MACOS_EVIDENCE: JSON.stringify({ ...macosEvidence, artifact: 0 }) }, 'positive integer'],
  ] as [Record<string, string>, string][]) {
    const refused = await run('gate', ['--json', '--qualification-plan'], inputs);
    assert(failure(refused).error.message.includes(message));
    assert.equal(refused.err, ''); assertNoQualification();
  }

  // Refuse each incomplete or unsuccessful fixed job, and mode-inconsistent
  // macOS results. Removing the prior receipt prevents stale success masking a write.
  async function refuseQualification(mode: string, needs: Needs, extra: Record<string, string> = {}, message: string) {
    clearQualification();
    const refused = await run('gate', ['--json', '--qualification'], {
      ...env, ...modeEnv(mode), CI_NEEDS: JSON.stringify(needs), ...extra,
    });
    assert(failure(refused).error.message.includes(message), refused.out);
    assert.equal(refused.err, ''); assertNoQualification();
  }
  for (const mode of ['skip', 'run', 'reuse']) {
    for (const job of baseJobs) {
      for (const state of ['skipped', 'failure', 'cancelled', 'missing']) {
        const needs = qualificationNeeds(mode);
        if (state === 'missing') delete needs[job]; else needs[job] = { result: state };
        await refuseQualification(mode, needs, {}, job);
      }
    }
    for (const job of macosJobs) {
      for (const state of [mode === 'run' ? 'skipped' : 'success', 'failure', 'cancelled', 'missing']) {
        const needs = qualificationNeeds(mode);
        if (state === 'missing') delete needs[job]; else needs[job] = { result: state };
        await refuseQualification(mode, needs, {}, job);
      }
    }
    await refuseQualification(mode, qualificationNeeds(mode), { GITHUB_SHA: 'b'.repeat(40) }, 'differs from candidate');
  }
  await refuseQualification('always', qualificationNeeds('skip'), {}, 'Unknown macOS mode');
  await refuseQualification('skip', { lint: { result: 'success' } }, {}, 'plan');
  await refuseQualification('reuse', qualificationNeeds('reuse'), { CI_MACOS_EVIDENCE: '' }, 'needs CI_MACOS_EVIDENCE');
  await refuseQualification('run', qualificationNeeds('run'), { CI_MACOS_EVIDENCE: JSON.stringify(macosEvidence) }, 'only for macOS mode reuse');
  const qualifiedHuman = await run('gate', ['--qualification'], {
    ...env, ...modeEnv('skip'), CI_NEEDS: JSON.stringify(qualificationNeeds('skip')),
  });
  assert.equal(qualifiedHuman.status, 0); assert.equal(qualifiedHuman.err, '');
  // qualification_stdout_is_json: stdout is the receipt and nothing else.
  assert.equal(qualifiedHuman.out, qualifiedSkip.out);
  assert.equal(qualifiedHuman.out.split('\n').length, 2);
  assert.equal(JSON.stringify(JSON.parse(qualifiedHuman.out)) + '\n', qualifiedHuman.out);
  assert(existsSync(qualificationPath));
  const gateSelfTest = await run('gate', ['--json', '--self-test'], { ...env, ...modeEnv('skip') });
  assert.equal(success(gateSelfTest).passed, true);
  assert(gateSelfTest.err.includes('qualification plan, macOS modes, fixed job lists and v2 receipt pass'));
  assert(gateSelfTest.err.includes('argparse forms and refusals pass'));
  failure(await run('gate', ['--json', '--receipt', scratch], env));

  const verdict = await run('reuse', ['push', '--sha', sha, '--before', 'b'.repeat(40), '--json'], { GITHUB_REPOSITORY: '' });
  assert.deepEqual(json(verdict), { trusted: false, exact: false, reason: 'no repository' });
  console.log(`CI JSON presentation: ${cases} cases, ${names.length} reused ${target} artifacts, ${((performance.now() - started) / 1000).toFixed(2)}s`);
} finally {
  if (receipts) writeFileSync(join(receipts, 'commands.json'), JSON.stringify({ target, moon, moonrun, git, artifacts: artifacts.size, builds, cases: evidence, elapsedMs: performance.now() - started }, null, 2) + '\n');
  rmSync(scratch, { recursive: true, force: true });
}
