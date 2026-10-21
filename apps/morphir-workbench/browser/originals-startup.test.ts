import assert from 'node:assert/strict';
import { once } from 'node:events';
import type { AddressInfo } from 'node:net';
import { test } from 'node:test';
import { chromium } from 'playwright';
import { createWorkbenchServer } from '../scripts/server.ts';
import { gettingStarted } from '../scripts/workbench-steps.ts';

// Exercise the built page, its real initializer and its actual network/worker
// effects. A mode parser alone cannot prove this startup boundary.
test('originals mode waits for an explicit opening without starting the legacy runtime', { timeout: 15_000 }, async () => {
  const server = createWorkbenchServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const effects: string[] = [], errors: string[] = [];
    page.on('request', request => {
      const path = new URL(request.url()).pathname;
      if (path.startsWith('/api/') || path.endsWith('/execution-core.js') || path.endsWith('/worker.js')) effects.push(path);
    });
    page.on('websocket', () => effects.push('websocket'));
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    await page.waitForFunction(() => globalThis.morphirWorkbench !== undefined);
    assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.connected), true);
    await page.getByRole('status').filter({ hasText: 'Choose a model source' }).waitFor();
    await page.getByRole('button', { name: 'Workspace: Connected host', exact: true }).waitFor();
    assert.deepEqual(effects, [], 'No worker, execution-core, manifest or websocket before the opening command');
    const refusal = JSON.parse(await page.evaluate(() => new Promise<string>(resolve => {
      void globalThis.morphirWorkbench.request({ operation: 'initialize', source: '' }, resolve);
    })));
    assert.equal(refusal.success, false);
    assert.deepEqual(effects, [], 'Even a stale legacy initialization request cannot start this page runtime');
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});

test('the local experience keeps its runtime and exposes an originals route before connection', { timeout: 15_000 }, async () => {
  const server = createWorkbenchServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const effects: string[] = [];
    page.on('request', request => {
      const path = new URL(request.url()).pathname;
      if (path.startsWith('/api/') || path.endsWith('/execution-core.js') || path.endsWith('/worker.js')) effects.push(path);
    });
    page.on('websocket', () => effects.push('websocket'));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=local`);
    await gettingStarted(page);
    assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.connected), false);
    assert.ok(effects.includes('/execution-core.js'));
    assert.ok(effects.includes('/worker.js'));
    const originals = page.getByRole('link', { name: 'Model sources', exact: true });
    assert.equal(await originals.count(), 1);
    effects.length = 0;
    await originals.click();
    await page.getByRole('status').filter({ hasText: 'Choose a model source' }).waitFor();
    assert.equal(new URL(page.url()).search, '?mode=connected-originals');
    assert.deepEqual(effects, []);
  } finally {
    await browser.close();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
