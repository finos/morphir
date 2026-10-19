import assert from 'node:assert/strict';
import { once } from 'node:events';
import { readFile, cp, mkdtemp, writeFile, rm, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { unzipSync } from 'fflate';
import type { AddressInfo } from 'node:net';
import { chromium } from 'playwright';
import { createWorkbenchServer } from './server.ts';

const desktopAssets = process.argv.includes('--desktop');
const server = createWorkbenchServer({ root: desktopAssets ? new URL('../../morphir-workbench-desktop/frontend/dist/', import.meta.url) : undefined });
let browser;
const scratch = await mkdtemp(join(tmpdir(), 'morphir-yaml-tree-'));
try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ acceptDownloads: true });
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}`);
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.evaluate(() => {
    const request = globalThis.morphirWorkbench.request;
    globalThis.morphirWorkbench.request = (input, receive) => request(input, raw => {
      const result = JSON.parse(raw);
      Object.assign(globalThis, { modelCompatibilityResult: result });
      if (result.modelSource?.kind === "original-tree") Object.assign(globalThis, { yamlImportedTree: result.modelSource.files.length });
      if (result.modelSource?.kind === "original-file") Object.assign(globalThis, { yamlImportedName: result.modelSource.filename });
      receive(raw);
    });
  });
  const source = Buffer.from('\ufeff# retained\r\nformatVersion: 4\r\ndistribution: {Library: {packageName: yaml-browser, dependencies: {}, def: {modules: {}}}}\r\n');
  for (const [name, format] of [['model.yaml', ''], ['model.yml', 'morphir-yaml'], ['unknown.txt', 'morphir-yaml']]) {
    await page.getByLabel('Model format', { exact: true }).selectOption(format!);
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import model', exact: true }).click();
    await (await chooser).setFiles({ name: name!, mimeType: 'application/yaml', buffer: source });
    await page.waitForFunction(name => (globalThis as unknown as { yamlImportedName: string }).yamlImportedName === name, name);
    await page.getByRole('button', { name: 'Download original file', exact: true }).waitFor();
    const details = page.locator('details').filter({ has: page.getByText('Original YAML', { exact: true }) });
    if (await details.getAttribute('open') === null) await page.getByText('Original YAML', { exact: true }).click();
    assert.equal(await page.locator('#model-original').getAttribute('data-language'), 'yaml');
    assert.match(await page.locator('#model-original').evaluate(node => (node as HTMLElement & { value: string }).value), /# retained/);
    const download = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Download original file', exact: true }).click();
    const saved = await download;
    assert.deepEqual(await readFile((await saved.path())!), source);
    assert.equal(saved.suggestedFilename(), name);
  }
  // The shared inspector also accepts explicit raw IR, engine checkpoints and
  // MEP model envelopes. Keep their bytes separate from the normalized IR view.
  const expectation = JSON.parse(await readFile(new URL('../fixtures/headless-parity/v1/yaml/literal42-tree/expectation.json', import.meta.url), 'utf8'));
  const ir = expectation.expectedNormalizedIr;
  const checkpoint = `before::morphir_pipeline::after::{profile:"morphir-pipeline-v1",contract:"ir-unit",unit_id:"browser-compat",ir:${JSON.stringify(ir)},metadata:[{node_id:"value:parity:main#answer",data:future::{label:"must not rename",huge:18446744073709551616000001,amount:123.4500}}],provenance:[origin::"kept"]}`;
  const corpus = JSON.parse(await readFile(new URL('../fixtures/headless-parity/v1/draft.29/cases.json', import.meta.url), 'utf8'));
  const mepIr = JSON.parse(corpus.cases.find((test: {id: string}) => test.id === 'inspect-model-ion').expected.value.normalizedIr);
  const compatibility = [
    {name: 'raw-ir.json', codec: 'morphir-json', bytes: Buffer.from('\ufeff' + JSON.stringify(ir, null, 2).replace(/\n/g, '\r\n') + '\r\n'), ir},
    {name: 'engine-checkpoint.ion', codec: 'ion-text', bytes: Buffer.from('\ufeff// retained checkpoint\r\n' + checkpoint + '\r\n'), ir},
    {name: 'mep-model.ion', codec: 'ion-text', bytes: await readFile(new URL('../fixtures/headless-parity/v1/originals/model.ion', import.meta.url)), ir: mepIr},
    {name: 'mep-model.ionb', codec: 'ion-binary', bytes: await readFile(new URL('../fixtures/headless-parity/v1/originals/model.ionb', import.meta.url)), ir: mepIr},
  ];
  for (const input of compatibility) {
    await page.getByLabel('Model format', {exact: true}).selectOption(input.codec);
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', {name: 'Import model', exact: true}).click();
    await (await chooser).setFiles({name: input.name, mimeType: 'application/octet-stream', buffer: input.bytes});
    await page.waitForFunction(name => (globalThis as unknown as {yamlImportedName: string}).yamlImportedName === name, input.name);
    const result = await page.evaluate(() => (globalThis as unknown as {modelCompatibilityResult: {ir: unknown; sourceUnitIon: string}}).modelCompatibilityResult);
    assert.deepEqual(result.ir, input.ir, input.name);
    assert.match(result.sourceUnitIon, /morphir_pipeline::/);
    if (input.name.startsWith('mep-')) assert.match(result.sourceUnitIon, /morphir_model_import::/);
    if (input.name.startsWith('engine-')) {
      assert.match(result.sourceUnitIon, /browser-compat/);
      assert.match(result.sourceUnitIon, /18446744073709551616000001/);
      assert.match(result.sourceUnitIon, /future::/);
    }
    const original = page.waitForEvent('download');
    await page.getByRole('button', {name: 'Download original file', exact: true}).click();
    const download = await original;
    assert.equal(download.suggestedFilename(), input.name);
    assert.deepEqual(await readFile((await download.path())!), input.bytes);
    const normalized = page.waitForEvent('download');
    await page.getByRole('button', {name: 'Export IR', exact: true}).click();
    const projection = await normalized;
    assert.equal(projection.suggestedFilename(), 'morphir-ir.json');
    assert.deepEqual(JSON.parse(await readFile((await projection.path())!, 'utf8')), input.ir);
    const logs = page.getByRole('tab', {name: 'Logs', exact: true});
    if (await logs.getAttribute('aria-selected') !== 'true' || !await page.locator('#tool-panel-body').isVisible()) await logs.click();
    await page.getByText('Exported normalized IR as morphir-ir.json', {exact: true}).last().waitFor();
  }
  const fixture = fileURLToPath(new URL('../fixtures/headless-parity/v1/yaml/reference-greeting/tree/', import.meta.url));
  await cp(fixture, scratch, { recursive: true });
  const rawSidecar = Buffer.from([0, 255, 128, 13, 10]);
  await writeFile(join(scratch, 'raw.bin'), rawSidecar);
  const captured = await readdir(scratch, { recursive: true, withFileTypes: true });
  const expectedFiles = captured.filter(entry => entry.isFile());
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import YAML tree', exact: true }).click();
  await (await chooser).setFiles(scratch);
  await page.waitForFunction(count => (globalThis as unknown as { yamlImportedTree: number }).yamlImportedTree === count, expectedFiles.length);
  const archiveDownload = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download captured original files', exact: true }).click();
  const archive = unzipSync(await readFile((await (await archiveDownload).path())!));
  for (const entry of expectedFiles) {
    const full = join(entry.parentPath, entry.name);
    const path = full.slice(scratch.length + 1);
    assert.deepEqual(Buffer.from(archive[path]!), await readFile(full), path);
  }
  assert.deepEqual(Buffer.from(archive['raw.bin']!), rawSidecar);
  assert.equal(Object.keys(archive).length, expectedFiles.length);
  assert.deepEqual(errors, []);
  console.log('YAML browser passed: real YAML/raw IR/checkpoint/MEP text and binary pickers, normalized projection labels, local worker, YAML preview and byte-exact file/ZIP originals including binary sidecars.');
} finally {
  await browser?.close();
  await rm(scratch, { recursive: true, force: true });
  server.closeAllConnections();
  await new Promise<void>(resolve => server.close(() => resolve()));
}
