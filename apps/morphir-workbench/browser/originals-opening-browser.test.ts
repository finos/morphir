import assert from 'node:assert/strict';
import {once} from 'node:events';
import type {AddressInfo} from 'node:net';
import {test} from 'node:test';
import {chromium} from 'playwright';
import {createWorkbenchServer} from '../scripts/server.ts';
import {startOriginalsFixture} from '../scripts/originals-fixture-host.ts';

for (const interruption of ['none', 'pending-cancel', 'queued-cancel', 'queued-close', 'queued-legacy', 'pagination'] as const)
test(`built originals page owns source/project opening and delivery: ${interruption}`, {timeout: 15000}, async () => {
  const fixture = startOriginalsFixture(interruption === 'pagination' ? 'paged-inventory' : 'single-file');
  const {host, original, shared, binding, requests, pendingRelease, release} = fixture;
  const server = createWorkbenchServer({host: host.url.origin});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    const errors: string[] = [], effects: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => {if (/execution-core\.js|worker\.js/.test(request.url())) effects.push(request.url());});
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    await page.getByRole('status').filter({hasText: 'Choose a model source'}).waitFor();
    assert.equal(await page.locator('[data-document="source"]').count(), 0);
    assert.equal(await page.getByRole('group', {name: 'Source mode', exact: true}).count(), 0);
    assert.equal(await page.getByRole('button', {name: 'Run worksheet', exact: true}).count(), 0);
    if (interruption.startsWith('queued-')) await page.evaluate(() => {
      const original = globalThis.morphirWorkbench.openOriginals;
      Reflect.set(globalThis, '__originalsTakeCount', 0);
      globalThis.morphirWorkbench.openOriginals = (hash, receive) => original(hash, event => {
        if (event.kind !== 'received') {receive(event); return;}
        const take = event.stage.take.bind(event.stage);
        event.stage.take = adopt => {
          Reflect.set(globalThis, '__originalsTakeCount', Number(Reflect.get(globalThis, '__originalsTakeCount')) + 1);
          return take(adopt);
        };
        // Hold the actual private stage and callback. No test-created owner,
        // bytes, selections or successful application result is substituted.
        Reflect.set(globalThis, '__deliverOriginals', () => receive(event));
      });
    });
    assert.equal(await page.getByRole('button', {name: 'Connect model source', exact: true}).count(), 1);
    await page.getByRole('button', {name: 'Connect model source', exact: true}).click();
    await page.getByRole('button', {name: 'Same source', exact: true}).nth(1).click();
    await page.getByRole('button', {name: 'Same project', exact: true}).nth(1).click();
    await pendingRelease;
    assert.equal(await page.getByRole('button', {name: 'Download model.yaml', exact: true}).count(), 0);
    if (interruption === 'none') {
      await page.getByRole('button', {name: 'Settings', exact: true}).click();
      await page.getByRole('radio', {name: 'Tabs', exact: true}).check();
      await page.getByRole('radio', {name: 'Dark', exact: true}).check();
      await page.keyboard.press('Escape');
      await page.getByRole('button', {name: 'Close model', exact: true}).waitFor();
      assert.equal(requests.filter(request => request.method.endsWith('.capture')).length, 1);
    }
    if (interruption === 'pending-cancel') {
      await page.getByRole('button', {name: 'Discard', exact: true}).click();
      await page.getByRole('status').filter({hasText: 'Model opening cancelled'}).waitFor();
    }
    release();
    if (interruption.startsWith('queued-')) {
      await page.waitForFunction(() => Reflect.has(globalThis, '__deliverOriginals'));
      if (interruption === 'queued-legacy') await page.evaluate(() => globalThis.morphirWorkbench.cancel());
      else {
        await page.getByRole('button', {name: interruption === 'queued-close' ? 'Close model' : 'Discard', exact: true}).click();
        await page.getByRole('status').filter({hasText: interruption === 'queued-close' ? 'Model closed' : 'Model opening cancelled'}).waitFor();
      }
      await page.evaluate(() => Reflect.get(globalThis, '__deliverOriginals')());
    }
    if (interruption !== 'none' && interruption !== 'queued-legacy' && interruption !== 'pagination') {
      await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
      assert.equal(await page.getByRole('button', {name: 'Download model.yaml', exact: true}).count(), 0);
      if (interruption === 'queued-cancel' || interruption === 'queued-close') assert.equal(await page.evaluate(() => Reflect.get(globalThis, '__originalsTakeCount')), 0);
      assert.equal(fixture.manifests, 1);
      assert.equal(await page.getByRole('button', {name: 'Connect model source', exact: true}).isEnabled(), true);
      assert.deepEqual(effects, []); assert.deepEqual(errors, []);
      return;
    }
    await page.getByRole('status').filter({hasText: 'Original files ready'}).waitFor();
    if (interruption === 'queued-legacy') assert.equal(await page.evaluate(() => Reflect.get(globalThis, '__originalsTakeCount')), 1);
    await page.getByText('Original IR 4.0.0', {exact: true}).waitFor();
    if (interruption === 'pagination') {
      const next = page.getByRole('button', {name: 'Next originals page', exact: true});
      const previous = page.getByRole('button', {name: 'Previous originals page', exact: true});
      assert.equal(await previous.isDisabled(), true);
      const seen = new Set<string>();
      let pages = 0;
      for (;;) {
        await page.getByText(`Entries ${pages * 100 + 1} to ${Math.min((pages + 1) * 100, 1002)} of 1002`, {exact: true}).waitFor();
        const entries = await page.locator('.original-files li').allTextContents();
        assert(entries.length > 0 && entries.length <= 100);
        for (const entry of entries) {assert(!seen.has(entry)); seen.add(entry);}
        assert(++pages <= 11);
        if (await next.isDisabled()) break;
        await next.click();
      }
      assert.equal(pages, 11); assert.equal(seen.size, 1002);
      await page.getByText('Entries 1001 to 1002 of 1002', {exact: true}).waitFor();
      for (let index = pages - 2; index >= 0; --index) {
        await previous.click();
        await page.getByText(`Entries ${index * 100 + 1} to ${Math.min((index + 1) * 100, 1002)} of 1002`, {exact: true}).waitFor();
      }
      assert.equal(await previous.isDisabled(), true);
      await page.getByText('Entries 1 to 100 of 1002', {exact: true}).waitFor();
    }
    const download = page.waitForEvent('download');
    await page.getByRole('button', {name: 'Download model.yaml', exact: true}).click();
    const stream = await (await download).createReadStream();
    assert(stream); const chunks: Buffer[] = []; for await (const chunk of stream) chunks.push(Buffer.from(chunk));
    assert.deepEqual(Buffer.concat(chunks), original);
    assert.deepEqual(requests.find(request => request.method.endsWith('.capture'))!.params, {
      contractVersion: shared.contractVersion, source: binding.source, projectId: 'project-B', scope: 'complete', semantic: 'none',
    });
    assert.deepEqual(requests.map(request => request.method), ['morphir.session.initialize', 'morphir.workspace.open',
      'morphir.model-originals.capture', ...Array.from({length: interruption === 'pagination' ? 4 : 1}, () => 'morphir.model-originals.inventory'),
      'morphir.model-originals.read', 'morphir.model-originals.release']);
    await page.getByRole('button', {name: 'Close model', exact: true}).click();
    await page.getByRole('status').filter({hasText: 'Model closed'}).waitFor();
    assert.equal(await page.getByRole('button', {name: 'Download model.yaml', exact: true}).count(), 0);
    assert.equal(fixture.manifests, 1);
    if (interruption === 'none') {
      await page.getByRole('button', {name: 'Settings', exact: true}).click();
      assert.equal(await page.getByRole('radio', {name: 'Tabs', exact: true}).isChecked(), true);
      assert.equal(await page.getByRole('radio', {name: 'Dark', exact: true}).isChecked(), true);
    }
    assert.deepEqual(effects, []); assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    await host.stop(true);
  }
});
