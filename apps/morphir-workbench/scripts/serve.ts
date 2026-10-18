import type { AddressInfo } from 'node:net';
import { createWorkbenchServer } from './server.ts';
import { createExecutionProvider } from './execution-provider.ts';

const host = process.env.MORPHIR_WORKBENCH_HOST_URL;
if (process.env.MORPHIR_WORKBENCH_EXECUTIONS === '1' && !host) throw new Error('MORPHIR_WORKBENCH_EXECUTIONS requires MORPHIR_WORKBENCH_HOST_URL.');
const executions = process.env.MORPHIR_WORKBENCH_EXECUTIONS === '1' ? await createExecutionProvider() : null;
const server = createWorkbenchServer({ host, executions });
server.listen(Number(process.env.MORPHIR_WORKBENCH_PORT ?? 5173), '127.0.0.1', () => {
  console.log(`Morphir Workbench: http://127.0.0.1:${(server.address() as AddressInfo).port}`);
});
