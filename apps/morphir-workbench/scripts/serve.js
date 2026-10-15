import { createWorkbenchServer } from './server.js';
import { createJobProvider } from './job-provider.js';

const host = process.env.MORPHIR_WORKBENCH_HOST_URL;
if (process.env.MORPHIR_WORKBENCH_JOBS === '1' && !host) throw new Error('MORPHIR_WORKBENCH_JOBS requires MORPHIR_WORKBENCH_HOST_URL.');
const jobs = process.env.MORPHIR_WORKBENCH_JOBS === '1' ? await createJobProvider() : null;
const server = createWorkbenchServer({ host, jobs });
server.listen(Number(process.env.MORPHIR_WORKBENCH_PORT ?? 5173), '127.0.0.1', () => {
  console.log(`Morphir Workbench: http://127.0.0.1:${server.address().port}`);
});
