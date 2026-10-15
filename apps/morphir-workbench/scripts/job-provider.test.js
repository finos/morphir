import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { setTimeout as pause } from 'node:timers/promises';
import { createJobProvider } from './job-provider.js';

const version = '0.1.0-draft.1';
function fixture() {
  const jobs = new Map(); let sequence = 0;
  return rawOffer => { const offer = JSON.parse(rawOffer); return source => {
    const request = JSON.parse(source);
    let value;
    if (request.op === 'submit') {
      const identity = { ...offer, jobId: `job-${++sequence}`, snapshotId: 'snapshot' };
      for (const key of ['profile', 'contractVersion', 'operations']) delete identity[key];
      const receipt = { contractVersion: version, identity, sequence: 0, state: 'submitted', cancelRequested: false, outcomes: null };
      jobs.set(identity.jobId, receipt); value = { identity, calls: ['workbench'], receipt };
    } else {
      const identity = request.identity || JSON.parse(request.body).identity;
      const job = jobs.get(identity.jobId);
      if (request.op === 'claim') { job.state = 'running'; job.sequence++; value = { operation: 'evaluate', executionMode: 'typed', source: '{}', entry: 'example:main#identity', arguments: [] }; }
      if (request.op === 'query') value = job;
      if (request.op === 'cancel') { job.cancelRequested = true; job.sequence++; value = job; }
      if (request.op === 'complete') { job.state = 'terminal'; job.sequence++; job.outcomes = request.outcomes; value = job; }
      if (request.op === 'release') { jobs.delete(identity.jobId); value = { released: true }; }
    }
    return JSON.stringify({ ok: true, value });
  }; };
}
class WorkerStub extends EventEmitter {
  constructor() { super(); this.exited = false; this.terminated = 0; }
  postMessage(value) { this.request = value; }
  async terminate() { this.terminated++; this.exited = true; this.emit('exit', 1); return 1; }
  finish(outcomes) { this.emit('message', { id: 1, result: { terminalOutcomes: outcomes } }); }
  exit(code = 0) { this.exited = true; this.emit('exit', code); }
}
const returned = { contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '7' } } }], cleanup: null, extensions: null };
const body = identity => JSON.stringify({ contractVersion: version, identity });
async function setup(t, options = {}) {
  const workers = [];
  const provider = await createJobProvider({ factory: fixture(), workerFactory: () => { const worker = new WorkerStub(); workers.push(worker); return worker; }, ...options });
  t.after(() => provider.close());
  return { provider, workers, submit: () => provider.command('submit', '{}', 'session') };
}

test('provider binds one authenticated session and offers no replacement identity', async t => {
  const { provider } = await setup(t);
  const first = await provider.session('session');
  assert.equal(first.offer.sessionId, 'session');
  assert.equal(first.offer.providerId, 'moonbit-scheme');
  assert.equal(first.offer.hostId, (await provider.session('session')).offer.hostId);
  await assert.rejects(provider.session('other'), error => error.status === 409);
  assert.deepEqual(await provider.session('session'), first);
});
test('result remains running until worker exit confirms release', async t => {
  const { provider, workers, submit } = await setup(t);
  const job = await submit(); await pause(0);
  assert.equal(workers.length, 1); workers[0].finish(returned);
  assert.equal((await provider.command('query', body(job.identity), 'session')).state, 'running');
  workers[0].exit(); await pause(0);
  const receipt = await provider.command('query', body(job.identity), 'session');
  assert.equal(receipt.state, 'terminal'); assert.deepEqual(receipt.outcomes, returned);
});
test('scheduler starts at most two workers and queued cancel completes without execution', async t => {
  const { provider, workers, submit } = await setup(t);
  await submit(); await submit(); const queued = await submit(); await pause(0);
  assert.equal(workers.length, 2);
  const ack = await provider.command('cancel', body(queued.identity), 'session');
  assert.equal(ack.cancelRequested, true);
  await pause(0);
  const done = await provider.command('query', body(queued.identity), 'session');
  assert.equal(done.state, 'terminal'); assert.equal(done.outcomes.calls[0].outcome.status, 'cancelled');
  assert.equal(workers.length, 2);
});
test('captured result survives cancellation while uncaptured work becomes cancelled after termination', async t => {
  const { provider, workers, submit } = await setup(t);
  const first = await submit(); const second = await submit(); await pause(0);
  workers[0].finish(returned);
  await provider.command('cancel', body(first.identity), 'session');
  await provider.command('cancel', body(second.identity), 'session'); await pause(0);
  assert.equal((await provider.command('query', body(first.identity), 'session')).outcomes.calls[0].outcome.status, 'returned');
  assert.equal((await provider.command('query', body(second.identity), 'session')).outcomes.calls[0].outcome.status, 'cancelled');
});
test('host deadline waits for termination then records bounded failure', async t => {
  const { provider, workers, submit } = await setup(t, { deadlineMs: 10 });
  const job = await submit(); await pause(30);
  const done = await provider.command('query', body(job.identity), 'session');
  assert.equal(workers[0].terminated, 1); assert.equal(done.state, 'terminal');
  assert.equal(done.outcomes.calls[0].outcome.status, 'failed');
  assert.equal(done.outcomes.calls[0].outcome.failure.code, 'workbench.worker_deadline');
});

