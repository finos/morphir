// An explicit test adapter for the frozen draft.12 execute/JSON-arguments kit.
// Expected observations and case IDs never enter this process.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import { headlessEnvironment } from './headless-environment.ts';

const version = '0.1.0-draft.12';
const limit = 2 * 1024 * 1024;
const cli = process.env.MORPHIR_HEADLESS_CLI;
const framingPath = process.env.MORPHIR_WORKBENCH_MCK_JSON;
const target = process.env.MORPHIR_HEADLESS_TARGET ?? 'js';
if (!cli || !framingPath || !['js', 'native'].includes(target))
  throw new Error('Set explicit MORPHIR_HEADLESS_CLI, MORPHIR_WORKBENCH_MCK_JSON and js/native target');
const executable = resolve(cli);
const cliHash = createHash('sha256').update(readFileSync(executable)).digest('hex');
const framing: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; morphirWorkbenchMckJson?: (source: string) => string } = { TextEncoder, TextDecoder };
runInNewContext(readFileSync(framingPath, 'utf8'), framing);
const core = framing.morphirWorkbenchMckJson;
if (!core) throw new Error('Missing production duplicate-aware MCK framing decoder');

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function closed(value: Record<string, unknown>, names: string[]) {
  if (Object.keys(value).sort().join(',') !== [...names].sort().join(','))
    throw new Error('Invalid closed MCK request');
}
function parse(source: string): Record<string, unknown> {
  const decoded: unknown = JSON.parse(core!(source));
  if (!object(decoded) || decoded.ok !== true || !object(decoded.value))
    throw new Error('Invalid duplicate-aware JSON frame');
  return decoded.value;
}
function canonical(value: unknown): string {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (object(value)) return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  if (typeof value === 'number' && !Number.isSafeInteger(value))
    throw new Error('Unsafe number in declaration evidence');
  const source = JSON.stringify(value);
  if (source === undefined) throw new Error('Missing declaration evidence');
  return source;
}
function evaluate(input: unknown) {
  if (!object(input) || typeof input.model !== 'string' || input.runtime !== 'scheme' ||
      !Array.isArray(input.calls) || input.calls.length === 0 || input.calls.length > 1000 ||
      input.extensions !== null || 'completion' in input ||
      Buffer.byteLength(JSON.stringify(input)) > 1024 * 1024)
    throw new Error('Input is outside the explicitly selected execute/JSON-arguments kit');
  const policy = object(input.admission) ? input.admission.policy : 'strict';
  if (policy !== 'strict' && policy !== 'permissive') throw new Error('Invalid selected policy');
  const calls = input.calls.map(call => {
    if (!object(call) || typeof call.id !== 'string' || typeof call.entry !== 'string' ||
        !object(call.inputs) || call.inputs.format !== 'json' || typeof call.inputs.source !== 'string')
      throw new Error('This explicit kit requires captured JSON argument sources');
    // Preserve opaque original argument tokens. The production CLI decodes them.
    return `{"id":${JSON.stringify(call.id)},"entry":${JSON.stringify(call.entry)},"arguments":${call.inputs.source}}`;
  });
  const root = mkdtempSync(join(tmpdir(), 'morphir-headless-mck-'));
  try {
    const model = join(root, 'model.json'), suite = join(root, 'suite.json');
    writeFileSync(model, input.model);
    writeFileSync(suite, '{"profile":"morphir-invocations-v1","calls":[' + calls.join(',') + ']}');
    const args = ['eval', model, '--model-format', 'json', '--suite', suite, '--checking-policy', policy, '--json'];
    const child = spawnSync(target === 'js' ? process.execPath : executable, target === 'js' ? [executable, ...args] : args, {
      cwd: root, env: headlessEnvironment(root),
      encoding: 'utf8', timeout: 30_000, maxBuffer: limit, windowsHide: true,
    });
    if (child.error || child.signal || ![0, 1, 130].includes(child.status ?? -1))
      throw new Error('Actual CLI process failed or exceeded its bounded execution/output budget');
    const result = parse(child.stdout.trim());
    if (result.operation !== 'evaluate' || result.provider !== 'scheme-portable-v1/shared-sdk/bounded' ||
        result.checkingPolicy !== policy || result.successful !== (child.status === 0) ||
        !('boundary' in result) || !('failure' in result) || !('terminalOutcomes' in result))
      throw new Error('Actual CLI evidence is incomplete or belongs to a different operation/provider');
    if (createHash('sha256').update(readFileSync(executable)).digest('hex') !== cliHash)
      throw new Error('Selected CLI changed during qualification');
    return {
      mode: 'execute', policy: result.checkingPolicy, runtime: 'scheme',
      boundary: typeof result.boundary === 'string' ? canonical(parse(result.boundary)) : result.boundary,
      outcomes: result.terminalOutcomes, failure: result.failure,
    };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
function handle(line: string) {
  const request = parse(line);
  if (request.op === 'exit') {
    closed(request, request.id === undefined ? ['op'] : ['op', 'id']);
    return null;
  }
  if (!Number.isSafeInteger(request.id) || Number(request.id) < 1 ||
      request.suite !== 'workbench' || request.contractVersion !== version)
    throw new Error('Unsupported MCK request identity/profile');
  if (request.op === 'capabilities') {
    closed(request, ['id', 'op', 'suite', 'contractVersion']);
    return { id: request.id, suite: 'workbench', contractVersion: version,
      binding: `morphir-headless-cli-${target}-sha256:${cliHash}`, language: 'moonbit',
      operations: ['run-capability-policy'], formats: ['json'] };
  }
  closed(request, ['id', 'op', 'suite', 'contractVersion', 'format', 'input']);
  if (request.op !== 'run-capability-policy' || request.format !== 'json')
    throw new Error('Unsupported MCK operation');
  return { id: request.id, status: 'ok', value: evaluate(request.input) };
}
async function serve() {
  let pending = Buffer.alloc(0);
  const decoder = new TextDecoder('utf-8', { fatal: true });
  for await (const chunk of process.stdin) {
    pending = Buffer.concat([pending, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)]);
    let end: number;
    while ((end = pending.indexOf(10)) !== -1) {
      if (end > limit) throw new Error('Oversize MCK frame');
      const line = decoder.decode(pending.subarray(0, end));
      pending = pending.subarray(end + 1);
      const reply = handle(line);
      if (reply === null) { process.stdin.destroy(); return; }
      const source = JSON.stringify(reply) + '\n';
      if (Buffer.byteLength(source) > limit) throw new Error('Oversize MCK observation');
      if (!process.stdout.write(source)) await once(process.stdout, 'drain');
    }
    if (pending.length > limit) throw new Error('Oversize MCK frame');
  }
  if (pending.length) throw new Error('Incomplete MCK frame');
}
try { await serve(); }
catch (error) {
  process.stderr.write((error instanceof Error ? error.message : 'MCK adapter infrastructure failure').slice(0, 4096) + '\n');
  process.exitCode = 1;
}
