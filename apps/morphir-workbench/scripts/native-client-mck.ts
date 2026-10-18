import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { once } from 'node:events';
import type { Core } from '../browser/contracts.ts';
import {
  runNativeClientTrace,
  runNativePolicyClientTrace,
} from '../browser/native-client-trace.ts';
import { isRecord } from '../../../types/data.ts';
import { nativeClientBrowser } from './native-client-browser.ts';

const corePath = process.env.MORPHIR_WORKBENCH_CLIENT_CORE;
if (!corePath)
  throw new Error(
    'Set MORPHIR_WORKBENCH_CLIENT_CORE to a compiled production execution core',
  );
const compiled = readFileSync(corePath, 'utf8');
function core(): Core {
  const context: {
    TextEncoder: typeof TextEncoder;
    TextDecoder: typeof TextDecoder;
    console: typeof console;
    morphirWorkbenchExecutions?: Core;
  } = { TextEncoder, TextDecoder, console };
  runInNewContext(compiled, context);
  if (!context.morphirWorkbenchExecutions)
    throw new Error('Missing production execution core');
  return context.morphirWorkbenchExecutions;
}
const parser = core();
const browserMode = process.env.MORPHIR_WORKBENCH_CLIENT_BROWSER === '1';
const driverPath = process.env.MORPHIR_WORKBENCH_CLIENT_DRIVER;
if (browserMode && !driverPath)
  throw new Error(
    'Set MORPHIR_WORKBENCH_CLIENT_DRIVER to the checked browser driver',
  );
const mapping = process.env.MORPHIR_WORKBENCH_CLIENT_MAPPING ?? 'executions';
if (mapping !== 'executions' && mapping !== 'capability-checks')
  throw new Error('Invalid explicit native client MCK mapping');
const policy = mapping === 'capability-checks';
const browser = browserMode
  ? await nativeClientBrowser(compiled, driverPath!, mapping)
  : null;
const version = policy ? '0.1.0-draft.21' : '0.1.0-draft.17';
const operation = policy ? 'run-native-policy-client' : 'run-native-client';
function closed(value: Record<string, unknown>, keys: string[]) {
  if (Object.keys(value).sort().join(',') !== [...keys].sort().join(','))
    throw new Error('Invalid MCK request shape');
}
async function handle(line: string) {
  // Production generic JSON admission preserves duplicate detection. The compact
  // fixture budget leaves room for this diagnostic-free framing command.
  const decoded: unknown = JSON.parse(
    parser(JSON.stringify({ op: 'decode', source: line })),
  );
  if (!isRecord(decoded) || decoded.ok !== true || !isRecord(decoded.value))
    throw new Error('Invalid MCK JSON');
  const request = decoded.value;
  if (request.op === 'exit') {
    closed(request, request.id === undefined ? ['op'] : ['id', 'op']);
    if (
      request.id !== undefined &&
      (!Number.isSafeInteger(request.id) || Number(request.id) < 1)
    )
      throw new Error('Invalid exit id');
    return null;
  }
  if (
    !Number.isSafeInteger(request.id) ||
    Number(request.id) < 1 ||
    request.suite !== 'workbench' ||
    request.contractVersion !== version
  )
    throw new Error('Invalid MCK negotiation');
  if (request.op === 'capabilities') {
    closed(request, ['id', 'op', 'suite', 'contractVersion']);
    return {
      id: request.id,
      suite: 'workbench',
      contractVersion: version,
      binding:
        'morphir-moonbit-native-client-' + (browserMode ? 'chromium' : 'node'),
      language: 'typescript',
      operations: [operation],
      formats: ['json'],
    };
  }
  closed(request, ['id', 'op', 'suite', 'contractVersion', 'format', 'input']);
  if (request.op !== operation || request.format !== 'json')
    throw new Error('Unsupported client MCK operation');
  const run = policy ? runNativePolicyClientTrace : runNativeClientTrace;
  return {
    id: request.id,
    status: 'ok',
    value: await (browser
      ? browser.run(request.input)
      : run(request.input, core())),
  };
}
async function serve() {
  const limit = 2 * 1024 * 1024;
  let pending = Buffer.alloc(0);
  const decoder = new TextDecoder('utf-8', { fatal: true });
  for await (const chunk of process.stdin) {
    pending = Buffer.concat([
      pending,
      Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk),
    ]);
    let end: number;
    while ((end = pending.indexOf(10)) !== -1) {
      if (end > limit) throw new Error('Oversize MCK line');
      const line = decoder.decode(pending.subarray(0, end));
      pending = pending.subarray(end + 1);
      const reply = await handle(line);
      if (reply === null) {
        process.stdin.destroy();
        return;
      }
      if (!process.stdout.write(JSON.stringify(reply) + '\n'))
        await once(process.stdout, 'drain');
    }
    if (pending.length > limit) throw new Error('Oversize MCK line');
  }
  if (pending.length) throw new Error('Incomplete MCK line');
}
try {
  await serve();
} catch {
  process.stderr.write('native client MCK infrastructure failure\n');
  process.exitCode = 1;
  process.stdin.destroy();
} finally {
  await browser?.close();
}
