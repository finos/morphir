import type { ChildProcess } from 'node:child_process';
import type { AddressInfo } from 'node:net';
import type { WorkResult, Json, InitialSource, Project } from '../browser/contracts.ts';
interface RpcReply { id: number; error?: { code: number; message: string }; result?: Partial<WorkResult> & { irVersion?: string; snapshot?: { projects: Project[] }; content?: string }; }
interface RpcCall { method: string; params: { source?: InitialSource; projectId?: string; documents?: { uri: string; languageId: string; version: number; text: string }[]; [key: string]: unknown }; }
import type { Page, Locator, Request, Response, WebSocket, Browser, BrowserContext } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { readFile, mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createWorkbenchServer } from './server.ts';
import { createJobProvider } from './job-provider.ts';
import { jobWorkflow } from './job-workflow.ts';
import { createServer as createPortReservation } from 'node:net';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { elmWorkflow, moonbitWorkflow, libraryWorkflow, stringWorkflow, supportedWorkflow } from './elm-workflow.ts';
import { toolPanelWorkflow, terminalOutcomeWorkflow } from './tool-panel-workflow.ts';
import { explorerWorkflow } from './explorer-workflow.ts';
import { detailsWorkflow } from './details-workflow.ts';
import { unzipSync, strFromU8 } from 'fflate';
import { openSample } from './workbench-steps.ts';

