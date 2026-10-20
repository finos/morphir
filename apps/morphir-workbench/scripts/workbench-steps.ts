import type { Locator, Page } from 'playwright';

/**
 * Opens an example or sample from the command palette, as a person without the shortcut would: the top-bar button,
 * then "Open sample: <label>". Like the sidebar buttons it replaces, it waits until the sample can open (no execution is
 * running) before it chooses it.
 */
export async function openSample(page: Page, label: string): Promise<void> {
  const name = 'Open sample: ' + label;
  await page.getByRole('button', { name: 'Command palette', exact: true }).click();
  const palette = page.getByRole('dialog', { name: 'Command palette', exact: true });
  const input = palette.getByRole('combobox');
  await input.fill('>' + name);
  await page.waitForFunction(name => {
    const option = document.querySelector('#palette-list [role="option"][aria-selected="true"]');
    return option?.getAttribute('aria-label') === name && option.getAttribute('aria-disabled') !== 'true';
  }, name);
  await input.press('Enter');
  await palette.waitFor({ state: 'detached' });
}

/**
 * Waits until getting started accepts its entries: the page has its catalog and runs no work, so the examples are
 * enabled.
 */
export async function gettingStarted(page: Page): Promise<void> {
  await page.getByRole('heading', { name: 'Start with an idea.', exact: true }).waitFor();
  await page.waitForFunction(() => {
    const examples = [...document.querySelectorAll<HTMLButtonElement>('.example-link')];
    return examples.length > 0 && examples.every(example => !example.disabled);
  });
}

/**
 * Creates and opens a workspace from getting started, as a person would: Create a workspace, an optional name, the
 * starting point, then Create workspace. A source project workspace opens its source document.
 */
export async function createWorkspace(page: Page, options: { preset?: 'Empty workspace' | 'Source project' | 'Sandbox'; name?: string } = {}): Promise<void> {
  const preset = options.preset ?? 'Source project';
  await gettingStarted(page);
  const create = page.getByRole('button', { name: 'Create a workspace', exact: true });
  if (await create.getAttribute('aria-expanded') !== 'true') await create.click();
  if (options.name) await page.getByRole('textbox', { name: 'Name', exact: true }).fill(options.name);
  await page.getByRole('radio', { name: new RegExp('^' + preset) }).check();
  await page.getByRole('button', { name: 'Create workspace', exact: true }).click();
  await page.locator(preset === 'Empty workspace' ? '.document-area' : '.document-tabs').waitFor();
}

/**
 * Opens the page in local mode and creates a source project workspace, ready to compile: the start of every workflow
 * that edits and compiles source.
 */
export async function openLocal(page: Page, url: string, options: { name?: string } = {}): Promise<void> {
  await page.goto(url);
  await createWorkspace(page, { name: options.name });
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
}

/**
 * Explores a model file from getting started: Explore a model, Import a model file…, then the file in the picker. The
 * model opens in a new workspace named after the file.
 */
export async function exploreModel(page: Page, file: string | { name: string; mimeType: string; buffer: Buffer }): Promise<void> {
  await gettingStarted(page);
  const explore = page.getByRole('button', { name: 'Explore a model', exact: true });
  if (await explore.getAttribute('aria-expanded') !== 'true') await explore.click();
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import a model file…', exact: true }).click();
  await (await chooser).setFiles(file);
  const name = typeof file === 'string' ? file.split(/[\\/]/).at(-1)! : file.name;
  await page.getByRole('button', { name: new RegExp('^Workspace: ' + escape(name) + '( \\d+)?$') }).waitFor();
  await page.locator('.model-document').waitFor();
}

/** Opens an example from Explore an example on getting started; it opens in a new source workspace. */
export async function openExample(page: Page, label: string): Promise<void> {
  await gettingStarted(page);
  await page.getByRole('button', { name: label, exact: true }).click();
  await page.locator('#source').waitFor();
}

/** Opens or closes the left sidebar with the Explorer button of the left rail. */
export async function setExplorer(page: Page, open: boolean): Promise<void> {
  const sidebar = page.locator('#sidebar-primary');
  if (await sidebar.isVisible() !== open) await page.getByRole('button', { name: 'Explorer', exact: true }).click();
  await sidebar.waitFor({ state: open ? 'visible' : 'hidden' });
}

