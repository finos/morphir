import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { headlessEnvironment } from './headless-environment.ts';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const target = process.argv[2] ?? 'js';
assert.ok(['js', 'native', 'wasm-gc', 'wasm'].includes(target));
const build = resolve(repo, process.env.MORPHIR_HEADLESS_BUILD ?? '.dev/build-headless');
const profile = process.env.MORPHIR_HEADLESS_PROFILE ?? 'debug';
const binary = process.env.MORPHIR_HEADLESS_BINARY ?? join(build, target, `${profile}/build/morphir/morphir`, target === 'native' ? 'morphir.exe' : target === 'js' ? 'morphir.js' : 'morphir.wasm');
const launcher = process.env.MORPHIR_HEADLESS_LAUNCHER ?? join(repo, 'apps/morphir/bin/morphir.js');
const runner = process.env.MORPHIR_HEADLESS_WASM_RUNNER ?? join(repo, 'pkgs/morphir-host/runners/wasm.mjs');
const program = target === 'native' ? binary : process.execPath;
const prefix = target === 'native' ? [] : target === 'js' ? [launcher] : [runner, binary];
const root = mkdtempSync(join(tmpdir(), 'morphir-headless-worksheet-'));
const file = join(root, 'source.scm');
const env = headlessEnvironment(root);
const corpus = JSON.parse(readFileSync(join(repo, 'apps/morphir-workbench/fixtures/headless-parity/v1/draft.27/cases.json'), 'utf8'));
function invoke(args: string[], status: number, input?: string | Buffer) {
  const result = spawnSync(program, [...prefix, ...args], { cwd: root, env, encoding: 'utf8', input, timeout: 30000, maxBuffer: 4 * 1024 * 1024 });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, status, `${args.join(' ')}\n${result.stderr}\n${result.stdout}`);
  return result;
}
try {
  if (target === 'wasm') {
    assert.ok(JSON.parse(invoke(['worksheet', '--help', '--json'], 0).stdout).usage.includes('worksheet'));
    writeFileSync(file, '(+ 1 2)');
    assert.equal(JSON.parse(invoke(['worksheet', file, '--json'], 2).stdout).error, 'worksheet.interruption_unavailable');
    console.log('WASI worksheet: portable help and explicit unavailable interruption refusal passed.');
  } else {
    let cases = 0;
    for (const test of corpus.cases) {
      if (test.operation !== 'worksheet-evaluate') continue;
      const request = JSON.parse(test.input.request);
      const expected = test.expected.value;
      const status = expected.completion.status !== 'returned' || expected.observations.some((row: { outcome: { status: string } }) => row.outcome.status !== 'returned') ? 1 : 0;
      writeFileSync(file, request.source.text);
      const options = ['--source-id', request.source.id, '--source-revision', String(request.source.revision)];
      const actual = JSON.parse(invoke(['worksheet', file, ...options, '--json'], status).stdout);
      assert.deepEqual(actual, expected, test.id);
      assert.deepEqual(JSON.parse(invoke(['worksheet', '-', ...options, '--json'], status, request.source.text).stdout), expected, `${test.id} stdin`);
      const lines = invoke(['worksheet', file, ...options, '--json-lines'], status).stdout.trim().split(/\r?\n/).map(line => JSON.parse(line));
      assert.deepEqual(lines.slice(0, -1).map(line => line.data), expected.observations);
      assert.deepEqual(lines.at(-1).data, expected);
      cases++;
    }
    for (const text of ['', '; empty\r\n']) {
      const report = JSON.parse(invoke(['worksheet', '-', '--json'], 0, text).stdout);
      assert.deepEqual(report.observations, []);
      assert.equal(report.completion.status, 'returned');
    }
    const shared = JSON.parse(invoke(['worksheet', '-', '--json'], 0, '(define x 40)\r\n(+ x 2)').stdout);
    assert.deepEqual(shared.observations[1].range, { start: 15, end: 22 });
    assert.deepEqual(shared.observations[1].outcome.value, { type: 'int', value: '42' });
    assert.equal(JSON.parse(invoke(['worksheet', '-', '--json'], 1, '1/3\n42').stdout).observations[0].outcome.failure.code, 'worksheet.value_unsupported');
    for (const input of [Buffer.from([0xff]), Buffer.from([0xf0, 0x9f])]) {
      assert.equal(JSON.parse(invoke(['worksheet', '-', '--json'], 2, input).stdout).error, 'worksheet.invalid_utf8');
    }
    invoke(['worksheet', '-', '--json'], 2, ' '.repeat(1048577));
    invoke(['worksheet', '-', '--json'], 2, '1\n'.repeat(1001));
    const outputLimit = JSON.parse(invoke(['worksheet', '-', '--json'], 1, '1\n(let loop ((n 30) (v #(1))) (if (= n 0) v (loop (- n 1) (vector v v))))').stdout);
    assert.equal(outputLimit.completion.failure.code, 'worksheet.output_limit');
    assert.equal(outputLimit.observations.length, 1);
    const runtime = JSON.parse(invoke(['worksheet', '-', '--json'], 1, '1\n(let loop () (loop))\n2').stdout);
    assert.equal(runtime.completion.failure.code, 'worksheet.runtime_limit');
    assert.equal(runtime.observations.length, 2);
    const timeout = JSON.parse(invoke(['worksheet', '-', '--timeout', '1', '--json'], 1, '(let loop () (loop))').stdout);
    assert.equal(timeout.completion.failure.code, 'worksheet.timeout');
    assert.deepEqual(timeout.observations, []);
    writeFileSync(file, '(let loop () (loop))');
    const cancel = join(root, 'cancel');
    writeFileSync(cancel, 'cancel');
    const cancelled = JSON.parse(invoke(['worksheet', file, '--cancel-file', cancel, '--json'], 130).stdout);
    assert.equal(cancelled.completion.status, 'cancelled');
    assert.deepEqual(cancelled.observations, []);
    assert.deepEqual(cancelled.diagnostic, { stage: 'transport', range: null });
    invoke(['worksheet', '--json'], 2);
    invoke(['worksheet', file, '--source-revision', '-1', '--json'], 2);
    invoke(['worksheet', file, '--timeout', '0', '--json'], 2);
    // Keep stdin open without EOF. Cancellation must stop the owned worker
    // and parent without waiting for another byte from the caller.
    for (const args of process.platform === 'win32' ? [] : [['worksheet', '-', '--json'], ['--json', 'worksheet', '-']]) {
    const child = spawn(program, [...prefix, ...args], { cwd: root, env, stdio: ['pipe', 'pipe', 'pipe'] });
    child.stdin.on('error', error => { if ((error as NodeJS.ErrnoException).code !== 'EPIPE') throw error; });
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', data => { stdout += data; });
    child.stderr.setEncoding('utf8').on('data', data => { stderr += data; });
    const closed = new Promise<{ code: number | null; signal: string | null }>((resolve, reject) => {
      child.once('error', reject);
      child.once('close', (code, signal) => resolve({ code, signal }));
    });
    await new Promise(resolve => setTimeout(resolve, 250));
    child.kill('SIGINT');
    const deadline = setTimeout(() => child.kill('SIGKILL'), 5000);
    const result = await closed;
    clearTimeout(deadline);
    child.stdin.destroy();
    assert.equal(result.signal, null, stderr);
    assert.equal(result.code, 130, stdout + stderr);
    const interrupted = JSON.parse(stdout);
    assert.ok(interrupted.completion?.status === 'cancelled' || interrupted.error === 'Cancelled');
    }
    console.log(`Headless worksheet ${target}: ${cases} frozen cases through file/stdin/JSON-lines, exact ranges, limits, timeout and cancellation passed. SIGINT injection: ${process.platform === 'win32' ? 'not exercised on Windows' : 'passed'}.`);
  }
} finally {
  rmSync(root, { recursive: true, force: true });
}
