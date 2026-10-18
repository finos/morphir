import type { Core, Fetch, Json, Progress, WorkRequest, WorkResult } from './contracts.ts';
import { ExecutionClient } from './execution-session.ts';
import { isRecord, workbenchError } from '../../../types/data.ts';

type Evaluation = { model: string; entry: string; runtime: string; providerId: string; inputs: { format: 'json' | 'ion-text'; source: string }; admission?: Json };
type Action = { op: 'initialize' | 'evaluate' | 'resume' | 'cancel' | 'release'; id: string }
  | { op: 'deliver'; call: string } | { op: 'mutate'; evaluation: Evaluation } | { op: 'authenticate'; sessionId: string | null };
interface Invocation { id: string; path: string; status: number; source: string | null; held: boolean }
interface Input { sessionId: string; evaluation: Evaluation; invocations: Invocation[]; actions: Action[] }
interface Attempt { id: string; status: 'pending' | 'returned' | 'rejected'; success: boolean | null; submissionUnknown: boolean; executionTransport: boolean }
const fail = (): never => { throw new Error('Invalid HTTP client fixture infrastructure.'); };
const closed = (value: unknown, keys: string[]) => {
  if (!isRecord(value) || Object.keys(value).sort().join(',') !== [...keys].sort().join(',')) return fail();
  return value;
};
function text(value: unknown, maximum: number, minimum = 1): string {
  if (typeof value !== 'string') return fail();
  const length = [...value].length;
  return length >= minimum && length <= maximum ? value : fail();
}
function evaluation(raw: unknown): Evaluation {
  const hasPolicy = isRecord(raw) && Object.hasOwn(raw, 'admission');
  const e = closed(raw, ['model', 'entry', 'runtime', 'providerId', 'inputs', ...(hasPolicy ? ['admission'] : [])]);
  const inputs = closed(e.inputs, ['format', 'source']);
  if ((inputs.format !== 'json' && inputs.format !== 'ion-text') || e.runtime !== 'scheme') return fail();
  return { model: text(e.model, 1048576), entry: text(e.entry, 1024), runtime: text(e.runtime, 128), providerId: text(e.providerId, 128),
    inputs: { format: inputs.format, source: text(inputs.source, 1048576, 0) }, ...(hasPolicy ? { admission: e.admission as Json } : {}) };
}
function admit(raw: unknown): Input {
  const root = closed(raw, ['sessionId', 'evaluation', 'invocations', 'actions']);
  if (new TextEncoder().encode(JSON.stringify(raw)).length > 1048576 || !Array.isArray(root.invocations) || root.invocations.length > 128 || !Array.isArray(root.actions) || root.actions.length > 32) return fail();
  const ids = new Set<string>();
  const invocations = root.invocations.map(raw => {
    const call = closed(raw, ['id', 'path', 'status', 'source', 'held']);
    const id = text(call.id, 128);
    if (ids.has(id) || !['session', 'submit', 'query', 'cancel', 'release'].includes(String(call.path)) || (typeof call.status !== 'number' || ![200, 400, 401, 403, 404, 409, 413, 503].includes(call.status)) || typeof call.held !== 'boolean') return fail();
    ids.add(id);
    return { id, path: String(call.path), status: Number(call.status), source: call.source === null ? null : text(call.source, 393216, 0), held: call.held };
  });
  const attempts = new Set<string>();
  const actions: Action[] = root.actions.map(raw => {
    if (!isRecord(raw)) return fail();
    if (raw.op === 'deliver') { const a = closed(raw, ['op', 'call']); return { op: 'deliver', call: text(a.call, 128) }; }
    if (raw.op === 'mutate') { const a = closed(raw, ['op', 'evaluation']); return { op: 'mutate', evaluation: evaluation(a.evaluation) }; }
    if (raw.op === 'authenticate') { const a = closed(raw, ['op', 'sessionId']); return { op: 'authenticate', sessionId: a.sessionId === null ? null : text(a.sessionId, 128) }; }
    if (!['initialize', 'evaluate', 'resume', 'cancel', 'release'].includes(String(raw.op))) return fail();
    const a = closed(raw, ['op', 'id']), id = text(a.id, 128);
    if (attempts.has(id)) return fail();
    attempts.add(id);
    return { op: raw.op, id } as Action;
  });
  return { sessionId: text(root.sessionId, 128), evaluation: evaluation(root.evaluation), invocations, actions };
}
/** A task boundary drains promise continuations without elapsed-time verdicts. */
async function quiescent() {
  await new Promise<void>(resolve => {
    const channel = new MessageChannel();
    channel.port1.onmessage = () => { channel.port1.close(); channel.port2.close(); resolve(); };
    channel.port2.postMessage(null);
  });
}
function request(e: Evaluation, core: Core): WorkRequest {
  // JSON arguments cross the raw source boundary before they become a typed
  // WorkRequest. Do not let ordinary JSON.parse silently coalesce duplicate keys.
  if (e.inputs.format === 'json') {
    const decoded: unknown = JSON.parse(core(JSON.stringify({ op: 'decode', source: e.inputs.source })));
    if (!isRecord(decoded) || decoded.ok !== true || !Array.isArray(decoded.value)) throw new Error('Invalid JSON argument source.');
  }
  return { operation: 'evaluate', executionMode: 'capability', source: e.model, entry: e.entry,
    ...(e.inputs.format === 'json' ? { arguments: JSON.parse(e.inputs.source) as Json } : { argumentsIon: e.inputs.source }),
    ...(e.admission === undefined ? {} : { admission: structuredClone(e.admission) }) };
}