// Opt-in acceptance uses a real Rust binary and an isolated provider/workspace.
// Keep the ordinary fixture workflow independent of Rust tooling.
async function liveHostWorkflow(binary: string) {
  const scratch = await mkdtemp(join(tmpdir(), 'morphir-workbench-live-'));
  const workspace = join(scratch, 'workspace'), home = join(scratch, 'home');
  await mkdir(workspace); await mkdir(home);
  await writeFile(join(workspace, 'morphir.toml'), '[project]\nname="acceptance/workbench"\nversion="1.0.0"\nsource_directory="src"\n[frontend]\nlanguage="gleam"\n');
  let host: ChildProcess | undefined, proxy: ReturnType<typeof createWorkbenchServer> | undefined, browser: Browser | null | undefined, desktop: ChildProcess | undefined;
  const jobsEnabled = process.env.MORPHIR_WORKBENCH_LIVE_JOBS === '1';
  try {
    host = spawn(binary, ['ui', workspace, '--no-open', '--no-banner'], {
      env: {...process.env, MORPHIR_HOME:home, RUST_LOG:'warn'}, stdio:['ignore','ignore','pipe'],
    });
    const exited = once(host, 'exit').catch(() => null);
    const launch = await new Promise<URL>((resolve, reject) => {
      let buffer = '';
      const timer = setTimeout(() => reject(new Error('Rust UI host did not become ready in 15 seconds.')), 15000);
      host!.once('error', error => { clearTimeout(timer); reject(error); });
      host!.once('exit', () => { clearTimeout(timer); reject(new Error('Rust UI host exited before startup.')); });
      host!.stderr!.on('data', data => {
        buffer = (buffer + data).slice(-16384);
        const url = buffer.match(/Morphir UI: (http:\/\/127\.0\.0\.1:\d+\/launch[^\s]+)/)?.[1];
        if (url) { clearTimeout(timer); resolve(new URL(url)); }
      });
    });
    const jobs = jobsEnabled ? await createJobProvider() : null;
    proxy = createWorkbenchServer({host:launch.origin, jobs});
    proxy.listen(0, '127.0.0.1'); await once(proxy, 'listening');
    const origin = `http://127.0.0.1:${(proxy.address() as AddressInfo).port}`;
    let context: BrowserContext, page: Page;
    if (process.env.MORPHIR_WORKBENCH_DESKTOP_BIN) {
      const reservation = createPortReservation();
      reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
      const port = (reservation.address() as AddressInfo).port;
      await new Promise(resolve => reservation.close(resolve));
      const env: NodeJS.ProcessEnv = { ...process.env, PROTON_HEADLESS: '1', PROTON_REMOTE_DEBUGGING_PORT: String(port),
        MORPHIR_WORKBENCH_LAUNCH_URL: origin + launch.pathname + launch.search };
      delete env.PROTON_FRONTEND_URL;
      desktop = spawn(process.env.MORPHIR_WORKBENCH_DESKTOP_BIN, [], {env, stdio:['ignore','ignore','ignore']});
      desktop.on('error', () => {});
      const deadline = Date.now() + 30000;
      while (Date.now() < deadline) {
        if (desktop.exitCode !== null || desktop.signalCode !== null) throw new Error('Packaged Proton exited before connection.');
        try { const response = await fetch(`http://127.0.0.1:${port}/json/version`); if (response.ok) break; } catch {}
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
      context = browser.contexts()[0]!;
      page = context!.pages()[0]!;
      await page!.waitForURL(url => url.origin === origin && url.search === '?mode=connected');
      const nativeAccess = await page!.evaluate(async () => {
        if (typeof window.__MoonBit__?.core?.invokeOp !== 'function') return [];
        const accessible = [];
        for (const [name, payload] of [
          ['app:workbench_native', JSON.stringify({ profile: 'morphir/workbench/native', contractVersion: '0.1.0-draft.1', operation: 'session.open' })],
          ['app:workbench_session_open', '0.1.0-draft.1'],
          ['app:workbench_workspace_choose', 'not-a-native-session'],
          ['app:workbench_workspace', JSON.stringify({ sessionId: 'not-a-native-session', body: '{"action":"cancel-picker"}' })],
          ['app:workbench_job', JSON.stringify({ sessionId: 'not-a-native-session', path: 'session', body: null })],
        ] as const) {
          try { await window.__MoonBit__.core.invokeOp(name!, payload!); accessible.push(name); } catch { /* No native command grant. */ }
        }
        return accessible;
      });
      assert.deepEqual(nativeAccess, [], 'An explicit connected launch registers no native commands');
    } else {
      browser = await chromium.launch({headless:true});
      context = await browser.newContext({viewport:{width:1440,height:1000}});
      page = await context.newPage();
    }
    const errors: string[] = [], methods: string[] = [], replies: RpcReply[] = [], requestMethods = new Map<number,string>();
    let finishProjectOpen: (reply: RpcReply) => void = () => {};
    const projectOpened = new Promise<RpcReply>(resolve => { finishProjectOpen = resolve; });
    page!.on('pageerror', error => errors.push(error.message));
    page!.on('websocket', socket => {
      socket.on('framesent', ({payload}) => {
        const message = JSON.parse(String(payload));
        if (message.method) { methods.push(message.method); requestMethods.set(message.id, message.method); }
      });
      socket.on('framereceived', ({payload}) => {
        const message = JSON.parse(String(payload)); replies.push(message);
        if (requestMethods.get(message.id) === 'morphir.project-model.open') finishProjectOpen(message);
      });
    });
    if (!desktop) {
      assert.equal((await context!.request.get(origin+'/api/session')).status(), 401);
      if (jobsEnabled) assert.equal((await context!.request.get(origin+'/api/workbench/session')).status(), 401);
      await page!.goto(origin+launch.pathname+launch.search);
    } else await page!.reload();
    await page!.getByRole('status').filter({hasText:'Connected · ready to compile'}).waitFor();
    assert.equal(new URL(page!.url()).search, '?mode=connected');
    assert.ok((await context!.cookies()).some(cookie => cookie.httpOnly), 'Launch exchanged into an HttpOnly cookie');
    assert.equal((await context!.request.get(origin+'/api/session')).status(), 200);
    assert.equal(await page!.getByRole('button',{name:'Compile & run',exact:true}).isEnabled(), false);
    assert.equal((await context!.request.get(origin+launch.pathname+launch.search)).status(), 401, 'Launch token is single-use');
    await page!.getByRole('combobox',{name:'Language',exact:true}).selectOption('gleam');
    const targets = await page!.getByRole('combobox',{name:'Target',exact:true}).locator('option').evaluateAll(items => items.map(item => (item as CodeEditor).value).filter(Boolean));
    assert.ok(targets.includes('gleam'), 'Real host advertises the built-in Gleam generator');
    await page!.getByRole('combobox',{name:'Target',exact:true}).selectOption('gleam');
    await page!.getByRole('textbox',{name:'Source editor',exact:true}).fill('pub type Currency { Currency }\n\npub fn identity(value: Int) -> Int { value }\n');
    await page!.getByRole('button',{name:'Compile',exact:true}).click();
    await page!.getByRole('status').filter({hasText:'Model ready'}).waitFor();
    const ir = JSON.parse(await page!.locator('#output').evaluate(editor => (editor as CodeEditor).value));
    assert.ok(ir.distribution, 'Rust frontend returned real Morphir IR');
    const compilation = replies.find(message => message.result?.ir);
    assert.ok(compilation?.result!.success);
    const generation = replies.find(message => Array.isArray(message.result?.artifacts));
    assert.ok(generation?.result!.success && generation.result.artifacts!.length > 0, 'Rust backend generated real artifacts');
    await page!.getByRole('button',{name:'Generated',exact:true}).click();
    assert.match(await page!.locator('#output').evaluate(editor => (editor as CodeEditor).value), /Currency|currency/);
    await writeFile(join(workspace, 'morphir-ir.json'), JSON.stringify(compilation.result.ir));
    await page!.getByRole('button',{name:'Model Explorer',exact:true}).click();
    const workspaceReply = replies.find(message => Array.isArray(message.result?.snapshot?.projects));
    assert.ok(workspaceReply?.result!.snapshot!.projects.length, 'Real host discovers the temporary workspace project');
    await page!.getByRole('button',{name:workspaceReply.result.snapshot.projects[0]!.name,exact:true}).click();
    const opened = await Promise.race([
      projectOpened,
      new Promise<never>((_, reject) => { const timer = setTimeout(() => reject(new Error('Project model RPC timed out.')), 15000); timer.unref(); projectOpened.finally(() => clearTimeout(timer)); }),
    ]);
    assert.ok(opened.result && !opened.error, 'Real host opened the workspace model');
    await page!.waitForFunction(() => [...document.querySelectorAll<HTMLButtonElement>('button')].some(button => button.textContent === 'Import model' && !button.disabled));
    await page!.getByRole('status').filter({hasText:'Model ready'}).waitFor();
    await page!.locator('.tree-item').filter({hasText:'Currency'}).click();
    await page!.getByRole('heading',{name:'Currency',exact:true}).waitFor();
    await page!.locator('.tree-item').filter({hasText:'identity'}).click();
    await page!.getByRole('heading',{name:'identity',exact:true}).waitFor();
    if (!jobsEnabled) assert.equal(await page!.getByRole('button',{name:'Evaluate',exact:true}).count(), 0);
    else await jobWorkflow(page!, { screenshot: process.env.MORPHIR_WORKBENCH_JOB_SCREENSHOT });
    assert.ok(methods.includes('morphir.session.initialize'));
    for (const method of ['catalog','compile','generate']) assert.ok(methods.includes('morphir.playground.'+method));
    assert.ok(methods.includes('morphir.workspace.open'));
    assert.ok(methods.includes('morphir.project-model.open'));
    assert.ok(methods.every(method => !/evaluate|cancel/.test(method)), 'v1 does not invent evaluation or cancellation RPC');
    assert.deepEqual(errors, []);
    if (process.env.MORPHIR_WORKBENCH_LIVE_SCREENSHOT) await page!.screenshot({path:process.env.MORPHIR_WORKBENCH_LIVE_SCREENSHOT,fullPage:true});
    console.log(JSON.stringify({liveRustHost:true,protocol:1,authenticated:true,singleUseLaunch:true,jobs:jobsEnabled,proton:!!desktop,frontend:'gleam',provider:'morphir-gleam',target:'gleam',artifactCount:generation.result.artifacts!.length,workspaceModel:true,methods:[...new Set(methods)]}));
    await browser.close(); browser = null;
    host.kill('SIGINT');
    const timer = setTimeout(() => host!.kill('SIGKILL'), 5000);
    try { await exited; } finally { clearTimeout(timer); }
  } finally {
    await browser?.close();
    if (desktop?.pid && desktop.exitCode === null && desktop.signalCode === null) {
      const exited = once(desktop, 'exit'); desktop.kill('SIGTERM');
      const timer = setTimeout(() => desktop!.kill('SIGKILL'), 5000);
      try { await exited; } finally { clearTimeout(timer); }
    }
    proxy?.closeAllConnections();
    if (proxy?.listening) await new Promise(resolve => proxy!.close(resolve));
    await proxy?.jobCleanup;
    if (host?.pid && host.exitCode === null && host.signalCode === null) {
      const exited = once(host, 'exit'); host.kill('SIGKILL'); await exited;
    }
    await rm(scratch,{recursive:true,force:true});
  }
}

if (process.env.MORPHIR_WORKBENCH_LIVE_HOST_BIN) {
  await liveHostWorkflow(process.env.MORPHIR_WORKBENCH_LIVE_HOST_BIN);
  process.exit(0);
}

const server = spawn(process.execPath, [fileURLToPath(new URL('./serve.ts', import.meta.url))], {
  env: { ...process.env, MORPHIR_WORKBENCH_PORT: '0' }, stdio: ['ignore', 'pipe', 'inherit'],
});
let browser: Browser | undefined;
try {
  const [output] = await once(server.stdout, 'data');
  const url = String(output).match(/http:\/\/127\.0\.0\.1:\d+/)![0];
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(url);
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  const back = page.getByRole('button', { name: 'Back', exact: true });
  assert.equal(await back.isEnabled(), false, 'Fresh session has no navigation history');
  assert.equal(await page.locator('.breadcrumb a, a.brand').count(), 0, 'Without a site home the workbench has no home links');
  assert.equal(await page.locator('#tool-panel-body').isVisible(), false, 'The tool panel starts collapsed');
  assert.equal(await page.getByRole('tab', { name: 'Logs', exact: true }).getAttribute('aria-selected'), 'true');
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  assert.equal(await back.isEnabled(), false, 'Active experience does not create history');
  await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('(square 7)'));
  await page.getByRole('textbox', { name: 'Source editor' }).fill('(+ 8 9)');
  await back.focus();
  await page.keyboard.press('Enter');
  await page.getByRole('button', { name: 'Compile & run', exact: true }).waitFor();
  assert.equal(await back.isEnabled(), false, 'Back consumes history without recording itself');
  assert.deepEqual(await page.locator('.toolbar-actions .primary:visible').allTextContents(), ['Compile & run'], 'One primary action leads the toolbar');
  await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value === '(+ 8 9)');
  assert.equal(await page.locator('#source').evaluate(editor => (editor as CodeEditor).value), '(+ 8 9)', 'Back retains source edits');
  await openSample(page, 'Pricing & arithmetic');
  await back.click();
  await page.locator('#source .cm-editor').waitFor();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('(total 3)'));
  await page.locator('#source .cm-line span').first().waitFor();
  assert.equal(await page.locator('#source .cm-lineNumbers').count(), 1);
  assert.equal(await page.locator('#source .cm-content').getAttribute('spellcheck'), 'false');
  const syntaxColors = await page.locator('#source .cm-line span').evaluateAll(tokens => [...new Set(tokens.map(token => getComputedStyle(token).color))]);
  assert.ok(syntaxColors.includes('rgb(123, 63, 176)'), 'Scheme numbers are highlighted');
  assert.ok(syntaxColors.includes('rgb(0, 114, 158)'), 'Scheme builtins are highlighted');
  assert.ok(await page.locator('#source .cm-line span').evaluateAll(tokens => tokens.some(token => getComputedStyle(token).fontStyle === 'italic')), 'Scheme comments are highlighted');
  await page.getByRole('button', { name: 'Compile & run', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  assert.equal(await page.locator('.run-value strong').textContent(), '41');
  assert.match(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value), /formatVersion/);
  assert.equal(await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).getAttribute('aria-readonly'), 'true');
  assert.ok(await page.locator('#output .cm-line span').count() > 0, 'JSON output is highlighted');
  const compiledIr = JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value));
  // Code panes take the height between the controls and the status bar at any window height.
  const splitGeometry = () => page.evaluate(() => {
    const box = (selector: string) => document.querySelector(selector)!.getBoundingClientRect();
    const scroller = document.querySelector<CodeEditor>('#output')!.shadowRoot.querySelector<HTMLElement>('.cm-scroller');
    return { page: document.documentElement.scrollHeight, viewport: innerHeight, source: box('#source').height,
      output: box('#output').height, gap: box('.statusbar').top - box('.footnote').bottom,
      run: box('.toolbar-actions .primary').bottom + scrollY, status: box('.statusbar').bottom + scrollY,
      outputScrolls: scroller!.scrollHeight > scroller!.clientHeight };
  });
  const fitted = await splitGeometry();
  assert.ok(fitted.page <= fitted.viewport + 1, 'Try Morphir fits a 1000px window without page scrolling');
  assert.ok(fitted.gap >= 0 && fitted.gap < 32, `No unused band above the status bar (${fitted.gap}px)`);
  assert.ok(fitted.source >= fitted.viewport * 0.55, `Source editor uses most of the window (${fitted.source}px)`);
  assert.ok(fitted.outputScrolls, 'Long output scrolls inside its editor');
  await page.setViewportSize({ width: 1440, height: 1400 });
  const tall = await splitGeometry();
  assert.ok(tall.source - fitted.source >= 350 && tall.output - fitted.output >= 350, 'A taller window gives its height to both code panes');
  assert.ok(tall.gap >= 0 && tall.gap < 32, `No unused band in a tall window (${tall.gap}px)`);
  await page.setViewportSize({ width: 1440, height: 640 });
  const short = await splitGeometry();
  assert.ok(short.source >= 280 && short.output >= 200, 'A short window keeps usable code panes');
  assert.ok(short.run < short.status && short.page - short.viewport < 120, 'A short window keeps actions, footnote and status reachable');
  await page.setViewportSize({ width: 1440, height: 1000 });

  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.locator('.tree-item').filter({ hasText: 'total' }).click();
  assert.match((await page.locator('.type-signature').textContent()!)!, /total/);
  await page.getByRole('button', { name: 'IR JSON', exact: true }).click();
  assert.match(await page.locator('#model-detail').evaluate(editor => (editor as CodeEditor).value), /Apply/);
  await page.getByRole('button', { name: 'Details', exact: true }).click();
  await page.getByRole('button', { name: 'Toggle sidebar' }).click();
  await page.locator('#context-navigation').waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.locator('#context-navigation').waitFor({ state: 'visible' });
  await page.getByRole('button', { name: 'Toggle sidebar' }).click();
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.locator('#context-navigation').waitFor({ state: 'hidden' });
  assert.match((await page.locator('.type-signature').textContent()!)!, /total/);
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();

  await page.getByRole('textbox', { name: 'Source editor' }).fill('(+ 20 22)');
  await page.getByText('Source changed · rerun').waitFor();
  await page.getByRole('textbox', { name: 'Source editor' }).press('End');
  await page.keyboard.insertText(' ');
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('textbox', { name: 'Source editor' }).press('ControlOrMeta+z');
  // CodeMirror may group nearby edits; verify undo/redo without depending on timing.
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')!.value !== '(+ 20 22) ');
  await page.getByRole('textbox', { name: 'Source editor' }).press('ControlOrMeta+Shift+z');
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')!.value === '(+ 20 22) ');
  await page.getByRole('button', { name: 'Compile & run', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.waitForFunction(() => document.querySelector<HTMLElement>('.run-value strong')?.textContent === '42');
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.value.includes('morphir'));
  await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
  await page.getByRole('button', { name: 'Run worksheet', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Worksheet finished' }).waitFor();
  const values = await page.locator('.worksheet-result .value').allTextContents();
  assert.ok(values.includes('49')); assert.ok(values.includes('(1 4 9 16)')); assert.ok(values.includes('1'));
  await page.getByRole('button', { name: 'Compile & inspect', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<HTMLElement>('.run-value strong')?.textContent === '42');
  await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
  await page.waitForFunction(() => [...document.querySelectorAll<HTMLElement>('.worksheet-result .value')].some(node => node.textContent === '49'));

  await page.getByRole('textbox', { name: 'Source editor' }).fill('(let ((x 1))');
  await page.getByRole('button', { name: 'Run worksheet', exact: true }).click();
  await page.waitForFunction(() => /[Uu]nterminated|[Uu]nexpected|[Ll]ist|[Ee]nd/.test(document.querySelector<HTMLElement>('.statusbar')!.textContent));
  assert.match((await page.getByRole('status').textContent()!)!, /[Uu]nterminated|[Uu]nexpected|[Ll]ist|[Ee]nd/);
  await page.getByRole('textbox', { name: 'Source editor' }).fill('(let loop ((x 0)) (loop (+ x 1)))');
  await page.getByRole('button', { name: 'Run worksheet', exact: true }).click();
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Cancelled' }).waitFor();
  await page.getByRole('textbox', { name: 'Source editor' }).fill('(+ 2 2)');
  await page.getByRole('button', { name: 'Run worksheet', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Worksheet finished' }).waitFor();
  assert.deepEqual(await page.locator('.worksheet-result .value').allTextContents(), ['4']);

  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  const chooserPromise = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await (await chooserPromise).setFiles(fileURLToPath(new URL('../../../pkgs/morphir-ir/conformance/fixtures/v3-greeting.json', import.meta.url)));
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await back.click();
  await page.getByRole('button', { name: 'Run worksheet', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.locator('.model-metrics strong').first().waitFor();
  assert.equal(await page.locator('.model-metrics strong').count(), 3, 'Replacement model removes old declaration destinations');
  assert.equal(await page.getByRole('heading', { name: 'total', exact: true }).count(), 0);
  await page.getByRole('button', { name: 'IR JSON', exact: true }).click();
  await page.waitForFunction(() => (document.querySelector<HTMLElement>('#model-detail') as CodeEditor)?.value.includes('elm-compat'));
  assert.match(await page.locator('#model-detail').evaluate(editor => (editor as CodeEditor).value), /elm-compat/);
  await page.getByRole('button', { name: 'Details', exact: true }).click();
  await page.locator('.model-metrics strong').first().waitFor();
  assert.deepEqual(await page.locator('.model-metrics strong').allTextContents(), ['2', '8', '7']);
  if (!await page.locator('#context-navigation').isVisible()) await page.getByRole('button', { name: 'Toggle sidebar' }).click();
  await page.getByRole('button', { name: 'Collapse main', exact: true }).click();
  await page.getByRole('button', { name: 'T Product', exact: true }).waitFor({ state: 'hidden' });
  await page.getByRole('textbox', { name: 'Find a declaration' }).fill('Product');
  await page.getByRole('button', { name: 'T Product', exact: true }).click();
  await page.getByRole('heading', { name: 'Product', exact: true }).waitFor();
  assert.match((await page.locator('.declaration-doc').textContent()!)!, /product with price information/);
  assert.deepEqual(await page.locator('.inspector-table tbody td:first-child').allTextContents(), ['id', 'name', 'price']);
  await page.locator('.reference-link').filter({ hasText: 'Main.ProductId' }).click();
  await page.getByRole('heading', { name: 'ProductId', exact: true }).waitFor();
  await page.getByRole('heading', { name: 'Used by', exact: true }).waitFor();
  await page.getByRole('textbox', { name: 'Find a declaration' }).fill('ProductId');
  await page.getByRole('button', { name: 'Toggle sidebar', exact: true }).click();
  await back.click();
  await page.getByRole('heading', { name: 'Product', exact: true }).waitFor();
  assert.equal(await page.locator('#context-navigation').isVisible(), false, 'Back works with the sidebar collapsed');
  await page.getByRole('button', { name: 'Toggle sidebar', exact: true }).click();
  assert.equal(await page.getByRole('textbox', { name: 'Find a declaration' }).inputValue(), 'Product', 'Back restores search context');
  await page.getByRole('button', { name: 'T Product', exact: true }).click();
  await back.click();
  await page.getByRole('heading', { name: 'Product', exact: true }).waitFor({state:'hidden'});
  await page.locator('.model-metrics strong').first().waitFor();
  assert.equal(await page.locator('.model-metrics strong').count(), 3, 'Repeated selection adds no duplicate; Back returns to overview');
  await page.getByRole('button', { name: 'T Product', exact: true }).click();
  await page.locator('.reference-link').filter({ hasText: 'Main.ProductId' }).click();
  await page.getByRole('heading', { name: 'ProductId', exact: true }).waitFor();
  await page.getByRole('textbox', { name: 'Find a declaration' }).fill('');
  await page.getByRole('button', { name: 'T Product', exact: true }).waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Expand main', exact: true }).click();
  await page.locator('.model-tree .tree-item[title="elm-compat:main#apply-discount"]').click();
  await page.getByRole('heading', { name: 'applyDiscount', exact: true }).waitFor();
  assert.match((await page.locator('.type-signature').textContent()!)!, /applyDiscount.*Basics.Float/);
  assert.deepEqual(await page.locator('.inspector-table tbody td:first-child').allTextContents(), ['discountPercent', 'originalPrice']);
  await page.getByRole('textbox', { name: 'discountPercent', exact: true }).fill('20');
  await page.getByRole('textbox', { name: 'originalPrice', exact: true }).fill('100');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '80.0');
  await page.getByRole('textbox', { name: 'discountPercent', exact: true }).fill('1e');
  await page.getByRole('textbox', { name: 'discountPercent', exact: true }).press('End');
  await page.keyboard.insertText('+1');
  assert.equal(await page.getByRole('textbox', { name: 'discountPercent', exact: true }).inputValue(), '1e+1');
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  const argumentsEditor = page.getByRole('textbox', { name: 'Function arguments', exact: true });
  await argumentsEditor.fill('[20, 100]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '80.0');
  await argumentsEditor.fill('[10, 100]');
  await page.getByText('Inputs changed · evaluate again', { exact: true }).waitFor();
  await argumentsEditor.fill('["bad", 100]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Evaluation failed' }).waitFor();
  assert.match((await page.locator('.evaluation-result pre').textContent()!)!, /finite float/);
  await argumentsEditor.fill('[20]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Evaluation failed' }).waitFor();
  await page.locator('.evaluation-result pre').filter({ hasText: 'Expected 2 arguments' }).waitFor();
  // A lone opening bracket can be completed by CodeMirror into valid JSON.
  await argumentsEditor.fill('not valid json');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.locator('.evaluation-result pre').filter({ hasText: 'valid JSON array' }).waitFor();
  // Hold a real worker reply at the host boundary to exercise late-result guards.
  await page.evaluate(() => {
    const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
    globalThis.morphirWorkbench.request = (data, receive) => request(data, reply => {
      if (data.operation === 'evaluate') globalThis.releaseEvaluation = () => { delete globalThis.releaseEvaluation; receive(reply); };
      else receive(reply);
    });
    globalThis.restoreRequests = () => { globalThis.morphirWorkbench.request = request; };
  });
  await argumentsEditor.fill('[20, 100]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.waitForFunction(() => typeof globalThis.releaseEvaluation === 'function');
  await argumentsEditor.fill('[10, 100]');
  await page.evaluate(() => globalThis.releaseEvaluation!());
  await page.getByRole('status').filter({ hasText: 'Finished for earlier inputs' }).waitFor();
  assert.equal(await page.locator('.evaluation-result.stale pre').textContent(), '80.0');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.waitForFunction(() => typeof globalThis.releaseEvaluation === 'function');
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Cancelled' }).waitFor();
  await page.evaluate(() => globalThis.releaseEvaluation!());
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '80.0');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.waitForFunction(() => typeof globalThis.releaseEvaluation === 'function');
  await page.locator('.model-tree .tree-item[title="elm-compat:main#order-status-to-string"]').click();
  await page.getByRole('heading', { name: 'orderStatusToString', exact: true }).waitFor();
  await page.evaluate(() => globalThis.releaseEvaluation!());
  await page.getByRole('status').filter({ hasText: 'Finished for another function' }).waitFor();
  assert.equal(await page.locator('.evaluation-result').count(), 0);
  await page.evaluate(() => globalThis.restoreRequests!());
  await argumentsEditor.fill('[{"constructor":"elm-compat:main#shipped","arguments":[]}]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '"Shipped"');
  await page.locator('.model-tree .tree-item[title="elm-compat:main#is-valid-order"]').click();
  await page.getByRole('heading', { name: 'isValidOrder', exact: true }).waitFor();
  const order = { 'order-id': 'order-1', products: [[{ id: 'sku-1', name: 'Book', price: 12.5 }, '2']], status: { constructor: 'elm-compat:main#confirmed', arguments: [] } };
  await argumentsEditor.fill(JSON.stringify([order]));
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '#t');
  await page.locator('.model-tree .tree-item[title="elm-compat:main#calculate-total"]').click();
  await page.getByRole('heading', { name: 'calculateTotal', exact: true }).waitFor();
  await argumentsEditor.fill(JSON.stringify([order]));
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '25.0');
  // Switch the same record document to fields and modify a nested product tuple.
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  const price = page.getByRole('textbox', { name: 'order.products[1][1].price', exact: true });
  await price.fill('15.00');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.locator('.evaluation-result pre').filter({ hasText: '30.0' }).waitFor();
  await page.getByRole('button', { name: 'Add item to order.products', exact: true }).click();
  await page.getByRole('textbox', { name: 'order.products[2][1].price', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Remove order.products[1]', exact: true }).click();
  await page.getByRole('textbox', { name: 'order.products[2][1].price', exact: true }).waitFor({ state: 'hidden' });
  assert.equal(await price.inputValue(), '0');
  await page.getByRole('button', { name: 'Remove order.products[1]', exact: true }).click();
  await page.getByRole('button', { name: 'Add item to order.products', exact: true }).click();
  await price.fill('2.50');
  await page.getByRole('textbox', { name: 'order.products[1][2]', exact: true }).fill('9007199254740993');
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  await page.waitForFunction(() => (document.querySelector<HTMLElement>('#evaluation-input') as CodeEditor)?.value.includes('9007199254740993'));
  assert.match(await page.locator('#evaluation-input').evaluate(editor => (editor as CodeEditor).value), /2\.50/);
  await argumentsEditor.fill('[true]');
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.locator('.argument-shape-error').waitFor();
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  assert.equal(await page.locator('#evaluation-input').evaluate(editor => (editor as CodeEditor).value), '[true]');
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.getByRole('button', { name: 'Reset inputs', exact: true }).click();
  await page.getByRole('textbox', { name: 'order.order-id', exact: true }).fill('first line\nsecond line');
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  await page.waitForFunction(() => { const editor = document.querySelector<HTMLElement>('#evaluation-input'); return editor && JSON.parse((editor as CodeEditor).value)[0]['order-id'] === 'first line\nsecond line'; });
  // A lone opening bracket can be completed by CodeMirror into valid JSON.
  await argumentsEditor.fill('not valid json');
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.getByRole('button', { name: 'Reset inputs', exact: true }).click();
  await page.getByRole('textbox', { name: 'order.order-id', exact: true }).waitFor();
  // Inspect a real nested return value, not a parsed Scheme string or mock reply.
  await page.locator('.model-tree .tree-item[title="elm-compat:api#create-order"]').click();
  await page.getByRole('textbox', { name: 'orderId', exact: true }).fill('<script>\norder-1');
  await page.getByRole('button', { name: 'Add item to products', exact: true }).click();
  await page.getByRole('textbox', { name: 'products[1][1].id', exact: true }).fill('sku-1');
  await page.getByRole('textbox', { name: 'products[1][1].name', exact: true }).fill('Book');
  await page.getByRole('textbox', { name: 'products[1][1].price', exact: true }).fill('12.5');
  await page.getByRole('textbox', { name: 'products[1][2]', exact: true }).fill('9007199254740993');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  const resultRoot = page.locator('.result-view > .result-branch');
  await resultRoot.waitFor();
  assert.deepEqual(await resultRoot.locator(':scope > .result-children > * > .result-node-title > strong, :scope > .result-children > details > summary strong').allTextContents(), ['order-id', 'products', 'status']);
  assert.equal(await page.locator('.result-view script').count(), 0);
  await resultRoot.locator(':scope > summary').focus();
  await page.keyboard.press('Enter');
  assert.equal(await resultRoot.getAttribute('open'), null, 'Result branches collapse with the keyboard');
  await page.keyboard.press('Enter');
  await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  const resultJson = JSON.parse(await page.locator('#evaluation-output').evaluate(editor => (editor as CodeEditor).value));
  assert.equal(resultJson.kind, 'record');
  assert.equal(resultJson.fields[0].value.text, JSON.stringify('<script>\norder-1'));
  const tuple = resultJson.fields[1].value.items[0];
  assert.equal(tuple.kind, 'tuple');
  assert.equal(tuple.items[1].text, '9007199254740993');
  const priceResult = tuple.items[0].fields.find((field: { name: string; value: Json }) => field.name === 'price').value;
  const floatBits = new DataView(new ArrayBuffer(8)); floatBits.setFloat64(0, 12.5);
  assert.equal(priceResult.bits, floatBits.getBigUint64(0).toString());
  assert.equal(resultJson.fields[2].value.tag, 'elm-compat:main#pending');
  assert.equal(await page.locator('#evaluation-output .cm-content').getAttribute('contenteditable'), 'false');
  await page.getByRole('textbox', { name: 'orderId', exact: true }).fill('changed');
  await page.getByText('Inputs changed · evaluate again', { exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(editor => (editor as CodeEditor).value)), resultJson, 'View changes retain the previous result');
  await page.getByRole('button', { name: 'Printed', exact: true }).click();
  await page.getByRole('textbox', { name: 'Printed result', exact: true }).waitFor();
  assert.match(await page.locator('#evaluation-output').evaluate(editor => (editor as CodeEditor).value), /9007199254740993/);
  await page.getByRole('button', { name: 'Value', exact: true }).click();
  await page.locator('.result-branch summary').filter({ hasText: 'Tuple / vector' }).click();
  await page.locator('.result-view pre').filter({ hasText: '9007199254740993' }).waitFor();
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await back.isVisible(), true, 'Back remains available on mobile');
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'Nested result fits mobile');
  const resultBounds = await page.locator('.result-view').boundingBox();
  for (const button of await page.getByRole('group', { name: 'Result view' }).getByRole('button').all()) {
    const bounds = await button.boundingBox();
    assert.ok(bounds!.x + bounds!.width <= resultBounds!.x + resultBounds!.width + 1, 'Result controls remain inside their mobile panel');
  }
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.locator('.model-tree .tree-item[title="elm-compat:main#order-status-to-string"]').click();
  await page.getByRole('combobox', { name: 'status constructor', exact: true }).selectOption({ label: 'Shipped' });
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  assert.equal(await page.locator('.evaluation-result pre').textContent(), '"Shipped"');
  await page.locator('.model-tree .tree-item[title="elm-compat:main#order-status-to-string"]').click();
  await page.locator('.reference-link').filter({ hasText: 'Main.Pending' }).click();
  await page.getByRole('heading', { name: 'OrderStatus', exact: true }).waitFor();
  assert.ok((await page.locator('.constructor-list strong').allTextContents()).includes('Pending'));
  await page.getByRole('textbox', { name: 'Find a declaration' }).fill('does-not-exist');
  await page.getByText('No declarations match this search.', { exact: true }).waitFor();
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  assert.equal(await page.getByRole('textbox', { name: 'Find a declaration' }).inputValue(), 'does-not-exist');
  await page.getByRole('textbox', { name: 'Find a declaration' }).fill('');
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export IR', exact: true }).click();
  assert.equal((await downloadPromise).suggestedFilename(), 'morphir-ir.json');

  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  for (let state = 0; state < 2; state++) {
    // The sidebar becomes a band above the page, so neither state narrows the content.
    assert.ok(await page.locator('main').evaluate(main => main.getBoundingClientRect().width) >= 380, 'Narrow screens keep the full content width');
    assert.ok(await page.locator('#source').evaluate(editor => editor.getBoundingClientRect().height) >= 280, 'Stacked source pane keeps a usable height');
    await page.getByRole('button', { name: 'Toggle sidebar' }).click();
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  }
  await page.getByRole('button', { name: 'Toggle sidebar' }).click();

  await page.setViewportSize({ width: 1440, height: 1000 });
  await elmWorkflow(page);
  await moonbitWorkflow(page);
  await libraryWorkflow(page);
  await stringWorkflow(page);
  await supportedWorkflow(page);
  await toolPanelWorkflow(page);
  await terminalOutcomeWorkflow(page, { resize: true, screenshot: process.env.MORPHIR_WORKBENCH_OUTCOME_SCREENSHOT });
  await explorerWorkflow(page);
  await detailsWorkflow(page);
  await page.locator('.connection a', { hasText: 'Connect' }).click();
  await page.waitForURL(u => new URL(u).search === '?mode=connected', { timeout: 5000 }).catch(() => {});
  assert.equal(new URL(page.url()).search, '?mode=connected', 'The Connect link opens connected mode');
  await page.goto(`${url}/?mode=connected`);
  await page.getByRole('status').filter({ hasText: 'launch URL' }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Compile', exact: true }).isEnabled(), false);
  const rpcCalls: RpcCall[] = [];
  let includeBinary = false;
  const generatedFiles = [
    {path:'src/Sample/Main.scala',content:'val answer = 41',binary:false},
    {path:'src/Sample/Helpers.scala',content:'def identity(value: Int): Int = value',binary:false},
    {path:'src/Other/Main.scala',content:'val answer = 42',binary:false},
    {path:'src/Sample/VeryLongUnicode_雪_Module.scala',content:'val snow = "雪"',binary:false},
    {path:'build.json',content:'{"name":"sample"}\n',binary:false},
    {path:'empty.txt',content:'',binary:false},
    {path:Array.from({length:20},(_,i)=>`level${i}`).join('/')+'/deep.txt',content:'deep host path',binary:false},
  ];
  await page.route('**/api/session', route => route.fulfill({ json: {
    protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'fixture-session', initialSources: [],
    providers: [{ id: 'fixture', status: 'available', capabilities: ['catalog', 'compile', 'generate'].map(name => ({ name: `morphir/playground/${name}`, version: '1' })) }],
  } }));
  await page.routeWebSocket('**/rpc', socket => {
    socket.onMessage(raw => {
      const request = JSON.parse(String(raw));
      rpcCalls.push(request);
      const result = request.method.endsWith('catalog') ? {
        frontends: [
          { languageId: 'scheme', displayName: 'Fixture Scheme', fileExtensions: ['.scm'], irVersions: ['4.0.0'], compile: true, providerId: 'fixture', defaultProfile: 'unnegotiated-profile', profiles: [{id:'unnegotiated-profile',displayName:'Unnegotiated profile'}] },
          { languageId: 'gleam', displayName: 'Fixture Gleam', fileExtensions: ['.gleam'], irVersions: ['4.0.0'], compile: true },
        ],
        targets: [{ target: 'scala', displayName: 'Fixture Scala', irVersions: ['4.0.0'], generate: true }, { target: 'elm', displayName: 'Fixture Elm', irVersions: ['4.0.0'], generate: true }],
      } : request.method.endsWith('compile') && request.params.documents[0].text.includes('type-error') ? { success: false, diagnostics: [{ severity: 'error', code: 'E-TYPE', message: 'Type mismatch',
          location: { uri: 'file:///main.scm', range: { start: { line: 0, character: 4 }, end: { line: 0, character: 10 } } } }] }
        : request.method.endsWith('compile') ? { success: true, ir: compiledIr, irVersion: '4.0.0', diagnostics: [], modules: ['Main'] }
        : request.method.endsWith('generate') ? { success: true, artifacts: includeBinary ? [...generatedFiles,{path:'assets/example.bin',content:'opaque host payload',binary:true}] : generatedFiles, diagnostics: [] } : {};
      socket.send(JSON.stringify({ jsonrpc: '2.0', id: request.id, result }));
    });
  });
  await page.goto(`${url}/?mode=connected`);
  await page.getByRole('status').filter({ hasText: 'Connected · ready' }).waitFor();
  assert.equal(await back.isEnabled(), false, 'Connected session starts with empty history');
  const callsBeforeNavigation = rpcCalls.length;
  await page.getByRole('button', {name:'Model Explorer',exact:true}).click();
  await back.click();
  await page.getByRole('button', {name:'Compile',exact:true}).waitFor();
  assert.equal(rpcCalls.length, callsBeforeNavigation, 'Back is local UI navigation and adds no RPC');
  assert.equal(await page.getByRole('button', { name: 'Worksheet', exact: true }).isEnabled(), false);
  assert.equal(await page.getByRole('button', { name: 'Compile & run', exact: true }).isEnabled(), false);
  await page.getByRole('textbox', { name: 'Source editor' }).fill('(total 3)');
  assert.equal(await page.getByRole('combobox',{name:'Source profile',exact:true}).count(),0,'Connected v1 does not expose unnegotiated source profiles');
  const connectedLanguage = page.getByRole('combobox', {name:'Language',exact:true});
  assert.deepEqual(await connectedLanguage.locator('option').evaluateAll(options=>options.map(option=>(option as CodeEditor).value)),['scheme','gleam'],'Connected choices come only from the host catalog');
  await connectedLanguage.selectOption('gleam');
  await page.getByText('src/main.gleam',{exact:true}).waitFor();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#source')?.value === '').catch(async error => {
    console.error('Connected source draft state', await page.locator('#source').evaluate(e => ({value:(e as CodeEditor).value, language:e.dataset.language, document:e.dataset.document})), await connectedLanguage.inputValue());
    throw error;
  });
  await page.getByRole('textbox',{name:'Source editor',exact:true}).fill('// retained host-language draft');
  await connectedLanguage.selectOption('scheme');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#source')?.value === '(total 3)');
  await connectedLanguage.selectOption('gleam');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#source')?.value === '// retained host-language draft');
  await connectedLanguage.selectOption('scheme');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#source')?.value === '(total 3)');
  assert.equal(rpcCalls.length,2,'Language switching adds no connected RPC calls');
  await page.getByRole('combobox', { name: 'Target' }).selectOption('scala');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.value.includes('val answer = 41'));
  assert.deepEqual(rpcCalls.map(call => call.method), ['morphir.session.initialize', 'morphir.playground.catalog', 'morphir.playground.compile', 'morphir.playground.generate']);
  assert.deepEqual(rpcCalls[2]!.params.package, { name: 'user' });
  assert.equal(rpcCalls[2]!.params.documents![0]!.text, '(total 3)');
  assert.equal('frontendProvider' in rpcCalls[2]!.params,false);
  assert.equal('frontendProfile' in rpcCalls[2]!.params,false);
  const generated = page.getByRole('textbox', { name: 'Generated output', exact: true });
  assert.equal(await generated.getAttribute('aria-readonly'), 'true');
  assert.ok(await page.locator('#output .cm-line span').count() > 0, 'Host Scala output is highlighted');
  assert.equal(rpcCalls[2]!.params.irVersion, '4.0.0');
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.locator('.tree-item[title="user:main#main"]').click();
  await page.getByText('Evaluation is unavailable in connected protocol v1.', { exact: false }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Evaluate', exact: true }).count(), 0);
  assert.equal(rpcCalls.length, 4);
  await page.getByRole('button', {name:'Try Morphir',exact:true}).click();
  const fileNavigation = page.getByRole('navigation', {name:'Generated files',exact:true});
  await fileNavigation.waitFor();
  assert.equal(await fileNavigation.locator('.artifact-file').count(),7);
  await fileNavigation.getByRole('button', {name:'src/Other/Main.scala',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value==='val answer = 42');
  assert.equal(await page.locator('.artifact-breadcrumb').textContent(),'src/Other/Main.scala');
  await page.getByRole('combobox', {name:'Target',exact:true}).selectOption('elm');
  await page.waitForFunction(()=>document.querySelector<HTMLSelectElement>('select[aria-label="Target"]')?.value==='elm');
  assert.equal(await page.locator('#output').getAttribute('data-language'),'scala','Current file highlighting follows its path until new output is generated');
  assert.equal(rpcCalls.length,4,'Changing the target alone does not regenerate files');
  await page.getByRole('combobox', {name:'Target',exact:true}).selectOption('scala');
  await fileNavigation.getByRole('button', {name:'Collapse src/Sample/',exact:true}).click();
  await fileNavigation.getByRole('button', {name:'Expand src/Sample/',exact:true}).waitFor();
  assert.equal(await fileNavigation.getByRole('button', {name:'src/Sample/Main.scala',exact:true}).isVisible(),false);
  assert.equal(await fileNavigation.getByRole('button', {name:'src/Other/Main.scala',exact:true}).isVisible(),true);
  await fileNavigation.getByRole('button', {name:'Expand src/Sample/',exact:true}).click();
  await fileNavigation.getByRole('button', {name:generatedFiles.at(-1)!.path,exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value==='deep host path');
  const archiveDownload = page.waitForEvent('download');
  await page.getByRole('button', {name:'Download project',exact:true}).click();
  const archive = unzipSync(await readFile(await (await archiveDownload).path()));
  assert.deepEqual(Object.keys(archive),generatedFiles.map(file=>file.path));
  for(const file of generatedFiles) assert.equal(strFromU8(archive[file.path]!),file.content);
  await page.getByRole('button', {name:'Expand generated files',exact:true}).click();
  await page.locator('.editor-grid.output-expanded').waitFor();
  await fileNavigation.getByRole('button', {name:'src/Other/Main.scala',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value==='val answer = 42');
  if(process.env.MORPHIR_WORKBENCH_OUTPUT_MULTI_SCREENSHOT) await page.screenshot({path:process.env.MORPHIR_WORKBENCH_OUTPUT_MULTI_SCREENSHOT,fullPage:true});
  includeBinary = true;
  await page.getByRole('button', {name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Model ready'}).waitFor();
  await fileNavigation.getByRole('button', {name:'assets/example.bin',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value==='Binary artifact: text preview unavailable');
  assert.equal(await page.getByRole('button', {name:'Download file',exact:true}).isEnabled(),false);
  assert.equal(await page.getByRole('button', {name:'Download project',exact:true}).isEnabled(),false);
  await page.setViewportSize({width:390,height:844});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Focused multi-file output fits mobile width');
  await page.getByRole('button', {name:'Hide generated files',exact:true}).click();
  await page.getByRole('button', {name:'Show generated files',exact:true}).waitFor();
  assert.equal(await fileNavigation.isVisible(),false);
  await page.getByRole('button', {name:'Show generated files',exact:true}).click();
  await fileNavigation.waitFor();
  await page.getByRole('button', {name:'Restore split view',exact:true}).click();
  await page.setViewportSize({ width: 1440, height: 1000 });
  // A connected compile failure keeps the host's structured v1 diagnostics.
  await page.getByRole('textbox', { name: 'Source editor' }).fill('(type-error)');
  await page.getByRole('button', {name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Type mismatch'}).waitFor();
  await page.getByRole('tab', {name:/^Diagnostics/}).click();
  const hostReport = page.locator('.tool-report.current').filter({ hasText: 'E-TYPE' });
  await hostReport.waitFor();
  assert.equal(await hostReport.locator('.tool-location').textContent(), 'main.scm:1:5');
  assert.equal(await hostReport.locator('.tool-location').getAttribute('title'), 'file:///main.scm 0:4–0:10');
  assert.match((await hostReport.locator('.tool-severity').textContent()!)!, /^Error$/);
  assert.ok(rpcCalls.every(call => /^morphir\.(session|playground)\./.test(call.method)), 'Diagnostics add no RPC method');
  await page.getByRole('tab', {name:'Logs',exact:true}).click();
  assert.match((await page.locator('.tool-log').filter({ hasText: 'Initialize' }).last().textContent()!)!, /Connecting to the same-origin Morphir host/);
  await page.getByRole('button', {name:'Collapse panel',exact:true}).click();
  // The tagged mode uses the merged execution codec, including values that
  // cannot pass through ordinary JavaScript numbers or Unicode scalar strings.
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto(url);
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  const typedChooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await (await typedChooser).setFiles(fileURLToPath(new URL('../fixtures/typed-pricing.json', import.meta.url)));
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.locator('.tree-item[title="pricing:quotes#total"]').click();
  await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
  await page.getByRole('textbox', { name: 'quote.price.coefficient', exact: true }).fill('125');
  await page.getByRole('textbox', { name: 'quote.price.exponent', exact: true }).fill('-1');
  await page.getByRole('textbox', { name: 'quote.quantity', exact: true }).fill('3');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByText('Result · scheme-portable-v1/shared-sdk/bounded', { exact: true }).waitFor();
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  const typedArguments = page.getByRole('textbox', { name: 'Function arguments', exact: true });
  await typedArguments.fill(JSON.stringify([{ type: 'record', fields: [
    { name: 'price', value: { type: 'decimal', coefficient: '125', exponent: -1 } },
    { name: 'quantity', value: { type: 'int', value: '3' } },
  ] }]));
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
  await page.getByText('Result · scheme-portable-v1/shared-sdk/bounded', { exact: true }).waitFor();
  await page.getByRole('button', { name: 'Result JSON', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'decimal', coefficient: '375', exponent: -1 });
  await typedArguments.fill('[{"type":"int","value":"3"}]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.locator('.evaluation-result pre').filter({ hasText: 'execution.wrong_type' }).waitFor();
  await page.locator('.tree-item[title="pricing:boundaries#text"]').click();
  await typedArguments.fill('[{"type":"text","units":[55296,0,55357,56832]}]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'text', units: [55296,0,55357,56832] });
  await page.locator('.tree-item[title="pricing:results#failure"]').click();
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByText('Result · scheme-portable-v1/shared-sdk/bounded · model error', { exact: true }).waitFor();
  await page.locator('.tree-item[title="pricing:scalars#huge"]').click();
  await page.getByRole('button', { name: 'IR JSON', exact: true }).click();
  await page.waitForFunction(() => (document.querySelector<HTMLElement>('#model-detail') as CodeEditor)?.value.includes('1234567890123456789012345678901234567890'));
  await page.getByRole('button', { name: 'Details', exact: true }).click();
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'int', value: '1234567890123456789012345678901234567890' });
  const typedDownload = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export IR', exact: true }).click();
  const exportedText = await readFile(await (await typedDownload).path(), 'utf8');
  assert.ok(exportedText.includes('1234567890123456789012345678901234567890'), 'IR export preserves exact integer lexemes');
  await page.locator('.tree-item[title="pricing:quotes#captured"]').click();
  await page.getByText('Typed evaluation requires a public entry', { exact: false }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Evaluate', exact: true }).count(), 0);
  await page.locator('.tree-item[title="pricing:quotes#difference"]').click();
  // Hold a worker callback across a runtime switch; the new request ID rejects it.
  await page.evaluate(() => {
    const request = globalThis.morphirWorkbench.request;
    globalThis.morphirWorkbench.request = (payload, receive) => request(payload, reply => {
      globalThis.releaseTyped = () => receive(reply);
    });
    globalThis.restoreTyped = () => { globalThis.morphirWorkbench.request = request; };
  });
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.waitForFunction(() => typeof globalThis.releaseTyped === 'function');
  await page.getByRole('button', { name: 'Local Scheme', exact: true }).click();
  await page.evaluate(() => { globalThis.releaseTyped!(); globalThis.restoreTyped!(); });
  await page.getByRole('status').filter({ hasText: 'Evaluation mode changed' }).waitFor();
  assert.equal(await page.locator('.evaluation-result').count(), 0);
  await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
  await typedArguments.waitFor();
  await page.waitForFunction(() => JSON.parse((document.querySelector<HTMLElement>('#evaluation-input')! as CodeEditor).value)[0]?.type === 'int');
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value)), [{type:'int',value:'0'}, {type:'int',value:'0'}]);
  // Every typed field edits the canonical document, including numeric drafts.
  await page.locator('.tree-item[title="pricing:boundaries#decimal"]').click();
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.getByRole('textbox', { name: 'input.coefficient', exact: true }).fill('9007199254740993');
  await page.getByRole('textbox', { name: 'input.exponent', exact: true }).fill('-');
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value)), [{type:'decimal',coefficient:'9007199254740993',exponent:'-'}]);
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  assert.equal(await page.getByRole('textbox', { name: 'input.exponent', exact: true }).inputValue(), '-');
  await page.getByRole('textbox', { name: 'input.exponent', exact: true }).fill('-2');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'decimal',coefficient:'9007199254740993',exponent:-2});
  await page.locator('.tree-item[title="pricing:boundaries#float"]').click();
  await page.getByRole('textbox', { name: 'input.number', exact: true }).fill('-0.0');
  await page.waitForFunction(() => document.querySelector<HTMLInputElement>('input[aria-label="input.bits"]')?.value === '9223372036854775808');
  assert.equal(await page.getByRole('textbox', { name: 'input.bits', exact: true }).inputValue(), '9223372036854775808');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'float64',bits:'9223372036854775808'});
  await page.getByRole('textbox', { name: 'input.bits', exact: true }).fill('9221120237041090561');
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  assert.equal(JSON.parse(await page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value))[0].bits, '9221120237041090561');
  await page.locator('.tree-item[title="pricing:boundaries#text"]').click();
  await typedArguments.fill('[{"type":"text","units":[55296,0]}]');
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  assert.equal(await page.getByRole('textbox', { name: 'input.text', exact: true }).count(), 0);
  await page.getByRole('textbox', { name: 'input.units[1]', exact: true }).fill('65');
  await page.getByRole('textbox', { name: 'input.text', exact: true }).fill('A😀\nB');
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value))[0].units, [65,55357,56832,10,66]);
  await page.locator('.tree-item[title="pricing:quotes#status-amount"]').click();
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.getByRole('combobox', { name: 'status constructor', exact: true }).selectOption('pricing:quotes#approved');
  await page.getByRole('textbox', { name: 'status.1.coefficient', exact: true }).fill('375');
  await page.getByRole('textbox', { name: 'status.1.exponent', exact: true }).fill('-1');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'decimal',coefficient:'375',exponent:-1});
  await page.locator('.tree-item[title="pricing:boundaries#maybe"]').click();
  await page.getByRole('combobox', { name: 'input case', exact: true }).selectOption('just');
  await page.getByRole('textbox', { name: 'input.1', exact: true }).fill('9007199254740993');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'maybe',case:'just',value:{type:'int',value:'9007199254740993'}});
  await page.locator('.tree-item[title="pricing:boundaries#result"]').click();
  await page.getByRole('combobox', { name: 'input case', exact: true }).selectOption('err');
  await page.getByRole('textbox', { name: 'input.1.text', exact: true }).fill('Error');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'result',case:'err',value:{type:'text',units:[69,114,114,111,114]}});
  await page.locator('.tree-item[title="pricing:boundaries#tuple"]').click();
  await page.getByRole('textbox', { name: 'input[1].coefficient', exact: true }).fill('125');
  await page.getByRole('textbox', { name: 'input[1].exponent', exact: true }).fill('-1');
  await page.getByRole('textbox', { name: 'input[2]', exact: true }).fill('9007199254740993');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'tuple',items:[{type:'decimal',coefficient:'125',exponent:-1},{type:'int',value:'9007199254740993'}]});
  await page.locator('.tree-item[title="pricing:boundaries#character"]').click();
  await page.getByRole('textbox', { name: 'input.text', exact: true }).fill('😀');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'character',units:[55357,56832]});
  await page.locator('.tree-item[title="pricing:boundaries#list"]').click();
  await page.getByRole('button', { name: 'Add item to input', exact: true }).click();
  await page.getByRole('textbox', { name: 'input[1]', exact: true }).fill('9007199254740993');
  await page.getByRole('button', { name: 'Add item to input', exact: true }).click();
  await page.getByRole('button', { name: 'Remove input[2]', exact: true }).click();
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'list',items:[{type:'int',value:'9007199254740993'}]});
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  await typedArguments.fill('[{"type":"bool","value":true}]');
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.locator('.argument-shape-error').waitFor();
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value)), [{type:'bool',value:true}]);
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.getByRole('button', { name: 'Reset inputs', exact: true }).click();
  await page.getByRole('button', { name: 'Add item to input', exact: true }).waitFor();
  // Ion uses the shared codec and converts back into the same fields/JSON values.
  await page.locator('.tree-item[title="pricing:boundaries#decimal"]').click();
  await page.getByRole('button', { name: 'Ion inputs', exact: true }).click();
  await typedArguments.fill('[12.50] // exact decimal');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'decimal',coefficient:'125',exponent:-1});
  assert.ok(await page.locator('#evaluation-input .cm-line span').evaluateAll(tokens => tokens.some(token => getComputedStyle(token).fontStyle === 'italic')), 'Ion comments are highlighted');
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  assert.equal(await page.getByRole('textbox', { name: 'input.coefficient', exact: true }).inputValue(), '1250');
  assert.equal(await page.getByRole('textbox', { name: 'input.exponent', exact: true }).inputValue(), '-2');
  await page.getByRole('button', { name: 'Ion inputs', exact: true }).click();
  await page.locator('.tree-item[title="pricing:quotes#difference"]').click();
  await typedArguments.fill('[9007199254740993, 1]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'int',value:'9007199254740992'});
  await page.locator('.tree-item[title="pricing:boundaries#text"]').click();
  await typedArguments.fill('[morphir_value::{type:"text",units:[55296,0]}]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), {type:'text',units:[55296,0]});
  const ionColors = await page.locator('#evaluation-input .cm-line span').evaluateAll(tokens => [...new Set(tokens.map(token => getComputedStyle(token).color))]);
  assert.ok(ionColors.includes('rgb(123, 63, 176)'), 'Ion numbers are highlighted');
  assert.ok(ionColors.includes('rgb(0, 88, 120)'), 'Ion annotations are highlighted');
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  assert.equal(await page.getByRole('textbox', { name: 'input.text', exact: true }).count(), 0);
  assert.equal(await page.getByRole('textbox', { name: 'input.units[1]', exact: true }).inputValue(), '55296');
  await page.getByRole('button', { name: 'Ion inputs', exact: true }).click();
  await typedArguments.fill('invalid Ion !!!');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Evaluation failed' }).waitFor();
  await page.getByText('Ion: unexpected trailing input', { exact: false }).waitFor();
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Cannot switch inputs:' }).waitFor();
  assert.equal(await page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value), 'invalid Ion !!!');
  assert.equal(await page.locator('#evaluation-input').getAttribute('data-language'), 'ion');
  await typedArguments.fill('[morphir_value::{type:"text",units:[55296,0]}]');
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<HTMLElement>('#evaluation-input')!.dataset.language === 'json');
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-input').evaluate(e => (e as CodeEditor).value)), [{type:'text',units:[55296,0]}]);
  await page.getByRole('button', { name: 'Ion inputs', exact: true }).click();
  await page.getByRole('button', { name: 'Local Scheme', exact: true }).click();
  await typedArguments.fill('["local text"]');
  await page.getByRole('button', { name: 'Evaluate', exact: true }).click();
  await page.getByRole('textbox', { name: 'Result JSON', exact: true }).waitFor();
  assert.equal(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)).text, '"local text"');
  await page.getByRole('button', { name: 'Typed invocation', exact: true }).click();
  await page.getByRole('button', { name: 'Input fields', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: 'Toggle sidebar' }).click();
  await page.getByText('Input and output types', { exact: true }).click();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);

  // Exercise the reusable component's contract independently of app messages.
  const componentPage = await browser.newPage();
  componentPage.on('pageerror', error => errors.push(error.message));
  await componentPage.goto(url);
  await componentPage.locator('#source .cm-editor').waitFor();
  await componentPage.evaluate(() => {
    const editor = document.createElement('morphir-code-editor');
    editor.id = 'component-fixture';
    editor.dataset.document = 'component-contract';
    editor.dataset.language = 'scheme';
    editor.dataset.readonly = 'false';
    editor.setAttribute('aria-label', 'Component fixture');
    (editor as CodeEditor).value = '(+ 1 2)';
    (editor as CodeEditor & { inputCount: number }).inputCount = 0;
    editor.addEventListener('input', () => ++(editor as CodeEditor & { inputCount: number }).inputCount);
    document.body.append(editor);
  });
  const fixture = componentPage.getByRole('textbox', { name: 'Component fixture', exact: true });
  await fixture.press('End');
  await componentPage.keyboard.insertText(' ');
  await componentPage.waitForFunction(() => (document.querySelector<HTMLElement>('#component-fixture')! as CodeEditor).value === '(+ 1 2) ');
  assert.equal(await componentPage.locator('#component-fixture').evaluate(editor => (editor as CodeEditor & { inputCount: number }).inputCount), 1, 'One change event per user edit');
  await componentPage.evaluate(() => {
    const editor = document.querySelector<HTMLElement>('#component-fixture');
    (editor as CodeEditor).value = '(+ 3 4)';
    editor!.dataset.language = 'unknown-host-language';
  });
  await componentPage.waitForFunction(() => (document.querySelector<HTMLElement>('#component-fixture')! as CodeEditor).value === '(+ 3 4)');
  assert.ok(await componentPage.locator('#component-fixture .cm-line span').evaluateAll(tokens => tokens.every(token => getComputedStyle(token).color === 'rgb(28, 30, 33)')), 'Unknown languages have no syntax colors');
  assert.equal(await componentPage.locator('#component-fixture').evaluate(editor => (editor as CodeEditor & { inputCount: number }).inputCount), 1, 'Controlled updates do not echo input');
  await componentPage.evaluate(() => { document.querySelector<HTMLElement>('#component-fixture')!.dataset.readonly = 'true'; });
  await componentPage.waitForFunction(() => document.querySelector<HTMLElement>('#component-fixture')!.shadowRoot!.querySelector<HTMLElement>('.cm-content')!.getAttribute('contenteditable') === 'false');
  await fixture.focus();
  await componentPage.keyboard.type('cannot edit');
  assert.equal(await componentPage.locator('#component-fixture').evaluate(editor => (editor as CodeEditor).value), '(+ 3 4)', 'Read-only documents reject editing');
  assert.equal(await componentPage.locator('#component-fixture').evaluate(editor => { editor.remove(); return (editor as CodeEditor).view; }), null, 'Unmount destroys CodeMirror');
  await componentPage.close();
  assert.deepEqual(errors, []);
  console.log('Browser workflow passed: local compile/run, explorer, back navigation, context retention, typed evaluation, Ion conversion/highlighting/invalid drafts and controls (exact Decimal/Int, Float64 bits, UTF-16, Maybe/Result, constructors, records/lists/tuples), structured/JSON/printed results, stale replies, worksheet, cancellation, import/export, mobile, connection failure and connected-v1 compile/generate fixture.');

} finally {
  await browser?.close();
  server.kill();
}