test('real compiled host and isolated pipeline evaluate admitted JSON and Ion values and retain release semantics', async t => {
  const { readFile } = await import('node:fs/promises');
  const model = await readFile(new URL('../fixtures/typed-pricing.json', import.meta.url), 'utf8');
  const provider = await createJobProvider(); t.after(() => provider.close());
  const argumentsValue = [{ type: 'record', fields: [
    { name: 'price', value: { type: 'decimal', coefficient: '125', exponent: -1 } },
    { name: 'quantity', value: { type: 'int', value: '3' } },
  ] }];
  for (const format of ['json', 'ion-text']) {
    const source = format === 'json' ? JSON.stringify(argumentsValue) : `[morphir_value::${JSON.stringify(argumentsValue[0])}]`;
    const submitted = await provider.command('submit', JSON.stringify({ contractVersion: version, model, entry: 'pricing:quotes#total', inputs: { format, source } }), 'real-session');
    assert.equal(submitted.receipt.sequence, 0); assert.equal(submitted.receipt.state, 'submitted');
    let latest;
    for (let attempt = 0; attempt < 100; attempt++) {
      latest = await provider.command('query', body(submitted.identity), 'real-session');
      if (latest.state === 'terminal') break;
      await pause(10);
    }
    assert.equal(latest.state, 'terminal');
    assert.deepEqual(latest.outcomes.calls[0].outcome, { status: 'returned', value: { type: 'decimal', coefficient: '375', exponent: -1 } });
    assert.deepEqual(await provider.command('release', body(submitted.identity), 'real-session'), { released: true });
    await assert.rejects(provider.command('query', body(submitted.identity), 'real-session'));
  }
});

test('missing worker evidence becomes fixed failure and cleanup failure stays separate from returned value', async t => {
  const { provider, workers, submit } = await setup(t);
  const missing = await submit(); const captured = await submit(); await pause(0);
  workers[0].exit(0); workers[1].finish(returned); workers[1].exit(1); await pause(0);
  const absent = await provider.command('query', body(missing.identity), 'session');
  assert.equal(absent.outcomes.calls[0].outcome.status, 'failed');
  assert.equal(absent.outcomes.calls[0].outcome.failure.code, 'workbench.worker_result');
  const kept = await provider.command('query', body(captured.identity), 'session');
  assert.equal(kept.outcomes.calls[0].outcome.status, 'returned');
  assert.equal(kept.outcomes.cleanup.stage, 'cleanup');
  assert.equal(kept.outcomes.cleanup.code, 'workbench.worker_cleanup');
});
test('provider shutdown terminates only its workers and disables new admission', async t => {
  const owned = await setup(t); const other = await setup(t);
  await owned.submit(); await other.submit(); await pause(0);
  await owned.provider.close();
  assert.equal(owned.workers[0].terminated, 1); assert.equal(other.workers[0].terminated, 0);
  await assert.rejects(owned.provider.session('session'), error => error.status === 503);
});

