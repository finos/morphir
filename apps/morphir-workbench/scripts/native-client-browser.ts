import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { once } from 'node:events';
import { chromium } from 'playwright';
import type * as Trace from '../browser/native-client-trace.ts';

/** Browser binding for the same explicit adapter; all verdicts remain in Rust. */
export async function nativeClientBrowser(
  compiled: string,
  driverPath: string,
) {
  const driver = readFileSync(driverPath);
  const server = createServer((request, response) => {
    const asset =
      request.url === '/core.js'
        ? compiled
        : request.url === '/trace.js'
          ? driver
          : request.url === '/'
            ? '<!doctype html><html><body>Native client MCK fixture</body></html>'
            : null;
    response.writeHead(asset === null ? 404 : 200, {
      'content-type':
        request.url === '/'
          ? 'text/html; charset=utf-8'
          : 'text/javascript; charset=utf-8',
      'cache-control': 'no-store',
    });
    response.end(asset ?? 'Not found');
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string')
    throw new Error('Missing browser fixture address');
  const url = `http://127.0.0.1:${address.port}`;
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (error) {
    server.close();
    throw error;
  }
  return {
    async run(input: unknown) {
      const page = await browser.newPage();
      try {
        await page.goto(url);
        await page.addScriptTag({ url: url + '/core.js' });
        return await page.evaluate(
          async ({ input, url }) => {
            const trace = (await import(url + '/trace.js')) as typeof Trace;
            return trace.runNativeClientTrace(
              input,
              globalThis.morphirWorkbenchJobs,
            );
          },
          { input, url },
        );
      } finally {
        await page.close();
      }
    },
    async close() {
      await browser.close();
      await new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      );
    },
  };
}
