// Transport adapter only. The shared upstream MCK owns every semantic verdict;
// neither expected results nor case IDs are accepted by this process.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { appendFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { runInNewContext } from 'node:vm';

const version = '0.1.0-draft.29';
// One MiB of hex source plus the closed JSON envelope must fit in a frame.
const limit = 3 * 1024 * 1024;
const target = process.env.MORPHIR_HEADLESS_TARGET ?? 'js';
const selected = process.env.MORPHIR_HEADLESS_BINARY ?? process.env.MORPHIR_HEADLESS_CLI;
const framingPath = process.env.MORPHIR_WORKBENCH_MCK_JSON;
if (!selected || !framingPath || !['js', 'native'].includes(target))
  throw new Error('Select explicit CLI binary, duplicate-aware framing helper and js/native target');
const binary = resolve(selected);
const launcher = resolve(process.env.MORPHIR_HEADLESS_LAUNCHER ?? binary);
const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const binaryHash = hash(readFileSync(binary)), launcherHash = hash(readFileSync(launcher));
const framing: { TextEncoder: typeof TextEncoder; TextDecoder: typeof TextDecoder; morphirWorkbenchModelMckJson?: (source: string) => string } = { TextEncoder, TextDecoder };
runInNewContext(readFileSync(framingPath, 'utf8'), framing);
const core = framing.morphirWorkbenchModelMckJson;
if (!core) throw new Error('Missing production duplicate-aware MCK framing decoder');
function object(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function closed(value: Record<string, unknown>, names: string[]) {
  if (Object.keys(value).sort().join(',') !== [...names].sort().join(','))
    throw new Error('Invalid closed MCK request');
}
function parse(source: string): Record<string, unknown> {
  if (Buffer.byteLength(source) > limit) throw new Error('Oversize JSON frame');
  const decoded: unknown = JSON.parse(core!(source));
  if (!object(decoded) || decoded.ok !== true || !object(decoded.value))
    throw new Error('Invalid duplicate-aware JSON frame');
  return decoded.value;
}
let observations = 0;
function observe(operation: string, input: unknown): Record<string, unknown> {
  if (++observations > 64 || !object(input)) throw new Error('Model request budget exceeded');
  closed(input, ['providerId', 'format', 'source']);
  if (typeof input.providerId !== 'string' || input.providerId.length < 1 || input.providerId.length > 128 ||
      typeof input.format !== 'string' || !['json', 'yaml', 'ion-text', 'ion-binary'].includes(input.format) ||
      !object(input.source)) throw new Error('Unsupported local-model input binding');
  closed(input.source, ['hex']);
  if (typeof input.source.hex !== 'string' || !/^(?:[0-9a-f]{2})*$/.test(input.source.hex) ||
      input.source.hex.length > 2 * (1024 * 1024 + 1)) throw new Error('Invalid captured model byte evidence');
  const bytes = Buffer.from(input.source.hex, 'hex');
  const root = mkdtempSync(join(tmpdir(), 'morphir-model-mck-'));
  try {
    const filename = 'captured.model';
    writeFileSync(join(root, filename), bytes);
    const args = ['model', operation === 'inspect-model' ? 'inspect' : 'export-original', filename,
      '--model-format', input.format, '--json', ...(operation === 'export-model-original' ? ['--output', 'saved'] : [])];
    const child = spawnSync(target === 'native' ? binary : process.execPath, target === 'native' ? args : [launcher, ...args], {
      cwd: root, env: { ...process.env, HOME: root, USERPROFILE: root, DISPLAY: '', WAYLAND_DISPLAY: '' },
      encoding: 'utf8', timeout: 30_000, maxBuffer: limit, windowsHide: true,
    });
    if (child.error || child.signal || ![0, 2].includes(child.status ?? -1))
      throw new Error('Actual model CLI failed or exceeded its execution/output budget');
    const report = parse(child.stdout.trim());
    if (hash(readFileSync(binary)) !== binaryHash || hash(readFileSync(launcher)) !== launcherHash)
      throw new Error('Selected CLI or launcher changed during qualification');
    if (process.env.MORPHIR_MODEL_MCK_RAW) appendFileSync(process.env.MORPHIR_MODEL_MCK_RAW,
      JSON.stringify({ operation, inputSha256: hash(bytes), exitStatus: child.status, report, stderr: child.stderr }) + '\n');
    if (child.status === 2) {
      if (report.successful !== false || typeof report.code !== 'string') throw new Error('Incomplete model refusal');
      return { status: 'invalid', code: report.code };
    }
    if (report.successful !== true) throw new Error('Missing successful model evidence');
    if (operation === 'inspect-model') {
      if (report.representation !== 'normalized-ir' || report.originalKind !== 'captured-file' ||
          typeof report.irVersion !== 'string' || typeof report.distribution !== 'string' ||
          typeof report.packageName !== 'string' || !Array.isArray(report.modules) || typeof report.normalizedIr !== 'string')
        throw new Error('Incomplete actual model inspection');
      return { status: 'ok', value: {
        providerId: input.providerId, inputFormat: input.format,
        irVersion: report.irVersion, distribution: report.distribution,
        packageName: report.packageName, modules: report.modules, normalizedIr: report.normalizedIr,
      } };
    }
    if (report.kind !== 'original' || !Array.isArray(report.files) || report.files.length !== 1 ||
        !object(report.files[0]) || report.files[0].path !== 'saved/originals/' + filename)
      throw new Error('Incomplete actual original export');
    const exported = readFileSync(join(root, 'saved/originals', filename));
    if (report.files[0].byteLength !== exported.length || report.files[0].sha256 !== hash(exported))
      throw new Error('Export receipt differs from published file');
    return { status: 'ok', value: {
      providerId: input.providerId, kind: report.kind, format: input.format,
      hex: exported.toString('hex'), byteLength: report.files[0].byteLength, sha256: report.files[0].sha256,
    } };
  } finally { rmSync(root, { recursive: true, force: true }); }
}
function handle(line: string) {
  const request = parse(line);
  if (request.op === 'exit') { closed(request, request.id === undefined ? ['op'] : ['op', 'id']); return null; }
  if (!Number.isSafeInteger(request.id) || Number(request.id) < 1 || request.suite !== 'workbench' || request.contractVersion !== version)
    throw new Error('Unsupported MCK request identity/profile');
  if (request.op === 'capabilities') {
    closed(request, ['id', 'op', 'suite', 'contractVersion']);
    return { id: request.id, suite: 'workbench', contractVersion: version,
      binding: `morphir-local-model-cli-${target}-sha256:${binaryHash}`, language: 'moonbit',
      operations: ['inspect-model', 'export-model-original'], formats: ['json'] };
  }
  closed(request, ['id', 'op', 'suite', 'contractVersion', 'format', 'input']);
  if (!['inspect-model', 'export-model-original'].includes(String(request.op)) || request.format !== 'json')
    throw new Error('Unsupported MCK model operation');
  return { id: request.id, ...observe(String(request.op), request.input) };
}
async function serve() {
  let pending = Buffer.alloc(0);
  const decoder = new TextDecoder('utf-8', { fatal: true });
  for await (const chunk of process.stdin) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    let start = 0;
    while (start < bytes.length) {
      const end = bytes.indexOf(10, start);
      const stop = end < 0 ? bytes.length : end;
      const piece = bytes.subarray(start, stop);
      if (piece.length > limit - pending.length) throw new Error('Oversize MCK frame');
      pending = pending.length ? Buffer.concat([pending, piece]) : piece;
      if (end < 0) break;
      const line = decoder.decode(pending); pending = Buffer.alloc(0);
      const reply = handle(line);
      if (reply === null) { process.stdin.destroy(); return; }
      const source = JSON.stringify(reply) + '\n';
      if (Buffer.byteLength(source) > limit) throw new Error('Oversize MCK observation');
      if (!process.stdout.write(source)) await once(process.stdout, 'drain');
      start = end + 1;
    }
  }
  if (pending.length) throw new Error('Incomplete MCK frame');
}
try { await serve(); }
catch (error) {
  process.stderr.write((error instanceof Error ? error.message : 'MCK adapter infrastructure failure').slice(0, 4096) + '\n');
  process.exitCode = 1;
}