test('actual isolated thread is stopped before cancelled evidence is published', async t => {
  const { Worker } = await import('node:worker_threads');
  const { once } = await import('node:events');
  const workers = [];
  const module = `data:text/javascript,${encodeURIComponent(`self.onmessage = () => { while (true) {} };`)}`;
  const provider = await createJobProvider({ factory: fixture(), deadlineMs: 5000,
    workerFactory: () => { const worker = new Worker(new URL('./job-worker.js', import.meta.url), { workerData: { module } }); workers.push(worker); return worker; } });
  t.after(() => provider.close());
  const job = await provider.command('submit', '{}', 'session');
  await once(workers[0], 'online');
  const exit = once(workers[0], 'exit');
  const ack = await provider.command('cancel', body(job.identity), 'session');
  assert.equal(ack.cancelRequested, true); assert.equal(ack.state, 'running');
  await exit; await pause(0);
  const final = await provider.command('query', body(job.identity), 'session');
  assert.equal(final.state, 'terminal'); assert.equal(final.outcomes.calls[0].outcome.status, 'cancelled');
  assert.equal(workers[0].threadId, -1);
});
test('actual worker result captured before cancellation survives termination of its busy thread', async t => {
  const { Worker } = await import('node:worker_threads');
  const { once } = await import('node:events');
  const workers = [];
  const script = `self.onmessage = () => { self.postMessage({ id: 1, result: { terminalOutcomes: ${JSON.stringify(returned)} } }); while (true) {} };`;
  const module = `data:text/javascript,${encodeURIComponent(script)}`;
  const provider = await createJobProvider({ factory: fixture(), deadlineMs: 5000,
    workerFactory: () => { const worker = new Worker(new URL('./job-worker.js', import.meta.url), { workerData: { module } }); workers.push(worker); return worker; } });
  t.after(() => provider.close());
  const job = await provider.command('submit', '{}', 'session');
  await once(workers[0], 'message');
  const exit = once(workers[0], 'exit');
  await provider.command('cancel', body(job.identity), 'session');
  await exit; await pause(0);
  const final = await provider.command('query', body(job.identity), 'session');
  assert.equal(final.state, 'terminal'); assert.deepEqual(final.outcomes.calls[0].outcome, returned.calls[0].outcome);
  assert.equal(workers[0].threadId, -1);
});

test('unconfirmed failed termination never invents Cancelled and close reports a bounded cleanup failure', async t => {
  const worker = new WorkerStub();
  worker.terminate = async () => { throw new Error('private worker implementation details'); };
  const provider = await createJobProvider({ factory: fixture(), workerFactory: () => worker });
  t.after(() => provider.close().catch(() => {}));
  const job = await provider.command('submit', '{}', 'session');
  await provider.command('cancel', body(job.identity), 'session'); await pause(0);
  const current = await provider.command('query', body(job.identity), 'session');
  assert.equal(current.state, 'running'); assert.equal(current.outcomes, null);
  await assert.rejects(provider.close(), error => error.code === 'workbench.worker_cleanup' && !error.message.includes('private'));
});
test('real owner retains eight jobs without eviction and releases only terminal work', async t => {
  const { readFile } = await import('node:fs/promises');
  const provider = await createJobProvider(); t.after(() => provider.close());
  const model = await readFile(new URL('../fixtures/typed-pricing.json', import.meta.url), 'utf8');
  const submit = JSON.stringify({ contractVersion: version, model, entry: 'pricing:quotes#difference', inputs: { format: 'json', source: '[{"type":"int","value":"7"},{"type":"int","value":"3"}]' } });
  const retained = [];
  for (let count = 0; count < 8; count++) retained.push(await provider.command('submit', submit, 'session'));
  await assert.rejects(provider.command('submit', submit, 'session'), error => error.status === 409 && error.code === 'workbench.host_capacity');
  for (const job of retained) assert.deepEqual((await provider.command('query', body(job.identity), 'session')).identity, job.identity);
  await assert.rejects(provider.command('release', body(retained.at(-1).identity), 'session'), error => error.status === 409 && error.code === 'workbench.host_not_terminal');
});