/** Opens or closes the right sidebar with its header button. */
export async function setRightSidebar(page: Page, open: boolean): Promise<void> {
  const sidebar = page.locator('#sidebar-secondary');
  if (await sidebar.isVisible() !== open) await page.getByRole('button', { name: 'Toggle right sidebar', exact: true }).click();
  await sidebar.waitFor({ state: open ? 'visible' : 'hidden' });
}

/** Shows the Generated section: the right sidebar opens and the section expands. */
export async function showGeneratedFiles(page: Page): Promise<void> {
  await setRightSidebar(page, true);
  const toggle = page.locator('#section-generated');
  if (await toggle.getAttribute('aria-expanded') !== 'true') await toggle.click();
  await page.locator('#section-generated-body').waitFor();
}

/** Selects the source document in compile mode, not as a worksheet. */
export async function showCompile(page: Page): Promise<void> {
  await showSource(page);
  const compile = page.getByRole('button', { name: 'Compile & inspect', exact: true });
  if (await compile.getAttribute('aria-pressed') !== 'true') await compile.click();
  await page.locator('.mode-switch button[aria-pressed="true"]').filter({ hasText: 'Compile & inspect' }).waitFor();
  await buildAction(page, 'Compile').waitFor();
}

/** Shows the source document of the active workspace: the editor with its output. */
export async function showSource(page: Page): Promise<void> {
  await page.locator('[data-document="source"]').click();
  await page.locator('#source').waitFor();
}

/** Shows the model document of the active workspace: declarations, details and evaluation. */
export async function showModel(page: Page): Promise<void> {
  await page.locator('[data-document="model"]').click();
  await page.locator('.model-document').waitFor();
}

/** Opens a saved workspace from Recent workspaces on getting started. */
export async function reopenWorkspace(page: Page, name: string): Promise<void> {
  await page.getByRole('button', { name: 'Open ' + name, exact: true }).click();
  await page.locator('.document-tabs').waitFor();
}

/**
 * Runs a build action of the source document: the primary button when it is that action, else the entry of the
 * More build actions menu.
 */
export async function build(page: Page, name: string): Promise<void> {
  const direct = buildAction(page, name);
  if (await direct.count()) { await direct.click(); return; }
  await (await buildMenuItem(page, name)).click();
}

/**
 * The primary build button when its action is `name`. A menu entry has no button of its own; use `buildMenuItem`.
 */
export function buildAction(page: Page, name: string): Locator {
  return page.locator('.build-actions > button.primary').filter({ hasText: new RegExp('^\\W*' + escape(name) + '$') });
}

/**
 * Opens the More build actions menu and returns its entry `name`. `closeBuildMenu` closes the menu without a choice.
 */
export async function buildMenuItem(page: Page, name: string): Promise<Locator> {
  const button = page.getByRole('button', { name: 'More build actions', exact: true });
  const menu = page.getByRole('menu', { name: 'Build actions', exact: true });
  if (await button.getAttribute('aria-expanded') !== 'true') await button.click();
  await menu.waitFor();
  return menu.getByRole('menuitem', { name: new RegExp('^' + escape(name) + '(?!\\S)') });
}

/** Closes the More build actions menu as a pointer would: a click outside it. */
export async function closeBuildMenu(page: Page): Promise<void> {
  const menu = page.getByRole('menu', { name: 'Build actions', exact: true });
  if (!await menu.count()) return;
  // The open menu has the focus, so Escape closes it and returns the focus to its button.
  await page.keyboard.press('Escape');
  await menu.waitFor({ state: 'detached' });
  await page.waitForFunction(() => document.activeElement?.id === 'build-menu-button');
}

/** The build menu entries' names, as the open menu shows them; the menu closes again. */
export async function buildMenuEntries(page: Page): Promise<string[]> {
  await buildMenuItem(page, '');
  const names = await page.getByRole('menu', { name: 'Build actions', exact: true }).locator('[role="menuitem"] > span:first-child').allTextContents();
  await closeBuildMenu(page);
  return names;
}

function escape(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
