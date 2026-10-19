import type { Adapter, Core, FetchInit, Execution, Json, ProjectPayload, WorkRequest, WorkerPort, WorkResult } from './contracts.ts';
import { workbenchError } from '../../../types/data.ts';
import { malformed } from '../../../tests/helpers.ts';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LocalAdapter, RpcClient, ConnectedAdapter, chooseVersion, validateManifest } from './transport.ts';

test('tree path overflow refuses before request cloning or worker creation', async () => {
  const prefix = `${'p'.repeat(240)}/`.repeat(16);
  const files = Array.from({length: 256}, (_, i) => ({path: prefix + String(i).padStart(240, 'x'), contentBase64: ''}));
  files.push({path: 'x', contentBase64: ''});
  let clones = 0, workers = 0;
  const clone = globalThis.structuredClone;
  globalThis.structuredClone = () => { clones++; throw new Error('must not clone'); };
  try {
    const adapter = new LocalAdapter(() => { workers++; throw new Error('must not create worker'); });
    await assert.rejects(adapter.execute({operation: 'inspect', source: '', sourceTree: files}), /path text budget/);
    assert.equal(clones, 0);
    assert.equal(workers, 0);
  } finally { globalThis.structuredClone = clone; }
});

const source = { providerId: 'workspace', locator: 'workspace:demo', displayName: 'Demo' };
const manifest = {
  protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'test-session', initialSources: [source],
  providers: [{ id: 'workspace', status: 'available', capabilities: [
    'workspace/open', 'project-model/open', 'playground/catalog', 'playground/compile', 'playground/generate',
  ].map(name => ({ name: `morphir/${name}`, version: '1' })) }],
};
const catalog = {
  frontends: [{ languageId: 'scheme', displayName: 'Scheme', fileExtensions: ['.scm'], irVersions: ['3', '4.0.0'], compile: true }],
  targets: [{ target: 'scala', irVersions: ['4'], generate: true }],
};

class Socket extends EventTarget {
  readyState = 1;
  sent: { id: number; method: string; params: unknown }[] = [];
  send(message: string) { this.sent.push(JSON.parse(message)); }
  close() { this.readyState = 3; this.dispatchEvent(new Event('close')); }
  reply(data: unknown) { this.dispatchEvent(new MessageEvent('message', { data: JSON.stringify(data) })); }
}

test('RPC correlates out-of-order replies and never reuses a request ID', async () => {
  const socket = new Socket();
  const rpc = new RpcClient(socket, 1000);
  const first = rpc.call('morphir.playground.catalog', {});
  const second = rpc.call('morphir.workspace.open', { source });
  assert.deepEqual(socket.sent[0], { jsonrpc: '2.0', id: 1, method: 'morphir.playground.catalog', params: {} });
  socket.reply({ jsonrpc: '2.0', method: 'morphir.workspace.event', params: { kind: 'snapshot' } });
  socket.reply({ jsonrpc: '2.0', id: 2, result: 'second' });
  socket.reply({ jsonrpc: '2.0', id: 1, result: 'first' });
  assert.equal(await first, 'first'); assert.equal(await second, 'second');
  const third = rpc.call('morphir.playground.catalog', {});
  assert.equal(socket.sent[2]!.id, 3);
  socket.reply({ jsonrpc: '2.0', id: 3, error: { code: -32013, message: 'Capability unavailable' } });
  await assert.rejects(third, /Capability unavailable/);
  rpc.dispose();
});

test('disconnect rejects pending RPC and later calls', async () => {
  const socket = new Socket(); const rpc = new RpcClient(socket);
  const pending = rpc.call('morphir.playground.catalog', {});
  socket.close();
  await assert.rejects(pending, /disconnected/);
  await assert.rejects(rpc.call('morphir.playground.catalog', {}), /not connected/);
});

test('invalid manifest and incompatible IR are refused before a request', () => {
  assert.throws(() => validateManifest({ ...manifest, protocolVersion: 2 }), /protocol v1/);
  assert.throws(() => validateManifest({ ...manifest, initialSources: [{ ...source, providerId: 'unknown' }] }), /unknown provider/);
  assert.equal(chooseVersion(catalog.frontends[0]!, catalog.targets[0]), '4.0.0');
  assert.equal(chooseVersion(catalog.frontends[0]!, { irVersions: ['3.0.0'] }), '3');
  assert.throws(() => chooseVersion(catalog.frontends[0]!, { irVersions: ['2'] }), /compatible IR/);
});

test('connected adapter emits upstream v1 initialize, source, compile and generate shapes', async () => {
  const calls: { method: string; params: Record<string,unknown> }[] = [];
  const ir = { formatVersion: 4, distribution: {} };
  const rpc = { async call(method: string, params: Record<string,unknown>) {
    calls.push({ method, params });
    if (method.endsWith('initialize')) return {};
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('workspace.open')) return { snapshot: { projects: [{ id: 'p1', name: 'Pricing' }] } };
    if (method.endsWith('compile')) return { success: true, ir, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('generate')) return { success: true, artifacts: [{ path: 'Main.scala', content: 'val answer = 42', binary: false }] };
    if (method.endsWith('project-model.open')) return { content: JSON.stringify(ir) };
    throw new Error(method);
  } };
  const inspected: WorkRequest[] = [];
  const adapter = new ConnectedAdapter(rpc, manifest, { async execute(request) { inspected.push(request); return { success: true, ir, nodes: [] }; }, cancel() {} });
  const initialized = await adapter.initialize();
  assert.equal(initialized.connected, true);
  assert.deepEqual(calls[0], { method: 'morphir.session.initialize', params: { protocolVersion: 1, sessionId: 'test-session' } });
  assert.deepEqual(calls[2], { method: 'morphir.workspace.open', params: { source } });
  const result = await adapter.execute({ operation: 'compile', source: '(+ 20 22)', languageId: 'scheme', target: 'scala' });
  assert.deepEqual(calls[3], { method: 'morphir.playground.compile', params: {
    languageId: 'scheme', documents: [{ uri: 'file:///main.scm', languageId: 'scheme', version: 1, text: '(+ 20 22)' }],
    package: { name: 'user' }, irVersion: '4.0.0', options: {},
  } });
  assert.deepEqual(calls[4], { method: 'morphir.playground.generate', params: { ir, irVersion: '4.0.0', target: 'scala', options: {} } });
  assert.match(result.generated!, /val answer = 42/);
  await adapter.execute({ operation: 'project', project: initialized.projects[0]!.id });
  assert.deepEqual(calls[5], { method: 'morphir.project-model.open', params: { source, projectId: 'p1' } });
  assert.deepEqual(inspected[0], { operation: 'inspect', source: JSON.stringify(ir) });
  await assert.rejects(adapter.execute({ operation: 'run' }), /does not offer evaluation/);
});

