import type { Browser } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createWorkspace, openLocal, openSample, showCompile, showModel } from './workbench-steps.ts';
import { isRecord } from '../../../types/data.ts';

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
  const importModel = async (path: string, content?: string) => {
    await showModel(page);
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
    await openLocal(page, url);
    await page.evaluate(() => {
      const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
      globalThis.morphirWorkbench.request = (data, receive) => request(data, reply => {
        const completed = (window as unknown as ControlledWindow).capabilityTest.completed;
        completed[data.operation] = (completed[data.operation] ?? 0) + 1;
        receive(reply);
      });
    });
    const fixture = fileURLToPath(new URL('../fixtures/capability-execution.json', import.meta.url));
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

    // Current dated source profile stays separate from checking policy in the source document.
    await showCompile(page);
    await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('elm');
    await paint();
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.dataset.language === 'elm');
    await page.getByRole('combobox', { name: 'Target', exact: true }).selectOption('moonbit');
    await paint();
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill(
      'module Workbench.Main exposing (answer, readX)\n\nanswer : Int\nanswer = 42\n\nreadX : { a | x : Int } -> Int\nreadX r = r.x\n');
    await paint();
    await compile('MoonBit generation failed');
    await showModel(page);
    await page.locator('.tree-item[title="workbench:main#answer"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    await choosePolicy('permissive'); await evaluate();
    await page.getByRole('tab', { name: /^Diagnostics/ }).click();
    await page.locator('#tool-panel-body').getByText('Open records require specialization', { exact: false }).first().waitFor();
    await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();
    await showCompile(page);
    await openSample(page, 'MoonBit library');
    await compile();
    const sourceProfile = page.getByRole('combobox', { name: 'Source profile', exact: true });
    assert.equal(await sourceProfile.inputValue(), 'moonbit-model-stable-v1');
    await showModel(page);
    await page.locator('.tree-item[title="user:main#welcome"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    await inputMode('JSON');
    const args = '[{"type":"text","units":[55357,56832]},{"type":"bool","value":true}]';
    await inputs.fill(args); await choosePolicy('permissive');
    await showCompile(page);
    assert.equal(await sourceProfile.inputValue(), 'moonbit-model-stable-v1');
    await showModel(page);
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
      ['MoonBit Boolean library', 'moonbit-model-stable-v1'],
      ['MoonBit Boolean', 'moonbit-model-stable-v1'],
    ]) {
      await showCompile(page);
      await openSample(page, sample!);
      assert.equal(await sourceProfile.inputValue(), profile);
      await compile();
      await showModel(page);
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
      await showCompile(page);
      assert.equal(await sourceProfile.inputValue(), profile, 'Checking policy never upgrades a pinned source profile');
      await showModel(page);
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

interface DesktopPolicyControls {
  completed: Record<string, number>;
  results: import('../browser/contracts.ts').WorkResult[];
  frames: { operation: string; payload?: Record<string, unknown>; contractVersion: string }[];
  holdSubmit: boolean;
  release: (() => void) | null;
  restore: () => void;
}
type DesktopPolicyWindow = Window & { desktopPolicyTest: DesktopPolicyControls };

/** Actual packaged bridge, native owner and Scheme workers. Only reply delivery is controlled. */
export async function desktopCapabilityWorkflow(page: import('playwright').Page) {
  const controls = () => page.evaluate(() => {
    const state: DesktopPolicyControls = { completed: {}, results: [], frames: [], holdSubmit: false, release: null, restore() {} };
    Object.assign(window, { desktopPolicyTest: state });
    const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
    const bridge = window.__MoonBit__!.core!;
    const invoke = bridge.invokeOp!.bind(bridge);
    bridge.invokeOp = async (name, source) => {
      const frame = name === 'app:workbench_native' ? JSON.parse(source) : null;
      if (frame?.operation.startsWith('execution.')) state.frames.push(frame);
      const raw = await invoke(name, source);
      if (frame?.operation === 'execution.submit' && state.holdSubmit) {
        return new Promise(resolve => { state.release = () => { state.holdSubmit = false; state.release = null; resolve(raw); }; });
      }
      return raw;
    };
    globalThis.morphirWorkbench.request = (data, receive) => request(data, source => {
      const result = JSON.parse(source);
      if (result.operation !== 'execution-progress') {
        state.completed[data.operation] = (state.completed[data.operation] ?? 0) + 1;
        if (data.operation === 'evaluate') state.results.push(result);
      }
      receive(source);
    });
    state.restore = () => { globalThis.morphirWorkbench.request = request; bridge.invokeOp = invoke; };
  });
  const state = () => page.evaluate(() => {
    const { completed, results, frames } = (window as unknown as DesktopPolicyWindow).desktopPolicyTest;
    return { completed, results, frames };
  });
  const paint = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const policy = page.getByRole('combobox', { name: 'Capability checks', exact: true });
  const run = page.getByRole('button', { name: 'Evaluate', exact: true });
  const fixture = fileURLToPath(new URL('../fixtures/capability-execution.json', import.meta.url));
  // Keep the dormant branch fixture, adding an unused parameter so the UI
  // exposes its JSON/Ion input controls. The direct owner probe uses the original.
  const uiFixture = (await readFile(fixture, 'utf8')).replace('\"inputTypes\": {}', '\"inputTypes\": {\"unused\": \"morphir/SDK:basics#int\"}');
  const selection = { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: 'permissive' };
  const importModel = async (content?: string) => {
    await showModel(page);
    const before = (await state()).completed.inspect ?? 0;
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
    await (await chooser).setFiles({ name: 'capability-execution.json', mimeType: 'application/json', buffer: Buffer.from(content ?? uiFixture) });
    await page.waitForFunction(before => ((window as unknown as DesktopPolicyWindow).desktopPolicyTest.completed.inspect ?? 0) > before, before);
    await paint();
    await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
    await page.locator('.tree-item[title="selected:main#answer"]').click();
    await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
    await paint();
  };
  const finish = async (before: number) => {
    await page.waitForFunction(before => ((window as unknown as DesktopPolicyWindow).desktopPolicyTest.completed.evaluate ?? 0) > before, before);
    await paint();
  };
  const evaluate = async () => {
    const before = (await state()).completed.evaluate ?? 0;
    await run.click(); await finish(before);
    return (await state()).results.at(-1)!;
  };
  const resultJson = () => page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value);
  const readPolicy = async () => {
    await page.locator('.captured-policy').filter({ hasText: 'As code executes' }).waitFor();
    const result = (await state()).results.at(-1)!;
    assert.deepEqual(result.admission, selection);
    const plan = result.executionPlan;
    assert.ok(isRecord(plan));
    assert.equal(plan.runtime, 'scheme');
    assert.equal(plan.evaluator, 'scheme-portable-v1/shared-sdk/bounded');
    assert.deepEqual(plan.admission, selection);
    assert.deepEqual(plan.identity, result.execution!.identity);
    assert.deepEqual(plan.boundary, { entries: [{ name: 'selected:main#answer', inputs: [{ type: 'int' }], output: { type: 'int' } }], definitions: [] });
  };
  await controls();
  try {
    const direct = await page.evaluate(async model => {
      const call = async (operation: string, sessionId: string | null, payload?: unknown) => {
        const frame = { profile: 'morphir/workbench/native', contractVersion: '0.2.0-draft.2', operation,
          ...(sessionId === null ? {} : { sessionId }), ...(payload === undefined ? {} : { payload }) };
        const source = await window.__MoonBit__!.core!.invokeOp!('app:workbench_native', JSON.stringify(frame));
        const decoded = JSON.parse(globalThis.morphirWorkbenchExecutions(JSON.stringify({ op: 'native-policy-response', source, operation, sessionId })));
        if (!decoded.ok) throw new Error(`The actual native reply failed validation: ${decoded.code}`);
        return decoded.value;
      };
      const opened = await call('session.open', null);
      if (!opened.ok) throw new Error('Cannot open the packaged checking session');
      const descriptor = opened.value;
      const base = { contractVersion: '0.2.0-draft.1', model, entry: 'selected:main#answer', runtime: 'scheme', providerId: descriptor.offer.providerId };
      const strict = await call('execution.submit', descriptor.sessionId, { ...base, inputs: { format: 'json', source: '[]' } });
      const runs = [];
      for (const format of ['json', 'ion-text']) {
        const accepted = await call('execution.submit', descriptor.sessionId, { ...base, inputs: { format, source: '[]' },
          admission: { profile: 'morphir/workbench/admission', contractVersion: '0.1.0-draft.1', policy: 'permissive' } });
        if (!accepted.ok) throw new Error('Actual native permissive submission was refused');
        const body = { contractVersion: '0.2.0-draft.1', identity: accepted.value.identity };
        let terminal = accepted.value.receipt;
        for (let attempt = 0; attempt < 300 && terminal.state !== 'terminal'; attempt++) {
          const observed = await call('execution.query', descriptor.sessionId, body);
          if (!observed.ok) throw new Error('Actual native query was refused');
          terminal = observed.value;
          if (terminal.state !== 'terminal') await new Promise(resolve => setTimeout(resolve, 10));
        }
        if (terminal.state !== 'terminal') throw new Error('The real Scheme worker did not become terminal');
        const released = await call('execution.release', descriptor.sessionId, body);
        runs.push({ format, accepted: accepted.value, terminal, released });
      }
      return { strict, runs };
    }, await readFile(fixture, 'utf8'));
    assert.equal(direct.strict.ok, false, 'The actual owner defaults omitted policy to whole-model checks');
    assert.equal(direct.strict.error.effect, 'none');
    for (const run of direct.runs) {
      assert.deepEqual(run.accepted.plan.admission, selection);
      assert.deepEqual(run.accepted.plan.identity, run.accepted.identity);
      assert.equal(run.accepted.plan.runtime, 'scheme');
      assert.equal(run.accepted.plan.evaluator, 'scheme-portable-v1/shared-sdk/bounded');
      assert.deepEqual(run.terminal.outcomes.calls, [{ id: 'workbench', outcome: { status: 'returned', value: { type: 'int', value: '42' } } }]);
      assert.deepEqual(run.released, { ok: true, operation: 'execution.release', value: { released: true } });
    }
    assert.notEqual(direct.runs[0]!.accepted.identity.executionId, direct.runs[1]!.accepted.identity.executionId);
    assert.notEqual(direct.runs[0]!.accepted.plan.planId, direct.runs[1]!.accepted.plan.planId);
    await importModel();
    assert.equal(await policy.inputValue(), 'strict');
    assert.equal(await policy.locator('option[value="permissive"]').evaluate(e => (e as HTMLOptionElement).disabled), false);
    const initialSubmits = (await state()).frames.filter(f => f.operation === 'execution.submit').length;
    assert.equal((await evaluate()).success, false, 'Whole-model checks refuse the dormant unsupported operation');
    assert.equal((await state()).frames.filter(f => f.operation === 'execution.submit').length, initialSubmits, 'Client preflight refuses the unsupported whole model before a native effect');
    await policy.selectOption('permissive'); await paint();
    for (const mode of ['JSON', 'Ion']) {
      await page.getByRole('button', { name: `${mode} inputs`, exact: true }).click();
      const argumentsSource = mode === 'Ion' ? '[7]' : '[{\"type\":\"int\",\"value\":\"7\"}]';
      await page.getByRole('textbox', { name: 'Function arguments', exact: true }).fill(argumentsSource);
      const result = await evaluate();
      assert.equal(result.success, true);
      assert.deepEqual(result.typed, { type: 'int', value: '42' });
      assert.deepEqual(result.admission, selection);
      await readPolicy();
      await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
      assert.deepEqual(JSON.parse(await resultJson()), { type: 'int', value: '42' });
      const submission = (await state()).frames.filter(f => f.operation === 'execution.submit').at(-1)!;
      assert.equal(submission.contractVersion, '0.2.0-draft.2');
      assert.deepEqual(submission.payload?.admission, selection);
      assert.deepEqual(submission.payload?.inputs, { format: mode === 'Ion' ? 'ion-text' : 'json', source: argumentsSource });
    }
    await policy.selectOption('strict'); await paint();
    await page.locator('.evaluation-result.stale .captured-policy').filter({ hasText: 'As code executes' }).waitFor();
    await showCompile(page);
    await showModel(page);
    assert.equal(await policy.inputValue(), 'strict');
    await page.locator('.captured-policy').filter({ hasText: 'As code executes' }).waitFor();

    // Hold only the real accepted reply. Cancellation still uses the packaged
    // bridge and owner, and cannot rewrite an already captured Returned outcome.
    await policy.selectOption('permissive'); await paint();
    await page.evaluate(() => { (window as unknown as DesktopPolicyWindow).desktopPolicyTest.holdSubmit = true; });
    const beforeCancel = await state();
    await run.click();
    await page.waitForFunction(() => !!(window as unknown as DesktopPolicyWindow).desktopPolicyTest.release);
    assert.equal(await policy.isDisabled(), true, 'An accepted pending selection cannot be edited');
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    await page.evaluate(() => { (window as unknown as DesktopPolicyWindow).desktopPolicyTest.release!(); });
    await finish(beforeCancel.completed.evaluate ?? 0);
    const afterCancel = await state();
    assert.ok(afterCancel.frames.filter(f => f.operation === 'execution.cancel').length > beforeCancel.frames.filter(f => f.operation === 'execution.cancel').length, 'Cancellation crosses the real native bridge');
    await readPolicy();
    assert.equal(await policy.inputValue(), 'permissive');
    await policy.selectOption('strict'); await paint();
    await page.locator('.captured-policy').filter({ hasText: 'As code executes' }).waitFor();

    const reached = uiFixture.replace('"condition": false', '"condition": true');
    await importModel(reached);
    await policy.selectOption('permissive'); await paint();
    const failed = await evaluate();
    assert.equal(failed.success, false);
    await page.locator('.evaluation-result').filter({ hasText: 'execution.unsupported_reached' }).waitFor();
    await readPolicy();
    const frames = (await state()).frames;
    for (const operation of ['execution.submit', 'execution.query', 'execution.cancel', 'execution.release']) assert.ok(frames.some(frame => frame.operation === operation), `Actual packaged ${operation} was exercised`);
  } finally {
    await page.evaluate(() => { const state = (window as unknown as DesktopPolicyWindow).desktopPolicyTest; state.release?.(); state.restore(); });
  }
  // A reloaded local page shows getting started; a new workspace holds the fresh page's model.
  await page.reload();
  await createWorkspace(page);
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  await controls();
  try {
    await importModel();
    assert.equal(await policy.inputValue(), 'strict', 'A new native page starts with whole-model checks');
    assert.equal(await page.locator('.captured-policy').count(), 0, 'Reload never relabels a prior accepted result');
  } finally { await page.evaluate(() => (window as unknown as DesktopPolicyWindow).desktopPolicyTest.restore()); }
  console.log('Packaged Proton capability workflow passed: actual native owner/workers, strict preflight, permissive JSON/Ion, captured policy, cancellation, reached-operation failure, navigation and fresh-page strict default. No OS picker claim.');
}
