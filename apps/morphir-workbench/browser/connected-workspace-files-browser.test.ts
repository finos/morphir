import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addAbortListener, once } from 'node:events';
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium, type Browser, type BrowserContext, type Page } from 'playwright';
import type { AddressInfo } from 'node:net';
import type { CodeEditor } from './editor/code-editor.ts';
import { createWorkbenchServer } from '../scripts/server.ts';
import { fillNewProject } from '../scripts/workbench-steps.ts';
import { nativeFileHost } from './native-test-fixture.ts';
import { workspaceFilesProfile as profile, workspaceFilesVersion as version } from './workspace-files.ts';

async function savedText(path: string, expected: string) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    if (await readFile(path, 'utf8').catch(() => null) === expected) return;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.equal(await readFile(path, 'utf8'), expected);
}

// Observe the existing bridge callback without another global or a product hook.
// The handle retains only the single actual request/reply, and forwards the same reply to the app.
async function captureWorksheet(page: Page) {
  return page.evaluateHandle(() => {
    const original = globalThis.morphirWorkbench.request;
    const observation = {calls: 0, received: null as {source: string; request: string | undefined; reply: string} | null};
    globalThis.morphirWorkbench.request = (request, receive) => {
      const source = request.source, captured = request.worksheetRequest;
      return original(request, raw => {
        if (request.operation === 'worksheet') {
          observation.calls++;
          if (observation.calls === 1) observation.received = {source: source!, request: captured, reply: raw};
        }
        receive(raw);
      });
    };
    return {observation, restore() {globalThis.morphirWorkbench.request = original;}};
  });
}

interface FixtureOwners {
  base: string;
  host: ReturnType<typeof nativeFileHost>;
  server: ReturnType<typeof createWorkbenchServer>;
  browser: Browser;
  context: BrowserContext;
}
type ReplyOrder = 'ordinary' | 'save-after-report' | {
  kind: 'cancel-before-commit';
  cancel(): void;
  retainOwners(actual: FixtureOwners): void;
  disposalFailure: Error | null;
};

async function waitForFixtureBoundary(entered: Promise<void>, signal: AbortSignal) {
  signal.throwIfAborted();
  let listener: Disposable | undefined;
  try {
    await Promise.race([entered, new Promise<never>((_, reject) => {
      listener = addAbortListener(signal, () => reject(signal.reason));
    })]);
  } finally { listener?.[Symbol.dispose](); }
}

