import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';
import type { AddressInfo } from 'node:net';
import type { CodeEditor } from './editor/code-editor.ts';
import { createWorkbenchServer } from '../scripts/server.ts';
import { nativeFileHost } from './native-test-fixture.ts';
import { workspaceFilesProfile as profile, workspaceFilesVersion as version } from './workspace-files.ts';

async function savedText(path: string, expected: string) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    if (await readFile(path, 'utf8').catch(() => null) === expected) return;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.equal(await readFile(path, 'utf8'), expected);
}

test('negotiated connected files create a project on the provider and compile or run worksheets locally', { timeout: 90000 }, async () => {
  const base = await mkdtemp(join(tmpdir(), 'morphir-connected-files-'));
  const root = join(base, 'workspace'); await mkdir(join(root, 'models'), { recursive: true });
  const binary = Buffer.from([0, 255, 128, 13, 10]); await writeFile(join(root, 'models/raw.ionb'), binary);
  await writeFile(join(base, 'outside'), 'SECRET');
  const host = nativeFileHost(root);
  const source = { providerId: 'workspace', locator: 'workspace://fixture', displayName: 'Connected fixture' };
  const manifest = { protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'fixture-session',
    providers: [{ id: source.providerId, status: 'available', capabilities: [{ name: profile, version }] }], initialSources: [source] };
  const server = createWorkbenchServer(); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const methods: string[] = [], errors: string[] = [];
  try {
    await context.route('**/api/session', route => route.fulfill({ json: manifest }));
    await context.routeWebSocket('**/rpc', socket => socket.onMessage(async message => {
      const request = JSON.parse(String(message)); methods.push(request.method);
      try {
        let result: unknown;
        if (request.method === 'morphir.session.initialize') result = {};
        else {
          assert.equal(request.method, 'morphir.workspace-files.exchange');
          assert.equal(request.params.protocolVersion, 1); assert.equal(request.params.sessionId, manifest.sessionId);
          assert.deepEqual(request.params.source, source);
          result = await host.exchange(request.params.frame);
        }
        socket.send(JSON.stringify({ jsonrpc: '2.0', id: request.id, result }));
      } catch (error) { socket.send(JSON.stringify({ jsonrpc: '2.0', id: request.id, error: { code: -32603, message: String(error) } })); }
    }));
    const page = await context.newPage(); page.on('pageerror', error => errors.push(error.message)); page.setDefaultTimeout(15000);
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected`);
    await page.getByRole('button', { name: 'Add project…', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Add project…', exact: true }).click();
    await page.getByRole('textbox', { name: 'Project name', exact: true }).fill('Quotes');
    await page.getByRole('textbox', { name: 'Project folder', exact: true }).fill('packages/quotes');
    await page.getByRole('combobox', { name: 'Project language', exact: true }).selectOption('scheme');
    await page.getByRole('button', { name: 'Create project', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Workspace folder saved' }).waitFor();
    assert.match(await readFile(join(root, 'morphir.toml'), 'utf8'), /packages\/quotes/);
    await page.getByRole('button', { name: 'Compile workspace', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Compiled 1/1 projects' }).waitFor();
    await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('(identity 42)');
    await page.getByRole('button', { name: 'Run worksheet', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Worksheet finished' }).waitFor();
    await page.locator('.worksheet-observation pre.value').filter({ hasText: '42' }).waitFor();
    await savedText(join(root, 'worksheet.scm'), '(identity 42)');
    await page.locator('button[role="treeitem"][title="packages/quotes/src/main.scm"]').click();
    await writeFile(join(root, 'packages/quotes/src/main.scm'), 'external edit');
    await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('33');
    await page.getByRole('status').filter({ hasText: 'workspace request was refused' }).waitFor();
    assert.equal(await readFile(join(root, 'packages/quotes/src/main.scm'), 'utf8'), 'external edit');
    assert.equal(await page.locator('#source').evaluate(element => (element as CodeEditor).value), '33');
    assert.deepEqual(await readFile(join(root, 'models/raw.ionb')), binary);
    assert.equal(await readFile(join(base, 'outside'), 'utf8'), 'SECRET');
    assert.equal(methods.includes('morphir.playground.compile'), false);
    assert.deepEqual(errors, []);
  } finally {
    await context.close(); await browser.close(); await new Promise<void>(resolve => server.close(() => resolve()));
    await host.close(); await rm(base, { recursive: true, force: true });
  }
});
