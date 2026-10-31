// The browser Web Worker feasibility proof (BRW-1 of host-extensions-as-workers). It runs the proof program of
// pkgs/morphir-host/worker/browser/proof twice with the same product session code: on Node, where each guest runs in
// a worker thread, and in Chromium, where each guest runs in a Web Worker. It checks that describe, compile and
// generate give the same results, that a runaway guest's Web Worker is terminated at its deadline while the page stays
// responsive, and that a browser host refuses process pins without starting a worker. `mise run test:wasm-workers --
// --target js --scope browser` builds the inputs and runs it. The receipt (argument 1) keeps the measured values.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import type {AddressInfo} from 'node:net';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {chromium, type Browser, type Worker} from 'playwright';

type Proof = {
  platform: string;
  moonbit: Guest;
  python: Guest;
  runaway?: {ending: string; stop: {status: string; method: string}; elapsedMs: number};
  refusals?: {code: string; message: string; supported: boolean; workerStopped: boolean}[];
  error?: string;
};
type Guest = {results: Record<string, unknown>; measured: Record<string, number>};
type ProofInput = {
  platform: 'browser' | 'node'; entry: string; portable: Uint8Array; python: Uint8Array; callMs?: number;
  measureMemory?: () => Promise<number> | number; mark?: (name: string) => void; done: (text: string) => void;
};
declare global {
  var morphirWorkerProof: ProofInput | undefined;
  var proofMark: ((name: string) => Promise<void>) | undefined;
  var proofMemory: (() => Promise<number>) | undefined;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set: run mise run test:wasm-workers -- --target js --scope browser`);
  return resolve(value);
}

const receiptPath = resolve(process.argv[2] ?? '.dev/browser-workers/receipt.json');
const files = {
  portable: required('MORPHIR_PORTABLE_GUEST'),
  python: resolve(required('MORPHIR_PYTHON_EXTENSIONS'), '0.4.2/morphir-python-binding-0.4.2.wasm'),
  threadEntry: required('MORPHIR_WASM_THREAD_ENTRY'),
  browserEntry: required('MORPHIR_BROWSER_WORKER_ENTRY'),
  proof: required('MORPHIR_BROWSER_WORKER_PROOF'),
};
const portable = new Uint8Array(await readFile(files.portable));
const python = new Uint8Array(await readFile(files.python));
const callMs = 300;

// The resident memory of Chromium's renderer processes, which run the page and its dedicated Web Workers, from the
// process IDs that the DevTools protocol reports, or -1 where `ps` cannot read them.
async function rendererBytes(browser: Browser): Promise<number> {
  const session = await browser.newBrowserCDPSession();
  try {
    const {processInfo} = await session.send('SystemInfo.getProcessInfo') as {processInfo: {type: string; id: number}[]};
    let total = 0;
    for (const item of processInfo.filter(item => item.type === 'renderer')) {
      total += Number(execFileSync('ps', ['-o', 'rss=', '-p', String(item.id)], {encoding: 'utf8'}).trim()) * 1024;
    }
    return total > 0 ? total : -1;
  } catch { return -1; } finally { await session.detach(); }
}

const sha256 = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');

async function compileMs(bytes: Uint8Array<ArrayBuffer>): Promise<number> {
  const started = performance.now();
  await WebAssembly.compile(bytes);
  return performance.now() - started;
}

// The Node run: the proof program with the worker-thread launcher.
process.stderr.write('worker-proof: Node worker threads\n');
const nodeBaselineBytes = process.memoryUsage().rss;
const nodeCompile = {portableMs: await compileMs(portable), pythonMs: await compileMs(python)};
const node = await new Promise<Proof>((done, failed) => {
  globalThis.morphirWorkerProof = {platform: 'node', entry: files.threadEntry, portable, python,
    measureMemory: () => process.memoryUsage().rss, done: text => done(JSON.parse(text) as Proof)};
  import(pathToFileURL(files.proof).href).catch(failed);
});
assert.equal(node.error, undefined, `the Node proof failed: ${node.error}`);

// The browser run: the same program with the Web Worker launcher. Memory is the renderer's resident memory, measured
// by the driver: the page's own memory API is not available in headless Chromium.
const page = '<!doctype html><meta charset="utf-8"><title>Morphir browser worker proof</title>';
const served: Record<string, [string, string]> = {
  '/': ['text/html', ''], '/entry.js': ['text/javascript', files.browserEntry], '/proof.js': ['text/javascript', files.proof],
  '/portable.wasm': ['application/wasm', files.portable], '/python.wasm': ['application/wasm', files.python],
};
const server = createServer(async (request, response) => {
  const route = served[new URL(request.url ?? '/', 'http://localhost').pathname];
  if (!route) { response.statusCode = 404; response.end(); return; }
  response.setHeader('Content-Type', route[0]);
  response.end(route[1] === '' ? page : await readFile(route[1]));
});
await new Promise<void>(done => server.listen(0, '127.0.0.1', done));
const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
const browser = await chromium.launch({headless: true});
try {
  process.stderr.write(`worker-proof: Chromium ${browser.version()} Web Workers\n`);
  const tab = await browser.newPage();
  const workers: {url: string; closed: boolean}[] = [];
  tab.on('worker', (worker: Worker) => {
    const record = {url: worker.url(), closed: false};
    workers.push(record);
    worker.on('close', () => { record.closed = true; });
  });
  const marks: Record<string, {started: number; open: number}> = {};
  await tab.exposeFunction('proofMark', (name: string) => {
    marks[name] = {started: workers.length, open: workers.filter(worker => !worker.closed).length};
  });
  await tab.exposeFunction('proofMemory', () => rendererBytes(browser));
  await tab.goto(`${origin}/`);
  const rendererBaselineBytes = await rendererBytes(browser);
  const run = await tab.evaluate(async ({callMs}) => {
    const bytes = async (path: string) => new Uint8Array(await (await fetch(path)).arrayBuffer());
    const [portable, python] = [await bytes('/portable.wasm'), await bytes('/python.wasm')];
    const timed = async (module: Uint8Array<ArrayBuffer>) => { const started = performance.now(); await WebAssembly.compile(module);
      return performance.now() - started; };
    const compile = {portableMs: await timed(portable), pythonMs: await timed(python)};
    // A timer on the page: its largest gap shows whether a guest blocked the page.
    const ticks: number[] = [];
    let watching = false;
    const timer = setInterval(() => { if (watching) ticks.push(performance.now()); }, 10);
    const measure = async () => await globalThis.proofMemory?.() ?? -1;
    const text = await new Promise<string>((done, failed) => {
      globalThis.morphirWorkerProof = {platform: 'browser', entry: new URL('/entry.js', location.href).href, portable,
        python, callMs, measureMemory: measure, done,
        mark: name => { if (name === 'runaway-start') watching = true; if (name === 'runaway-end') watching = false;
          void globalThis.proofMark?.(name); }};
      const script = document.createElement('script');
      script.src = '/proof.js';
      script.onerror = () => failed(new Error('the proof program did not load'));
      document.head.append(script);
    });
    clearInterval(timer);
    let gap = 0;
    for (let index = 1; index < ticks.length; index++) gap = Math.max(gap, ticks[index]! - ticks[index - 1]!);
    return {text, compile, ticks: ticks.length, gap};
  }, {callMs});
  const proof = JSON.parse(run.text) as Proof;
  assert.equal(proof.error, undefined, `the browser proof failed: ${proof.error}`);
  const answered = performance.now();
  assert.equal(await tab.evaluate(() => 1 + 1), 2);
  const answerMs = performance.now() - answered;
  // Termination is immediate; Playwright reports the closed worker shortly after.
  for (let wait = 0; wait < 40 && workers.some(worker => !worker.closed); wait++) await new Promise(done => setTimeout(done, 50));

  // Scenario: MoonBit and Python guests in a browser give the same results as on Node.
  assert.deepEqual(proof.moonbit.results, node.moonbit.results, 'the MoonBit guest differs between Node and the browser');
  assert.deepEqual(proof.python.results, node.python.results, 'the Python extension differs between Node and the browser');
  // The results are real: the compiled IR names the source's declarations and the generators returned files.
  const text = (value: unknown) => JSON.stringify(value);
  assert.match(text(proof.moonbit.results.compile), /"model"/);
  assert.match(text(proof.python.results.compile), /"amount"/);
  assert.match(text(proof.python.results.generate), /Approved/);
  assert.ok(text(proof.moonbit.results.generate).length > 100, 'the MoonBit generate result is empty');
  for (const guest of [proof.moonbit, proof.python]) {
    assert.deepEqual(guest.results.generateStop, {status: 'Exited(code=0)', method: 'ThreadTermination'});
  }
  // Scenario: runaway guest in a browser. The deadline ends the call, the Web Worker is terminated, and the page
  // kept running its timer while the guest looped.
  assert.ok(proof.runaway, 'no runaway result');
  assert.equal(proof.runaway.ending, 'Deadline');
  assert.deepEqual(proof.runaway.stop, {status: 'Terminated(Deadline)', method: 'ThreadTermination'});
  assert.ok(proof.runaway.elapsedMs >= callMs, `the deadline ended the call after ${proof.runaway.elapsedMs} ms`);
  assert.ok(run.ticks > 5 && run.gap < 250, `the page timer stalled: ${run.ticks} ticks, largest gap ${run.gap} ms`);
  const runawayStart = marks['runaway-start'], runawayEnd = marks['runaway-end'];
  assert.ok(runawayStart && runawayEnd, 'the runaway marks were not recorded');
  assert.equal(runawayEnd.started - runawayStart.started, 1, 'the runaway guest did not run in one Web Worker');
  assert.ok(workers.every(worker => worker.closed), 'a Web Worker is still running');
  // Scenario: browser host and a process artifact. Each process pin is refused with runtime_unavailable and no Web
  // Worker starts.
  assert.ok(proof.refusals && proof.refusals.length === 2, 'no refusals');
  for (const refusal of proof.refusals) {
    assert.equal(refusal.code, 'extension.runtime_unavailable');
    assert.match(refusal.message, /wasm/);
    assert.equal(refusal.supported, false);
    assert.equal(refusal.workerStopped, false);
  }
  const refusalStart = marks['refusal-start'], refusalEnd = marks['refusal-end'];
  assert.ok(refusalStart && refusalEnd && refusalEnd.started === refusalStart.started, 'a process pin started a worker');

  const receipt = {
    profile: 'morphir/browser-worker-proof', contractVersion: '0.1.0', state: 'succeeded',
    browser: {name: 'chromium', version: browser.version(), headless: true},
    node: process.version, platform: process.platform, architecture: process.arch,
    modules: {portableBytes: portable.length, pythonBytes: python.length},
    results: {moonbitSha256: sha256(proof.moonbit.results), pythonSha256: sha256(proof.python.results)},
    measured: {
      node: {baselineRssBytes: nodeBaselineBytes, compile: nodeCompile, moonbit: node.moonbit.measured, python: node.python.measured},
      browser: {rendererBaselineRssBytes: rendererBaselineBytes, compile: run.compile, moonbit: proof.moonbit.measured, python: proof.python.measured,
        runaway: {elapsedMs: proof.runaway.elapsedMs, callMs, pageTimerTicks: run.ticks, largestTimerGapMs: run.gap,
          pageAnswerMs: answerMs},
        webWorkers: {started: workers.length, running: workers.filter(worker => !worker.closed).length}},
    },
    scenarios: ['MoonBit and Python guests in a browser', 'Runaway guest in a browser',
      'Browser host and a process artifact'],
  };
  await mkdir(dirname(receiptPath), {recursive: true});
  await writeFile(receiptPath, JSON.stringify(receipt, null, 2) + '\n');
  await writeFile(resolve(dirname(receiptPath), 'results.json'), JSON.stringify({node, browser: proof}, null, 2) + '\n');
  process.stderr.write(`worker-proof: every Browser Web Workers scenario passed; receipt ${receiptPath}\n`);
} finally {
  await browser.close();
  await new Promise(done => server.close(done));
}