test('connected IR export retains the negotiated host version after local migration', async () => {
  const ir = { formatVersion: 3, distribution: {} };
  const migrated = { formatVersion: 4, distribution: {} };
  let generatedIr;
  const adapter = new ConnectedAdapter({ async call(method: string, params: Record<string,unknown>) {
    if (method.endsWith('catalog')) return {
      frontends: [{ ...catalog.frontends[0], irVersions: ['3'] }],
      targets: [{ ...catalog.targets[0], irVersions: ['3'] }],
    };
    if (method.endsWith('compile')) return { success: true, ir, irVersion: '3', diagnostics: [] };
    if (method.endsWith('generate')) {
      generatedIr = params.ir;
      return { success: true, artifacts: [] };
    }
    return {};
  } }, { ...manifest, initialSources: [] }, {
    async execute() { return { success: true, ir: migrated, irSource: JSON.stringify(migrated), nodes: [] }; },
    cancel() {},
  });
  await adapter.initialize();
  const result = await adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 20 22)', target: 'scala' });
  assert.equal(result.ir, ir);
  assert.deepEqual(JSON.parse(result.irSource!), ir);
  assert.equal(generatedIr, ir);
});

test('providers without compile capability leave compilation unavailable', async () => {
  const adapter = new ConnectedAdapter({ async call() { return catalog; } }, {
    ...manifest, initialSources: [], providers: [{ id: 'catalog-only', status: 'available', capabilities: [{ name: 'morphir/playground/catalog', version: '1' }] }],
  }, { execute: async () => ({success: false}), cancel() {} });
  assert.equal((await adapter.initialize()).catalog.frontends.length, 0);
  await assert.rejects(adapter.execute({ operation: 'compile', languageId: 'scheme' }), /unavailable/);
});

test('worker cancellation terminates active execution and a new execution gets a fresh worker', async () => {
  const workers: (WorkerPort & { terminated: boolean; message?: { id: number; request: WorkRequest } })[] = [];
  const adapter = new LocalAdapter(() => {
    const worker: WorkerPort & { terminated: boolean; message?: { id: number; request: WorkRequest } } = { terminated: false, terminate() { this.terminated = true; }, postMessage(message) { this.message = message; } };
    workers.push(worker); return worker;
  });
  const first = adapter.execute({ operation: 'run', source: '(+ 1 2)' });
  adapter.cancel();
  await assert.rejects(first, /Cancelled/);
  assert.equal(workers[0]!.terminated, true);
  const second = adapter.execute({ operation: 'run', source: '(+ 20 22)' });
  workers[1]!.onmessage!({ data: { id: workers[1]!.message!.id, result: { success: true, value: '42' } } });
  assert.deepEqual(await second, { success: true, value: '42' });
  assert.equal(workers[1]!.terminated, true);
});

test('worker execution deadline ends the execution', async () => {
  let terminated = false;
  const adapter = new LocalAdapter(() => ({ postMessage() {}, terminate() { terminated = true; } }), 5);
  await assert.rejects(adapter.execute({ operation: 'run', source: '(+ 1 2)' }), /timed out/);
  assert.equal(terminated, true);
});

test('discarding a compile does not start inspection or generation after its reply', async () => {
  let resolveCompile;
  const calls: string[] = [];
  let inspections = 0;
  const adapter = new ConnectedAdapter({ async call(method: string) {
    calls.push(method);
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('compile')) return new Promise(resolve => { resolveCompile = resolve; });
    return {};
  } }, { ...manifest, initialSources: [] }, { cancel() {}, async execute() { ++inspections; return { success: true }; } });
  await adapter.initialize();
  const compiling = adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 1 2)', target: 'scala' });
  adapter.cancel();
  resolveCompile!({ success: true, ir: { formatVersion: 4 }, irVersion: '4.0.0', diagnostics: [] });
  await assert.rejects(compiling, /Discarded/);
  assert.equal(inspections, 0);
  assert.equal(calls.some(method => method.endsWith('generate')), false);
});

test('generator failure keeps successfully compiled IR available to inspect', async () => {
  const ir = { formatVersion: 4 };
  const adapter = new ConnectedAdapter({ async call(method: string) {
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('compile')) return { success: true, ir, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('generate')) throw new Error('Generator disconnected');
    return {};
  } }, { ...manifest, initialSources: [] }, { cancel() {}, async execute() { return { success: true, nodes: [] }; } });
  await adapter.initialize();
  const result = await adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 1 2)', target: 'scala' });
  assert.equal(result.success, true); assert.deepEqual(result.ir, ir);
  assert.equal(result.generationMessage, 'Generator disconnected');
});

test('malformed generated files preserve compiled IR and report the host envelope error', async () => {
  for (const artifacts of [null, {}, [{path:'Main.scala',content:'source'}], [null]]) {
    const ir = {formatVersion:4};
    const adapter = new ConnectedAdapter({ async call(method: string) {
      if (method.endsWith('catalog')) return catalog;
      if (method.endsWith('compile')) return {success:true,ir,irVersion:'4.0.0',diagnostics:[]};
      if (method.endsWith('generate')) return {success:true,artifacts};
      return {};
    } }, {...manifest,initialSources:[]}, { cancel() {},async execute() {return {success:true,nodes:[]};}});
    await adapter.initialize();
    const result = await adapter.execute({operation:'compile',languageId:'scheme',source:'42',target:'scala'});
    assert.equal(result.success,true); assert.deepEqual(result.ir,ir);
    assert.match(result.generationMessage!,/invalid generated file envelope/);
    assert.equal(result.artifacts,undefined);
  }
});

test('oversized evaluation arguments are rejected before starting a worker', async () => {
  let workers = 0;
  const adapter = new LocalAdapter(() => { ++workers; throw new Error('Must not start'); });
  await assert.rejects(adapter.execute({ operation: 'evaluate', source: '{}', arguments: ['x'.repeat(16 * 1024 * 1024)] }), /arguments must be smaller/);
  assert.equal(workers, 0);
});

test('inspection rejection preserves host compilation and continues generation', async () => {
  const ir = { formatVersion: 4, padding: 'x'.repeat(16 * 1024 * 1024) };
  const calls: { method: string; params: Record<string,unknown> }[] = [];
  let workers = 0;
  const local = new LocalAdapter(() => { ++workers; throw new Error('Oversized inspection must not start'); });
  const adapter = new ConnectedAdapter({ async call(method: string, params: Record<string,unknown>) {
    calls.push({ method, params });
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('compile')) return { success: true, ir, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('generate')) return { success: true, artifacts: [{ path: 'Main.scala', content: 'val answer = 42', binary: false }] };
    return {};
  } }, { ...manifest, initialSources: [] }, local);
  await adapter.initialize();
  const result = await adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 20 22)', target: 'scala' });
  assert.equal(result.success, true);
  assert.equal(result.ir, ir);
  assert.match(result.inspectionMessage!, /16 MiB/);
  assert.match(result.generated!, /val answer = 42/);
  assert.equal(workers, 0);
  assert.equal(calls.find(call => call.method.endsWith('generate'))!.params.ir, ir);
});

