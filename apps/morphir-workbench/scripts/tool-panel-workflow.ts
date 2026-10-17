import type { Outcome, Failure } from './job-contracts.ts';
import type { Page, Locator, Request, Response, WebSocket, Browser, BrowserContext } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { openSample } from './workbench-steps.ts';

// Shared by the browser and packaged Proton workflows. Content comes from real
// operations in this session: compiles, a frontend refusal and an evaluation.
const recursion = 'pub fn recur(x : Bool) -> Bool { recur(x) }';

// Rabbita renders on the next frame; measure after the update has painted.
async function geometry(page: Page) {
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  return page.evaluate(() => {
    const box = (selector: string) => document.querySelector(selector)?.getBoundingClientRect();
    const experience = document.querySelector<HTMLElement>('main > .experience');
    return {
      viewport: innerHeight, width: innerWidth, page: document.documentElement.scrollHeight,
      pageWidth: document.documentElement.scrollWidth, source: box('#source')?.height ?? 0,
      panelTop: box('.tool-panel')!.top, panelBottom: box('.tool-panel')!.bottom, body: box('#tool-panel-body')?.height ?? 0,
      workspaceTop: box('main > .experience')!.top, workspaceBottom: box('main > .experience')!.bottom,
      workspaceScroll: experience!.scrollTop, documentScroll: document.scrollingElement!.scrollTop,
    };
  });
}

// A focusable control reached from the keyboard is inside the workspace and not under the panel.
async function assertReachable(page: Page, locator: Locator, message: string) {
  await locator.focus();
  const [control, layout] = [await locator.boundingBox(), await geometry(page)];
  assert.ok(control!.y >= layout.workspaceTop - 1 && control!.y + control!.height <= layout.panelTop + 1, message);
  assert.ok(layout.page <= layout.viewport + 1, `${message}: the page itself does not scroll`);
}

