import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { createReadStream } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer as createPortReservation, type AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium, type Browser, type BrowserContext, type Page } from 'playwright';
import { unzipSync } from 'fflate';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import { createWorkbenchServer } from './server.ts';
import { showGeneratedFiles, setTarget } from './workbench-steps.ts';

const binary = process.env.MORPHIR_WORKBENCH_ARTIFACT_FIXTURE_BIN;
if (!binary) throw new Error('Set MORPHIR_WORKBENCH_ARTIFACT_FIXTURE_BIN to the qualified installed-process host fixture.');
const mode = process.env.MORPHIR_WORKBENCH_ARTIFACT_FIXTURE_MODE ?? 'download';
if (!['download', 'binary', 'nul-text'].includes(mode)) throw new Error('Unknown artifact fixture mode.');
const reportPath = resolve(process.env.MORPHIR_WORKBENCH_ARTIFACT_REPORT ??
  fileURLToPath(new URL('../../../.dev/artifact-transfer/browser-download-report.json', import.meta.url)));
const desktopBinary = process.env.MORPHIR_WORKBENCH_DESKTOP_BIN;
const assetRoot = process.env.MORPHIR_WORKBENCH_ARTIFACT_ASSET_ROOT;
if (desktopBinary && !assetRoot) throw new Error('Set MORPHIR_WORKBENCH_ARTIFACT_ASSET_ROOT to the packaged frontend directory.');
const assetsURL = assetRoot ? pathToFileURL(resolve(assetRoot) + '/') : new URL('../dist/', import.meta.url);
const scratch = await mkdtemp(join(tmpdir(), 'morphir-artifact-browser-'));
await mkdir(dirname(reportPath), { recursive: true });
// Never mistake a previous run's file for a successful native save or overwrite it.
const output = await mkdtemp(join(dirname(reportPath), `saved-${mode}-`));
const pendingPath = join(dirname(reportPath), 'pending-native-save.json');
const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
async function fileDigest(path: string): Promise<string> {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
const source = 'pub type Currency { Currency }\n\npub fn identity(value: Int) -> Int { value }\n';
type Descriptor = { launchUrl: string; baseUrl: string; sessionId: string; providerId: string;
  target: string; stateDirectory: string; catalog: unknown };
type RpcFrame = { method?: string; id?: number; result?: { status?: string; producer?: { id: string }; artifacts?: {
  path: string; byteLength: number; sha256: string }[] } };
let host: ChildProcess | undefined; let desktop: ChildProcess | undefined; let browser: Browser | undefined;
let proxy: ReturnType<typeof createWorkbenchServer> | undefined;
let page: Page | undefined;
const failures: string[] = [];
async function saveDownload(name: string, click: () => Promise<unknown>, verify: (bytes: Uint8Array) => void): Promise<string> {
  const destination = join(output, name);
  if (!desktop) {
    const downloading = page!.waitForEvent('download');
    await click();
    const download = await downloading; assert.equal(download.suggestedFilename(), name);
    await download.saveAs(destination);
    verify(new Uint8Array(await readFile(destination)));
    return destination;
  }
  // CEF does not emit Playwright's download event. A visible native Save dialog
  // must be accepted by the operator, and the actual filesystem bytes must match.
  await writeFile(pendingPath, JSON.stringify({ phase: 'save', desktopPid: desktop.pid, name, destination }) + '\n');
  await click();
  const deadline = Date.now() + 600000;
  while (Date.now() < deadline) {
    if (desktop.exitCode !== null || desktop.signalCode !== null) throw new Error('Proton exited during a native save.');
    try {
      verify(new Uint8Array(await readFile(destination)));
      await rm(pendingPath);
      return destination;
    } catch { /* An absent or incomplete file is not a successful save. */ }
    await new Promise(resolve_ => setTimeout(resolve_, 100));
  }
  throw new Error(`Native Save did not produce the expected bytes for ${name} within 10 minutes.`);
}

async function stopOwnedProcess(child: ChildProcess | undefined): Promise<void> {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  const exited = once(child, 'exit');
  child.kill('SIGTERM');
  const timer = setTimeout(() => { if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL'); }, 5000);
  try { await exited; } finally { clearTimeout(timer); }
}
try {
  host = spawn(binary, ['--artifact-process-host', join(scratch, 'host'), ...(mode === 'download' ? [] : [mode])],
    { stdio: ['ignore', 'pipe', 'pipe'] });
  const descriptor = await new Promise<Descriptor>((resolve_, reject) => {
    let pending = '';
    const timer = setTimeout(() => reject(new Error('The installed-process fixture did not start within 30 seconds.')), 30000);
    host!.once('error', error => { clearTimeout(timer); reject(error); });
    host!.once('exit', () => { clearTimeout(timer); reject(new Error('The installed-process fixture exited before startup.')); });
    host!.stdout!.on('data', (data: Buffer) => {
      pending += data.toString();
      if (pending.length > 65536) { clearTimeout(timer); reject(new Error('Oversized fixture startup descriptor.')); return; }
      const newline = pending.indexOf('\n');
      if (newline >= 0) {
        try { const value = JSON.parse(pending.slice(0, newline)) as Descriptor; clearTimeout(timer); resolve_(value); }
        catch (error) { clearTimeout(timer); reject(error); }
      }
    });
  });
  proxy = createWorkbenchServer({ host: descriptor.baseUrl, root: assetsURL });
  proxy.listen(0, '127.0.0.1'); await once(proxy, 'listening');
  const origin = `http://127.0.0.1:${(proxy.address() as AddressInfo).port}`;
  const launch = new URL(descriptor.launchUrl);
  let context: BrowserContext;
  if (desktopBinary) {
    const reservation = createPortReservation();
    reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
    const port = (reservation.address() as AddressInfo).port;
    await new Promise<void>(resolve_ => reservation.close(() => resolve_()));
    const env: NodeJS.ProcessEnv = { ...process.env, PROTON_REMOTE_DEBUGGING_PORT: String(port),
      MORPHIR_WORKBENCH_LAUNCH_URL: origin + launch.pathname + launch.search };
    delete env.PROTON_HEADLESS; delete env.PROTON_FRONTEND_URL;
    desktop = spawn(desktopBinary, [], { env, stdio: 'ignore' });
    let startupError: Error | undefined;
    desktop.once('error', error => { startupError = error; });
    const deadline = Date.now() + 30000;
    let listening = false;
    while (Date.now() < deadline) {
      if (startupError) throw startupError;
      if (desktop.exitCode !== null || desktop.signalCode !== null) throw new Error('Proton exited before CDP startup.');
      try {
        const response = await fetch(`http://127.0.0.1:${port}/json/version`);
        if (response.ok) { listening = true; break; }
      } catch { /* Wait for this owned application's CDP endpoint. */ }
      await new Promise(resolve_ => setTimeout(resolve_, 100));
    }
    if (!listening) throw new Error('Proton CDP startup exceeded 30 seconds.');
    // The pinned Playwright runtime supports noDefaults for embedded browsers.
    // Otherwise connecting installs a download override before our first click,
    // preventing the application's real native Save dialog from being tested.
    const nativeConnection = { timeout: 30000, noDefaults: true };
    browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, nativeConnection);
    context = browser.contexts()[0]!; page = context.pages()[0]!;
    await page.waitForURL(url => url.origin === origin && url.search === '?mode=connected');
  } else {
    browser = await chromium.launch({ headless: true });
    context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
    page = await context.newPage();
  }
  page.on('pageerror', error => failures.push(error.message));
  const sent: RpcFrame[] = [], received: RpcFrame[] = [];
  page.on('websocket', socket => {
    socket.on('framesent', frame => { try { sent.push(JSON.parse(frame.payload.toString()) as RpcFrame); } catch {} });
    socket.on('framereceived', frame => { try { received.push(JSON.parse(frame.payload.toString()) as RpcFrame); } catch {} });
  });
  if (desktop) await page.reload(); // The launch token was already consumed, retain the authenticated cookie.
  else await page.goto(origin + launch.pathname + launch.search);
  await page.getByRole('status').filter({ hasText: 'Connected · ready to compile' }).waitFor();
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('gleam');
  await setTarget(page, descriptor.target);
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill(source);
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor({ timeout: 120000 });
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  // The generated files are listed in the right sidebar; the selected file previews in the output panel.
  await showGeneratedFiles(page);
  const navigation = page.locator('#sidebar-secondary').getByRole('navigation', { name: 'Generated files', exact: true });
  const expected = mode === 'download' ? {
    'indexed.bin': Uint8Array.from({ length: 1048833 }, (_, index) => (index % 256) ^ ((Math.floor(index / 65536)) % 256)),
    'original.txt': new TextEncoder().encode('\ufeffOriginal\r\nline two\r\n'),
    'empty.bin': new Uint8Array(),
  } : Object.fromEntries([0, 37, 83, 199].map((seed, index) => [mode === 'binary' ? `file-${index}.bin` : `file-${index}.txt`,
    mode === 'binary' ? Uint8Array.from({ length: 16777216 }, (_, offset) => (offset % 256) ^ ((Math.floor(offset / 65536) + seed) % 256)) : new Uint8Array(16777216)]));
  if (mode === 'download') assert.equal(digest(expected['indexed.bin']!), 'fa651153f54c6b07a3b2d6543fdd2601cf423ebe8e5a5e0d278437e6ac5565e0');
  if (mode === 'binary') assert.deepEqual(Object.values(expected).map(digest), [
    '728f52a85b49e21b090f8aab42eac87b30f1c82bdb3a3890627bc244de6756b0',
    'd42312f945214c8f55c283c08415efdddb975c664bc7ae4b129a6c37b79b87c8',
    '75e9210fb9b010ccd02fc3b824d482d6f1646aa3a5765baba3034423eb1550f7',
    'd5f3e8e4c2a22852ec5d5aa01c92f7ad149031ea896fd3fd70887f425fc30d27',
  ]);
  const saved: { path: string; byteLength: number; sha256: string }[] = [];
  for (const [path, original] of Object.entries(expected)) {
    await navigation.getByRole('button', { name: path, exact: true }).click();
    await page.waitForFunction(path => document.querySelector('.artifact-breadcrumb')?.getAttribute('title') === path, path);
    if (path === 'original.txt') await page.waitForFunction(() =>
      document.querySelector<CodeEditor>('#output')?.value.replace(/\r\n/g, '\n') === '\ufeffOriginal\nline two\n');
    const destination = await saveDownload(path, () => page!.getByRole('button', { name: 'Download file', exact: true }).click(),
      bytes => assert.deepEqual(bytes, original));
    const bytes = new Uint8Array(await readFile(destination)); assert.deepEqual(bytes, original);
    saved.push({ path, byteLength: bytes.byteLength, sha256: digest(bytes) });
  }
  const archivePath = await saveDownload('morphir-project.zip', () => page!.getByRole('button', { name: 'Download project', exact: true }).click(), bytes => {
    const entries = unzipSync(bytes); assert.deepEqual(Object.keys(entries), Object.keys(expected));
    for (const [path, original] of Object.entries(expected)) assert.deepEqual(entries[path], original);
  });
  const entries = unzipSync(await readFile(archivePath)); assert.deepEqual(Object.keys(entries), Object.keys(expected));
  for (const [path, original] of Object.entries(expected)) assert.deepEqual(entries[path], original);
  assert.equal(sent.filter(frame => frame.method === 'morphir.artifacts.generate').length, 1);
  assert.equal(sent.filter(frame => frame.method === 'morphir.artifacts.release').length, 1);
  assert.equal(sent.filter(frame => frame.method === 'morphir.playground.generate').length, 0);
  const sdkEvents = await readFile(join(descriptor.stateDirectory, 'events'), 'utf8');
  assert.equal(sdkEvents.split('\n').filter(line => line.startsWith('generate ')).length, 1);
  const captured = JSON.parse(await readFile(join(descriptor.stateDirectory, 'captured.json'), 'utf8')) as { ir: unknown };
  const compiled = received.find(frame => frame.result && 'ir' in frame.result)?.result as { ir?: unknown } | undefined;
  assert.deepEqual(captured.ir, compiled?.ir, 'Actual SDK child receives the frontend compiled IR');
  await page.screenshot({ path: join(dirname(reportPath), `artifacts-${mode}.png`), fullPage: true });
  let staleDownloads = 0; const unexpectedDownload = () => { ++staleDownloads; };
  page.on('download', unexpectedDownload);
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill(source + '// A later source revision\n');
  await page.getByRole('button', { name: 'Download file', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'no longer available' }).waitFor();
  assert.equal(staleDownloads, 0, 'A source edit invalidates old verified download references');
  page.off('download', unexpectedDownload);
  // The real built-in language backend is a separate probe from the deterministic byte target.
  await setTarget(page, 'gleam');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor({ timeout: 120000 });
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  await page.waitForFunction(() => /Currency|currency|identity/.test(document.querySelector<CodeEditor>('#output')?.value ?? ''));
  assert.ok(received.some(frame => frame.result?.status === 'ready' && frame.result.producer?.id === 'morphir-gleam'));
  assert.deepEqual(failures, []);
  const assets = Object.fromEntries(await Promise.all(['bootstrap.js', 'browser.js', 'transport.js', 'artifact-download.js'].map(async name =>
    [name, await fileDigest(fileURLToPath(new URL(name, assetsURL)))])));
  const report = { profile: 'morphir/workbench/artifact-browser-evidence', mode, browser: browser.version(),
    saveMode: desktop ? 'native-dialog' : 'browser-download',
    ...(desktopBinary ? { desktopBinarySha256: await fileDigest(desktopBinary), desktopPid: desktop!.pid, packagedAssetRoot: fileURLToPath(assetsURL) } : {}),
    fixtureBinarySha256: await fileDigest(binary), browserAssetsSha256: assets,
    source: 'actual Gleam frontend → installed SDK process fixture → authenticated host → connected UI → saved files and ZIP',
    passed: true, files: saved, archive: { path: archivePath, sha256: digest(await readFile(archivePath)), entries: Object.keys(entries) },
    generationInvocations: 1, releases: 1, legacyGenerationCalls: 0, staleDownloadRefused: true, realGleamBackend: true,
    catalog: descriptor.catalog, sdkEvents, pageErrors: failures };
  await writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
  console.log(`Artifact browser workflow passed (${mode}): ${saved.length} saved files, exact ZIP entries, one SDK invocation, real Gleam backend.`);
} catch (error) {
  if (page) await page.screenshot({ path: join(dirname(reportPath), `artifacts-${mode}-failure.png`), fullPage: true }).catch(() => {});
  throw error;
} finally {
  await browser?.close();
  await stopOwnedProcess(desktop);
  if (proxy) await new Promise<void>(resolve_ => proxy!.close(() => resolve_()));
  await stopOwnedProcess(host);
  await rm(pendingPath, { force: true });
  await rm(scratch, { recursive: true, force: true });
}
