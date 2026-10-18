import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { chromium } from 'playwright';
import type { Core } from '../browser/contracts.ts';
import { runHttpPolicyClientTrace } from '../browser/http-client-trace.ts';
import { isRecord } from '../../../types/data.ts';

const corePath = process.env.MORPHIR_WORKBENCH_HTTP_CLIENT_CORE;
if (!corePath) throw new Error('Set MORPHIR_WORKBENCH_HTTP_CLIENT_CORE to the compiled production core');
const compiled = readFileSync(corePath, 'utf8');
function core(): Core {
  const context: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; console: typeof console; morphirWorkbenchExecutions?: Core } = { TextEncoder, TextDecoder, console };
  runInNewContext(compiled, context);
  if (!context.morphirWorkbenchExecutions) throw new Error('Missing production execution core');
  return context.morphirWorkbenchExecutions;
}
const jsonPath = process.env.MORPHIR_WORKBENCH_MCK_JSON;
if (!jsonPath) throw new Error('Set MORPHIR_WORKBENCH_MCK_JSON to the compiled MCK framing codec');
const framing: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; console: typeof console; morphirWorkbenchMckJson?: Core } = { TextEncoder, TextDecoder, console };
runInNewContext(readFileSync(jsonPath, 'utf8'), framing);
const parseFrame = framing.morphirWorkbenchMckJson;
if (!parseFrame) throw new Error('Missing compiled MCK framing codec');
const browserMode = process.env.MORPHIR_WORKBENCH_HTTP_CLIENT_BROWSER === '1';
async function browserBinding() {
  const driverPath = process.env.MORPHIR_WORKBENCH_HTTP_CLIENT_DRIVER;
  if (!driverPath) throw new Error('Set MORPHIR_WORKBENCH_HTTP_CLIENT_DRIVER to the checked browser driver');
  const driver = readFileSync(driverPath);
  const server = createServer((request, response) => {
    const source = request.url === '/core.js' ? compiled : request.url === '/trace.js' ? driver : request.url === '/' ? '<!doctype html><html><body>HTTP client MCK fixture</body></html>' : null;
    response.writeHead(source === null ? 404 : 200, { 'content-type': request.url === '/' ? 'text/html; charset=utf-8' : 'text/javascript; charset=utf-8', 'cache-control': 'no-store' });
    response.end(source ?? 'Not found');
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Missing fixture address');
  let browser;
  try { browser = await chromium.launch({ headless: true }); }
  catch (error) { server.close(); throw error; }
  const url = `http://127.0.0.1:${address.port}`;
  return {
    async run(input: unknown) {
      const page = await browser.newPage();
      try {
        await page.goto(url); await page.addScriptTag({ url: url + '/core.js' });
        return await page.evaluate(async ({ input, url }) => {
          const trace = await import(url + '/trace.js') as typeof import('../browser/http-client-trace.ts');
          return trace.runHttpPolicyClientTrace(input, globalThis.morphirWorkbenchExecutions);
        }, { input, url });
      } finally { await page.close(); }
    },
    async close() { await browser.close(); await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); },
  };
}
const browser = browserMode ? await browserBinding() : null;
const closed = (value: Record<string, unknown>, keys: string[]) => {
  if (Object.keys(value).sort().join(',') !== [...keys].sort().join(',')) throw new Error('Invalid MCK request shape');
};
async function handle(line: string) {
  const decoded: unknown = JSON.parse(parseFrame!(line));
  if (!isRecord(decoded) || decoded.ok !== true || !isRecord(decoded.value)) throw new Error('Invalid MCK JSON');
  const request = decoded.value;
  if (request.op === 'exit') {
    closed(request, request.id === undefined ? ['op'] : ['id', 'op']);
    if (request.id !== undefined && (!Number.isSafeInteger(request.id) || Number(request.id) < 1)) throw new Error('Invalid exit id');
    return null;
  }
  if (!Number.isSafeInteger(request.id) || Number(request.id) < 1 || request.suite !== 'workbench' || request.contractVersion !== '0.1.0-draft.24') throw new Error('Invalid MCK negotiation');
  if (request.op === 'capabilities') {
    closed(request, ['id', 'op', 'suite', 'contractVersion']);
    return { id: request.id, suite: 'workbench', contractVersion: '0.1.0-draft.24', binding: 'morphir-moonbit-http-policy-client-' + (browserMode ? 'chromium' : 'node'), language: 'typescript', operations: ['run-http-policy-client'], formats: ['json'] };
  }
  closed(request, ['id', 'op', 'suite', 'contractVersion', 'format', 'input']);
  if (request.op !== 'run-http-policy-client' || request.format !== 'json') throw new Error('Unsupported HTTP client operation');
  return { id: request.id, status: 'ok', value: await (browser ? browser.run(request.input) : runHttpPolicyClientTrace(request.input, core())) };
}
async function serve() {
  let pending = Buffer.alloc(0);
  const decoder = new TextDecoder('utf-8', { fatal: true }), limit = 2 * 1024 * 1024;
  for await (const chunk of process.stdin) {
    pending = Buffer.concat([pending, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)]);
    let end: number;
    while ((end = pending.indexOf(10)) !== -1) {
      if (end > limit) throw new Error('Oversize MCK line');
      const line = decoder.decode(pending.subarray(0, end)); pending = pending.subarray(end + 1);
      const reply = await handle(line);
      if (reply === null) { process.stdin.destroy(); return; }
      if (!process.stdout.write(JSON.stringify(reply) + '\n')) await once(process.stdout, 'drain');
    }
    if (pending.length > limit) throw new Error('Oversize MCK line');
  }
  if (pending.length) throw new Error('Incomplete MCK line');
}
try { await serve(); }
catch { process.stderr.write('HTTP client MCK infrastructure failure\n'); process.exitCode = 1; process.stdin.destroy(); }
finally { await browser?.close(); }
