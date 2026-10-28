import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { chmodSync, closeSync, constants, existsSync, fstatSync, lstatSync, mkdirSync, mkdtempSync, openSync, readFileSync, readSync, readdirSync, realpathSync, rmSync, writeFileSync, writeSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { supervised, supervisedBytes } from './supervision.mjs';

export const profile = 'morphir/cli/extism-services';
export const contractVersion = '0.1.0';
export const executionProfile = 'morphir/extism-mep-0.1/v1';
/** This exact closure is copied and checked before the worker is executed. */
export const helperModules = ['extism.mjs', 'supervision.mjs', 'windows-job.mjs'] as const;
const requestLimit = 4194304, descriptorLimit = 1048576, wasmLimit = 134217728;

export interface ExtismPin {
  contractVersion: typeof contractVersion; binding: 'extism-wasm'; executionProfile: typeof executionProfile;
  host: { executable: string; sha256: string; sourceRevision: string };
  runtime: { executable: string; version: string; sha256: string };
  helper: { root: string; modules: Record<string, string> };
  artifact: { directory: string; descriptorSha256: string; wasmSha256: string; extensionId: string; version: string };
  origin: string;
}
interface ExtismRequest {
  profile: typeof profile; contractVersion: typeof contractVersion; pin: ExtismPin;
  requestFile: string; responseFile: string; workDirectory: string; timeout: number; cancelFile: string;
}
export interface ExtismReply {
  profile: typeof profile; contractVersion: typeof contractVersion; state: 'exited' | 'failed' | 'cancelled';
  stderr: string; workDirectoryEmpty: boolean; error?: string;
}
function check(value: unknown, code: string): asserts value { if (!value) throw Error(code); }
function record(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function exact(value: Record<string, unknown>, keys: readonly string[]) { return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)); }
const digest = (value: unknown) => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const path = (value: unknown) => typeof value === 'string' && value.length <= 4096 && isAbsolute(value) && !value.includes('\0');
const text = (value: unknown, limit = 2048) => typeof value === 'string' && value.length > 0 && value.length <= limit && !value.includes('\0');

interface LosslessJson {
  parse(source: string, revive: (key: string, value: unknown, context?: {source?: string}) => unknown): unknown;
  rawJSON(source: string): unknown;
}
/** Delegate JSON tokenization to the runtime and retain numeric source tokens.
 * Parsing into ordinary JavaScript numbers would corrupt IR integers before
 * the shared Rust codec ever received them. */
function opaqueRequest(source: string): unknown {
  const native = JSON as unknown as LosslessJson;
  check(typeof native.rawJSON === 'function', 'extension.unsupported_runtime');
  let token = '';
  native.parse('9007199254740993', (_key, value, context) => { token = context?.source ?? ''; return value; });
  check(token === '9007199254740993' && JSON.stringify(native.rawJSON(token)) === token, 'extension.unsupported_runtime');
  return native.parse(source, (_key, value, context) => {
    if (typeof value !== 'number') return value;
    check(typeof context?.source === 'string', 'extension.unsupported_runtime');
    return native.rawJSON(context.source);
  });
}

const runtimeProbe = 'let source="";try{JSON.parse("9007199254740993",(_k,v,c)=>{source=c?.source??"";return v});if(typeof JSON.rawJSON!=="function"||source!=="9007199254740993"||JSON.stringify(JSON.rawJSON(source))!==source)process.exit(78);process.stdout.write(process.version)}catch{process.exit(78)}';

