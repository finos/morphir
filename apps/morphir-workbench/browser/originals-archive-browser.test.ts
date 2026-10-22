// Connected browser controls for archive publication and inventory ownership.
import assert from 'node:assert/strict';
import {once} from 'node:events';
import type {AddressInfo} from 'node:net';
import {test} from 'node:test';
import {unzipSync} from 'fflate';
import {chromium, type Page} from 'playwright';
import {createWorkbenchServer} from '../scripts/server.ts';
import {startOriginalsFixture} from '../scripts/originals-fixture-host.ts';
import type {OriginalArchiveOperation} from './originals-archive.ts';

type Fixture = ReturnType<typeof startOriginalsFixture>;
async function chooseInventory(page: Page, fixture: Fixture, ordinal: number) {
  await page.getByRole('button', {name: 'Connect model source', exact: true}).click();
  await page.getByRole('button', {name: 'Same source', exact: true}).nth(1).click();
  await page.getByRole('button', {name: 'Same project', exact: true}).nth(1).click();
  const end = Date.now() + 5000;
  while (fixture.requests.filter(row => row.method.endsWith('.release')).length < ordinal) {
    assert(Date.now() < end, 'actual release request must arrive before the test deadline');
    await new Promise<void>(resolve => setImmediate(resolve));
  }
  await page.getByRole('status').filter({hasText: 'Receiving original files'}).waitFor();
  fixture.release();
  await page.getByRole('status').filter({hasText: 'Original files ready'}).waitFor();
}

async function downloadBytes(page: Page, name: string): Promise<Buffer> {
  const pending = page.waitForEvent('download');
  await page.getByRole('button', {name, exact: true}).click();
  const download = await pending;
  const stream = await download.createReadStream();
  assert(stream);
  const chunks: Buffer[] = [];
  for await (const chunk of stream) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks);
}

