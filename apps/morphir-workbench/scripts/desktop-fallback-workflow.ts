import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import type { Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import { build, createWorkspace, showCompile, showModel } from './workbench-steps.ts';

type ProbeWindow = Window & { platformProbe: { completed: Record<string, number>; native: string[] } };
const paint = (page: Page) => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
async function probe(page: Page) {
  await page.evaluate(() => {
    const state = { completed: {} as Record<string, number>, native: [] as string[] };
    (window as unknown as ProbeWindow).platformProbe = state;
    const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
    globalThis.morphirWorkbench.request = (data, receive) => request(data, source => {
      state.completed[data.operation] = (state.completed[data.operation] ?? 0) + 1; receive(source);
    });
    const bridge = window.__MoonBit__?.core;
    if (!bridge?.invokeOp) return;
    const invoke = bridge.invokeOp.bind(bridge);
    bridge.invokeOp = (operation, source) => {
      if (operation === 'app:workbench_native') state.native.push(source);
      return invoke(operation, source);
    };
  });
}
async function complete(page: Page, operation: string, action: () => Promise<unknown>) {
  const before = await page.evaluate(operation => (window as unknown as ProbeWindow).platformProbe.completed[operation] ?? 0, operation);
  await action();
  try {
    await page.waitForFunction(({ operation, before }) => ((window as unknown as ProbeWindow).platformProbe.completed[operation] ?? 0) > before, { operation, before });
  } catch (error) {
    const observed = await page.evaluate(() => ({ completed: (window as unknown as ProbeWindow).platformProbe.completed,
      status: document.querySelector('.statusbar')?.textContent }));
    throw new Error(`No ${operation} completion: ${JSON.stringify(observed)}`, { cause: error });
  }
  await paint(page);
}
export async function fallbackWorkerWorkflow(page: Page, mode: 'native-fallback' | 'standalone') {
  await probe(page);
  // A page that just loaded shows getting started; the workflow compiles in a source workspace of its own.
  if (await page.locator('.getting-started').count()) await createWorkspace(page);
  await showCompile(page); await paint(page);
  const source = page.getByRole('textbox', { name: 'Source editor', exact: true });
  await source.fill('(+ 20 22)'); await paint(page);
  assert.equal(await page.locator('#source').evaluate(e => (e as CodeEditor).value), '(+ 20 22)');
  await complete(page, 'run', () => build(page, 'Compile & run'));
  await page.waitForFunction(() => document.querySelector('.run-value strong')?.textContent === '42');
  await showModel(page); await paint(page);
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await complete(page, 'inspect', async () => (await chooser).setFiles(fileURLToPath(new URL('../fixtures/typed-pricing.json', import.meta.url))));
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.locator('.tree-item[title="pricing:quotes#total"]').click();
  await page.getByRole('button', { name: 'Typed invocation', exact: true }).click(); await paint(page);
  const policy = page.getByRole('combobox', { name: 'Capability checks', exact: true });
  if (mode === 'native-fallback' && await policy.count()) {
    assert.equal(await policy.inputValue(), 'strict');
    assert.equal(await policy.locator('option[value="permissive"]').evaluate(e => (e as HTMLOptionElement).disabled), true);
  }
  const workspace = page.getByRole('button', { name: 'Open workspace', exact: true });
  assert.ok(await workspace.count() === 0 || await workspace.isDisabled(), 'Fallback must not offer a workspace grant');
  const evaluate = async () => {
    await complete(page, 'evaluate', () => page.getByRole('button', { name: 'Evaluate', exact: true }).click());
    await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
    const json = page.getByRole('button', { name: 'Result JSON', exact: true });
    await json.click(); await paint(page);
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'decimal', coefficient: '375', exponent: -1 });
  };
  await page.getByRole('textbox', { name: 'quote.price.coefficient', exact: true }).fill('125');
  await page.getByRole('textbox', { name: 'quote.price.exponent', exact: true }).fill('-1');
  await page.getByRole('textbox', { name: 'quote.quantity', exact: true }).fill('3'); await paint(page);
  await evaluate();
  const argumentsText = '[{"type":"record","fields":[{"name":"price","value":{"type":"decimal","coefficient":"125","exponent":-1}},{"name":"quantity","value":{"type":"int","value":"3"}}]}]';
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click(); await paint(page);
  await page.getByRole('textbox', { name: 'Function arguments', exact: true }).fill(argumentsText); await paint(page); await evaluate();
  await page.getByRole('button', { name: 'Ion inputs', exact: true }).click(); await paint(page);
  await page.getByRole('textbox', { name: 'Function arguments', exact: true }).fill('[morphir_value::{type:"record",fields:[{name:"price",value:{type:"decimal",coefficient:"125",exponent:-1}},{name:"quantity",value:{type:"int",value:"3"}}]}]');
  await paint(page); await evaluate();
  assert.ok(await page.locator('#evaluation-input .cm-line span').count() > 0, 'Real packaged CodeMirror highlights Ion');
  await page.locator('.tree-item[title="pricing:quotes#captured"]').click();
  // The empty native host has no capability-description offer. It retains the
  // legacy strict manifest, whose missing entry has the public-entry reason.
  const reason = mode === 'native-fallback'
    ? 'Typed evaluation requires a public entry with supported input and output types.'
    : 'Unsupported input/output boundary: execution.boundary_function';
  await page.getByText(reason, { exact: true }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Evaluate', exact: true }).count(), 0);
  const nativeCalls = await page.evaluate(() => (window as unknown as ProbeWindow).platformProbe.native.map(raw => JSON.parse(raw).operation as string));
  assert.ok(nativeCalls.every(operation => operation === 'session.check'), `Worker workflows must not submit native execution or workspace operations: ${nativeCalls}`);
  if (mode === 'standalone') assert.deepEqual(nativeCalls, []);
  return `${mode}:compile-fields-json-ion-unsupported-boundary`;
}
