import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {Worker} from 'node:worker_threads';
import {createEmbeddedToolchain} from '../../pkgs/morphir-host/embedding/index.mts';
import {qualify} from './checks.mts';
import type {Probe} from './checks.mts';
import {qualifyResources, qualifyCallbacks} from './lifetime-checks.mts';
import type {ComponentFactory, Sessions, Callbacks} from './lifetime-checks.mts';

const directory = resolve(process.argv[2] ?? '.dev/wasm-host-qualification');
const component = new Uint8Array(await readFile(`${directory}/probe.component.wasm`));
const componentSha256 = createHash('sha256').update(component).digest('hex');
const fixtureHashes = Object.fromEntries(await Promise.all(['probe', 'resources', 'callbacks'].map(async name => [
  name, createHash('sha256').update(await readFile(`${directory}/${name}.component.wasm`)).digest('hex'),
])));
const entry = pathToFileURL(`${directory}/js/probe.component.js`).href;
const api: Probe = await import(entry);
const values = qualify(api);
const load = async (path: string) => WebAssembly.compile(await readFile(`${directory}/js/${path}`));
const resourcesFactory: ComponentFactory<{sessions: Sessions}> = await import(pathToFileURL(`${directory}/js/resources.component.js`).href);
const callbacksFactory: ComponentFactory<Callbacks> = await import(pathToFileURL(`${directory}/js/callbacks.component.js`).href);
const resources = await qualifyResources(async () => (await resourcesFactory.instantiate(load, {})).sessions);
const callbacks = await qualifyCallbacks(callbacksFactory, load);
assert.deepEqual(qualify(await import(`${entry}?fresh`)), values);
const trapping: Probe = await import(`${entry}?trap`);
assert.throws(() => trapping.trap(), WebAssembly.RuntimeError);
assert.equal((await import(`${entry}?after-trap`)).calls(), 0);

// This is a production embedding API check. Its run operation accepts core Wasm,
// not components. Capture that gap instead of claiming jco is already integrated.
const embedded = createEmbeddedToolchain(() => { throw new Error('Compiler must not be used for run'); });
try {
  await assert.rejects(embedded.request({operation: 'run', export: 'calls',
    artifact: {target: 'wasm', bytes: component}}),
  WebAssembly.CompileError);
} finally { embedded.dispose(); }

// Terminating an isolated worker is host cancellation. It is not an interrupt
// API inside the component, nor proof of production Workbench integration.
const worker = new Worker(`
  const {parentPort, workerData} = require('node:worker_threads');
  import(workerData).then(api => { parentPort.postMessage('ready'); api.spin(); });
`, {eval: true, workerData: `${entry}?spin`});
try {
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Component worker did not become ready')), 10000);
    worker.once('message', message => {
      clearTimeout(timer);
      if (message === 'ready') resolve(); else reject(new Error('Unexpected worker response'));
    });
    worker.once('error', error => { clearTimeout(timer); reject(error); });
    worker.once('exit', code => { clearTimeout(timer); reject(new Error(`Worker exited before cancellation: ${code}`)); });
  });
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(await worker.terminate(), 1);
} finally { await worker.terminate(); }

const report = {host: 'node', route: 'jco-generated-bindings', componentSha256, node: process.version, values,
  fixtureHashes, resources, callbacks,
  freshInstance: true, trap: true, workerTermination: true, productionCoreHostRejectsComponent: true};
await writeFile(`${directory}/node-report.json`, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
