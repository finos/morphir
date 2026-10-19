import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Expected values were frozen from the published producer-independent draft12
// before the CLI adapter ran. This suite invokes the actual built CLI, without
// browser bundles, a display or a Workbench server.
const repo = fileURLToPath(new URL('../../../', import.meta.url));
const target = process.argv[2] ?? 'js';
assert.ok(['js', 'native'].includes(target), 'This acceptance exercises desktop host effects');
const build = resolve(repo, process.env.MORPHIR_HEADLESS_BUILD ?? '.dev/build-headless');
const profile = process.env.MORPHIR_HEADLESS_PROFILE ?? 'debug';
const binary = process.env.MORPHIR_HEADLESS_BINARY ?? join(build, target, `${profile}/build/morphir/morphir`, target === 'js' ? 'morphir.js' : 'morphir.exe');
const launcher = process.env.MORPHIR_HEADLESS_LAUNCHER ?? binary;
const root = mkdtempSync(join(tmpdir(), 'morphir-headless-evaluation-'));
const model = join(root, 'model.json');
const suite = join(root, 'calls.json');
const env = { ...process.env, HOME: root, USERPROFILE: root, DISPLAY: '', WAYLAND_DISPLAY: '' };
const corpus = JSON.parse(readFileSync(join(repo, 'apps/morphir-workbench/fixtures/headless-parity/v1/draft.12/cases.json'), 'utf8'));
function invoke(args: string[], status: number, input?: string) {
  const result = spawnSync(target === 'js' ? process.execPath : binary, target === 'js' ? [launcher, ...args] : args, {
    cwd: root, env, encoding: 'utf8', input, timeout: 30_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, status, `${args.join(' ')}\n${result.stderr}\n${result.stdout}`);
  return result;
}
try {
  for (const test of corpus.cases) {
    assert.equal(test.operation, 'run-capability-policy');
    assert.equal(test.format, 'json');
    writeFileSync(model, test.input.model);
    writeFileSync(suite, JSON.stringify({
      profile: 'morphir-invocations-v1',
      calls: test.input.calls.map((call: { id: string; entry: string; inputs: { format: string; source: string } }) => {
        assert.equal(call.inputs.format, 'json');
        return { id: call.id, entry: call.entry, arguments: JSON.parse(call.inputs.source) };
      }),
    }));
    const expected = test.expected.value;
    const failed = expected.failure !== null || expected.outcomes.calls.some((call: { outcome: { status: string } }) => call.outcome.status !== 'returned');
    const args = ['eval', model, '--suite', suite, '--checking-policy', test.input.admission.policy];
    const result = JSON.parse(invoke([...args, '--json'], failed ? 1 : 0).stdout);
    if (expected.failure) {
      assert.equal(result.successful, false);
      assert.ok(result.error.includes(expected.failure.code), `${test.id}: ${result.error}`);
      assert.deepEqual(result.failure, expected.failure);
    } else {
      assert.deepEqual(result.terminalOutcomes, expected.outcomes, test.id);
      assert.equal(result.provider, 'scheme-portable-v1/shared-sdk/bounded');
      const records = invoke([...args, '--json-lines'], failed ? 1 : 0).stdout.trim().split(/\r?\n/).map(line => JSON.parse(line));
      assert.deepEqual(records.filter(record => record.type === 'call').map(record => record.data), expected.outcomes.calls);
      assert.deepEqual(records.at(-1).data, result);
    }
  }
  // Explicit stdin retains the same model codec and outcome. Both stdin inputs
  // are refused before consuming either stream.
  const first = corpus.cases[0];
  writeFileSync(suite, JSON.stringify({ profile: 'morphir-invocations-v1', calls: [{ id: 'first', entry: 'selected:main#answer', arguments: [] }] }));
  const stdin = JSON.parse(invoke(['eval', '-', '--model-format', 'json', '--suite', suite, '--checking-policy', 'permissive', '--json'], 0, first.input.model).stdout);
  assert.deepEqual(stdin.terminalOutcomes, first.expected.value.outcomes);
  // A native YAML representation, authored from the fixed literal-42 IR
  // contract, exercises indentation and scalar resolution rather than only
  // JSON's YAML-compatible syntax. Presentation bytes include BOM and CRLF.
  const yaml = '\ufeff# Fixed literal-42 model\r\nformatVersion: 4\r\ndistribution:\r\n  Library:\r\n    packageName: selected\r\n    dependencies: {}\r\n    def:\r\n      modules:\r\n        main:\r\n          Public:\r\n            types: {}\r\n            values:\r\n              answer:\r\n                Public:\r\n                  ExpressionBody:\r\n                    inputTypes: {}\r\n                    outputType: "morphir/SDK:basics#int"\r\n                    body: {Literal: {IntegerLiteral: 42}}\r\n';
  for (const suffix of ['yaml', 'yml']) {
    const path = join(root, `model.${suffix}`);
    writeFileSync(path, yaml);
    const actual = JSON.parse(invoke(['eval', path, '--suite', suite, '--json'], 0).stdout);
    assert.deepEqual(actual.terminalOutcomes, first.expected.value.outcomes);
  }
  assert.deepEqual(JSON.parse(invoke(['eval', '-', '--model-format', 'yaml', '--suite', suite, '--json'], 0, yaml).stdout).terminalOutcomes, first.expected.value.outcomes);
  for (const args of [
    ['eval', '-', '--suite', '-'],
    ['eval', model, '--suite', suite, '--provider', 'unselected-provider'],
    ['eval', model, '--suite', suite, '--checking-policy', 'unchecked'],
  ]) assert.equal(JSON.parse(invoke([...args, '--json'], 2).stdout).successful, false);
  writeFileSync(model, ' '.repeat(4194305));
  assert.equal(JSON.parse(invoke(['eval', model, '--suite', suite, '--checking-policy', 'permissive', '--json'], 2).stdout).successful, false);
  writeFileSync(join(root, 'cancel'), 'cancel');
  writeFileSync(model, first.input.model);
  const cancelled = JSON.parse(invoke(['eval', model, '--suite', suite, '--checking-policy', 'permissive', '--cancel-file', join(root, 'cancel'), '--json'], 130).stdout);
  assert.equal(cancelled.terminalOutcomes.calls[0].outcome.status, 'cancelled');
  // Hand-authored domain-error control. The established SDK contract assigns
  // integer division by zero sdk.division_by_zero, independently of CLI output.
  const domainError = JSON.parse(first.input.model);
  domainError.distribution.Library.def.modules.main.Public.values.answer.Public.ExpressionBody.body = {
    Apply: {
      function: { Apply: { function: { Reference: 'morphir/SDK:basics#integer-divide' }, argument: { Literal: { IntegerLiteral: 1 } } } },
      argument: { Literal: { IntegerLiteral: 0 } },
    },
  };
  writeFileSync(model, JSON.stringify(domainError));
  const error = JSON.parse(invoke(['eval', model, '--suite', suite, '--checking-policy', 'permissive', '--json'], 1).stdout);
  assert.deepEqual(error.terminalOutcomes.calls[0].outcome, { status: 'model-error', code: 'sdk.division_by_zero' });
  console.log(`Headless ${target}: nine frozen policy/value cases, domain error, JSON-lines, bounded stdin, invalid selection and cancellation passed.`);
} finally {
  rmSync(root, { recursive: true, force: true });
}