async function connectedFilesWorkflow(order: ReplyOrder, signal: AbortSignal) {
  signal.throwIfAborted();
  const scenario = typeof order === 'string' ? null : order;
  const base = await mkdtemp(join(tmpdir(), 'morphir-connected-files-'));
  const root = join(base, 'workspace'); await mkdir(join(root, 'models'), { recursive: true });
  const binary = Buffer.from([0, 255, 128, 13, 10]); await writeFile(join(root, 'models/raw.ionb'), binary);
  await writeFile(join(base, 'outside'), 'SECRET');
  const host = nativeFileHost(root);
  const source = { providerId: 'workspace', locator: 'workspace://fixture', displayName: 'Connected fixture' };
  const manifest = { protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'fixture-session',
    providers: [{ id: source.providerId, status: 'available', capabilities: [{ name: profile, version }] }], initialSources: [source] };
  const server = createWorkbenchServer(); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const methods: string[] = [], errors: string[] = [];
  let worksheetSequence: unknown;
  let releaseCommit!: () => void, enteredCommit!: () => void;
  const commitEntered = new Promise<void>(resolve => {enteredCommit = resolve;});
  const commitRelease = new Promise<void>(resolve => {releaseCommit = resolve;});
  let releaseWrite!: () => void, enteredWrite!: () => void;
  const writeEntered = new Promise<void>(resolve => {enteredWrite = resolve;});
  const writeRelease = new Promise<void>(resolve => {releaseWrite = resolve;});
  let worksheet: Awaited<ReturnType<typeof captureWorksheet>> | undefined;
  try {
    scenario?.retainOwners({base, host, server, browser, context});
    await context.route('**/api/session', route => route.fulfill({ json: manifest }));
    await context.routeWebSocket('**/rpc', socket => socket.onMessage(async message => {
      const request = JSON.parse(String(message)); methods.push(request.method);
      try {
        let result: unknown;
        if (request.method === 'morphir.session.initialize') result = {};
        else {
          assert.equal(request.method, 'morphir.workspace-files.exchange');
          assert.equal(request.params.protocolVersion, 1); assert.equal(request.params.sessionId, manifest.sessionId);
          assert.deepEqual(request.params.source, source);
          const frame = JSON.parse(request.params.frame);
          if (order !== 'ordinary' && frame.operation === 'workspace.write') {
            const snapshot = JSON.parse(Buffer.from(frame.payload.content, 'base64').toString('utf8'));
            if (snapshot.files['worksheet.scm'] === '(identity 42)') worksheetSequence = frame.payload.sequence;
          }
          result = await host.exchange(request.params.frame);
          if (scenario && frame.operation === 'workspace.write' && frame.payload.sequence === worksheetSequence) {
            enteredWrite(); await writeRelease;
          }
          if (order !== 'ordinary' && frame.operation === 'workspace.commit' && frame.payload.sequence === worksheetSequence) {
            enteredCommit(); await commitRelease;
          }
        }
        socket.send(JSON.stringify({ jsonrpc: '2.0', id: request.id, result }));
      } catch (error) { socket.send(JSON.stringify({ jsonrpc: '2.0', id: request.id, error: { code: -32603, message: String(error) } })); }
    }));
    const page = await context.newPage(); page.on('pageerror', error => errors.push(error.message)); page.setDefaultTimeout(15000);
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected`);
    await page.getByRole('button', { name: 'Add project…', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Add project…', exact: true }).click();
    await fillNewProject(page, 'Quotes', 'packages/quotes', 'scheme');
    await page.getByRole('button', { name: 'Create project', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Workspace folder saved' }).waitFor();
    assert.match(await readFile(join(root, 'morphir.toml'), 'utf8'), /members = \["packages\/quotes"\]/);
    assert.match(await readFile(join(root, 'packages/quotes/morphir.toml'), 'utf8'), /Quotes/);
    await page.getByRole('button', { name: 'Compile workspace', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Compiled 1/1 projects' }).waitFor();
    await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
    // Wait for the intended worksheet document, not merely the click returning.
    await page.waitForFunction(() => {
      const editor = document.querySelector<CodeEditor>('#source');
      return editor?.isConnected && !editor.queued && !editor.readOnly &&
        editor.dataset.document?.startsWith('worksheet-source|') &&
        editor.text.key === editor.dataset.document &&
        editor.view?.state.doc.toString() === editor.text.current &&
        editor.text.current === editor.text.rendered;
    });
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(identity 42)');
    worksheet = await captureWorksheet(page);
    if (scenario?.disposalFailure) {
      const failure = scenario.disposalFailure;
      worksheet.dispose = async () => {throw failure;};
    }
    await page.getByRole('button', { name: 'Run worksheet', exact: true }).click();
    await page.waitForFunction(state => state.observation.calls === 1, worksheet);
    const observed = await worksheet.evaluate(state => state.observation.received!);
    assert.equal(observed.source, '(identity 42)');
    const capture = JSON.parse(observed.request!);
    const report = JSON.parse(JSON.parse(observed.reply).worksheetReport);
    assert.equal(capture.source.text, '(identity 42)');
    assert.deepEqual(report.source, capture.source);
    assert.deepEqual(report.completion, {status: 'returned', value: {type: 'unit'}});
    assert.equal(report.diagnostic, null);
    assert.equal(report.observations.length, 1);
    assert.equal(report.observations[0].expression, '(identity 42)');
    assert.deepEqual(report.observations[0].outcome, {status: 'returned', value: {type: 'int', value: '42'}});
    await page.locator('.worksheet-observation pre.value').filter({ hasText: '42' }).waitFor();
    if (order !== 'ordinary') {
      if (scenario) {
        await waitForFixtureBoundary(writeEntered, signal);
        // Cancel while the real write reply is held and no commit can yet arrive.
        // Then let old code finish normally so its failing control never leaks the actual fixture.
        queueMicrotask(() => {scenario.cancel(); releaseWrite();});
      }
      await waitForFixtureBoundary(commitEntered, signal);
      releaseCommit();
      await page.getByRole('status').filter({ hasText: 'Workspace folder saved' }).waitFor();
    }
    await savedText(join(root, 'worksheet.scm'), '(identity 42)');
    assert.deepEqual(await page.locator('.worksheet-observation pre.value').allTextContents(), ['42']);
    assert.equal(await page.locator('.worksheet-expression code').textContent(), '(identity 42)');
    assert.equal(await page.locator('.worksheet-completion').count(), 0);
    assert.equal(await page.locator('.worksheet-stale').count(), 0);
    assert.equal(await page.getByRole('button', {name: 'Show expression in source', exact: true}).isDisabled(), false);
    assert.equal(await page.locator('#source').evaluate(element => (element as CodeEditor).value), '(identity 42)');
    await page.locator('button[role="treeitem"][title="packages/quotes/src/main.scm"]').click();
    // As with the worksheet, fill only once the editor shows the opened file.
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value === '(define (identity value) value)\n');
    await writeFile(join(root, 'packages/quotes/src/main.scm'), 'external edit');
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('33');
    await page.getByRole('status').filter({ hasText: 'workspace request was refused' }).waitFor();
    assert.equal(await readFile(join(root, 'packages/quotes/src/main.scm'), 'utf8'), 'external edit');
    assert.equal(await page.locator('#source').evaluate(element => (element as CodeEditor).value), '33');
    assert.deepEqual(await readFile(join(root, 'models/raw.ionb')), binary);
    assert.equal(await readFile(join(base, 'outside'), 'utf8'), 'SECRET');
    assert.equal(methods.includes('morphir.playground.compile'), false);
    assert.deepEqual(errors, []);
  } finally {
    releaseWrite();
    releaseCommit();
    // Observation teardown must not replace the workflow's error or skip its actual owners.
    try { await worksheet?.evaluate(state => state.restore()); } catch {}
    try { await worksheet?.dispose(); } catch {}
    await context.close(); await browser.close(); await new Promise<void>(resolve => server.close(() => resolve()));
    await host.close(); await rm(base, { recursive: true, force: true });
  }
}

test('negotiated connected files create a project on the provider and compile or run worksheets locally', {timeout: 90000}, async t => {
  await connectedFilesWorkflow('ordinary', t.signal);
});

test('a matching completed worksheet survives its actual native save reply arriving afterward', {timeout: 90000}, async t => {
  await connectedFilesWorkflow('save-after-report', t.signal);
});

for (const disposal of ['normal', 'raises'] as const) test(`cancel before the actual native commit preserves cause and closes real owners when observation disposal ${disposal}`, {timeout: 90000}, async t => {
  const controller = new AbortController(), reason = new Error('caller cancelled before native commit');
  let owners: FixtureOwners | undefined;
  let result: {kind: 'returned'} | {kind: 'raised'; error: unknown};
  try {
    await connectedFilesWorkflow({
      kind: 'cancel-before-commit', cancel() {controller.abort(reason);},
      retainOwners(actual) {owners = actual;},
      disposalFailure: disposal === 'raises' ? new Error('observation disposal failed') : null,
    }, AbortSignal.any([t.signal, controller.signal]));
    result = {kind: 'returned'};
  } catch (error) { result = {kind: 'raised', error}; }
  assert.ok(owners, 'the genuine browser/server/native fixture must have started');
  const beforeRescue = {
    browserConnected: owners.browser.isConnected(), serverListening: owners.server.listening,
    directoryExists: await stat(owners.base).then(() => true, error => {if (error.code === 'ENOENT') return false; throw error;}),
  };
  // Rescue the old failing implementation before asserting. host.close awaits the real native child exit/code.
  const cleanupErrors: unknown[] = [];
  await owners.context.close().catch(error => {cleanupErrors.push(error);});
  await owners.browser.close().catch(error => {cleanupErrors.push(error);});
  if (owners.server.listening) await new Promise<void>(resolve => owners!.server.close(() => resolve()));
  await owners.host.close().catch(error => {cleanupErrors.push(error);});
  await rm(owners.base, {recursive: true, force: true});
  assert.deepEqual(cleanupErrors, []);
  assert.deepEqual(beforeRescue, {browserConnected: false, serverListening: false, directoryExists: false});
  assert.equal(result.kind, 'raised');
  if (result.kind === 'raised') assert.equal(result.error, reason);
});

test('an unchanged editor render preserves select-all until browser text replacement', {timeout: 30000}, async () => {
  const server = createWorkbenchServer(); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  const page = await browser.newPage();
  try {
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`);
    await page.evaluate(async () => {
      await customElements.whenDefined('morphir-code-editor');
      const editor = document.createElement('morphir-code-editor') as CodeEditor;
      editor.id = 'fill-regression'; editor.dataset.document = 'stable-document';
      editor.dataset.readonly = 'false'; editor.setAttribute('aria-label', 'Replacement regression');
      editor.value = '; old worksheet\n(define (square x) (* x x))\n(square 7)';
      document.body.append(editor);
    });
    const input = page.getByRole('textbox', {name: 'Replacement regression', exact: true});
    await input.selectText();
    // A host render may update metadata after select-all but before the browser inserts replacement text.
    await page.locator('#fill-regression').evaluate((element: CodeEditor) => element.setAttribute('data-marks', ''));
    await page.keyboard.insertText('(identity 42)');
    assert.equal(await page.locator('#fill-regression').evaluate((element: CodeEditor) => element.value), '(identity 42)');
    // Exercise real focus and replacement repeatedly to cross CodeMirror's delayed focus notification.
    // Every replacement must succeed; this is a bounded race regression, never a retry-until-success loop.
    for (let attempt = 0; attempt < 60; attempt++) {
      await page.locator('#fill-regression').evaluate((element: CodeEditor) => {
        element.value = '; old worksheet\n(define (square x) (* x x))\n(square 7)';
        (element.shadowRoot.activeElement as HTMLElement | null)?.blur();
      });
      await input.fill('(identity 42)');
      assert.equal(await page.locator('#fill-regression').evaluate((element: CodeEditor) => element.value), '(identity 42)', `replacement ${attempt}`);
    }
  } finally {
    await page.close(); await browser.close(); await new Promise<void>(resolve => server.close(() => resolve()));
  }
});
