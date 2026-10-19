import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import type { Browser, Download, FileChooser, Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';

async function contents(download: Download): Promise<Buffer> {
  const stream = await download.createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks);
}

async function choose(page: Page): Promise<FileChooser> {
  const pending = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  return pending;
}

/** Actual picker, worker migration, browser save and model release. */
export async function modelDocumentWorkflow(browser: Browser, url: string): Promise<void> {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage(), errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(url);
    await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
    const source = await page.locator('#source').evaluate(editor => (editor as CodeEditor).value);
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    const input = await readFile(new URL('../../../pkgs/morphir-ir/conformance/fixtures/v1-rentals.json', import.meta.url), 'utf8');
    const original = Buffer.from('\ufeff' + input.replace(/\r?\n/g, '\r\n'));
    await (await choose(page)).setFiles({ name: 'rentals-original.json', mimeType: 'application/json', buffer: original });
    await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
    const originalButton = page.getByRole('button', { name: 'Download original file', exact: true });
    await originalButton.waitFor();
    assert.match(await originalButton.getAttribute('title') ?? '', /1\.0\.0/);
    const download = page.waitForEvent('download');
    await originalButton.click();
    const saved = await download;
    assert.equal(saved.suggestedFilename(), 'rentals-original.json');
    assert.deepEqual(await contents(saved), original);

    // A failed replacement must leave the previous original available.
    await (await choose(page)).setFiles({ name: 'broken.json', mimeType: 'application/json', buffer: Buffer.from('invalid json') });
    await page.getByRole('status').filter({ hasText: 'The model is not valid' }).waitFor();
    const retained = page.waitForEvent('download'); await originalButton.click();
    assert.deepEqual(await contents(await retained), original);

    // Hold a genuine File read, close the old document, then allow the late read.
    await page.evaluate(() => {
      const read = File.prototype.arrayBuffer;
      const state = globalThis as typeof globalThis & { finishModelRead?: () => void; modelReadStarted?: boolean };
      File.prototype.arrayBuffer = function () {
        state.modelReadStarted = true;
        return new Promise<ArrayBuffer>((resolve, reject) => {
          state.finishModelRead = () => { File.prototype.arrayBuffer = read; void read.call(this).then(resolve, reject); };
        });
      };
    });
    await (await choose(page)).setFiles({ name: 'late.json', mimeType: 'application/json', buffer: original });
    await page.waitForFunction(() => (globalThis as typeof globalThis & { modelReadStarted?: boolean }).modelReadStarted);
    await page.getByRole('button', { name: 'Close model', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Model closed' }).waitFor();
    await page.evaluate(() => (globalThis as typeof globalThis & { finishModelRead?: () => void }).finishModelRead?.());
    await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
    assert.equal(await originalButton.count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Close model', exact: true }).count(), 0);
    assert.equal(await page.locator('.tree-item').count(), 0);
    await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
    assert.equal(await page.locator('#source').evaluate(editor => (editor as CodeEditor).value), source);
    assert.equal(await page.getByRole('button', { name: 'Source unit', exact: true }).count(), 0);
    // Imported semantic inspection still supports exact UTF-16 evaluation.
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    await (await choose(page)).setFiles(new URL('../fixtures/typed-pricing.json', import.meta.url).pathname);
    await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
    await page.locator('.tree-item[title="pricing:boundaries#text"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    await page.getByRole('button', { name: 'Ion inputs', exact: true }).click();
    await page.getByRole('textbox', { name: 'Function arguments', exact: true }).fill('[morphir_value::{type:"text",units:[55296,0]}]');
    await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
    await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
    await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(editor => (editor as CodeEditor).value)), { type: 'text', units: [55296, 0] });
    assert.deepEqual(errors, []);
    console.log('Model document workflow passed: migrated v1 BOM/CRLF original saved byte-for-byte, failed replacement retained it, close retired a pending real File read and preserved editor input.');
  } finally { await context.close(); }
}
