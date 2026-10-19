import {openSync, closeSync, writeFileSync, constants, lstatSync, existsSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {isDeepStrictEqual} from 'node:util';
import {
  ArtifactTransferAttempt, ArtifactTransferProtocolError,
} from '../../../pkgs/morphir-host/artifact-client/artifact-transfer.ts';
import {openArtifactChannel} from '../../../pkgs/morphir-host/artifact-client/artifact-rpc.ts';
import {selectArtifactTransferProfile} from '../../../pkgs/morphir-host/artifact-client/artifact-client/artifact-transfer.ts';
import {
  Refusal, refuse, closed, record, readBounded, decode, connection, context, authenticatedWebSocket,
} from '../../../pkgs/morphir-host/connection/node-session.mts';
import {artifactConnectionDescriptor} from '../../../pkgs/morphir-host/artifact-client/selection.mts';
import type {Core, Json} from '../../../pkgs/morphir-host/execution-client/contracts.mts';

const profile = 'morphir/cli/transfer-command';
const version = '0.1.0';
const binding = 'workbench-http';
type Stop = 'sigint' | 'timeout' | 'cancel-file';
type Observation = 'not-published' | 'discarded' | 'generation-failed' | 'verified';
interface Configuration {
  profile: typeof profile;
  contractVersion: typeof version;
  binding: typeof binding;
  operation: 'artifacts';
  source: string;
  connection: string;
  scratch: string;
  timeout: number;
  cancelFile: string;
}
interface Request {
  providerId: string;
  target: string;
  irVersion: string;
  ir: Json;
  options: Json;
}

function configuration(raw: unknown): Configuration {
  const fields = ['profile', 'contractVersion', 'binding', 'operation', 'source', 'connection', 'scratch', 'timeout', 'cancelFile'];
  if (!closed(raw, fields)) refuse('transfer.invalid_command');
  const value = raw as unknown as Configuration;
  if (value.profile !== profile || value.contractVersion !== version || value.binding !== binding ||
      value.operation !== 'artifacts' || typeof value.source !== 'string' ||
      Buffer.byteLength(value.source) > 1048576 || typeof value.connection !== 'string' ||
      !value.connection || typeof value.scratch !== 'string' || !value.scratch ||
      typeof value.cancelFile !== 'string' || !Number.isInteger(value.timeout) ||
      value.timeout < 1 || value.timeout > 600000) refuse('transfer.invalid_command');
  if (process.platform === 'win32' || !process.getuid) refuse('connected.private_file_permissions_unavailable');
  const scratch = lstatSync(value.scratch);
  if (!scratch.isDirectory() || (scratch.mode & 0o077) !== 0 || scratch.uid !== process.getuid()) {
    refuse('transfer.private_scratch_required');
  }
  return value;
}

async function acquire(config: Configuration, core: Core, interrupted: () => boolean): Promise<{code: number; report: object}> {
  const raw = decode(core, config.source);
  if (!closed(raw, ['providerId', 'target', 'irVersion', 'ir', 'options']) || !record(raw) ||
      typeof raw.providerId !== 'string' || typeof raw.target !== 'string' ||
      typeof raw.irVersion !== 'string') refuse('transfer.invalid_request');
  const request = structuredClone(raw) as unknown as Request;
  const selected = connection(core, config.connection);
  const deadline = new AbortController();
  const http = context(selected.origin, selected.cookie, Math.min(config.timeout, 10000), deadline.signal);
  let attempt: ArtifactTransferAttempt | undefined;
  let stop: Stop | null = null;
  let stopping: Promise<unknown> | undefined;
  const started = performance.now();
  const requestStop = (reason: Stop) => {
    if (stop) return;
    stop = reason;
    deadline.abort();
    if (attempt) stopping = attempt.cancel();
  };
  const onInterrupt = () => requestStop('sigint');
  process.on('SIGINT', onInterrupt);
  const watch = setInterval(() => {
    if (interrupted()) requestStop('sigint');
    if (config.cancelFile && existsSync(config.cancelFile)) requestStop('cancel-file');
    if (performance.now() - started >= config.timeout) requestStop('timeout');
  }, 20);
  const resultReport = (observation: Observation, cleanup: unknown, extra: object = {}) => ({
    profile, contractVersion: version, binding, operation: 'artifacts', observation,
    stopReason: stop, cleanup, ...extra,
  });
  try {
    if (interrupted()) requestStop('sigint');
    if (config.cancelFile && existsSync(config.cancelFile)) requestStop('cancel-file');
    if (stop) return {code: 130, report: resultReport('not-published', {kind: 'not-connected'})};
    const manifest = await http.manifest(core);
    if (manifest.sessionId !== selected.sessionId) refuse('connected.session_changed');
    const descriptor = artifactConnectionDescriptor(manifest);
    if (!isDeepStrictEqual(descriptor, selected.descriptor)) refuse('connected.offer_changed');
    if (!record(descriptor) || !record(descriptor.provider) || descriptor.provider.id !== request.providerId) {
      refuse('transfer.provider_changed');
    }
    const provider = manifest.providers.find(provider => provider.id === request.providerId)!;
    const selection = selectArtifactTransferProfile({...provider, status: 'available'});
    if (!selection.ok) refuse('transfer.profile_unavailable');
    attempt = new ArtifactTransferAttempt(selection.value, {
      sessionId: selected.sessionId, target: request.target, irVersion: request.irVersion,
      ir: request.ir, options: request.options,
    }, {
      isCurrent: () => !stop && !interrupted(),
      connect: signal => openArtifactChannel(() => authenticatedWebSocket(selected), signal, Math.min(config.timeout, 10000)),
    });
    if (stop || interrupted()) {
      requestStop('sigint');
      return {code: stop === 'timeout' ? 1 : 130, report: resultReport('not-published', await attempt.cancel())};
    }
    const result = await attempt.run();
    if (interrupted()) requestStop('sigint');
    await stopping;
    if (result.kind === 'discarded') {
      return {code: stop === 'timeout' ? 1 : 130, report: resultReport('discarded', result.cleanup)};
    }
    if (result.kind === 'failed') {
      const error = result.error instanceof ArtifactTransferProtocolError ? result.error.failure.code : 'transfer.verification_failed';
      return {code: 1, report: resultReport('not-published', result.cleanup, {error})};
    }
    if (result.kind === 'generation-failed') {
      return {code: 1, report: resultReport('generation-failed', result.cleanup, {error: 'transfer.producer_failed'})};
    }
    if (stop || interrupted()) {
      requestStop('sigint');
      return {code: stop === 'timeout' ? 1 : 130, report: resultReport('discarded', result.cleanup)};
    }
    const files = [];
    for (const [index, artifact] of result.files.manifest.artifacts.entries()) {
      if (stop || interrupted()) {
        requestStop('sigint');
        return {code: stop === 'timeout' ? 1 : 130, report: resultReport('discarded', result.cleanup)};
      }
      const bytes = result.files.bytes(artifact.id);
      let fd = -1;
      try {
        fd = openSync(join(config.scratch, 'file-' + index),
          constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW || 0), 0o600);
        writeFileSync(fd, bytes);
      } finally { if (fd >= 0) closeSync(fd); }
      files.push({path: artifact.path, byteLength: artifact.byteLength, sha256: artifact.sha256});
    }
    if (stop || interrupted()) {
      requestStop('sigint');
      return {code: stop === 'timeout' ? 1 : 130, report: resultReport('discarded', result.cleanup)};
    }
    return {code: 0, report: resultReport('verified', result.cleanup, {files})};
  } catch (error) {
    const cleanup = attempt ? await attempt.cancel() : {kind: 'not-connected'};
    return {
      code: stop === 'timeout' ? 1 : stop ? 130 : error instanceof Refusal ? 2 : 1,
      report: resultReport('not-published', cleanup, {
        error: error instanceof Refusal ? error.code : 'transfer.transport_unavailable',
      }),
    };
  } finally {
    clearInterval(watch);
    process.off('SIGINT', onInterrupt);
    http.close();
    await stopping;
  }
}