test('discard during rejected inspection never starts host generation', async () => {
  let started: () => void = () => {};
  let rejectInspection: (cause: unknown) => void = () => {};
  let generated = false;
  const inspecting = new Promise<void>(resolve => { started = resolve; });
  const local = {
    execute() { return new Promise<WorkResult>((_, reject) => { rejectInspection = reject; started(); }); },
    cancel() { rejectInspection(new Error('Cancelled')); },
  };
  const adapter = new ConnectedAdapter({ async call(method: string) {
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('compile')) return { success: true, ir: {}, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('generate')) { generated = true; return {}; }
    return {};
  } }, { ...manifest, initialSources: [] }, local);
  await adapter.initialize();
  const compiling = adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 20 22)', target: 'scala' });
  await inspecting;
  adapter.cancel();
  await assert.rejects(compiling, /Discarded/);
  assert.equal(generated, false);
});


test('oversized Ion input is rejected before starting a worker', async () => {
  let workers = 0;
  const adapter = new LocalAdapter(() => { ++workers; throw new Error('Must not start'); });
  await assert.rejects(adapter.execute({ operation: 'evaluate', source: '{}', argumentsIon: 'x'.repeat(16 * 1024 * 1024 + 1) }), /Ion arguments must be smaller/);
  assert.equal(workers, 0);
});


test('invalid v1 workspace envelope is visible without hiding compiler capabilities', async () => {
  for (const opened of [{projects:[]}, {snapshot:{}}, {snapshot:{projects:[{name:'Missing identity'}]}}]) {
    const adapter = new ConnectedAdapter({async call(method: string) {
      if (method.endsWith('catalog')) return catalog;
      if (method.endsWith('workspace.open')) return opened;
      return {};
    }}, manifest, { cancel() {}, async execute() { throw new Error('Unexpected local execution'); },});
    const initialized = await adapter.initialize();
    assert.match(initialized.message, /Invalid workspace snapshot/);
    assert.deepEqual(initialized.projects, []);
    assert.ok(initialized.catalog.frontends.length > 0);
  }
});

test('connected v1 binary extensions cannot enable private local downloads', async () => {
  const adapter = new ConnectedAdapter({async call(method: string) {
    if(method.endsWith('catalog'))return catalog;
    if(method.endsWith('compile'))return {success:true,ir:{formatVersion:4},irVersion:'4.0.0'};
    if(method.endsWith('generate'))return {success:true,artifacts:[{path:'symbols.10n',content:'AA==',binary:true,encoding:'base64'}]};
    return {};
  }}, {...manifest,initialSources:[]}, { cancel() {},async execute(){return {success:true,nodes:[]};}});
  await adapter.initialize();
  const result=await adapter.execute({operation:'compile',languageId:'scheme',source:'42',target:'scala'});
  assert.deepEqual(result.artifacts,[{path:'symbols.10n',content:'AA==',binary:true}]);
});

test('connected compile failure keeps the host diagnostics with their locations', async () => {
  const diagnostic = { severity: 'error', code: 'E001', message: 'Type mismatch',
    location: { uri: 'file:///main.gleam', range: { start: { line: 0, character: 4 }, end: { line: 0, character: 9 } } } };
  const rpc = { async call(method: string) {
    if (method.endsWith('initialize')) return {};
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('workspace.open')) return { snapshot: { projects: [] } };
    if (method.endsWith('compile')) return { success: false, diagnostics: [diagnostic] };
    throw new Error(method);
  } };
  const adapter = new ConnectedAdapter(rpc, manifest, { async execute() { return { success: true }; }, cancel() {} });
  await adapter.initialize();
  await assert.rejects(adapter.execute({ operation: 'compile', source: 'x', languageId: 'scheme', target: '' }), cause => {
    const error = workbenchError(cause);
    assert.equal(error.message, 'Type mismatch');
    assert.deepEqual(error.diagnostics, [diagnostic]);
    return true;
  });
});

// Transport fixtures are precomputed projections. Receipt/state validation is the
// compiled MoonBit cursor's responsibility, exercised by its own qualified tests.
import { ExecutionClient } from './execution-session.ts';
const executionIdentity = { hostId: 'host', sessionId: 'test-session', providerId: 'scheme', executionId: 'one', snapshotId: 'snapshot' };
const submittedExecution: Execution = { identity: executionIdentity, state: 'submitted', sequence: 0, cancelRequested: false, connected: true, cancelAction: 'send' };
const runningExecution: Execution = { ...submittedExecution, state: 'running', sequence: 1 };
const acknowledgedExecution: Execution = { ...runningExecution, sequence: 2, cancelRequested: true, cancelAction: 'pending' };
const terminalExecution: Execution = { ...acknowledgedExecution, state: 'terminal', sequence: 3, cancelAction: 'already-terminal' };
const hostDescriptor = { profile: 'morphir/workbench/host', contractVersion: '0.2.0-draft.1', offer: { sessionId: 'test-session' } };
const evaluated = { success: true, profile: 'scheme-portable-v1', value: '42', terminalOutcomes: { fixture: 'typed-evidence' } };
function cursorFixture() {
  let execution: Execution | null = null; let result: WorkResult | null = null; const commands: { op: string; offer?: unknown }[] = [];
  return { commands, core(source: string) {
    const command = JSON.parse(source); commands.push(command);
    if (command.op === 'decode') {
      if (command.source === 'duplicate-keys') return JSON.stringify({ ok: false, code: 'duplicate' });
      return JSON.stringify({ ok: true, value: JSON.parse(command.source) });
    }
    if (command.op === 'offer') {
      if (command.sessionId !== 'test-session' || command.value.offer.sessionId !== command.sessionId) return JSON.stringify({ ok: false, code: 'session' });
      return JSON.stringify({ ok: true, value: command.value });
    }
    if (command.op === 'start') { execution = { ...submittedExecution, identity: command.identity }; result = null; }
    if (command.op === 'observe') {
      ({ execution, result = null } = command.receipt);
    }
    if (command.op === 'disconnect') execution = { ...execution!, connected: false, cancelAction: 'disconnected' };
    if (command.op === 'reconnect') execution = { ...execution!, connected: true, cancelAction: execution!.cancelRequested ? 'pending' : 'send' };
    return JSON.stringify({ ok: true, execution, result });
  } };
}
const response = (value: unknown, status = 200) => new Response(typeof value === 'string' ? value : JSON.stringify(value), { status });
const submission = { identity: executionIdentity, calls: ['workbench'], receipt: { execution: submittedExecution } };
const evaluationRequest = { operation: 'evaluate', source: '{"distribution":{}}', entry: 'Example:Main:answer', arguments: [] };

