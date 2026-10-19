import { createServer } from 'node:http';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import type { ClientEvidence, ClientScenario } from '../browser/artifact-client-trace-contract.ts';

/** Fresh browser globals per case; all decisions remain in the production owner. */
export async function artifactClientBrowser(driverPath: string) {
  const driver = readFileSync(driverPath);
  const server = createServer((request, response) => {
    const content = request.url === '/trace.js' ? driver : request.url === '/' ?
      '<!doctype html><html><body>Artifact client compatibility fixture</body></html>' : null;
    response.writeHead(content === null ? 404 : 200, {
      'Content-Type': request.url === '/' ? 'text/html; charset=utf-8' : 'text/javascript; charset=utf-8',
      'Cache-Control': 'no-store',
    });
    response.end(content ?? 'Not found');
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('The browser fixture has no address.');
  let browser;
  try { browser = await chromium.launch({ headless: true }); }
  catch (error) { server.close(); throw error; }
  const origin = `http://127.0.0.1:${address.port}`;
  return {
    async run(input: ClientScenario): Promise<ClientEvidence> {
      const page = await browser.newPage();
      try {
        await page.goto(origin);
        return await page.evaluate(async ({ source, origin }) => {
          const driver = await import(origin + '/trace.js') as typeof import('../browser/artifact-client-trace.ts');
          return driver.runArtifactClientScenario(JSON.parse(source) as ClientScenario);
        }, { source: JSON.stringify(input), origin });
      } finally { await page.close(); }
    },
    async close() {
      await browser.close();
      await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    },
  };
}
