import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import type {AddressInfo} from 'node:net';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
import {createWorkbenchServer} from '../scripts/server.ts';
import {gettingStarted, createWorkspace, useSourceWorkspace, runCommand, build, waitForSourceDocument, replaceSourceDocument} from '../scripts/workbench-steps.ts';
import type {CodeEditor} from './editor/code-editor.ts';

test('a settled editor remains ready while its real user edit waits for the host echo', {timeout: 30000}, async () => {
  const server = createWorkbenchServer(); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
  let actual: {readyBeforeEcho: boolean; pending: boolean; sameKey: boolean; viewOwnsDraft: boolean} | undefined;
  try {
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`); await gettingStarted(page);
    await createWorkspace(page, {preset: 'Source project', name: 'Pending editor echo'});
    await waitForSourceDocument(page, 'src/main.scm');
    const held = await page.evaluateHandle(() => {
      const editor = document.querySelector<CodeEditor>('#source')!;
      const hold = (event: Event) => event.stopImmediatePropagation();
      editor.addEventListener('input', hold, {capture: true});
      return {snapshot() {return {pending: editor.text.current !== editor.text.rendered,
        sameKey: editor.text.key === editor.dataset.document, viewOwnsDraft: editor.view?.state.doc.toString() === editor.text.current};},
      release() {editor.removeEventListener('input', hold, {capture: true});
        editor.dispatchEvent(new InputEvent('input', {bubbles: true, composed: true, inputType: 'insertText'}));}};
    });
    let waiting: Promise<void> | undefined;
    try {
      const editor = page.getByRole('textbox', {name: 'Source editor', exact: true});
      await editor.press('ControlOrMeta+End'); await page.keyboard.insertText('\n; retained user draft');
      let readyBeforeEcho = false;
      waiting = waitForSourceDocument(page, 'src/main.scm').then(() => {readyBeforeEcho = true;});
      // Two real animation frames let the browser readiness poll and its reply
      // complete while the actual host input event remains held. No fabricated
      // editor text, key, queue, readOnly flag or helper result is installed.
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      actual = {readyBeforeEcho, ...await held.evaluate(state => state.snapshot())};
    } finally {await held.evaluate(state => state.release()); await waiting; await held.dispose();}
  } finally {await browser.close(); await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));}
  assert.deepEqual(actual, {readyBeforeEcho: true, pending: true, sameKey: true, viewOwnsDraft: true});
});

test('file editing waits for the real selected document before browser insertion', {timeout: 30000}, async () => {
  const server = createWorkbenchServer(); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
  let actual: {before: {settled: boolean; held: boolean; key: string | null; document: string | undefined}; value: string; inputKeys: (string | null)[]} | undefined;
  try {
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`); await gettingStarted(page);
    await createWorkspace(page, {preset: 'Source project', name: 'Source transition'});
    await useSourceWorkspace(page, 'elm');
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('module Workbench.Main'));
    const trace = await page.evaluateHandle(() => {
      const prototype = customElements.get('morphir-code-editor')!.prototype as CodeEditor;
      const reconcile = prototype.reconcile, hooked = new WeakSet<CodeEditor>();
      let held: CodeEditor | undefined, holdOnce = true;
      const inputKeys: (string | null)[] = [], undo: (() => void)[] = [];
      const release = () => {if (held) {const editor = held; held = undefined; reconcile.call(editor);}};
      prototype.reconcile = function () {
        if (!hooked.has(this)) {
          hooked.add(this);
          const listener = () => {release(); inputKeys.push(this.text.key);};
          this.shadowRoot!.addEventListener('beforeinput', listener, true);
          undo.push(() => this.shadowRoot!.removeEventListener('beforeinput', listener, true));
        }
        if (held === this) return;
        if (holdOnce && this.id === 'source' && this.dataset.document?.endsWith('|packages/core/src/main.scm') && this.text.key?.includes('|elm|')) {
          holdOnce = false; held = this; return;
        }
        return reconcile.call(this);
      };
      return {release, inputKeys, snapshot() {
        const editor = document.querySelector<CodeEditor>('#source')!;
        return {held: held !== undefined, key: editor.text.key, document: editor.dataset.document};
      }, restore() {release(); prototype.reconcile = reconcile; for (const undoHook of undo) undoHook();}};
    });
    let waiting: Promise<void> | undefined;
    try {
      const chooser = page.waitForEvent('filechooser'); await runCommand(page, 'Import folder…');
      await (await chooser).setFiles(fileURLToPath(new URL('../scripts/fixtures/folder-import/monorepo', import.meta.url)));
      const row = page.locator('[role="treeitem"][title="packages/core/src/main.scm"]'); await row.waitFor();
      await build(page, 'Compile'); await page.getByRole('status').filter({hasText: 'Compiled 2/2 projects'}).waitFor();
      await row.click();
      let settled = false;
      waiting = waitForSourceDocument(page, 'packages/core/src/main.scm').then(() => {settled = true;});
      // A browser round-trip lets an immediate/no-op wait settle while the real
      // document is still held. This changes scheduling, never application data.
      const snapshot = await trace.evaluate(state => state.snapshot());
      const before = {...snapshot, settled};
      if (!settled) await trace.evaluate(state => state.release());
      await waiting;
      await replaceSourceDocument(page, '(define broken', 'packages/core/src/main.scm');
      actual = {before, value: await page.locator('#source').evaluate(editor => (editor as CodeEditor).value),
        inputKeys: await trace.evaluate(state => state.inputKeys)};
    } finally {
      await trace.evaluate(state => state.restore()); await waiting?.catch(() => {}); await trace.dispose();
    }
  } finally {await browser.close(); await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));}
  // Real hooks, browser and server are disposed before the intended assertions.
  console.info(JSON.stringify({sourceTransition: actual}));
  assert.equal(actual?.before.held, true, 'the genuine import must reach a pending selected-document reconciliation');
  assert.notEqual(actual?.before.key, actual?.before.document);
  assert.equal(actual?.before.settled, false, 'the wait must not finish while the editor holds the previous document');
  assert.equal(actual?.value, '(define broken');
  assert.deepEqual(actual?.inputKeys, [actual!.before.document]);
});
