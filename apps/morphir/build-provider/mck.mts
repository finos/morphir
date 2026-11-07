import { existsSync, lstatSync, readFileSync } from 'node:fs';
import { isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { supervised } from './supervision.mjs';
import { pinnedFileHash } from './identity.mjs';

// A pin saved for beta.10 stays accepted; the release manifest acquires beta.12.
const runnerVersions = ['0.4.0-beta.10', '0.4.0-beta.12'] as const;
interface RunnerPin {
  contractVersion: '0.1.0-draft.1'; runnerVersion: typeof runnerVersions[number];
  executable: string; sha256: string; sourceRevision: string; origin: string;
}
interface MckRequest {
  profile: 'morphir/cli/mck-command'; contractVersion: '0.1.0-draft.1';
  pin: RunnerPin; arguments: string[]; cwd: string; timeout: number; cancelFile: string;
}
export interface MckResult {
  profile: 'morphir/cli/mck-command'; contractVersion: '0.1.0-draft.1';
  state: 'completed' | 'refused' | 'failed' | 'cancelled'; exitCode: number;
  runner?: RunnerPin; arguments?: string[]; stdout: string; stderr: string; error?: string;
  embeddedKit?: { revision: string; corpusHash: string; driverContract: 2; algorithm: string };
}
const profile = 'morphir/cli/mck-command', contractVersion = '0.1.0-draft.1';
function check(value: unknown, code: string): asserts value { if (!value) throw Error(code); }
function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function exact(value: Record<string, unknown>, fields: string[]) {
  return Object.keys(value).length === fields.length && fields.every(key => Object.hasOwn(value, key));
}
function request(value: unknown): MckRequest {
  check(record(value) && exact(value, ['profile','contractVersion','pin','arguments','cwd','timeout','cancelFile']) &&
    value.profile === profile && value.contractVersion === contractVersion, 'mck.invalid_request');
  check(Buffer.byteLength(JSON.stringify(value)) <= 131072, 'mck.argument_limit');
  const pin = value.pin;
  check(record(pin) && exact(pin, ['contractVersion','runnerVersion','executable','sha256','sourceRevision','origin']) &&
    pin.contractVersion === contractVersion, 'mck.invalid_runner_pin');
  check(runnerVersions.some(version => version === pin.runnerVersion), 'mck.unsupported_runner_version');
  check(typeof pin.executable === 'string' && isAbsolute(pin.executable) && pin.executable.length <= 4096 && !pin.executable.includes('\0') &&
    typeof pin.sha256 === 'string' && /^[a-f0-9]{64}$/.test(pin.sha256) &&
    typeof pin.sourceRevision === 'string' && /^[a-f0-9]{40}$/.test(pin.sourceRevision) &&
    typeof pin.origin === 'string' && pin.origin.length > 0 && pin.origin.length <= 2048 && !pin.origin.includes('\0'), 'mck.invalid_runner_pin');
  check(Array.isArray(value.arguments) && value.arguments.length > 0 && value.arguments.length <= 1000 &&
    value.arguments.every(arg => typeof arg === 'string' && arg.length <= 65536 && !arg.includes('\0')), 'mck.argument_limit');
  check(typeof value.cwd === 'string' && isAbsolute(value.cwd) && !value.cwd.includes('\0') &&
    Number.isSafeInteger(value.timeout) && Number(value.timeout) >= 1 && Number(value.timeout) <= 594000 &&
    typeof value.cancelFile === 'string' && !value.cancelFile.includes('\0'), 'mck.invalid_request');
  return value as unknown as MckRequest;
}

/** Effects only: the canonical runner retains every kit, suite and verdict. */
export async function mckCommand(value: unknown, interrupted: () => boolean = () => false, onProcessStarted?: (program: string) => void): Promise<MckResult> {
  let config: MckRequest | undefined, started = false;
  try {
    config = request(value);
    const deadline = performance.now() + config.timeout;
    const cancelFile = config.cancelFile ? resolve(config.cwd, config.cancelFile) : '';
    const tick = () => {
      check(!interrupted() && (!cancelFile || !existsSync(cancelFile)), 'execution.cancelled');
      check(performance.now() < deadline, 'execution.deadline');
    };
    const pin = () => check(pinnedFileHash(config!.pin.executable, tick, 'mck.executable') === config!.pin.sha256, 'mck.executable_changed');
    const run = (args: string[]) => {
      tick();
      return supervised(config!.pin.executable, args, {
        cwd: config!.cwd, env: { ...process.env, MORPHIR_NO_BANNER: '1' },
        timeout: Math.max(1, Math.floor(deadline - performance.now())), cancelFile, cancelled: interrupted, onProcessStarted, interruptGraceMs: 5000,
      });
    };
    pin();
    const version = await run(['--no-banner', '--version']);
    check(version.code === 0 && !version.signal && version.stdout.trim() === `morphir ${config.pin.runnerVersion}`, 'mck.runner_version_mismatch');
    const status = await run(['--no-banner', 'mck', 'kit', 'status', '--json']);
    check(status.code === 0 && !status.signal, 'mck.runner_contract_mismatch');
    const identity: unknown = JSON.parse(status.stdout);
    check(record(identity) && identity.revision === config.pin.sourceRevision && identity.driverContract === 2 &&
      identity.algorithm === 'mck-file-map-sha256/1' && typeof identity.corpusHash === 'string' &&
      /^sha256-[a-f0-9]{64}$/.test(identity.corpusHash), 'mck.runner_contract_mismatch');
    const embeddedKit = { revision: config.pin.sourceRevision, corpusHash: identity.corpusHash,
      driverContract: 2 as const, algorithm: identity.algorithm };
    pin();
    started = true;
    const result = await run(['--no-banner', 'mck', ...config.arguments]);
    pin();
    check(result.code !== null && !result.signal, 'mck.runner_terminated');
    return { profile, contractVersion, state: 'completed', exitCode: result.code,
      runner: config.pin, embeddedKit, arguments: config.arguments, stdout: result.stdout, stderr: result.stderr };
  } catch (cause) {
    const error = cause instanceof Error ? cause.message : 'mck.operation_failed';
    const cancelled = error.includes('execution.cancelled'), timedOut = error.includes('execution.deadline');
    return { profile, contractVersion, state: cancelled ? 'cancelled' : started ? 'failed' : 'refused',
      exitCode: cancelled ? 130 : timedOut ? 124 : started ? 1 : 2,
      ...(config ? { runner: config.pin, arguments: config.arguments } : {}), stdout: '', stderr: '', error };
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let result: MckResult;
  try {
    check(process.argv.length === 4 && process.argv[2] === '--morphir-mck-v1', 'mck.invalid_control');
    const path = process.argv[3]!;
    const stat = lstatSync(path);
    check(stat.isFile() && stat.size <= 131072, 'mck.invalid_control');
    result = await mckCommand(JSON.parse(readFileSync(path, 'utf8')));
  } catch {
    result = { profile, contractVersion, state: 'refused', exitCode: 2, stdout: '', stderr: '', error: 'mck.invalid_control' };
  }
  // This is the private helper envelope, not the canonical report format.
  process.stdout.write(JSON.stringify(result));
}
