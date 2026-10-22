// Actual built-page ownership, with synthetic pagehide as unit lifecycle input.
// This is not native navigation or browser-bfcache qualification.
import assert from 'node:assert/strict';
import {once} from 'node:events';
import type {AddressInfo} from 'node:net';
import {test} from 'node:test';
import {chromium} from 'playwright';
import {unzipSync} from 'fflate';
import {createWorkbenchServer} from '../scripts/server.ts';
import {startOriginalsFixture} from '../scripts/originals-fixture-host.ts';

test('real retirement clears only its matching pending archive and a foreign old failure cannot clear the new operation', {timeout: 20000}, async () => {
  const fixture = startOriginalsFixture('single-file');
  const server = createWorkbenchServer({host: fixture.host.url.origin}); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage(), errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    await page.getByRole('status').filter({hasText: 'Choose a model source'}).waitFor();
    await page.getByRole('button', {name: 'Connect model source', exact: true}).click();
    await page.getByRole('button', {name: 'Same source', exact: true}).nth(1).click();
    await page.getByRole('button', {name: 'Same project', exact: true}).nth(1).click();
    await fixture.pendingRelease; fixture.release();
    await page.getByRole('status').filter({hasText: 'Original files ready'}).waitFor();
    const revision = await page.locator('.original-files').getAttribute('data-inventory-revision'); assert(revision);
    await page.evaluate(() => {
      const actual = globalThis.morphirWorkbench.prepareOriginalsArchive;
      let ordinal = 0;
      globalThis.morphirWorkbench.prepareOriginalsArchive = (operation, receive) => {
        const current = ++ordinal;
        actual(operation, event => {
          if (event.kind === 'ready') {
            Reflect.set(globalThis, current === 1 ? '__oldActualReady' : '__newActualReady', () => receive(event)); return;
          }
          if (current === 1 && event.failure.kind === 'retired') Reflect.set(globalThis, '__replayOldActualRetirement', () => receive(event));
          receive(event);
        });
      };
    });
    const archive = page.getByRole('button', {name: 'Download originals archive', exact: true});
    await archive.click(); await page.waitForFunction(() => Reflect.has(globalThis, '__oldActualReady'));
    await page.waitForFunction(() => Array.from(document.querySelectorAll('button')).some(button => button.textContent === 'Download originals archive' && button.disabled));
    assert.equal(await archive.isDisabled(), true);
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted: true})));
    await page.waitForFunction(() => Reflect.has(globalThis, '__replayOldActualRetirement'), undefined, {timeout: 1500});
    await page.waitForFunction(() => Array.from(document.querySelectorAll('button')).some(button => button.textContent === 'Download originals archive' && !button.disabled));
    assert.equal(await archive.isEnabled(), true);
    assert.equal(await page.locator('.original-files').getAttribute('data-inventory-revision'), revision);
    await archive.click(); await page.waitForFunction(() => Reflect.has(globalThis, '__newActualReady'));
    await page.waitForFunction(() => Array.from(document.querySelectorAll('button')).some(button => button.textContent === 'Download originals archive' && button.disabled));
    assert.equal(await archive.isDisabled(), true);
    await page.evaluate(() => Reflect.get(globalThis, '__replayOldActualRetirement')());
    await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
    assert.equal(await archive.isDisabled(), true, 'actual old operation identity cannot clear the new pending owner');
    const pending = page.waitForEvent('download');
    await page.evaluate(() => Reflect.get(globalThis, '__newActualReady')());
    const download = await pending, stream = await download.createReadStream(); assert(stream);
    const chunks: Buffer[] = []; for await (const chunk of stream) chunks.push(Buffer.from(chunk));
    const entries = unzipSync(Buffer.concat(chunks)); assert.deepEqual(Object.keys(entries), ['model.yaml']);
    assert.deepEqual(Buffer.from(entries['model.yaml']!), fixture.original);
    await page.waitForFunction(() => Array.from(document.querySelectorAll('button')).some(button => button.textContent === 'Download originals archive' && !button.disabled));
    assert.equal(await archive.isEnabled(), true); assert.deepEqual(errors, []);
  } finally {
    await browser.close(); await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); await fixture.host.stop(true);
  }
});
