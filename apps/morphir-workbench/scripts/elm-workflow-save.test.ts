import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import type { AddressInfo } from 'node:net';
import { fileURLToPath } from 'node:url';
import { chromium, type Browser, type BrowserContext } from 'playwright';
import { createWorkbenchServer } from './server.ts';
import { waitForSavedCoreSource } from './elm-workflow.ts';
import { createWorkspace, runCommand, build, replaceSourceDocument, gettingStarted, reopenWorkspace } from './workbench-steps.ts';
import type { CodeEditor } from '../browser/editor/code-editor.ts';

test('reload waits for the active workspace edit even when imported sidecars and another saved workspace match', async () => {
  const server = createWorkbenchServer();
  let browser: Browser | undefined;
  let context: BrowserContext | undefined;
  let failed = false;
  try {
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    browser = await chromium.launch({ headless: true, args: ['--password-store=basic', '--use-mock-keychain'] });
    context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    const page = await context.newPage();
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`);
    const name = 'Edited source save barrier';
    await createWorkspace(page, { name });
    const chooser = page.waitForEvent('filechooser');
    await runCommand(page, 'Import folder…');
    await (await chooser).setFiles(fileURLToPath(new URL('./fixtures/folder-import/monorepo', import.meta.url)));
    const row = (path: string) => page.locator('[role="treeitem"][title=' + JSON.stringify(path) + ']');
    await row('packages/core/src/main.scm').waitFor();
    await build(page, 'Compile');
    await page.getByRole('status').filter({ hasText: 'Compiled 2/2 projects' }).waitFor();
    await row('packages/core/src/main.scm').click();
    const original = await page.locator('#source').evaluate(editor => (editor as CodeEditor).value);
    await waitForSavedCoreSource(page, original);
    const workspaceId = (await page.locator('#source').getAttribute('data-document'))!.split('|')[1]!;
    const expected = '(define broken';
    const held = await page.evaluateHandle(({ workspaceId, expected }) => {
      const treeKey = `morphir-workbench.workspace.${workspaceId}.tree.v1`;
      const importedTree = JSON.parse(localStorage.getItem(treeKey)!);
      // A different saved workspace satisfies even the exact-source condition.
      // Only the active workspace must be allowed to unblock the reload.
      const otherTreeKey = 'morphir-workbench.workspace.other-save-regression.tree.v1';
      const otherCoreKey = 'morphir-workbench.workspace.other-save-regression.core';
      localStorage.setItem(otherCoreKey, JSON.stringify(expected));
      localStorage.setItem(otherTreeKey, JSON.stringify({ ...importedTree,
        files: { ...importedTree.files, 'packages/core/src/main.scm': otherCoreKey } }));
      const setTimeout = window.setTimeout;
      const getItem = Storage.prototype.getItem;
      const saves: (() => void)[] = [];
      let polls = 0;
      // Hold the application's real debounce callbacks, without changing files,
      // editor events, revisions or the save implementation.
      window.setTimeout = ((callback: TimerHandler, delay?: number, ...args: unknown[]) => {
        if (delay !== 600 || typeof callback !== 'function') return setTimeout(callback, delay, ...args);
        saves.push(() => callback(...args));
        return -saves.length;
      }) as typeof window.setTimeout;
      Storage.prototype.getItem = function (key) {
        if (this === localStorage && key === treeKey) ++polls;
        return getItem.call(this, key);
      };
      return {
        snapshot() {
          const manifest = JSON.parse(getItem.call(localStorage, treeKey)!);
          return { polls, callbacks: saves.length,
            core: JSON.parse(getItem.call(localStorage, manifest.files['packages/core/src/main.scm'])!),
            binary: JSON.parse(getItem.call(localStorage, manifest.files['models/original.bin'])!),
            notes: JSON.parse(getItem.call(localStorage, manifest.files['notes.md'])!) };
        },
        release() { for (const save of saves.splice(0)) save(); },
        restore() {
          window.setTimeout = setTimeout;
          Storage.prototype.getItem = getItem;
          localStorage.removeItem(otherTreeKey);
          localStorage.removeItem(otherCoreKey);
        },
      };
    }, { workspaceId, expected });
    let waiting: Promise<void> | undefined;
    let resolved = false;
    try {
      await replaceSourceDocument(page, expected, 'packages/core/src/main.scm');
      await build(page, 'Compile');
      await page.getByRole('status').filter({ hasText: 'Compiled 1/2 projects' }).waitFor();
      await row('packages/utils/src/main.scm').click();
      await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('identity'));
      waiting = waitForSavedCoreSource(page, expected).then(() => { resolved = true; });
      // Observe an actual barrier poll, then let its browser reply settle while
      // persistence is held. An immediate or all-workspaces guard must fail here.
      await page.waitForFunction(state => state.snapshot().polls > 0, held);
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const before = await held.evaluate(state => state.snapshot());
      assert.ok(before.callbacks > 0, 'The real edited-source save is held');
      assert.equal(before.core, original, 'The active tree still contains the original import');
      assert.equal(before.binary.content, 'AP+A', 'The old binary guard already passes');
      assert.equal(before.notes, '\ufeffkeep\r\n', 'The old notes guard already passes');
      assert.equal(resolved, false, 'Sidecars and another workspace cannot satisfy the edited-source barrier');
      await held.evaluate(state => state.release());
      await waiting;
      assert.equal(await held.evaluate(state => state.snapshot().core), expected);
    } finally {
      await held.evaluate(state => { state.restore(); state.release(); });
      await waiting?.catch(() => {});
      await held.dispose();
    }
    await page.reload();
    await gettingStarted(page);
    await reopenWorkspace(page, name);
    await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
    await row('packages/core/src/main.scm').click();
    await page.waitForFunction(expected => document.querySelector<CodeEditor>('#source')?.value === expected, expected);
    await row('models/original.bin').waitFor();
    await waitForSavedCoreSource(page, expected);
    assert.deepEqual(errors, []);
  } catch (error) {
    failed = true;
    throw error;
  } finally {
    const cleanupErrors: unknown[] = [];
    for (const close of [
      () => context?.close(),
      () => browser?.close(),
      () => {
        if (!server.listening) return;
        server.closeAllConnections();
        return new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      },
    ]) {
      try { await close(); } catch (error) { cleanupErrors.push(error); }
    }
    if (!failed && cleanupErrors.length > 0) throw cleanupErrors[0];
  }
});