test('host executions are optional, advertised only after exact authenticated profile validation', async () => {
  const fixture = cursorFixture();
  const legacy = new ExecutionClient('test-session', { core: fixture.core, fetchFn: async () => response('', 404) });
  assert.equal(await legacy.initialize(), false);
  assert.equal(fixture.commands.length, 0);
  const invalid = new ExecutionClient('test-session', { core: fixture.core, fetchFn: async () => response({ ...hostDescriptor, unexpected: true }) });
  await assert.rejects(invalid.initialize(), /incompatible/);
  const otherSession = new ExecutionClient('wrong-session', { core: fixture.core, fetchFn: async () => response(hostDescriptor) });
  await assert.rejects(otherSession.initialize(), /rejected/);
});

test('a text transport reuses shared execution validation, polling and terminal release without HTTP', async () => {
  const fixture = cursorFixture(), requests: { operation: string; source?: string }[] = [];
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: async () => {},
    fetchFn() { throw new Error('HTTP must not be used'); },
    transport: { async request(operation, source) {
      requests.push({ operation, source });
      const value = operation === 'session' ? hostDescriptor : operation === 'submit' ? submission :
        operation === 'query' ? { execution: terminalExecution, result: evaluated } : { released: true };
      return { ok: true, status: 200, source: JSON.stringify(value) };
    } },
  });
  assert.equal(await client.initialize(), true);
  const result = await client.execute({ ...evaluationRequest, argumentsIon: '[42]' });
  assert.equal(result.value, '42'); assert.equal(result.execution!.state, 'terminal'); assert.equal(client.releasePending, false);
  assert.deepEqual(requests.map(r => r.operation), ['session', 'submit', 'query', 'release']);
  assert.equal(JSON.parse(requests[1]!.source!).inputs.format, 'ion-text');
  assert.ok(fixture.commands.some(c => c.op === 'decode'));
  assert.ok(fixture.commands.some(c => c.op === 'observe'));
});

test('a supplied text transport cannot bypass frame bounds or duplicate-aware decoding', async () => {
  for (const source of ['duplicate-keys', 'x'.repeat(1024 * 1024 + 1), null]) {
    const fixture = cursorFixture();
    const client = new ExecutionClient('test-session', { core: fixture.core, transport: {
      async request() { return malformed({ ok: true, status: 200, source }); },
    } });
    await assert.rejects(client.initialize(), /rejected|limit|invalid execution frame/);
  }
});

test('host execution evaluation sends tagged input source, observes progress, retains terminal evidence and releases', async () => {
  const fixture = cursorFixture(); const requests: { url: string; options?: FetchInit }[] = []; const progress: (Execution | null)[] = []; let queries = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: async () => {}, fetchFn: async (url, options) => {
    requests.push({ url, options });
    if (url.endsWith('/session')) return response(hostDescriptor);
    if (url.endsWith('/submit')) return response(submission);
    if (url.endsWith('/query')) return response(++queries === 1 ? { execution: runningExecution } : { execution: terminalExecution, result: evaluated });
    if (url.endsWith('/release')) return response({ released: true });
    throw new Error(url);
  } });
  assert.equal(await client.initialize(), true);
  const result = await client.execute({ ...evaluationRequest, argumentsIon: '[42]' }, execution => progress.push(execution));
  assert.equal(result.value, '42');
  assert.deepEqual(result.terminalOutcomes, evaluated.terminalOutcomes);
  assert.deepEqual(progress.map(execution => execution!.state), ['submitted', 'running', 'terminal']);
  const submit = requests.find(request => request.url.endsWith('/submit'));
  assert.deepEqual(JSON.parse(submit!.options!.body!), { contractVersion: '0.2.0-draft.1', model: evaluationRequest.source,
    entry: evaluationRequest.entry, inputs: { format: 'ion-text', source: '[42]' } });
  assert.ok(requests.every(request => request.options!.credentials === 'same-origin' && request.options!.cache === 'no-store'));
  assert.deepEqual(fixture.commands.find(command => command.op === 'start')!.offer, hostDescriptor.offer);
  assert.equal(client.releasePending, false);
});

test('query disconnect retains identity and explicit authenticated resume never resubmits', async () => {
  const fixture = cursorFixture(); const urls: string[] = []; let fail = true; let authentications = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: async () => {}, authenticate: async () => { ++authentications; return 'test-session'; }, fetchFn: async url => {
    urls.push(url);
    if (url.endsWith('/session')) return response(hostDescriptor);
    if (url.endsWith('/submit')) return response(submission);
    if (url.endsWith('/query')) { if (fail) { fail = false; throw new Error('offline'); } return response({ execution: terminalExecution, result: evaluated }); }
    if (url.endsWith('/release')) return response({ released: true });
  throw new Error('Unexpected test route');
} });
  await client.initialize();
  await assert.rejects(client.execute(evaluationRequest), error => (workbenchError(error).execution as Execution).identity.executionId === 'one' && !(workbenchError(error).execution as Execution).connected);
  await assert.rejects(client.execute(evaluationRequest), /already active/);
  const result = await client.resume();
  assert.equal(result.value, '42');
  assert.equal(authentications, 1);
  assert.equal(urls.filter(url => url.endsWith('/submit')).length, 1);
  assert.equal(fixture.commands.filter(command => command.op === 'reconnect').length, 1);
});

test('cancel waits for host acknowledgement and polling continues until terminal evidence', async () => {
  const fixture = cursorFixture(); let releasePoll: (() => void) | undefined; let queryCount = 0; let cancelCount = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: () => new Promise(resolve => { releasePoll = resolve; }), fetchFn: async url => {
    if (url.endsWith('/session')) return response(hostDescriptor);
    if (url.endsWith('/submit')) return response(submission);
    if (url.endsWith('/cancel')) { ++cancelCount; return response({ execution: acknowledgedExecution }); }
    if (url.endsWith('/query')) { ++queryCount; return response({ execution: terminalExecution, result: evaluated }); }
    if (url.endsWith('/release')) return response({ released: true });
  throw new Error('Unexpected test route');
} });
  await client.initialize();
  const pending = client.execute(evaluationRequest);
  while (!releasePoll) await new Promise(resolve => setImmediate(resolve));
  assert.equal(client.execution!.cancelRequested, false);
  await client.cancel();
  assert.equal(client.execution!.cancelRequested, true);
  assert.equal(client.execution!.state, 'running');
  await client.cancel();
  assert.equal(cancelCount, 1);
  releasePoll();
  assert.equal((await pending).execution!.state, 'terminal');
  assert.equal(queryCount, 1);
});

