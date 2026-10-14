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
  check((await page.title()).length > 0, 'landing page has a title');
  check(await page.locator('a[href$="/try/"]').count() > 0, 'landing page links to /try/');

  await page.fill('#search-input', 'decision');
  await page.waitForSelector('.search-results li a', { timeout: 5000 });
  check(await page.locator('.search-results li a').count() > 0, 'search for "decision" shows a result');
  await page.fill('#search-input', 'zzzqqq');
  await page.waitForSelector('.search-empty', { timeout: 5000 });
  check((await page.textContent('.search-empty')) === 'No results', 'search without match shows "No results"');

  const before = await page.evaluate(() => document.documentElement.dataset.theme ?? 'system');
  await page.click('.theme-toggle');
  const after = await page.evaluate(() => document.documentElement.dataset.theme ?? 'system');
  check(before !== after, 'theme toggle changes data-theme');

  await page.goto(`${origin}docs/`);
  check(await page.locator('.docs-sidebar a').count() > 0, 'docs index has a sidebar');

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
