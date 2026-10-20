import assert from 'node:assert/strict';
import type { Browser, Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import { gettingStarted, createWorkspace, runCommand } from './workbench-steps.ts';

const key = 'morphir-workbench.settings.v1';

/** The root element's `data-theme`, or `system` when it has none. */
function dataTheme(page: Page): Promise<string> {
  return page.evaluate(() => document.documentElement.dataset.theme ?? 'system');
}

/** The id of the focused element. */
function focused(page: Page): Promise<string | undefined> {
  return page.evaluate(() => document.activeElement?.id);
}

/** The computed background color of the page. */
function background(page: Page): Promise<string> {
  return page.evaluate(() => getComputedStyle(document.body).backgroundColor);
}

/** True when no element is wider than the window, so the page never scrolls sideways. */
function fits(page: Page): Promise<boolean> {
  return page.evaluate(() => document.documentElement.scrollWidth <= innerWidth);
}

/** Waits for the settings page and its focused heading. */
async function settingsShown(page: Page): Promise<void> {
  await page.getByRole('heading', { name: 'Settings', level: 1, exact: true }).waitFor();
  await page.waitForFunction(() => document.activeElement?.id === 'settings-heading');
}

/** Waits until the root element's `data-theme` is `theme` (`system` for none) and the toggle names the choice. */
async function themeIs(page: Page, theme: string): Promise<void> {
  await page.waitForFunction(theme => (document.documentElement.dataset.theme ?? 'system') === theme &&
    document.getElementById('theme-toggle')?.getAttribute('aria-label')?.toLowerCase() === 'theme: ' + theme, theme);
}

/**
 * Settings and the theme: the rail gear and the palette open the settings page, Escape, Close settings and the gear
 * return to the same screen and focus, navigation leaves it, and System, Light and Dark apply from the radio group,
 * the rail toggle and the palette, follow the system live and survive a reload without a light first paint.
 */
export async function settingsWorkflow(browser: Browser, url: string): Promise<void> {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, colorScheme: 'light' });
  const page = await context.newPage(), errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(url);
    await gettingStarted(page);
    const gear = page.getByRole('button', { name: 'Settings', exact: true });
    const toggle = page.locator('#theme-toggle');
    const start = page.getByRole('heading', { name: 'Start with an idea.', exact: true });
    assert.equal(await gear.getAttribute('aria-current'), null);
    assert.equal(await dataTheme(page), 'system');
    assert.equal(await toggle.getAttribute('aria-label'), 'Theme: System');
    assert.equal((await toggle.textContent())!.trim(), '', 'The theme toggle shows an icon, not text');
    const light = await background(page);

    // The gear opens settings over getting started; Escape returns there with the focus on the gear.
    await gear.focus();
    await page.keyboard.press('Enter');
    await settingsShown(page);
    assert.equal(await gear.getAttribute('aria-current'), 'page');
    assert.equal(await gear.getAttribute('aria-pressed'), 'true');
    assert.ok(await start.isHidden(), 'Getting started is hidden behind settings');
    await page.keyboard.press('Escape');
    await start.waitFor();
    assert.equal(await focused(page), 'rail-settings', 'Escape returns the focus to the gear');
    assert.equal(await gear.getAttribute('aria-current'), null);

    // The palette opens settings; Close settings returns to getting started's heading.
    await runCommand(page, 'Open settings');
    await settingsShown(page);
    await page.getByRole('button', { name: 'Close settings', exact: true }).click();
    await start.waitFor();
    await page.waitForFunction(() => document.activeElement?.id === 'start-heading');

    // The radio group, the rail toggle and the palette set the same theme and agree.
    await gear.click();
    await settingsShown(page);
    const radio = (name: string) => page.getByRole('radio', { name, exact: true });
    assert.ok(await radio('System (currently light)').isChecked());
    await radio('Dark').check();
    await themeIs(page, 'dark');
    assert.equal(await toggle.getAttribute('aria-label'), 'Theme: Dark');
    assert.equal(await page.evaluate(key => localStorage.getItem(key), key), '{"theme":"dark"}');
    assert.notEqual(await background(page), light, 'Dark changes the page background');
    await toggle.click();
    await themeIs(page, 'system');
    assert.ok(await radio('System (currently light)').isChecked(), 'The toggle moves from Dark to System');
    assert.equal(await background(page), light);
    await toggle.click();
    await themeIs(page, 'light');
    assert.ok(await radio('Light').isChecked());
    await runCommand(page, 'Theme: Dark');
    await themeIs(page, 'dark');
    assert.ok(await radio('Dark').isChecked(), 'A palette theme keeps settings open and checks its choice');
    await runCommand(page, 'Theme: Use system setting');
    await themeIs(page, 'system');

    // System follows the system appearance while the page is open.
    await page.emulateMedia({ colorScheme: 'dark' });
    await radio('System (currently dark)').waitFor();
    assert.notEqual(await background(page), light, 'System follows a dark system');
    await page.emulateMedia({ colorScheme: 'light' });
    await radio('System (currently light)').waitFor();
    assert.equal(await background(page), light);

    // Keyboard only: the arrow keys move through the theme choices.
    await radio('System (currently light)').focus();
    await page.keyboard.press('ArrowDown');
    await themeIs(page, 'light');
    await page.keyboard.press('ArrowDown');
    await themeIs(page, 'dark');
    assert.equal(await focused(page), 'theme-dark');

    // A reload in Dark paints dark before the application script runs.
    await page.route('**/bootstrap.js', route => route.abort());
    await page.reload();
    assert.equal(await dataTheme(page), 'dark', 'The head script applies the saved theme');
    assert.notEqual(await background(page), light, 'The first paint is dark');
    await page.unroute('**/bootstrap.js');
    await page.reload();
    await gettingStarted(page);
    assert.equal(await toggle.getAttribute('aria-label'), 'Theme: Dark');
    await gear.click();
    assert.ok(await radio('Dark').isChecked(), 'The saved theme shows after a reload');
    await page.getByRole('button', { name: 'Close settings', exact: true }).click();

    // In a workspace, settings keeps the document, its text and the layout, and navigation leaves it.
    await createWorkspace(page, { name: 'Settings check' });
    const editor = page.locator('#source');
    const text = () => editor.evaluate(editor => (editor as CodeEditor).value);
    await editor.evaluate(editor => (editor as unknown as { view: { focus(): void } }).view.focus());
    await page.keyboard.press('ControlOrMeta+End');
    await page.keyboard.type('\n; kept across settings');
    const before = await text();
    assert.ok(before.endsWith('; kept across settings'), 'The edit reached the editor');
    await gear.click();
    await settingsShown(page);
    assert.ok(await page.locator('.workspace-area').isHidden(), 'The workspace is hidden, not closed');
    await gear.click();
    await page.locator('.workspace-area').waitFor();
    assert.equal(await focused(page), 'rail-settings', 'The gear closes settings and keeps the focus');
    assert.equal(await text(), before, 'The source text is kept');
    // Escape closes settings wherever the focus is, after a header menu has closed first.
    await gear.click();
    await settingsShown(page);
    await page.locator('#workspace-picker').click();
    await page.getByRole('menu', { name: 'Workspaces', exact: true }).waitFor();
    await page.keyboard.press('Escape');
    await page.getByRole('menu', { name: 'Workspaces', exact: true }).waitFor({ state: 'detached' });
    assert.ok(await page.locator('#settings').isVisible(), 'The first Escape closes only the menu');
    await page.keyboard.press('Escape');
    await page.locator('.workspace-area').waitFor();
    assert.equal(await focused(page), 'rail-settings', 'Escape returns to the workspace with the focus on the gear that opened settings');
    await gear.click();
    await settingsShown(page);
    await page.getByRole('button', { name: 'Getting started', exact: true }).click();
    await start.waitFor();
    assert.equal(await page.locator('#settings').count(), 0, 'Getting started leaves settings');

    // Narrow windows: the gear and the toggle stay reachable and settings never scrolls sideways.
    for (const width of [768, 390]) {
      await page.setViewportSize({ width, height: 844 });
      for (const control of [gear, toggle]) {
        const box = (await control.boundingBox())!;
        assert.ok(box.x >= 0 && box.x + box.width <= width && box.y + box.height <= 844, `The rail control fits ${width}px`);
      }
      await gear.click();
      await settingsShown(page);
      assert.ok(await fits(page), `Settings fits ${width}px`);
      await page.keyboard.press('Escape');
      await start.waitFor();
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    await runCommand(page, 'Theme: Use system setting');
    assert.deepEqual(errors, []);
    console.log('Settings workflow passed: gear and palette open settings, Escape, Close settings and the gear return focus, navigation leaves it, radio group, rail toggle and palette themes agree, System follows the system live, arrow keys, dark first paint after reload, workspace state kept, and narrow windows.');
  } finally { await context.close(); }
}