function request(value: unknown): ExtismRequest {
  check(record(value) && exact(value, ['profile','contractVersion','pin','requestFile','responseFile','workDirectory','timeout','cancelFile']) &&
    value.profile === profile && value.contractVersion === contractVersion, 'extension.invalid_request');
  const pin = value.pin;
  check(record(pin) && exact(pin, ['contractVersion','binding','executionProfile','host','runtime','helper','artifact','origin']) &&
    pin.contractVersion === contractVersion, 'extension.invalid_pin');
  check(pin.binding === 'extism-wasm', 'extension.unsupported_binding');
  check(pin.executionProfile === executionProfile, 'extension.unsupported_execution_profile');
  const {host, runtime, helper, artifact} = pin;
  check(record(host) && exact(host, ['executable','sha256','sourceRevision']) && path(host.executable) && digest(host.sha256) &&
    typeof host.sourceRevision === 'string' && /^[a-f0-9]{40}$/.test(host.sourceRevision), 'extension.invalid_pin');
  check(record(runtime) && exact(runtime, ['executable','version','sha256']) && path(runtime.executable) && digest(runtime.sha256) &&
    typeof runtime.version === 'string' && /^v\d+\.\d+\.\d+$/.test(runtime.version), 'extension.invalid_pin');
  check(record(helper) && exact(helper, ['root','modules']) && path(helper.root) && record(helper.modules) &&
    exact(helper.modules, helperModules) && helperModules.every(name => digest((helper.modules as Record<string, unknown>)[name])), 'extension.incomplete_helper_modules');
  check(record(artifact) && exact(artifact, ['directory','descriptorSha256','wasmSha256','extensionId','version']) && path(artifact.directory) &&
    digest(artifact.descriptorSha256) && digest(artifact.wasmSha256) && text(artifact.extensionId, 256) && text(artifact.version, 128) && text(pin.origin), 'extension.invalid_pin');
  check(path(value.requestFile) && path(value.responseFile) && path(value.workDirectory) && Number.isSafeInteger(value.timeout) &&
    Number(value.timeout) > 0 && Number(value.timeout) <= 594000 && typeof value.cancelFile === 'string' && !value.cancelFile.includes('\0'), 'extension.invalid_request');
  return value as unknown as ExtismRequest;
}

/** Hash, bound and copy the same no-follow file descriptor. The returned bytes
 * are read from the snapshot, never by reopening an unverified input path. */