test('unknown submission effect cannot trigger a duplicate submission', async () => {
  const fixture = cursorFixture(); let submissions = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, fetchFn: async url => {
    if (url.endsWith('/session')) return response(hostDescriptor);
    ++submissions; throw new Error('connection lost before reply');
  } });
  await client.initialize();
  await assert.rejects(client.execute(evaluationRequest), /connection lost/);
  await assert.rejects(client.execute(evaluationRequest), /Submission status is unknown/);
  assert.equal(submissions, 1);
});

test('terminal result survives a failed release and explicit reconnect retries only release', async () => {
  const fixture = cursorFixture(); let releases = 0; let submissions = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: async () => {}, authenticate: async () => 'test-session', fetchFn: async url => {
    if (url.endsWith('/session')) return response(hostDescriptor);
    if (url.endsWith('/submit')) { ++submissions; return response(submission); }
    if (url.endsWith('/query')) return response({ execution: terminalExecution, result: evaluated });
    if (url.endsWith('/release')) { if (++releases === 1) throw new Error('offline'); return response({ released: true }); }
  throw new Error('Unexpected test route');
} });
  await client.initialize();
  const result = await client.execute(evaluationRequest);
  assert.equal(result.value, '42');
  assert.equal(result.execution!.connected, false);
  assert.equal(client.releasePending, true);
  assert.equal((await client.resume()).value, '42');
  assert.equal(client.releasePending, false);
  assert.equal(submissions, 1);
  assert.equal(releases, 2);
});

test('raw HTTP evidence is bounded and duplicate-aware decoding precedes submission adoption', async () => {
  const fixture = cursorFixture();
  const duplicate = new ExecutionClient('test-session', { core: fixture.core, fetchFn: async () => response('duplicate-keys') });
  await assert.rejects(duplicate.initialize(), /rejected/);
  const huge = new ExecutionClient('test-session', { core: fixture.core, fetchFn: async () => response('x'.repeat(1024 * 1024 + 1)) });
  await assert.rejects(huge.initialize(), /1-MiB/);
  let requests = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, fetchFn: async () => { ++requests; return response(hostDescriptor); } });
  await client.initialize();
  await assert.rejects(client.execute({ ...evaluationRequest, source: 'é'.repeat(600000) }), /1-MiB/);
  assert.equal(requests, 1);
  assert.equal(client.uncertainSubmission, false);
});

test('cancel requested before submission identity is admitted is queued and concurrent cancels share one acknowledgement', async () => {
  const fixture = cursorFixture(); let replySubmit: ((response: Response) => void) | undefined; let replyCancel: ((response: Response) => void) | undefined; let releasePoll: (() => void) | undefined; let cancellations = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: () => new Promise(resolve => { releasePoll = resolve; }), fetchFn: async url => {
    if (url.endsWith('/session')) return response(hostDescriptor);
    if (url.endsWith('/submit')) return new Promise(resolve => { replySubmit = resolve; });
    if (url.endsWith('/cancel')) { ++cancellations; return new Promise(resolve => { replyCancel = resolve; }); }
    if (url.endsWith('/query')) return response({ execution: terminalExecution, result: evaluated });
    if (url.endsWith('/release')) return response({ released: true });
  throw new Error('Unexpected test route');
} });
  await client.initialize();
  const execution = client.execute(evaluationRequest);
  assert.equal(client.active, true);
  await client.cancel();
  assert.equal(cancellations, 0);
  replySubmit!(response(submission));
  while (!replyCancel) await new Promise(resolve => setImmediate(resolve));
  const duplicateCancel = client.cancel();
  assert.equal(cancellations, 1);
  assert.equal(client.execution!.cancelRequested, false);
  replyCancel(response({ execution: acknowledgedExecution }));
  await duplicateCancel;
  while (!releasePoll) await new Promise(resolve => setImmediate(resolve));
  releasePoll();
  assert.equal((await execution).execution!.state, 'terminal');
  assert.equal(cancellations, 1);
  assert.equal(client.active, false);
});

test('invalid initial receipt or submission envelope cannot be resubmitted after possible host execution', async () => {
  for (const invalidReceipt of [false, true]) {
    const fixture = cursorFixture(); let submissions = 0;
    const client = new ExecutionClient('test-session', { core: source => {
      if (invalidReceipt && JSON.parse(source).op === 'start') return JSON.stringify({ ok: false, code: 'execution.sequence' });
      return fixture.core(source);
    }, fetchFn: async url => {
      if (url.endsWith('/session')) return response(hostDescriptor);
      ++submissions; return response(invalidReceipt ? submission : { ...submission, calls: ['other-call'] });
    } });
    await client.initialize();
    await assert.rejects(client.execute(evaluationRequest), error => workbenchError(error).submissionUnknown === true);
    await assert.rejects(client.execute(evaluationRequest), /Submission status is unknown/);
    assert.equal(submissions, 1);
  }
});

test('explicit resume refuses a changed authenticated session before querying the retained identity', async () => {
  const fixture = cursorFixture(); let queries = 0; let descriptors = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: async () => {}, authenticate: async () => 'different-session', fetchFn: async url => {
    if (url.endsWith('/session')) { ++descriptors; return response(hostDescriptor); }
    if (url.endsWith('/submit')) return response(submission);
    ++queries; throw new Error('offline');
  } });
  await client.initialize();
  await assert.rejects(client.execute(evaluationRequest), /offline/);
  await assert.rejects(client.resume(), /session changed/);
  assert.equal(descriptors, 1);
  assert.equal(queries, 1);
  assert.deepEqual(client.execution!.identity, executionIdentity);
});

test('a timed out observation disconnects the retained execution without synthesizing a terminal result', async () => {
  const fixture = cursorFixture();
  const client = new ExecutionClient('test-session', { core: fixture.core, timeout: 5, pause: async () => {}, fetchFn: async (url, options) => {
    if (url.endsWith('/session')) return response(hostDescriptor);
    if (url.endsWith('/submit')) return response(submission);
    return new Promise((resolve, reject) => options!.signal!.addEventListener('abort', () => reject(options!.signal!.reason), { once: true }));
  } });
  await client.initialize();
  await assert.rejects(client.execute(evaluationRequest), /timed out/);
  assert.equal(client.execution!.connected, false);
  assert.equal(client.execution!.state, 'submitted');
  assert.equal(client.result, null);
});