/**
 * The settings smoke for a host page that the test does not own, such as the packaged desktop app over CDP: the gear,
 * Escape, each theme from the radio group, the toggle and the palette, and the System label against the appearance
 * that the host's page reports. Leaves the theme on System. Returns that appearance.
 */
export async function settingsSmoke(page: Page): Promise<'light' | 'dark'> {
  await gettingStarted(page);
  const gear = page.getByRole('button', { name: 'Settings', exact: true });
  const toggle = page.locator('#theme-toggle');
  const radio = (name: string) => page.getByRole('radio', { name, exact: true });
  await runCommand(page, 'Theme: Use system setting');
  const system = await page.evaluate(() => matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  await gear.click();
  await settingsShown(page);
  assert.equal(await gear.getAttribute('aria-current'), 'page');
  assert.ok(await radio(`System (currently ${system})`).isChecked(), 'System names the host appearance');
  const systemBackground = await background(page);
  await radio('Dark').check();
  await themeIs(page, 'dark');
  await radio('Light').check();
  await themeIs(page, 'light');
  const lightBackground = await background(page);
  await toggle.click();
  await themeIs(page, 'dark');
  assert.equal(await toggle.getAttribute('aria-label'), 'Theme: Dark');
  assert.notEqual(await background(page), lightBackground, 'Light and Dark differ');
  await runCommand(page, 'Theme: Use system setting');
  await themeIs(page, 'system');
  assert.equal(await background(page), systemBackground);
  await page.getByRole('button', { name: 'Close settings', exact: true }).click();
  await page.getByRole('heading', { name: 'Start with an idea.', exact: true }).waitFor();
  return system;
}
