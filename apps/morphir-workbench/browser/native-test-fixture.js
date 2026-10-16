// Actual compiled production admission and receipt cursor, isolated per client.
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
const compiled = readFileSync(new URL('../dist/job-core.js', import.meta.url), 'utf8');
export function core() {
  const context = { TextEncoder, TextDecoder, console };
  runInNewContext(compiled, context);
  return context.morphirWorkbenchJobs;
}
export const version = '0.1.0-draft.1';
export const descriptor = { profile: 'morphir/workbench/native', contractVersion: version,
  sessionId: 'proton-session-1', operations: [] };
export const success = (operation, value) => JSON.stringify({ ok: true, operation, value });
export const failure = (code = 'unauthorized', effect = 'none') => JSON.stringify({ ok: false,
  error: { code, effect, message: 'Native request rejected.' } });
export function bridge(handle = () => descriptor) {
  return async (name, source) => {
    if (name !== 'app:workbench_native') throw new Error('Unexpected native command');
    const frame = JSON.parse(source);
    const value = await handle(frame);
    return typeof value === 'string' ? value : success(frame.operation, value);
  };
}
