// Actual built-page characterization of retained ownership. Authored after the
// first integration; it does not relabel earlier A01/A02/A03 as this evidence.
import assert from 'node:assert/strict';
import {once} from 'node:events';
import type {AddressInfo} from 'node:net';
import {test} from 'node:test';
import {chromium, type Download} from 'playwright';
import {unzipSync} from 'fflate';
import {createWorkbenchServer} from '../scripts/server.ts';
import {startOriginalsFixture} from '../scripts/originals-fixture-host.ts';

for (const ending of ['cancelled', 'failed'] as const) test(`actual queued archive survives a ${ending} new opening of the same inventory`, {timeout: 20000}, async () => {
  const fixture = startOriginalsFixture('single-file');
  const server = createWorkbenchServer({host: fixture.host.url.origin});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage(); const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    await page.getByRole('status').filter({hasText: 'Choose a model source'}).waitFor();
    await page.getByRole('button', {name: 'Connect model source', exact: true}).click();
    await page.getByRole('button', {name: 'Same source', exact: true}).nth(1).click();
    await page.getByRole('button', {name: 'Same project', exact: true}).nth(1).click();
    await fixture.pendingRelease; fixture.release();
    await page.getByRole('status').filter({hasText: 'Original files ready'}).waitFor();
    const revision = await page.locator('.original-files').getAttribute('data-inventory-revision'); assert(revision);
    const checkDownload = async (pending: Promise<Download>) => {
      const download = await pending; const stream = await download.createReadStream(); assert(stream);
      const chunks: Buffer[] = []; for await (const chunk of stream) chunks.push(Buffer.from(chunk));
      const entries = unzipSync(Buffer.concat(chunks));
      assert.deepEqual(Object.keys(entries), ['model.yaml']);
      assert.deepEqual(Buffer.from(entries['model.yaml']!), fixture.original);
    };
    const calibration = page.waitForEvent('download');
    await page.getByRole('button', {name: 'Download originals archive', exact: true}).click();
    await checkDownload(calibration);
    await page.evaluate(() => {
      const actual = globalThis.morphirWorkbench.prepareOriginalsArchive;
      globalThis.morphirWorkbench.prepareOriginalsArchive = (operation, receive) => actual(operation, event => {
        if (event.kind === 'ready') Reflect.set(globalThis, '__deliverRetainedArchive', () => receive(event));
        else receive(event);
      });
    });
    await page.getByRole('button', {name: 'Download originals archive', exact: true}).click();
    await page.waitForFunction(() => Reflect.has(globalThis, '__deliverRetainedArchive'));
    await page.getByRole('button', {name: 'Connect model source', exact: true}).click();
    // The unchanged fixture binds capture to source B. Selecting A produces a
    // genuine binding rejection, not a test-created failure event or payload.
    await page.getByRole('button', {name: 'Same source', exact: true}).nth(ending === 'failed' ? 0 : 1).click();
    await page.getByRole('button', {name: 'Same project', exact: true}).nth(1).click();
    if (ending === 'cancelled') {
      await page.waitForFunction(() => document.querySelector('[role="status"]')?.textContent?.includes('Receiving original files'));
      const end = Date.now() + 5000;
      while (fixture.requests.filter(row => row.method.endsWith('.release')).length < 2) {
        assert(Date.now() < end); await new Promise<void>(resolve => setImmediate(resolve));
      }
      await page.getByRole('button', {name: 'Discard', exact: true}).click();
      await page.getByRole('status').filter({hasText: 'Model opening cancelled'}).waitFor();
    } else await page.getByRole('status').filter({hasText: 'originals.binding_changed'}).waitFor();
    assert.equal(fixture.requests.filter(row => row.method.endsWith('.capture')).length, 2);
    assert.equal(await page.locator('.original-files').getAttribute('data-inventory-revision'), revision);
    const retained = page.waitForEvent('download');
    await page.evaluate(() => Reflect.get(globalThis, '__deliverRetainedArchive')());
    await checkDownload(retained);
    assert.equal(await page.locator('.original-files').getAttribute('data-inventory-revision'), revision);
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    await fixture.host.stop(true);
  }
});
