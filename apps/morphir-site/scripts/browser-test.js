import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import { createSiteServer, siteBase } from './serve.js';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const base = siteBase(root);
const server = createSiteServer({ dir: `${root}_site`, base }).listen(0, '127.0.0.1');
await new Promise((resolve) => server.once('listening', resolve));
const origin = `http://127.0.0.1:${server.address().port}${base}`;
const browser = await chromium.launch();
const failures = [];
const check = (ok, message) => { if (!ok) failures.push(message); };

try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));

  await page.goto(origin);
  check((await page.title()) === 'Morphir', 'landing page title is "Morphir"');
  check(await page.locator('a[href$="/try/"]').count() > 0, 'landing page links to /try/');

  await page.fill('#search-input', 'decision');
  await page.waitForSelector('.search-results li a', { timeout: 5000 });
  check(await page.locator('.search-results li a').count() > 0, 'search for "decision" shows a result');
  const firstHref = await page.locator('.search-results li a').first().getAttribute('href');
  await page.locator('.search-results li a').first().click();
  await page.waitForURL((url) => url.pathname === firstHref, { timeout: 5000 }).catch(() => {});
  check(new URL(page.url()).pathname === firstHref, `clicking a search result opens ${firstHref}, not ${page.url()}`);
  await page.goto(origin);
  await page.fill('#search-input', 'zzzqqq');
  await page.waitForSelector('.search-empty', { timeout: 5000 });
  check((await page.textContent('.search-empty')) === 'No results', 'search without match shows "No results"');

  const toggle = page.locator('.theme-toggle');
  check((await toggle.textContent()).trim() === '', 'theme toggle shows an icon, not text');
  check(await toggle.locator('.theme-icon').count() === 1, 'theme toggle has one icon');
  const modes = [];
  for (const mode of ['system', 'light', 'dark']) {
    await page.waitForSelector(`.theme-toggle[aria-label="Theme: ${mode}"]`, { timeout: 2000 }).catch(() => {});
    modes.push([await toggle.getAttribute('aria-label'), await page.evaluate(() => document.documentElement.dataset.theme ?? 'system')]);
    await toggle.click();
  }
  check(JSON.stringify(modes) === JSON.stringify([['Theme: system', 'system'], ['Theme: light', 'light'], ['Theme: dark', 'dark']]),
    `theme toggle cycles system, light, dark: ${JSON.stringify(modes)}`);

  await page.goto(`${origin}docs/`);
  check(await page.locator('.docs-sidebar a').count() > 0, 'docs index has a sidebar');
  const sidebar = (await page.locator('.docs-sidebar li').allTextContents()).map((t) => t.trim());
  check(sidebar[0] === 'Get started' && sidebar[1] === 'Quick Start Guide',
    `the sidebar starts with the Get started group and Quick start: ${sidebar.slice(0, 3).join(', ')}`);

  const wide = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await wide.goto(`${origin}docs/architecture/`);
  const rail = wide.locator('.docs-toc');
  check(await rail.isVisible(), 'the On this page rail shows at 1440 px');
  check((await rail.locator('a').allTextContents()).includes('Overview'), 'the rail lists the Overview heading');
  const [preWidth, pWidth] = await wide.evaluate(() => ['.prose pre', '.prose p'].map((s) => document.querySelector(s).getBoundingClientRect().width));
  check(preWidth > pWidth + 50, `code blocks are wider than text at 1440 px (${preWidth} vs ${pWidth})`);
  const target = rail.locator('a').nth(2);
  const hash = await target.getAttribute('href');
  await target.click();
  await wide.waitForFunction((h) => document.querySelector(`.docs-toc a[href="${h}"]`)?.getAttribute('aria-current') === 'location', hash, { timeout: 3000 }).catch(() => {});
  check(await target.getAttribute('aria-current') === 'location', `clicking ${hash} in the rail marks it as the current heading`);
  const [headingTop, headerBottom] = await wide.evaluate((h) => [document.getElementById(h.slice(1)).getBoundingClientRect().top, document.querySelector('.site-header').getBoundingClientRect().bottom], hash);
  check(headingTop >= headerBottom - 1, `the sticky header does not cover ${hash} (${headingTop} < ${headerBottom})`);
  check(await wide.locator('.site-header').isVisible() && headerBottom > 0, 'the header stays in view after scrolling');
  await wide.setViewportSize({ width: 1024, height: 900 });
  check(!(await rail.isVisible()), 'the rail is hidden at 1024 px');
  for (const path of ['', 'docs/architecture/']) {
    await wide.setViewportSize({ width: 390, height: 844 });
    await wide.goto(`${origin}${path}`);
    check(await wide.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `/${path} has no horizontal scroll at 390 px`);
  }
  await wide.close();

  const copyContext = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'] });
  const copyPage = await copyContext.newPage();
  await copyPage.goto(origin);
  check(await copyPage.locator('.code-window .copy-button').count() === 1, 'the landing-page sample has a copy button');
  await copyPage.goto(`${origin}docs/architecture/`);
  const block = copyPage.locator('.prose .code-block').first();
  const copy = block.locator('.copy-button');
  check(await copy.count() === 1, 'a docs code block has one copy button');
  if (await copy.count() === 1) {
    check(await copy.getAttribute('data-tooltip') === 'Copy', 'the copy button tooltip says "Copy"');
    const code = (await block.locator('code').innerText()).replace(/\n$/, '');
    await copy.click();
    await copyPage.waitForSelector('.copy-button[data-tooltip="Copied"]', { timeout: 2000 }).catch(() => {});
    check(await copy.getAttribute('data-tooltip') === 'Copied', 'the tooltip says "Copied" after a click');
    check(await copyPage.evaluate(() => navigator.clipboard.readText()) === code, 'the copy button puts the code block text on the clipboard');
  }
  await copyContext.close();

  await page.goto(`${origin}docs/writing_for_the_site/`);
  check(await page.locator('figure.diagram svg').count() > 0, 'writing guide renders its Mermaid diagram as figure.diagram svg');

  const feed = await page.request.get(`${origin}blog/atom.xml`);
  check(feed.ok(), 'atom feed is served');
  const parsed = await page.evaluate((xml) => !new DOMParser().parseFromString(xml, 'application/xml').querySelector('parsererror'), await feed.text());
  check(parsed, 'atom feed parses as XML');

  const tryPage = await browser.newPage();
  await tryPage.goto(`${origin}try/`);
  await tryPage.waitForSelector('#app *', { timeout: 15000 });
  check(true, 'workbench mounts at /try/');
  check(await tryPage.locator('a.brand[href="../"]').count() === 1, '/try/ sidebar logo links to the site home');
  const home = tryPage.locator('.breadcrumb a', { hasText: 'Morphir' });
  check(await home.count() === 1, '/try/ breadcrumb links to the site home');
  if (await home.count() === 1) {
    await home.click();
    await tryPage.waitForURL(origin, { timeout: 5000 }).catch(() => {});
    check(tryPage.url() === origin, `/try/ home link opens ${origin}, not ${tryPage.url()}`);
  }

  check(errors.length === 0, `no page errors: ${errors.join('; ')}`);
} finally {
  await browser.close();
  server.close();
}

if (failures.length) {
  for (const f of failures) console.error(`FAIL: ${f}`);
  process.exit(1);
}
console.log('site browser smoke test passed');
