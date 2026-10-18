import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import type {AddressInfo} from 'node:net';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve, sep} from 'node:path';
import {chromium} from 'playwright';
import type {Probe, qualify as CheckValues} from './checks.mts';
import type {ComponentFactory, Sessions, Callbacks, qualifyResources as CheckResources, qualifyCallbacks as CheckCallbacks} from './lifetime-checks.mts';
import type {createEmbeddedToolchain as CoreHost} from '../../pkgs/morphir-host/embedding/index.mts';

const directory = resolve(process.argv[2] ?? '.dev/wasm-host-qualification');
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url ?? '/', 'http://localhost').pathname;
    if (pathname === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><title>Component host qualification</title>');
      return;
    }
    const path = resolve(directory, '.' + decodeURIComponent(pathname));
    if (!path.startsWith(directory + sep)) throw new Error('Invalid fixture path');
    response.setHeader('Content-Type', path.endsWith('.wasm') ? 'application/wasm' : 'text/javascript');
    response.end(await readFile(path));
  } catch { response.statusCode = 404; response.end(); }
});
await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
let browser;
try {
  browser = await chromium.launch({headless: true});
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`);
  const result = await page.evaluate(async () => {
    const {qualify, qualifyResources, qualifyCallbacks, createEmbeddedToolchain} = await import(new URL('/checks.js', location.href).href) as {
      qualify: typeof CheckValues; qualifyResources: typeof CheckResources; qualifyCallbacks: typeof CheckCallbacks;
      createEmbeddedToolchain: typeof CoreHost;
    };
    const entry = new URL('/js/probe.component.js', location.href).href;
    const api: Probe = await import(entry);
    const values = qualify(api);
    const load = async (path: string) => WebAssembly.compileStreaming(fetch(new URL(`/js/${path}`, location.href)));
    const resourcesFactory: ComponentFactory<{sessions: Sessions}> = await import(new URL('/js/resources.component.js', location.href).href);
    const callbacksFactory: ComponentFactory<Callbacks> = await import(new URL('/js/callbacks.component.js', location.href).href);
    const resources = await qualifyResources(async () => (await resourcesFactory.instantiate(load, {})).sessions);
    const callbacks = await qualifyCallbacks(callbacksFactory, load);
    const freshValues = qualify(await import(`${entry}?fresh`));
    if (JSON.stringify(values) !== JSON.stringify(freshValues)) throw new Error('Fresh instance differs');
    let trapped = false;
    try { (await import(`${entry}?trap`)).trap(); }
    catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
    if (!trapped || (await import(`${entry}?after-trap`)).calls() !== 0) throw new Error('Trap isolation failed');

    const embedded = createEmbeddedToolchain(() => { throw new Error('Compilation not requested'); });
    let rejected = false;
    try {
      await embedded.request({operation: 'run', export: 'calls', artifact: {target: 'wasm',
        bytes: new Uint8Array(await (await fetch('/probe.component.wasm')).arrayBuffer())}});
    } catch (error) { rejected = error instanceof WebAssembly.CompileError; }
    finally { embedded.dispose(); }
    if (!rejected) throw new Error('Production core host unexpectedly accepted a component');

    const source = URL.createObjectURL(new Blob([
      `import * as api from ${JSON.stringify(entry)}; self.postMessage('ready'); api.spin();`,
    ], {type: 'text/javascript'}));
    const worker = new Worker(source, {type: 'module'});
    try {
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Component worker not ready')), 10000);
        worker.onmessage = event => {
          clearTimeout(timer);
          if (event.data === 'ready') resolve(); else reject(new Error('Unexpected worker response'));
        };
        worker.onerror = event => { clearTimeout(timer); reject(new Error(event.message)); };
      });
      await new Promise(resolve => setTimeout(resolve, 50));
      worker.terminate();
    } finally { worker.terminate(); URL.revokeObjectURL(source); }
    // A fresh call after terminating the isolated execution remains possible.
    if ((await import(`${entry}?after-termination`)).calls() !== 0) throw new Error('Host did not recover');
    return {values, resources, callbacks, freshInstance: true, trap: true, workerTerminationRequested: true,
      productionCoreHostRejectsComponent: true};
  });
  assert.equal(result.values.acceptedCalls, 105);
  const report = {host: 'chromium', route: 'jco-generated-bindings', browser: browser.version(), ...result};
  await writeFile(`${directory}/browser-report.json`, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report));
} finally {
  await browser?.close();
  await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}
