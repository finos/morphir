import assert from 'node:assert/strict';
import type { Browser, Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import { fileURLToPath } from 'node:url';
import { gettingStarted, createWorkspace, reopenWorkspace, exploreModel, showSource, setExplorer, setRightSidebar, build, runCommand, setTarget, currentTarget } from './workbench-steps.ts';

const entries = ['Try an idea', 'Open a workspace', 'Create a workspace', 'Explore a model'];

/** The source editor's text. */
function source(page: Page): Promise<string> {
  return page.locator('#source').evaluate(editor => (editor as CodeEditor).value);
}

/** True when no element is wider than the window, so the page never scrolls sideways. */
function fits(page: Page): Promise<boolean> {
  return page.evaluate(() => document.documentElement.scrollWidth <= innerWidth);
}

/** The focused element is part of the page, not the document body that a removed control leaves behind. */
function focusKept(page: Page): Promise<boolean> {
  return page.evaluate(() => document.activeElement !== null && document.activeElement !== document.body);
}

/** The bounding boxes of the documents area and both sidebars, rounded. */
function layoutOf(page: Page) {
  return page.evaluate(() => ['.document-area', '#sidebar-primary', '#sidebar-secondary'].map(selector => {
    const box = document.querySelector(selector)!.getBoundingClientRect();
    return [box.x, box.y, box.width, box.height].map(Math.round);
  }));
}

/**
 * Workspaces from getting started: the four ways in, drafts that survive a reload, names, a cancelled model,
 * switching, the sidebars and their sections, the generation notification and narrow windows.
 */
export async function workspaceWorkflow(browser: Browser, url: string): Promise<void> {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage(), errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(url);
    await gettingStarted(page);
    const group = page.getByRole('group', { name: 'Get started', exact: true });
    assert.deepEqual(await group.locator(':scope > .start-action').evaluateAll(buttons => buttons.map(button => button.getAttribute('aria-label'))), entries);
    for (const [entry, choices] of [
      ['Try an idea', ['Capture intent', 'Sketch a conceptual model', 'Scratch worksheet']],
      ['Open a workspace', ['Import a source folder…']],
      ['Explore a model', ['Import a model file…', 'Import a YAML model tree…']],
    ] as const) {
      const button = page.getByRole('button', { name: entry, exact: true });
      assert.equal(await button.getAttribute('aria-expanded'), 'false');
      await button.click();
      await page.waitForFunction(entry => document.querySelector(`[aria-label="${entry}"]`)?.getAttribute('aria-expanded') === 'true', entry);
      for (const choice of choices) await page.getByRole('button', { name: choice, exact: true }).waitFor();
      await button.click();
      await page.getByRole('button', { name: choices[0], exact: true }).waitFor({ state: 'detached' });
    }
    await page.getByRole('button', { name: 'Create a workspace', exact: true }).click();
    for (const preset of ['Empty workspace', 'Source project', 'Sandbox']) await page.getByRole('radio', { name: new RegExp('^' + preset) }).waitFor();
    assert.equal(await page.evaluate(() => document.activeElement?.id), 'create-name', 'Create a workspace focuses its name');
    await page.getByRole('button', { name: 'Create a workspace', exact: true }).click();
    assert.equal(await page.getByRole('button', { name: 'Workspace: Workspaces', exact: true }).count(), 1, 'Getting started has no active workspace');

    // Try an idea: a sandbox holds the intent, and the draft survives a reload.
    await page.getByRole('button', { name: 'Try an idea', exact: true }).click();
    await page.getByRole('button', { name: 'Capture intent', exact: true }).click();
    await page.getByRole('button', { name: 'Workspace: Sandbox', exact: true }).waitFor();
    const intent = page.locator('#intent-text');
    await intent.waitFor();
    assert.equal(await page.evaluate(() => document.activeElement?.id), 'intent-text', 'Capture intent focuses the draft');
    await page.locator('#section-ideas').waitFor();
    assert.equal(await page.locator('#section-files').count(), 0, 'A sandbox has no project files');
    assert.equal(await page.locator('[data-document="intent"]').getAttribute('aria-pressed'), 'true');
    await intent.fill('Orders are priced before fulfilment.');
    await page.getByText('Saved in this browser as you type.', { exact: false }).waitFor();
    await page.waitForFunction(() => Object.keys(localStorage).some(key => /^morphir-workbench\.workspace\.w\d+\.intent\.v1$/.test(key) && localStorage.getItem(key) === 'Orders are priced before fulfilment.'));
    await page.reload();
    await gettingStarted(page);
    await reopenWorkspace(page, 'Sandbox');
    assert.equal(await page.locator('#intent-text').inputValue(), 'Orders are priced before fulfilment.', 'The intent draft survives a reload');

    // Create a workspace: a named one, a default name for a blank one and an error for a long one.
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await createWorkspace(page, { name: '  Orders  ' });
    await page.getByRole('button', { name: 'Workspace: Orders', exact: true }).waitFor();
    await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await createWorkspace(page, { name: '   ', preset: 'Source project' });
    await page.getByRole('button', { name: 'Workspace: Source project', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await gettingStarted(page);
    await page.getByRole('button', { name: 'Create a workspace', exact: true }).click();
    const name = page.getByRole('textbox', { name: 'Name', exact: true });
    await name.fill('x'.repeat(81));
    await page.getByRole('button', { name: 'Create workspace', exact: true }).click();
    await page.getByText('Use at most 80 characters', { exact: true }).waitFor();
    assert.equal(await name.getAttribute('aria-invalid'), 'true');
    assert.equal(await page.evaluate(() => document.activeElement?.id), 'create-name', 'The name keeps the focus to correct it');
    assert.equal(await page.locator('.document-tabs').count(), 0, 'An invalid name creates no workspace');
    await name.fill('Valid');
    await page.getByText('Use at most 80 characters', { exact: true }).waitFor({ state: 'hidden' });
    assert.equal(await name.getAttribute('aria-invalid'), 'false', 'Editing the name clears its error');
    await page.getByRole('button', { name: 'Create a workspace', exact: true }).click();

    // Explore a model: a cancelled or failed picker removes the provisional workspace and says why.
    const recents = () => page.locator('.recent-open').evaluateAll(buttons => buttons.map(button => button.getAttribute('aria-label')));
    const before = await recents();
    await page.getByRole('button', { name: 'Explore a model', exact: true }).click();
    let chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import a model file…', exact: true }).click();
    await (await chooser).element().evaluate(input => input.dispatchEvent(new Event('cancel')));
    const message = page.locator('.start-message');
    await message.filter({ hasText: /cancel/i }).waitFor();
    assert.equal(await page.locator('.document-tabs').count(), 0, 'A cancelled model stays on getting started');
    assert.deepEqual(await recents(), before, 'A cancelled model keeps the earlier workspaces');
    await page.getByRole('button', { name: 'Workspace: Workspaces', exact: true }).click();
    const menu = page.getByRole('menu', { name: 'Workspaces', exact: true });
    await menu.waitFor();
    assert.deepEqual((await menu.locator('.picker-name').allTextContents()).sort(), ['Orders', 'Sandbox', 'Source project'], 'The picker lists no provisional workspace');
    await menu.getByRole('menuitem', { name: 'Getting started', exact: true }).focus();
    await page.keyboard.press('Escape');
    await page.getByRole('menu', { name: 'Workspaces', exact: true }).waitFor({ state: 'detached' });
    if (await page.getByRole('button', { name: 'Import a model file…', exact: true }).count() === 0) await page.getByRole('button', { name: 'Explore a model', exact: true }).click();
    chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import a model file…', exact: true }).click();
    await (await chooser).setFiles({ name: 'broken.json', mimeType: 'application/json', buffer: Buffer.from('invalid json') });
    await message.filter({ hasText: 'The model is not valid' }).waitFor();
    assert.deepEqual(await recents(), before, 'A failed model keeps the earlier workspaces');
    // A cancelled source folder and a wait the person stops leave nothing behind either.
    await page.getByRole('button', { name: 'Open a workspace', exact: true }).click();
    chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import a source folder…', exact: true }).click();
    await (await chooser).element().evaluate(input => input.dispatchEvent(new Event('cancel')));
    await message.filter({ hasText: 'Folder selection cancelled' }).waitFor();
    assert.deepEqual(await recents(), before, 'A cancelled folder keeps the earlier workspaces');
    await page.getByRole('button', { name: 'Explore a model', exact: true }).click();
    chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import a model file…', exact: true }).click();
    await chooser;
    // The rail has no Explorer while a workspace waits.
    await page.getByRole('button', { name: 'Explorer', exact: true }).waitFor({ state: 'detached' });
    await page.getByRole('button', { name: 'Stop waiting', exact: true }).click();
    await message.filter({ hasText: 'Stopped waiting; nothing was opened' }).waitFor();
    assert.deepEqual(await recents(), before, 'A stopped wait keeps the earlier workspaces');
    assert.equal(await page.getByRole('button', { name: 'Workspace: Workspaces', exact: true }).count(), 1, 'A stopped wait opens nothing');

    // Switching with the picker keeps each workspace's source edits.
    await reopenWorkspace(page, 'Orders');
    await showSource(page);
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(+ 1 2) ; orders');
    const pick = async (workspace: string) => {
      await page.locator('#workspace-picker').click();
      await page.getByRole('menuitemradio', { name: new RegExp('^' + workspace + ' ') }).click();
      await page.getByRole('button', { name: 'Workspace: ' + workspace, exact: true }).waitFor();
    };
    await pick('Source project');
    await showSource(page);
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(+ 3 4) ; source');
    await pick('Orders');
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value === '(+ 1 2) ; orders');
    await pick('Source project');
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value === '(+ 3 4) ; source');
    await pick('Sandbox');
    assert.equal(await page.locator('#intent-text').inputValue(), 'Orders are priced before fulfilment.');
    await pick('Orders');
    assert.equal(await source(page), '(+ 1 2) ; orders');

    // The workspace sidebar: a tile per open workspace, and the primary sidebar's header names the open workspace.
    const openWorkspaces = page.getByRole('group', { name: 'Open workspaces', exact: true });
    const card = (workspace: string) => openWorkspaces.getByRole('button', { name: new RegExp('^' + workspace + ', ') });
    const title = page.locator('#sidebar-primary .sidebar-title');
    assert.equal(await title.textContent(), 'Orders', 'The primary sidebar names the open workspace');
    assert.equal(await card('Orders').getAttribute('aria-current'), 'page');
    assert.equal((await card('Orders').textContent())!.startsWith('OR'), true, 'A collapsed tile shows initials');
    assert.equal(await card('Orders').locator('.workspace-card-name').isVisible(), false, 'A collapsed tile hides the name');
    await card('Sandbox').click();
    await page.getByRole('button', { name: 'Workspace: Sandbox', exact: true }).waitFor();
    assert.equal(await page.locator('#intent-text').inputValue(), 'Orders are priced before fulfilment.', 'A tile switches to its workspace');
    assert.equal(await card('Orders').getAttribute('aria-current'), null);
    // Expanded, each card shows its name and kind; the choice is saved for the whole Workbench.
    const expand = page.getByRole('button', { name: 'Expand workspace sidebar', exact: true });
    await expand.click();
    const collapse = page.getByRole('button', { name: 'Collapse workspace sidebar', exact: true });
    assert.equal(await collapse.getAttribute('aria-expanded'), 'true');
    await page.waitForFunction(() => document.activeElement?.id === 'workspace-sidebar-toggle');
    assert.equal(await card('Orders').locator('.workspace-card-name').textContent(), 'Orders');
    assert.match((await card('Orders').locator('.workspace-card-detail').textContent())!, /^Source project/);
    assert.equal(JSON.parse((await page.evaluate(() => localStorage.getItem('morphir-workbench.settings.v1')))!).workspaceSidebar, 'expanded');
    // Keyboard: arrows move between the cards and Enter switches.
    const labels = await openWorkspaces.locator('.workspace-card-open').evaluateAll(cards => cards.map(card => card.getAttribute('aria-label')));
    await openWorkspaces.locator('.workspace-card-open').first().focus();
    await page.keyboard.press('ArrowDown');
    assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('aria-label')), labels[1], 'ArrowDown moves to the next card');
    await page.keyboard.press('End');
    assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('aria-label')), labels.at(-1), 'End moves to the last card');
    await card('Orders').focus();
    await page.keyboard.press('Enter');
    await page.getByRole('button', { name: 'Workspace: Orders', exact: true }).waitFor();
    assert.equal(await title.textContent(), 'Orders');
    // At 1050 px and narrower the expanded sidebar shows tiles, and the expand button hides.
    await page.setViewportSize({ width: 1000, height: 900 });
    assert.equal(await card('Orders').locator('.workspace-card-name').isVisible(), false, 'Narrow windows show tiles');
    assert.equal(await collapse.isVisible(), false);
    await page.setViewportSize({ width: 1440, height: 1000 });
    await runCommand(page, 'Toggle workspace sidebar');
    await expand.waitFor();
    assert.equal(await page.evaluate(() => localStorage.getItem('morphir-workbench.settings.v1')), '{"theme":"system"}');

    // The rail's Explorer and Ctrl+B close and reopen the left sidebar; the focus stays on the page.
    const left = page.locator('#sidebar-primary'), right = page.locator('#sidebar-secondary');
    const explorer = page.getByRole('button', { name: 'Explorer', exact: true });
    assert.equal(await explorer.getAttribute('aria-pressed'), 'true');
    await explorer.click();
    await left.waitFor({ state: 'hidden' });
    assert.equal(await explorer.getAttribute('aria-pressed'), 'false');
    await page.waitForFunction(() => document.activeElement?.id === 'rail-explorer');
    assert.ok(await focusKept(page), 'Closing the left sidebar keeps the focus on the rail');
    await explorer.click();
    await left.waitFor();
    await page.getByRole('textbox', { name: 'Filter files', exact: true }).click();
    await page.keyboard.press('ControlOrMeta+b');
    await left.waitFor({ state: 'hidden' });
    // Closing the sidebar that holds the focus moves it to the rail's Explorer.
    await page.waitForFunction(() => document.activeElement?.id === 'rail-explorer');
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).click();
    await page.keyboard.press('ControlOrMeta+b');
    await left.waitFor();
    assert.ok(await focusKept(page), 'Ctrl+B keeps the focus where it was');
    assert.equal(await right.isVisible(), false, 'The right sidebar starts closed');
    await setRightSidebar(page, true);
    assert.equal(await left.isVisible(), true, 'The right sidebar opens independently');
    await setExplorer(page, false);
    assert.equal(await right.isVisible(), true, 'The left sidebar closes independently');
    await setExplorer(page, true);
    await setRightSidebar(page, false);

    // Moving Files to the right sidebar and back keeps its filter and its open state.
    const filter = page.getByRole('textbox', { name: 'Filter files', exact: true });
    await filter.fill('main');
    await page.getByRole('button', { name: 'Move Files to the right sidebar', exact: true }).click();
    await right.locator('#section-files').waitFor();
    assert.equal(await left.locator('#section-files').count(), 0, 'A view is in one sidebar at a time');
    // The moved section keeps the focus.
    await page.waitForFunction(() => document.activeElement?.id === 'section-files');
    assert.equal(await right.getByRole('textbox', { name: 'Filter files', exact: true }).inputValue(), 'main');
    await page.locator('#section-files').click();
    await page.locator('#section-files[aria-expanded="false"]').waitFor();
    await page.getByRole('button', { name: 'Move Files to the left sidebar', exact: true }).click();
    await left.locator('#section-files').waitFor();
    assert.equal(await page.locator('#section-files').getAttribute('aria-expanded'), 'false', 'A move keeps the section closed');
    await page.locator('#section-files').click();
    await page.locator('#section-files[aria-expanded="true"]').waitFor();
    assert.equal(await left.getByRole('textbox', { name: 'Filter files', exact: true }).inputValue(), 'main', 'A move keeps the filter');
    await filter.fill('');
    await setRightSidebar(page, false);

    // Keyboard resizing through the splitter.
    const splitter = page.getByRole('separator', { name: 'Resize left sidebar', exact: true });
    const width = Number(await splitter.getAttribute('aria-valuenow'));
    await splitter.focus();
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(width => document.querySelector('[aria-label="Resize left sidebar"]')?.getAttribute('aria-valuenow') === String(width + 16), width);
    assert.equal(Math.round((await left.boundingBox())!.width), width + 16, 'The sidebar takes the new width');
    await page.keyboard.press('ArrowLeft');
    await page.waitForFunction(width => document.querySelector('[aria-label="Resize left sidebar"]')?.getAttribute('aria-valuenow') === String(width), width);
    await page.keyboard.press('Home');
    await page.waitForFunction(() => document.querySelector('[aria-label="Resize left sidebar"]')?.getAttribute('aria-valuenow') === '200');
    await page.keyboard.press('End');
    await page.waitForFunction(() => document.querySelector('[aria-label="Resize left sidebar"]')?.getAttribute('aria-valuenow') === '560');
    await page.keyboard.press('Home');
    await page.waitForFunction(() => document.querySelector('[aria-label="Resize left sidebar"]')?.getAttribute('aria-valuenow') === '200');
    for (let at = 200; at < width; at += 16) await page.keyboard.press('ArrowRight');
    await page.waitForFunction(width => document.querySelector('[aria-label="Resize left sidebar"]')?.getAttribute('aria-valuenow') === String(width), width);

    // Generation: a notification that takes no focus and changes no layout until the person asks.
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(define answer 42)');
    // The palette and Settings change the same target: the current project's.
    await setTarget(page, 'moonbit');
    await page.getByRole('button', { name: 'Command palette', exact: true }).click();
    const palette = page.getByRole('dialog', { name: 'Command palette', exact: true });
    await palette.getByRole('combobox').fill('>Set generation target…');
    await page.waitForFunction(() => document.querySelector('#palette-list [role="option"][aria-selected="true"]')?.getAttribute('aria-label') === 'Set generation target…');
    await palette.getByRole('combobox').press('Enter');
    await palette.getByRole('combobox').fill('Elm');
    await page.waitForFunction(() => document.querySelector('#palette-list [role="option"][aria-selected="true"]')?.getAttribute('aria-label')?.startsWith('Elm'));
    await palette.getByRole('combobox').press('Enter');
    await palette.waitFor({ state: 'detached' });
    assert.equal(await currentTarget(page), 'elm', 'Settings shows the target that the palette chose');
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).focus();
    const layout = await layoutOf(page);
    await build(page, 'Compile');
    const notice = page.getByRole('status').filter({ hasText: 'Generation complete' });
    await notice.waitFor();
    assert.match((await notice.textContent())!, /ready to inspect for target elm/);
    assert.equal(await right.isVisible(), false, 'Generation opens no sidebar');
    assert.deepEqual(await layoutOf(page), layout, 'Generation changes no layout');
    await page.getByRole('button', { name: 'Dismiss notification', exact: true }).click();
    await notice.waitFor({ state: 'detached' });
    assert.deepEqual(await layoutOf(page), layout, 'Dismiss changes no layout');
    await build(page, 'Compile');
    await notice.waitFor();
    await page.getByRole('button', { name: 'Show generated files', exact: true }).click();
    await notice.waitFor({ state: 'detached' });
    await right.waitFor();
    assert.equal(await page.locator('#section-generated').getAttribute('aria-expanded'), 'true');
    // Show generated files moves the focus to them.
    await page.waitForFunction(() => document.activeElement?.id === 'section-generated');
    const files = right.getByRole('navigation', { name: 'Generated files', exact: true });
    const generated = await files.locator('.artifact-file').evaluateAll(buttons => buttons.map(button => button.getAttribute('aria-label')!));
    assert.ok(generated.includes('elm.json'), 'Elm generation writes elm.json');
    await files.getByRole('button', { name: 'elm.json', exact: true }).click();
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.value.includes('"type"'));
    assert.equal(await page.locator('.artifact-breadcrumb').getAttribute('title'), 'elm.json', 'The editor area shows the selected file');
    assert.equal(await page.locator('.output-panel .tabs').getByRole('button', { name: 'Generated', exact: true }).getAttribute('class'), 'tab selected');
    await setRightSidebar(page, false);

    // A model-only workspace explores its model and has no project files.
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await exploreModel(page, fileURLToPath(new URL('../../../pkgs/morphir-ir/conformance/fixtures/v3-greeting.json', import.meta.url)));
    await page.getByRole('button', { name: 'Workspace: v3-greeting.json', exact: true }).waitFor();
    await page.locator('.model-tree .tree-item').first().waitFor();
    assert.equal(await page.locator('#section-files').count(), 0, 'A model-only workspace has no Files section');
    assert.equal(await page.locator('#section-generated').count(), 0, 'A model-only workspace has no Generated section');
    assert.equal(await page.locator('[data-document="source"]').count(), 0, 'A model-only workspace has no source document');
    assert.equal(await page.locator('[data-document="model"]').getAttribute('aria-pressed'), 'true');
    assert.equal(await page.getByRole('button', { name: 'Compile & inspect', exact: true }).count(), 0, 'The mode picker belongs to the source document');

    // Close: the picker, the command palette and Recent workspaces save a workspace and close it. It reopens from
    // browser storage, and once closed it can be removed.
    const closingDraft = () => page.evaluate(() => Object.keys(localStorage).some(key => /^morphir-workbench\.workspace\.w\d+\.intent\.v1$/.test(key) && localStorage.getItem(key) === 'Saved when it closes.'));
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await createWorkspace(page, { name: 'Closing', preset: 'Sandbox' });
    await page.getByRole('button', { name: 'Workspace: Closing', exact: true }).waitFor();
    await page.locator('[data-document="intent"]').click();
    await page.locator('#intent-text').fill('Saved when it closes.');
    await page.locator('#workspace-picker').click();
    await page.getByRole('menuitem', { name: 'Close workspace Closing', exact: true }).click();
    // Closing the active workspace opens the most recently used open workspace and moves the focus to the picker.
    await page.getByRole('button', { name: 'Workspace: v3-greeting.json', exact: true }).waitFor();
    await page.waitForFunction(() => document.activeElement?.id === 'workspace-picker');
    assert.ok(await closingDraft(), 'Closing saves the draft first');
    await page.locator('#workspace-picker').click();
    // A closed workspace stays saved and is no longer open: the picker shows its kind, not "open".
    await menu.getByRole('menuitemradio', { name: 'Closing Sandbox', exact: true }).waitFor();
    await page.keyboard.press('Escape');
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await reopenWorkspace(page, 'Closing');
    await page.locator('[data-document="intent"]').click();
    assert.equal(await page.locator('#intent-text').inputValue(), 'Saved when it closes.', 'A closed workspace reopens from browser storage');
    await runCommand(page, 'Close workspace');
    await page.getByRole('button', { name: 'Workspace: v3-greeting.json', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await gettingStarted(page);
    assert.equal(await page.getByRole('button', { name: 'Close Closing', exact: true }).count(), 0, 'A closed row has no Close');
    await reopenWorkspace(page, 'Closing');
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await gettingStarted(page);
    assert.equal(await page.getByRole('button', { name: 'Remove Closing from this browser', exact: true }).count(), 0, 'An open workspace closes before it is removed');
    await page.getByRole('button', { name: 'Close Closing', exact: true }).click();
    await message.filter({ hasText: 'Closed Closing' }).waitFor();
    await page.waitForFunction(() => document.activeElement?.getAttribute('aria-label') === 'Open Closing');
    await page.getByRole('button', { name: 'Remove Closing from this browser', exact: true }).click();
    await page.locator('#recent-remove-confirm').click();
    await message.filter({ hasText: 'Removed Closing from this browser' }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Open Closing', exact: true }).count(), 0, 'A removed workspace leaves Recent workspaces');
    assert.ok(!await closingDraft(), 'Removing deletes the saved draft');

    // Narrow windows: nothing overflows and the four entries stay reachable.
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    for (const width of [768, 390]) {
      await page.setViewportSize({ width, height: 844 });
      await gettingStarted(page);
      assert.ok(await fits(page), `Getting started fits ${width}px`);
      for (const entry of entries) {
        const button = page.getByRole('button', { name: entry, exact: true });
        await button.scrollIntoViewIfNeeded();
        const box = (await button.boundingBox())!;
        assert.ok(box.x >= 0 && box.x + box.width <= width + 1, `${entry} is inside a ${width}px window`);
        await button.click({ trial: true });
      }
      await reopenWorkspace(page, 'Orders');
      assert.ok(await fits(page), `A workspace fits ${width}px`);
      await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    assert.deepEqual(errors, []);
    console.log('Workspace workflow passed: getting started entries, intent draft across reload, names, cancelled and failed models, cancelled folder, stopped wait, switching, workspace sidebar tiles and cards, sidebars, Ctrl+B, moves, resizing, generation notification, model-only workspace, close, reopen and remove, and narrow windows.');
  } finally { await context.close(); }
}
