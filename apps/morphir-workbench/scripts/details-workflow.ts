import type { Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { openSample } from './workbench-steps.ts';

// Real failures can be read in the tool panel: each failed job and each diagnostic opens its details (code, stage,
// location, message, job context), copies a plain-text report and shows the reply without source or models.
export async function detailsWorkflow(page: Page) {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new URL(page.url()).origin });
  const tab = (name: string) => page.getByRole('tab', { name: new RegExp(`^${name}`) });
  const body = page.locator('#tool-panel-body');
  const clipboard = () => page.evaluate(() => navigator.clipboard.readText());
  const copy = async (scope: ReturnType<Page['locator']>) => {
    await page.evaluate(() => navigator.clipboard.writeText(''));
    await scope.getByRole('button', { name: /^Copy details of / }).click();
    await page.getByRole('status').filter({ hasText: 'Copied the details' }).waitFor();
    return clipboard();
  };

  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('button', { name: 'Compile & inspect', exact: true }).click();
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('elm');
  await page.locator('.file-name').getByText('src/Workbench/Main.elm', { exact: true }).waitFor();
  // A real Elm syntax error.
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('module Workbench.Main exposing (..)\n\nbroken =');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('[role="status"]')?.textContent?.includes('elm.'));

  // Diagnostics: the row opens its code, severity, stage, location, message and job; the location opens the file.
  await tab('Diagnostics').click();
  const row = body.locator('.tool-report.current .tool-diagnostic').first();
  await row.waitFor();
  const code = (await row.locator('.tool-code').textContent())!;
  assert.match(code, /^elm\./, 'The engine code is shown as it is');
  const disclosure = row.locator(':scope > .tool-disclosure');
  assert.equal(await disclosure.getAttribute('aria-expanded'), 'false');
  assert.equal(await disclosure.getAttribute('aria-controls'), null, 'A closed disclosure controls nothing');
  assert.match((await disclosure.getAttribute('aria-label'))!, /^Details of elm\.\S+ at src\/Workbench\/Main\.elm line 3, column \d+$/, 'Each diagnostic names its location');
  await disclosure.focus();
  await page.keyboard.press('Enter');
  const details = row.locator('.tool-details');
  await details.waitFor();
  assert.equal(await disclosure.getAttribute('aria-expanded'), 'true', 'The disclosure says it is open');
  assert.match((await details.getAttribute('id'))!, /^tool-details-diagnostic-\d+-\d+$/, 'Details ids carry the panel prefix');
  assert.equal(await disclosure.getAttribute('aria-controls'), await details.getAttribute('id'));
  const value = (label: string) => details.locator(`dt:text-is("${label}") + dd`);
  assert.equal(await value('Code').textContent(), code);
  assert.equal(await value('Severity').textContent(), 'Error');
  assert.equal(await value('Stage').textContent(), 'frontend');
  assert.match((await value('Location').textContent())!, /^src\/Workbench\/Main\.elm line 3, column \d+elm-source-position-v1 3:/);
  assert.match((await value('Language').textContent())!, /Elm/);
  const report = await copy(details);
  assert.match(report, /^Messages can quote your source\.\nMorphir Workbench diagnostic\nSeverity: Error\nCode: elm\./);
  assert.match(report, /Location: src\/Workbench\/Main\.elm line 3/);
  assert.match(report, /Reported by: Compile \(job \d+, source revision \d+\)/);
  await details.getByRole('button', { name: /^Raw reply of elm\./ }).click();
  const raw = details.getByRole('region', { name: /^Raw reply of elm\.\S+ at src\/Workbench\/Main\.elm/ });
  await raw.waitFor();
  assert.match((await raw.textContent())!, /"success": false/);
  await details.getByRole('button', { name: /^Open src\/Workbench\/Main\.elm/ }).click();
  await page.waitForFunction(() => (document.querySelector<CodeEditor>('#source')?.caretLine ?? 0) === 3);
  await disclosure.click();
  await details.waitFor({ state: 'detached' });
  assert.equal(await disclosure.getAttribute('aria-expanded'), 'false', 'The disclosure closes again');
  assert.equal(await disclosure.getAttribute('aria-controls'), null, 'The closed disclosure controls nothing again');

  // Logs: the failed job opens its context and failure.
  await tab('Logs').click();
  const failedLog = body.locator('.tool-log').filter({ hasText: /Job \d+ failed in/ }).first();
  await failedLog.getByRole('button', { name: /^Details of Compile job \d+$/ }).click();
  const logDetails = failedLog.locator('.tool-details');
  await logDetails.waitFor();
  const logValue = (label: string) => logDetails.locator(`dt:text-is("${label}") + dd`);
  assert.equal(await logValue('Code').textContent(), code);
  assert.equal(await logValue('Project').textContent(), 'Workbench (1 file)');
  assert.match((await logValue('Duration').textContent())!, /^\d+ ms$/);
  const logReport = await copy(logDetails);
  assert.match(logReport, /^Messages can quote your source\.\nMorphir Workbench failure\nOperation: Compile \(job \d+\)\nCode: elm\./);
  assert.ok(logReport.includes('Reply (source, models and values omitted; other text over 32 characters replaced by its size, except messages, codes and paths):'), 'The report says what the reply leaves out');

  // Output: the failed result opens the same details.
  await tab('Output').click();
  const outcome = body.locator('.tool-outcome').filter({ hasText: 'Compile failed' }).first();
  await outcome.getByRole('button', { name: /^Details of Compile job \d+$/ }).click();
  await outcome.locator('.tool-details dt:text-is("Code") + dd').filter({ hasText: code }).waitFor();

  // Details fit a phone-width window.
  const viewport = page.viewportSize();
  if (viewport) {
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'Open details fit a narrow window');
    await page.setViewportSize(viewport);
  }

  // A model that is not valid fails with a stable code and the codec's detail, never a bare key name.
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await (await chooser).setFiles({ name: 'empty.json', mimeType: 'application/json', buffer: Buffer.from('{}') });
  await page.getByRole('status').filter({ hasText: 'The model is not valid' }).waitFor();
  await tab('Logs').click();
  const importLog = body.locator('.tool-log').filter({ hasText: 'The model is not valid' }).first();
  await importLog.locator('.tool-extra .tool-disclosure').click();
  assert.equal(await importLog.locator('.tool-details dt:text-is("Code") + dd').textContent(), 'workbench.invalid_model');
  assert.equal(await importLog.locator('.tool-details dt:text-is("Stage") + dd').textContent(), 'model');

  // A reply that carries source: the MoonBit refusal of Records holds the IR and the source unit, which both quote
  // the module's doc comment. The raw reply keeps their names and sizes and never the text.
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  const targetBox = page.getByRole('combobox', { name: 'Target', exact: true });
  const previousTarget = await targetBox.inputValue();
  await openSample(page, 'Records (parity corpus)');
  await page.locator('[data-path="src/Parity/Records/Points.elm"]').first().waitFor();
  await targetBox.selectOption('moonbit');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'moonbit.unsupported_type' }).waitFor();
  // The refused generation keeps its failure on the Diagnostics report. Clicking the open tab would collapse the panel.
  if (!(await body.isVisible() && await tab('Diagnostics').getAttribute('aria-selected') === 'true')) await tab('Diagnostics').click();
  const refused = body.locator('.tool-report.current .tool-diagnostic').filter({ has: page.locator('.tool-code', { hasText: 'moonbit.unsupported_type' }) }).first();
  await refused.locator(':scope > .tool-disclosure').click();
  const refusedDetails = refused.locator('.tool-details');
  assert.equal(await refusedDetails.locator('dt:text-is("Code") + dd').textContent(), 'moonbit.unsupported_type');
  await refusedDetails.getByRole('button', { name: /^Raw reply of moonbit\.unsupported_type/ }).click();
  const refusedRaw = (await refusedDetails.getByRole('region', { name: /^Raw reply of moonbit\.unsupported_type.*: source, models/ }).textContent())!;
  assert.match(refusedRaw, /"sourceUnitIon": "<omitted: \d+ characters>"/, 'The reply carried the source unit');
  assert.match(refusedRaw, /"irSource": "<omitted: \d+ characters>"/, 'The reply carried the IR');
  assert.match(refusedRaw, /"code": "moonbit\.unsupported_type"/, 'The raw reply keeps the code');
  assert.equal(refusedRaw.includes('Record literals, alias constructors'), false, 'The raw reply leaves out the source text');
  await targetBox.selectOption(previousTarget);

  // Leave a clean Elm project and a closed panel.
  await page.getByRole('button', { name: 'More actions', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Reset project…', exact: true }).click();
  await page.getByRole('button', { name: 'Confirm reset', exact: true }).click();
  if (await body.isVisible()) await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();
  console.log(JSON.stringify({ diagnosticDetails: true, logDetails: true, outputDetails: true, copyDetails: true, rawReply: true, revealFromDetails: true, invalidModelCode: true }));
}
