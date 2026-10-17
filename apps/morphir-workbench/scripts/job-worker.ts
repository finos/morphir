import type { WorkRequest } from '../browser/contracts.ts';
import type { Outcomes, SchemeJobPlan } from './job-contracts.ts';
import { parentPort, workerData } from 'node:worker_threads';

// Each thread owns one compiled pipeline instance and one request. No gateway
// session state, credentials or core handler crosses the worker boundary.
const port = parentPort;
if (!port) throw new Error('An owned worker port is required');
let policyJob = false;
const scope: { postMessage(value: { result?: { terminalOutcomes?: Outcomes; jobPlan?: SchemeJobPlan } }): void; onmessage?: (event: { data: { id: number; request: WorkRequest } }) => void } = {
  postMessage(value) {
    const admitted = value?.result?.terminalOutcomes ? { id: 1, result: { terminalOutcomes: value.result.terminalOutcomes,
      ...(policyJob && value.result.jobPlan ? { jobPlan: value.result.jobPlan } : {}) } } : { id: 1, result: null };
    const source = JSON.stringify(admitted);
    // Policy jobs carry a separately bounded 1 MiB selected boundary beside the
    // existing 1 MiB outcomes. The frozen worker framing keeps its original cap.
    if (Buffer.byteLength(source) <= (policyJob ? 3 : 1) * 1024 * 1024) port.postMessage(admitted);
    else port.postMessage({ id: 1, result: null });
  },
};
Object.assign(globalThis, { self: scope });
const loaded = import((workerData as { module: string }).module);
port.once('message', async data => {
  try {
    await loaded;
    policyJob = data?.request?.operation === 'evaluate-scheme-job';
    if (typeof scope.onmessage !== 'function') throw new Error('Missing pipeline listener');
    scope.onmessage({ data });
  } finally { port.close(); }
});