test('connected evaluator uses the separately admitted host profile without adding v1 RPC operations', async () => {
  const rpcCalls: string[] = []; const evaluatedRequests: Pick<WorkRequest, 'source' | 'entry' | 'arguments' | 'argumentsIon'>[] = []; const progress: (Execution | null)[] = [];
  let cancellations = 0; let disposed = false;
  const executions: Pick<ExecutionClient, 'initialize' | 'execute' | 'resume' | 'cancel' | 'active' | 'execution'> = { active: false, async initialize() { return true; }, execution: submittedExecution,
    async execute(request, report) { evaluatedRequests.push(request); report?.(submittedExecution); return evaluated; },
    async resume(report) { report?.(runningExecution); return evaluated; },
    async cancel() { ++cancellations; } };
  const rpc = { async call(method: string) { rpcCalls.push(method); return {}; }, dispose() { disposed = true; } };
  const adapter = new ConnectedAdapter(rpc, { ...manifest, providers: [], initialSources: [] }, { async execute() { throw new Error('Unexpected local execution'); }, cancel() {} }, executions);
  assert.equal((await adapter.initialize()).executionsAvailable, true);
  assert.equal((await adapter.execute(evaluationRequest, execution => progress.push(execution))).value, '42');
  assert.deepEqual(evaluatedRequests[0], evaluationRequest);
  assert.notEqual(evaluatedRequests[0], evaluationRequest, 'The adapter captures caller input before asynchronous transport work');
  const epoch = adapter.epoch;
  await adapter.cancel();
  assert.equal(adapter.epoch, epoch);
  assert.equal(cancellations, 1);
  await adapter.execute({ operation: 'resume-execution' }, execution => progress.push(execution));
  assert.deepEqual(progress, [submittedExecution, runningExecution]);
  assert.deepEqual(rpcCalls, ['morphir.session.initialize']);
  adapter.dispose();
  assert.equal(cancellations, 1);
  assert.equal(disposed, true);
});

test('only closed bounded 4xx envelopes permit a later explicit submission', async () => {
  const valid = { error: { code: 'workbench.invalid_inputs', message: 'Repair the inputs.' } };
  for (const [status, envelope, knownRejected] of [
    [400, valid, true], [503, valid, false], [400, { ...valid, unexpected: true }, false],
    [400, { error: { ...valid.error, message: 'x'.repeat(513) } }, false],
  ] as [number, unknown, boolean][]) {
    const fixture = cursorFixture(); let submissions = 0;
    const client = new ExecutionClient('test-session', { core: fixture.core, fetchFn: async url => {
      if (url.endsWith('/session')) return response(hostDescriptor);
      ++submissions; return response(envelope, status!);
    } });
    await client.initialize();
    await assert.rejects(client.execute(evaluationRequest));
    assert.equal(client.uncertainSubmission, !knownRejected);
    await assert.rejects(client.execute(evaluationRequest));
    assert.equal(submissions, knownRejected ? 2 : 1);
  }
});

test('fresh authenticated resume recovers a lost successful release reply and permits the next submission', async () => {
  const fixture = cursorFixture(); let releases = 0; let submissions = 0; let authentications = 0;
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: async () => {}, authenticate: async () => { ++authentications; return 'test-session'; }, fetchFn: async url => {
    if (url.endsWith('/session')) return response(hostDescriptor);
    if (url.endsWith('/submit')) { ++submissions; return response(submission); }
    if (url.endsWith('/query')) return response({ execution: terminalExecution, result: evaluated });
    if (url.endsWith('/release')) {
      ++releases;
      if (releases === 1) throw new Error('reply lost after host released');
      if (releases === 2) return response({ error: { code: 'workbench.host_unknown_execution', message: 'The execution is absent.' } }, 404);
      return response({ released: true });
    }
  throw new Error('Unexpected test route');
} });
  await client.initialize();
  const original = await client.execute(evaluationRequest);
  assert.equal(original.value, '42');
  assert.equal(client.releasePending, true);
  const resumed = await client.resume();
  assert.equal(resumed.value, original.value);
  assert.deepEqual(resumed.terminalOutcomes, original.terminalOutcomes);
  assert.equal(client.releasePending, false);
  assert.equal(authentications, 1);
  assert.equal((await client.execute(evaluationRequest)).value, '42');
  assert.equal(submissions, 2);
});

test('release absence recovery requires both freshly authenticated identity and the exact unknown-execution error code', async () => {
  for (const [code, authenticate] of [
    ['workbench.host_disabled', async () => 'test-session'],
    ['workbench.host_unknown_execution', undefined],
  ] as [string, (() => Promise<string>) | undefined][]) {
    const fixture = cursorFixture(); let releases = 0;
    const client = new ExecutionClient('test-session', { core: fixture.core, pause: async () => {}, authenticate, fetchFn: async url => {
      if (url.endsWith('/session')) return response(hostDescriptor);
      if (url.endsWith('/submit')) return response(submission);
      if (url.endsWith('/query')) return response({ execution: terminalExecution, result: evaluated });
      if (url.endsWith('/release')) {
        if (++releases === 1) throw new Error('release reply lost');
        return response({ error: { code, message: 'Release unavailable.' } }, 404);
      }
    throw new Error('Unexpected test route');
} });
    await client.initialize();
    const original = await client.execute(evaluationRequest);
    await assert.rejects(client.resume(), error => workbenchError(error).status === 404 && workbenchError(error).code === code);
    assert.equal(client.releasePending, true);
    assert.equal(client.result!.value, original.value);
    assert.equal(client.execution!.state, 'terminal');
    assert.equal(client.execution!.connected, false);
  }
});

test('a late cancellation failure from a released execution cannot disconnect its replacement', async () => {
  const fixture = cursorFixture(); const pauses: (() => void)[] = []; let failOldCancel: (cause: unknown) => void = () => {}; let submissions = 0;
  const nextIdentity = { ...executionIdentity, executionId: 'two', snapshotId: 'snapshot-two' };
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: () => new Promise(resolve => pauses.push(resolve)), fetchFn: async (url, options) => {
    if (url.endsWith('/session')) return response(hostDescriptor);
    if (url.endsWith('/submit')) return response(++submissions === 1 ? submission : { ...submission, identity: nextIdentity });
    if (url.endsWith('/cancel')) return new Promise((resolve, reject) => { failOldCancel = reject; });
    if (url.endsWith('/query')) return response({ execution: { ...terminalExecution, identity: JSON.parse(options!.body!).identity }, result: evaluated });
    if (url.endsWith('/release')) return response({ released: true });
  throw new Error('Unexpected test route');
} });
  await client.initialize();
  const first = client.execute(evaluationRequest);
  while (!pauses.length) await new Promise(resolve => setImmediate(resolve));
  const oldCancellation = client.cancel().then(() => null, error => error);
  pauses.shift()!();
  await first;
  const replacement = client.execute(evaluationRequest);
  while (!pauses.length) await new Promise(resolve => setImmediate(resolve));
  failOldCancel!(new Error('late old-execution cancellation failure'));
  const lateError = await oldCancellation;
  assert.equal(client.execution!.identity!.executionId, 'two');
  assert.equal(client.execution!.connected, true, 'A rejected old request cannot disconnect the new cursor');
  assert.equal(lateError, null, 'Stale cancellation failure is ignored');
  pauses.shift()!();
  assert.equal((await replacement).execution!.identity!.executionId, 'two');
});

