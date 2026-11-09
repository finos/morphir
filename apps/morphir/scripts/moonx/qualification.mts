import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir, constants } from 'node:os';
import { basename, isAbsolute, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { createConnection } from 'node:net';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import {start,finish,cleanup,observations,waitObservation,waitControlLine,proveCleanup,recoveryProblems} from './process-fixture.mts';

const options = { json: { type: 'boolean' as const }, help: { type: 'boolean' as const } };
const help = 'Qualify an actual Morphir launcher. --json emits one command-result on stdout; child diagnostics remain on stderr. Supply MORPHIR_MOONX_PROGRAM, PREFIX_JSON, KIND=archive|public, VERSION and COMPILER_HOME; Windows also requires CONTROLLER. Success requires actual product results and separate boundary/lifecycle proofs. No upload or source override is performed.';

function document(state: 'succeeded' | 'failed', exitCode: number, payload: object) {
  return { profile: 'morphir/command-result', contractVersion: '0.1.0', command: 'test.moonx-launcher', state, exitCode, diagnostics: [], ...payload };
}
function required(name: string): string {
  const value = process.env[`MORPHIR_MOONX_${name}`];
  assert.ok(value, `MORPHIR_MOONX_${name} is required`);
  return value;
}

async function qualify() {
  const program = required('PROGRAM'), home = realpathSync(required('COMPILER_HOME'));
  assert.ok(isAbsolute(program));
  assert.ok(['moonrun', 'moonrun.exe', 'moonx', 'moonx.exe'].includes(basename(program)));
  assert.equal(realpathSync(program), realpathSync(join(home, 'bin', basename(program))), 'Program belongs to the selected toolchain');
  const prefix: unknown = JSON.parse(required('PREFIX_JSON'));
  assert.ok(Array.isArray(prefix) && prefix.every(arg => typeof arg === 'string'));
  const registry = basename(program).startsWith('moonx');
  const entry = prefix[0]; assert.ok(typeof entry === 'string');
  assert.equal(prefix.length, registry ? 1 : 2);
  if (!registry) assert.equal(prefix[1], '--');
  const kind = required('KIND'); assert.ok(kind === 'archive' || kind === 'public');
  const version = required('VERSION'); assert.match(version, /^\d+\.\d+\.\d+$/);
  if (kind === 'public') {
    assert.equal(registry, true, 'Public qualification must invoke stock Moonx');
    assert.equal(entry, `finos/morphir/moonx@${version}`, 'Public qualification must use the exact Morphir coordinate and version');
  } else {
    assert.equal(registry, false, 'Archive qualification must invoke stock Moonrun');
    assert.ok(isAbsolute(entry) && entry.endsWith('.wasm') && existsSync(entry));
  }
  assert.equal(process.env.MOONCAKES_TOKEN ?? '', '', 'Test consumers receive no token');
  assert.equal(existsSync(join(home, 'credentials.json')), false);
  for (const variable of ['MOONC_OVERRIDE', 'MOONRUN_OVERRIDE', 'MOON_OVERRIDE', 'MOON_CORE_OVERRIDE']) {
    assert.equal(process.env[variable], undefined, `${variable} must not override the selected stock toolchain`);
  }
  const selectedEnv: NodeJS.ProcessEnv = { ...process.env, MOON_HOME: home, MOON_TOOLCHAIN_ROOT: home, MOON_WORK: 'off', NODE_OPTIONS: '' };
  const compiler = spawnSync(join(home, 'bin', process.platform === 'win32' ? 'moonc.exe' : 'moonc'), ['-v'], { encoding: 'utf8', env: selectedEnv });
  assert.ifError(compiler.error); assert.equal(compiler.status, 0);
  assert.match(compiler.stdout, /^v0\.10\.20\+65efd5b93 /);
  const tools = spawnSync(join(home, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon'), ['version', '--all'], { encoding: 'utf8', env: selectedEnv });
  assert.ifError(tools.error); assert.equal(tools.status, 0);
  const lines = tools.stdout.split('\n');
  const compilers = lines.filter(line => line.startsWith('moonc v'));
  const moons = lines.filter(line => line.startsWith('moon '));
  const runners = lines.filter(line => line.startsWith('moonrun '));
  assert.equal(compilers.length, 1); assert.equal(moons.length, 1); assert.equal(runners.length, 1);
  const versionToken = compiler.stdout.trim().split(' ')[0]; assert.ok(versionToken);
  const compilerVersion = versionToken.slice(1);
  const reportedCompiler = compilers[0], reportedMoon = moons[0], reportedRunner = runners[0];
  assert.ok(reportedCompiler && reportedMoon && reportedRunner);
  assert.ok(reportedCompiler.startsWith(`moonc v${compilerVersion} `));
  const toolCommit = '940aa18';
  assert.ok(reportedMoon.includes(`(${toolCommit} `) && reportedRunner.includes(`(${toolCommit} `), 'Moon and Moonrun belong to the same supported stock release');
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'morphir-moonx-qualification-')));
  const cwd = join(root, 'workspace Ω'); mkdirSync(cwd);
  const applicationHome = join(root, 'home'); mkdirSync(applicationHome);
  const env: NodeJS.ProcessEnv = { ...selectedEnv, USERPROFILE: applicationHome, XDG_CONFIG_HOME: join(applicationHome, 'config') };
  for (const key of Object.keys(env)) if (key.startsWith('MORPHIR_')) delete env[key];
  env.MORPHIR_HOME = applicationHome;
  const proofs: object[] = [];
  const finiteCleanup: object[] = [];
  let sequence = 0;
  const probe = (mode: 'observe' | 'transport' | 'unresponsive') => {
    const stage = join(root, `probe-${++sequence} Ω`), temporary = join(stage, 'payloads');
    mkdirSync(temporary, { recursive: true });
    const events = join(stage, 'events.jsonl'), config = join(stage, 'config.json');
    writeFileSync(config, JSON.stringify({ mode, events }));
    return { events, temporary, env: { ...env, MORPHIR_MOONX_TEST_CONFIG: config,
      NODE_OPTIONS: `--require ${JSON.stringify(fileURLToPath(new URL('./preload.cts', import.meta.url)))}`,
      TMPDIR: temporary, TMP: temporary, TEMP: temporary } };
  };
  const invoke = (args: string[], environment: NodeJS.ProcessEnv = env, events?: string) => start(program, [...prefix, ...args], cwd, environment, events);
  try {
    for (const args of [['--moonx-help', '--json'], ['version', '--json']]) {
      const fixture = probe('observe');
      const run = invoke(args, fixture.env, fixture.events); run.child.stdin.end();
      try {
        assert.deepEqual(await finish(run), { code: 0, signal: null, error: undefined });
        const value = JSON.parse(Buffer.concat(run.stdout).toString());
        assert.equal(value.profile, 'morphir/command-result'); assert.equal(value.state, 'succeeded');
        if (args[0] === 'version') assert.equal(value.result.version, version); else assert.ok(value.result.help);
        if (args[0] === 'version') finiteCleanup.push({ command: 'version', ...proveCleanup(fixture.events, fixture.temporary) });
        else assert.deepEqual(readdirSync(fixture.temporary), [], 'Local launcher help creates no payload');
      } finally { await cleanup(run); }
    }
    const badControls = invoke(['--moonx-json', '--moonx-unknown']); badControls.child.stdin.end();
    try {
      assert.equal((await finish(badControls)).code, 2);
      assert.equal(Buffer.concat(badControls.stdout).length, 0);
      const result = JSON.parse(Buffer.concat(badControls.stderr).toString());
      assert.equal(result.error.code, 'invalid_arguments');
    } finally { await cleanup(badControls); }
    const missing = probe('observe');
    const missingNode = invoke(['--moonx-json', 'version', '--json'], {
      ...missing.env, PATH: join(home, 'bin'),
    }, missing.events);
    missingNode.child.stdin.end();
    try {
      assert.equal((await finish(missingNode)).code, 1);
      assert.equal(Buffer.concat(missingNode.stdout).length, 0);
      const result = JSON.parse(Buffer.concat(missingNode.stderr).toString());
      assert.equal(result.error.code, 'moonx.node_missing');
      assert.deepEqual(readdirSync(missing.temporary), [], 'Failed startup removes its partial payload');
      proofs.push({ kind: 'actual-product-startup-refusal', nodeUnavailable: true, exitCode: 1,
        diagnosticChannel: 'stderr', payloadRemoved: true });
    } finally { await cleanup(missingNode); }
    const invalid = join(cwd, 'invalid.scm'); writeFileSync(invalid, '(');
    const malformed = probe('observe');
    const failure = invoke(['worksheet', invalid, '--isolated', '--discovery-boundary', cwd, '--json'], malformed.env, malformed.events); failure.child.stdin.end();
    try {
      assert.equal((await finish(failure)).code, 1);
      const result = JSON.parse(Buffer.concat(failure.stdout).toString());
      assert.ok(result.completion, `Worksheet failure omitted completion: ${JSON.stringify(result)}; stderr: ${Buffer.concat(failure.stderr).toString()}`);
      assert.equal(result.completion.status, 'failed'); assert.equal(result.completion.failure.code, 'worksheet.read_failed');
      finiteCleanup.push({ command: 'malformed-worksheet', ...proveCleanup(malformed.events, malformed.temporary) });
    } finally { await cleanup(failure); }
    const answer = join(cwd, 'answer.scm'); writeFileSync(answer, '(+ 40 2)');
    const evaluated = probe('observe');
    const success = invoke(['worksheet', answer, '--isolated', '--discovery-boundary', cwd, '--json'], evaluated.env, evaluated.events); success.child.stdin.end();
    try {
      assert.equal((await finish(success)).code, 0);
      const result = JSON.parse(Buffer.concat(success.stdout).toString());
      assert.equal(result.completion?.status, 'returned', JSON.stringify(result));
      assert.equal(result.observations?.[0]?.outcome?.status, 'returned', JSON.stringify(result));
      assert.deepEqual(result.observations[0].outcome.value, { type: 'int', value: '42' });
      finiteCleanup.push({ command: 'worksheet-42', ...proveCleanup(evaluated.events, evaluated.temporary) });
    } finally { await cleanup(success); }
    proofs.push({ kind: 'actual-product', help: true, version, worksheetInteger: '42', malformedWorksheetExit: 1, localRefusalChannel: 'stderr', finiteCleanup });

    for (const [controls, forwarded] of [
      [['--json'], ['--json', 'argv-probe', '', 'Ω🙂', 'a\nb', '--', '--json', '--moonx-help', 'x y']],
      [['--moonx-forward'], ['--moonx-help', '', '--', 'Ω🙂']],
    ] as [string[], string[]][]) {
      const fixture = probe('transport');
      const args = controls[0] === '--json' ? [...controls, ...forwarded.slice(1)] : [...controls, ...forwarded];
      const run = invoke(args, fixture.env, fixture.events);
      const input = Buffer.from(Array.from({ length: 1048576 }, (_, index) => index % 256));
      run.child.stdin.end(input);
      try {
        assert.equal((await finish(run)).code, 23);
        assert.deepEqual(Buffer.concat(run.stdout), input);
        assert.deepEqual(Buffer.concat(run.stderr), Buffer.from(Array.from({ length: 1792 }, (_, index) => 255 - index % 256)));
        const observed = observations(fixture.events).find(row => row.event === 'node-started');
        assert.deepEqual(observed?.arguments, forwarded); assert.equal(observed?.cwd, cwd);
        proofs.push({ kind: 'transport-boundary-fixture', applicationExecuted: false, stdinStdoutBytes: input.length, stderrBytes: 1792,
          childStatus: 23, opaqueArguments: forwarded, ...proveCleanup(fixture.events, fixture.temporary) });
      } finally { await cleanup(run); }
    }
    if (process.platform !== 'win32') {
      for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 143]] as const) {
        const fixture = probe('observe');
        const run = invoke(['worksheet', '-', '--isolated', '--discovery-boundary', cwd, '--json'], fixture.env, fixture.events);
        try {
          const ready = await waitObservation(run, fixture.events, 'stdin-read-starting');
          assert.ok(ready.sigintListeners! > 0 && ready.sigtermListeners! > 0);
          run.child.kill(signal);
          const result = await finish(run);
          assert.ok(result.code === code || result.signal === signal, JSON.stringify(result));
          const output = JSON.parse(Buffer.concat(run.stdout).toString());
          assert.ok(output.completion?.status === 'cancelled' || output.error === 'Cancelled', JSON.stringify(output));
          const childExit = observations(fixture.events).find(row => row.event === 'node-exit');
          assert.equal(childExit?.code, code, 'Observe the real Node exit, not only the expected parent mapping');
          assert.deepEqual(observations(fixture.events).filter(row => row.event === 'node-signal').map(row => row.signal), [signal]);
          proofs.push({ kind: 'actual-product-signal', signal, selectedExitCode: result.code ?? 128 + constants.signals[result.signal!],
            actualChildExitCode: childExit.code, actualParent: result, stdinHeldOpenThroughExit: true,
            applicationResult: output, ...proveCleanup(fixture.events, fixture.temporary) });
        } finally { await cleanup(run); }
      }
    } else {
      const controller = realpathSync(required('CONTROLLER'));
      for (const mode of ['observe', 'unresponsive'] as const) {
        const fixture = probe(mode);
        const run = start(controller, ['--kind', registry ? 'registry' : 'wasm', '--program', program,
          '--entry', entry, '--boundary', cwd, '--json'], cwd, fixture.env, fixture.events);
        let connection: ReturnType<typeof createConnection> | undefined;
        try {
          const address = await waitControlLine(run, 'CONTROL_ADDR=');
          assert.match(address, /^127\.0\.0\.1:\d+$/);
          const ready = await waitObservation(run, fixture.events,
            mode === 'observe' ? 'stdin-read-starting' : 'unresponsive-ready');
          if (mode === 'observe') assert.ok(ready.sigbreakListeners! > 0);
          const node = observations(fixture.events).find(row => row.event === 'node-started');
          assert.ok(node);
          connection = createConnection({ host: '127.0.0.1', port: Number(address.split(':')[1]) });
          const socketErrors: Error[] = []; connection.on('error', error => socketErrors.push(error));
          const lines = createInterface({ input: connection })[Symbol.asyncIterator]();
          await once(connection, 'connect');
          const expectLine = async (expected?: string) => {
            const row = await lines.next(); assert.equal(row.done, false);
            assert.equal(socketErrors.length, 0);
            if (expected !== undefined) assert.equal(row.value, expected);
            return row.value!;
          };
          connection.write(`WATCH_NODE=${node.pid}\n`); await expectLine('CHILD_WATCHED');
          const started = performance.now();
          connection.write('CTRL_C\n'); await expectLine('CTRL_SENT');
          const rawParent = Number(await waitControlLine(run, 'CONSOLE_STATUS='));
          const elapsedMilliseconds = performance.now() - started;
          assert.ok(Number.isInteger(rawParent)); assert.equal(rawParent >>> 0, 0xc000013a);
          connection.write('CHECK_NODE\n'); await expectLine('NODE_RUNNING=0');
          const childRecord = await expectLine(); assert.match(childRecord, /^CHILD_STATUS=-?\d+$/);
          const rawChild = Number(childRecord.slice('CHILD_STATUS='.length));
          await expectLine('DONE');
          assert.equal((await finish(run)).code, 0, Buffer.concat(run.stderr).toString());
          const stdout = Buffer.concat(run.stdout).toString().split('\n').filter(line => line &&
            !['CONTROL_ADDR=', 'CONSOLE_PID=', 'CONSOLE_STATUS='].some(prefix => line.startsWith(prefix)));
          const details = { rawParent, parentStatusBits: rawParent >>> 0, rawChild, childStatusBits: rawChild >>> 0,
            elapsedMilliseconds, consoleDelivery: 'GenerateConsoleCtrlEvent(CTRL_C_EVENT)', stdinHeldOpenThroughExit: true,
            ...proveCleanup(fixture.events, fixture.temporary) };
          assert.ok(elapsedMilliseconds < 12000, 'Default five-second grace remains bounded with scheduler allowance');
          if (mode === 'observe') {
            assert.equal(rawChild >>> 0, 131); assert.equal(stdout.length, 1);
            const productJson = stdout[0]; assert.ok(productJson);
            const output = JSON.parse(productJson);
            assert.ok(output.completion?.status === 'cancelled' || output.error === 'Cancelled', JSON.stringify(output));
            const signals = observations(fixture.events).filter(row => row.event === 'node-signal').map(row => row.signal);
            assert.deepEqual(signals, ['SIGBREAK']);
            proofs.push({ kind: 'actual-product-windows-console', deliveredNodeSignal: 'SIGBREAK',
              applicationResult: output, ...details });
          } else {
            assert.equal(rawChild >>> 0, 1); assert.equal(stdout.length, 0);
            assert.ok(elapsedMilliseconds >= 4000, 'Unresponsive child reaches the actual standard grace boundary');
            proofs.push({ kind: 'unresponsive-child-fault', applicationExecuted: false,
              fault: 'Node event loop withheld after registering signal handlers', ...details });
          }
        } finally { connection?.destroy(); await cleanup(run); }
      }
    }
    assert.deepEqual(recoveryProblems, []);
    return { compilerVersion, toolchainDescription: tools.stdout.trim(), source: kind, program, prefix, node: process.version,
      platform: process.platform, architecture: process.arch, proofs };
  } finally { rmSync(root, { recursive: true, force: true }); }
}

let json = false;
try {
  // Let the same library own presentation even when strict validation fails.
  json = parseArgs({ options, strict: false, allowPositionals: true }).values.json === true;
  const parsed = parseArgs({ options, strict: true, allowPositionals: false });
  json = parsed.values.json ?? false;
  if (parsed.values.help) console.log(json ? JSON.stringify(document('succeeded', 0, { result: { help } })) : help);
  else {
    const result = await qualify();
    console.log(json ? JSON.stringify(document('succeeded', 0, { result })) : JSON.stringify(result, null, 2));
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  const syntax = (error as NodeJS.ErrnoException).code?.startsWith('ERR_PARSE_ARGS_') ?? false;
  const status = syntax ? 2 : 1;
  if (recoveryProblems.length) console.error(JSON.stringify({ recoveryProblems }));
  if (json) console.log(JSON.stringify(document('failed', status, { error: { code: syntax ? 'invalid_arguments' : 'qualification_failed', message } })));
  else console.error(message);
  process.exitCode = status;
}
