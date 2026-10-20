import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { headlessEnvironment } from './headless-environment.ts';

// Expected values were frozen from the published producer-independent draft12
// before the CLI adapter ran. This suite invokes the actual built CLI, without
// browser bundles, a display or a Workbench server.
const repo = fileURLToPath(new URL('../../../', import.meta.url));
const target = process.argv[2] ?? 'js';
assert.ok(['js', 'native', 'wasm', 'wasm-gc'].includes(target));
const build = resolve(repo, process.env.MORPHIR_HEADLESS_BUILD ?? '.dev/build-headless');
const profile = process.env.MORPHIR_HEADLESS_PROFILE ?? 'debug';
const binary = process.env.MORPHIR_HEADLESS_BINARY ?? join(build, target, `${profile}/build/morphir/morphir`, target === 'native' ? 'morphir.exe' : target === 'js' ? 'morphir.js' : 'morphir.wasm');
const launcher = process.env.MORPHIR_HEADLESS_LAUNCHER ?? binary;
const runner = process.env.MORPHIR_HEADLESS_WASM_RUNNER ?? join(repo, 'pkgs/morphir-host/runners/wasm.mjs');
const program = target === 'native' ? binary : process.execPath;
const prefix = target === 'native' ? [] : target === 'js' ? [launcher] : [runner, binary];
const root = mkdtempSync(join(tmpdir(), 'morphir-headless-evaluation-'));
const model = join(root, 'model.json');
const suite = join(root, 'calls.json');
const env = headlessEnvironment(join(root, 'cli-environment'));
const corpus = JSON.parse(readFileSync(join(repo, 'apps/morphir-workbench/fixtures/headless-parity/v1/draft.12/cases.json'), 'utf8'));
function invoke(args: string[], status: number, input?: string | Uint8Array) {
  const result = spawnSync(program, [...prefix, ...args], {
    cwd: root, env, encoding: 'utf8', input, timeout: 30_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, status, `${args.join(' ')}\n${result.stderr}\n${result.stdout}`);
  return result;
}
function evaluateCodecs() {
  const codecProject = join(root, 'codecs');
  mkdirSync(join(codecProject, 'src'), { recursive: true });
  writeFileSync(join(codecProject, 'morphir.toml'), '[project]\nname="FixedPolicies"\n[frontend]\nlanguage="ir-json"\n[pipeline]\nbackend="checkpoint"\n');
  let codecCases = 0;
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
    const document = JSON.parse(test.input.model);
    const yamlPath = join(root, 'policy.yaml');
    // Fixed model JSON uses only small integer literals. Typed invocation
    // numbers stay tagged strings, including 2^53+1, -0 bits and decimal scale.
    writeFileSync(yamlPath, `\ufeff# Fixed draft12 policy model\r\nformatVersion: ${document.formatVersion}\r\ndistribution: ${JSON.stringify(document.distribution)}\r\n`);
    writeFileSync(join(codecProject, 'src/Model.json'), test.input.model);
    const sources: [string, string][] = [['json', model], ['yaml', yamlPath]];
    // Use the maintained registered checkpoint encoders. They prepare physical
    // Ion inputs only; expected values/failures remain the independent draft12
    // records and are never derived from either converted model or CLI output.
    for (const [format, suffix] of [['ion-text', 'ion'], ['ion-binary', 'ionb']] as const) {
      invoke(['run', 'codecs', '--checkpoint-format', format, '--json'], 0);
      const source = join(root, `policy.${suffix}`);
      const bytes = readFileSync(join(codecProject, '.morphir/out/compile.dest', `Model.${suffix}`));
      if (format === 'ion-binary') assert.deepEqual([...bytes.subarray(0, 4)], [0xe0, 0x01, 0x00, 0xea]);
      writeFileSync(source, bytes);
      sources.push([format, source]);
    }
    for (const [format, source] of sources) {
      const args = ['eval', source, '--model-format', format, '--suite', suite, '--checking-policy', test.input.admission.policy];
      const result = JSON.parse(invoke([...args, '--json'], failed ? 1 : 0).stdout);
      const records = invoke([...args, '--json-lines'], failed ? 1 : 0).stdout.trim().split(/\r?\n/).map(line => JSON.parse(line));
      assert.deepEqual(records.at(-1).data, result);
      if (expected.failure) {
        assert.equal(result.successful, false);
        assert.ok(result.error.includes(expected.failure.code), `${test.id}/${format}: ${result.error}`);
        assert.deepEqual(result.failure, expected.failure);
        assert.equal(result.terminalOutcomes, null);
        assert.deepEqual(records.filter(record => record.type === 'call'), []);
      } else {
        assert.deepEqual(result.terminalOutcomes, expected.outcomes, `${test.id}/${format}`);
        assert.equal(result.provider, 'scheme-portable-v1/shared-sdk/bounded');
        assert.deepEqual(records.filter(record => record.type === 'call').map(record => record.data), expected.outcomes.calls);
      }
      codecCases++;
    }
  }
  assert.equal(codecCases, 36);
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
  console.log(`Headless ${target}: ${codecCases} frozen policy/value cases across JSON, YAML, Ion text and Ion binary, domain error, JSON-lines, bounded stdin, invalid selection and cancellation passed.`);
}
try {
  assert.match(JSON.parse(invoke(['eval', '--help', '--json'], 0).stdout).usage, /eval/);
  if (target === 'wasm') {
    // WASI Preview 1 has no interrupt handler. Refuse before opening even a
    // missing input; codec support does not grant this unavailable host effect.
    assert.equal(JSON.parse(invoke(['eval', 'missing.json', '--suite', 'missing-calls.json', '--json'], 2).stdout).error, 'eval.interruption_unavailable');
    console.log('WASI evaluation: portable help and explicit unavailable interruption refusal passed.');
  } else evaluateCodecs();
} finally {
  rmSync(root, { recursive: true, force: true });
}
