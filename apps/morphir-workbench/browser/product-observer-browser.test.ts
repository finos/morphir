// Real built product + existing HTTP/WS fixture. Not MCK/driver qualification.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {once} from 'node:events';
import {mkdtemp, cp, readFile, writeFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import type {AddressInfo} from 'node:net';
import type {IncomingMessage, ServerResponse} from 'node:http';
import type {Duplex} from 'node:stream';
import {WebSocketServer} from 'ws';
import {chromium} from 'playwright';
import {createWorkbenchServer} from '../scripts/server.ts';
import {startOriginalsFixture} from '../scripts/originals-fixture-host.ts';
import type {ProductFact} from './product-observer.ts';

// Real HTTP bootstrap and WebSocket transport for the actual fixed entry. This
// fixture owns only its loopback endpoint and ACKs, never native host authority.
function attachDocumentFixture(server: ReturnType<typeof createWorkbenchServer>) {
  const records = 128, journalBytes = 65536, frameBytes = 2048, backing = journalBytes + 8 * records;
  const bootstrap = {observation: {owners: 32, events: 128}, records, journalBytes, frameBytes,
    journalCharge: {retainedBytes: backing, slots: 104 * records + 8, byteVisits: backing + records * (4218 + 66 * frameBytes) + 8},
    transportCharge: {retainedBytes: frameBytes + 16, slots: 8 + 2 * records, byteVisits: frameBytes + 16 + records * (2 * frameBytes + 64) + 96},
    credential: 'A'.repeat(43)};
  const request = server.listeners('request')[0]! as (request: IncomingMessage, response: ServerResponse) => void;
  server.removeAllListeners('request');
  server.on('request', (incoming, response) => {
    if (incoming.url !== '/_mck/document') {request(incoming, response); return;}
    if (incoming.method !== 'POST') {response.writeHead(405).end(); return;}
    response.writeHead(200, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'}).end(JSON.stringify(bootstrap));
  });
  const upgrade = server.listeners('upgrade')[0]! as (request: IncomingMessage, socket: Duplex, head: Buffer) => void;
  server.removeAllListeners('upgrade');
  const sockets = new WebSocketServer({noServer: true, handleProtocols: protocols =>
    protocols.size === 2 && protocols.has('morphir-document-v1') && protocols.has(`morphir-document-key.${bootstrap.credential}`)
      ? 'morphir-document-v1' : false});
  server.on('upgrade', (incoming, socket, head) => {
    if (incoming.url !== '/_mck/document') {upgrade(incoming, socket, head); return;}
    sockets.handleUpgrade(incoming, socket, head, peer => sockets.emit('connection', peer, incoming));
  });
  const facts: ProductFact[] = [], failures: string[] = [];
  sockets.on('connection', peer => peer.on('message', (data, binary) => {
    try {
      assert(binary && Buffer.isBuffer(data));
      const header = new DataView(data.buffer, data.byteOffset, data.byteLength);
      assert.equal(header.getUint8(0), 1); assert.equal(header.getUint8(1), 1);
      assert.equal(header.getUint16(2), 0); assert.equal(header.getUint32(12), data.byteLength - 16);
      assert.equal(header.getBigUint64(4), BigInt(facts.length + 1)); assert(facts.length < records);
      facts.push(JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(data.subarray(16))));
      const ack = new Uint8Array(16), control = new DataView(ack.buffer);
      control.setUint8(0, 1); control.setUint8(1, 3); control.setBigUint64(4, header.getBigUint64(4)); peer.send(ack);
    } catch (error) {failures.push(String(error)); peer.terminate();}
  }));
  return {facts, failures, async close() {
    for (const socket of sockets.clients) socket.terminate();
    await new Promise<void>((resolve, reject) => sockets.close(error => error ? reject(error) : resolve()));
  }};
}

test('actual standard entry remains unobserved and cannot attach after startup', {timeout: 10000}, async () => {
  const server = createWorkbenchServer(); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    await page.getByRole('status').filter({hasText: 'Choose a model source'}).waitFor({timeout: 3000});
    // Fixed diagnostic read of the actual built module, not a driver API or an
    // event constructor. No product facts or selections are manufactured.
    const actual = await page.evaluate(async () => {
      const moduleURL = new URL('/product-observer.js', location.href).href;
      const {productObservation} = await import(moduleURL);
      return {state: productObservation.state(), attachment: productObservation.attach(document, {owners: 1, events: 1}, () => {})};
    });
    assert.deepEqual(actual, {state: {kind: 'unobserved'}, attachment: 'late'});
  } finally {
    await browser.close(); await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});

for (const ending of ['inspect', 'close-before-core'] as const)
test(`fixed observed entry holds the genuine projection inspection command: ${ending}`, {timeout: 20000}, async () => {
  const fixture = startOriginalsFixture('projected-model');
  const assets = await mkdtemp(join(tmpdir(), 'workbench-inspection-'));
  await cp(new URL('../dist/', import.meta.url), assets, {recursive: true});
  await cp(join(assets, 'observed-index.html'), join(assets, 'index.html'));
  const server = createWorkbenchServer({host: fixture.host.url.origin, root: pathToFileURL(assets + '/')});
  const document = attachDocumentFixture(server);
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    const workers: string[] = [], errors: string[] = [];
    page.on('request', request => {if (new URL(request.url()).pathname.endsWith('/worker.js')) workers.push(request.url());});
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    const capture = await page.evaluateHandle(async () => {
      const url = new URL('/observed-document-entry.js', location.href).href;
      return (await import(url)).openingControls.prepareOpeningCapture();
    });
    await page.locator('button[data-model-connect="originals"]').click();
    const captured = await capture.evaluateHandle(actual => actual.whenRegistered());
    // Literal fixture identities, not display names or an assumed row order.
    await page.locator('[data-model-choice-phase="source"]').waitFor();
    assert.deepEqual(await captured.evaluate(actual => actual.chooseSource('provider', 'workspace:B')), {kind: 'source-selected'});
    await page.locator('[data-model-choice-phase="project"]').waitFor();
    assert.deepEqual(await captured.evaluate(actual => actual.chooseProject('project-B')), {kind: 'project-selected'});
    await fixture.pendingRelease;
    assert.deepEqual(workers, []);
    fixture.release();
    const pending = await captured.evaluate(actual => actual.awaitInspectionPending());
    assert.deepEqual(pending, {kind: 'inspection-pending'});
    assert.deepEqual(workers, [], 'the genuine app command must still be held before worker creation');
    assert.equal(await page.getByRole('button', {name: 'Download model.yaml', exact: true}).count(), 0);
    if (ending === 'close-before-core') {
      await page.getByRole('button', {name: 'Close model', exact: true}).click();
      await page.getByRole('status').filter({hasText: 'Model closed'}).waitFor();
      assert.equal(await captured.evaluate(actual => actual.executePendingCore()), 'ignored');
      assert.deepEqual(workers, []);
    } else {
      assert.equal(await captured.evaluate(actual => actual.executePendingCore()), 'enqueued');
      assert.deepEqual(await captured.evaluate(actual => actual.awaitOpeningSettled()), {kind: 'stored'});
      assert.equal(await captured.evaluate(actual => actual.executePendingCore()), 'ignored');
      await page.getByRole('status').filter({hasText: 'captured model inspected'}).waitFor();
      assert.equal(workers.length, 1);
      assert.equal(await page.getByRole('button', {name: 'Export IR', exact: true}).isEnabled(), true);
      await page.getByText('Inspected model and original files from the selected capture', {exact: true}).waitFor();
      const download = page.waitForEvent('download');
      await page.getByRole('button', {name: 'Download model.yaml', exact: true}).click();
      const stream = await (await download).createReadStream();
      assert(stream);
      const chunks: Buffer[] = []; for await (const chunk of stream) chunks.push(Buffer.from(chunk));
      assert.deepEqual(Buffer.concat(chunks), fixture.original);
    }
    assert.equal((fixture.requests.find(row => row.method.endsWith('.capture'))!.params as {semantic: string}).semantic, 'projection');
    assert.deepEqual(document.failures, []);
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    await document.close();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    await fixture.host.stop(true); await rm(assets, {recursive: true, force: true});
  }
});

