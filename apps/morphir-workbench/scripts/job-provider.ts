import type { Claim, Failure, JobOperation, JobProvider, JobRecord, JobValues, Offer, Outcome, Outcomes, ProviderOptions, Receipt, Submission } from './job-contracts.ts';
import type { Core, CoreReply } from '../browser/contracts.ts';
import { randomUUID } from 'node:crypto';
import { Worker } from 'node:worker_threads';

const version = '0.1.0-draft.1';
const terminalVersion = '0.1.0-draft.5';
const safeCode = (code: unknown) => typeof code === 'string' && /^[a-zA-Z0-9_.-]{1,128}$/.test(code) ? code : 'workbench.provider_failure';
export class JobProviderError extends Error {
  code: string;
  status: number;
  constructor(code: unknown, status = 400) {
    super('The host rejected this job request.'); this.code = safeCode(code); this.status = status;
  }
}
const failure = (code: string, message: string, stage = 'evaluate') => ({ stage, code, message });
const evidence = (outcome: Outcome): Outcomes => ({ contractVersion: terminalVersion, calls: [{ id: 'workbench', outcome }], cleanup: null, extensions: null });
const failed = (code: string, message: string) => evidence({ status: 'failed', failure: failure(code, message) });

export async function createJobProvider({
  bridgeUrl = new URL('../_build/js/release/build/finos/morphir-workbench/job-host/job-host.js', import.meta.url),
  workerUrl = new URL('../_build/js/release/build/finos/morphir-workbench/worker/worker.js', import.meta.url),
  deadlineMs = 30000, factory, workerFactory, decoder,
}: ProviderOptions = {}): Promise<JobProvider> {
  if (!Number.isFinite(deadlineMs) || deadlineMs < 1) throw new Error('A positive worker deadline is required.');
  if (!factory) {
    await import(bridgeUrl.href ?? bridgeUrl);
    factory = globalThis.morphirWorkbenchJobHost;
  }
  decoder ??= globalThis.morphirWorkbenchDecode;
  if (typeof factory !== 'function') throw new Error('Build the private Workbench job host first.');
  const spawnWorker = workerFactory ?? (() => new Worker(new URL('./job-worker.ts', import.meta.url), {
    workerData: { module: workerUrl.href ?? String(workerUrl) }, resourceLimits: { maxOldGenerationSizeMb: 128 },
  }));
  let owner: string | null = null, offer: Offer | null = null, handler: Core | null = null, active = 0, closed = false;
  const records = new Map<string, JobRecord>(); const queue: JobRecord[] = [];
  const command = <T,>(value: unknown): T => {
    let reply: CoreReply<T>;
    try { reply = JSON.parse(handler!(JSON.stringify(value))); }
    catch { throw new JobProviderError('workbench.provider_failure', 503); }
    if (!reply?.ok) {
      const code = safeCode(reply?.code);
      const status = ['workbench.host_capacity', 'workbench.host_already_claimed', 'workbench.host_not_terminal'].includes(code) ? 409 : ['workbench.host_unknown_job', 'workbench.host_cancel_unavailable'].includes(code) ? 404 : /limit|budget/.test(code) ? 413 : 400;
      throw new JobProviderError(code, status);
    }
    return reply.value;
  };
  const bind = (sessionId: string) => {
    if (closed) throw new JobProviderError('workbench.provider_closed', 503);
    if (owner !== null && owner !== sessionId) throw new JobProviderError('workbench.session_changed', 409);
    if (owner === null) {
      offer = { profile: 'morphir/workbench/jobs', contractVersion: version, hostId: randomUUID(), sessionId,
        providerId: 'moonbit-scheme', operations: ['query', 'cancel'] };
      handler = factory!(JSON.stringify(offer));
      if (typeof handler !== 'function') throw new JobProviderError('workbench.provider_failure', 503);
      owner = sessionId;
    }
  };
  const complete = (record: JobRecord, outcomes: Outcomes) => {
    try { command({ op: 'complete', identity: record.identity, outcomes }); }
    catch {
      try { command({ op: 'complete', identity: record.identity,
        outcomes: failed('workbench.worker_outcomes', 'The worker produced invalid terminal evidence.') }); }
      catch (error) { record.failure = error; }
    }
    record.done = !record.failure;
    record.captured = null;
  };
  const stop = (record: JobRecord, reason: string) => {
    if (!record.stopReason) record.stopReason = reason;
    if (!record.stopping) record.stopping = Promise.resolve().then(() => record.worker!.terminate());
    // A failed termination is not evidence that execution stopped.
    record.stopping.catch(() => {});
    return record.stopping;
  };
  const finish = async (record: JobRecord, exitCode: number) => {
    if (record.finished) return;
    record.finished = true;
    clearTimeout(record.timer);
    let cleanup = null;
    if (record.stopping) {
      try { await record.stopping; }
      catch { cleanup = failure('workbench.worker_cleanup', 'The worker termination operation failed.', 'cleanup'); }
    }
    let outcomes = record.captured;
    if (!outcomes) {
      if (record.stopReason === 'cancel' || record.stopReason === 'close') outcomes = evidence({ status: 'cancelled' });
      else if (record.stopReason === 'deadline') outcomes = failed('workbench.worker_deadline', 'The host worker deadline expired.');
      else outcomes = failed(exitCode === 0 ? 'workbench.worker_result' : 'workbench.worker_crash', 'The worker did not return terminal evidence.');
    } else if (exitCode !== 0 && (!record.stopReason || record.stopReason === 'crash')) cleanup = failure('workbench.worker_cleanup', 'The worker exited unexpectedly after returning a result.', 'cleanup');
    if (cleanup) outcomes = { ...outcomes, cleanup };
    complete(record, outcomes);
    record.worker = null;
    active--;
    drain();
  };
  const start = (record: JobRecord) => {
    let request: Claim;
    try { request = command<Claim>({ op: 'claim', identity: record.identity }); }
    catch (error) { record.failure = error; return; }
    active++;
    try {
      record.worker = spawnWorker();
      record.exited = new Promise<void>(resolve => record.worker!.once('exit', code => { resolve(); void finish(record, code); }));
      record.worker.on('message', message => {
        if (message?.id === 1 && message?.result?.terminalOutcomes && !record.captured) record.captured = structuredClone(message.result.terminalOutcomes);
      });
      record.worker.on('error', () => { void stop(record, 'crash'); });
      record.timer = setTimeout(() => { void stop(record, 'deadline'); }, deadlineMs);
      record.timer.unref?.();
      record.worker.postMessage({ id: 1, request });
    } catch {
      if (record.worker) void stop(record, 'crash');
      else { active--; complete(record, failed('workbench.worker_start', 'The host could not start an isolated worker.')); }
    }
  };
  function drain() {
    while (!closed && active < 2 && queue.length) {
      const record = queue.shift()!;
      if (!record.done) start(record);
    }
  }
  return {
    decode(source: string) {
      if (typeof decoder !== 'function') throw new JobProviderError('workbench.host_unavailable', 503);
      let reply;
      try { reply = JSON.parse(decoder(source)); } catch { throw new JobProviderError('workbench.host_unavailable', 503); }
      if (!reply?.ok) throw new JobProviderError('workbench.host_unavailable', 503);
      return reply.value;
    },
    async session(sessionId: string) { bind(sessionId); return { profile: 'morphir/workbench/host', contractVersion: version, offer: structuredClone(offer!) }; },
    async command<K extends JobOperation>(op: K, body: string, sessionId: string): Promise<JobValues[K]> {
      bind(sessionId);
      const value = command<Submission & Receipt & { released: boolean }>({ op, body });
      if (op === 'submit') {
        const record: JobRecord = { identity: structuredClone(value.identity), done: false, worker: null };
        records.set(value.identity.jobId, record); queue.push(record); queueMicrotask(drain);
      } else if (op === 'cancel') {
        const record = records.get(value.identity.jobId);
        if (record && !record.done && value.state !== 'terminal') {
          if (record.worker) void stop(record, 'cancel');
          else {
            const index = queue.indexOf(record); if (index !== -1) queue.splice(index, 1);
            queueMicrotask(() => complete(record, evidence({ status: 'cancelled' })));
          }
        }
      } else if (op === 'release') {
        // The core admits release only for terminal jobs.
        const identity = JSON.parse(body).identity;
        records.delete(identity.jobId);
      }
      return value as JobValues[K];
    },
    async close() {
      closed = true;
      for (const record of queue.splice(0)) complete(record, evidence({ status: 'cancelled' }));
      const running = [...records.values()].filter(record => record.worker);
      try { await Promise.all(running.map(async record => { await stop(record, 'close'); await record.exited; })); }
      catch { throw new JobProviderError('workbench.worker_cleanup', 503); }
    },
  };
}