for (const ending of ['current', 'close', 'replace'] as const)
test(`connected complete archive publishes only for its actual inventory owner: ${ending}`, {timeout: 20000}, async () => {
  // Reuse the existing real1002-entry complete/none fixture without modifying it.
  const fixture = startOriginalsFixture('paged-inventory');
  const server = createWorkbenchServer({host: fixture.host.url.origin});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    const errors: string[] = [], downloads: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('download', download => downloads.push(download.suggestedFilename()));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    await page.getByRole('status').filter({hasText: 'Choose a model source'}).waitFor();
    await chooseInventory(page, fixture, 1);
    const beforeRequests = fixture.requests.length;
    const archive = page.getByRole('button', {name: 'Download originals archive', exact: true});
    await archive.waitFor({state: 'visible', timeout: 1500});
    if (ending === 'current') {
      const raw = await downloadBytes(page, 'Download originals archive');
      // Existing independent application reader, not the future MCK comparator.
      const entries = unzipSync(raw);
      const expected = ['model.yaml', 'notes/', ...Array.from({length: 1000}, (_, index) =>
        `notes/empty-${String(index).padStart(4, '0')}/`)];
      assert.deepEqual(Object.keys(entries).sort(), expected.sort());
      assert.deepEqual(Buffer.from(entries['model.yaml']!), fixture.original);
      for (const name of expected.filter(name => name.endsWith('/'))) assert.equal(entries[name]!.length, 0);
      assert.equal(downloads.length, 1);
      assert.equal(fixture.requests.length, beforeRequests, 'archive must use the retained inventory without recapture/read/release');
    } else {
      // Positive calibration precedes every stale-path premise.
      const calibration = await downloadBytes(page, 'Download originals archive');
      const calibratedEntries = unzipSync(calibration);
      const calibratedNames = ['model.yaml', 'notes/', ...Array.from({length: 1000}, (_, index) =>
        `notes/empty-${String(index).padStart(4, '0')}/`)];
      assert.deepEqual(Object.keys(calibratedEntries).sort(), calibratedNames.sort());
      assert.deepEqual(Buffer.from(calibratedEntries['model.yaml']!), fixture.original);
      for (const name of calibratedNames.filter(name => name.endsWith('/'))) assert.equal(calibratedEntries[name]!.length, 0);
      assert.equal(downloads.length, 1);
      assert.equal(fixture.requests.length, beforeRequests);
      const calibratedDownloads = [...downloads];
      const initialRevision = await page.locator('.original-files').getAttribute('data-inventory-revision');
      assert(initialRevision && initialRevision.length > 0, 'actual adopted inventory revision must be rendered');
      // Hold the genuine ready callback after actual archive construction,
      // before Rabbita handles it. The test creates no bytes, owner or ACK.
      await page.evaluate(() => {
        const bridge = globalThis.morphirWorkbench;
        const actual = Reflect.get(bridge, 'prepareOriginalsArchive');
        if (typeof actual !== 'function') throw new Error('Reviewed prepareOriginalsArchive bridge is required');
        Reflect.set(globalThis, '__archiveProbe', {blobs: 0, urls: 0, downloadRequests: 0, disposed: 0, callbackDelivered: false});
        const probe = Reflect.get(globalThis, '__archiveProbe');
        const ActualBlob = globalThis.Blob;
        globalThis.Blob = class extends ActualBlob {
          constructor(parts?: BlobPart[], options?: BlobPropertyBag) { super(parts, options); ++probe.blobs; }
        };
        const create = URL.createObjectURL.bind(URL);
        URL.createObjectURL = object => {++probe.urls; return create(object);};
        Reflect.set(bridge, 'prepareOriginalsArchive', (operation: OriginalArchiveOperation, receive: (event: object) => void) =>
          actual(operation, (event: object) => {
            if (Reflect.get(event, 'kind') !== 'ready') {receive(event); return;}
            const owned = Reflect.get(event, 'archive');
            const requestDownload = owned.requestDownload.bind(owned), dispose = owned.dispose.bind(owned);
            owned.requestDownload = () => {++probe.downloadRequests; return requestDownload();};
            owned.dispose = () => {++probe.disposed; return dispose();};
            Reflect.set(globalThis, '__deliverActualArchive', () => {probe.callbackDelivered = true; receive(event);});
          }));
      });
      await archive.click();
      await page.waitForFunction(() => Reflect.has(globalThis, '__deliverActualArchive'));
      if (ending === 'close') {
        await page.getByRole('button', {name: 'Close model', exact: true}).click();
        await page.getByRole('status').filter({hasText: 'Model closed'}).waitFor();
      } else {
        await chooseInventory(page, fixture, 2);
        assert.equal(fixture.requests.filter(row => row.method.endsWith('.capture')).length, 2);
        assert.equal(fixture.requests.filter(row => row.method.endsWith('.release')).length, 2);
        await page.waitForFunction(oldRevision => {
          const actual = document.querySelector('.original-files')?.getAttribute('data-inventory-revision');
          return actual !== null && actual !== undefined && actual !== '' && actual !== oldRevision;
        }, initialRevision, {timeout: 5000});
        const adoptedRevision = await page.locator('.original-files').getAttribute('data-inventory-revision');
        assert(adoptedRevision && adoptedRevision !== initialRevision, 'replacement must actually adopt a different inventory revision before old callback');
      }
      await page.evaluate(() => Reflect.get(globalThis, '__deliverActualArchive')());
      await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
      const probe = await page.evaluate(() => Reflect.get(globalThis, '__archiveProbe'));
      assert.equal(probe.callbackDelivered, true);
      assert.equal(probe.downloadRequests, 0, 'stale handler must reject before requesting the fixed browser download');
      assert(probe.disposed > 0, 'actual stale output backing must be disposed');
      assert.equal(probe.blobs, 0); assert.equal(probe.urls, 0); assert.deepEqual(downloads, calibratedDownloads, 'stale callback must cause no additional download after actual positive calibration');
      if (ending === 'replace') {
        assert.deepEqual(await downloadBytes(page, 'Download model.yaml'), fixture.original);
      } else {
        assert.equal(await page.getByRole('button', {name: 'Download model.yaml', exact: true}).count(), 0);
      }
    }
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    await fixture.host.stop(true);
  }
});
