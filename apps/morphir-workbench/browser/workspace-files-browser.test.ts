import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { createInterface } from 'node:readline';
import { chromium } from 'playwright';
import type { AddressInfo } from 'node:net';
import { createWorkbenchServer } from '../scripts/server.ts';
import { fillNewProject, gettingStarted } from '../scripts/workbench-steps.ts';
import type { CodeEditor } from './editor/code-editor.ts';

async function savedText(path: string, expected: string) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    const value = await readFile(path, 'utf8').catch(() => null);
    if (value === expected) return;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.equal(await readFile(path, 'utf8'), expected);
}

test('browser workspace edits reach the real native owner and stale saves retain the local draft', { timeout: 90000 }, async () => {
  const base = await mkdtemp(join(tmpdir(), 'morphir-file-browser-'));
  const root = join(base, 'workspace'); await mkdir(root);
  const binary = Buffer.from([0, 255, 128, 13, 10]);
  await mkdir(join(root, 'models')); await writeFile(join(root, 'models/original.ionb'), binary);
  const executable = resolve(import.meta.dirname, '../../../_build/native/debug/build/finos/morphir-workbench-native/files-acceptance/files-acceptance.exe');
  const owner = spawn(executable, [root], { stdio: ['pipe', 'pipe', 'pipe'] });
  let stderr = ''; owner.stderr.on('data', chunk => { stderr += chunk; });
  const pending: { resolve(value: string): void; reject(error: Error): void }[] = [];
  const lines = createInterface({ input: owner.stdout });
  lines.on('line', line => pending.shift()?.resolve(line));
  owner.on('error', error => { for (const item of pending.splice(0)) item.reject(error); });
  owner.on('exit', () => { for (const item of pending.splice(0)) item.reject(new Error(`Native owner exited: ${stderr}`)); });
  const server = createWorkbenchServer(); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const errors: string[] = [];
  try {
    await context.route('https://proton.localhost/**', async route => {
      const url = new URL(route.request().url());
      const origin = new URL(`http://127.0.0.1:${(server.address() as AddressInfo).port}`);
      const response = await route.fetch({ url: new URL(url.pathname + url.search, origin).href,
        headers: { ...route.request().headers(), host: origin.host, origin: origin.origin, 'sec-fetch-site': 'same-origin' } });
      await route.fulfill({ response });
    });
    await context.exposeBinding('nativeFileRequest', async (_binding, source: string) => {
      const frame = JSON.parse(source);
      if (frame.profile === 'morphir/workbench/native') {
        return JSON.stringify({ ok: true, operation: frame.operation, value: frame.operation === 'session.close' ? {} : {
          profile: frame.profile, contractVersion: frame.contractVersion, sessionId: 'browser-native-page', operations: ['workspace'],
        } });
      }
      return new Promise<string>((resolve, reject) => { pending.push({ resolve, reject }); owner.stdin.write(source + '\n'); });
    });
    await context.addInitScript(() => {
      globalThis.__MoonBit__ = { core: { invokeOp: (_name, source) => (globalThis as unknown as { nativeFileRequest(source: string): Promise<string> }).nativeFileRequest(source) } };
    });
    const page = await context.newPage(); page.on('pageerror', error => errors.push(error.message));
    await page.goto('https://proton.localhost/'); await gettingStarted(page);
    await page.getByRole('button', { name: 'Open a workspace', exact: true }).click();
    await page.getByRole('button', { name: 'Open a workspace folder…', exact: true }).click();
    await page.getByRole('button', { name: 'Add project…', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Add project…', exact: true }).click();
    await fillNewProject(page, 'Quotes', 'packages/quotes', 'scheme');
    await page.getByRole('button', { name: 'Create project', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Workspace folder saved' }).waitFor();
    assert.match(await readFile(join(root, 'morphir.toml'), 'utf8'), /members = \["packages\/quotes"\]/);
    assert.match(await readFile(join(root, 'packages/quotes/morphir.toml'), 'utf8'), /Quotes/);
    await page.locator('button[role="treeitem"][title="packages/quotes/src/main.scm"]').click();
    // Fill only once the editor shows the opened file: a later switch would replace the selection and keep the typed text.
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value === '(define (identity value) value)\n');
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(+ 20 22)');
    await savedText(join(root, 'packages/quotes/src/main.scm'), '(+ 20 22)');
    await page.getByRole('status').filter({ hasText: 'Workspace folder saved' }).waitFor();
    assert.equal(await readFile(join(root, 'packages/quotes/src/main.scm'), 'utf8'), '(+ 20 22)');
    assert.deepEqual(await readFile(join(root, 'models/original.ionb')), binary);
    await writeFile(join(root, 'packages/quotes/src/main.scm'), 'external edit');
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(+ 30 12)');
    await page.getByRole('status').filter({ hasText: 'workspace request was refused' }).waitFor();
    assert.equal(await readFile(join(root, 'packages/quotes/src/main.scm'), 'utf8'), 'external edit');
    assert.equal(await page.locator('#source').evaluate(element => (element as CodeEditor).value), '(+ 30 12)');
    assert.deepEqual(errors, []);
  } finally {
    await context.close(); await browser.close();
    await new Promise<void>(resolve => server.close(() => resolve()));
    owner.stdin.end(); if (owner.exitCode === null) await once(owner, 'exit'); lines.close();
    await rm(base, { recursive: true, force: true });
  }
});
