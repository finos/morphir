import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { once } from 'node:events';
import { setTimeout as pause } from 'node:timers/promises';
import { Worker } from 'node:worker_threads';
import type { Core } from '../browser/contracts.ts';
import type { ExecutionOperation, ExecutionValues, Identity, Receipt, SchemeExecutionPlan, SchemeSubmission } from './execution-contracts.ts';
import { isRecord, type Json } from '../../../types/data.ts';
import { createExecutionProvider } from './execution-provider.ts';
import { createWorkbenchServer } from './server.ts';

type TraceOperation = ExecutionOperation | 'session' | 'wait';
interface TraceRequest { operation: TraceOperation; status: number | null; code: string | null; execution: number | null; }
interface TraceExecution { plan: SchemeExecutionPlan; receipt: Receipt; released: boolean; }
interface TraceResult {
  requests: TraceRequest[]; executions: TraceExecution[];
  workers: { started: number; exited: number; policies: SchemeExecutionPlan['admission']['policy'][] };
  failure: { stage: 'fixture' | 'projection'; code: string } | null;
}
interface TraceCore { factory: (source: string) => Core; decoder: Core; workerUrl: URL; }

function closed(value: Record<string, unknown>, keys: string[]) {
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort(), 'Invalid provider trace shape');
}
async function listen(server: Server) {
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}
async function close(server: Server) {
  server.closeAllConnections();
  if (server.listening) await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}

