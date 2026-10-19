import { readFileSync } from 'node:fs';
import { once } from 'node:events';
import { runInNewContext } from 'node:vm';
import type { Core } from '../browser/contracts.ts';
import type { ClientScenario } from '../browser/artifact-client-trace-contract.ts';
import { runArtifactClientScenario } from '../browser/artifact-client-trace.ts';
import { isRecord } from '../../../types/data.ts';
import { artifactClientBrowser } from './artifact-client-browser.ts';

// The shared runner owns closed scenario validation and pre-expansion budgets.
// Reuse the production duplicate-aware MCK envelope codec; artifact replies
// still go raw to their actual profile decoder inside the production attempt.
const framePath = process.env.MORPHIR_WORKBENCH_MCK_JSON;
if (!framePath) throw new Error('Set MORPHIR_WORKBENCH_MCK_JSON to the compiled MCK framing codec.');
const environment: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; console: typeof console; morphirWorkbenchMckJson?: Core } =
  { TextEncoder, TextDecoder, console };
runInNewContext(readFileSync(framePath, 'utf8'), environment);
const parseFrame = environment.morphirWorkbenchMckJson;
if (!parseFrame) throw new Error('The compiled MCK framing codec is missing.');
const version = '0.1.0-draft.28';
const operation = 'artifact-client';
const frameLimit = 1048576 + 1024;
const browserMode = process.env.MORPHIR_WORKBENCH_ARTIFACT_CLIENT_BROWSER === '1';
const driverPath = process.env.MORPHIR_WORKBENCH_ARTIFACT_CLIENT_DRIVER;
if (browserMode && !driverPath) throw new Error('Set MORPHIR_WORKBENCH_ARTIFACT_CLIENT_DRIVER to the checked browser trace bundle.');
const browser = browserMode ? await artifactClientBrowser(driverPath!) : null;
function closed(record: Record<string, unknown>, keys: readonly string[]) {
  if (Object.keys(record).length !== keys.length || !keys.every(key => Object.hasOwn(record, key))) throw new Error('Invalid MCK envelope shape.');
}
async function handle(source: string) {
  const decoded: unknown = JSON.parse(parseFrame!(source));
  if (!isRecord(decoded) || decoded.ok !== true || !isRecord(decoded.value)) throw new Error('Invalid MCK JSON envelope.');
  const request = decoded.value;
  if (request.op === 'exit') {
    closed(request, request.id === undefined ? ['op'] : ['id', 'op']);
    if (request.id !== undefined && (!Number.isSafeInteger(request.id) || Number(request.id) < 1)) throw new Error('Invalid MCK exit ID.');
    return null;
  }
  if (!Number.isSafeInteger(request.id) || Number(request.id) < 1 || request.suite !== 'workbench' || request.contractVersion !== version) throw new Error('Invalid MCK negotiation.');
  if (request.op === 'capabilities') {
    closed(request, ['id', 'op', 'suite', 'contractVersion']);
    return { id: request.id, suite: 'workbench', contractVersion: version,
      binding: 'morphir-moonbit-artifact-client-' + (browser ? 'chromium' : process.versions.bun ? 'bun' : 'node'),
      language: 'typescript', operations: [operation], formats: ['json'] };
  }
  closed(request, ['id', 'op', 'suite', 'contractVersion', 'format', 'input']);
  if (request.op !== operation || request.format !== 'json') throw new Error('Unsupported artifact client operation.');
  if (!isRecord(request.input) || !Array.isArray(request.input.attempts) || !Array.isArray(request.input.actions)) throw new Error('Missing validated client scenario.');
  // The existing Rust runner checks every nested scenario member and budget
  // before invoking this adapter. The trace additionally checks allocation,
  // effect references and terminal resource invariants against actual calls.
  const input = request.input as unknown as ClientScenario;
  return { id: request.id, status: 'ok', value: await (browser ? browser.run(input) : runArtifactClientScenario(input)) };
}
async function serve() {
  let pending = Buffer.alloc(0);
  const decoder = new TextDecoder('utf-8', { fatal: true });
  for await (const incoming of process.stdin) {
    const chunk = Buffer.isBuffer(incoming) ? incoming : Buffer.from(incoming);
    let start = 0; let end: number;
    while ((end = chunk.indexOf(10, start)) !== -1) {
      const part = chunk.subarray(start, end);
      if (pending.byteLength + part.byteLength > frameLimit) throw new Error('MCK frame limit exceeded.');
      const line = decoder.decode(Buffer.concat([pending, part])); pending = Buffer.alloc(0); start = end + 1;
      const response = await handle(line);
      if (response === null) { process.stdin.destroy(); return; }
      const encoded = JSON.stringify(response) + '\n';
      if (Buffer.byteLength(encoded) > frameLimit) throw new Error('MCK response limit exceeded.');
      if (!process.stdout.write(encoded)) await once(process.stdout, 'drain');
    }
    const tail = chunk.subarray(start);
    if (pending.byteLength + tail.byteLength > frameLimit) throw new Error('MCK frame limit exceeded.');
    pending = Buffer.concat([pending, tail]);
  }
  if (pending.byteLength) throw new Error('Incomplete MCK frame.');
}
try { await serve(); }
catch { process.stderr.write('Artifact client MCK infrastructure failure.\n'); process.exitCode = 1; process.stdin.destroy(); }
finally { await browser?.close(); }
