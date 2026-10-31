import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdir, writeFile, mkdtemp, readFile, rm } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { AddressInfo } from 'node:net';
import { fileURLToPath } from 'node:url';
import { chromium, type Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import { createWorkbenchServer } from './server.ts';
import { gettingStarted } from './workbench-steps.ts';
import {validateJupyterNotebook} from '../../morphir/scripts/notebook-acceptance.ts';

async function downloadNotebook(page: Page, format: string) {
  const downloaded = page.waitForEvent('download');
  await page.getByRole('button', {name: format === 'ipynb' ? 'Export Jupyter' : 'Export DIB (source only)', exact: true}).click();
  const download = await downloaded;
  assert.equal(download.suggestedFilename(), 'worksheet.' + format);
  const stream = await download.createReadStream();
  assert.ok(stream);
  const chunks: Buffer[] = [];
  for await (const chunk of stream) chunks.push(Buffer.from(chunk));
  return Buffer.concat(chunks).toString('utf8');
}

async function notebookDownloads(page: Page, source: string) {
  const directory = await mkdtemp(join(tmpdir(), 'morphir-notebook-browser-'));
  const workspace = fileURLToPath(new URL('../../../', import.meta.url));
  try {
    await writeFile(join(directory, 'worksheet.scm'), source);
    execFileSync('moon', ['build', 'apps/morphir/node', '--target', 'js', '--release'], {cwd: workspace, stdio: ['ignore', 'pipe', 'pipe']});
    const worker = new URL('../../../pkgs/morphir-host/runners/terminal-worker.mjs', import.meta.url).href;
    const artifact = new URL('../../../_build/js/release/build/morphir/morphir/node/node.js', import.meta.url).href;
    const launcher = join(directory, 'launcher.mjs');
    await writeFile(launcher, `import {terminalWorker} from ${JSON.stringify(worker)};\nif (!terminalWorker(new URL(import.meta.url),process.argv.slice(2))) await import(${JSON.stringify(artifact)});\n`);
    for (const format of ['ipynb', 'dib']) {
      const output = join(directory, 'worksheet.' + format);
      const result = JSON.parse(execFileSync(process.execPath, [launcher, 'notebook', 'export', join(directory, 'worksheet.scm'),
        '-o', output, '--json', ...(format === 'ipynb' ? ['--evaluate'] : [])], {encoding: 'utf8'}));
      assert.equal(result.state, 'succeeded');
      const actual = await downloadNotebook(page, format);
      const expected = await readFile(output, 'utf8');
      if (format === 'ipynb') {
        const notebook: unknown = JSON.parse(actual);
        validateJupyterNotebook(notebook);
        assert.deepEqual(notebook, JSON.parse(expected), 'Workbench cells and current outputs match the CLI');
      } else assert.equal(actual, expected, 'Workbench DIB source matches the CLI');
    }
  } finally { await rm(directory, {recursive: true, force: true}); }
}

async function openNotebook(page: Page, name: string, content: string) {
  const picker = page.waitForEvent('filechooser');
  await page.getByRole('button', {name: 'Open notebook…', exact: true}).click();
  await (await picker).setFiles({name, mimeType: 'application/octet-stream', buffer: Buffer.from(content)});
}

interface WorksheetReport {
  source: { id: string; revision: number; text: string };
  observations: { expression: string; preview: string; range: { start: number; end: number }; outcome: unknown }[];
  completion: { status: string; failure?: { code: string } };
  diagnostic: { stage: string; range: { start: number; end: number } | null } | null;
}

export async function worksheetWorkflow(page: Page) {
  // A scratch worksheet is an idea of its own: getting started opens it in a new workspace.
  await gettingStarted(page);
  await page.getByRole('button', { name: 'Try an idea', exact: true }).click();
  await page.getByRole('button', { name: 'Scratch worksheet', exact: true }).click();
  await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
  assert.equal(await page.getByRole('button', { name: 'Worksheet', exact: true }).getAttribute('aria-pressed'), 'true');
  // Observe the real bridge callback without replacing the worker or its result.
  await page.evaluate(() => {
    const original = globalThis.morphirWorkbench.request;
    const receipts: unknown[] = [];
    Object.assign(globalThis, { worksheetTestReceipts: receipts });
    globalThis.morphirWorkbench.request = (request, receive) => original(request, raw => {
      const reply = JSON.parse(raw);
      if (request.operation === 'worksheet' && typeof reply.worksheetReport === 'string') receipts.push(JSON.parse(reply.worksheetReport));
      receive(raw);
    });
  });
  const source = page.locator('#source');
  const setSource = async (text: string) => {
    // Playwright fill selects the DOM before inserting text. CodeMirror can
    // restore its own selection between those steps and append the fixture.
    // A transaction replaces the document and emits the real editor input event.
    await source.evaluate((node, text) => {
      const view = (node as CodeEditor).view;
      if (!view) throw new Error('The source editor must be mounted.');
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
    }, text);
    assert.equal(await source.evaluate(node => (node as CodeEditor).value), text.replace(/\r\n?/g, '\n'));
  };
  const run = page.getByRole('button', { name: 'Run worksheet', exact: true });
  const report = () => page.evaluate(() => (globalThis as unknown as { worksheetTestReceipts: WorksheetReport[] }).worksheetTestReceipts.at(-1)!);
  await setSource('; capture 😀\r\n"😀"\r\n(+ 40 2)\r\n-0.0');
  const captured = await page.locator('#source').evaluate(node => (node as CodeEditor).value);
  await run.click();
  await page.getByRole('status').filter({ hasText: 'Worksheet finished' }).waitFor();
  const first = await report();
  assert.equal(first.source.text, captured);
  assert.equal(first.observations.length, 3);
  for (const row of first.observations) assert.equal(first.source.text.slice(row.range.start, row.range.end), row.expression);
  assert.deepEqual(first.observations[0]!.outcome, { status: 'returned', value: { type: 'text', units: [55357, 56832] } });
  assert.deepEqual(first.observations[1]!.outcome, { status: 'returned', value: { type: 'int', value: '42' } });
  assert.equal(first.observations[2]!.preview, '-0.0');
  await notebookDownloads(page, captured);
  await page.getByRole('button', { name: 'Show expression in source', exact: true }).nth(1).click();
  await page.waitForFunction(() => {
    const view = document.querySelector<CodeEditor>('#source')?.view;
    return view && view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to) === '(+ 40 2)';
  });
  assert.equal(await page.locator('#source').evaluate(node => {
    const view = (node as CodeEditor).view!;
    return view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to);
  }), '(+ 40 2)');
  await page.locator('.worksheet-typed summary').nth(1).click();
  assert.match(await page.locator('.worksheet-typed[open]').innerText(), /"value": "42"/);
  await setSource('; new revision\n' + captured);
  await page.locator('.worksheet-stale').waitFor();
  assert.equal(await page.getByRole('button', { name: 'Show expression in source', exact: true }).nth(1).isDisabled(), true);
  assert.equal(await page.locator('#source').evaluate(node => (node as CodeEditor).dataset.marks), '');
  const staleExport: unknown = JSON.parse(await downloadNotebook(page, 'ipynb'));
  validateJupyterNotebook(staleExport);
  assert.ok(staleExport.cells.filter(cell => cell.cell_type === 'code').every(cell => cell.outputs?.length === 0),
    'Editing must never attach outputs from the previous worksheet revision');

  await setSource('1\nmissing\n2');
  await run.click();
  await page.getByRole('status').filter({ hasText: 'Worksheet stopped' }).waitFor();
  const failed = await report();
  assert.equal(failed.observations.length, 2);
  assert.equal(failed.completion.failure?.code, 'worksheet.evaluation_failed');
  assert.deepEqual(failed.diagnostic, { stage: 'evaluate', range: { start: 2, end: 9 } });
  assert.notEqual(await page.locator('#source').evaluate(node => (node as CodeEditor).dataset.marks), '');

  await setSource('(let loop () (loop))');
  await run.click();
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Worksheet cancelled' }).waitFor();
  const cancelled = await report();
  assert.equal(cancelled.completion.status, 'cancelled');
  assert.deepEqual(cancelled.observations, []);
  assert.deepEqual(cancelled.diagnostic, { stage: 'transport', range: null });

  await setSource('(let loop ((n 30) (x 1)) (if (= n 0) x (loop (- n 1) (vector x x))))');
  await run.click();
  await page.getByRole('status').filter({ hasText: 'Worksheet stopped' }).waitFor();
  assert.equal((await report()).completion.failure?.code, 'worksheet.output_limit');
  await setSource('(+ 2 2)');
  await run.click();
  await page.getByRole('status').filter({ hasText: 'Worksheet finished' }).waitFor();
  assert.deepEqual(await page.locator('.worksheet-result .value').allTextContents(), ['4']);
  await openNotebook(page, 'mixed.ipynb', JSON.stringify({nbformat: 4, nbformat_minor: 4,
    metadata: {language_info: {name: 'scheme'}}, cells: [
      {cell_type: 'code', metadata: {}, source: '42', outputs: [], execution_count: null},
      {cell_type: 'code', metadata: {language: 'python'}, source: 'print(1)', outputs: [], execution_count: null},
      {cell_type: 'markdown', metadata: {}, source: '# End'},
    ]}));
  await page.getByRole('status').filter({hasText: 'Opened mixed.ipynb'}).waitFor();
  assert.equal(await source.evaluate(node => (node as CodeEditor).value), '42\n\n;; # End\n');
  assert.match(await page.locator('body').innerText(), /skipped 1 cells/);
  await openNotebook(page, 'broken.ipynb', '{');
  await page.getByRole('status').filter({hasText: 'Notebook could not be opened'}).waitFor();
  assert.equal(await source.evaluate(node => (node as CodeEditor).value), '42\n\n;; # End\n');
  await openNotebook(page, 'source.dib', '#!scheme\n\n(+ 2 3)\n');
  await page.getByRole('status').filter({hasText: 'Opened source.dib'}).waitFor();
  // Lossless DIB parsing retains the blank source line after the kernel directive.
  assert.equal(await source.evaluate(node => (node as CodeEditor).value), '\n(+ 2 3)\n');
  return page.evaluate(() => (globalThis as unknown as { worksheetTestReceipts: WorksheetReport[] }).worksheetTestReceipts);
}

