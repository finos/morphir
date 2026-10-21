import assert from 'node:assert/strict';
import { once } from 'node:events';
import type { AddressInfo } from 'node:net';
import { chromium } from 'playwright';
import { createWorkbenchServer } from './server.ts';
import { createWorkspace, gettingStarted, setExplorer } from './workbench-steps.ts';

const server = createWorkbenchServer();
server.listen(0, '127.0.0.1');
await once(server, 'listening');
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
const errors: string[] = [];
page.on('pageerror', error => errors.push(error.message));
page.setDefaultTimeout(10000);
try {
  await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=standalone`);
  await createWorkspace(page, { preset: 'Empty workspace', name: 'Multi-project acceptance' });
  await page.getByRole('button', { name: 'Add project…', exact: true }).waitFor();
  for (const name of ['Quotes', 'Pricing']) {
    await page.getByRole('button', { name: 'Add project…', exact: true }).click();
    await page.getByRole('textbox', { name: 'Project name', exact: true }).fill(name);
    await page.getByRole('textbox', { name: 'Project folder', exact: true }).fill(`packages/${name.toLowerCase()}`);
    await page.getByRole('combobox', { name: 'Project language', exact: true }).selectOption('scheme');
    await page.getByRole('button', { name: 'Create project', exact: true }).click();
    await page.getByRole('dialog', { name: 'Project changes', exact: true }).waitFor({ state: 'detached' });
  }
  assert.equal(await page.getByRole('combobox', { name: 'Language', exact: true }).count(), 0);
  await page.getByRole('button', { name: 'Compile workspace', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Compiled 2/2 projects' }).waitFor();
  await page.locator('button[title="packages/quotes/src/main.scm"]').click();
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(');
  await page.getByRole('button', { name: 'Compile workspace', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Compiled 1/2 projects' }).waitFor();
  await page.locator('button[title="packages/pricing/src/main.scm"]').click();
  await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(identity 42)');
  await page.getByRole('button', { name: 'Run worksheet', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Worksheet finished' }).waitFor();
  await page.locator('.worksheet-observation pre.value').filter({ hasText: '42' }).waitFor();
  const saved = await page.evaluate(() => Object.keys(localStorage).filter(key => key.endsWith('.tree.v1')));
  await page.waitForFunction(() => Object.keys(localStorage).filter(key => key.endsWith('.tree.v1')).some(key => {
    const manifest = JSON.parse(localStorage.getItem(key)!);
    return manifest.files['packages/quotes/src/main.scm'] && manifest.files['packages/pricing/src/main.scm'] &&
      JSON.parse(localStorage.getItem(manifest.files['packages/quotes/src/main.scm'])!) === '(';
  }));
  await page.getByRole('button', { name: 'Folders', exact: true }).click();
  await page.reload();
  await gettingStarted(page);
  await page.getByRole('button', { name: 'Open Multi-project acceptance', exact: true }).click();
  await page.locator('.document-tabs').waitFor();
  await setExplorer(page, true);
  if (await page.locator('#section-files').getAttribute('aria-expanded') !== 'true') await page.locator('#section-files').click();
  await page.getByRole('button', { name: 'Folders', exact: true }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Folders', exact: true }).getAttribute('aria-pressed'), 'true');
  await page.getByRole('button', { name: 'Projects', exact: true }).click();
  await page.getByRole('button', { name: 'Actions for Quotes', exact: true }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Actions for Quotes', exact: true }).count(), 1);
  assert.equal(await page.getByRole('button', { name: 'Actions for Pricing', exact: true }).count(), 1);
  await page.getByRole('button', { name: 'Actions for Quotes', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Remove…', exact: true }).click();
  await page.getByRole('button', { name: 'Remove project', exact: true }).click();
  await page.getByRole('button', { name: 'Actions for Quotes', exact: true }).waitFor({ state: 'detached' });
  assert.equal(await page.getByRole('button', { name: 'Actions for Quotes', exact: true }).count(), 0);
  await page.setViewportSize({ width: 390, height: 844 });
  await setExplorer(page, true);
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await page.screenshot({ path: '/tmp/pearl-workspace-projects-390.png', fullPage: true });
  assert.ok(saved.length <= 1);
  assert.deepEqual(errors, []);
  console.log('Workspace projects browser acceptance passed');
} catch (error) {
  await page.screenshot({ path: '/tmp/pearl-workspace-projects-failed.png', fullPage: true });
  console.error((await page.locator('body').innerText()).slice(0, 6000), errors);
  throw error;
} finally {
  await context.close();
  await browser.close();
  await new Promise<void>(resolve => server.close(() => resolve()));
}
