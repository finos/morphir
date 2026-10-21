import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { gettingStarted } from '../scripts/workbench-steps.ts';

// Explicit packaged acceptance only. The folder path is a test assertion input;
// the app must receive its authority through its real native picker.
test('packaged native picker grants editing and project creation writes the chosen folder', { timeout: 180000 }, async () => {
  const endpoint = process.env.MORPHIR_WORKBENCH_NATIVE_CDP;
  const folder = process.env.MORPHIR_WORKBENCH_NATIVE_FOLDER;
  assert.ok(endpoint && folder, 'Provide the owned package CDP endpoint and empty test folder');
  assert.deepEqual(await readdir(folder), [], 'Use an empty disposable test folder');
  const browser = await chromium.connectOverCDP(endpoint);
  const page = browser.contexts()[0]!.pages().find(page => page.url().startsWith('https://proton.localhost/'));
  assert.ok(page, 'The real packaged app page is present');
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  try {
    await gettingStarted(page);
    await page.getByRole('button', { name: 'Open a workspace', exact: true }).click();
    await page.getByRole('button', { name: 'Open a workspace folder…', exact: true }).click();
    console.log('Waiting for the real native editing picker to choose the test folder.');
    await page.getByRole('button', { name: 'Add project…', exact: true }).waitFor({ timeout: 120000 });
    await page.getByRole('button', { name: 'Add project…', exact: true }).click();
    await page.getByRole('textbox', { name: 'Project name', exact: true }).fill('PackagedQuotes');
    await page.getByRole('textbox', { name: 'Project folder', exact: true }).fill('packages/quotes');
    await page.getByRole('combobox', { name: 'Project language', exact: true }).selectOption('scheme');
    await page.getByRole('button', { name: 'Create project', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Workspace folder saved' }).waitFor();
    assert.match(await readFile(join(folder, 'morphir.toml'), 'utf8'), /packages\/quotes/);
    assert.match(await readFile(join(folder, 'packages/quotes/morphir.toml'), 'utf8'), /PackagedQuotes/);
    assert.match(await readFile(join(folder, 'packages/quotes/src/main.scm'), 'utf8'), /identity/);
    assert.deepEqual(errors, []);
    console.log('Packaged native picker/project creation acceptance passed.');
  } finally { await page.close({ runBeforeUnload: true }).catch(() => {}); await browser.close(); }
});
