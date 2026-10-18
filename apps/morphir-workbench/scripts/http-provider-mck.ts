import { readFileSync } from 'node:fs';
import { once } from 'node:events';
import { runInNewContext } from 'node:vm';
import { pathToFileURL } from 'node:url';
import type { Core } from '../browser/contracts.ts';
import { isRecord } from '../../../types/data.ts';
import { runHttpProviderTrace } from './http-provider-trace.ts';

const hostPath = process.env.MORPHIR_WORKBENCH_PROVIDER_HOST;
const workerPath = process.env.MORPHIR_WORKBENCH_PROVIDER_WORKER;
if (!hostPath || !workerPath) throw new Error('Set the compiled production provider host and worker paths.');
const context: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; console: typeof console;
  morphirWorkbenchExecutionHost?: (source: string) => Core; morphirWorkbenchDecode?: Core } = { TextEncoder, TextDecoder, console };
runInNewContext(readFileSync(hostPath, 'utf8'), context);
const factory = context.morphirWorkbenchExecutionHost, decoder = context.morphirWorkbenchDecode;
if (!factory || !decoder) throw new Error('Missing compiled production provider exports.');
const core = { factory, decoder, workerUrl: pathToFileURL(workerPath) };
const framingPath = process.env.MORPHIR_WORKBENCH_MCK_JSON;
if (!framingPath) throw new Error('Set the compiled MCK framing codec path.');
const framing: { morphirWorkbenchMckJson?: Core; TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder } = { TextEncoder, TextDecoder };
runInNewContext(readFileSync(framingPath, 'utf8'), framing);
if (!framing.morphirWorkbenchMckJson) throw new Error('Missing MCK framing codec export.');
const parseFrame = framing.morphirWorkbenchMckJson;
const version = '0.1.0-draft.25', operation = 'run-http-policy-provider';
function closed(value: Record<string, unknown>, keys: string[]) {
  if (Object.keys(value).sort().join(',') !== [...keys].sort().join(',')) throw new Error('Invalid provider MCK shape');
}
async function handle(line: string) {
  const parsed: unknown = JSON.parse(parseFrame(line));
  if (!isRecord(parsed) || parsed.ok !== true || !isRecord(parsed.value)) throw new Error('Invalid provider MCK JSON');
  const request = parsed.value;
  if (request.op === 'exit') {
    closed(request, request.id === undefined ? ['op'] : ['id', 'op']);
    if (request.id !== undefined && (!Number.isSafeInteger(request.id) || Number(request.id) < 1)) throw new Error('Invalid provider MCK exit id');
    return null;
  }
  if (!Number.isSafeInteger(request.id) || Number(request.id) < 1 || request.suite !== 'workbench'
    || request.contractVersion !== version) throw new Error('Invalid provider MCK negotiation');
  if (request.op === 'capabilities') {
    closed(request, ['id', 'op', 'suite', 'contractVersion']);
    return { id: request.id, suite: 'workbench', contractVersion: version,
      binding: 'morphir-moonbit-http-provider-node', language: 'typescript', operations: [operation], formats: ['json'] };
  }
  closed(request, ['id', 'op', 'suite', 'contractVersion', 'format', 'input']);
  if (request.op !== operation || request.format !== 'json') throw new Error('Unsupported provider MCK operation');
  return { id: request.id, status: 'ok', value: await runHttpProviderTrace(request.input, core) };
}
async function serve() {
  const limit = 2 * 1024 * 1024;
  let pending = Buffer.alloc(0);
  const utf8 = new TextDecoder('utf-8', { fatal: true });
  for await (const chunk of process.stdin) {
    pending = Buffer.concat([pending, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)]);
    let end: number;
    while ((end = pending.indexOf(10)) !== -1) {
      if (end > limit) throw new Error('Oversize provider MCK line');
      const line = utf8.decode(pending.subarray(0, end)); pending = pending.subarray(end + 1);
      const reply = await handle(line);
      if (reply === null) { process.stdin.destroy(); return; }
      if (!process.stdout.write(JSON.stringify(reply) + '\n')) await once(process.stdout, 'drain');
    }
    if (pending.length > limit) throw new Error('Oversize provider MCK line');
  }
  if (pending.length) throw new Error('Incomplete provider MCK line');
}
try { await serve(); }
catch { process.stderr.write('HTTP provider MCK infrastructure failure\n'); process.exitCode = 1; process.stdin.destroy(); }
