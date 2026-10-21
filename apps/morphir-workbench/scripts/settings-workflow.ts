import assert from 'node:assert/strict';
import type { Browser, Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import { gettingStarted, createWorkspace, runCommand, build, setTarget } from './workbench-steps.ts';

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

/** Asserts that the theme toggle sits at the right end of the header, after every other header control, and not in the rail. */
async function inHeader(page: Page): Promise<void> {
  const place = await page.evaluate(() => {
    const toggle = document.getElementById('theme-toggle'), end = toggle?.closest('.topbar-end');
    return {
      header: end !== null && end !== undefined,
      last: [...end?.querySelectorAll('a, button, select') ?? []].at(-1) === toggle,
      rail: document.querySelector('.rail #theme-toggle') !== null,
      railEnd: [...document.querySelectorAll('.rail-end > *')].map(element => element.id),
    };
  });
  assert.deepEqual(place, { header: true, last: true, rail: false, railEnd: ['workspace-sidebar-toggle', 'rail-settings'] },
    'The theme toggle is the last control of the header, and the rail end holds the workspace sidebar toggle and the gear');
}

/**
 * Settings and the theme: the rail gear and the palette open the settings page, Escape, Close settings and the gear
 * return to the same screen and focus, navigation leaves it, and System, Light and Dark apply from the radio group,
 * the header toggle and the palette, follow the system live and survive a reload without a light first paint.
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
    await inHeader(page);
    const light = await background(page);

    // Both connection routes precede the theme toggle in the keyboard order.
    await page.getByRole('link', { name: 'Connect', exact: true }).focus();
    await page.keyboard.press('Tab');
    assert.equal(await page.getByRole('link', { name: 'Model sources', exact: true }).evaluate(link => link === document.activeElement), true);
    await page.keyboard.press('Tab');
    assert.equal(await focused(page), 'theme-toggle', 'Tab moves from the connection pill to the theme toggle');
    await page.keyboard.press('Enter');
    await themeIs(page, 'light');
    await runCommand(page, 'Theme: Use system setting');
    await themeIs(page, 'system');

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

    // The radio group, the header toggle and the palette set the same theme and agree.
    await gear.click();
    await settingsShown(page);
    await inHeader(page);
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
    await inHeader(page);
    await gear.click();
    await settingsShown(page);
    assert.ok(await page.locator('.workspace-area').isHidden(), 'The workspace is hidden, not closed');
    await gear.click();
    await page.locator('.workspace-area').waitFor();
    assert.equal(await focused(page), 'rail-settings', 'The gear closes settings and keeps the focus');
    assert.equal(await text(), before, 'The source text is kept');

    // Source and output: side by side the source expands to the full width and restores; as tabs, the source, Morphir
    // IR and Generated are tabs on the document row. The editor keeps its text and the choice is saved.
    const outputPane = page.locator('.output-panel');
    await page.getByRole('button', { name: 'Expand source', exact: true }).click();
    await outputPane.waitFor({ state: 'hidden' });
    assert.equal(await page.getByRole('button', { name: 'Restore split view', exact: true }).getAttribute('aria-pressed'), 'true');
    await page.getByRole('button', { name: 'Restore split view', exact: true }).click();
    await outputPane.waitFor();
    await runCommand(page, 'Editor layout: Tabs');
    await outputPane.waitFor({ state: 'hidden' });
    assert.equal(await page.getByRole('button', { name: 'Expand source', exact: true }).isVisible(), false, 'Tabs need no expand button');
    await page.locator('.document-tab[data-output="ir"]').click();
    await page.locator('#output').waitFor();
    assert.equal(await page.locator('#source').isVisible(), false, 'The Morphir IR tab shows the output alone');
    await page.locator('.document-tab[data-output="ir"][aria-pressed="true"]').waitFor();
    // A compile opens the selected generated file in its own tab; a file tab closes, and then the source shows.
    await setTarget(page, 'scheme');
    await build(page, 'Compile');
    await page.getByRole('status').filter({ hasText: /Model ready|Compiled 1\/1 projects/ }).waitFor();
    const fileTab = page.locator('.document-tab[data-output-path]');
    assert.equal(await fileTab.count(), 1, 'One generated file opens as a tab');
    const generatedPath = (await fileTab.getAttribute('data-output-path'))!;
    await fileTab.click();
    await page.locator('.document-tab[data-output-path][aria-pressed="true"]').waitFor();
    assert.equal(await page.locator('.output-panel .artifact-breadcrumb').getAttribute('title'), generatedPath);
    await page.getByRole('button', { name: 'Close generated ' + generatedPath, exact: true }).click();
    await fileTab.waitFor({ state: 'detached' });
    await page.locator('#source').waitFor();
    await page.locator('.document-tab[data-output="generated"]').click();
    await page.locator('.document-tab[data-output-path][aria-pressed="true"]').waitFor();
    await page.locator('[data-document="source"]').click();
    await page.locator('#source').waitFor();
    assert.equal(await text(), before, 'Switching tabs keeps the source text');
    assert.equal(JSON.parse((await page.evaluate(key => localStorage.getItem(key), key))!).editorLayout, 'tabs');
    await gear.click();
    await settingsShown(page);
    await radio('Side by side').check();
    await gear.click();
    await outputPane.waitFor();
    assert.equal(await page.evaluate(key => localStorage.getItem(key), key), '{"theme":"dark"}', 'Side by side is the default and is not saved');
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

    // Narrow windows: the gear and the header toggle stay reachable and settings never scrolls sideways.
    for (const width of [768, 390]) {
      await page.setViewportSize({ width, height: 844 });
      for (const control of [gear, toggle]) {
        const box = (await control.boundingBox())!;
        assert.ok(box.x >= 0 && box.x + box.width <= width && box.y + box.height <= 844, `The ${await control.getAttribute('id')} control fits ${width}px`);
      }
      const header = (await page.locator('.topbar').boundingBox())!, box = (await toggle.boundingBox())!;
      assert.ok(box.y >= header.y && box.y + box.height <= header.y + header.height, `The theme toggle stays in the wrapped header at ${width}px`);
      assert.ok(await fits(page), `Getting started fits ${width}px`);
      await runCommand(page, 'Theme: Light');
      await themeIs(page, 'light');
      await toggle.click();
      await themeIs(page, 'dark');
      await gear.click();
      await settingsShown(page);
      assert.ok(await fits(page), `Settings fits ${width}px`);
      await page.keyboard.press('Escape');
      await start.waitFor();
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    await runCommand(page, 'Theme: Use system setting');
    assert.deepEqual(errors, []);
    console.log('Settings workflow passed: gear and palette open settings, Escape, Close settings and the gear return focus, navigation leaves it, toggle in the header, radio group, header toggle and palette themes agree, System follows the system live, arrow keys, dark first paint after reload, workspace state kept, source expansion and tabs, and narrow windows.');
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
  const toggle = page.locator('.topbar #theme-toggle');
  const radio = (name: string) => page.getByRole('radio', { name, exact: true });
  await runCommand(page, 'Theme: Use system setting');
  assert.equal(await page.locator('.rail #theme-toggle').count(), 0, 'The theme toggle is in the header, not the rail');
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
