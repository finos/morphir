import type { Page, Request, Route } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import type { WorkResult } from '../browser/contracts.ts';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { isRecord } from '../../../types/data.ts';
import { executionWorkflow } from './execution-workflow.ts';

type Selection = { profile: string; contractVersion: string; policy: string };
interface PolicySubmission { contractVersion: string; model: string; entry: string; runtime: string; providerId: string; inputs: { format: string; source: string }; admission?: Selection }
interface ConnectedControls { completed: Record<string, number>; results: WorkResult[]; restore(): void }
type ConnectedWindow = Window & { connectedPolicyTest: ConnectedControls };
const endpoint = (request: Request, operation: string) => new URL(request.url()).pathname === `/api/workbench/${operation}`;
const evaluator = 'scheme-portable-v1/shared-sdk/bounded';
const selection = (policy: string) => ({ profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy });

/** Actual authenticated HTTP gateway, owner and workers, shared by Chromium and packaged Proton. */
export async function connectedCapabilityWorkflow(page: Page, { screenshot }: { screenshot?: string } = {}) {
  // Retain the existing real HTTP fields/JSON/Ion, cancellation, release-loss and
  // reconnect regression against this exact policy mapping too.
  await executionWorkflow(page, { submitVersion: '0.2.0-draft.2' });
  const errors: string[] = [], submissions: PolicySubmission[] = [], operations: string[] = [];
  const onError = (error: Error) => errors.push(error.message);
  const onRequest = (request: Request) => {
    const match = new URL(request.url()).pathname.match(/^\/api\/workbench\/(session|submit|query|cancel|release)$/);
    if (match) operations.push(match[1]!);
    if (endpoint(request, 'submit')) submissions.push(request.postDataJSON());
  };
  page.on('pageerror', onError); page.on('request', onRequest);
  const install = () => page.evaluate(() => {
    const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
    const controls: ConnectedControls = { completed: {}, results: [], restore() {} };
    Object.assign(window, { connectedPolicyTest: controls });
    globalThis.morphirWorkbench.request = (data, receive) => request(data, source => {
      const result = JSON.parse(source);
      if (result.operation !== 'execution-progress') {
        controls.completed[data.operation] = (controls.completed[data.operation] ?? 0) + 1;
        if (data.operation === 'evaluate') controls.results.push(result);
      }
      receive(source);
    });
    controls.restore = () => { globalThis.morphirWorkbench.request = request; };
  });
  const state = () => page.evaluate(() => {
    const { completed, results } = (window as unknown as ConnectedWindow).connectedPolicyTest;
    return { completed, results };
  });
  const paint = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const policy = page.getByRole('combobox', { name: 'Capability checks', exact: true });
  const evaluate = page.getByRole('button', { name: 'Evaluate', exact: true });
  const inputs = page.getByRole('textbox', { name: 'Function arguments', exact: true });
  const fixture = (await readFile(fileURLToPath(new URL('../fixtures/capability-execution.json', import.meta.url)), 'utf8'))
    .replace('"inputTypes": {}', '"inputTypes": {"unused": "morphir/SDK:basics#int"}');
  const importModel = async (model = fixture) => {
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    const before = (await state()).completed.inspect ?? 0;
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
    await (await chooser).setFiles({ name: 'connected-policy.json', mimeType: 'application/json', buffer: Buffer.from(model) });
    await page.waitForFunction(before => ((window as unknown as ConnectedWindow).connectedPolicyTest.completed.inspect ?? 0) > before, before);
    await paint();
    await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
    await page.locator('.tree-item[title="selected:main#answer"]').click();
    await paint();
  };
  const finish = async (before: number) => {
    await page.waitForFunction(before => ((window as unknown as ConnectedWindow).connectedPolicyTest.completed.evaluate ?? 0) > before, before);
    await paint();
    return (await state()).results.at(-1)!;
  };
  const run = async () => {
    const before = (await state()).completed.evaluate ?? 0;
    await evaluate.click();
    return finish(before);
  };
  const retained = async (result: WorkResult, expectedPolicy: string) => {
    assert.deepEqual(result.admission, selection(expectedPolicy));
    const plan = result.executionPlan;
    assert.ok(isRecord(plan));
    assert.equal(plan.runtime, 'scheme'); assert.equal(plan.evaluator, evaluator);
    assert.deepEqual(plan.admission, selection(expectedPolicy));
    assert.deepEqual(plan.identity, result.execution!.identity);
    assert.deepEqual(plan.boundary, { entries: [{ name: 'selected:main#answer', inputs: [{ type: 'int' }], output: { type: 'int' } }], definitions: [] });
    await page.locator('.captured-policy').filter({ hasText: expectedPolicy === 'strict' ? 'Whole model before running' : 'As code executes' }).waitFor();
  };
  let queryRoute: ((route: Route) => Promise<void>) | undefined;
  let releaseQuery: (() => void) | undefined;
  let submitRoute: ((route: Route) => Promise<void>) | undefined;
  try {
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('status').filter({ hasText: 'Connected' }).waitFor();
    await install();
    const descriptorResponse = await page.request.get(new URL('/api/workbench/session', page.url()).href);
    assert.equal(descriptorResponse.status(), 200);
    const descriptor = await descriptorResponse.json();
    assert.equal(descriptor.profile, 'morphir/workbench/host');
    assert.equal(descriptor.contractVersion, '0.2.0-draft.2');
    assert.equal(descriptor.capabilityChecks.evaluator, evaluator);
    await importModel();
    assert.equal(await policy.inputValue(), 'strict');
    assert.equal(await policy.locator('option[value="permissive"]').evaluate(e => (e as HTMLOptionElement).disabled), false);
    const initial = submissions.length;
    const strict = await run();
    assert.equal(strict.success, false);
    assert.equal(submissions.length, initial, 'Whole-model preflight refuses before an HTTP submission');
    await policy.selectOption('permissive'); await paint();
    for (const mode of ['JSON', 'Ion'] as const) {
      await page.getByRole('button', { name: `${mode} inputs`, exact: true }).click();
      const source = mode === 'Ion' ? '[7]' : '[{"type":"int","value":"7"}]';
      await inputs.fill(source);
      const result = await run();
      assert.equal(result.success, true); assert.deepEqual(result.typed, { type: 'int', value: '42' });
      await retained(result, 'permissive');
      const submitted = submissions.at(-1)!;
      assert.equal(submitted.runtime, 'scheme'); assert.equal(submitted.providerId, descriptor.offer.providerId);
      assert.equal(submitted.contractVersion, '0.2.0-draft.2');
      assert.deepEqual(submitted.admission, selection('permissive'));
      assert.deepEqual(submitted.inputs, { format: mode === 'Ion' ? 'ion-text' : 'json', source });
      await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
      assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'int', value: '42' });
    }
    // Delay only delivery of a real query. The policy control stays locked
    // while this accepted execution is pending. Edits affect the next draft.
    const gate = new Promise<void>(resolve => { releaseQuery = resolve; });
    queryRoute = async route => { await gate; await route.continue(); };
    await page.route('**/api/workbench/query', queryRoute);
    const observedQuery = page.waitForRequest(request => endpoint(request, 'query'));
    const before = (await state()).completed.evaluate ?? 0;
    const submissionCount = submissions.length;
    await evaluate.click(); await observedQuery;
    assert.equal(await policy.isDisabled(), true, 'A pending accepted checking policy cannot be edited');
    await inputs.fill('[99]'); await paint();
    releaseQuery!();
    const captured = await finish(before);
    await page.unroute('**/api/workbench/query', queryRoute); queryRoute = undefined;
    assert.equal(submissions.length, submissionCount + 1);
    await retained(captured, 'permissive');
    await page.locator('.evaluation-result.stale').waitFor();
    await policy.selectOption('strict'); await paint();
    await retained(captured, 'permissive');
    assert.equal(await policy.inputValue(), 'strict');
    assert.equal(await page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value), '[99]');
    await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    await retained(captured, 'permissive');
    assert.equal(await policy.inputValue(), 'strict');
    if (screenshot) {
      await page.locator('.captured-policy').scrollIntoViewIfNeeded();
      await page.screenshot({ path: screenshot, fullPage: false });
    }
    await importModel(fixture.replace('"condition": false', '"condition": true'));
    await policy.selectOption('permissive'); await paint();
    const failed = await run();
    assert.equal(failed.success, false); await retained(failed, 'permissive');
    await page.locator('.evaluation-result').filter({ hasText: 'execution.unsupported_reached' }).waitFor();
    // Lose delivery of a genuinely accepted submit. The owner still executes,
    // but the UI has no authority to invent its identity or retry the effect.
    await importModel();
    await policy.selectOption('permissive'); await paint();
    let uncertainIdentity: Record<string, string> | undefined;
    submitRoute = async route => {
      const accepted = await route.fetch();
      assert.equal(accepted.status(), 200);
      const value = await accepted.json();
      uncertainIdentity = value.identity;
      assert.deepEqual(value.plan.admission, selection('permissive'));
      await route.abort('failed');
    };
    await page.route('**/api/workbench/submit', submitRoute);
    const beforeUnknown = submissions.length;
    await evaluate.click();
    await page.getByRole('status').filter({ hasText: 'Submission status unknown' }).waitFor();
    assert.equal(await evaluate.isEnabled(), false);
    assert.equal(submissions.length, beforeUnknown + 1, 'An unknown accepted submission is never automatically retried');
    await page.unroute('**/api/workbench/submit', submitRoute); submitRoute = undefined;
    assert.ok(uncertainIdentity);
    // Clean up the known test-owned identity via the real authenticated API.
    // This evidence is deliberately never supplied to the uncertain UI client.
    const body = { contractVersion: '0.2.0-draft.1', identity: uncertainIdentity };
    const headers = { Origin: new URL(page.url()).origin };
    let terminal = false;
    for (let attempt = 0; attempt < 300; attempt++) {
      const response = await page.request.post(new URL('/api/workbench/query', page.url()).href, { data: body, headers });
      assert.equal(response.status(), 200);
      if ((await response.json()).state === 'terminal') { terminal = true; break; }
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert.equal(terminal, true);
    const released = await page.request.post(new URL('/api/workbench/release', page.url()).href, { data: body, headers });
    assert.equal(released.status(), 200);
    assert.deepEqual(await released.json(), { released: true });
    assert.equal(await evaluate.isEnabled(), false, 'External cleanup never silently renews an uncertain UI authority');
    assert.ok(operations.includes('submit') && operations.includes('query') && operations.includes('release'));
    assert.deepEqual(errors, []);
    await page.evaluate(() => (window as unknown as ConnectedWindow).connectedPolicyTest.restore());
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('status').filter({ hasText: 'Connected' }).waitFor();
    await install(); await importModel();
    assert.equal(await policy.inputValue(), 'strict', 'A fresh connected page defaults to whole-model checking');
    assert.equal(await page.locator('.captured-policy').count(), 0);
    console.log(JSON.stringify({ connectedCapabilityChecks: true, authenticatedHttp: true, contractVersion: descriptor.contractVersion,
      wholeModelPreflight: true, permissiveJsonIon: true, exactRetainedPlan: true, capturedPolicyAndInputs: true, reachedFailure: true,
      freshPageStrict: true, unknownAcceptedSubmitNoRetry: true, submissions: submissions.length, legacyLifecycleRegression: true }));
  } finally {
    releaseQuery?.();
    if (queryRoute) await page.unroute('**/api/workbench/query', queryRoute);
    if (submitRoute) await page.unroute('**/api/workbench/submit', submitRoute);
    await page.evaluate(() => (window as unknown as ConnectedWindow).connectedPolicyTest?.restore()).catch(() => {});
    page.off('pageerror', onError); page.off('request', onRequest);
  }
}
