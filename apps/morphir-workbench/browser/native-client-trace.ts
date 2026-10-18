import type {
  Adapter,
  Core,
  Json,
  Progress,
  WorkRequest,
  WorkResult,
} from './contracts.ts';
import { isRecord, workbenchError } from '../../../types/data.ts';
import { NativeAdapter } from './native-session.ts';

/** Offline delivery control around the shipped client. Contains no expected results. */
export interface ClientTraceInput {
  evaluation: {
    model: string;
    entry: string;
    inputs: { format: 'json' | 'ion-text'; source: string };
  };
  inspectionSuccess: boolean;
  checkSource: string;
  invocations: {
    id: string;
    operation: string;
    source: string | null;
    held: boolean;
  }[];
  actions: ClientAction[];
}
type Launch = 'initialize' | 'evaluate' | 'resume' | 'cancel' | 'choose';
export type ClientAction =
  | { op: Launch; id: string }
  | { op: 'open'; id: string; project: string }
  | { op: 'deliver'; call: string }
  | { op: 'set-check'; source: string }
  | { op: 'poll' | 'dispose' };
interface TraceError {
  native: boolean;
  code: string | null;
  effect: string | null;
  submissionUnknown: boolean;
  executionTransport: boolean;
}
interface TraceResult {
  success: boolean;
  operation: string | null;
  cancelled: boolean | null;
  typed: string | null;
  terminalOutcomes: string | null;
  artifact: string | null;
}
interface Attempt {
  id: string;
  status: 'pending' | 'returned' | 'rejected';
  error: TraceError | null;
  result: TraceResult | null;
}

const fail = (): never => {
  throw new Error('Invalid native client fixture infrastructure.');
};
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (
    !isRecord(value) ||
    Object.keys(value).sort().join(',') !== [...keys].sort().join(',')
  )
    return fail();
  return value;
}
function text(value: unknown, max: number, token = false): string {
  if (
    typeof value !== 'string' ||
    [...value].length > max ||
    (token && !/^[A-Za-z0-9_.-]{1,128}$/.test(value))
  )
    return fail();
  return value;
}
export function admitClientTrace(value: unknown): ClientTraceInput {
  const root = object(value, [
    'evaluation',
    'inspectionSuccess',
    'invocations',
    'actions',
    'checkSource',
  ]);
  if (new TextEncoder().encode(JSON.stringify(value)).length > 491520)
    return fail();
  const e = object(root.evaluation, ['model', 'entry', 'inputs']);
  const inputs = object(e.inputs, ['format', 'source']);
  if (inputs.format !== 'json' && inputs.format !== 'ion-text') return fail();
  const source = text(inputs.source, 16384);
  if (inputs.format === 'json') {
    const args: unknown = JSON.parse(source);
    if (!Array.isArray(args)) return fail();
  }
  if (
    typeof root.inspectionSuccess !== 'boolean' ||
    !Array.isArray(root.invocations) ||
    root.invocations.length > 128 ||
    !Array.isArray(root.actions) ||
    root.actions.length > 32
  )
    return fail();
  const calls = new Set<string>();
  const held = new Set<string>();
  const invocations = root.invocations.map((raw) => {
    const call = object(raw, ['id', 'operation', 'source', 'held']);
    const id = text(call.id, 128, true);
    if (calls.has(id) || typeof call.held !== 'boolean') return fail();
    calls.add(id);
    if (call.held) held.add(id);
    const operation = text(call.operation, 128);
    if (
      ![
        'session.open',
        'session.close',
        'execution.submit',
        'execution.query',
        'execution.cancel',
        'execution.release',
        'workspace.choose',
        'workspace.cancel-picker',
        'workspace.revoke',
        'workspace.open',
        'workspace.read',
        'workspace.release',
      ].includes(operation)
    )
      return fail();
    return {
      id,
      operation,
      source: call.source === null ? null : text(call.source, 393216),
      held: call.held,
    };
  });
  const attempts = new Set<string>();
  const delivered = new Set<string>();
  const actions: ClientAction[] = root.actions.map((raw) => {
    if (!isRecord(raw)) return fail();
    const op = raw.op;
    if (op === 'poll' || op === 'dispose') {
      object(raw, ['op']);
      return { op };
    }
    if (op === 'set-check') {
      object(raw, ['op', 'source']);
      return { op, source: text(raw.source, 393216) };
    }
    if (op === 'deliver') {
      object(raw, ['op', 'call']);
      const call = text(raw.call, 128, true);
      if (!held.has(call) || delivered.has(call)) return fail();
      delivered.add(call);
      return { op, call };
    }
    if (
      op !== 'initialize' &&
      op !== 'evaluate' &&
      op !== 'resume' &&
      op !== 'cancel' &&
      op !== 'choose' &&
      op !== 'open'
    )
      return fail();
    object(raw, op === 'open' ? ['op', 'id', 'project'] : ['op', 'id']);
    const id = text(raw.id, 128, true);
    if (attempts.has(id)) return fail();
    attempts.add(id);
    return op === 'open'
      ? { op, id, project: text(raw.project, 128, true) }
      : { op, id };
  });
  return {
    evaluation: {
      model: text(e.model, 262144),
      entry: text(e.entry, 512),
      inputs: { format: inputs.format, source },
    },
    inspectionSuccess: root.inspectionSuccess,
    checkSource: text(root.checkSource, 393216),
    invocations,
    actions,
  };
}

