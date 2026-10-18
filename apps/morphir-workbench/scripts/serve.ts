import type { AddressInfo } from 'node:net';
import { createWorkbenchServer } from './server.ts';
import { createExecutionProvider } from './execution-provider.ts';

const host = process.env.MORPHIR_WORKBENCH_HOST_URL;
const mapping = process.env.MORPHIR_WORKBENCH_EXECUTIONS;
if (mapping && !['0', '1', 'capability-checks'].includes(mapping)) throw new Error('Unknown Workbench execution mapping.');
if ((mapping === '1' || mapping === 'capability-checks') && !host) throw new Error('MORPHIR_WORKBENCH_EXECUTIONS requires MORPHIR_WORKBENCH_HOST_URL.');
const executions = mapping === '1' || mapping === 'capability-checks'
  ? await createExecutionProvider({ mapping: mapping === 'capability-checks' ? 'capability-checks' : 'strict' }) : null;
const server = createWorkbenchServer({ host, executions });
server.listen(Number(process.env.MORPHIR_WORKBENCH_PORT ?? 5173), '127.0.0.1', () => {
  console.log(`Morphir Workbench: http://127.0.0.1:${(server.address() as AddressInfo).port}`);
});
