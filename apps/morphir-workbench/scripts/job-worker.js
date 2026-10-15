import { parentPort, workerData } from 'node:worker_threads';

// Each thread owns one compiled pipeline instance and one request. No gateway
// session state, credentials or core handler crosses the worker boundary.
globalThis.self = {
  postMessage(value) {
    const admitted = value?.result?.terminalOutcomes ? { id: 1, result: { terminalOutcomes: value.result.terminalOutcomes } } : { id: 1, result: null };
    const source = JSON.stringify(admitted);
    if (Buffer.byteLength(source) <= 1024 * 1024) parentPort.postMessage(admitted);
    else parentPort.postMessage({ id: 1, result: null });
  },
};
const loaded = import(workerData.module);
parentPort.once('message', async data => {
  try {
    await loaded;
    if (typeof self.onmessage !== 'function') throw new Error('Missing pipeline listener');
    self.onmessage({ data });
  } finally { parentPort.close(); }
});