/** Sort object keys only; preserve opaque model, argument and native reply text. */
export function clientTraceJson(value: unknown): string {
  const ordered = (value: unknown): unknown =>
    Array.isArray(value)
      ? value.map(ordered)
      : isRecord(value)
        ? Object.fromEntries(
            Object.keys(value)
              .sort()
              .filter((k) => value[k] !== undefined)
              .map((k) => [k, ordered(value[k])]),
          )
        : value;
  return JSON.stringify(ordered(value));
}
const optionalJson = (value: unknown) =>
  value === undefined || value === null ? null : clientTraceJson(value);
function result(value: WorkResult | void): TraceResult {
  return {
    success: value?.success ?? true,
    operation: value?.operation ?? null,
    cancelled: value?.cancelled ?? null,
    typed: optionalJson(value?.typed),
    terminalOutcomes: optionalJson(value?.terminalOutcomes),
    artifact: optionalJson(value?.originalArtifact),
  };
}
function error(value: unknown): TraceError {
  const e = workbenchError(value);
  const diagnostic = e.diagnostics?.find(
    (value) => isRecord(value) && typeof value.code === 'string',
  );
  return {
    native: e.native === true,
    code:
      e.code ??
      (isRecord(diagnostic) && typeof diagnostic.code === 'string'
        ? diagnostic.code
        : null),
    effect: e.effect ?? null,
    submissionUnknown: e.submissionUnknown === true,
    executionTransport: e.executionTransport === true,
  };
}
/** A task boundary drains promise continuations. No elapsed-time value decides a verdict. */
async function quiescent() {
  await new Promise<void>((resolve) => {
    const channel = new MessageChannel();
    channel.port1.onmessage = () => {
      channel.port1.close();
      channel.port2.close();
      resolve();
    };
    channel.port2.postMessage(null);
  });
}
export async function runNativeClientTrace(raw: unknown, core: Core) {
  const input = admitClientTrace(raw);
  let recording = true;
  let checkSource = input.checkSource;
  let wireCalls = 0;
  const consumed = new Set<string>();
  if (input.evaluation.inputs.format === 'json') {
    const decoded: unknown = JSON.parse(
      core(
        JSON.stringify({
          op: 'decode',
          source: input.evaluation.inputs.source,
        }),
      ),
    );
    if (
      !isRecord(decoded) ||
      decoded.ok !== true ||
      !Array.isArray(decoded.value)
    )
      return fail();
  }
  const requests: string[] = [];
  const progress: string[] = [];
  const publishProgress: Progress = (execution) => {
    const value = clientTraceJson(execution);
    if (recording && progress.at(-1) !== value) progress.push(value);
  };
  const localCalls: string[] = [];
  const attempts = new Map<string, Attempt>();
  const pauses: (() => void)[] = [];
  const held = new Map<string, { deliver: () => void; reject: () => void }>();
  const local: Adapter = {
    async initialize() {
      if (recording)
        localCalls.push(clientTraceJson({ operation: 'initialize' }));
      return {
        success: true,
        catalog: { frontends: [], targets: [] },
        connected: false,
      };
    },
    async execute(request) {
      if (recording) localCalls.push(clientTraceJson(request));
      return { success: input.inspectionSuccess };
    },
    cancel() {},
    dispose() {},
  };
  const adapter = new NativeAdapter(
    local,
    async (name, source) => {
      if (!recording) throw new Error('Fixture cleanup');
      if (++wireCalls > 512) throw new Error('Fixture call budget exceeded');
      const frame: unknown = JSON.parse(source);
      if (!isRecord(frame)) throw new Error('Invalid originating frame');
      // Successful repeated checks are transparent to compatibility. The driver
      // can change their raw reply explicitly at an action boundary.
      if (
        frame.operation === 'session.check' &&
        name === 'app:workbench_native' &&
        Object.keys(frame).sort().join(',') ===
          'contractVersion,operation,profile,sessionId' &&
        frame.profile === 'morphir/workbench/native' &&
        frame.contractVersion === '0.2.0-draft.1' &&
        typeof frame.sessionId === 'string'
      )
        return checkSource;
      requests.push(
        clientTraceJson({
          command: name,
          frame,
        }),
      );
      const call = input.invocations.find(
        (call) => call.operation === frame.operation && !consumed.has(call.id),
      );
      if (!call) throw new Error('Unconfigured native delivery');
      consumed.add(call.id);
      const complete = () =>
        call.source === null
          ? Promise.reject(new Error('Controlled lost reply'))
          : Promise.resolve(call.source);
      if (!call.held) return complete();
      return new Promise<string>((resolve, reject) =>
        held.set(call.id, {
          deliver() {
            held.delete(call.id);
            complete().then(resolve, reject);
          },
          reject() {
            reject(new Error('Fixture cleanup'));
          },
        }),
      );
    },
    60000,
    { core, pause: () => new Promise<void>((resolve) => pauses.push(resolve)) },
  );
  const launch = (id: string, call: () => Promise<WorkResult | void>) => {
    attempts.set(id, { id, status: 'pending', error: null, result: null });
    Promise.resolve()
      .then(call)
      .then(
        (value) =>
          attempts.set(id, {
            id,
            status: 'returned',
            error: null,
            result: result(value),
          }),
        (cause) =>
          attempts.set(id, {
            id,
            status: 'rejected',
            error: error(cause),
            result: null,
          }),
      );
  };
  const snapshot = (
    action: ClientAction['op'],
    delivery: null | 'delivered' | 'unavailable',
  ) => {
    const j = adapter.executions;
    const w = adapter.workspace;
    return {
      action,
      requestCount: requests.length,
      progressCount: progress.length,
      localCount: localCalls.length,
      session: { id: adapter.session.id, disposed: adapter.session.disposed },
      disposed: adapter.disposed,
      executions: j
        ? {
            execution: optionalJson(j.execution),
            active: j.active,
            polling: j.polling,
            releasePending: j.releasePending,
            uncertainSubmission: j.uncertainSubmission,
            suspended: j.suspended,
            cancelOnSubmit: j.cancelOnSubmit,
          }
        : null,
      workspace: w
        ? {
            grant: w.grant,
            projects: clientTraceJson(w.projects),
            pendingRelease: optionalJson(w.pendingRelease),
            choosing: w.choosing,
            opening: w.opening,
            sequence: w.sequence,
            disposed: w.disposed,
          }
        : null,
      attempts: [...attempts.values()].map((a) => ({ ...a })),
      delivery,
    };
  };
  const steps: ReturnType<typeof snapshot>[] = [];
  try {
    for (const action of input.actions) {
      let delivery: null | 'delivered' | 'unavailable' = null;
      switch (action.op) {
        case 'initialize':
          launch(action.id, () => adapter.initialize());
          break;
        case 'evaluate': {
          const e = input.evaluation;
          const request: WorkRequest = {
            operation: 'evaluate',
            executionMode: 'typed',
            source: e.model,
            entry: e.entry,
            ...(e.inputs.format === 'ion-text'
              ? { argumentsIon: e.inputs.source }
              : { arguments: JSON.parse(e.inputs.source) as Json[] }),
          };
          launch(action.id, () => adapter.execute(request, publishProgress));
          break;
        }
        case 'resume':
          launch(action.id, () =>
            adapter.execute(
              { operation: 'resume-execution', source: '' },
              publishProgress,
            ),
          );
          break;
        case 'choose':
          launch(action.id, () =>
            adapter.execute({ operation: 'workspace', source: '' }),
          );
          break;
        case 'open':
          launch(action.id, () =>
            adapter.execute({
              operation: 'project',
              source: '',
              project: action.project,
            }),
          );
          break;
        case 'cancel':
          launch(action.id, async () => {
            await adapter.cancel();
          });
          break;
        case 'dispose':
          adapter.dispose();
          break;
        case 'set-check':
          checkSource = action.source;
          break;
        case 'poll':
          pauses.shift()?.();
          break;
        case 'deliver': {
          const call = held.get(action.call);
          delivery = call ? 'delivered' : 'unavailable';
          call?.deliver();
          break;
        }
      }
      await quiescent();
      steps.push(snapshot(action.op, delivery));
    }
    return {
      steps,
      requests: [...requests],
      progress: [...progress],
      localCalls: [...localCalls],
      consumed: consumed.size,
      remaining: input.invocations.length - consumed.size,
    };
  } finally {
    recording = false;
    adapter.dispose();
    for (const call of held.values()) call.reject();
    for (const pause of pauses) pause();
    await quiescent();
  }
}
