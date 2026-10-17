import type { WorkRequest } from '../browser/contracts.ts';
import type { Outcomes } from './job-contracts.ts';
import { parentPort, workerData } from 'node:worker_threads';

// Each thread owns one compiled pipeline instance and one request. No gateway
// session state, credentials or core handler crosses the worker boundary.
const port = parentPort;
if (!port) throw new Error('An owned worker port is required');
const scope: { postMessage(value: { result?: { terminalOutcomes?: Outcomes } }): void; onmessage?: (event: { data: { id: number; request: WorkRequest } }) => void } = {
  postMessage(value) {
    const admitted = value?.result?.terminalOutcomes ? { id: 1, result: { terminalOutcomes: value.result.terminalOutcomes } } : { id: 1, result: null };
    const source = JSON.stringify(admitted);
    if (Buffer.byteLength(source) <= 1024 * 1024) port.postMessage(admitted);
    else port.postMessage({ id: 1, result: null });
  },
};
Object.assign(globalThis, { self: scope });
const loaded = import((workerData as { module: string }).module);
port.once('message', async data => {
  try {
    await loaded;
    if (typeof scope.onmessage !== 'function') throw new Error('Missing pipeline listener');
    scope.onmessage({ data });
  } finally { port.close(); }
});
