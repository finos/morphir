// Real built product + existing HTTP/WS fixture. Not MCK/driver qualification.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {once} from 'node:events';
import {mkdtemp, cp, readFile, writeFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import type {AddressInfo} from 'node:net';
import {chromium} from 'playwright';
import {createWorkbenchServer} from '../scripts/server.ts';
import {startOriginalsFixture} from '../scripts/originals-fixture-host.ts';
import type {ProductFact} from './product-observer.ts';

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