test('late old-execution cancel replies and failures preserve the replacement cancellation promise', async () => {
  for (const lateFailure of [false, true]) {
    const fixture = cursorFixture(); const pauses: (() => void)[] = []; const pendingCancels: { resolve(response: Response): void; reject(cause: unknown): void }[] = []; let submissions = 0;
    const nextIdentity = { ...executionIdentity, executionId: 'two', snapshotId: 'snapshot-two' };
    const client = new ExecutionClient('test-session', { core: fixture.core, pause: () => new Promise(resolve => pauses.push(resolve)), fetchFn: async (url, options) => {
      if (url.endsWith('/session')) return response(hostDescriptor);
      if (url.endsWith('/submit')) return response(++submissions === 1 ? submission : { ...submission, identity: nextIdentity });
      if (url.endsWith('/cancel')) return new Promise((resolve, reject) => pendingCancels.push({ resolve, reject }));
      if (url.endsWith('/query')) return response({ execution: { ...terminalExecution, identity: JSON.parse(options!.body!).identity }, result: evaluated });
      if (url.endsWith('/release')) return response({ released: true });
    throw new Error('Unexpected test route');
} });
    await client.initialize();
    const first = client.execute(evaluationRequest);
    while (!pauses.length) await new Promise(resolve => setImmediate(resolve));
    const oldCancellation = client.cancel().then(() => null, error => error);
    pauses.shift()!();
    await first;
    const replacement = client.execute(evaluationRequest);
    while (!pauses.length) await new Promise(resolve => setImmediate(resolve));
    const newCancellation = client.cancel();
    assert.equal(pendingCancels.length, 2, 'The new execution does not reuse the old cancellation promise');
    if (lateFailure) pendingCancels[0]!.reject(new Error('late old-execution cancellation failure'));
    else pendingCancels[0]!.resolve(response({ execution: acknowledgedExecution }));
    assert.equal(await oldCancellation, null);
    assert.equal(client.execution!.identity!.executionId, 'two');
    assert.equal(client.execution!.connected, true);
    assert.equal(client.execution!.cancelRequested, false, 'An old acknowledgement cannot change the replacement receipt');
    let duplicateSettled = false;
    const duplicate = client.cancel().then(() => { duplicateSettled = true; });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(pendingCancels.length, 2, 'Old cancellation cleanup cannot clear the new promise');
    assert.equal(duplicateSettled, false, 'A repeated cancel waits for the new execution acknowledgement');
    pendingCancels[1]!.resolve(response({ execution: { ...acknowledgedExecution, identity: nextIdentity } }));
    await Promise.all([newCancellation, duplicate]);
    assert.equal(client.execution!.cancelRequested, true);
    pauses.shift()!();
    assert.equal((await replacement).execution!.identity!.executionId, 'two');
    assert.equal(client.execution!.connected, true);
  }
});

test('host HTTP fetch keeps the browser global receiver required by native Window.fetch', async () => {
  const fixture = cursorFixture();
  const client = new ExecutionClient('test-session', { core: fixture.core, fetchFn: function () {
    assert.equal(this, globalThis, 'Native browser fetch rejects a ExecutionClient receiver');
    return Promise.resolve(response(hostDescriptor));
  } });
  assert.equal(await client.initialize(), true);
});

test('an in-flight submission cannot be replaced by another submission before its receipt arrives', async () => {
  const fixture = cursorFixture(); let resolveSubmit, submissions = 0;
  const pending = new Promise(resolve => { resolveSubmit = resolve; });
  const client = new ExecutionClient('test-session', { core: fixture.core, pause: async () => {},
    transport: { async request(path) {
      if (path === 'submit') { ++submissions; await pending; }
      return { ok: true, status: 200, source: JSON.stringify(path === 'session' ? hostDescriptor :
        path === 'submit' ? submission : path === 'query' ? { execution: terminalExecution, result: evaluated } : { released: true }) };
    } },
  });
  await client.initialize();
  const first = client.execute(evaluationRequest);
  await assert.rejects(client.execute(evaluationRequest), /already active/);
  assert.equal(submissions, 1);
  resolveSubmit!(); assert.equal((await first).value, '42');
});

test('project requests are bounded by file count, path length and total size', async () => {
  const adapter = new LocalAdapter(() => ({ postMessage() {}, terminate() {} }), 5);
  const file = (path: unknown, content: unknown) => ({ path, content });
  const refused = (project: ProjectPayload) => assert.rejects(adapter.execute({ operation: 'compile', project }), /smaller than 16 MiB/);
  await refused({ files: Array.from({ length: 2001 }, (_, i) => file(`src/m${i}.elm`, '')) });
  await refused({ files: [file('p'.repeat(4097), '')] });
  await refused({ files: [{ path: 7, content: '' }] });
  await refused({ files: [file('src/a.elm', 5)] });
  await refused({ files: [file('src/a.elm', 'x'.repeat(16 * 1024 * 1024))] });
  await assert.rejects(adapter.execute({ operation: 'compile', project: { files: [file('src/a.elm', 'x')] } }), /timed out/);
});

test('a folder import is bounded like a project request', async () => {
  const adapter = new LocalAdapter(() => ({ postMessage() {}, terminate() {} }), 5);
  const file = (path: unknown, content: unknown) => ({ path, content });
  await assert.rejects(adapter.execute({ operation: 'import-folder', files: Array.from({ length: 2001 }, (_, i) => file(`p/${i}.elm`, '')) }), /smaller than 16 MiB/);
  await assert.rejects(adapter.execute({ operation: 'import-folder' }), /smaller than 16 MiB/);
  await assert.rejects(adapter.execute({ operation: 'import-folder', files: [file('p/morphir.json', '{}')] }), /timed out/);
});

