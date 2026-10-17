import type { CodeEditor } from '../browser/editor/code-editor.ts';
import type { Invoke, NativeReply, NativeDescriptor, CoreReply, WorkResult } from '../browser/contracts.ts';
import type { AddressInfo } from 'node:net';
import { malformed } from '../../../tests/helpers.ts';
import assert from 'node:assert/strict';
import { chromium, type FileChooser } from 'playwright';
import { fileURLToPath } from 'node:url';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { readFile, readdir } from 'node:fs/promises';
import { basename, join, relative, sep } from 'node:path';
import { elmWorkflow, moonbitWorkflow, libraryWorkflow } from './elm-workflow.ts';
import { toolPanelWorkflow, terminalOutcomeWorkflow } from './tool-panel-workflow.ts';

// CEF cancels CDP directory enumeration even though ordinary file uploads work.
// Replay the selected files at the DOM input boundary; production readFiles,
// bounded import and compilation still run. Chromium tests the real directory
// upload. This does not qualify the OS folder dialog or native workspace grants.
async function selectCefFolder(chooser: FileChooser, directory: string): Promise<void> {
  const files: { name: string; path: string; bytes: number[] }[] = [];
  for (const entry of await readdir(directory, { recursive: true, withFileTypes: true })) {
    if (!entry.isFile()) continue;
    const path = join(entry.parentPath, entry.name);
    files.push({ name: entry.name, path: basename(directory) + '/' + relative(directory, path).split(sep).join('/'),
      bytes: Array.from(await readFile(path)) });
  }
  assert.equal(files.length, 2, 'The complete rentals folder fixture is selected');
  // File metadata added in Playwright's utility world is invisible to the app.
  await chooser.page().evaluate(({ input, files }) => {
    if (!(input instanceof HTMLInputElement) || input.type !== 'file' || !input.webkitdirectory) {
      throw new Error('Folder import must request a directory file input');
    }
    const selection = new DataTransfer();
    for (const { name, path, bytes } of files) {
      const file = new File([new Uint8Array(bytes)], name);
      Object.defineProperty(file, 'webkitRelativePath', { value: path });
      selection.items.add(file);
    }
    input.files = selection.files;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }, { input: chooser.element(), files });
  const mainPaths = await chooser.page().evaluate(input => Array.from((input as HTMLInputElement).files!, file => file.webkitRelativePath), chooser.element());
  assert.deepEqual(mainPaths, files.map(file => file.path), 'The application sees the selected directory-relative paths');
}

