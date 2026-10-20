import type { Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { showCompile, setExplorer } from './workbench-steps.ts';

// The project explorer, its context menu, its shortcuts and the command palette, driven from the mouse and the
// keyboard as a person would. Starts from any state of the local workbench and leaves the Elm project reset.
export async function explorerWorkflow(page: Page) {
  const app = 'src/Morphir/Example/App';
  const tree = page.getByRole('tree', { name: 'Project files', exact: true });
  const row = (path: string) => tree.locator(`[role="treeitem"][data-path="${path}"]`);
  const waitFocus = (expected: string) => page.waitForFunction(expected => {
    const el = document.activeElement;
    return (el?.getAttribute('data-path') ?? el?.id) === expected;
  }, expected);
  const palette = page.getByRole('dialog', { name: 'Command palette', exact: true });
  const paletteInput = palette.getByRole('combobox');
  const openPalette = async (keys: string) => {
    await page.keyboard.press(keys);
    await palette.waitFor();
    await waitFocus('palette-input');
  };
  const runCommand = async (name: string) => {
    await openPalette('ControlOrMeta+Shift+P');
    await paletteInput.fill('>' + name);
    await page.waitForFunction(name => document.querySelector('#palette-list [role="option"][aria-selected="true"]')?.getAttribute('aria-label') === name, name, { timeout: 10000 })
      .catch(async error => {
        // Say what the palette showed, so a failure names the state rather than only the timeout.
        const shown = await page.evaluate(() => ({
          query: document.querySelector<HTMLInputElement>('#palette-input')?.value,
          options: [...document.querySelectorAll('#palette-list [role="option"]')].map(o => `${o.getAttribute('aria-label')}${o.getAttribute('aria-selected') === 'true' ? ' (selected)' : ''}`),
          status: document.querySelector('.statusbar')?.textContent,
        }));
        throw new Error(`The palette did not select ${name}: ${JSON.stringify(shown)}`, { cause: error });
      });
    await paletteInput.press('Enter');
  };

  const fileName = page.locator('[data-document="source"] .document-tab-label');
  await showCompile(page);
  await setExplorer(page, true);
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('elm');
  await row('src/Workbench/Main.elm').waitFor();

  // Samples live in the palette and the project menu, not in the sidebar.
  assert.equal(await page.locator('#sidebar-primary').getByText('EXAMPLES', { exact: true }).count(), 0, 'The sidebar has no examples list');
  await page.getByRole('button', { name: 'More actions', exact: true }).click();
  const projectMenu = page.getByRole('menu', { name: 'Project actions', exact: true });
  await projectMenu.locator('.context-menu-heading').getByText('New from sample', { exact: true }).waitFor();
  const menuSamples = await projectMenu.getByRole('menuitem').evaluateAll(items => items.map(item => item.getAttribute('aria-label')).filter(name => name?.startsWith('New from sample: ')));
  assert.deepEqual(menuSamples.slice(0, 4), ['Pricing & arithmetic', 'Elm constant', 'MoonBit Boolean', 'MoonBit library'].map(label => 'New from sample: ' + label));
  assert.ok(menuSamples.includes('New from sample: Rentals tutorial (morphir-examples)'), 'Elm lists its corpus samples in the menu');
  await page.keyboard.press('Escape');
  await projectMenu.waitFor({ state: 'detached' });
  // F1 opens commands; each sample is one entry, the same list as the menu.
  await openPalette('F1');
  assert.equal(await paletteInput.inputValue(), '>', 'F1 lists commands');
  await paletteInput.fill('>open sample');
  // Rabbita renders on the next animation frame; fill() only waits for the input event.
  await page.waitForFunction(count => document.querySelectorAll('#palette-list [role="option"]').length === count, menuSamples.length);
  const paletteSamples = await palette.getByRole('option').evaluateAll(items => items.map(item => item.getAttribute('aria-label')));
  // The palette ranks by match, so ignore order while still rejecting duplicate entries.
  assert.deepEqual(paletteSamples.filter(name => name?.startsWith('Open sample: ')).map(name => name?.slice('Open sample: '.length)).sort(),
    menuSamples.map(name => name?.slice('New from sample: '.length)).sort(), 'The palette and the menu list the same samples');
  await paletteInput.fill('>rentals tutorial');
  await page.waitForFunction(() => document.querySelector('#palette-list [role="option"][aria-selected="true"]')?.getAttribute('aria-label') === 'Open sample: Rentals tutorial (morphir-examples)');
  await paletteInput.press('Enter');
  await palette.waitFor({ state: 'detached' });
  await page.waitForFunction(() => document.querySelectorAll('[role="tree"] .explorer-row.is-file').length === 6);
  assert.equal(await row(app).getAttribute('aria-expanded'), 'true', 'Single folders compact into one open row');
  assert.equal(await page.locator('#sidebar-primary .sidebar-sections').evaluate(sections => sections.scrollWidth <= sections.clientWidth), true, 'The sidebar never scrolls sideways');

  // Tree keys: roving focus and the WAI-ARIA tree pattern.
  const tabStops = await tree.locator('[role="treeitem"][tabindex="0"]').count();
  assert.equal(tabStops, 1, 'Exactly one row is a Tab stop');
  await row(app + '/App.elm').click();
  await waitFocus(app + '/App.elm');
  await page.keyboard.press('ArrowDown');
  await waitFocus(app + '/BusinessTerms.elm');
  await page.keyboard.press('ArrowUp');
  await waitFocus(app + '/App.elm');
  await page.keyboard.press('End');
  await waitFocus(app + '/Winds.elm');
  await page.keyboard.press('Home');
  await waitFocus(app);
  await page.keyboard.press('ArrowLeft');
  await page.waitForFunction(path => document.querySelector(`[data-path="${path}"]`)?.getAttribute('aria-expanded') === 'false', app);
  assert.equal(await row(app + '/App.elm').count(), 0, 'Left closes the folder');
  await page.keyboard.press('ArrowRight');
  await row(app + '/App.elm').waitFor();
  await page.keyboard.press('ArrowRight');
  await waitFocus(app + '/Analytics.elm');
  await page.keyboard.press('f');
  await waitFocus(app + '/Forecast.elm');
  await page.keyboard.press('Enter');
  await fileName.getByText(app + '/Forecast.elm', { exact: true }).waitFor();
  await page.waitForFunction(() => document.activeElement?.id === 'source', null, { timeout: 5000 });

  // New file in a folder from its context menu; a name with a slash makes a subfolder.
  await row(app).click({ button: 'right' });
  const menu = page.getByRole('menu');
  await menu.waitFor();
  await menu.getByRole('menuitem', { name: 'New file…', exact: true }).click();
  const newName = tree.getByRole('textbox', { name: 'New file name in ' + app, exact: true });
  await waitFocus('explorer-input');
  await newName.fill('Sub/Util');
  await newName.press('Enter');
  await tree.locator('.explorer-error').getByText(/Use one of \.elm/).waitFor();
  assert.equal(await newName.isVisible(), true, 'A refused name keeps its input open');
  await newName.fill('Sub/Util.elm');
  await newName.press('Enter');
  await row(app + '/Sub/Util.elm').waitFor();
  await row(app + '/Sub').waitFor();
  assert.equal(await row(app + '/Sub/Util.elm').getAttribute('aria-selected'), 'true', 'The new file opens');
  assert.match(await page.locator('#source').evaluate(editor => (editor as CodeEditor).value), /module Morphir\.Example\.App\.Sub\.Util exposing/);
  assert.equal(await row(app + '/Sub').getAttribute('aria-level'), '2');
  assert.equal(await row(app + '/Sub/Util.elm').getAttribute('aria-level'), '3');

  // Right-click → Rename: the name is selected up to its extension; a duplicate is refused inline.
  await row(app + '/Sub/Util.elm').click({ button: 'right' });
  await menu.getByRole('menuitem', { name: 'Rename…', exact: true }).click();
  const renameBox = tree.getByRole('textbox', { name: 'New name for Util.elm', exact: true });
  await waitFocus('explorer-input');
  assert.deepEqual(await renameBox.evaluate(input => [(input as HTMLInputElement).selectionStart, (input as HTMLInputElement).selectionEnd]), [0, 4]);
  await page.keyboard.type('../App');
  await renameBox.press('Enter');
  await tree.locator('.explorer-error').waitFor();
  await renameBox.fill('Helpers.elm');
  await renameBox.press('Enter');
  await row(app + '/Sub/Helpers.elm').waitFor();
  await waitFocus(app + '/Sub/Helpers.elm');

  // F2 renames the focused row; Escape cancels and keeps the name.
  await page.keyboard.press('F2');
  await waitFocus('explorer-input');
  await page.keyboard.type('Gone');
  await page.keyboard.press('Escape');
  await waitFocus(app + '/Sub/Helpers.elm');
  assert.equal(await row(app + '/Sub/Helpers.elm').count(), 1, 'Escape keeps the name');
  await page.keyboard.press('F2');
  await waitFocus('explorer-input');
  await page.keyboard.type('Tools');
  await page.keyboard.press('Enter');
  await row(app + '/Sub/Tools.elm').waitFor();

  // Delete asks inline; Escape keeps the file, Enter confirms.
  await waitFocus(app + '/Sub/Tools.elm');
  await page.keyboard.press('Delete');
  await tree.getByText('Delete Tools.elm?', { exact: true }).waitFor();
  await waitFocus('explorer-confirm');
  await page.keyboard.press('Escape');
  await waitFocus(app + '/Sub/Tools.elm');
  await page.keyboard.press('Delete');
  await waitFocus('explorer-confirm');
  await page.keyboard.press('Enter');
  await row(app + '/Sub/Tools.elm').waitFor({ state: 'detached' });
  assert.equal(await page.locator('.explorer-row.is-file').count(), 6);

  // Shift+F10 opens the menu of the focused row; arrows move, Escape returns to the row.
  await row(app + '/Rentals.elm').click();
  await waitFocus(app + '/Rentals.elm');
  await page.keyboard.press('Shift+F10');
  await menu.waitFor();
  assert.equal(await menu.getAttribute('aria-label'), 'Actions for Rentals.elm');
  await waitFocus('explorer-menu-0');
  await page.keyboard.press('ArrowUp');
  const last = await menu.getByRole('menuitem').count() - 1;
  await waitFocus('explorer-menu-' + last);
  assert.equal(await menu.getByRole('menuitem').last().textContent(), 'Stop exposing module');
  assert.equal(await menu.getByRole('menuitem', { name: 'Rename…', exact: true }).getAttribute('aria-keyshortcuts'), 'F2');
  const box = (await menu.boundingBox())!;
  const viewport = page.viewportSize()!;
  assert.ok(box.x >= 0 && box.y >= 0 && box.x + box.width <= viewport.width && box.y + box.height <= viewport.height, 'The menu stays in the viewport');
  await page.keyboard.press('Escape');
  await menu.waitFor({ state: 'detached' });
  await waitFocus(app + '/Rentals.elm');
  // Exposure from the menu: the marker follows.
  await page.keyboard.press('Shift+F10');
  await menu.getByRole('menuitem', { name: 'Stop exposing module', exact: true }).click();
  await page.waitForFunction(path => !document.querySelector(`[data-path="${path}"] .explorer-exposed`), app + '/Rentals.elm');
  // An outside click closes a menu.
  await row(app + '/Winds.elm').click({ button: 'right' });
  await menu.waitFor();
  await page.mouse.click(900, 600);
  await menu.waitFor({ state: 'detached' });
  // A right-click outside an open menu, here over the editor, only closes it; a right-click on an item keeps it.
  const frames = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await row(app + '/Winds.elm').click({ button: 'right' });
  await menu.waitFor();
  await menu.getByRole('menuitem', { name: 'Copy path', exact: true }).click({ button: 'right' });
  await frames();
  assert.equal(await page.getByRole('menu').count(), 1);
  assert.equal(await menu.getAttribute('aria-label'), 'Actions for Winds.elm', 'A right-click on an item opens no other menu');
  await page.mouse.click(900, 600, { button: 'right' });
  await menu.waitFor({ state: 'detached' });
  await frames();
  assert.equal(await page.getByRole('menu').count(), 0, 'A right-click outside the menu opens no project menu');

  // Ctrl/Cmd+P opens quick open from the editor; fuzzy letters are marked; Enter opens the file in the editor.
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).click();
  await page.keyboard.press('F2');
  assert.equal(await tree.getByRole('textbox').count(), 0, 'Tree shortcuts do not fire in the editor');
  await openPalette('ControlOrMeta+P');
  assert.equal(await palette.locator('.palette-chip').textContent(), 'Go to file');
  await paletteInput.fill('bterms');
  const option = palette.getByRole('option', { name: 'BusinessTerms.elm', exact: true });
  await page.waitForFunction(() => document.querySelectorAll('#palette-list [role="option"]').length === 1);
  assert.equal(await option.getAttribute('aria-selected'), 'true');
  assert.equal(await paletteInput.getAttribute('aria-activedescendant'), await option.getAttribute('id'));
  assert.deepEqual(await option.locator('.palette-match').allTextContents(), ['B', 'Terms']);
  await paletteInput.press('Enter');
  await palette.waitFor({ state: 'detached' });
  await fileName.getByText(app + '/BusinessTerms.elm', { exact: true }).waitFor();
  assert.equal(await row(app + '/BusinessTerms.elm').getAttribute('aria-selected'), 'true');
  await page.waitForFunction(() => document.activeElement?.id === 'source', null, { timeout: 5000 });
  // Escape closes the palette and returns the focus where it was.
  await row(app + '/Winds.elm').click();
  await openPalette('ControlOrMeta+P');
  await paletteInput.press('Escape');
  await palette.waitFor({ state: 'detached' });
  await waitFocus(app + '/Winds.elm');
  // A palette command that moves the focus keeps it: Rename file… puts typing in the inline input.
  await runCommand('Rename file…');
  await waitFocus('explorer-input');
  await page.keyboard.type('Breeze');
  await page.keyboard.press('Enter');
  await row(app + '/Breeze.elm').waitFor();
  assert.equal(await row(app + '/Winds.elm').count(), 0, 'The open file was renamed from the palette');
  await waitFocus(app + '/Breeze.elm');

  // The keyboard selection stays in view in a list longer than the palette.
  await openPalette('ControlOrMeta+Shift+P');
  const inView = () => page.evaluate(() => {
    const list = document.getElementById('palette-list');
    const selected = list?.querySelector('[aria-selected="true"]');
    if (!list || !selected) return false;
    const outer = list.getBoundingClientRect(), inner = selected.getBoundingClientRect();
    return inner.top >= outer.top - 1 && inner.bottom <= outer.bottom + 1;
  });
  assert.equal(await page.locator('#palette-list').evaluate(list => list.scrollHeight > list.clientHeight), true, 'The command list is longer than the palette');
  await paletteInput.press('ArrowUp');
  await page.waitForFunction(() => document.querySelector('#palette-list [role="option"]:last-child')?.getAttribute('aria-selected') === 'true');
  await page.waitForFunction(() => {
    const list = document.getElementById('palette-list');
    const selected = list?.querySelector('[aria-selected="true"]');
    if (!list || !selected) return false;
    const outer = list.getBoundingClientRect(), inner = selected.getBoundingClientRect();
    return inner.top >= outer.top - 1 && inner.bottom <= outer.bottom + 1;
  });
  await paletteInput.press('ArrowDown');
  await page.waitForFunction(() => document.querySelector('#palette-list [role="option"]')?.getAttribute('aria-selected') === 'true');
  await page.waitForFunction(() => {
    const list = document.getElementById('palette-list');
    const selected = list?.querySelector('[aria-selected="true"]');
    if (!list || !selected) return false;
    const outer = list.getBoundingClientRect(), inner = selected.getBoundingClientRect();
    return inner.top >= outer.top - 1 && inner.bottom <= outer.bottom + 1;
  });
  assert.equal(await inView(), true);
  await paletteInput.press('Escape');
  await palette.waitFor({ state: 'detached' });

  // Without a right button or a chord: the row's ⋯ button, the top-bar button and More actions open the same menus.
  await row(app + '/App.elm').hover();
  const more = row(app + '/App.elm').getByRole('button', { name: 'More actions for App.elm', exact: true });
  assert.equal(await more.evaluate(button => getComputedStyle(button).opacity), '1', 'Hovering a row shows its ⋯ button');
  await more.click();
  await menu.waitFor();
  assert.equal(await menu.getAttribute('aria-label'), 'Actions for App.elm');
  assert.equal(await fileName.textContent(), app + '/Breeze.elm', 'The ⋯ button does not open the file');
  await page.keyboard.press('Escape');
  await menu.waitFor({ state: 'detached' });
  await page.getByRole('button', { name: 'Command palette', exact: true }).click();
  await palette.waitFor();
  assert.equal(await paletteInput.inputValue(), '>');
  await paletteInput.press('Escape');
  await palette.waitFor({ state: 'detached' });
  await page.getByRole('button', { name: 'More actions', exact: true }).click();
  await menu.getByRole('menuitem', { name: 'Command palette…', exact: true }).click();
  await palette.waitFor();
  await waitFocus('palette-input');
  await paletteInput.press('Escape');
  await palette.waitFor({ state: 'detached' });
  // Rename it back from the palette, so the module name matches its file again.
  await runCommand('Rename file…');
  await waitFocus('explorer-input');
  await page.keyboard.type('Winds');
  await page.keyboard.press('Enter');
  await row(app + '/Winds.elm').waitFor();

  // Ctrl/Cmd+Shift+P → Compile runs the compile; recent commands come first next time.
  await runCommand('Compile');
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await openPalette('ControlOrMeta+Shift+P');
  const first = palette.getByRole('option').first();
  assert.equal(await first.getAttribute('aria-label'), 'Compile', 'A recent command comes first');
  assert.equal(await first.locator('.palette-recent').textContent(), 'recently used');
  assert.match(await first.locator('kbd').textContent() ?? '', /^(⌘↩|Ctrl\+Enter)$/);
  await paletteInput.press('Escape');
  // Ctrl/Cmd+Enter compiles from the editor too, without inserting a line.
  const source = page.getByRole('textbox', { name: 'Source editor', exact: true });
  await source.press('ControlOrMeta+End');
  await page.keyboard.insertText(' ');
  await page.getByText('Source changed · rerun', { exact: true }).waitFor();
  const text = await page.locator('#source').evaluate(editor => (editor as CodeEditor).value);
  await page.keyboard.press('ControlOrMeta+Enter');
  await page.getByText('Source changed · rerun', { exact: true }).waitFor({ state: 'hidden' });
  assert.equal(await page.locator('#source').evaluate(editor => (editor as CodeEditor).value), text, 'The shortcut does not edit the source');

  // A one-file language shows New file disabled with its reason, in the header and in the palette.
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('moonbit');
  await page.waitForFunction(() => document.querySelector('.explorer-meta')?.textContent?.startsWith('MoonBit'));
  const newFile = page.getByRole('region', { name: 'Project explorer', exact: true }).getByRole('button', { name: 'New file', exact: true });
  assert.equal(await newFile.isDisabled(), true);
  assert.match(await newFile.getAttribute('title') ?? '', /morphir-ukvn\.5\.22\.14/);
  await openPalette('ControlOrMeta+Shift+P');
  await paletteInput.fill('>new file');
  await page.waitForFunction(() => document.querySelector('#palette-list [role="option"]')?.getAttribute('aria-label') === 'New file…');
  const disabled = palette.getByRole('option', { name: 'New file…', exact: true });
  assert.equal(await disabled.getAttribute('aria-disabled'), 'true');
  assert.match(await disabled.getAttribute('aria-description') ?? '', /morphir-ukvn\.5\.22\.14/);
  await paletteInput.press('Enter');
  assert.equal(await palette.isVisible(), true, 'A disabled command does not run');
  await paletteInput.press('Escape');

  // Leave a clean Elm project for later workflows.
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('elm');
  await runCommand('Reset project…');
  await page.getByRole('button', { name: 'Confirm reset', exact: true }).click();
  await row('src/Workbench/Main.elm').waitFor();
  console.log(JSON.stringify({ explorerTree: true, treeKeys: true, contextMenu: true, keyboardMenu: true, inlineNewFile: true, inlineRename: true, f2Rename: true, inlineDelete: true, exposure: true, quickOpen: true, commandPalette: true, compileShortcut: true, oneFileReason: true, focusRestored: true }));
}
