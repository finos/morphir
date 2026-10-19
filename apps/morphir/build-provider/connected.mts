import {artifactConnectionDescriptor} from '../../../pkgs/morphir-host/artifact-client/selection.mts';
import {Refusal,refuse,record,closed,readBounded,decode,connection,context,establishConnection} from '../../../pkgs/morphir-host/connection/node-session.mts';
import { existsSync } from 'node:fs';
import { isDeepStrictEqual } from 'node:util';
import { pathToFileURL } from 'node:url';
import { ExecutionClient } from '../../../pkgs/morphir-host/execution-client/client.mts';
import { HttpExecutionTransport } from '../../../pkgs/morphir-host/execution-client/transport.mts';
import type { Core, Json, WorkRequest, WorkResult } from '../../../pkgs/morphir-host/execution-client/contracts.mts';

const profile = 'morphir/cli/connected-command';
const version = '0.1.0';
const binding = 'workbench-http';
interface Configuration {
  profile: typeof profile; contractVersion: typeof version;
  operation: 'connect' | 'run'; binding: typeof binding; source: string; connectionScope?: 'executions' | 'artifacts';
  connection: string; timeout: number; cancelFile: string;
}
type Stop = 'sigint' | 'timeout' | 'cancel-file';
const safeFailure = (error: unknown) => error instanceof Refusal ? error.code : 'connected.transport_unavailable';
function configuration(raw: unknown): Configuration {
  if (!closed(raw, ['profile', 'contractVersion', 'operation', 'binding', 'source', 'connection', 'timeout', 'cancelFile', ...(record(raw) && Object.hasOwn(raw,'connectionScope') ? ['connectionScope'] : [])])) refuse('connected.invalid_command');
  const value = raw as unknown as Configuration;
  if (value.connectionScope !== undefined && !['executions','artifacts'].includes(value.connectionScope)) refuse('connected.invalid_connection_scope');
  if (value.profile !== profile || value.contractVersion !== version || value.binding !== binding ||
      !['connect', 'run'].includes(value.operation) || typeof value.source !== 'string' ||
      typeof value.connection !== 'string' || !value.connection || typeof value.cancelFile !== 'string' ||
      !Number.isInteger(value.timeout) || value.timeout < 1 || value.timeout > 600000) refuse('connected.invalid_command');
  if (Buffer.byteLength(value.source) > 1048576) refuse('connected.input_limit');
  return value;
}
async function openConnection(config: Configuration, core: Core, interrupted: () => boolean): Promise<{ code: number; report: object }> {
  const selected = await establishConnection(config, core, interrupted, async (manifest, http) => {
    if (config.connectionScope === 'artifacts') return artifactConnectionDescriptor(manifest);
    const client = new ExecutionClient(manifest.sessionId, { core, transport: new HttpExecutionTransport({ fetchFn: http.fetchFn, timeout: Math.min(config.timeout, 10000) }) });
    if (!await client.initialize()) refuse('connected.execution_unavailable');
    return client.offer as unknown as Json;
  }, () => !!config.cancelFile && existsSync(config.cancelFile));
  return {code: 0, report: {profile, contractVersion: version, operation:'connect', binding, connectionScope:config.connectionScope ?? 'executions', connected: true, ...selected}};
}