if (import.meta.main) {
  const cdp = process.argv[2];
  const server = cdp ? null : createWorkbenchServer();
  let browser;
  try {
    let page: Page;
    if (cdp) {
      browser = await chromium.connectOverCDP(cdp);
      const packaged = browser.contexts()[0]?.pages().find(page => new URL(page.url()).hostname === 'proton.localhost');
      assert.ok(packaged, 'The actual packaged Proton asset page must be present.');
      page = packaged;
    } else {
      server!.listen(0, '127.0.0.1');
      await once(server!, 'listening');
      browser = await chromium.launch({ headless: true });
      page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    }
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    if (cdp) await page.reload();
    else await page.goto(`http://127.0.0.1:${(server!.address() as AddressInfo).port}`);
    await gettingStarted(page);
    let workersClosed = 0;
    const closed: Promise<void>[] = [];
    page.on('worker', worker => closed.push(new Promise(resolve => worker.once('close', () => {
      workersClosed++;
      resolve();
    }))));
    const receipts = await worksheetWorkflow(page).catch(async error => {
      console.error((await page.locator('body').innerText()).slice(-8000));
      console.error(await page.evaluate(() => (globalThis as unknown as { worksheetTestReceipts?: unknown[] }).worksheetTestReceipts));
      throw error;
    });
    let deadline: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([Promise.all(closed), new Promise((_, reject) => {
        deadline = setTimeout(() => reject(new Error('An owned worksheet worker did not close.')), 5000);
      })]);
    } finally { clearTimeout(deadline); }
    assert.ok(closed.length >= 5, 'The workflow must observe actual browser workers.');
    assert.equal(workersClosed, closed.length);
    assert.equal(page.workers().length, 0);
    assert.deepEqual(errors, []);
    const runtime = cdp ? 'actual packaged Proton / production local worker' : 'real Chromium / production worker';
    const out = fileURLToPath(new URL(`../../../.dev/campaign-completion/worksheet-${cdp ? 'proton' : 'browser'}/`, import.meta.url));
    await mkdir(out, { recursive: true });
    await writeFile(`${out}/receipts.json`, JSON.stringify({ runtime, workersStarted: closed.length, workersClosed, receipts }, null, 2));
    await page.screenshot({ path: `${out}/worksheet.png`, fullPage: true });
    console.log('Worksheet browser workflow passed.');
  } finally {
    await browser?.close();
    if (server) await new Promise<void>(resolve => server.close(() => resolve()));
  }
}