test('local capability results must echo the submitted policy before publication', async () => {
  for (const policy of ['strict', 'permissive']) {
    for (const echoed of [policy, 'other', null]) {
      let stopped = false;
      const adapter = new LocalAdapter(() => {
        const port: WorkerPort = { terminate() { stopped = true; }, postMessage(message) {
          queueMicrotask(() => port.onmessage?.({ data: { id: message.id, result: {
            success: true, ...(echoed === null ? {} : { admission: { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: echoed } }),
          } } }));
        } };
        return port;
      });
      const pending = adapter.execute({ operation: 'evaluate', source: '{}', executionMode: 'capability',
        admission: { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy } });
      if (echoed === policy) assert.equal((await pending).success, true);
      else await assert.rejects(pending, /different checking policy/);
      assert.equal(stopped, true);
    }
  }
});

test('connected mapping refuses explicit policy instead of silently running strict', async () => {
  let calls = 0;
  const adapter = new ConnectedAdapter({ async call() { calls++; return {}; } }, manifest,
    { async execute() { calls++; return { success: true }; }, cancel() {} });
  for (const request of [
    { operation: 'evaluate', source: '{}', executionMode: 'capability' },
    { operation: 'evaluate', source: '{}', executionMode: 'typed', admission: { policy: 'permissive' } },
  ]) await assert.rejects(adapter.execute(request), /does not offer checking-policy/);
  assert.equal(calls, 0);
});

test('local policy echo checks retain the submitted selection after caller edits', async () => {
  for (const changeMode of [false, true]) {
    let port: WorkerPort | undefined;
    let id = 0;
    const adapter = new LocalAdapter(() => (port = { terminate() {}, postMessage(message) { id = message.id; } }));
    const admission = { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: 'strict' };
    const request = { operation: 'evaluate', source: '{}', executionMode: 'capability', admission };
    const pending = adapter.execute(request);
    admission.policy = 'permissive';
    if (changeMode) request.executionMode = 'typed';
    port!.onmessage!({ data: { id, result: { success: true,
      admission: { ...admission, policy: changeMode ? 'permissive' : 'strict' },
    } } });
    if (changeMode) await assert.rejects(pending, /different checking policy/);
    else assert.equal((await pending).success, true);
  }
});

test('invalid capability selections are refused before a worker starts', async () => {
  let started = 0;
  const adapter = new LocalAdapter(() => { started++; throw new Error('Unexpected worker'); });
  const selections: Json[] = [
    { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: 'unknown' },
    { profile: 'morphir/workbench/admission', contractVersion: 'future', policy: 'strict' },
    { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: 'strict', extra: true },
    { policy: 'permissive' },
  ];
  for (const selection of selections) {
    await assert.rejects(adapter.execute({ operation: 'evaluate', source: '{}', executionMode: 'capability', admission: selection }), /invalid capability checking policy/);
  }
  assert.equal(started, 0);
});

test('an omitted capability policy is captured as strict and must be echoed', async () => {
  for (const policy of ['strict', 'permissive']) {
    const adapter = new LocalAdapter(() => {
      const port: WorkerPort = { terminate() {}, postMessage(message) {
        queueMicrotask(() => port.onmessage?.({ data: { id: message.id, result: { success: true,
          admission: { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy },
        } } }));
      } };
      return port;
    });
    const pending = adapter.execute({ operation: 'evaluate', source: '{}', executionMode: 'capability' });
    if (policy === 'strict') assert.equal((await pending).success, true);
    else await assert.rejects(pending, /different checking policy/);
  }
});


test('connected checking controls require the validated live policy evaluator', async () => {
  for (const evaluator of [undefined, 'unknown-evaluator', 'scheme-portable-v1/shared-sdk/bounded']) {
    for (const available of [false, true]) {
      const executions = { capabilityEvaluator: evaluator, active: false, execution: null,
        async initialize() { return available; }, async execute() { return evaluated; },
        async resume() { return evaluated; }, async cancel() {} };
      const adapter = new ConnectedAdapter({ async call() { return {}; } }, { ...manifest, providers: [], initialSources: [] },
        { async execute() { return { success: true }; }, cancel() {} }, executions);
      const result = await adapter.initialize();
      const qualified = available && evaluator === 'scheme-portable-v1/shared-sdk/bounded';
      assert.equal(result.capabilityEvaluator, qualified ? evaluator : undefined);
      assert.equal(result.capabilityRuntime, qualified ? 'connected' : undefined);
      if (!qualified) await assert.rejects(adapter.execute({ ...evaluationRequest, executionMode: 'capability' }), /does not offer/);
    }
  }
});

test('connected policy evaluation captures source inputs and selection before any asynchronous work', async () => {
  let captured: WorkRequest | undefined;
  let finish: () => void = () => {};
  const gate = new Promise<void>(resolve => { finish = resolve; });
  const executions = { capabilityEvaluator: 'scheme-portable-v1/shared-sdk/bounded', active: false, execution: null,
    async initialize() { return true; }, async execute(request: WorkRequest) { await gate; captured = request; return evaluated; },
    async resume() { return evaluated; }, async cancel() {} };
  const adapter = new ConnectedAdapter({ async call() { return {}; } }, { ...manifest, providers: [], initialSources: [] },
    { async execute() { throw new Error('No local execution'); }, cancel() {} }, executions);
  await adapter.initialize();
  const request: WorkRequest = { ...evaluationRequest, executionMode: 'capability', arguments: [{ type: 'int', value: '42' }],
    admission: { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: 'permissive' } };
  const expected = structuredClone(request);
  const pending = adapter.execute(request);
  request.source = 'changed'; request.arguments = []; request.argumentsIon = '[]';
  (request.admission as Record<string, Json>).policy = 'strict';
  finish(); await pending;
  assert.deepEqual(captured, expected);
  for (const operation of ['compile', 'inspect', 'resume-execution']) {
    await assert.rejects(adapter.execute({ ...expected, operation }), /only.*evaluation/);
  }
});

test('a disconnected checking client cannot reuse earlier UI capability discovery', async () => {
  let connected = true, calls = 0;
  const executions = { get capabilityEvaluator() { return connected ? 'scheme-portable-v1/shared-sdk/bounded' : undefined; },
    active: false, execution: null, async initialize() { return true; },
    async execute() { calls++; return evaluated; }, async resume() { return evaluated; }, async cancel() {} };
  const adapter = new ConnectedAdapter({ async call() { return {}; } }, { ...manifest, providers: [], initialSources: [] },
    { async execute() { return { success: true }; }, cancel() {} }, executions);
  assert.equal((await adapter.initialize()).capabilityRuntime, 'connected');
  connected = false;
  await assert.rejects(adapter.execute({ ...evaluationRequest, executionMode: 'capability' }), /does not offer/);
  assert.equal(calls, 0, 'Stale UI discovery never authorizes a submission');
});
