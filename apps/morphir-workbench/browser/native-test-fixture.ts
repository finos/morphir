import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { resolve } from 'node:path';


import type { Core, Json } from './contracts.ts';
// Actual compiled production validation and receipt cursor, isolated per client.
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
const compiled = readFileSync(process.env.MORPHIR_WORKBENCH_EXECUTION_CORE ?? new URL('../dist/execution-core.js', import.meta.url), 'utf8');
export function core() {
  const context: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; console: typeof console; morphirWorkbenchExecutions?: Core } = { TextEncoder, TextDecoder, console };
  runInNewContext(compiled, context);
  if (!context.morphirWorkbenchExecutions) throw new Error('Missing compiled core');
  return context.morphirWorkbenchExecutions;
}
export function worksheetCore(): Core {
  const context: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; console: typeof console; morphirWorkbenchWorksheet?: Core } = { TextEncoder, TextDecoder, console };
  runInNewContext(compiled, context);
  if (!context.morphirWorkbenchWorksheet) throw new Error('Missing compiled worksheet core');
  return context.morphirWorkbenchWorksheet;
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

/** Test-only native owner: its parent supplies the fixed picker root. */
export function nativeFileHost(root: string) {
  const executable = resolve(import.meta.dirname, '../../../_build/native/debug/build/finos/morphir-workbench-native/files-acceptance/files-acceptance.exe');
  const child = spawn(executable, [root], { stdio: ['pipe', 'pipe', 'pipe'] });
  const pending: { resolve(value: string): void; reject(error: Error): void }[] = [];
  let stderr = '';
  child.stderr.on('data', data => { stderr += data; });
  const lines = createInterface({ input: child.stdout });
  lines.on('line', line => pending.shift()?.resolve(line));
  child.on('error', error => { for (const item of pending.splice(0)) item.reject(error); });
  child.on('exit', () => { for (const item of pending.splice(0)) item.reject(new Error(`Native file test owner exited: ${stderr}`)); });
  return {
    exchange(source: string) { return new Promise<string>((resolve, reject) => { pending.push({ resolve, reject }); child.stdin.write(source + '\n'); }); },
    async close() {
      child.stdin.end(); if (child.exitCode === null) await once(child, 'exit'); lines.close();
      if (child.exitCode !== 0) throw new Error(`Native file test owner failed (${child.exitCode}): ${stderr}`);
    },
  };
}