test('actual worker crash after a typed result preserves that result with separate cleanup evidence', async t => {
  const { Worker } = await import('node:worker_threads');
  const { readFile } = await import('node:fs/promises');
  const workers = [];
  const script = `self.onmessage = () => { self.postMessage({ id: 1, result: { terminalOutcomes: ${JSON.stringify(returned)} } }); setTimeout(() => { throw new Error('private worker failure'); }, 0); };`;
  const module = `data:text/javascript,${encodeURIComponent(script)}`;
  const provider = await createJobProvider({ workerFactory: () => { const worker = new Worker(new URL('./job-worker.js', import.meta.url), { workerData: { module } }); workers.push(worker); return worker; } });
  t.after(() => provider.close());
  const model = await readFile(new URL('../fixtures/typed-pricing.json', import.meta.url), 'utf8');
  const submitted = await provider.command('submit', JSON.stringify({ contractVersion: version, model, entry: 'pricing:quotes#difference', inputs: { format: 'json', source: '[{"type":"int","value":"10"},{"type":"int","value":"3"}]' } }), 'session');
  await new Promise(resolve => workers[0].once('exit', resolve)); await pause(0);
  const done = await provider.command('query', body(submitted.identity), 'session');
  assert.equal(done.state, 'terminal'); assert.deepEqual(done.outcomes.calls[0].outcome, returned.calls[0].outcome);
  assert.equal(done.outcomes.cleanup?.stage, 'cleanup');
  assert.equal(done.outcomes.cleanup?.code, 'workbench.worker_cleanup');
});

test('real owner replaces near-limit evidence that cannot fit a receipt with bounded Failed evidence', async t => {
  const { Worker } = await import('node:worker_threads');
  const { readFile } = await import('node:fs/promises');
  const large = { contractVersion: '0.1.0-draft.5', calls: [{ id: 'workbench', outcome: {
    status: 'returned', value: { type: 'list', items: Array.from({ length: 104 }, () => ({ type: 'int', value: '1'.repeat(10000) })).concat({ type: 'int', value: '1' }) },
  } }], cleanup: null, extensions: null };
  const target = 1024 * 1024 - 100;
  const padding = target - Buffer.byteLength(JSON.stringify(large));
  assert(padding > 0 && padding < 9999);
  large.calls[0].outcome.value.items.at(-1).value += '1'.repeat(padding);
  assert.equal(Buffer.byteLength(JSON.stringify(large)), target);
  const script = `self.onmessage = () => self.postMessage({ id: 1, result: { terminalOutcomes: ${JSON.stringify(large)} } });`;
  const module = `data:text/javascript,${encodeURIComponent(script)}`;
  const workers = [];
  const provider = await createJobProvider({ workerFactory: () => { const worker = new Worker(new URL('./job-worker.js', import.meta.url), { workerData: { module } }); workers.push(worker); return worker; } });
  t.after(() => provider.close());
  const model = await readFile(new URL('../fixtures/typed-pricing.json', import.meta.url), 'utf8');
  const job = await provider.command('submit', JSON.stringify({ contractVersion: version, model, entry: 'pricing:boundaries#list', inputs: { format: 'json', source: '[{"type":"list","items":[]}]' } }), 'session');
  await new Promise(resolve => workers[0].once('exit', resolve));
  const final = await provider.command('query', body(job.identity), 'session');
  assert.equal(final.state, 'terminal');
  assert.equal(final.outcomes.calls[0].outcome.status, 'failed');
  assert.equal(final.outcomes.calls[0].outcome.failure.code, 'workbench.worker_outcomes');
  assert(Buffer.byteLength(JSON.stringify(final)) <= 1024 * 1024);
});
