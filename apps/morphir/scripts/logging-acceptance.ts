import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {headlessEnvironment} from './headless-environment.ts';

/** Compare actual nonempty CLI Ion output under controlled clocks and IDs.
 * The preload belongs only to this child fixture; production has no test hook. */
export function exerciseTelemetryDiagnosticParity(target: string, binary: string, launcher?: string): void {
  if (target !== 'js') return;
  const root = mkdtempSync(join(tmpdir(), 'morphir-log-parity-'));
  try {
    const env = headlessEnvironment(root);
    mkdirSync(join(root, 'src'));
    writeFileSync(join(root, 'morphir.toml'), "[project]\nname='DiagnosticParity'\nsource_directory='src'\n");
    writeFileSync(join(root, 'src/Main.mbt'), 'pub fn enabled(active : Bool) -> Bool { active }\n');
    const preload = join(root, 'fixed-clocks.mjs');
    writeFileSync(preload, `import crypto from 'node:crypto';import {syncBuiltinESMExports} from 'node:module';
crypto.randomUUID=()=> '00000000-0000-4000-8000-000000000001';
Date.now=()=>1793246400000;process.hrtime.bigint=()=>1000000000n;syncBuiltinESMExports();\n`);
    const args = ['run', '.', '--frontend', 'moonbit', '--backend', 'checkpoint', '--checkpoint-format', 'ion-binary', '--log', '--log-format', 'ion-binary', '--json', '--isolated', '--discovery-boundary', '.'];
    const baseline = join(root, 'baseline.ionb'), diagnostic = join(root, 'diagnostic.ionb');
    const invoke = (file: string, extra: string[]) => {
      const result = spawnSync(process.execPath, ['--import', pathToFileURL(preload).href, launcher ?? binary, ...args, '--log-file', file, ...extra], {cwd: root, env, encoding: 'utf8', timeout: 20000, maxBuffer: 1048576});
      assert.equal(result.status, 0, result.stdout + '\n' + result.stderr);
      return {report: JSON.parse(result.stdout), stderr: result.stderr};
    };
    const plain = invoke(baseline, []), traced = invoke(diagnostic, ['--log-level', 'trace']);
    assert.deepEqual(traced.report, plain.report);
    const bytes = readFileSync(baseline);
    assert.deepEqual([...bytes.subarray(0, 4)], [224, 1, 0, 234]);
    assert.ok(bytes.length > 1024 && bytes.includes('morphir-observation-v1'), 'Need a nonempty observation stream');
    assert.deepEqual(readFileSync(diagnostic), bytes, 'Diagnostic level changed Ion binary telemetry');
    assert.equal(plain.stderr.includes('morphir.cli.run'), false);
    assert.match(traced.stderr, /morphir\.cli\.run/);
    console.log(`CLI diagnostic/telemetry ${target}: ${bytes.length} nonempty Ion bytes unchanged with --log-level trace; JSON and stderr channels passed.`);
  } finally { rmSync(root, {recursive: true, force: true}); }
}

/** The real helper Promise and its foreign callback stay inside the mediator. */
export function exerciseAsyncDiagnosticScope(target: string, binary: string, launcher?: string): void {
  if (target !== 'js') return;
  const root = mkdtempSync(join(tmpdir(), 'morphir-async-diagnostics-'));
  try {
    const env = headlessEnvironment(root);
    writeFileSync(join(root, 'morphir.toml'), '[workspace]\nmembers=[]\n[logging]\nlevel="debug"\n[logging.file]\nenabled=true\nformat="json-lines"\n');
    writeFileSync(join(root, 'input.scm'), '(define answer 42)');
    const helper = join(root, 'delayed-helper.mjs');
    writeFileSync(helper, `export async function connectedCommand(config, core, interrupted){await new Promise(resolve=>setTimeout(resolve,40));return {code:0,report:{profile:'morphir/cli/connected-command',contractVersion:'0.1.0',cancelled:interrupted(),completedAt:Date.now()}};}\n`);
    const args = ['connected', 'connect', join(root, 'input.scm'), '--provider', 'workbench-http', '--connection', 'controlled', '--connected-helper', helper, '--json', '--isolated', '--discovery-boundary', '.'];
    const result = spawnSync(process.execPath, [launcher ?? binary, ...args], {cwd: root, env, encoding: 'utf8', timeout: 10000});
    assert.equal(result.status, 0, result.stdout + '\n' + result.stderr);
    const report = JSON.parse(result.stdout);
    assert.equal(report.cancelled, false, 'Foreign callback must poll without a current coroutine');
    const directory = join(root, '.morphir/logs');
    const records = readdirSync(directory).filter(name => name.startsWith('morphir-diagnostics')).flatMap(name => readFileSync(join(directory, name), 'utf8').trim().split('\n').map(line => JSON.parse(line)));
    const finished = records.find(record => record.category === 'morphir.cli.connected.connect' && record.message.startsWith('Finished'));
    assert.ok(finished, JSON.stringify(records));
    assert.ok(Date.parse(finished.timestamp) >= report.completedAt, 'Log scope ended before the helper Promise');
    assert.ok(finished.properties.ElapsedMilliseconds >= 30, 'Timing excluded the real async operation');
    console.log('CLI async diagnostics js: real Promise awaited inside timing/log scope, foreign callback safe, records drained before exit.');
  } finally { rmSync(root, {recursive: true, force: true}); }
}
