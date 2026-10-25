import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pinnedFileHash } from './identity.mjs';
import { supervisedBytes } from './supervision.mjs';

const profile = 'morphir/cli/native-services', contractVersion = '0.1.0';
export const sharedRevision = 'ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409';
const record = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v);
const check = (v: unknown, message: string): void => { if (!v) throw Error(message); };
const digest = (v: unknown) => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
const absolute = (v: unknown): v is string => typeof v === 'string' && isAbsolute(v) && !v.includes('\0');

/** Supervise a verified copy of the shared-library adapter. The adapter owns
 * MEP and distribution semantics; this module owns process-group cleanup. */
export async function extensionCommand(value: unknown, interrupted: () => boolean = () => false) {
  let stage = '', work = '';
  const empty = () => { try { return readdirSync(work).length === 0; } catch { return false; } };
  try {
    check(record(value) && value.profile === profile && value.contractVersion === contractVersion, 'native.invalid_request');
    const config = value as Record<string, unknown>;
    check(absolute(config.requestFile) && absolute(config.responseFile) && absolute(config.workDirectory), 'native.invalid_paths');
    check(Number.isSafeInteger(config.timeout) && Number(config.timeout) > 0 && Number(config.timeout) <= 594000 && typeof config.cancelFile === 'string', 'native.invalid_controls');
    work = config.workDirectory as string;
    check(empty(), 'native.work_directory_not_empty');
    const host = config.host;
    check(record(host) && absolute(host.executable) && digest(host.sha256) && host.sourceRevision === sharedRevision, 'native.invalid_host_pin');
    const pin = host as { executable: string; sha256: string; sourceRevision: string };
    const timeout = Number(config.timeout), deadline = performance.now() + timeout;
    const tick = () => {
      check(!interrupted() && (!config.cancelFile || !existsSync(String(config.cancelFile))), 'execution.cancelled');
      check(performance.now() < deadline, 'execution.deadline');
    };
    tick();
    stage = mkdtempSync(join(tmpdir(), 'morphir-native-services-'));
    const executable = join(stage, process.platform === 'win32' ? 'adapter.exe' : 'adapter');
    check(pinnedFileHash(pin.executable, tick, 'native.adapter', executable) === pin.sha256, 'native.host_identity_mismatch');
    chmodSync(executable, 0o500);
    const temporary = join(stage, 'temporary');
    mkdirSync(temporary, { mode: 0o700 });
    const input = readFileSync(config.requestFile as string);
    check(input.length <= 4194304, 'native.request_limit');
    const child = await supervisedBytes(executable, [], { cwd: work,
      env: process.platform === 'win32' ? { SystemRoot: process.env.SystemRoot, TMP: temporary, TEMP: temporary } : { TMPDIR: temporary },
      timeout: Math.max(1, Math.floor(deadline - performance.now())),
      cancelFile: String(config.cancelFile), cancelled: interrupted, input });
    tick();
    check(child.code === 0 && !child.signal, 'native.adapter_failed');
    const reply: unknown = JSON.parse(child.stdout.toString('utf8'));
    check(record(reply) && reply.profile === 'morphir/native-services' && reply.contractVersion === contractVersion && reply.sourceRevision === sharedRevision, 'native.invalid_adapter_reply');
    writeFileSync(config.responseFile as string, child.stdout, { flag: 'wx', mode: 0o600 });
    return { profile, contractVersion, state: 'exited', stderr: child.stderr, workDirectoryEmpty: empty() };
  } catch (cause) {
    const error = cause instanceof Error ? cause.message : 'native.failed';
    return { profile, contractVersion, state: error.includes('execution.cancelled') ? 'cancelled' : 'failed', error, stderr: '', workDirectoryEmpty: empty() };
  } finally {
    if (stage) rmSync(stage, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let stopped = false;
  process.on('SIGINT', () => { stopped = true; });
  process.on('SIGTERM', () => { stopped = true; });
  let reply;
  try {
    check(process.argv.length === 4 && process.argv[2] === '--morphir-extension-v1', 'native.invalid_control');
    reply = await extensionCommand(JSON.parse(readFileSync(process.argv[3]!, 'utf8')), () => stopped);
  } catch {
    reply = { profile, contractVersion, state: 'failed', error: 'native.invalid_control', stderr: '', workDirectoryEmpty: false };
  }
  process.stdout.write(JSON.stringify(reply));
}
