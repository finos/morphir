import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {headlessEnvironment} from './headless-environment.ts';

type LifecycleReceipt = {target: string; request: string; command: string; code: number; signal: null; diagnosticRecords: number};

/** Real process stops while stdin remains open, using the installed host adapter. */
export async function exerciseHostLifecycle(target: string, binary: string, launcher?: string): Promise<LifecycleReceipt[]> {
  if (target !== 'native' && target !== 'js') return [];
  const cases = process.platform === 'win32'
    ? [{request: 'cancel-file', command: 'worksheet', code: 130}]
    : [{request: 'SIGINT', command: 'worksheet', code: 130},
       {request: 'SIGTERM', command: 'worksheet', code: 143},
       {request: 'SIGTERM', command: 'notebook', code: 143},
       {request: 'cancel-file', command: 'worksheet', code: 130}];
  if (target === 'js') {
    cases.push({request: 'cancel-file', command: 'connected', code: 130});
    if (process.platform !== 'win32') cases.push({request: 'SIGTERM', command: 'connected', code: 143});
  }
  const receipts: LifecycleReceipt[] = [];
  for (const item of cases) {
    const root = mkdtempSync(join(tmpdir(), 'morphir-host-lifecycle-'));
    try {
      const env = headlessEnvironment(root);
      writeFileSync(join(root, 'morphir.toml'), '[workspace]\nmembers=[]\n[logging]\nlevel="debug"\n[logging.file]\nenabled=true\nformat="json-lines"\n');
      let args: string[];
      if (item.command === 'connected') {
        const helper = join(root, 'waiting-helper.mjs');
        writeFileSync(join(root, 'input.scm'), '(define answer 42)');
        writeFileSync(helper, `export async function connectedCommand(config,core,interrupted){while(!interrupted())await new Promise(resolve=>setTimeout(resolve,10));return {code:130,report:{profile:'morphir/cli/connected-command',contractVersion:'0.1.0',observation:'cancelled',completedAt:Date.now()}};}\n`);
        args = ['connected', 'connect', join(root, 'input.scm'), '--provider', 'workbench-http', '--connection', 'controlled', '--connected-helper', helper];
      } else args = item.command === 'notebook' ? ['notebook', 'export', '-', '--evaluate', '-o', 'cancelled.ipynb'] : ['worksheet', '-'];
      args.push('--json', '--isolated', '--discovery-boundary', '.');
      const cancel = join(root, 'stop.flag');
      if (item.request === 'cancel-file') args.push('--cancel-file', cancel);
      const program = target === 'native' ? binary : process.execPath;
      const prefix = target === 'native' ? [] : [launcher ?? binary];
      const child = spawn(program, [...prefix, ...args], {cwd: root, env, stdio: ['pipe', 'pipe', 'pipe']});
      let stdout = '', stderr = '';
      child.stdout.setEncoding('utf8').on('data', chunk => { stdout += chunk; });
      child.stderr.setEncoding('utf8').on('data', chunk => { stderr += chunk; });
      child.stdin.on('error', error => { if ((error as NodeJS.ErrnoException).code !== 'EPIPE') throw error; });
      const closed = new Promise<{code: number | null; signal: NodeJS.Signals | null}>((resolve, reject) => {
        child.once('error', reject);
        child.once('close', (code, signal) => resolve({code, signal}));
      });
      const deadline = setTimeout(() => child.kill('SIGKILL'), 8000);
      let result: Awaited<typeof closed>;
      try {
        // Retain the caller's open stdin. The final receipt proves the command
        // entered its host, produced its cancellation result and drained logs.
        await new Promise(resolve => setTimeout(resolve, 350));
        if (item.request === 'cancel-file') writeFileSync(cancel, 'stop');
        else child.kill(item.request as NodeJS.Signals);
        result = await closed;
      } finally { clearTimeout(deadline); child.stdin.destroy(); }
      assert.equal(result.signal, null, `${target} ${item.request}: ${stdout}\n${stderr}`);
      assert.equal(result.code, item.code, `${target} ${item.request}: ${stdout}\n${stderr}`);
      const report = JSON.parse(stdout);
      if (item.command === 'notebook') {
        assert.equal(report.error.code, 'notebook.cancelled');
        assert.equal(report.exitCode, item.code);
        assert.equal(existsSync(join(root, 'cancelled.ipynb')), false);
      } else if (item.command === 'connected') assert.equal(report.observation, 'cancelled');
      else assert.ok(report.completion?.status === 'cancelled' || report.error === 'Cancelled', stdout);
      const logs = join(root, '.morphir/logs');
      const files = readdirSync(logs).filter(name => name.startsWith('morphir-diagnostics'));
      const records = files.flatMap(name => readFileSync(join(logs, name), 'utf8').trim().split('\n').map(line => JSON.parse(line)));
      assert.ok(records.some(record => record.category === 'morphir.configuration'));
      assert.ok(records.some(record => record.category === `morphir.cli.${item.command === 'notebook' ? 'notebook.export' : item.command === 'connected' ? 'connected.connect' : 'worksheet'}` && record.message.startsWith('Starting')));
      assert.ok(records.some(record => record.message.startsWith('Finished')), JSON.stringify(records));
      for (const record of records) {
        assert.match(record.timestamp, /^\d{4}-\d\d-\d\dT.*Z$/);
        assert.equal(typeof record.properties, 'object');
        assert.ok(!Array.isArray(record.properties));
      }
      assert.match(stderr, /morphir\.configuration/);
      receipts.push({target, request: item.request, command: item.command, code: result.code!, signal: null, diagnosticRecords: records.length});
    } finally { rmSync(root, {recursive: true, force: true}); }
  }
  console.log(`CLI hosted lifecycle ${target}: ${receipts.length} real stops, single JSON results and drained diagnostic files passed.`);
  return receipts;
}