/** All file and stream bytes use the maintained exact .21 consumer. */
export async function transferCommand(raw: unknown, suppliedCore?: Core, interrupted: () => boolean = () => false): Promise<{code: number; report: object}> {
  try {
    const config = configuration(raw);
    let core = suppliedCore;
    if (!core) {
      await import(new URL('../dist/connected-core.js', import.meta.url).href);
      const factory = (globalThis as typeof globalThis & {__morphirConnectedCore?: () => Core}).__morphirConnectedCore;
      if (!factory) refuse('connected.validation_core_unavailable');
      core = factory();
    }
    return await acquire(config, core, interrupted);
  } catch (error) {
    return {code: 2, report: {
      profile, contractVersion: version, binding, operation: 'artifacts', observation: 'refused',
      cleanup: {kind: 'not-connected'}, error: error instanceof Refusal ? error.code : 'transfer.invalid_command',
    }};
  }
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  let result;
  try {
    if (process.argv[2] !== '--morphir-transfer-v1' || !process.argv[3] || process.argv.length !== 4) refuse('transfer.invalid_command');
    result = await transferCommand(JSON.parse(readBounded(process.argv[3], 4194304)));
  } catch {
    result = {code: 2, report: {
      profile, contractVersion: version, binding, operation: 'artifacts', observation: 'refused',
      cleanup: {kind: 'not-connected'}, error: 'transfer.invalid_command',
    }};
  }
  console.log(JSON.stringify(result.report));
  process.exitCode = result.code;
}
