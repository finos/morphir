import type { Core, Json } from './contracts.ts';
// Actual compiled production validation and receipt cursor, isolated per client.
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
const compiled = readFileSync(new URL('../dist/execution-core.js', import.meta.url), 'utf8');
export function core() {
  const context: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; console: typeof console; morphirWorkbenchExecutions?: Core } = { TextEncoder, TextDecoder, console };
  runInNewContext(compiled, context);
  if (!context.morphirWorkbenchExecutions) throw new Error('Missing compiled core');
  return context.morphirWorkbenchExecutions;
}
export const version = '0.2.0-draft.1';
export const descriptor = { profile: 'morphir/workbench/native', contractVersion: version,
  sessionId: 'proton-session-1', operations: [] };
export const success = (operation: string, value: unknown) => JSON.stringify({ ok: true, operation, value });
export const failure = (code = 'unauthorized', effect = 'none') => JSON.stringify({ ok: false,
  error: { code, effect, message: 'Native request rejected.' } });
export function bridge(handle: (frame: { operation: string; sessionId: string; payload: Record<string, Json> }) => unknown | Promise<unknown> = () => descriptor) {
  return async (name: string, source: string) => {
    if (name !== 'app:workbench_native') throw new Error('Unexpected native command');
    const frame = JSON.parse(source);
    const value = await handle(frame);
    return typeof value === 'string' ? value : success(frame.operation, value);
  };
}