if (!process.argv[2]) throw new Error('Usage: node scripts/desktop-test.js http://127.0.0.1:<cdp-port>');
const browser = await chromium.connectOverCDP(process.argv[2]);
try {
  const page = browser.contexts()[0]!.pages().find(page => page.url().includes('proton.localhost'));
  assert.ok(page, 'Packaged Proton asset page is present');
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  // Optional continuation after choosing this fixture with the real OS picker.
  // No test bridge accepts a filesystem path or bypasses user folder selection.
  if (process.argv[3]) {
    const fixture = process.argv[3];
    // CEF does not emit Playwright's browser Download event. Capture the exact
    // Blob passed to the normal anchor download without opening a save dialog.
    await page.evaluate(() => {
      const original = URL.createObjectURL.bind(URL);
      URL.createObjectURL = blob => {
        globalThis.workspaceDownload = (blob as Blob).arrayBuffer().then(bytes => Array.from(new Uint8Array(bytes)));
        return original(blob);
      };
      document.addEventListener('click', event => { if (event.target instanceof HTMLAnchorElement && event.target.download) event.preventDefault(); }, true);
    });
    for (const [label, relative, model] of [
      ['demo/rich · rich/morphir-ir.ion', 'rich/morphir-ir.ion', 'user'],
      ['demo/rich · rich/morphir-ir.ionb', 'rich/morphir-ir.ionb', 'user'],
      ['demo/legacy', 'legacy/morphir-ir.json', 'morphir/example/app'],
    ] as const) {
      await page.getByRole('button', { name: label, exact: true }).click();
      await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
      await page.getByRole('heading', { name: model, exact: true }).waitFor();
      await page.getByRole('button', { name: 'Original file', exact: true }).click();
      const original: Buffer = Buffer.from(await page.evaluate(() => globalThis.workspaceDownload));
      assert.deepEqual(original, await readFile(join(fixture, relative!)), 'Original checkpoint download Blob is byte exact');
    }
    await page.reload();
    console.log('Real picker continuation passed: Ion text/binary and legacy JSON inspect, byte-exact original downloads, page reload.');
  }
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  const originalUrl = page.url();
  const native = async <T = NativeDescriptor,>(operation: string, fields: Record<string,string> = {}): Promise<NativeReply<T>> => {
    const raw = await page.evaluate(async ([operation, fields]) => {
    const frame = { profile: 'morphir/workbench/native', contractVersion: '0.1.0-draft.1', operation: `session.${operation}`, ...fields };
    const source = await window.__MoonBit__!.core!.invokeOp!('app:workbench_native', JSON.stringify(frame));
    const admitted = JSON.parse(globalThis.morphirWorkbenchJobs(JSON.stringify({ op: 'native-response', source,
      operation: operation === 'unknown' ? 'session.open' : `session.${operation}`,
      sessionId: operation === 'open' || operation === 'unknown' ? null : fields.sessionId })));
    if (!admitted.ok) throw new Error(`Native smoke reply admission failed: ${admitted.code}`);
    return JSON.stringify(admitted.value);
  }, [operation, fields] as const);
    return JSON.parse(raw);
  };
  const value = <T,>(reply: NativeReply<T>): T => { assert.ok(reply.ok); return reply.value; };
  const denied = (reply: NativeReply<unknown>, code: string) => {
    assert.ok(!reply.ok); assert.equal(reply.error.code, code); assert.equal(reply.error.effect, 'none');
  };
  const opened = await native('open');
  assert.ok(opened.ok);
  const firstSession = opened.value;
  assert.deepEqual(firstSession.operations, ['jobs', 'workspace'], 'The packaged host offers owned native evaluation jobs and read-only workspace grants');
  assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.runtimeLabel), 'Desktop local');
  assert.deepEqual(value(await native('check', { sessionId: firstSession.sessionId })), firstSession);
  denied(await native('open', { contractVersion: '0.1.0-draft.2' }), 'invalid_request');
  denied(await native('close', { sessionId: 'not-this-session' }), 'unauthorized');
  denied(await native('unknown'), 'invalid_request');
  await assert.rejects(page.evaluate(() => window.__MoonBit__!.core!.invokeOp!('app:workbench_native', { operation: 'session.open' } as unknown as string)));
  const hostile = createServer((_, response) => { response.writeHead(200, { 'Content-Type': 'text/html' }); response.end('<!doctype html><title>Untrusted frame</title>'); });
  try {
    hostile.listen(0, '127.0.0.1'); await once(hostile, 'listening');
    const url = `http://127.0.0.1:${(hostile.address() as AddressInfo).port}`;
    await page.goto(url);
    const access = await page.evaluate(async () => {
      if (typeof window.__MoonBit__?.core?.invokeOp !== 'function') return 'absent';
      return await Promise.race([
        Promise.resolve(window.__MoonBit__.core.invokeOp('app:workbench_native', JSON.stringify({ profile: 'morphir/workbench/native', contractVersion: '0.1.0-draft.1', operation: 'session.open' }))).then(() => 'allowed', () => 'rejected'),
        new Promise<string>(resolve => setTimeout(() => resolve('timeout'), 5000)),
      ]);
    });
    assert.ok(['absent', 'rejected'].includes(access), 'An unrelated origin cannot negotiate a native session: ' + access);
    await page.goto(originalUrl);
    await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  } finally {
    hostile.closeAllConnections();
    await new Promise(resolve => hostile.close(resolve));
  }
  await page.reload();
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  const freshSession = value(await native('open'));
  assert.notEqual(freshSession.sessionId, firstSession.sessionId);
  denied(await native('check', { sessionId: firstSession.sessionId }), 'unauthorized');
  assert.deepEqual(value(await native<Record<string,never>>('close', { sessionId: freshSession.sessionId })), {});
  const revoked = await page.evaluate(() => new Promise<WorkResult>(resolve => globalThis.morphirWorkbench.request(
    { operation: 'compile', source: '(+ 1 2)', languageId: 'scheme', target: 'scheme' }, text => resolve(JSON.parse(text)))));
  assert.equal(revoked.success, false); assert.match(revoked.message!, /session|authorized/);
  await page.goto(originalUrl + '?mode=standalone');
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.runtimeLabel), 'Browser local');
  await page.goto(originalUrl);
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  await page.evaluate(() => {
    const invoke = window.__MoonBit__!.core!.invokeOp!.bind(window.__MoonBit__!.core);
    globalThis.nativeJobCalls = [];
    window.__MoonBit__!.core!.invokeOp = (name, payload) => {
      if (name === 'app:workbench_native') {
        const operation = JSON.parse(payload).operation;
        if (operation.startsWith('job.')) globalThis.nativeJobCalls.push(operation.slice(4));
      }
      return invoke!(name, payload);
    };
  });
  const back = page.getByRole('button', {name:'Back',exact:true});
  assert.equal(await back.isEnabled(), false);
  assert.equal(await page.locator('#tool-panel-body').isVisible(), false, 'The packaged tool panel starts collapsed');
  await page.locator('#source .cm-editor').waitFor();
  assert.ok(await page.locator('#source .cm-line span').count() > 0, 'Packaged source has syntax highlighting');
  await page.getByRole('textbox', { name: 'Source editor' }).fill('(+ 20 22)');
  await page.getByRole('button', { name: 'Compile & run', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<HTMLElement>('.run-value strong')?.textContent === '42');
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.locator('.tree-item').filter({ hasText: 'main' }).click();
  await page.getByRole('heading', { name: 'Returns', exact: true }).waitFor();
  assert.match((await page.locator('.type-signature').textContent()!)!, /main/);
  await page.getByRole('button', { name: 'Local Scheme', exact: true }).click();
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '42');
  const chooserPromise = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await (await chooserPromise).setFiles(fileURLToPath(new URL('../../../pkgs/morphir-ir/conformance/fixtures/v3-greeting.json', import.meta.url)));
  await page.getByRole('button', { name: 'T Product', exact: true }).click();
  await page.getByRole('heading', { name: 'Product', exact: true }).waitFor();
  assert.match((await page.locator('.type-signature').textContent()!)!, /Main.ProductId/);
  await page.locator('.reference-link').filter({ hasText: 'Main.ProductId' }).click();
  await page.getByRole('heading', { name: 'ProductId', exact: true }).waitFor();
  await back.click();
  await page.getByRole('heading', { name: 'Product', exact: true }).waitFor();
  if (process.env.MORPHIR_WORKBENCH_DESKTOP_SCREENSHOT) await page.screenshot({path:process.env.MORPHIR_WORKBENCH_DESKTOP_SCREENSHOT,fullPage:false});
  await page.getByRole('button', {name:'Try Morphir',exact:true}).click();
  await back.click();
  await page.getByRole('heading', { name: 'Product', exact: true }).waitFor();
  await page.locator('.reference-link').filter({hasText:'Main.ProductId'}).click();
  await page.getByRole('heading', { name: 'ProductId', exact: true }).waitFor();
  await page.getByRole('button', { name: 'IR JSON', exact: true }).click();
  await page.waitForFunction(() => (document.querySelector<HTMLElement>('#model-detail') as CodeEditor)?.value.includes('TypeAliasDefinition'));
  await page.getByRole('button', { name: 'Details', exact: true }).click();
  await page.locator('.tree-item[title="elm-compat:main#apply-discount"]').click();
  await page.getByRole('heading', { name: 'applyDiscount', exact: true }).waitFor();
  await page.getByRole('textbox', { name: 'discountPercent', exact: true }).fill('20');
  await page.getByRole('textbox', { name: 'originalPrice', exact: true }).fill('100');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '80.0');
  await page.locator('.tree-item[title="elm-compat:api#create-order"]').click();
  await page.getByRole('textbox', { name: 'orderId', exact: true }).fill('desktop-order');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.locator('.result-view > .result-branch').waitFor();
  await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  const projected = JSON.parse(await page.locator('#evaluation-output').evaluate(editor => (editor as CodeEditor).value));
  assert.equal(projected.kind, 'record');
  assert.equal(projected.fields.find((field: { name: string; value: unknown }) => field.name === 'order-id').value.text, '"desktop-order"');
  assert.equal(projected.fields.find((field: { name: string; value: unknown }) => field.name === 'status').value.tag, 'elm-compat:main#pending');
  await page.getByRole('button', { name: 'Printed', exact: true }).click();
  await page.getByRole('textbox', { name: 'Printed result', exact: true }).waitFor();
  assert.match(await page.locator('#evaluation-output').evaluate(editor => (editor as CodeEditor).value), /desktop-order/);
  await page.getByRole('button', { name: 'Value', exact: true }).click();
  const typedChooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await (await typedChooser).setFiles(fileURLToPath(new URL('../fixtures/typed-pricing.json', import.meta.url)));
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.locator('.tree-item[title="pricing:quotes#total"]').click();
  await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
  await page.getByRole('textbox', { name: 'quote.price.coefficient', exact: true }).fill('125');
  await page.getByRole('textbox', { name: 'quote.price.exponent', exact: true }).fill('-1');
  await page.getByRole('textbox', { name: 'quote.quantity', exact: true }).fill('3');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByText('Result · scheme-portable-v1/shared-sdk/bounded', { exact: true }).waitFor();
  await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'decimal', coefficient: '375', exponent: -1 });
  await page.getByRole('button', { name: 'Ion inputs', exact: true }).click();
  const ionEditor = page.getByRole('textbox', { name: 'Function arguments', exact: true });
  await ionEditor.fill('[morphir_value::{type:"record",fields:[{name:"price",value:{type:"decimal",coefficient:"125",exponent:-1}},{name:"quantity",value:{type:"int",value:"3"}}]}]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'decimal',coefficient:'375',exponent:-1});
  assert.ok(await page.locator('#evaluation-input .cm-line span').count() > 0, 'Packaged Ion has syntax highlighting');
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  assert.equal(await page.getByRole('textbox', { name: 'quote.quantity', exact: true }).inputValue(), '3');
  await page.locator('.tree-item[title="pricing:scalars#huge"]').click();
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'int', value: '1234567890123456789012345678901234567890' });
  const nativeJobCalls = await page.evaluate(() => globalThis.nativeJobCalls);
  for (const operation of ['submit', 'query', 'release']) assert.ok(nativeJobCalls.includes(operation), `Native ${operation} was used by real typed evaluation`);
  // The shared project workflow deliberately reloads the document for storage
  // acceptance, so check this page's native-call recorder before those reloads.
  await elmWorkflow(page, { nativeDownloads: false, selectFolder: selectCefFolder });
  await moonbitWorkflow(page, { nativeDownloads: false });
  await libraryWorkflow(page, { nativeDownloads: false });
  await toolPanelWorkflow(page, { resize: false });
  // Native job availability must not apply host retention rules to Local Scheme.
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  const localModel = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await (await localModel).setFiles(fileURLToPath(new URL('../../../pkgs/morphir-ir/conformance/fixtures/v3-greeting.json', import.meta.url)));
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  const originalEntry = page.locator('.tree-item[title="elm-compat:main#apply-discount"]');
  const otherEntry = page.locator('.tree-item[title="elm-compat:main#order-status-to-string"]');
  await originalEntry.click();
  await page.getByRole('heading', { name: 'applyDiscount', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Local Scheme', exact: true }).click();
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  await page.getByRole('textbox', { name: 'Function arguments', exact: true }).fill('[20,100]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  await otherEntry.click();
  await page.getByRole('heading', { name: 'orderStatusToString', exact: true }).waitFor();
  assert.equal(await page.locator('.evaluation-result').count(), 0);
  await originalEntry.click();
  await page.getByRole('heading', { name: 'applyDiscount', exact: true }).waitFor();
  assert.equal(await page.locator('.evaluation-result').count(), 0, 'Local results do not reappear after navigation');
  await page.evaluate(() => {
    const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
    globalThis.restoreLocalScopeRequests = () => { globalThis.morphirWorkbench.request = request; };
    globalThis.morphirWorkbench.request = (data, receive) => request(data, reply => {
      if (data.operation === 'evaluate') globalThis.releaseLocalScopeReply = () => receive(reply);
      else receive(reply);
    });
  });
  try {
    await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
    await page.waitForFunction(() => typeof globalThis.releaseLocalScopeReply === 'function');
    await otherEntry.click();
    await page.getByRole('heading', { name: 'orderStatusToString', exact: true }).waitFor();
    await page.evaluate(() => globalThis.releaseLocalScopeReply!());
    await page.getByRole('status').filter({ hasText: 'Finished for another function' }).waitFor();
    assert.equal(await page.locator('.evaluation-result').count(), 0);
  } finally { await page.evaluate(() => globalThis.restoreLocalScopeRequests!()); }
  // Presentation fixtures model standalone callbacks without host receipts.
  await page.goto(originalUrl + '?mode=standalone');
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  await terminalOutcomeWorkflow(page, { resize: false, screenshot: process.env.MORPHIR_WORKBENCH_OUTCOME_SCREENSHOT });
  assert.deepEqual(errors, []);
  console.log('Packaged Proton smoke passed: page-bound native session, hostile-origin rejection, reload/revocation, explicit standalone, shared UI, worker compile/run, model import/reference/back navigation, typed fields/Ion evaluation and result views.');
} finally { await browser.close(); }