export async function toolPanelWorkflow(page: Page, { resize = true } = {}) {
  const tab = (name: string) => page.getByRole('tab', { name: new RegExp(`^${name}`) });
  const body = page.locator('#tool-panel-body');
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('button', { name: 'Compile & inspect', exact: true }).click();
  if (await body.isVisible()) await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();
  await openSample(page, 'MoonBit Boolean library');
  const source = page.getByRole('textbox', { name: 'Source editor', exact: true });
  const compile = page.getByRole('button', { name: 'Compile', exact: true });
  await compile.click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  const collapsed = await geometry(page);
  assert.equal(await body.isVisible(), false, 'The panel starts as a compact bar');
  assert.ok(collapsed.panelBottom <= collapsed.viewport + 1 && collapsed.viewport - collapsed.panelTop <= 70, 'The collapsed bar stays at the bottom of the window');

  // Start from an empty diagnostics history so counts below come from this workflow.
  await tab('Diagnostics').click();
  await body.waitFor();
  await page.getByRole('button', { name: 'Clear diagnostics', exact: true }).click();
  await body.getByText('No diagnostics yet.', { exact: false }).waitFor();
  await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();
  // Logs are bounded application operations with job, revision and duration.
  await tab('Logs').click();
  await body.waitFor();
  assert.equal(await tab('Logs').getAttribute('aria-selected'), 'true');
  const logs = body.locator('.tool-log');
  assert.match((await logs.filter({ hasText: 'Started job' }).first().textContent()!)!, /Compile.*Started job \d+ · source revision \d+ · moonbit \(moonbit-model-bool-library-v1\)/);
  assert.match((await logs.first().textContent()!)!, /Compile.*Job \d+ finished in \d+ ms · user · 1 modules, 0 types, 3 values/);
  const open = await geometry(page);
  assert.ok(Math.abs(collapsed.source - open.source - open.body) <= 4, `Opening the panel takes its height from the code panes (${collapsed.source} → ${open.source}, panel ${open.body})`);
  assert.ok(open.panelBottom <= open.viewport + 1 && open.page <= open.viewport + 1, 'The open panel stays inside the window');
  await assertReachable(page, compile, 'Compile stays reachable above the open panel');

  // Panel changes do not remount editors: an edit made before them still undoes.
  const library = await page.locator('#source').evaluate(editor => (editor as CodeEditor).value);
  await source.press('ControlOrMeta+End');
  await source.pressSequentially(' // panel draft');
  for (const control of ['Maximize panel', 'Restore panel size', 'Collapse panel']) {
    await page.getByRole('button', { name: control, exact: true }).click();
  }
  await tab('Logs').click();
  await source.press('ControlOrMeta+z');
  await page.waitForFunction(text => document.querySelector<CodeEditor>('#source')?.value === text, library);
  assert.equal(await page.getByRole('combobox', { name: 'Source profile', exact: true }).inputValue(), 'moonbit-model-bool-library-v1');

  // A real frontend refusal is a current diagnostic with code and location until the source changes.
  await source.fill(recursion);
  await compile.click();
  await page.getByRole('status').filter({ hasText: 'recursive_call' }).waitFor();
  await tab('Diagnostics').click();
  const current = body.locator('.tool-report.current').filter({ hasText: 'recursive_call' });
  await current.waitFor();
  assert.equal(await current.locator('.tool-code').textContent(), 'moonbit_frontend.recursive_call');
  // The diagnostic points to the declaration name 'recur', after 'pub fn '.
  assert.equal(await current.locator('.tool-location').textContent(), 'src/main.mbt line 1, column 8');
  assert.match((await current.locator('.tool-location').getAttribute('title')!)!, /^moonbit-parser-position-v1 1:7–/);
  assert.equal(await tab('Diagnostics').locator('.tool-count').textContent(), '1');
  await source.press('ControlOrMeta+End');
  await source.pressSequentially(' ');
  await body.locator('.tool-report.previous').filter({ hasText: 'recursive_call' }).waitFor();
  assert.equal(await tab('Diagnostics').locator('.tool-count').isVisible(), false, 'Editing the source makes the report previous');
  await source.fill(library);
  await compile.click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await body.locator('.tool-report.current').filter({ hasText: 'No problems reported.' }).first().waitFor();

  // Tab keys move focus and selection without scrolling the page or the workspace.
  await page.evaluate(() => {
    globalThis.toolKeys = [];
    document.addEventListener('keydown', event => globalThis.toolKeys.push(event.defaultPrevented));
  });
  const before = await geometry(page);
  await tab('Diagnostics').focus();
  for (const [key, id] of [['ArrowRight', 'tool-tab-output'], ['Home', 'tool-tab-logs'], ['End', 'tool-tab-output'], ['ArrowRight', 'tool-tab-logs'], ['ArrowLeft', 'tool-tab-output']] as const) {
    await page.keyboard.press(key!);
    await page.waitForFunction(id => document.activeElement?.id === id, id, { timeout: 2000 })
      .catch(() => assert.fail(`${key} moves focus to ${id}`));
    assert.equal(await page.locator(`#${id}`).getAttribute('aria-selected'), 'true');
  }
  assert.deepEqual(await page.evaluate(() => globalThis.toolKeys), [true, true, true, true, true], 'Tab keys prevent their default scrolling');
  const after = await geometry(page);
  assert.equal(after.workspaceScroll, before.workspaceScroll);
  assert.equal(after.documentScroll, before.documentScroll);
  await page.keyboard.press('Enter');
  await body.waitFor({ state: 'hidden', timeout: 2000 }).catch(() => assert.fail('Activating the open tab collapses the panel'));
  await page.keyboard.press('Enter');
  await body.waitFor({ timeout: 2000 });
  assert.equal(await tab('Output').getAttribute('aria-selected'), 'true');

  // Output keeps results; the panel state survives experience navigation.
  await body.locator('.tool-outcome').filter({ hasText: 'recursive_call' }).first().waitFor();
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.getByRole('heading', { name: 'Model Explorer', exact: true }).waitFor();
  assert.equal(await body.isVisible(), true, 'The open Output tab is retained in Model Explorer');
  await page.getByRole('heading', { name: 'Model Explorer', exact: true }).waitFor();
  if (!await page.locator('#context-navigation').isVisible()) await page.getByRole('button', { name: 'Toggle sidebar', exact: true }).click();
  await page.locator('.model-tree .tree-item').filter({ hasText: 'eligible' }).click();
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.getByRole('combobox', { name: 'activeUser', exact: true }).selectOption('true');
  await page.getByRole('combobox', { name: 'vipMember', exact: true }).selectOption('false');
  const evaluate = page.getByRole('button', { name: 'Evaluate', exact: true });
  await assertReachable(page, evaluate, 'Evaluate stays reachable above the open panel');
  await evaluate.click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  const evaluated = body.locator('.tool-outcome').first();
  assert.match((await evaluated.textContent()!)!, /Evaluate eligible · scheme-portable-v1\/shared-sdk\/bounded/);
  assert.equal(await evaluated.locator('.terminal-kind').textContent(), 'Returned');
  assert.deepEqual(JSON.parse((await evaluated.locator('.terminal-preview').textContent()!)!), {type:'bool',value:true});
  // An input error belongs to its model: replacing the model makes it previous.
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  await page.getByRole('textbox', { name: 'Function arguments', exact: true }).fill('not json');
  await evaluate.click();
  await page.getByRole('status').filter({ hasText: 'Invalid evaluation inputs' }).waitFor();
  await tab('Diagnostics').click();
  const inputReport = body.locator('.tool-report').filter({ hasText: 'Arguments must be a valid JSON array' });
  await inputReport.locator('.tool-badge', { hasText: 'Current' }).waitFor();
  assert.equal(await tab('Diagnostics').locator('.tool-count').textContent(), '1');
  assert.equal(await inputReport.locator('.tool-location').textContent(), 'eligible');
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await compile.click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  assert.equal(await inputReport.locator('.tool-badge').textContent(), 'Previous', 'A replaced model makes its input diagnostics previous');
  assert.equal(await tab('Diagnostics').locator('.tool-count').isVisible(), false, 'Previous input diagnostics are not current problems');
  await tab('Output').click();
  await page.waitForFunction(() => document.getElementById('tool-tab-output')?.getAttribute('aria-selected') === 'true');

  // Expanded and short windows keep the workspace scrollable above the panel.
  const restored = await geometry(page);
  await page.getByRole('button', { name: 'Maximize panel', exact: true }).click();
  const expanded = await geometry(page);
  assert.ok(expanded.body > restored.body + 100, 'Maximize gives the panel more height');
  await assertReachable(page, compile, 'Compile scrolls into the workspace with a maximized panel');
  const sizes: [number, number, string][] = resize ? [[1440, 640, 'short window'], [390, 844, 'narrow window']] : [];
  const viewport = page.viewportSize();
  for (const [width, height, label] of sizes) {
    await page.setViewportSize({ width, height });
    const layout = await geometry(page);
    assert.ok(layout.panelBottom <= layout.viewport + 1 && layout.pageWidth <= layout.width, `The panel fits the ${label}`);
    await assertReachable(page, compile, `Compile stays reachable in the ${label}`);
    await page.getByRole('button', { name: 'Restore panel size', exact: true }).click();
    await assertReachable(page, compile, `Compile stays reachable with a normal panel in the ${label}`);
    await page.getByRole('button', { name: 'Maximize panel', exact: true }).click();
  }
  if (viewport && sizes.length) await page.setViewportSize(viewport);
  await page.getByRole('button', { name: 'Restore panel size', exact: true }).click();
  await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();
  const closed = await geometry(page);
  assert.ok(Math.abs(closed.source - restored.source - restored.body) <= 4, `Collapsing returns the panel height to the code panes (${restored.source} + ${restored.body} → ${closed.source})`);
  // Real normalization recovery keeps both declarations under one warning.
  const collision = 'pub fn is_ready() -> Bool { true }\npub fn isReady() -> Bool { false }';
  await source.fill(collision);
  await compile.click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await tab('Diagnostics').click();
  const recovered = body.locator('.tool-report.current .tool-diagnostic').filter({ hasText: 'moonbit_frontend.name_normalization_collision' });
  await recovered.waitFor();
  assert.equal(await tab('Diagnostics').locator('.tool-count').textContent(), '1', 'Both related declarations count as one problem');
  const disclosure = recovered.locator(':scope > .tool-disclosure');
  await disclosure.focus();
  await page.keyboard.press('Enter');
  await recovered.locator('.tool-related').waitFor();
  assert.equal(await disclosure.getAttribute('aria-expanded'), 'true');
  const related = recovered.locator('.tool-related li');
  assert.equal(await related.count(), 2);
  assert.match((await related.first().textContent()!)!, /Authored: isReady · Allocated: is-ready-source-/);
  assert.match((await related.last().textContent()!)!, /Authored: is_ready · Allocated: is-ready/);
  assert.equal(await related.first().locator('span').last().textContent(), 'line 2, column 8');
  assert.match((await recovered.locator('.tool-fix').textContent()!)!, /Rename is_ready/);
  assert.match((await related.first().locator('span').last().getAttribute('title')!)!, /moonbit-parser-position-v1 2:7/);
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  await page.getByRole('navigation', { name: 'Generated files', exact: true }).getByRole('button', { name: 'library.mbt', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|library.mbt');
  const generated = await page.locator('#output').evaluate(editor => (editor as CodeEditor).value);
  assert.match(generated, /fn isReady\(/, 'Readable backend allocation retains usable source spelling');
  assert.match(generated, /fn is_ready\(/, 'The distinct declaration keeps its own public name');
  const recoveredReport = body.locator('.tool-report').filter({ hasText: 'moonbit_frontend.name_normalization_collision' }).first();
  await source.fill(library);
  await recoveredReport.locator('.tool-badge').filter({ hasText: 'Previous' }).waitFor();
  await compile.click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  assert.equal(await tab('Diagnostics').locator('.tool-count').isVisible(), false);
  await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();
  console.log(JSON.stringify({ toolPanel: true, namingWarnings: true, collapsedDefault: true, realLogs: true, scopedDiagnostics: true, output: true, keyboardTabs: true, preventsScroll: true, retainedAcrossExperiences: true, undoPreserved: true, resized: sizes.length > 0 }));
}

// The local producer genuinely returns a value. Cleanup/failure/cancellation
// combinations below are explicit evidence fixtures, not claims of host execution.
export async function terminalOutcomeWorkflow(page: Page, { resize = true, screenshot }: { resize?: boolean; screenshot?: string } = {}) {
  const body = page.locator('#tool-panel-body');
  const output = page.getByRole('tab', { name: /^Output/ });
  const diagnostics = page.getByRole('tab', { name: /^Diagnostics/ });
  const open = async (tab: Locator) => {
    if (!await body.isVisible() || await tab.getAttribute('aria-selected') !== 'true') await tab.click();
    await body.waitFor();
  };
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('heading', {name:'Try Morphir',exact:true}).waitFor();
  await openSample(page, 'MoonBit Boolean library');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.waitForFunction(() => ![...document.querySelectorAll<HTMLButtonElement>('button')].find(b => b.textContent.trim() === 'Compile')?.disabled && document.querySelector<HTMLElement>('.statusbar')?.textContent === 'Model ready');
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.locator('.model-tree .tree-item').filter({ hasText: 'eligible' }).click();
  await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.getByRole('combobox', { name: 'activeUser', exact: true }).selectOption('true');
  await page.getByRole('combobox', { name: 'vipMember', exact: true }).selectOption('false');
  await open(output);
  await page.getByRole('button', { name: 'Clear output', exact: true }).click();
  const evaluate = page.getByRole('button', { name: 'Evaluate', exact: true });
  await evaluate.click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result .terminal-kind').textContent(), 'Returned');
  assert.deepEqual(JSON.parse((await body.locator('.terminal-preview').textContent()!)!), {type:'bool',value:true});
  await page.getByRole('button', { name: 'Result JSON', exact: true }).click();

  await page.evaluate(() => {
    const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
    globalThis.morphirWorkbench.request = (data, receive) => {
      if (data.operation === 'evaluate' && globalThis.terminalFixture) queueMicrotask(() => receive(JSON.stringify(globalThis.terminalFixture)));
      else request(data, reply => {
        if (data.operation === 'evaluate' && globalThis.holdTerminalReply) {
          delete globalThis.holdTerminalReply;
          globalThis.releaseTerminalReply = () => { delete globalThis.releaseTerminalReply; receive(reply); };
        } else receive(reply);
      });
    };
    globalThis.restoreTerminalRequests = () => { globalThis.morphirWorkbench.request = request; delete globalThis.terminalFixture; };
  });
  const fixture = async (outcome: Outcome, cleanup: Failure | null = null, id = 'workbench') => {
    await page.evaluate((source: string) => {
      const {outcome,cleanup,id} = JSON.parse(source);
      globalThis.terminalFixture = {success:true,profile:'explicit-evidence-fixture',typed:{type:'int',value:'999'},value:'forged legacy value',terminalOutcomes:{contractVersion:'0.1.0-draft.5',calls:[{id,outcome}],cleanup,extensions:null}};
    }, JSON.stringify({outcome,cleanup,id}));
    await evaluate.click();
  };
  const cleanup = {stage:'cleanup',code:'provider.dispose',message:'Fixture disposal failed'};
  const viewport = page.viewportSize();
  try {
    await page.evaluate(() => { globalThis.holdTerminalReply = true; });
    await evaluate.click();
    await page.waitForFunction(() => typeof globalThis.releaseTerminalReply === 'function');
    await page.getByRole('combobox', {name:'activeUser',exact:true}).selectOption('false');
    await page.evaluate(() => globalThis.releaseTerminalReply!());
    await page.getByRole('status').filter({hasText:'Finished for earlier inputs'}).waitFor();
    assert.equal(await page.locator('.evaluation-result.stale .terminal-kind').textContent(), 'Returned');
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'bool',value:true});
    await page.evaluate(() => { globalThis.holdTerminalReply = true; });
    await evaluate.click();
    await page.waitForFunction(() => typeof globalThis.releaseTerminalReply === 'function');
    await page.getByRole('button', {name:'Cancel',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Cancelled'}).waitFor();
    await page.evaluate(() => globalThis.releaseTerminalReply!());
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'bool',value:true}, 'A cancelled UI job ignores its late terminal evidence');
    await page.getByRole('combobox', {name:'activeUser',exact:true}).selectOption('true');
    await fixture({status:'returned',value:{type:'bool',value:true}}, cleanup);
    await page.getByRole('status').filter({hasText:'Returned · Cleanup failed'}).waitFor();
    const result = page.locator('.evaluation-result');
    assert.equal(await result.locator('.terminal-kind').textContent(), 'Returned');
    assert.equal(await result.evaluate(e => e.classList.contains('failed')), false, 'Cleanup does not paint the returned value as failed');
    assert.match((await result.locator('.terminal-cleanup').textContent()!)!, /provider.dispose.*Fixture disposal failed/);
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#evaluation-output')?.value === '{\n  "type": "bool",\n  "value": true\n}');
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'bool',value:true}, 'Cleanup failure preserves the admitted value and ignores forged legacy fields');
    await open(output);
    const latest = body.locator('.tool-outcome').first();
    assert.equal(await latest.locator('.terminal-kind').textContent(), 'Returned');
    assert.match((await latest.locator('.terminal-cleanup').textContent()!)!, /provider.dispose/);
    if (screenshot) await page.screenshot({path:screenshot,fullPage:false});
    if (resize) {
      await page.setViewportSize({width:390,height:844});
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'Outcome and cleanup fit narrow windows');
      await page.setViewportSize(viewport!);
    }
    await fixture({status:'failed',failure:{stage:'evaluate',code:'execution.evaluate',message:'Fixture evaluation failed'}}, cleanup);
    await result.locator('.terminal-call.failed').waitFor();
    assert.equal(await result.locator('.terminal-kind').textContent(), 'Failed');
    assert.equal(await result.locator(':scope > p').textContent(), 'Failed · Cleanup failed');
    assert.equal(await page.locator('#evaluation-output').count(), 0, 'A failed terminal has no invented value editor');
    await open(diagnostics);
    const causes = body.locator('.tool-report.current').filter({hasText:'execution.evaluate'});
    await causes.waitFor();
    assert.deepEqual(await causes.locator('.tool-code').allTextContents(), ['provider.dispose','execution.evaluate']);
    await fixture({status:'cancelled'}, cleanup);
    await result.locator('.terminal-call.cancelled').waitFor();
    assert.equal(await result.locator('.terminal-kind').textContent(), 'Cancelled');
    assert.equal(await result.locator(':scope > p').textContent(), 'Cancelled · Cleanup failed');
    assert.match((await result.locator('.terminal-cleanup').textContent()!)!, /provider.dispose/);
    await fixture({status:'returned',value:{type:'bool',value:true}}, null, 'wrong-call');
    await result.locator('.terminal-invalid').waitFor();
    assert.match((await result.locator('.terminal-invalid').textContent()!)!, /execution.call_identity/);
    assert.equal(await result.locator('.terminal-kind').count(), 0, 'Mismatched evidence does not fall back to success');
    assert.equal(await page.locator('#evaluation-output').count(), 0);
  } finally {
    if (resize && viewport) await page.setViewportSize(viewport);
    await page.evaluate(() => { globalThis.restoreTerminalRequests!(); delete globalThis.restoreTerminalRequests; });
  }
  await evaluate.click();
  await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
  await open(output);
  assert.equal(await body.locator('.tool-outcome').first().locator('.terminal-kind').textContent(), 'Returned', 'Real local producer restored');
  await page.getByRole('button', {name:'Collapse panel',exact:true}).click();
}
