import type { Route } from 'playwright';
import type { Receipt } from './execution-contracts.ts';
import type { Page, Locator, Request, Response, WebSocket, Browser, BrowserContext } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const quote = [{ type: 'record', fields: [
  { name: 'price', value: { type: 'decimal', coefficient: '125', exponent: -1 } },
  { name: 'quantity', value: { type: 'int', value: '3' } },
] }];
const decimal = { type: 'decimal', coefficient: '375', exponent: -1 };
const quoteIon = '[morphir_value::{type:"record",fields:[{name:"price",value:{type:"decimal",coefficient:"125",exponent:-1}},{name:"quantity",value:{type:"int",value:"3"}}]}]';
const endpoint = (request: Request, name: string) => new URL(request.url()).pathname === `/api/workbench/${name}`;

// The caller owns real host startup/authentication and browser or Proton cleanup.
// This helper never replaces execution results or manufactures execution receipts.
export async function executionWorkflow(page: Page, { screenshot }: { screenshot?: string } = {}) {
  const errors: string[] = [], submissions: { contractVersion: string; model: string; inputs: {format: string;source: string} }[] = [], cancellations: unknown[] = [], responses: { path: string; status: number; value: Receipt }[] = [], methods: string[] = [];
  const responseReads: Promise<unknown>[] = [];
  const onError = (error: Error) => errors.push(error.message);
  const onRequest = (request: Request) => {
    if (endpoint(request, 'submit')) submissions.push(request.postDataJSON());
    if (endpoint(request, 'cancel')) cancellations.push(request.postDataJSON());
  };
  const onResponse = (response: Response) => {
    if (!/\/api\/workbench\/(submit|query|cancel|release)$/.test(new URL(response.url()).pathname)) return;
    responseReads.push(response.json().then(value => responses.push({ path: new URL(response.url()).pathname, status: response.status(), value })).catch(() => {}));
  };
  const onSocket = (socket: WebSocket) => socket.on('framesent', ({ payload }) => {
    try { const message = JSON.parse(String(payload)); if (message.method) methods.push(message.method); } catch { /* Non-RPC frames do not add methods. */ }
  });
  page.on('pageerror', onError);
  page.on('request', onRequest);
  page.on('response', onResponse);
  page.on('websocket', onSocket);
  const evaluate = page.getByRole('button', { name: 'Evaluate', exact: true });
  const input = page.getByRole('textbox', { name: 'Function arguments', exact: true });
  const view = () => page.evaluate(() => JSON.parse(globalThis.morphirWorkbenchExecutions(JSON.stringify({ op: 'view' }))));
  const ready = async () => {
    await page.waitForFunction(() => [...document.querySelectorAll<HTMLButtonElement>('button')].some(button => button.textContent.trim() === 'Evaluate' && !button.disabled));
  };
  const terminal = async (previous: string) => {
    await page.waitForFunction(previous => {
      const current = JSON.parse(globalThis.morphirWorkbenchExecutions(JSON.stringify({ op: 'view' })));
      return current.ok && current.execution.identity.executionId !== previous && current.execution.state === 'terminal' &&
        [...document.querySelectorAll<HTMLButtonElement>('button')].some(button => button.textContent.trim() === 'Evaluate' && !button.disabled);
    }, previous);
    const current = await view();
    assert.equal(current.execution.connected, true, 'Terminal evidence remains connected after release');
    assert.deepEqual(current.result.terminalOutcomes.calls.map((call: {id: string}) => call.id), ['workbench']);
    return current;
  };
  const begin = async () => {
    await ready();
    const previous = await view();
    return { id: previous.ok ? previous.execution.identity.executionId : null, count: submissions.length };
  };
  const run = async () => {
    const before = await begin();
    await evaluate.click();
    const current = await terminal(before.id);
    assert.equal(submissions.length, before.count + 1, 'Each Evaluate submits exactly one host execution');
    return current;
  };
  const resultJson = async (expected: unknown) => {
    await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
    await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(editor => (editor as CodeEditor).value)), expected);
  };
  const openPanel = async (name: string) => {
    const tab = page.getByRole('tab', { name: new RegExp(`^${name}`) });
    const body = page.locator('#tool-panel-body');
    if (!await body.isVisible() || await tab.getAttribute('aria-selected') !== 'true') await tab.click();
    await page.waitForFunction(name => [...document.querySelectorAll<HTMLElement>('[role=tab]')].some(tab =>
      tab.textContent.trim().startsWith(name) && tab.getAttribute('aria-selected') === 'true'), name);
    await body.waitFor();
    return body;
  };
  let queryRoute, releaseRoute;
  try {
    // Reinitialize through the existing authenticated cookie, capturing the real
    // v1 socket so evaluation/cancellation can be proved to use HTTP only.
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('status').filter({ hasText: 'Connected' }).waitFor();
    assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.connected), true);
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
    await (await chooser).setFiles(fileURLToPath(new URL('../fixtures/typed-pricing.json', import.meta.url)));
    await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
    await page.locator('.tree-item[title="pricing:quotes#total"]').click();
    await page.getByRole('textbox', { name: 'quote.price.coefficient', exact: true }).fill('125');
    await page.getByRole('textbox', { name: 'quote.price.exponent', exact: true }).fill('-1');
    await page.getByRole('textbox', { name: 'quote.quantity', exact: true }).fill('3');
    const fields = await run();
    assert.equal(fields.result.profile, 'scheme-portable-v1/shared-sdk/bounded');
    await resultJson(decimal);
    assert.equal(await page.locator('.evaluation-result.stale').count(), 0);
    assert.equal(await page.locator('.evaluation-result .terminal-kind').textContent(), 'Returned');

    await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-input').evaluate(editor => (editor as CodeEditor).value)), quote, 'Fields and JSON share the tagged document');
    await input.fill(JSON.stringify(quote));
    await run();
    await resultJson(decimal);
    assert.equal(submissions.at(-1)!.inputs.format, 'json');

    await page.getByRole('button', { name: 'Ion inputs', exact: true }).click();
    await input.fill(quoteIon);
    await run();
    await resultJson(decimal);
    assert.equal(submissions.at(-1)!.inputs.format, 'ion-text');
    assert.equal(submissions.at(-1)!.inputs.source, quoteIon);

    // A real result can arrive while another declaration is selected. Keep one
    // active host entry's exact draft and full result when navigating back.
    await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
    const retainedSource = JSON.stringify(quote);
    await input.fill(retainedSource);
    const beforeNavigation = await begin();
    let releaseQuery: () => void = () => {}, finishQuery: () => void = () => {};
    const queryGate = new Promise<void>(resolve => { releaseQuery = resolve; });
    const queryContinued = new Promise<void>(resolve => { finishQuery = resolve; });
    queryRoute = async (route: Route) => { await queryGate; try { await route.continue(); } finally { finishQuery(); } };
    await page.route('**/api/workbench/query', queryRoute);
    const observedQuery = page.waitForRequest(request => endpoint(request, 'query'));
    await evaluate.click();
    await observedQuery;
    const editedDraft = structuredClone(quote);
    editedDraft[0]!.fields[1]!.value.value = '4';
    const editedSource = JSON.stringify(editedDraft);
    await input.fill(editedSource);
    await page.locator('.tree-item[title="pricing:boundaries#decimal"]').click();
    await input.fill('[{"type":"decimal","coefficient":"999","exponent":0}]');
    releaseQuery!();
    await queryContinued;
    await page.unroute('**/api/workbench/query', queryRoute); queryRoute = null;
    const navigated = await terminal(beforeNavigation.id);
    assert.equal(submissions.length, beforeNavigation.count + 1);
    assert.equal(await page.locator('.evaluation-result').count(), 0, 'Another declaration never displays the retained host entry result');
    await page.locator('.tree-item[title="pricing:quotes#total"]').click();
    await page.getByRole('heading', { name: 'total', exact: true }).waitFor();
    assert.equal(await page.locator('.evaluation-result').count(), 1, 'Returning to the host entry restores its full result');
    assert.equal(await page.locator('#evaluation-input').evaluate(editor => (editor as CodeEditor).value), editedSource, 'Returning restores the exact host entry draft instead of another declaration defaults');
    await resultJson(decimal);
    assert.equal(await page.locator('.evaluation-result.stale').count(), 1, 'The edited host draft keeps the captured result stale after navigation');
    assert.deepEqual(navigated.result.typed, decimal);

    // A genuine release may succeed while its reply is lost. Until the exact
    // terminal identity is authenticated and reconciled, keep its model intact.
    await input.fill(retainedSource);
    const beforeRelease = await begin();
    let releaseAborted = false;
    releaseRoute = async (route: Route) => {
      if (releaseAborted) { await route.continue(); return; }
      releaseAborted = true;
      const released = await route.fetch();
      assert.equal(released.status(), 200, 'The real host released the terminal identity');
      assert.deepEqual(await released.json(), { released: true });
      await route.abort('failed');
    };
    await page.route('**/api/workbench/release', releaseRoute);
    await evaluate.click();
    await page.waitForFunction(previous => {
      const current = JSON.parse(globalThis.morphirWorkbenchExecutions(JSON.stringify({ op: 'view' })));
      return current.ok && current.execution.identity.executionId !== previous && current.execution.state === 'terminal' && !current.execution.connected &&
        [...document.querySelectorAll<HTMLButtonElement>('button')].some(button => button.textContent.trim() === 'Reconnect / resume' && !button.disabled);
    }, beforeRelease.id);
    const releaseDisconnected = await view();
    assert.equal(submissions.length, beforeRelease.count + 1);
    await resultJson(decimal);
    await page.unroute('**/api/workbench/release', releaseRoute); releaseRoute = null;
    const compileCalls = methods.filter(method => method === 'morphir.playground.compile').length;
    await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('pub fn replacement(value: Int) -> Int { value }');
    await page.getByRole('button', { name: 'Compile', exact: true }).click();
    await page.waitForFunction(() => /before replacing the model|Model ready/.test(document.querySelector<HTMLElement>('.statusbar')?.textContent ?? ''));
    assert.equal(methods.filter(method => method === 'morphir.playground.compile').length, compileCalls, 'A disconnected terminal execution blocks model replacement before reconnect');
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    await page.locator('.tree-item[title="pricing:quotes#total"]').waitFor();
    await resultJson(decimal);
    const releaseSubmissionCount = submissions.length;
    await page.getByRole('button', { name: 'Reconnect / resume', exact: true }).click();
    await ready();
    const releaseRecovered = await view();
    assert.deepEqual(releaseRecovered.execution.identity, releaseDisconnected.execution.identity);
    assert.equal(releaseRecovered.execution.connected, true);
    assert.equal(submissions.length, releaseSubmissionCount, 'Release reconciliation never resubmits or evaluates against a replacement model');
    await resultJson(decimal);

    // Result.Err is a returned model value, separate from the SDK failure below.
    await page.locator('.tree-item[title="pricing:boundaries#result"]').click();
    await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
    const errValue = { type: 'result', case: 'err', value: { type: 'text', units: [69, 114, 114, 111, 114] } };
    await input.fill(JSON.stringify([errValue]));
    const returnedErr = await run();
    assert.equal(returnedErr.result.terminalOutcomes.calls[0].outcome.status, 'returned');
    await resultJson(errValue);
    assert.equal(await page.locator('.evaluation-result .terminal-kind').textContent(), 'Returned');

    await page.locator('.tree-item[title="pricing:results#failure"]').click();
    const sdk = await run();
    assert.deepEqual(sdk.result.terminalOutcomes.calls[0].outcome, { status: 'model-error', code: 'sdk.division_by_zero' });
    await resultJson({ type: 'model-error', code: 'sdk.division_by_zero' });
    assert.equal(await page.locator('.evaluation-result .terminal-kind').textContent(), 'Model error');
    const diagnostics = await openPanel('Diagnostics');
    assert.ok((await diagnostics.locator('.tool-report.current .tool-code').allTextContents()).includes('sdk.division_by_zero'));
    const output = await openPanel('Output');
    assert.equal(await output.locator('.tool-outcome').first().locator('.terminal-kind').textContent(), 'Model error');
    await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();

    await page.locator('.tree-item[title="pricing:quotes#total"]').click();
    await input.fill(JSON.stringify(quote));
    const beforeCancel = await begin();
    const cancellationCount = cancellations.length;
    const submitted = page.waitForRequest(request => endpoint(request, 'submit'));
    await evaluate.click();
    await submitted;
    let clickedCancel = false;
    try {
      await page.getByRole('button', { name: 'Cancel', exact: true }).click({ timeout: 1000 });
      clickedCancel = true;
    } catch (error) {
      const current = await view();
      if (!current.ok || current.execution.state !== 'terminal') throw error;
    }
    const cancelled = await terminal(beforeCancel.id);
    assert.equal(submissions.length, beforeCancel.count + 1, 'Cancellation never resubmits an execution');
    const cancelOutcome = cancelled.result.terminalOutcomes.calls[0].outcome;
    assert.ok(['cancelled', 'returned'].includes(cancelOutcome.status), 'A terminal receipt decides whether cancellation or return won');
    await Promise.all(responseReads);
    const cancelReplies = responses.filter(reply => reply.path.endsWith('/cancel') && reply.status === 200 && reply.value.identity.executionId === cancelled.execution.identity.executionId);
    const acknowledgements = cancelReplies.filter(reply => reply.value.cancelRequested);
    for (const reply of cancelReplies) {
      if (reply.value.state !== 'terminal') assert.equal(reply.value.cancelRequested, true, 'A pending cancellation reply acknowledges the request');
    }
    if (acknowledgements.length) assert.equal(cancelled.execution.cancelRequested, true, 'Cancellation acknowledgement is retained through actual terminal evidence');
    assert.ok(cancellations.length <= cancellationCount + 1, 'Repeated UI updates do not send duplicate cancellation requests');
    assert.equal(await page.locator('.evaluation-result .terminal-kind').textContent(), cancelOutcome.status === 'cancelled' ? 'Cancelled' : 'Returned');

    // Abort a genuine query once. The host still owns the real evaluation; the
    // client must reconnect and query the same identity without another submit.
    await input.fill(JSON.stringify(quote));
    const beforeResume = await begin();
    let aborted = false;
    queryRoute = async (route: Route) => {
      if (!aborted) { aborted = true; await route.abort('failed'); }
      else await route.continue();
    };
    await page.route('**/api/workbench/query', queryRoute);
    await evaluate.click();
    const reconnect = page.getByRole('button', { name: 'Reconnect / resume', exact: true });
    await reconnect.waitFor();
    await page.waitForFunction(() => [...document.querySelectorAll<HTMLButtonElement>('button')].some(button => button.textContent.trim() === 'Reconnect / resume' && !button.disabled));
    const disconnected = await view();
    assert.equal(disconnected.execution.connected, false);
    assert.notEqual(disconnected.execution.state, 'terminal', 'Transport failure does not invent a terminal receipt');
    assert.equal(disconnected.result, null);
    assert.equal(await evaluate.isEnabled(), false, 'A disconnected pending execution cannot be resubmitted');
    assert.equal(submissions.length, beforeResume.count + 1);
    const changed = structuredClone(quote);
    changed[0]!.fields[1]!.value.value = '4';
    await input.fill(JSON.stringify(changed));
    await page.unroute('**/api/workbench/query', queryRoute); queryRoute = null;
    await reconnect.click();
    const resumed = await terminal(beforeResume.id);
    assert.deepEqual(resumed.execution.identity, disconnected.execution.identity, 'Resume keeps the retained snapshot identity');
    assert.equal(submissions.length, beforeResume.count + 1, 'Reconnect only observes; it never resubmits');
    await page.getByRole('status').filter({ hasText: 'Finished for earlier inputs' }).waitFor();
    await page.locator('.evaluation-result.stale').waitFor();
    await resultJson(decimal);
    await input.fill(JSON.stringify(quote));
    await run();
    await resultJson(decimal);
    assert.equal(await page.locator('.evaluation-result.stale').count(), 0, 'A fresh run clears stale input presentation');
    const finalOutput = await openPanel('Output');
    assert.deepEqual(JSON.parse((await finalOutput.locator('.tool-outcome').first().locator('.terminal-preview').textContent()!)!), decimal);
    await openPanel('Diagnostics');
    assert.ok(await page.locator('#tool-panel-body .tool-report.current .tool-clean').count() > 0, 'Current successful evaluation has no invented diagnostics');
    await openPanel('Output');
    await Promise.all(responseReads);
    assert.ok(submissions.every(body => body.contractVersion === '0.2.0-draft.1' && typeof body.model === 'string' && typeof body.inputs.source === 'string'));
    assert.ok(methods.length > 0 && methods.every(method => !/evaluate|cancel/.test(method)), 'Evaluation and cancellation add no v1 RPC operation');
    assert.deepEqual(errors, []);
    if (screenshot) await page.screenshot({ path: screenshot, fullPage: false });
    const report = { realConnectedExecutions: true, fields: true, json: true, ion: true, exactDecimal: true,
      returnedResultErr: true, sdkModelError: true, terminalOutputAndDiagnostics: true, retainedEntryNavigation: true, terminalReleaseBlocksReplacement: true,
      cancellation: { clicked: clickedCancel, requests: cancellations.length - cancellationCount, terminal: cancelOutcome.status, acknowledged: acknowledgements.length > 0 },
      disconnectAndResume: true, capturedInputsStayStale: true, submissions: submissions.length,
      v1Methods: [...new Set(methods)] };
    console.log(JSON.stringify(report));
    return report;
  } finally {
    if (queryRoute) await page.unroute('**/api/workbench/query', queryRoute);
    if (releaseRoute) await page.unroute('**/api/workbench/release', releaseRoute);
    page.off('pageerror', onError);
    page.off('request', onRequest);
    page.off('response', onResponse);
    page.off('websocket', onSocket);
  }
}
