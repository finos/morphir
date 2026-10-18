import type { Page } from 'playwright';

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