for (const ending of ['current', 'close', 'replace', 'sink-raised'] as const)
test(`observed entry links real product owners without changing effects: ${ending}`, {timeout: 20000}, async () => {
  const fixture = startOriginalsFixture('single-file');
  const assets = await mkdtemp(join(tmpdir(), 'workbench-observer-'));
  await cp(new URL('../dist/', import.meta.url), assets, {recursive: true});
  const index = join(assets, 'index.html');
  await writeFile(index, (await readFile(index, 'utf8')).replace('src="./bootstrap.js"', 'src="./observer-test-entry.js"'));
  await writeFile(join(assets, 'observer-test-entry.js'),
    `import {startObservedWorkbench} from './observed-bootstrap.js';
     const handle = await startObservedWorkbench({owners: 32, events: 128}, fact => {
       void globalThis.__productFact(fact);
       if (${ending === 'sink-raised'} && fact.kind === 'archive-ready') throw new Error('actual observer callback refusal');
     });
     globalThis.__observationState = handle.state;`);
  const server = createWorkbenchServer({host: fixture.host.url.origin, root: pathToFileURL(assets + '/')});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  let phase = 'startup';
  const page = await browser.newPage(), facts: ProductFact[] = [], errors: string[] = [];
  try {
    page.setDefaultTimeout(3000);
    page.on('pageerror', error => errors.push(error.message));
    page.on('websocket', socket => socket.on('socketerror', error => errors.push(`websocket: ${error}`)));
    page.on('requestfailed', request => errors.push(`${new URL(request.url()).pathname}: ${request.failure()?.errorText}`));
    // Fixture-only transport for the maintained fixed entry. It creates no
    // events or product owners and does not replace product bridge methods.
    await page.exposeFunction('__productFact', (fact: ProductFact) => facts.push(fact));
    // Serve the actual built assets over real HTTP. Intercepting navigation
    // with route.fulfill changes Chromium's address-space classification and
    // blocks the genuine loopback WS under local-network access checks.
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    await page.getByRole('status').filter({hasText: 'Choose a model source'}).waitFor({timeout: 3000});
    phase = 'choose source';
    await page.getByRole('button', {name: 'Connect model source', exact: true}).click();
    await page.getByRole('button', {name: 'Same source', exact: true}).nth(1).click();
    phase = 'choose project';
    await page.getByRole('button', {name: 'Same project', exact: true}).nth(1).click();
    phase = 'release request';
    await Promise.race([fixture.pendingRelease, new Promise<never>((_, reject) => setTimeout(() => reject(new Error('actual release request missing')), 3000))]);
    assert.equal(facts.some(fact => fact.kind === 'inventory-adopted'), false);
    fixture.release();
    phase = 'adoption';
    await page.getByRole('status').filter({hasText: 'Original files ready'}).waitFor();
    const actualRevision = await page.locator('.original-files').getAttribute('data-inventory-revision');
    const pending = page.waitForEvent('download'); // prearmed before actual action
    phase = 'archive/download';
    await page.getByRole('button', {name: 'Download originals archive', exact: true}).click();
    const download = await pending; assert.equal(download.suggestedFilename(), 'morphir-originals.zip');
    assert.equal(await download.failure(), null); await download.delete();
    // Flush the real fixed transport's callbacks, not a product transition.
    await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => resolve())));
    const selected = facts.find(fact => fact.kind === 'project-selected');
    const verified = facts.find(fact => fact.kind === 'transfer-verified');
    const adopted = facts.find(fact => fact.kind === 'inventory-adopted');
    const stored = facts.find(fact => fact.kind === 'archive-stored');
    const ready = facts.find(fact => fact.kind === 'archive-ready');
    const result = facts.find(fact => fact.kind === 'download-result');
    assert(selected?.kind === 'project-selected' && verified && adopted?.kind === 'inventory-adopted');
    assert(stored?.kind === 'archive-stored' && ready?.kind === 'archive-ready');
    assert.equal(adopted.actual.inventoryRevision, actualRevision);
    assert.equal(selected.actual.openingOrdinal, adopted.actual.openingOrdinal);
    assert.equal(stored.actual.operationOrdinal, ready.actual.operationOrdinal);
    assert.equal(stored.actual.inventoryRevision, ready.actual.inventoryRevision);
    if (ending === 'sink-raised') {
      assert.equal(result, undefined);
      assert.deepEqual(await page.evaluate(() => Reflect.get(globalThis, '__observationState')()), {kind: 'incomplete', cause: 'sink-raised'});
      await page.getByRole('button', {name: 'Close model', exact: true}).click();
      await page.getByRole('status').filter({hasText: 'Model closed'}).waitFor();
      assert.deepEqual(errors, []); return;
    }
    assert(result?.kind === 'download-result'); assert.deepEqual(ready.actual, result.actual);
    assert.deepEqual(result.outcome, {kind: 'returned', result: 'download-requested'});
    assert(verified.sequence < adopted.sequence && adopted.sequence < stored.sequence && stored.sequence < ready.sequence && ready.sequence < result.sequence);
    if (ending === 'close' || ending === 'replace') {
      phase = `held actual ready: ${ending}`;
      const downloads: string[] = []; page.on('download', actual => downloads.push(actual.suggestedFilename()));
      await page.evaluate(() => {
        const bridge = globalThis.morphirWorkbench, actual = bridge.prepareOriginalsArchive;
        bridge.prepareOriginalsArchive = (operation, receive) => actual(operation, event => {
          if (event.kind === 'ready') Reflect.set(globalThis, '__deliverObservedReady', () => receive(event));
          else receive(event);
        });
      });
      await page.getByRole('button', {name: 'Download originals archive', exact: true}).click();
      await page.waitForFunction(() => Reflect.has(globalThis, '__deliverObservedReady'));
      const held = facts.filter(fact => fact.kind === 'archive-ready').at(-1); assert(held?.kind === 'archive-ready');
      assert.notEqual(held.actual.operationOrdinal, ready.actual.operationOrdinal);
      if (ending === 'close') {
        await page.getByRole('button', {name: 'Close model', exact: true}).click();
        await page.getByRole('status').filter({hasText: 'Model closed'}).waitFor();
      } else {
        await page.getByRole('button', {name: 'Connect model source', exact: true}).click();
        await page.getByRole('button', {name: 'Same source', exact: true}).nth(1).click();
        await page.getByRole('button', {name: 'Same project', exact: true}).nth(1).click();
        const end = Date.now() + 3000;
        while (fixture.requests.filter(row => row.method.endsWith('.release')).length < 2) {assert(Date.now() < end); await new Promise<void>(resolve => setImmediate(resolve));}
        await page.getByRole('status').filter({hasText: 'Receiving original files'}).waitFor(); fixture.release();
        await page.getByRole('status').filter({hasText: 'Original files ready'}).waitFor();
        assert.notEqual(await page.locator('.original-files').getAttribute('data-inventory-revision'), actualRevision);
      }
      await page.evaluate(() => Reflect.get(globalThis, '__deliverObservedReady')());
      await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
      assert.deepEqual(downloads, []);
      assert.equal(facts.some(fact => fact.kind === 'download-result' && fact.actual.operationOrdinal === held.actual.operationOrdinal), false);
      assert(facts.some(fact => fact.kind === 'archive-retirement-requested' && fact.actual.operationOrdinal === held.actual.operationOrdinal));
    }
    if (ending !== 'close') {
      await page.getByRole('button', {name: 'Close model', exact: true}).click();
      await page.getByRole('status').filter({hasText: 'Model closed'}).waitFor();
    }
    await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => resolve())));
    assert(facts.some(fact => fact.kind === 'model-closed'));
    assert.deepEqual(await page.evaluate(() => Reflect.get(globalThis, '__observationState')()), {kind: 'active'});
    assert.deepEqual(errors, []);
  } catch (cause) {
    console.error(JSON.stringify({phase, errors, facts, requests: fixture.requests.map(row => row.method), status: await page.getByRole('status').allTextContents()}));
    throw new Error(`Actual observer workflow phase: ${phase}`, {cause});
  }
  finally {
    await browser.close(); await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    await fixture.host.stop(true);
    await rm(assets, {recursive: true, force: true});
  }
});
