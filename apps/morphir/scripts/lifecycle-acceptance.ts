import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, normalize} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {headlessEnvironment} from './headless-environment.ts';

type LifecycleReceipt = {target: string; request: string; command: string; code: number; signal: null; diagnosticRecords: number};
type LifecycleCase = {request: 'cancel-file' | 'SIGINT' | 'SIGQUIT' | 'SIGTERM'; command: 'worksheet' | 'notebook' | 'connected'; code: 130 | 131 | 143; input?: 'empty-idle'};

function gcHostFixture(root: string, mode: 'normal' | 'transient-file' | 'missing-registration' | 'missing-clock' | 'failed-cleanup' = 'normal') {
  const ready = join(root, 'command-ready');
  const audit = join(root, 'registration.ndjson');
  const preload = join(root, 'observe-host.mjs');
  writeFileSync(preload, `
import {Worker} from 'node:worker_threads';
import {appendFileSync,writeFileSync} from 'node:fs';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {normalize} from 'node:path';
const mode=${JSON.stringify(mode)};
if(mode==='transient-file') {
  const lstat=fs.lstatSync;
  fs.lstatSync=function(path,...args) {
    const value=lstat(path,...args);
    if(normalize(String(path))===normalize(${JSON.stringify(join(root, 'stop.flag'))})) fs.unlinkSync(path);
    return value;
  };
  syncBuiltinESMExports();
}
const emit=Worker.prototype.emit;
Worker.prototype.emit=function(event,...args) {
  if(event==='message' && args[0]?.type==='morphir:stdin') writeFileSync(${JSON.stringify(ready)},'reading');
  return emit.call(this,event,...args);
};
const instantiate=WebAssembly.instantiate;
WebAssembly.instantiate=async function(module,imports,...rest) {
  const host=imports?.morphir_host_v1;
  if(host) {
    const request=host.request;
    host.request=(op,a,b)=>{
      let result;
      if(op.text==='register_cancel_file' && mode==='missing-registration') result={text:JSON.stringify({error:'Unsupported host operation'})};
      else if(op.text==='register_cancel_file' && a.text==='' && mode==='failed-cleanup') result={text:JSON.stringify({error:'Cleanup refused'})};
      else if(op.text==='utc_milliseconds' && mode==='missing-clock') result={text:JSON.stringify({error:'Clock unavailable'})};
      else result=request(op,a,b);
      if(op.text==='register_cancel_file') appendFileSync(${JSON.stringify(audit)},JSON.stringify({path:a.text,response:JSON.parse(result.text)})+String.fromCharCode(10));
      return result;
    };
  }
  return instantiate.call(WebAssembly,module,imports,...rest);
};
`);
  return {ready, audit, preload};
}