function copyVerified(source: string, destination: string, expected: string | undefined, limit: number, tick: () => void): void {
  tick();
  const before = lstatSync(source);
  check(before.isFile(), 'extension.integrity_mismatch');
  check(before.size <= limit, 'extension.resource_limit');
  const input = openSync(source, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  let output: number | undefined;
  try {
    const opened = fstatSync(input);
    check(opened.isFile() && opened.dev === before.dev && opened.ino === before.ino, 'extension.integrity_mismatch');
    mkdirSync(dirname(destination), {recursive:true, mode:0o700});
    output = openSync(destination, 'wx', 0o600);
    const hash = createHash('sha256'), bytes = Buffer.alloc(65536);
    let total = 0;
    for (;;) {
      tick();
      const size = readSync(input, bytes, 0, bytes.length, null);
      if (!size) break;
      total += size; check(total <= limit, 'extension.resource_limit'); hash.update(bytes.subarray(0,size));
      let written = 0;
      while (written < size) written += writeSync(output, bytes, written, size - written);
    }
    const after = fstatSync(input), named = lstatSync(source);
    check(after.size === opened.size && after.mtimeMs === opened.mtimeMs && after.ctimeMs === opened.ctimeMs &&
      named.isFile() && named.dev === opened.dev && named.ino === opened.ino, 'extension.integrity_mismatch');
    check(expected === undefined || hash.digest('hex') === expected, 'extension.integrity_mismatch');
  } finally { closeSync(input); if (output !== undefined) closeSync(output); }
}

function safeMember(root: string, member: unknown): string {
  check(typeof member === 'string' && member.length > 0 && member.length <= 1024 && !member.includes('\\') && !member.includes('\0') &&
    !isAbsolute(member) && member.split('/').every(part => part !== '' && part !== '.' && part !== '..' && !part.includes(':')), 'extension.unsafe_artifact');
  let current = root;
  for (const part of member.split('/')) {
    current = join(current, part);
    check(!lstatSync(current).isSymbolicLink(), 'extension.unsafe_artifact');
  }
  return member;
}

function stagedArtifact(pin: ExtismPin, stage: string, tick: () => void): string {
  check(lstatSync(pin.artifact.directory).isDirectory() && !lstatSync(pin.artifact.directory).isSymbolicLink(), 'extension.unsafe_artifact');
  const directory = join(stage, 'artifact'), descriptorPath = join(directory, 'release.json');
  copyVerified(join(pin.artifact.directory, 'release.json'), descriptorPath, pin.artifact.descriptorSha256, descriptorLimit, tick);
  let value: unknown;
  try { value = JSON.parse(readFileSync(descriptorPath, 'utf8')); } catch { throw Error('extension.invalid_descriptor'); }
  // Canonical full descriptor and claim validation belongs to morphir-distribution
  // in the Rust adapter. This check chooses only the one pinned local WASM member.
  check(record(value) && value.schemaVersion === '2.0.0-draft.2' && value.extensionId === pin.artifact.extensionId &&
    value.version === pin.artifact.version && Array.isArray(value.artifacts), 'extension.invalid_descriptor');
  const candidates = value.artifacts.filter((artifact: unknown) => record(artifact) && artifact.runtime === 'wasm' && artifact.sha256 === pin.artifact.wasmSha256);
  check(candidates.length === 1, 'extension.integrity_mismatch');
  const artifact: unknown = candidates[0];
  check(record(artifact), 'extension.invalid_descriptor');
  const filename = safeMember(pin.artifact.directory, artifact.filename);
  copyVerified(join(pin.artifact.directory, filename), join(directory, filename), pin.artifact.wasmSha256, wasmLimit, tick);
  safeMember(pin.artifact.directory, filename);
  return directory;
}

function normalizeError(cause: unknown): string {
  const message = cause instanceof Error ? cause.message : 'extension.operation_failed';
  if (message.includes('execution.tree_termination')) return 'extension.incomplete_session: ' + message;
  if (message.includes('execution.cancelled')) return 'execution.cancelled';
  if (message.includes('execution.deadline')) return 'extension.timeout';
  if (message.includes('execution.response_limit') || message.includes('execution.diagnostic_limit') || message.includes('execution.input_limit')) return 'extension.resource_limit';
  return message.startsWith('extension.') || message.includes('execution.tree_termination') ? message : 'extension.operation_failed: ' + message;
}

/** Trusted package bootstrap. All selected runtime, worker, host and guest
 * bytes execute only after immutable descriptor-based snapshot verification. */
export async function extensionCommand(value: unknown, interrupted: () => boolean = () => false): Promise<ExtismReply> {
  let stage = '', work = '', stderr = '', retain = false;
  let result: ExtismReply;
  const empty = () => { try { return work !== '' && readdirSync(work).length === 0; } catch { return false; } };
  try {
    const config = request(value);
    work = config.workDirectory;
    check(lstatSync(work).isDirectory() && !lstatSync(work).isSymbolicLink() && empty(), 'extension.invalid_work_directory');
    check((process.platform === 'darwin' || process.platform === 'linux') && (process.arch === 'arm64' || process.arch === 'x64'), 'extension.unsupported_target');
    if (process.platform === 'linux') check(Boolean((process.report.getReport() as {header:{glibcVersionRuntime?:string}}).header.glibcVersionRuntime), 'extension.unsupported_target');
    const deadline = performance.now() + config.timeout, cancelFile = config.cancelFile ? resolve(config.cancelFile) : '';
    const tick = () => {
      check(!interrupted() && (!cancelFile || !existsSync(cancelFile)), 'execution.cancelled');
      check(performance.now() < deadline, 'extension.timeout');
    };
    const remaining = () => Math.max(1, Math.floor(deadline - performance.now()));
    tick(); stage = realpathSync(mkdtempSync(join(tmpdir(), 'morphir-extism-')));
    const pin = config.pin, runtime = join(stage, 'node'), host = join(stage, 'adapter'), helper = join(stage, 'helper');
    copyVerified(pin.runtime.executable, runtime, pin.runtime.sha256, 536870912, tick); chmodSync(runtime, 0o500);
    copyVerified(pin.host.executable, host, pin.host.sha256, 536870912, tick); chmodSync(host, 0o500);
    for (const member of helperModules) copyVerified(join(pin.helper.root, member), join(helper, member), pin.helper.modules[member], 4194304, tick);
    const artifact = stagedArtifact(pin, stage, tick);
    const privateRequest = join(stage, 'request.json');
    copyVerified(config.requestFile, privateRequest, undefined, requestLimit, tick);
    let input: unknown;
    try { input = opaqueRequest(new TextDecoder('utf-8', {fatal:true}).decode(readFileSync(privateRequest))); }
    catch (cause) { if (cause instanceof Error && cause.message === 'extension.unsupported_runtime') throw cause; throw Error('extension.invalid_request'); }
    check(record(input) && ['extism.describe','extism.compile','extism.generate'].includes(String(input.operation)) && isDeepStrictEqual(input.pin, pin), 'extension.invalid_request');
    const stagedPin: ExtismPin = {...pin, host:{...pin.host, executable:host}, runtime:{...pin.runtime, executable:runtime},
      helper:{...pin.helper, root:helper}, artifact:{...pin.artifact, directory:artifact}};
    input.pin = stagedPin; input.timeout = remaining(); input.workDirectory = work;
    const bytes = Buffer.from(JSON.stringify(input)); check(bytes.length <= requestLimit, 'extension.resource_limit');
    const temporary = join(stage, 'temporary'); mkdirSync(temporary, {mode:0o700});
    const version = await supervised(runtime, ['-e',runtimeProbe], {cwd:work, env:{}, timeout:Math.min(remaining(),10000), cancelFile, cancelled:interrupted});
    check(version.code === 0 && !version.signal, 'extension.unsupported_runtime');
    check(version.stdout.trim() === pin.runtime.version, 'extension.runtime_version_mismatch');
    tick();
    const child = await supervisedBytes(runtime, [join(helper,'extism.mjs'),'--morphir-extism-worker-v1',host,temporary],
      {cwd:work, env:{TMPDIR:temporary}, timeout:remaining(), cancelFile, cancelled:interrupted, input:bytes});
    stderr = child.stderr;
    tick(); check(child.code === 0 && !child.signal, 'extension.host_failed');
    let reply: unknown;
    try { reply = JSON.parse(child.stdout.toString('utf8')); } catch { throw Error('extension.invalid_result'); }
    check(record(reply) && reply.profile === 'morphir/native-services' && reply.contractVersion === contractVersion &&
      reply.sourceRevision === pin.host.sourceRevision, 'extension.invalid_result');
    check(empty(), 'extension.guest_wrote_files');
    writeFileSync(config.responseFile, child.stdout, {flag:'wx', mode:0o600});
    tick();
    result = {profile, contractVersion, state:'exited', stderr:child.stderr, workDirectoryEmpty:true};
  } catch (cause) {
    const error = normalizeError(cause);
    retain = error.includes('execution.tree_termination');
    result = {profile, contractVersion, state:error.includes('execution.cancelled') ? 'cancelled' : 'failed', stderr, workDirectoryEmpty:!retain && empty(), error};
  }
  // The outer supervisor owns the worker and Rust child in the same process
  // group. An uncertain group is deliberately retained rather than disposed.
  if (stage && !retain) {
    try { rmSync(stage, {recursive:true, force:true}); }
    catch { result = {profile, contractVersion, state:'failed', stderr:result.stderr, workDirectoryEmpty:false, error:'extension.scratch_cleanup_failed'}; }
  }
  return result;
}

async function worker(program: string, temporary: string): Promise<void> {
  // Do not detach this child. The bootstrap's one owned group contains both
  // this pinned Node worker and the Rust host, including on hard cancellation.
  const child = spawn(program, [], {cwd:process.cwd(), env:{TMPDIR:temporary}, detached:false, stdio:['pipe','pipe','pipe']});
  process.stdin.pipe(child.stdin); child.stdout.pipe(process.stdout); child.stderr.pipe(process.stderr);
  child.stdin.on('error', () => {});
  let failed = false;
  child.on('error', () => { failed = true; });
  await new Promise<void>(done => child.once('close', code => { process.exitCode = failed ? 1 : code ?? 1; done(); }));
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  if (process.argv.length === 5 && process.argv[2] === '--morphir-extism-worker-v1') {
    await worker(process.argv[3]!, process.argv[4]!);
  } else {
    let result: ExtismReply;
    let stopped = false;
    const stop = () => { stopped = true; };
    process.on('SIGINT', stop); process.on('SIGTERM', stop);
    try {
      check(process.argv.length === 4 && process.argv[2] === '--morphir-extension-v1', 'extension.invalid_control');
      const control = process.argv[3]!;
      const stat = lstatSync(control);
      check(stat.isFile() && !stat.isSymbolicLink() && stat.size <= descriptorLimit, 'extension.invalid_control');
      result = await extensionCommand(JSON.parse(readFileSync(control, 'utf8')), () => stopped);
    } catch {
      result = {profile, contractVersion, state:'failed', stderr:'', workDirectoryEmpty:false, error:'extension.invalid_control'};
    } finally { process.removeListener('SIGINT', stop); process.removeListener('SIGTERM', stop); }
    process.stdout.write(JSON.stringify(result));
  }
}
