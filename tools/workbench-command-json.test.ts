import assert from 'node:assert/strict';
import { chmodSync, copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// These are current-artifact wrapper contract tests. The compiled MoonBit child
// fixtures exercise orchestration, not the runtimes or the independent Rust MCK.
const root = fileURLToPath(new URL('../', import.meta.url));
const names = ['headless-parity-controls', 'workbench-artifact-client-mck',
  'workbench-capability-execution-mck', 'workbench-capability-policy-mck',
  'workbench-http-policy-client-mck', 'workbench-http-policy-mck',
  'workbench-http-policy-provider-mck', 'workbench-live-host', 'workbench-mck',
  'workbench-native-client-mck', 'workbench-native-owner-mck',
  'workbench-native-policy-client-mck', 'workbench-native-policy-mck',
  'workbench-native-session', 'workbench-native-workers', 'workbench-native-workspaces',
  'workbench-selected-scheme-mck'] as const;
const mappings: Record<string, [string, string]> = {
  'workbench-artifact-client-mck': ['0.1.0-draft.28', 'artifact-client'],
  'workbench-capability-execution-mck': ['0.1.0-draft.19', 'run-capability-executions'],
  'workbench-capability-policy-mck': ['0.1.0-draft.12', 'run-capability-policy'],
  'workbench-http-policy-client-mck': ['0.1.0-draft.24', 'client'],
  'workbench-http-policy-mck': ['0.1.0-draft.23', 'validate-http-policy-boundary'],
  'workbench-http-policy-provider-mck': ['0.1.0-draft.25', 'run-http-policy-provider'],
  'workbench-native-client-mck': ['0.1.0-draft.17', 'client'],
  'workbench-native-owner-mck': ['0.1.0-draft.18', 'owner'],
  'workbench-native-policy-client-mck': ['0.1.0-draft.21', 'client'],
  'workbench-native-policy-mck': ['0.1.0-draft.20', 'validate-native-policy-boundary'],
  'workbench-selected-scheme-mck': ['0.1.0-draft.11', 'run-selected-scheme'],
};
const scratch = realpathSync(mkdtempSync(join(tmpdir(), 'workbench-command-json-')));
const fixtureSource = join(scratch, 'child.mbtx');
const fixtureBuild = join(scratch, 'child-build');
const executable = (build: string) => join(build, 'native/debug/build/single/single.exe');
const run = (argv: string[], cwd = root, extra: Record<string, string | undefined> = {}, stdin?: string) => {
  const child = Bun.spawnSync(argv, { cwd, env: { ...process.env, ...extra },
    ...(stdin === undefined ? {} : { stdin: Buffer.from(stdin) }), timeout: 120_000 });
  return { status: child.exitCode, stdout: child.stdout.toString(), stderr: child.stderr.toString() };
};
function build(source: string, output: string) {
  const result = run(['moon', 'build', source, '--target', 'native', '--target-dir', output]);
  assert.equal(result.status, 0, `${source}: ${result.stdout}${result.stderr}`);
  return executable(join(output, basename(source)));
}
type Check = { program?: string; args?: string[]; exitCode?: number; expectedAccepted?: boolean; checkerExitCode?: number };
type Receipt = { path: string; qualified?: boolean; recordCount?: number; independentlyChecked?: boolean };
type Completion = { profile: string; contractVersion: string; command: string; state: string; exitCode: number;
  result?: { checks?: Check[]; reports?: Receipt[]; help?: string; caseCount?: number; kitCount?: number; [key: string]: unknown };
  error?: { code: string; message: string }; diagnostics: unknown[] };
function completion(value: ReturnType<typeof run>, name: string, status = 0): Completion {
  assert.equal(value.status, status, `${name}: ${value.stderr}\n${value.stdout}`);
  assert.ok(value.stdout.endsWith('\n'));
  assert.equal(value.stdout.trim().split('\n').length, 1, `${name} stdout framing`);
  const parsed = JSON.parse(value.stdout) as Completion;
  assert.equal(parsed.profile, 'morphir/command-result');
  assert.equal(parsed.contractVersion, '0.1.0');
  assert.equal(parsed.command, name.replaceAll('-', '.'));
  assert.equal(parsed.exitCode, status);
  assert.deepEqual(parsed.diagnostics, []);
  assert.equal(parsed.state, status === 0 ? 'succeeded' : 'failed');
  if (status === 0) { assert.ok(parsed.result); assert.equal(parsed.error, undefined); }
  else { assert.equal(parsed.result, undefined); assert.ok(parsed.error?.code); assert.ok(parsed.error?.message); }
  return parsed;
}
const fixture = `import {
  "moonbitlang/async@0.22.4", "moonbitlang/async@0.22.4/fs",
  "moonbitlang/async@0.22.4/stdio", "moonbitlang/core/env", "moonbitlang/core/json",
  "moonbitlang/x@0.5.5/sys",
}
async fn main {
  let argv = @env.args()
  let args = argv[1:].to_owned()
  let log = @env.get_env_var("STUB_LOG").unwrap()
  let prior = if @fs.exists(log) { @fs.read_file(log).text() } else { "" }
  let invocation = prior.split("\\n").to_array().length()
  let environment : Map[String, String] = Map([])
  for key, value in @env.get_env_vars() {
    if key.has_prefix("MORPHIR_") || key == "WRAPPER_MARKER" { environment[key] = value }
  }
  let cwd = @fs.realpath(".")
  let input = if @env.get_env_var("STUB_READ_STDIN") == Some("1") { @stdio.stdin.read_all().text() } else { "" }
  let entry : Json = { "argv": Json(args), "program": argv[0], "cwd": cwd,
    "environment": Json(environment), "stdin": input, "hadDev": @fs.exists(".dev") }
  @fs.write_file(log, entry.stringify() + "\\n", append=true, create_mode=OpenOrCreate)
  @stdio.stdout.write("child.stdout\\n")
  @stdio.stderr.write("child.stderr\\n")
  if @env.get_env_var("STUB_FAIL_AT") == Some(invocation.to_string()) {
    @sys.exit(if @env.get_env_var("STUB_EXIT") == Some("130") { 130 } else { 23 })
  }
  if args.contains("--report") {
    let index = args.search_by(x => x == "--report").unwrap()
    let report = args[index + 1]
    if @env.get_env_var("STUB_CONTROLS") == Some("1") {
      @sys.exit(if report.has_suffix("-positive.json") { 0 } else { 23 })
    }
    if args.contains("run") {
      let kit = args[args.search_by(x => x == "--kit").unwrap() + 1]
      let corpus = @fs.read_file(kit + "/cases.json").json()
      let rows = match corpus { Object(fields) => fields.get("cases").unwrap(); _ => Json::null() }
      let value : Json = { "qualified": @env.get_env_var("STUB_BAD_REPORT") != Some("1"), "records": rows }
      @fs.write_file(report, value.stringify())
    }
  }
}
`;
interface ChildLog { argv: string[]; program: string; cwd: string; environment: Record<string, string>; stdin: string; hadDev: boolean }
function logs(path: string): ChildLog[] {
  return existsSync(path) ? readFileSync(path, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line) as ChildLog) : [];
}
try {
  writeFileSync(fixtureSource, fixture);
  const childBinary = build(fixtureSource, fixtureBuild);
  const bin = join(scratch, 'bin'); mkdirSync(bin);
  for (const name of ['moon', 'moonx', 'bun', 'node', 'mck']) {
    const path = join(bin, name + (process.platform === 'win32' ? '.exe' : ''));
    copyFileSync(childBinary, path); chmodSync(path, 0o755);
  }
  for (const name of names) {
    const binary = build(join(root, 'scripts', `${name}.mbtx`), join(scratch, `build-${name}`));
    const cwd = join(scratch, name); mkdirSync(cwd);
    mkdirSync(join(cwd, 'apps/morphir-workbench'), { recursive: true });
    for (const leaf of ['acceptance', 'fixture', 'bridge-acceptance', 'workspace-acceptance']) {
      const path = join(cwd, `_build/native/release/build/finos/morphir-workbench-native/${leaf}/${leaf}.exe`);
      mkdirSync(dirname(path), { recursive: true }); copyFileSync(childBinary, path); chmodSync(path, 0o755);
    }
    if (name === 'headless-parity-controls') {
      cpSync(join(root, 'apps/morphir-workbench/fixtures/headless-parity/v1'),
        join(cwd, 'apps/morphir-workbench/fixtures/headless-parity/v1'), { recursive: true });
    }
    const kit = join(cwd, 'kit space λ'); mkdirSync(kit);
    const mapping = mappings[name] ?? ['0.1.0', 'value'];
    const corpus = { formatVersion: mapping[0], cases: [{ id: 'a', operation: mapping[1], format: 'json' }, { id: 'b', operation: mapping[1], format: 'json' }] };
    writeFileSync(join(kit, 'cases.json'), JSON.stringify(corpus));
    const log = join(cwd, 'children.jsonl');
    const evidence = join(cwd, 'evidence');
    const env: Record<string, string | undefined> = { PATH: bin + (process.platform === 'win32' ? ';' : ':') + process.env.PATH,
      MORPHIR_MCK_BIN: join(bin, process.platform === 'win32' ? 'mck.exe' : 'mck'), MORPHIR_WORKBENCH_KIT: kit,
      MORPHIR_WORKBENCH_EVIDENCE: evidence, WRAPPER_MARKER: 'inherited λ', STUB_LOG: log,
      STUB_CONTROLS: name === 'headless-parity-controls' ? '1' : '0', STUB_FAIL_AT: undefined, STUB_READ_STDIN: undefined, STUB_BAD_REPORT: undefined, STUB_EXIT: undefined };
    const invoke = (args: string[], extra: Record<string, string | undefined> = {}, stdin?: string) => run([binary, ...args], cwd, { ...env, ...extra }, stdin);
    const before = readFileSync(join(kit, 'cases.json'));
    const help = completion(invoke(['--json', '--help'], { MORPHIR_MCK_BIN: undefined }), name);
    assert.match(help.result?.help ?? '', /stdout.*stderr/);
    assert.deepEqual(completion(invoke(['--json', '-h']), name), help);
    assert.ok(!existsSync(log) && !existsSync(evidence), `${name} help effects`);
    completion(invoke(['--json', '--unknown']), name, 1);
    completion(invoke(['--json', '--self-test']), name, 1); // No legacy self-test exists in this slice.
    assert.ok(!existsSync(log) && !existsSync(evidence), `${name} syntax effects`);
    if (!['workbench-live-host', 'workbench-native-session', 'workbench-native-workers', 'workbench-native-workspaces'].includes(name)) {
      completion(invoke(['--json'], { MORPHIR_MCK_BIN: undefined, MORPHIR_WORKBENCH_KIT: undefined }), name, 1);
      assert.ok(!existsSync(log) && !existsSync(evidence));
    }
    const operands = name === 'workbench-live-host' ? ['--host-bin=--json', '--desktop-bin=--', '--executions'] : [];
    const json = completion(invoke(['--json', ...operands]), name);
    const checked = json.result?.checks;
    assert.ok(checked && checked.length > 0, `${name} actual completed checks`);
    const observed = logs(log); assert.equal(observed.length, checked.length);
    assert.ok(observed.every(entry => entry.environment['WRAPPER_MARKER'] === 'inherited λ'));
    assert.ok(observed.every(entry => entry.cwd === cwd || name === 'workbench-native-workspaces'));
    if (name === 'headless-parity-controls') {
      assert.ok(checked.some(check => check.expectedAccepted === false && check.checkerExitCode === 23));
      assert.ok((json.result?.kitCount ?? 0) > 0);
    } else {
      assert.ok(checked.every(check => check.exitCode === 0));
      assert.match(invoke(['--json', ...operands]).stderr, /child.stdout\nchild.stderr/);
    }
    for (const report of json.result?.reports ?? []) {
      assert.ok(existsSync(report.path));
      if (report.recordCount !== undefined) { assert.equal(report.qualified, true); assert.equal(report.recordCount, 2); }
    }
    if (name === 'workbench-live-host') {
      assert.equal(observed[0]?.environment['MORPHIR_WORKBENCH_LIVE_HOST_BIN'], '--json');
      assert.equal(observed[0]?.environment['MORPHIR_WORKBENCH_DESKTOP_BIN'], '--');
      assert.equal(observed[0]?.environment['MORPHIR_WORKBENCH_LIVE_EXECUTIONS'], '1');
      for (const literal of ['', 'λ 世界', '--', '--json', '--help', '-host']) {
        rmSync(log, { force: true });
        completion(invoke(['--json', `--host-bin=${literal}`]), name);
        assert.equal(logs(log)[0]?.environment['MORPHIR_WORKBENCH_LIVE_HOST_BIN'], literal);
      }
      rmSync(log, { force: true });
      completion(invoke(['--json', '--host-bin=x'], { STUB_READ_STDIN: '1' }, 'stdin λ\n'), name);
      assert.equal(logs(log)[0]?.stdin, 'stdin λ\n');
    } else {
      rmSync(log, { force: true });
      completion(invoke(['--json', '--', '--json', '', 'λ', '--', '--forward-argv', '--', '--help']), name);
      assert.deepEqual(logs(log).map(x => x.argv), observed.map(x => x.argv), `${name} ignored exact legacy tail`);
      rmSync(log, { force: true });
      const legacy = invoke(['--forward-argv', '--', '--json', '--', '--json']);
      assert.equal(legacy.status, 0); assert.ok(!legacy.stdout.includes('morphir/command-result'));
      assert.deepEqual(logs(log).map(x => x.argv), observed.map(x => x.argv));
      rmSync(log, { force: true });
      const foreign = invoke(['ignored', '--json', '--', '', 'λ']);
      assert.equal(foreign.status, 0); assert.ok(!foreign.stdout.includes('morphir/command-result'));
      assert.deepEqual(logs(log).map(x => x.argv), observed.map(x => x.argv));
    }
    rmSync(log, { force: true });
    const propagated = ['workbench-live-host', 'workbench-native-session', 'workbench-native-workspaces'].includes(name);
    completion(invoke(['--json', ...operands], { STUB_FAIL_AT: '1' }), name, propagated ? 23 : 1);
    assert.equal(logs(log).length, 1, `${name} failure stops later effects`);
    if (name === 'workbench-native-workers') {
      for (const index of ['2', '3']) {
        rmSync(log, { force: true }); completion(invoke(['--json'], { STUB_FAIL_AT: index }), name, 23);
        assert.equal(logs(log).length, Number(index));
      }
    }
    rmSync(log, { force: true });
    completion(invoke(['--json', ...operands], { STUB_FAIL_AT: '1', STUB_EXIT: '130' }), name, propagated ? 130 : 1);
    assert.deepEqual(readFileSync(join(kit, 'cases.json')), before, `${name} corpus untouched`);
    if (json.result?.reports?.some(report => report.recordCount !== undefined)) {
      rmSync(log, { force: true });
      completion(invoke(['--json', ...operands], { STUB_BAD_REPORT: '1' }), name, 1);
      assert.ok(logs(log).length > 0, `${name} invalid report was produced before rejection`);
    }
    if (name in mappings || name === 'workbench-mck') {
      rmSync(log, { force: true });
      writeFileSync(join(kit, 'cases.json'), '{');
      completion(invoke(['--json']), name, 1);
      assert.equal(logs(log).length, 0, `${name} malformed corpus has no child effects`);
      writeFileSync(join(kit, 'cases.json'), before);
    }

    if (name === 'workbench-native-workspaces') {
      const accepted = observed.at(-1); assert.ok(accepted); assert.equal(accepted.hadDev, false);
      assert.notEqual(accepted.cwd, cwd); assert.equal(existsSync(accepted.cwd), false, 'acceptance temporary cwd cleaned');
    }
    if (name === 'workbench-native-policy-mck') {
      corpus.formatVersion = '0.1.0-draft.22';
      for (const row of corpus.cases) row.operation = 'run-native-policy-owner';
      writeFileSync(join(kit, 'cases.json'), JSON.stringify(corpus));
      rmSync(log, { force: true }); const owner = completion(invoke(['--json']), name);
      assert.equal(owner.result?.reports?.length, 2);
    }
    console.log(`${name}: current native wrapper operations, JSON framing/help/errors, child argv/env/cwd/status and legacy controls passed`);
  }
} finally { rmSync(scratch, { recursive: true, force: true }); }