/** Real process stops while stdin remains open, using the installed host adapter. */
export async function exerciseHostLifecycle(target: string, binary: string, launcher?: string): Promise<LifecycleReceipt[]> {
  if (target !== 'native' && target !== 'js' && target !== 'wasm-gc') return [];
  const embedded = target === 'wasm-gc';
  const cases: LifecycleCase[] = embedded
    ? [{request: 'cancel-file', command: 'worksheet', code: 130, input: 'empty-idle'},
       {request: 'cancel-file', command: 'worksheet', code: 130},
       ...(process.platform === 'win32' ? [] : [{request: 'SIGINT', command: 'notebook', code: 130, input: 'empty-idle'} as const])]
    : process.platform === 'win32'
    ? [{request: 'cancel-file', command: 'worksheet', code: 130}]
    : [{request: 'SIGINT', command: 'worksheet', code: 130},
       {request: 'SIGQUIT', command: 'worksheet', code: 131},
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
      writeFileSync(join(root, 'morphir.toml'), '[workspace]\nmembers=[]\n[logging]\nlevel="debug"\n' +
        (embedded ? '' : '[logging.file]\nenabled=true\nformat="json-lines"\n'));
      const ready = join(root, 'command-ready');
      const audit = join(root, 'registration.ndjson');
      const preload = join(root, 'observe-host.mjs');
      if (embedded) gcHostFixture(root, item.request === 'cancel-file' && item.input === 'empty-idle' ? 'transient-file' : 'normal');
      let args: string[];
      if (item.command === 'connected') {
        const helper = join(root, 'waiting-helper.mjs');
        writeFileSync(join(root, 'input.scm'), '(define answer 42)');
        writeFileSync(helper, `import {writeFileSync} from 'node:fs';export async function connectedCommand(config,core,interrupted){writeFileSync(${JSON.stringify(ready)},'ready');while(!interrupted())await new Promise(resolve=>setTimeout(resolve,10));return {code:130,report:{profile:'morphir/cli/connected-command',contractVersion:'0.1.0',observation:'cancelled',completedAt:Date.now()}};}\n`);
        args = ['connected', 'connect', join(root, 'input.scm'), '--provider', 'workbench-http', '--connection', 'controlled', '--connected-helper', helper];
      } else args = item.command === 'notebook' ? ['notebook', 'export', '-', '--evaluate', '-o', 'cancelled.ipynb'] : ['worksheet', '-'];
      args.push('--json', '--isolated', '--discovery-boundary', '.');
      const cancel = join(root, 'stop.flag');
      if (item.request === 'cancel-file') args.push('--cancel-file', cancel);
      const program = target === 'native' ? binary : process.execPath;
      const prefix = target === 'native' ? [] : embedded
        ? ['--import', pathToFileURL(preload).href, fileURLToPath(new URL('../../../pkgs/morphir-host/runners/wasm.mjs', import.meta.url)), binary]
        : [launcher ?? binary];
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
        if (item.command === 'connected' || item.input === 'empty-idle') {
          const until = Date.now() + 7000;
          while (!existsSync(ready) && child.exitCode === null && Date.now() < until) {
            await new Promise(resolve => setTimeout(resolve, 10));
          }
          assert.ok(existsSync(ready), `Command did not reach its owned input/helper boundary: ${stdout}\n${stderr}`);
        } else {
          // Fill beyond the supported hosts' stdin pipe capacity, then await
          // its backpressure callback. The command must read to make progress.
          // Exactly one MiB stays within worksheet's input limit. Keep the pipe
          // open so the command remains in its next read until cancellation.
          await Promise.race([
            new Promise<void>((resolve, reject) => {
              child.stdin.write(Buffer.alloc(1048576, 0x20), error => error ? reject(error) : resolve());
            }),
            closed.then(() => { throw new Error(`Command exited before reading stdin: ${stdout}\n${stderr}`); }),
          ]);
        }
        if (item.request === 'cancel-file') writeFileSync(cancel, 'stop');
        else child.kill(item.request as NodeJS.Signals);
        result = await closed;
      } finally {
        clearTimeout(deadline); child.stdin.destroy();
        if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
      }
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
      const records = embedded
        ? stderr.split(/\r?\n/).filter(line => /^\d{4}-\d{2}-\d{2}T/.test(line)).map(line => ({
          timestamp: line.slice(0, 24),
          category: line.match(/\] ([^:]+):/)?.[1],
          message: line.slice(line.indexOf(': ', 24) + 2),
        }))
        : readdirSync(logs).filter(name => name.startsWith('morphir-diagnostics')).flatMap(name => readFileSync(join(logs, name), 'utf8').trim().split('\n').map(line => JSON.parse(line)));
      assert.ok(records.some(record => record.category === 'morphir.configuration'));
      assert.ok(records.some(record => record.category === `morphir.cli.${item.command === 'notebook' ? 'notebook.export' : item.command === 'connected' ? 'connected.connect' : 'worksheet'}` && record.message.startsWith('Starting')));
      assert.ok(records.some(record => record.message.startsWith('Finished')), JSON.stringify(records));
      for (const record of records) {
        assert.match(record.timestamp, /^\d{4}-\d\d-\d\dT.*Z$/);
        if (!embedded) {
          assert.equal(typeof record.properties, 'object');
          assert.ok(!Array.isArray(record.properties));
        }
      }
      assert.match(stderr, /morphir\.configuration/);
      if (embedded) {
        const registrations = existsSync(audit) ? readFileSync(audit, 'utf8').trim().split('\n').map(line => JSON.parse(line)) : [];
        assert.deepEqual(registrations.map(record => ({...record, path: record.path === '' ? '' : normalize(record.path)})), item.request === 'cancel-file' ? [{path: normalize(cancel), response: {value: true}}, {path: '', response: {value: true}}] : [], 'The selected file is registered and unconditionally cleared');
        if (item.request === 'cancel-file' && item.input === 'empty-idle') assert.equal(existsSync(cancel), false, 'An observed stop remains cancelled after the marker disappears');
        assert.equal(existsSync(logs), false, 'Portable diagnostics use stderr, without rolling files');
      }
      receipts.push({target, request: item.request, command: item.command, code: result.code!, signal: null, diagnosticRecords: records.length});
    } finally { rmSync(root, {recursive: true, force: true}); }
  }
  if (target === 'js') receipts.push(exercisePrestartQuit(binary, launcher));
  if (embedded) exerciseGcRegistrationFailures(binary);
  console.log(`CLI hosted lifecycle ${target}: ${receipts.length} stop scenarios, single JSON results and drained diagnostics passed.`);
  return receipts;
}