type Draft = { kind: 'valid'; request: WorkRequest } | { kind: 'invalid'; cause: unknown };
function draft(e: Evaluation, core: Core): Draft {
  try { return { kind: 'valid', request: request(e, core) }; }
  catch (cause) { return { kind: 'invalid', cause }; }
}

/** Parent-owned HTTP deliveries around the production client. Contains no expected results. */
export async function runHttpPolicyClientTrace(raw: unknown, core: Core) {
  const input = admit(raw), attempts = new Map<string, Attempt>();
  const consumed = new Set<string>(), held = new Map<string, { deliver(): void; reject(): void }>();
  const requests: { method: string; path: string; status: number | null; body: unknown }[] = [], acceptedPlans: Json[] = [];
  let recording = true, authenticated: string | null = input.sessionId;
  let currentEvaluation = input.evaluation;
  let current = draft(currentEvaluation, core);
  const fetchFn: Fetch = async (url, options) => {
    if (!recording || requests.length >= 128) throw new Error('Fixture request budget exceeded');
    const path = url.slice('/api/workbench/'.length);
    const observed = { method: options?.method ?? 'GET', path: url, status: null as number | null, body: options?.body === undefined ? null : JSON.parse(options.body) };
    requests.push(observed);
    const call = input.invocations.find(call => call.path === path && !consumed.has(call.id));
    if (!call) throw new Error('Unconfigured HTTP delivery');
    consumed.add(call.id);
    const complete = () => {
      if (call.source === null) return Promise.reject(new Error('Controlled lost HTTP reply'));
      observed.status = call.status;
      return Promise.resolve(new Response(call.source, { status: call.status }));
    };
    if (!call.held) return complete();
    return new Promise<Response>((resolve, reject) => held.set(call.id, {
      deliver() { held.delete(call.id); complete().then(resolve, reject); },
      reject() { reject(new Error('Fixture cleanup')); },
    }));
  };
  const client = new ExecutionClient(input.sessionId, { core, fetchFn, timeout: 60000,
    authenticate: async () => { if (authenticated === null) throw new Error('Controlled authentication loss'); return authenticated; },
    pause: async () => {}, onAcceptedPlan: plan => { if (recording) acceptedPlans.push(plan); } });
  const progress: Progress = () => {};
  const launch = (id: string, operation: () => Promise<boolean | WorkResult | void>) => {
    attempts.set(id, { id, status: 'pending', success: null, submissionUnknown: false, executionTransport: false });
    Promise.resolve().then(operation).then(value => {
      attempts.set(id, { id, status: 'returned', success: typeof value === 'boolean' ? value : value?.success ?? null, submissionUnknown: false, executionTransport: false });
    }, cause => {
      const error = workbenchError(cause);
      attempts.set(id, { id, status: 'rejected', success: null, submissionUnknown: error.submissionUnknown === true, executionTransport: error.executionTransport === true });
    });
  };
  const snapshot = (action: Action['op']) => ({ action, active: client.active, polling: client.polling, releasePending: client.releasePending,
    uncertainSubmission: client.uncertainSubmission, suspended: client.suspended,
    execution: client.execution === null ? null : { state: client.execution.state, sequence: client.execution.sequence, cancelRequested: client.execution.cancelRequested, connected: client.execution.connected },
    attempts: [...attempts.values()].map(value => ({ ...value })) });
  const steps: ReturnType<typeof snapshot>[] = [];
  try {
    for (const action of input.actions) {
      switch (action.op) {
        case 'initialize': launch(action.id, () => client.initialize()); break;
        case 'evaluate': {
          const offer = client.offer?.offer;
          if (currentEvaluation.runtime !== 'scheme' || (isRecord(offer) && currentEvaluation.providerId !== offer.providerId)) return fail();
          const selected = current;
          launch(action.id, () => {
            if (selected.kind === 'invalid') throw selected.cause;
            return client.execute(selected.request, progress);
          });
          break;
        }
        case 'resume': launch(action.id, () => client.resume(progress)); break;
        case 'cancel': launch(action.id, () => client.cancel()); break;
        case 'release': launch(action.id, () => client.release()); break;
        case 'authenticate': authenticated = action.sessionId; break;
        case 'mutate': {
          currentEvaluation = action.evaluation;
          const next = draft(currentEvaluation, core);
          if (current.kind === 'valid' && next.kind === 'valid') {
            // Mutate the same caller-owned object that an outstanding evaluate
            // received; only the production client may capture it for that run.
            for (const key of Object.keys(current.request)) delete current.request[key as keyof WorkRequest];
            Object.assign(current.request, next.request);
          } else current = next;
          break;
        }
        case 'deliver': held.get(action.call)?.deliver(); break;
      }
      await quiescent();
      steps.push(snapshot(action.op));
    }
    return { steps, requests: structuredClone(requests), acceptedPlans: structuredClone(acceptedPlans) };
  } finally {
    recording = false;
    client.suspended = true;
    for (const delivery of held.values()) delivery.reject();
    await quiescent();
  }
}