/** Exercises the real authenticated gateway, owner and isolated Node workers. */
export async function runHttpProviderTrace(input: unknown, core: TraceCore): Promise<Json> {
  assert.ok(isRecord(input)); closed(input, ['submission', 'actions']);
  assert.ok(Buffer.byteLength(JSON.stringify(input), 'utf8') <= 1048576);
  assert.ok(Array.isArray(input.actions) && input.actions.length <= 32);
  let submission: unknown = structuredClone(input.submission);
  let authenticated: string | null = 'session';
  let providerId: string | null = null;
  const observed: TraceResult = { requests: [], executions: [], workers: { started: 0, exited: 0, policies: [] }, failure: null };
  const executions = await createExecutionProvider({ mapping: 'capability-checks', factory: core.factory, decoder: core.decoder,
    workerUrl: core.workerUrl, deadlineMs: 5000, workerFactory: () => {
      const worker = new Worker(new URL('./execution-worker.ts', import.meta.url), { workerData: { module: core.workerUrl.href } });
      observed.workers.started++;
      worker.once('exit', () => { observed.workers.exited++; });
      const send = worker.postMessage.bind(worker);
      worker.postMessage = value => {
        assert.ok(isRecord(value) && isRecord(value.request) && isRecord(value.request.plan)
          && isRecord(value.request.plan.admission));
        const policy = value.request.plan.admission.policy;
        assert.ok(policy === 'strict' || policy === 'permissive');
        observed.workers.policies.push(policy); send(value);
      };
      return worker;
    } });
  let lastEffect: { operation: ExecutionOperation; value: unknown } | null = null;
  const original = executions.command.bind(executions);
  executions.command = async <K extends ExecutionOperation>(operation: K, body: string, sessionId: string): Promise<ExecutionValues[K]> => {
    const value = await original(operation, body, sessionId);
    lastEffect = { operation, value: structuredClone(value) }; return value;
  };
  const upstream = createServer((request, response) => {
    if (request.url !== '/api/session' || request.headers.cookie !== 'morphir_mck=owned' || authenticated === null) {
      response.writeHead(401).end(); return;
    }
    response.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({
      protocolVersion: 1, webSocketPath: '/rpc', sessionId: authenticated, providers: [], initialSources: [],
    }));
  });
  let gateway: ReturnType<typeof createWorkbenchServer> | undefined;
  try {
    const host = await listen(upstream);
    gateway = createWorkbenchServer({ host, executions });
    const origin = await listen(gateway);
    const headers = { Cookie: 'morphir_mck=owned', Origin: origin, 'Content-Type': 'application/json' };
    const request = async (operation: Exclude<TraceOperation, 'wait'>, execution: number | null, body?: unknown, record = true, discard = false) => {
      lastEffect = null;
      const response = await fetch(`${origin}/api/workbench/${operation}`, {
        method: operation === 'session' ? 'GET' : 'POST', headers,
        ...(operation === 'session' ? {} : { body: JSON.stringify(body) }),
      });
      // The simulated caller discards the body. The separately installed trusted
      // owner observer records effects; this does not recover a client identity.
      let value: unknown;
      if (discard) {
        await response.body?.cancel();
        const effect = lastEffect as { operation: ExecutionOperation; value: unknown } | null;
        assert.ok(response.ok && effect?.operation === operation);
        value = effect.value;
      } else value = await response.json();
      const code = isRecord(value) && isRecord(value.error) && typeof value.error.code === 'string' ? value.error.code : null;
      if (record) observed.requests.push({ operation, status: discard ? null : response.status, code, execution });
      return { response, value, code };
    };
    for (const raw of input.actions) {
      assert.ok(isRecord(raw) && typeof raw.op === 'string');
      if (raw.op === 'authenticate') {
        closed(raw, ['op', 'sessionId']);
        assert.ok(raw.sessionId === null || typeof raw.sessionId === 'string');
        authenticated = raw.sessionId; continue;
      }
      if (raw.op === 'replace-submission') {
        closed(raw, ['op', 'submission']);
        submission = structuredClone(raw.submission); continue;
      }
      if (raw.op === 'shutdown') { closed(raw, ['op']); await executions.close(); continue; }
      if (raw.op === 'session') {
        closed(raw, ['op']);
        const result = await request('session', null);
        if (result.response.ok) {
          assert.ok(isRecord(result.value) && isRecord(result.value.offer) && typeof result.value.offer.providerId === 'string');
          providerId ??= result.value.offer.providerId;
        }
        continue;
      }
      if (raw.op === 'submit' || raw.op === 'submit-lost-reply') {
        closed(raw, ['op']);
        const body = isRecord(submission) && submission.providerId === 'provider' && providerId !== null
          ? { ...submission, providerId } : submission;
        const result = await request('submit', null, body, true, raw.op === 'submit-lost-reply');
        if (result.response.ok) {
          const accepted = result.value as SchemeSubmission;
          assert.ok(accepted.plan && accepted.identity && accepted.receipt);
          const index = observed.executions.length;
          observed.requests.at(-1)!.execution = index;
          observed.executions.push({ plan: structuredClone(accepted.plan), receipt: structuredClone(accepted.receipt), released: false });
        }
        continue;
      }
      assert.ok(['wait', 'query', 'cancel', 'release', 'query-lost-reply', 'release-lost-reply'].includes(raw.op));
      closed(raw, ['op', 'execution']); assert.ok(Number.isInteger(raw.execution) && Number(raw.execution) >= 0);
      const index = Number(raw.execution), retained = observed.executions[index]; assert.ok(retained);
      const body = { contractVersion: '0.2.0-draft.1', identity: retained.plan.identity };
      if (raw.op === 'wait') {
        let result;
        for (let attempt = 0; attempt < 600; attempt++) {
          result = await request('query', index, body, false);
          if (!result.response.ok || (isRecord(result.value) && result.value.state === 'terminal')) break;
          await pause(10);
        }
        assert.ok(result);
        if (result.response.ok) {
          assert.ok(isRecord(result.value) && result.value.state === 'terminal', 'Worker did not exit within trace deadline');
          retained.receipt = result.value as unknown as Receipt;
        }
        observed.requests.push({ operation: 'wait', status: result.response.status, code: result.code, execution: index });
      } else {
        const operation = raw.op.replace(/-lost-reply$/, '');
        assert.ok(operation === 'query' || operation === 'cancel' || operation === 'release');
        const result = await request(operation, index, body, true, raw.op.endsWith('-lost-reply'));
        if (result.response.ok) {
          if (operation === 'release') retained.released = true;
          else retained.receipt = result.value as Receipt;
        }
      }
    }
  } finally {
    await executions.close();
    if (gateway) { await close(gateway); await gateway.executionCleanup; }
    await close(upstream);
  }
  return normalize(observed);
}

function normalize(value: TraceResult): Json {
  const fields = ['hostId', 'sessionId', 'providerId', 'executionId', 'snapshotId', 'planId'] as const;
  const names = ['host', 'session', 'provider', 'execution', 'snapshot', 'plan'];
  const roles = new Map<string, Map<string, string>>(fields.map(field => [field, new Map()]));
  function identity(field: typeof fields[number], id: string) {
    if (field === 'sessionId') return id;
    const role = roles.get(field)!;
    if (!role.has(id)) {
      const name = names[fields.indexOf(field)]!;
      role.set(id, ['hostId', 'sessionId', 'providerId'].includes(field) && role.size === 0 ? name : `${name}-${role.size + 1}`);
    }
    return role.get(id)!;
  }
  function project(node: unknown): Json {
    if (Array.isArray(node)) return node.map(project);
    if (isRecord(node)) return Object.fromEntries(Object.entries(node).map(([key, item]) => [key,
      fields.includes(key as keyof Identity) && typeof item === 'string'
        ? identity(key as typeof fields[number], item) : project(item)]));
    assert.ok(node === null || typeof node === 'string' || typeof node === 'number' || typeof node === 'boolean');
    return node;
  }
  return project(value);
}