/** A retained parent Quit before the first hook still gets one owned result. */
export function exercisePrestartQuit(binary: string, launcher?: string): LifecycleReceipt {
  const root = mkdtempSync(join(tmpdir(), 'morphir-prestart-quit-'));
  try {
    const preload = join(root, 'quit-before-host.mjs');
    writeFileSync(preload, `import {isMainThread,workerData} from 'node:worker_threads';
if(!isMainThread && workerData?.morphirInterrupt instanceof SharedArrayBuffer) Atomics.store(new Int32Array(workerData.morphirInterrupt),0,3);
`);
    const result = spawnSync(process.execPath, ['--import', pathToFileURL(preload).href,
      launcher ?? binary, 'worksheet', 'must-not-be-read.scm', '--json', '--isolated', '--discovery-boundary', '.'], {
      cwd: root, env: headlessEnvironment(root), encoding: 'utf8', timeout: 10000,
    });
    assert.equal(result.signal, null, result.stdout + result.stderr);
    assert.equal(result.status, 131, result.stdout + result.stderr);
    const report = JSON.parse(result.stdout);
    assert.ok(report.completion?.status === 'cancelled' || report.error === 'Cancelled', result.stdout);
    assert.ok(!result.stderr.includes('Starting worksheet'), 'A retained Quit skips the command hook');
    return {target: 'js', request: 'Quit-before-start', command: 'worksheet', code: 131, signal: null, diagnosticRecords: 0};
  } finally { rmSync(root, {recursive: true, force: true}); }
}

function exerciseGcRegistrationFailures(binary: string) {
  const root = mkdtempSync(join(tmpdir(), 'morphir-gc-registration-'));
  try {
    const env = headlessEnvironment(root);
    const runner = fileURLToPath(new URL('../../../pkgs/morphir-host/runners/wasm.mjs', import.meta.url));
    writeFileSync(join(root, 'morphir.toml'), '[workspace]\nmembers=[]\n');
    writeFileSync(join(root, 'input.scm'), '42');
    const cancel = join(root, 'stop.flag');
    const args = ['worksheet', 'input.scm', '--json', '--isolated', '--discovery-boundary', '.', '--log-level', 'debug', '--cancel-file', cancel];
    for (const [mode, status, error] of [
      ['missing-registration', 2, 'cancellation.cancel_file_registration_unavailable'],
      ['missing-clock', 2, 'diagnostics.utc_clock_unavailable'],
      ['failed-cleanup', 1, 'cancellation.cancel_file_cleanup_failed'],
    ] as const) {
      const {preload, audit, ready} = gcHostFixture(root, mode);
      if (existsSync(audit)) rmSync(audit);
      const result = spawnSync(process.execPath, ['--import', pathToFileURL(preload).href, runner, binary, ...args], {cwd: root, env, encoding: 'utf8', timeout: 10000});
      assert.equal(result.status, status, result.stdout + result.stderr);
      const report = JSON.parse(result.stdout);
      if (mode === 'failed-cleanup') {
        assert.equal(report.completion.status, 'returned', result.stdout);
        assert.match(result.stderr, new RegExp(error.replaceAll('.', '\\.')));
      } else {
        assert.equal(report.successful, false);
        assert.equal(report.error, error);
        assert.equal(existsSync(ready), false, 'Capability refusal never starts input');
        assert.ok(!result.stderr.includes('Starting worksheet'));
      }
      const registrations = readFileSync(audit, 'utf8').trim().split('\n').map(line => JSON.parse(line));
      assert.equal(normalize(registrations[0].path), normalize(cancel));
      assert.equal(registrations.length, mode === 'missing-registration' ? 1 : 2);
      if (mode !== 'missing-registration') assert.equal(registrations[1].path, '', 'Startup and completion paths both attempt cleanup');
    }
    console.log('GC cancel-file registration: unsupported host, pre-start clock failure and post-result cleanup failure preserve channels and cleanup ownership.');
  } finally { rmSync(root, {recursive: true, force: true}); }
}
