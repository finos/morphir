import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import type {AddressInfo} from 'node:net';
import {fileURLToPath} from 'node:url';
import {chromium, type Browser} from 'playwright';
import {createWorkbenchServer} from '../scripts/server.ts';
import {gettingStarted, createWorkspace, useSourceWorkspace, runCommand, build, waitForSourceDocument, replaceSourceDocument, openSample, showModel, replaceEvaluationArguments} from '../scripts/workbench-steps.ts';
import type {CodeEditor} from './editor/code-editor.ts';

test('a settled editor remains ready while its real user edit waits for the host echo', {timeout: 30000}, async () => {
  const server = createWorkbenchServer();
  let browser: Browser | undefined;
  let actual: {readyBeforeEcho: boolean; pending: boolean; sameKey: boolean; viewOwnsDraft: boolean} | undefined;
  try {
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    browser = await chromium.launch({headless: true, args: ['--password-store=basic', '--use-mock-keychain']});
    const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
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
  } finally {
    await browser?.close(); server.closeAllConnections();
    if (server.listening) await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
  assert.deepEqual(actual, {readyBeforeEcho: true, pending: true, sameKey: true, viewOwnsDraft: true});
});

test('file editing waits for the real selected document before browser insertion', {timeout: 30000}, async () => {
  const server = createWorkbenchServer();
  let browser: Browser | undefined;
  let actual: {before: {settled: boolean; held: boolean; key: string | null; document: string | undefined}; value: string; inputKeys: (string | null)[]} | undefined;
  try {
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    browser = await chromium.launch({headless: true, args: ['--password-store=basic', '--use-mock-keychain']});
    const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
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
  } finally {
    await browser?.close(); server.closeAllConnections();
    if (server.listening) await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
  // Real hooks, browser and server are disposed before the intended assertions.
  console.info(JSON.stringify({sourceTransition: actual}));
  assert.equal(actual?.before.held, true, 'the genuine import must reach a pending selected-document reconciliation');
  assert.notEqual(actual?.before.key, actual?.before.document);
  assert.equal(actual?.before.settled, false, 'the wait must not finish while the editor holds the previous document');
  assert.equal(actual?.value, '(define broken');
  assert.deepEqual(actual?.inputKeys, [actual!.before.document]);
});

test('argument editing waits for the real Ion-to-JSON transition and evaluates the exact JSON draft', {timeout: 30000}, async () => {
  const server = createWorkbenchServer();
  let browser: Browser | undefined;
  try {
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    browser = await chromium.launch({headless: true, args: ['--password-store=basic', '--use-mock-keychain']});
    const context = await browser.newContext({viewport: {width: 1440, height: 1000}});
    const page = await context.newPage(); page.setDefaultTimeout(10000);
    const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`);
    await createWorkspace(page, {name: 'Evaluation format transition'});
    await openSample(page, 'MoonBit String library');
    await build(page, 'Compile');
    await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
    await showModel(page);
    await page.locator('.model-tree .tree-item').filter({hasText: 'welcome'}).click();
    await page.getByRole('button', {name: 'Typed invocation', exact: true}).click();
    await page.getByRole('button', {name: 'Ion inputs', exact: true}).click();
    await page.waitForFunction(() => {
      const editor = document.querySelector<CodeEditor>('#evaluation-input');
      return editor?.dataset.document?.endsWith('-value|user:main#welcome-true-ion') &&
        editor.text.key === editor.dataset.document && !editor.queued && !editor.readOnly &&
        editor.view?.state.doc.toString() === editor.text.current;
    });
    const ionDocument = (await page.locator('#evaluation-input').getAttribute('data-document'))!;
    const documentKey = ionDocument.replace(/-ion$/, '-json');
    const text = JSON.stringify([{type: 'text', units: [55357, 56832]}, {type: 'bool', value: true}]);
    const held = await page.evaluateHandle(() => {
      const ion = document.querySelector<CodeEditor>('#evaluation-input')!;
      const original = ion.value, requestFrame = window.requestAnimationFrame;
      let armed = false, frame: FrameRequestCallback | undefined, released = false;
      const events: {type: string; document: string | null; focused: boolean; target: string}[] = [];
      const arm = (event: Event) => {
        if ((event.target as Element).closest('button')?.textContent?.trim() === 'JSON inputs') armed = true;
      };
      // Rabbita drains the real mode-change message immediately, then commits
      // its view on this frame. Hold only that commit, not browser polling.
      window.requestAnimationFrame = callback => {
        if (armed && !frame && !released) {frame = callback; armed = false; return 0;}
        return requestFrame.call(window, callback);
      };
      const capture = (event: Event) => {
        const editor = document.querySelector<CodeEditor>('#evaluation-input');
        events.push({type: event.type, document: editor?.text.key ?? null,
          focused: editor?.view?.hasFocus ?? false,
          target: event.composedPath()[0] instanceof Element ? (event.composedPath()[0] as Element).tagName : ''});
      };
      document.addEventListener('click', arm, true);
      for (const type of ['keydown', 'beforeinput', 'input']) document.addEventListener(type, capture, true);
      const release = async () => {
        released = true; window.requestAnimationFrame = requestFrame;
        const pending = frame; frame = undefined;
        if (pending) await new Promise<void>(resolve => requestFrame.call(window, time => {pending(time); resolve();}));
      };
      return {events, snapshot() {return {held: !!frame, original, value: ion.value,
        document: ion.dataset.document, key: ion.text.key, events: [...events]};}, release,
      async restore() {
        document.removeEventListener('click', arm, true);
        for (const type of ['keydown', 'beforeinput', 'input']) document.removeEventListener(type, capture, true);
        await release();
      }};
    });
    let waiting: Promise<void> | undefined;
    try {
      await page.getByRole('button', {name: 'JSON inputs', exact: true}).click();
      let settled = false;
      waiting = replaceEvaluationArguments(page, text, {format: 'json', document: documentKey}).then(() => {settled = true;});
      // Give readiness and keyboard operations browser turns while the genuine
      // application frame stays held. No timer or editor state is fabricated.
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const before = await held.evaluate(state => state.snapshot());
      console.info(JSON.stringify({evaluationTransitionHeld: {...before, settled}}));
      assert.equal(before.held, true, 'The actual JSON mode-change frame must be held');
      assert.equal(before.document, ionDocument);
      assert.equal(before.key, ionDocument);
      assert.equal(before.value, before.original, 'The previous Ion document must stay untouched');
      assert.deepEqual(before.events, [], 'No edit keys or input may reach the stale Ion editor or BODY');
      assert.equal(settled, false, 'Replacement cannot finish before the requested JSON document exists');
      await held.evaluate(state => state.release());
      await waiting;
      assert.deepEqual(await page.locator('#evaluation-input').evaluate(editor => {
        const input = editor as CodeEditor;
        return {document: input.dataset.document, key: input.text.key, language: input.dataset.language,
          value: input.value, current: input.text.current, rendered: input.text.rendered, queued: input.queued};
      }), {document: documentKey, key: documentKey, language: 'json', value: text, current: text, rendered: text, queued: false});
      const events = await held.evaluate(state => state.events);
      assert.ok(events.some(event => event.type === 'input'), 'The JSON draft must use real browser input');
      assert.ok(events.every(event => event.document === documentKey && event.focused && event.target !== 'BODY'),
        'Every edit event must belong to the focused current JSON view');
      await page.getByRole('button', {name: 'Evaluate', exact: true}).click();
      await page.getByRole('status').filter({hasText: 'Function evaluated'}).waitFor();
      await page.getByRole('button', {name: 'Result JSON', exact: true}).click();
      const units = Array.from({length: 'Hello, 😀'.length}, (_, i) => 'Hello, 😀'.charCodeAt(i));
      await page.waitForFunction(units => {
        const result = JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value ?? '{}');
        return result.type === 'text' && JSON.stringify(result.units) === JSON.stringify(units);
      }, units);
      console.info(JSON.stringify({evaluationTransitionReleased: {document: documentKey, arguments: text,
        result: await page.locator('#evaluation-output').evaluate(editor => (editor as CodeEditor).value), events}}));
      assert.deepEqual(errors, []);
    } finally {
      await held.evaluate(state => state.restore()); await waiting?.catch(() => {}); await held.dispose();
    }
  } finally {
    await browser?.close(); server.closeAllConnections();
    if (server.listening) await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
