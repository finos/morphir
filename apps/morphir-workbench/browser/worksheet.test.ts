import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ConnectedAdapter, LocalAdapter } from './transport.ts';
import { NativeAdapter } from './native-session.ts';
import { WorksheetCapture } from './worksheet.ts';
import { worksheetCore } from './native-test-fixture.ts';
import type { WorkRequest, WorkerPort } from './contracts.ts';

globalThis.morphirWorkbenchWorksheet = worksheetCore();
const request = (source = '7'): WorkRequest => ({ operation: 'worksheet', source,
  worksheetRequest: JSON.stringify({ profile: 'morphir/workbench/worksheet', contractVersion: '0.1.0-draft.1',
    source: { id: 'worksheet-source', revision: 4, text: source } }) });
const report = (input = request()) => JSON.stringify({ ...JSON.parse(input.worksheetRequest!),
  observations: [{ id: 'form-0', range: { start: 0, end: 1 }, expression: '7', preview: '7',
    outcome: { status: 'returned', value: { type: 'int', value: '7' } } }],
  completion: { status: 'returned', value: { type: 'unit' } }, diagnostic: null });

test('production worksheet boundary rejects forged captures and noncanonical evidence', () => {
  const capture = WorksheetCapture.from(request());
  assert.throws(() => capture.validate({ success: true, worksheetReport: report().replace('"revision":4', '"revision":5') }), /source_mismatch/);
  assert.throws(() => capture.validate({ success: true, worksheetReport: report().replace('"value":"7"', '"value":"07"') }), /invalid_report/);
  assert.throws(() => WorksheetCapture.from({ ...request(), source: '8' }), /source_mismatch/);
});

test('local worksheet captures before dispatch and settles once despite queued replies', async () => {
  let stops = 0;
  let posted: { id: number; request: WorkRequest };
  const worker: WorkerPort = { postMessage(message) { posted = message; }, terminate() { stops++; } };
  const adapter = new LocalAdapter(() => worker);
  const input = request();
  const pending = adapter.execute(input);
  input.source = '8';
  input.worksheetRequest = request('8').worksheetRequest;
  assert.equal(posted!.request.source, '7');
  worker.onmessage!({ data: { id: posted!.id, result: { success: true, worksheetReport: report() } } });
  const result = await pending;
  assert.equal(JSON.parse(result.worksheetReport!).source.text, '7');
  worker.onerror!();
  worker.onmessage!({ data: { id: posted!.id, result: { success: true, worksheetReport: report() } } });
  assert.equal(stops, 1);
});

test('worksheet cancellation, deadline and worker crash retain capture with no invented prefix', async () => {
  for (const reason of ['cancelled', 'timeout', 'worker-failed'] as const) {
    let stops = 0;
    const worker: WorkerPort = { postMessage() {}, terminate() { stops++; } };
    const adapter = new LocalAdapter(() => worker, reason === 'timeout' ? 5 : 15000);
    const input = request('(let loop () (loop))');
    const pending = adapter.execute(input);
    if (reason === 'cancelled') adapter.cancel();
    if (reason === 'worker-failed') worker.onerror!();
    const result = await pending;
    const terminal = JSON.parse(result.worksheetReport!);
    assert.equal(stops, 1);
    assert.deepEqual(terminal.source, JSON.parse(input.worksheetRequest!).source);
    assert.deepEqual(terminal.observations, []);
    assert.deepEqual(terminal.diagnostic, { stage: 'transport', range: null });
    assert.equal(terminal.completion.status, reason === 'cancelled' ? 'cancelled' : 'failed');
    if (reason !== 'cancelled') assert.equal(terminal.completion.failure.code, reason === 'timeout' ? 'worksheet.timeout' : 'worksheet.worker_failed');
  }
});

test('native and connected shells keep worksheet cancellation local', async () => {
  for (const shell of ['native', 'connected'] as const) {
    let stops = 0;
    let hostCalls = 0;
    const local = new LocalAdapter(() => ({ postMessage() {}, terminate() { stops++; } }));
    const adapter = shell === 'native'
      ? new NativeAdapter(local, async () => { hostCalls++; throw new Error('Unexpected native command'); })
      : new ConnectedAdapter({ async call() { hostCalls++; throw new Error('Unexpected RPC'); } },
        { protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'test', providers: [], initialSources: [] }, local);
    const pending = adapter.execute(request('(let loop () (loop))'));
    adapter.cancel();
    const result = await pending;
    assert.equal(JSON.parse(result.worksheetReport!).completion.status, 'cancelled');
    assert.equal(stops, 1);
    assert.equal(hostCalls, 0);
  }
});
