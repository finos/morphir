import type { Browser } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { openSample } from './workbench-steps.ts';

type ControlledWindow = Window & { capabilityTest: { hold: boolean; release: (() => void) | null; completed: Record<string, number> } };

/** Real standalone execution; native/HTTP policy mappings have separate qualification. */
export async function capabilityWorkflow(browser: Browser, url: string) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  const policy = page.getByRole('combobox', { name: 'Capability checks', exact: true });
  const run = page.getByRole('button', { name: 'Evaluate', exact: true });
  const inputs = page.getByRole('textbox', { name: 'Function arguments', exact: true });
  const paint = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const choosePolicy = async (value: string) => { await policy.selectOption(value); await paint(); };
  const inputMode = async (mode: 'JSON' | 'Ion') => {
    await page.getByRole('button', { name: `${mode} inputs`, exact: true }).click();
    await page.waitForFunction(language => document.querySelector<CodeEditor>('#evaluation-input')?.dataset.language === language, mode.toLowerCase());
  };
  const completed = (operation: string) => page.evaluate(operation => (window as unknown as ControlledWindow).capabilityTest.completed[operation] ?? 0, operation);
  const finish = async (operation: string, before: number) => {
    await page.waitForFunction(({ operation, before }) => ((window as unknown as ControlledWindow).capabilityTest.completed[operation] ?? 0) > before, { operation, before });
    await paint();
  };
  const compile = async (status = 'Model ready') => {
    const before = await completed('compile');
    await page.getByRole('button', { name: 'Compile', exact: true }).click();
    await finish('compile', before);
    await page.getByRole('status').filter({ hasText: status }).waitFor();
  };
  const evaluate = async (status = 'Function evaluated') => {
    const before = await completed('evaluate');
    await run.click();
    await finish('evaluate', before);
    // The UI commits on animation frames. An old status with the same wording
    // must not satisfy this run's completion check before its busy state paints.
    await paint();
    await page.getByRole('status').filter({ hasText: status }).waitFor();
    await page.waitForFunction(() => ![...document.querySelectorAll<HTMLButtonElement>('button')].find(e => e.textContent === 'Evaluate')?.disabled);
  };
  const readInputs = () => page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value);
  const ready = () => page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  const importModel = async (path: string, content?: string) => {
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    const before = await completed('inspect');
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
    await (await chooser).setFiles(content === undefined ? path : { name: 'model.json', mimeType: 'application/json', buffer: Buffer.from(content) });
    await finish('inspect', before);
    await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  };
  try {
    // Hold delivery of a real worker reply, so edits/cancellation can race a
    // deterministic captured run without replacing execution with a fake value.
    await page.addInitScript(() => {
      const controls = { hold: false, release: null as (() => void) | null, completed: {} as Record<string, number> };
      Object.assign(window, { capabilityTest: controls });
      const NativeWorker = Worker;
      globalThis.Worker = class extends NativeWorker {
        constructor(source: string | URL, options?: WorkerOptions) {
          super(source, options);
          this.addEventListener('message', event => {
            if (!controls.hold) return;
            event.stopImmediatePropagation();
            controls.release = () => { controls.hold = false; controls.release = null; this.onmessage?.call(this, event); };
          });
        }
      };
    });
    await page.goto(url); await ready();
    await page.evaluate(() => {
      const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
      globalThis.morphirWorkbench.request = (data, receive) => request(data, reply => {
        const completed = (window as unknown as ControlledWindow).capabilityTest.completed;
        completed[data.operation] = (completed[data.operation] ?? 0) + 1;
        receive(reply);
      });
    });
    const fixture = fileURLToPath(new URL('../fixtures/capability-job.json', import.meta.url));
    await importModel(fixture);
    await page.locator('.tree-item[title="selected:main#answer"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    assert.equal(await policy.inputValue(), 'strict');
    assert.equal(await policy.locator('option[value="permissive"]').evaluate(e => (e as HTMLOptionElement).disabled), false);
    await evaluate('Evaluation failed');
    await page.locator('.captured-policy').filter({ hasText: 'Whole model before running' }).waitFor();
    await choosePolicy('permissive');
    await evaluate();
    await page.locator('.captured-policy').filter({ hasText: 'As code executes' }).waitFor();
    await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'int', value: '42' });
    await choosePolicy('strict');
    await page.locator('.evaluation-result.stale').waitFor();
    await page.locator('.captured-policy').filter({ hasText: 'As code executes' }).waitFor();

    // Same preserved policy, with the formerly dormant operation actually reached.
    const reached = (await readFile(fixture, 'utf8')).replace('"condition": false', '"condition": true');
    await importModel(fixture, reached);
    await page.locator('.tree-item[title="selected:main#answer"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    assert.equal(await policy.inputValue(), 'strict');
    await choosePolicy('permissive'); await run.click();
    await page.locator('.evaluation-result').filter({ hasText: 'execution.unsupported_reached' }).waitFor();

    await importModel(fileURLToPath(new URL('../fixtures/typed-pricing.json', import.meta.url)));
    await page.locator('.tree-item[title="pricing:boundaries#text"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    assert.equal(await policy.inputValue(), 'permissive', 'Model replacement does not silently reset policy');
    await inputMode('JSON');
    await inputs.fill('[unfinished draft');
    await choosePolicy('strict');
    assert.equal(await readInputs(), '[unfinished draft');
    await choosePolicy('permissive');
    assert.equal(await readInputs(), '[unfinished draft');
    await inputs.fill('[{"type":"text","units":[55296,0,55357,56832]}]');
    await inputMode('Ion');
    const ion = await readInputs();
    await choosePolicy('strict'); assert.equal(await readInputs(), ion);
    await choosePolicy('permissive'); assert.equal(await readInputs(), ion);
    await evaluate();
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'text', units: [55296,0,55357,56832] });
    await page.evaluate(() => { (window as unknown as ControlledWindow).capabilityTest.hold = true; });
    await run.click();
    await page.waitForFunction(() => !!(window as unknown as ControlledWindow).capabilityTest.release);
    await choosePolicy('strict');
    await inputs.fill('[morphir_value::{type:"text",units:[65]}]');
    await page.evaluate(() => { (window as unknown as ControlledWindow).capabilityTest.release!(); });
    await page.getByRole('status').filter({ hasText: 'Finished for earlier inputs' }).waitFor();
    await page.locator('.evaluation-result.stale .captured-policy').filter({ hasText: 'As code executes' }).waitFor();
    assert.equal(await policy.inputValue(), 'strict');
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'text', units: [55296,0,55357,56832] });
    assert.equal(await readInputs(), '[morphir_value::{type:"text",units:[65]}]');
    await choosePolicy('permissive');
    await page.evaluate(() => { (window as unknown as ControlledWindow).capabilityTest.hold = true; });
    await run.click();
    await page.waitForFunction(() => !!(window as unknown as ControlledWindow).capabilityTest.release);
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Cancelled' }).waitFor();
    await page.evaluate(() => { (window as unknown as ControlledWindow).capabilityTest.release!(); });
    await paint();
    await page.getByRole('status').filter({ hasText: 'Cancelled' }).waitFor();
    assert.equal(await readInputs(), '[morphir_value::{type:"text",units:[65]}]');
    await page.locator('.tree-item[title="pricing:quotes#captured"]').click();
    await page.getByText('The selected checking policy is unavailable', { exact: false }).waitFor();
    assert.equal(await policy.inputValue(), 'permissive');
    assert.equal(await policy.locator('option[value="permissive"]').evaluate(e => (e as HTMLOptionElement).disabled), true);
    await choosePolicy('strict');

    // Current dated source profile stays separate from checking policy in Try Morphir.
    await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
    await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('elm');
    await paint();
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.dataset.language === 'elm');
    await page.getByRole('combobox', { name: 'Target', exact: true }).selectOption('moonbit');
    await paint();
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill(
      'module Workbench.Main exposing (answer, readX)\n\nanswer : Int\nanswer = 42\n\nreadX : { a | x : Int } -> Int\nreadX r = r.x\n');
    await paint();
    await compile('MoonBit generation failed');
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    await page.locator('.tree-item[title="workbench:main#answer"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    await choosePolicy('permissive'); await evaluate();
    await page.getByRole('tab', { name: /^Diagnostics/ }).click();
    await page.locator('#tool-panel-body').getByText('Open records require specialization', { exact: false }).first().waitFor();
    await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();
    await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
    await openSample(page, 'MoonBit library');
    await compile();
    const sourceProfile = page.getByRole('combobox', { name: 'Source profile', exact: true });
    assert.equal(await sourceProfile.inputValue(), 'moonbit-model-library-2026-10-17');
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    await page.locator('.tree-item[title="user:main#welcome"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    await inputMode('JSON');
    const args = '[{"type":"text","units":[55357,56832]},{"type":"bool","value":true}]';
    await inputs.fill(args); await choosePolicy('permissive');
    await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
    assert.equal(await sourceProfile.inputValue(), 'moonbit-model-library-2026-10-17');
    await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    assert.equal(await readInputs(), args);
    await evaluate();
    await page.locator('.captured-policy').filter({ hasText: 'As code executes' }).waitFor();
    await page.locator('.tree-item[title="user:main#choose-earlier"]').click();
    await inputMode('JSON');
    const first = { type: 'custom', owner: 'morphir/SDK:int#int-32', tag: 'morphir/SDK:int#int32', items: [{ type: 'int', value: '-2147483648' }] };
    const second = { ...first, items: [{ type: 'int', value: '2147483647' }] };
    await inputs.fill(JSON.stringify([{ type: 'text', units: [98] }, { type: 'text', units: [97,97] }, first, second]));
    for (const checking of ['strict', 'permissive']) {
      await choosePolicy(checking);
      await evaluate();
      await page.locator('.captured-policy').filter({ hasText: checking === 'strict' ? 'Whole model before running' : 'As code executes' }).waitFor();
      assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), first, 'Shortlex String selection preserves canonical Int32 minimum');
    }
    await inputMode('Ion');
    await evaluate();
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), first);
    await inputMode('JSON');
    await inputs.fill(JSON.stringify([{ type: 'text', units: [97,97] }, { type: 'text', units: [98] }, first, second]));
    await evaluate();
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), second, 'Shortlex selection preserves canonical Int32 maximum');
    const outside = { ...first, items: [{ type: 'int', value: '2147483648' }] };
    await inputs.fill(JSON.stringify([{ type: 'text', units: [97,97] }, { type: 'text', units: [98] }, outside, second]));
    await evaluate('Evaluation failed');
    await page.locator('.evaluation-result').filter({ hasText: 'execution.int32_range' }).waitFor();
    for (const [sample, profile] of [
      ['MoonBit Boolean library', 'moonbit-model-bool-library-v1'],
      ['MoonBit Boolean', 'moonbit-model-bool-v1'],
    ]) {
      await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
      await openSample(page, sample!);
      assert.equal(await sourceProfile.inputValue(), profile);
      await compile();
      await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
      await page.locator('.tree-item[title="user:main#eligible"]').click();
      await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
      await inputMode('JSON');
      await inputs.fill('[{"type":"bool","value":true},{"type":"bool","value":false}]');
      for (const checking of ['strict', 'permissive']) {
        await choosePolicy(checking); await evaluate();
        assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'bool', value: true });
      }
      await inputMode('Ion'); await evaluate();
      assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'bool', value: true });
      await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
      assert.equal(await sourceProfile.inputValue(), profile, 'Checking policy never upgrades a pinned source profile');
      await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
    }
    await policy.focus(); assert.equal(await policy.evaluate(e => document.activeElement === e), true);
    for (const width of [390, 768, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      assert.equal(await policy.isVisible(), true);
    }
    if (process.env.MORPHIR_WORKBENCH_CAPABILITY_SCREENSHOT) await page.screenshot({ path: process.env.MORPHIR_WORKBENCH_CAPABILITY_SCREENSHOT, fullPage: true });
    assert.deepEqual(errors, []);
    console.log('Standalone capability workflow passed: strict default, opt-in, reached failure, unsupported boundary, captured policy, stale results, JSON/Ion drafts, source-profile separation, keyboard and responsive layout.');
  } finally { await page.close(); }
}