function capture(core: Core, source: string): WorkRequest {
  const value = decode(core, source);
  if (!record(value)) refuse('connected.invalid_request');
  const keys = Object.keys(value);
  if (keys.some(key => !['source', 'entry', 'arguments', 'argumentsIon', 'executionMode', 'admission'].includes(key)) ||
      typeof value.source !== 'string' || typeof value.entry !== 'string' ||
      (Object.hasOwn(value, 'arguments') === Object.hasOwn(value, 'argumentsIon')) ||
      (Object.hasOwn(value, 'arguments') && !Array.isArray(value.arguments)) ||
      (Object.hasOwn(value, 'argumentsIon') && typeof value.argumentsIon !== 'string') ||
      (Object.hasOwn(value, 'executionMode') && value.executionMode !== 'capability')) refuse('connected.invalid_request');
  return structuredClone(value) as unknown as WorkRequest;
}
async function runExecution(config: Configuration, core: Core, interrupted: () => boolean): Promise<{ code: number; report: object }> {
  const request = capture(core, config.source);
  const selected = connection(core, config.connection);
  const http = context(selected.origin, selected.cookie, Math.min(config.timeout, 10000));
  let client: ExecutionClient | undefined;
  let stop: Stop | null = null;
  let stopAt = 0;
  let submitted = false;
  let cancellationSent = false;
  let reconnects = 0;
  let failure: unknown;
  let result: WorkResult | null = null;
  const started = performance.now();
  const requestStop = (reason: Stop) => { if (!stop) { stop = reason; stopAt = performance.now(); } };
  const onInterrupt = () => requestStop('sigint');
  process.on('SIGINT', onInterrupt);
  const watch = setInterval(() => {
    if (interrupted()) requestStop('sigint');
    if (config.cancelFile && existsSync(config.cancelFile)) requestStop('cancel-file');
    if (performance.now() - started >= config.timeout) requestStop('timeout');
    if (stop && client?.active && !cancellationSent) {
      cancellationSent = true;
      void client.cancel().catch(error => { failure = error; });
    }
    if (stop && performance.now() - stopAt >= 2000) http.close();
  }, 20);
  try {
    if (interrupted()) requestStop('sigint');
    if (config.cancelFile && existsSync(config.cancelFile)) requestStop('cancel-file');
    if (stop) return { code: 130, report: { profile, contractVersion: version, operation: 'run', binding,
      observation: 'not-submitted', stopReason: stop, execution: null, result: null, release: 'not-requested', reconnects } };
    const authenticated = await http.authenticate(core);
    if (authenticated !== selected.sessionId) refuse('connected.session_changed');
    client = new ExecutionClient(selected.sessionId, { core, authenticate: async () => http.authenticate(core),
      transport: new HttpExecutionTransport({ fetchFn: http.fetchFn, timeout: Math.min(config.timeout, 10000) }) });
    if (!await client.initialize() || !isDeepStrictEqual(client.offer, selected.descriptor)) refuse('connected.offer_changed');
    if (!stop && interrupted()) requestStop('sigint');
    if (stop) return { code: stop === 'timeout' ? 1 : 130, report: { profile, contractVersion: version, operation: 'run', binding,
      observation: 'not-submitted', stopReason: stop, execution: null, result: null, release: 'not-requested', reconnects } };
    submitted = true;
    try { result = await client.execute(request); }
    catch (error) { failure = error; }
    // Reauthentication may reconcile the same retained identity exactly once.
    // An unknown submission has no identity and must never enter this branch.
    if (client.execution && !client.uncertainSubmission && (client.suspended || client.releasePending) && (!stop || performance.now() - stopAt < 2000)) {
      reconnects++;
      try { result = await client.resume(); failure = undefined; }
      catch (error) { failure = error; }
    }
    const terminal = client.execution?.state === 'terminal';
    const unknown = client.uncertainSubmission;
    const observation = unknown ? 'submission-unknown' : terminal ? 'terminal' : client.execution ? 'observation-stopped' : 'rejected';
    const outcomes = record(result?.terminalOutcomes) ? result.terminalOutcomes : record(client.result?.terminalOutcomes) ? client.result.terminalOutcomes : undefined;
    const calls = outcomes && Array.isArray(outcomes.calls) ? outcomes.calls : [];
    const cancelled = calls.some(call => record(call) && record(call.outcome) && call.outcome.status === 'cancelled');
    const success = terminal && calls.length === 1 && calls.every(call => record(call) && record(call.outcome) && call.outcome.status === 'returned') && outcomes?.cleanup === null;
    const release = terminal ? client.releasePending ? 'pending' : 'confirmed' : 'not-requested';
    const code = terminal && !client.releasePending ? cancelled && stop !== 'timeout' ? 130 : success ? 0 : 1 : unknown || client.execution ? 1 : 2;
    return { code, report: { profile, contractVersion: version, operation: 'run', binding, observation,
      stopReason: stop, execution: client.execution, result: terminal ? (result ?? client.result) : null, release, reconnects,
      cancellation: { requested: cancellationSent, acknowledged: !!client.execution?.cancelRequested },
      ...(failure ? { error: unknown ? 'connected.submission_unknown' : client.execution ? 'connected.observation_unavailable' : 'connected.request_rejected' } : {}) } };
  } catch (error) {
    if (stop && !submitted) return { code: stop === 'timeout' ? 1 : 130, report: { profile, contractVersion: version, operation: 'run', binding,
      observation: 'not-submitted', stopReason: stop, execution: null, result: null, release: 'not-requested', error: 'connected.observation_unavailable' } };
    if (submitted && client?.uncertainSubmission) return { code: 1, report: { profile, contractVersion: version, operation: 'run', binding,
      observation: 'submission-unknown', execution: null, result: null, release: 'not-requested', stopReason: stop, error: 'connected.submission_unknown' } };
    throw error;
  } finally { clearInterval(watch); process.off('SIGINT', onInterrupt); http.close(); }
}

/** Versioned terminal effect boundary. The caller supplies the existing compiled
 * MoonBit cursor; the native process loads the same installed pure package. */
export async function connectedCommand(raw: unknown, suppliedCore?: Core, interrupted: () => boolean = () => false): Promise<{ code: number; report: object }> {
  try {
    const config = configuration(raw);
    let core = suppliedCore;
    if (!core) {
      await import(new URL('../dist/connected-core.js', import.meta.url).href);
      const factory = (globalThis as typeof globalThis & { __morphirConnectedCore?: () => Core }).__morphirConnectedCore;
      if (!factory) refuse('connected.validation_core_unavailable');
      core = factory();
    }
    return config.operation === 'connect' ? await openConnection(config, core, interrupted) : await runExecution(config, core, interrupted);
  } catch (error) {
    const code = error instanceof Refusal && error.code.startsWith('connected.interrupted_') ? 130 :
      error instanceof Refusal && error.code === 'connected.timeout_before_submission' ? 1 : 2;
    return { code, report: { profile, contractVersion: version, binding, observation: 'refused', error: safeFailure(error) } };
  }
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  if (process.argv[2] !== '--morphir-connected-v1' || !process.argv[3] || process.argv.length !== 4) {
    console.log(JSON.stringify({ profile, contractVersion: version, binding, observation: 'refused', error: 'connected.invalid_command' }));
    process.exitCode = 2;
  } else {
    let output;
    try { output = await connectedCommand(JSON.parse(readBounded(process.argv[3], 4194304))); }
    catch { output = { code: 2, report: { profile, contractVersion: version, binding, observation: 'refused', error: 'connected.invalid_command' } }; }
    console.log(JSON.stringify(output.report));
    process.exitCode = output.code;
  }
}
