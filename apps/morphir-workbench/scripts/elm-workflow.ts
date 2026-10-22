import { fileURLToPath } from 'node:url';
import type { Page, Locator, Request, Response, WebSocket, Browser, BrowserContext, FileChooser } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { unzipSync, strFromU8 } from 'fflate';
import { openSample, showCompile, showSource, showModel, setExplorer, setRightSidebar, showGeneratedFiles, build, buildAction, buildMenuItem, closeBuildMenu, buildMenuEntries, gettingStarted, reopenWorkspace, setTarget, currentTarget, useSourceWorkspace, currentSourceProfile, setSourceProfile, runCommand, forgetSourceWorkspace, replaceSourceDocument } from './workbench-steps.ts';

/** The Generated tab of the source document's output panel; the right sidebar's Generated section has its own name. */
const generatedTab = (page: Page) => page.locator('.output-panel .tabs').getByRole('button', { name: 'Generated', exact: true });

/** Shows the generated preview in the output panel and the generated file tree in the right sidebar. */
async function showGenerated(page: Page) {
  await generatedTab(page).click();
  await showGeneratedFiles(page);
}

/** The source document's tab, which names the file in the editor. */
const sourceFile = (page: Page, path: string) => page.locator('[data-document="source"] .document-tab-label').getByText(path, { exact: true });

/** The name of the active workspace, as its picker says it. */
async function workspaceName(page: Page) {
  return (await page.locator('#workspace-picker').getAttribute('aria-label'))!.replace(/^Workspace: /, '');
}

/** Reloads the page and opens the same saved workspace again from Recent workspaces. */
async function reloadWorkspace(page: Page) {
  const name = await workspaceName(page);
  await page.reload();
  await gettingStarted(page);
  await reopenWorkspace(page, name);
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
}

// The same generated-file component and worker run in Chromium and packaged CEF.
export async function elmWorkflow(page: Page, {
  nativeDownloads = true,
  selectFolder = (chooser: FileChooser, directory: string) => chooser.setFiles(directory),
} = {}) {
  await showCompile(page);
  await openSample(page, 'Elm constant');
  assert.equal(await currentTarget(page), 'elm', 'The Elm sample sets the project target');
  assert.equal(await page.getByRole('combobox', { name: 'Language', exact: true }).count(), 0, 'Language belongs to a project');
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('42');
  await build(page, 'Compile & run (Scheme)');
  await page.getByRole('status').filter({ hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/ }).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  assert.equal(await page.locator('.run-value strong').textContent(), '42');
  await openSample(page, 'Elm constant');
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('(define answer 42)'));
  await build(page, 'Compile');
  await page.getByRole('status').filter({ hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/ }).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  const ir = JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value));
  assert.ok(ir.distribution);
  await showGenerated(page);
  const selector = page.getByRole('navigation', { name: 'Generated files', exact: true });
  await selector.waitFor();
  const paths = await selector.locator('.artifact-file').evaluateAll(items => items.map(item => item.getAttribute('aria-label')!));
  assert.deepEqual(paths, ['root/src/User/Main.elm', 'root/elm.json', 'root/morphir.json']);
  const artifacts: Record<string,string> = {};
  for (const path of paths) {
    await selector.getByRole('button', { name: path, exact: true }).click();
    await page.waitForFunction(path => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|' + path, path);
    artifacts[path] = await page.locator('#output').evaluate(editor => (editor as CodeEditor).value);
    assert.equal(await page.getByRole('textbox', { name: 'Generated output', exact: true }).getAttribute('aria-readonly'), 'true');
    assert.ok(await page.locator('#output .cm-line span').count() > 0, 'Elm and JSON files have highlighting');
  }
  assert.match(artifacts[paths[0]!]!, /module User.Main/);
  assert.match(artifacts[paths[0]!]!, /answer : Int/);
  assert.match(artifacts[paths[0]!]!, /answer =\s+42/);
  assert.equal(JSON.parse(artifacts['root/elm.json']!).type, 'package');
  assert.ok(JSON.parse(artifacts['root/morphir.json']!).name);
  await selector.getByRole('button', { name: 'root/src/User/Main.elm', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|root/src/User/Main.elm');
  async function download(button: string, expectedName: string) {
    if (nativeDownloads) {
      const pending = page.waitForEvent('download');
      await page.getByRole('button', { name: button, exact: true }).click();
      const download = await pending;
      assert.equal(download.suggestedFilename(), expectedName);
      return new Uint8Array(await readFile(await download.path()));
    }
    // CEF owns native download presentation. Verify the emitted bytes at its
    // application origin without depending on an OS save dialog.
    await page.evaluate(() => {
      window.artifactDownload = null;
      document.addEventListener('click', async function capture(event) {
        const link = (event.target as Element).closest<HTMLAnchorElement>('a[download]');
        if (!link) return;
        event.preventDefault();
        document.removeEventListener('click', capture, true);
        window.artifactDownload = { name: link.download, bytes: Array.from(new Uint8Array(await (await fetch(link.href)).arrayBuffer())) };
      }, true);
    });
    await page.getByRole('button', { name: button, exact: true }).click();
    await page.waitForFunction(() => window.artifactDownload !== null);
    const result = await page.evaluate(() => window.artifactDownload);
    assert.equal(result!.name, expectedName);
    return new Uint8Array(result!.bytes);
  }
  assert.equal(strFromU8(await download('Download file', 'Main.elm')), artifacts[paths[0]!]);
  const archive = await download('Download project', 'morphir-project.zip');
  const unpacked = unzipSync(archive);
  assert.deepEqual(Object.keys(unpacked), paths);
  for (const path of paths) assert.equal(strFromU8(unpacked[path]!), artifacts[path]);
  if (process.env.MORPHIR_WORKBENCH_ELM_PROJECT) {
    const directory = process.env.MORPHIR_WORKBENCH_ELM_PROJECT;
    await mkdir(directory, { recursive: true });
    await writeFile(join(directory, 'morphir-project.zip'), archive);
    for (const path of paths) {
      await mkdir(join(directory, path.replace(/^root\//, ''), '..'), { recursive: true });
      await writeFile(join(directory, path.replace(/^root\//, '')), unpacked[path]!);
    }
  }
  await setTarget(page, 'scheme');
  assert.equal(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value), artifacts[paths[0]!], 'Target changes retain the previous generated files');
  await setTarget(page, 'elm');
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('9223372036854775808');
  await build(page, 'Compile');
  await page.getByRole('status').filter({ hasText: 'elm.int_literal' }).waitFor();
  await page.getByText(/Elm generation failed: elm.int_literal at user:main#main/).first().waitFor();
  assert.equal(await selector.count(), 0);
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  assert.ok(JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value)).distribution, 'Backend refusal retains the compiled model');
  await openSample(page, 'Elm constant');
  await build(page, 'Compile');
  await page.getByRole('status').filter({ hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/ }).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await showGenerated(page);
  await selector.waitFor();
  assert.equal(await selector.locator('.artifact-file').count(), 3, 'Generation recovers after refusal');
  await selector.getByRole('button', { name: 'Collapse root/src/User/', exact: true }).click();
  await selector.getByRole('button', { name: 'Expand root/src/User/', exact: true }).waitFor();
  assert.equal(await selector.getByRole('button', { name: 'root/src/User/Main.elm', exact: true }).isVisible(), false);
  await selector.getByRole('button', { name: 'Expand root/src/User/', exact: true }).focus();
  await page.keyboard.press('Enter');
  await selector.getByRole('button', { name: 'root/src/User/Main.elm', exact: true }).waitFor();
  await selector.getByRole('button', { name: 'root/elm.json', exact: true }).focus();
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|root/elm.json');
  assert.equal(await selector.getByRole('button', { name: 'root/elm.json', exact: true }).getAttribute('aria-pressed'), 'true');
  assert.equal(await page.locator('.artifact-breadcrumb').textContent(), 'root/elm.json');
  // Closing the right sidebar hides the file tree; the preview and the selection stay.
  await setRightSidebar(page, false);
  assert.equal(await selector.isVisible(), false);
  assert.equal(await page.locator('#output').getAttribute('data-document'), 'generated|root/elm.json', 'Hiding the files keeps the preview');
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  await showGenerated(page);
  await selector.waitFor();
  assert.equal(await selector.getByRole('button', { name: 'root/elm.json', exact: true }).getAttribute('aria-pressed'), 'true', 'IR navigation retains the selected file');
  // The left sidebar opens and closes on its own: the right sidebar and its controls stay as they are.
  const leftOpen = await page.locator('#sidebar-primary').isVisible();
  const controlIcon = page.locator('#sidebar-secondary [data-view="generated"] .section-move .nav-icon');
  const iconTransform = await controlIcon.evaluate(element => getComputedStyle(element).transform);
  await setExplorer(page, !leftOpen);
  assert.equal(await controlIcon.evaluate(element => getComputedStyle(element).transform), iconTransform, 'Left sidebar changes do not reverse the Generated section controls');
  assert.equal(await page.getByRole('button', { name: 'Toggle right sidebar', exact: true }).getAttribute('aria-expanded'), 'true');
  assert.equal(await selector.isVisible(), true, 'The generated files stay in view');
  await setExplorer(page, leftOpen);
  const source = await page.locator('#source').evaluate(editor => (editor as CodeEditor).value);
  await page.getByRole('button', { name: 'Expand generated files', exact: true }).click();
  await page.locator('.editor-grid.output-expanded').waitFor();
  assert.equal(await page.locator('.source-panel').isVisible(), false);
  assert.equal(await page.locator('#source').evaluate(editor => (editor as CodeEditor).value), source, 'Focus layout retains the mounted source editor');
  if (process.env.MORPHIR_WORKBENCH_OUTPUT_FOCUS_SCREENSHOT) await page.screenshot({ path: process.env.MORPHIR_WORKBENCH_OUTPUT_FOCUS_SCREENSHOT, fullPage: true });
  await page.getByRole('button', { name: 'Restore split view', exact: true }).click();
  await page.locator('.source-panel').waitFor();
  assert.equal(await page.locator('#source').evaluate(editor => (editor as CodeEditor).value), source);
  await selector.getByRole('button', { name: 'root/src/User/Main.elm', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|root/src/User/Main.elm');
  if (process.env.MORPHIR_WORKBENCH_ELM_SCREENSHOT) await page.screenshot({ path: process.env.MORPHIR_WORKBENCH_ELM_SCREENSHOT, fullPage: true });
  const viewport = page.viewportSize();
  if (viewport) {
    const leftOpen = await page.locator('#sidebar-primary').isVisible();
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'Generated files fit mobile width');
    // On a narrow screen a sidebar covers the documents; close the left one so the right one is the only cover.
    await setExplorer(page, false);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await selector.getByRole('button', { name: 'root/elm.json', exact: true }).click();
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|root/elm.json');
    assert.equal(JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value)).type, 'package');
    await page.setViewportSize(viewport);
    await setExplorer(page, leftOpen);
  }
  await useSourceWorkspace(page, 'elm');
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('module Workbench.Main'));
  await setTarget(page, 'moonbit');
  await build(page, 'Compile');
  await page.getByRole('status').filter({ hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/ }).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.value.includes('"distribution"'));
  const elmIr = JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value));
  assert.ok(elmIr.distribution, 'The Elm module compiles to IR in the browser');
  // Copy a real TOML monorepo, including a binary model sidecar and exact text.
  const chooser = page.waitForEvent('filechooser');
  await runCommand(page, 'Import folder…');
  await selectFolder(await chooser, fileURLToPath(new URL('./fixtures/folder-import/monorepo', import.meta.url)));
  const row = (path: string) => page.locator('[role="treeitem"][title=' + JSON.stringify(path) + ']');
  await row('packages/core/src/main.scm').waitFor();
  await row('packages/utils/src/main.scm').waitFor();
  await row('models/original.bin').waitFor();
  await build(page, 'Compile');
  await page.getByRole('status').filter({ hasText: 'Compiled 2/2 projects' }).waitFor();
  await row('packages/core/src/main.scm').click();
  // A lone opener wraps a CodeMirror selection. Keep this a failed-compilation
  // and exact-save test with a multi-character incomplete form instead.
  const invalidCoreSource = '(define broken';
  await replaceSourceDocument(page, invalidCoreSource, 'packages/core/src/main.scm');
  await build(page, 'Compile');
  await page.getByRole('status').filter({ hasText: 'Compiled 1/2 projects' }).waitFor();
  await row('packages/utils/src/main.scm').click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('identity'));
  await page.waitForFunction(() => Object.keys(localStorage).filter(key => key.endsWith('.tree.v1')).some(key => {
    const manifest = JSON.parse(localStorage.getItem(key)!);
    const binary = manifest.files['models/original.bin'];
    const notes = manifest.files['notes.md'];
    return binary && notes && JSON.parse(localStorage.getItem(binary)!).content === 'AP+A' && JSON.parse(localStorage.getItem(notes)!) === '\ufeffkeep\r\n';
  }));
  await reloadWorkspace(page);
  await row('packages/core/src/main.scm').waitFor();
  await row('models/original.bin').waitFor();
  await row('packages/core/src/main.scm').click();
  await page.waitForFunction(expected => document.querySelector<CodeEditor>('#source')?.value === expected, invalidCoreSource);
  await row('packages/utils/src/main.scm').click();
  // A failed browser save keeps the edited files in memory and reports the failure.
  await page.evaluate(() => { Storage.prototype.setItem = () => { throw new Error('quota'); }; });
  try {
    await replaceSourceDocument(page, '(define kept 42)', 'packages/utils/src/main.scm');
    await page.getByText('Not saved', { exact: true }).waitFor();
  } finally {
    await reloadWorkspace(page);
  }
  forgetSourceWorkspace(page, 'elm');
  console.log(JSON.stringify({ elmTarget: true, elmInput: true, files: paths, fileWorkspace: true, keyboardSelection: true, independentNavigation: true, focusRetainsSource: true, exactFileAndZipBytes: true, nativeDownloads, refusalRetainsIR: true, schemeEvaluation: true }));
}

// Exercise the same language/draft/evaluation boundary in browser and packaged CEF.
export async function moonbitWorkflow(page: Page, { nativeDownloads = true } = {}) {
  await showCompile(page);
  await setExplorer(page, true);
  const language = { selectOption: (value: 'scheme' | 'elm' | 'moonbit') => useSourceWorkspace(page, value) };
  const sourceEditor = page.getByRole('textbox', {name:'Source editor',exact:true});
  await language.selectOption('scheme');
  const schemeDraft = '; Retained Scheme draft\n(define answer 42)';
  await sourceEditor.fill(schemeDraft);
  await language.selectOption('moonbit');
  await openSample(page, 'MoonBit Boolean');
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('pub fn eligible'));
  assert.equal(await page.locator('#source').getAttribute('data-language'),'moonbit');
  await sourceFile(page, 'src/main.mbt').waitFor();
  assert.equal(await page.getByRole('button', {name:'New file…',exact:true}).isEnabled(), true, 'Per-file languages keep ordinary workspace files');
  const moonbitSource = '// Boolean model\npub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }';
  await sourceEditor.fill(moonbitSource);
  await sourceEditor.press('ControlOrMeta+End');
  await sourceEditor.press('Enter');
  await sourceEditor.pressSequentially('// retained edit');
  const edited = await page.locator('#source').evaluate(editor => (editor as CodeEditor).value);
  await language.selectOption('scheme');
  await page.waitForFunction(expected => document.querySelector<CodeEditor>('#source')?.value === expected, schemeDraft);
  await language.selectOption('moonbit');
  await page.waitForFunction(expected => document.querySelector<CodeEditor>('#source')?.value === expected, edited);
  await sourceEditor.press('ControlOrMeta+z');
  await page.waitForFunction(() => !document.querySelector<CodeEditor>('#source')?.value.includes('retained edit'));
  assert.ok(await page.locator('#source .cm-line span').count() > 0,'MoonBit input has highlighting');
  await setTarget(page, 'moonbit');
  // Before a compile, Evaluate in Explorer says what it needs; it only shows the model document.
  const evaluateEntry = await buildMenuItem(page,'Evaluate in Explorer');
  assert.match(await evaluateEntry.getAttribute('title') ?? '',/^Compile, then select a public function/);
  await closeBuildMenu(page);
  assert.equal(await buildAction(page,'Compile').count(),1,'Compile leads when the layout cannot run');
  assert.equal(await page.locator('.build-actions > .primary').count(),1,'One primary action leads the source header');
  assert.deepEqual(await buildMenuEntries(page),['Compile user', 'Evaluate in Explorer'],'The current project can compile and be explored');
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await showGenerated(page);
  const navigator = page.getByRole('navigation',{name:'Generated files',exact:true});
  await navigator.locator('.artifact-file').first().waitFor();
  const paths = await navigator.locator('.artifact-file').evaluateAll(items=>items.map(item=>item.getAttribute('aria-label')!));
  assert.deepEqual(paths,['root/moon.mod','root/moon.pkg','root/library.mbt','root/symbols.10n']);
  await navigator.getByRole('button',{name:'root/library.mbt',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|root/library.mbt');
  assert.equal(await page.locator('#output').getAttribute('data-language'),'moonbit');
  assert.ok(await page.locator('#output .cm-line span').count()>0,'Generated MoonBit has highlighting');
  const source = await page.locator('#output').evaluate(editor=>(editor as CodeEditor).value);
  const download=(button: string,name: string)=>downloadArtifact(page,button,name,nativeDownloads);
  const archive=unzipSync(await download('Download project','morphir-project.zip'));
  assert.deepEqual(Object.keys(archive),paths);
  assert.equal(strFromU8(archive['root/library.mbt']!),source);
  assert.deepEqual(Array.from(archive['root/symbols.10n']!.slice(0,4)),[224,1,0,234]);
  await navigator.getByRole('button',{name:'root/symbols.10n',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value.startsWith('Binary artifact: text preview unavailable.\n\nThis file is binary Ion'));
  // Right-click → View as Ion text decodes the file in the worker and shows it with Ion highlighting.
  await navigator.getByRole('button',{name:'root/symbols.10n',exact:true}).click({button:'right'});
  const fileMenu=page.getByRole('menu',{name:'Actions for root/symbols.10n',exact:true});
  await fileMenu.getByRole('menuitem',{name:'View as Ion text',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|root/symbols.10n|ion-text');
  assert.match(await page.locator('#output').evaluate(editor=>(editor as CodeEditor).value),/^morphir_moonbit_symbols::\{/);
  assert.equal(await page.locator('#output').getAttribute('data-language'),'ion');
  assert.match((await page.locator('.artifact-view').textContent())!,/^Decoded Ion text · \d+ values?$/);
  await page.getByRole('button',{name:'Show binary summary',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|root/symbols.10n');
  // The keyboard opens the same menu; View raw (hex) shows the version marker.
  await navigator.getByRole('button',{name:'root/symbols.10n',exact:true}).focus();
  await page.keyboard.press('Shift+F10');
  await fileMenu.waitFor();
  // Escape closes the menu and returns the focus to the file.
  await page.keyboard.press('Escape');
  await fileMenu.waitFor({state:'detached'});
  await page.waitForFunction(()=>document.activeElement?.id==='generated-file:root/symbols.10n');
  await page.keyboard.press('Shift+F10');
  await fileMenu.waitFor();
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value.startsWith('00000000  e0 01 00 ea'));
  // The palette offers the selected file.
  await page.getByRole('button',{name:'Command palette',exact:true}).click();
  const palette=page.getByRole('dialog',{name:'Command palette',exact:true});
  await palette.getByRole('combobox').fill('>View as Ion text');
  await page.waitForFunction(()=>document.querySelector('#palette-list [role="option"][aria-selected="true"]')?.getAttribute('aria-label')==='View as Ion text: root/symbols.10n');
  await palette.getByRole('combobox').press('Enter');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|root/symbols.10n|ion-text');
  if (process.env.MORPHIR_WORKBENCH_ION_SCREENSHOT) await page.screenshot({ path: process.env.MORPHIR_WORKBENCH_ION_SCREENSHOT });
  assert.equal(await page.locator('#output').getAttribute('aria-label'),'Decoded Ion text: root/symbols.10n','The editor names the decoded view');
  // Download from another file's menu leaves the selection and the decoded view.
  await navigator.getByRole('button',{name:'root/library.mbt',exact:true}).click({button:'right'});
  const libraryMenu=page.getByRole('menu',{name:'Actions for root/library.mbt',exact:true});
  assert.deepEqual(await downloadArtifact(page,'Download','library.mbt',nativeDownloads,()=>libraryMenu.getByRole('menuitem',{name:'Download',exact:true}).click()),archive['root/library.mbt']);
  assert.equal(await page.locator('#output').getAttribute('data-document'),'generated|root/symbols.10n|ion-text','A download from a menu keeps the view');
  await page.getByRole('button',{name:'Show binary summary',exact:true}).click();
  assert.deepEqual(await download('Download file','symbols.10n'),archive['root/symbols.10n']);
  const unit=strFromU8(await download('Download source unit','main.ion'));
  assert.match(unit,/morphir_pipeline/);assert.match(unit,/moonbit-model-stable-v1/);assert.match(unit,/eligible/);
  if(process.env.MORPHIR_WORKBENCH_MOONBIT_PROJECT){
    const directory=process.env.MORPHIR_WORKBENCH_MOONBIT_PROJECT;
    await mkdir(directory,{recursive:true});
    for(const path of paths)await writeFile(join(directory,path.replace(/^root\//, '')),archive[path]!);
    await writeFile(join(directory,'main.ion'),unit);
  }
  await showModel(page);
  await page.locator('.model-tree .tree-item').filter({hasText:'eligible'}).click();
  await page.getByRole('heading',{name:'eligible',exact:true}).waitFor();
  await page.getByRole('button',{name:'Input fields',exact:true}).click();
  const active=page.getByRole('combobox',{name:'active',exact:true});
  const vip=page.getByRole('combobox',{name:'vip',exact:true});
  await active.selectOption('true');await vip.selectOption('false');
  await page.getByRole('button',{name:'Evaluate',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
  await page.getByRole('button',{name:'Result JSON',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#evaluation-output')?.value.includes('"bool"'));
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(editor=>(editor as CodeEditor).value)),{type:'bool',value:true});
  await vip.selectOption('true');
  await page.getByRole('button',{name:'Evaluate',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
  await page.waitForFunction(()=>JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value ?? '{}').value === false);
  assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(editor=>(editor as CodeEditor).value)),{type:'bool',value:false});
  await showSource(page);
  await sourceEditor.fill('pub fn answer(x : Double) -> Double { x }');
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText:'moonbit_frontend.experimental_capability'}).waitFor();
  assert.equal(await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value),'pub fn answer(x : Double) -> Double { x }');
  await openSample(page, 'MoonBit Boolean');
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  const moonbitDraft=await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value);
  await page.getByRole('button',{name:'Worksheet',exact:true}).click();
  await page.getByRole('button',{name:'Run worksheet',exact:true}).waitFor();
  // The worksheet header names its language instead of offering the Language choice.
  assert.equal(await page.locator('.source-header').getByText('Scheme worksheet',{exact:true}).isVisible(),true,'Worksheet explicitly belongs to Scheme');
  assert.equal(await page.getByRole('combobox', { name: 'Language', exact: true }).count(), 0, 'Language belongs to project configuration');
  await sourceEditor.fill('(+ 20 22)');
  await page.getByRole('button',{name:'Run worksheet',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Worksheet finished'}).waitFor();
  await page.getByRole('button',{name:'Compile & inspect',exact:true}).click();
  await page.waitForFunction(expected=>document.querySelector<CodeEditor>('#source')?.value===expected,moonbitDraft);
  assert.equal(await page.locator('#source').getAttribute('data-language'), 'moonbit');
  await language.selectOption('scheme');
  await page.waitForFunction(expected=>document.querySelector<CodeEditor>('#source')?.value===expected,schemeDraft);
  await setTarget(page, 'scheme');
  if(process.env.MORPHIR_WORKBENCH_MOONBIT_SCREENSHOT){
    await openSample(page, 'MoonBit Boolean');
    await build(page, 'Compile');
    await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
    await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
    await navigator.getByRole('button',{name:'root/library.mbt',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|root/library.mbt');
    await page.screenshot({path:process.env.MORPHIR_WORKBENCH_MOONBIT_SCREENSHOT,fullPage:true});
    await language.selectOption('scheme');await setTarget(page, 'scheme');
  }
  // Replacing a MoonBit model selects the replacement model's runtime, even
  // when the prior model selected typed admission automatically or manually.
  await sourceEditor.fill('(define (double x) (* x 2))\n(double 21)');
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button',{name:'Morphir IR',exact:true}).click();
  await page.getByRole('textbox',{name:'Morphir IR',exact:true}).waitFor();
  const schemeIr=await page.locator('#output').evaluate(editor=>(editor as CodeEditor).value);
  await showModel(page);
  await page.locator('.model-tree .tree-item[title="user:main#main"]').click();
  assert.equal(await page.getByRole('button',{name:'Local Scheme',exact:true}).getAttribute('aria-pressed'),'true');
  await page.getByRole('button',{name:'Evaluate',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
  await page.getByRole('button',{name:'Printed',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#evaluation-output')?.value==='42');
  await page.getByRole('button',{name:'Typed invocation',exact:true}).click();
  const chooser=page.waitForEvent('filechooser');
  await page.getByRole('button',{name:'Import model',exact:true}).first().click();
  await(await chooser).setFiles({name:'scheme.json',mimeType:'application/json',buffer:Buffer.from(schemeIr)});
  await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
  // The import command clears selection when its fresh worker reply arrives.
  await page.waitForFunction(()=>document.querySelectorAll<HTMLElement>('.model-tree .tree-item[aria-pressed="true"]').length===0);
  await page.locator('.model-tree .tree-item[title="user:main#main"]').click();
  assert.equal(await page.getByRole('button',{name:'Local Scheme',exact:true}).getAttribute('aria-pressed'),'true');
  await showSource(page);
  console.log(JSON.stringify({moonbitInput:'moonbit-model-stable-v1',moonbitGeneration:true,languageDraftsAndUndo:true,worksheetIndependent:true,typedPublicEvaluation:true,richIonUnit:true,exactTextAndBinaryExports:true,replacementModelResetsRuntime:true,nativeDownloads}));
}

export async function libraryWorkflow(page: Page, {nativeDownloads = true} = {}) {
  await showCompile(page);
  await setExplorer(page, true);
  const language = { selectOption: (value: 'scheme' | 'elm' | 'moonbit') => useSourceWorkspace(page, value) };
  const profile = { selectOption: (value: string) => setSourceProfile(page, value), inputValue: () => currentSourceProfile(page) };
  const source=page.getByRole('textbox',{name:'Source editor',exact:true});
  await language.selectOption('moonbit');
  assert.equal(await page.locator('#source').getAttribute('data-language'), 'moonbit');
  await profile.selectOption('moonbit-model-experimental-v1');
  const seed='pub fn seed(active : Bool) -> Bool { active }';
  await source.fill(seed);
  // One project for each language: a profile change keeps the text.
  await profile.selectOption('moonbit-model-stable-v1');
  await page.waitForFunction(text=>document.querySelector<CodeEditor>('#source')?.value===text,seed);
  await openSample(page, 'MoonBit Boolean library');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#source')?.value.includes('pub fn welcome'));
  const library=await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value);
  await source.press('ControlOrMeta+End');await source.press('Enter');await source.pressSequentially('// library draft');
  const edited=await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value);
  await profile.selectOption('moonbit-model-experimental-v1');
  await page.waitForFunction(text=>document.querySelector<CodeEditor>('#source')?.value===text,edited);
  await profile.selectOption('moonbit-model-stable-v1');
  await page.waitForFunction(text=>document.querySelector<CodeEditor>('#source')?.value===text,edited);
  await source.press('ControlOrMeta+z');
  await page.waitForFunction(()=>!document.querySelector<CodeEditor>('#source')?.value.includes('library draft'));
  await source.fill(library);
  await runCommand(page, 'Open settings');
  await page.locator('.source-capabilities summary').focus();
  await page.keyboard.press('Enter');
  assert.equal(await page.locator('.source-capabilities').getAttribute('open'),'','Profile details open from the keyboard');
  await page.getByText('direct same-file calls', {exact:false}).first().waitFor();
  await page.getByRole('button', { name: 'Close settings', exact: true }).click();
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
  await page.getByText('Source changed · rerun',{exact:true}).waitFor({state:'hidden'});
  await showModel(page);
  const tree=page.locator('.model-tree .tree-item');
  await tree.filter({hasText:'eligible'}).click();
  assert.equal(await page.getByRole('button',{name:'Typed invocation',exact:true}).getAttribute('aria-pressed'),'true');
  await page.getByRole('combobox',{name:'activeUser',exact:true}).selectOption('true');
  await page.getByRole('combobox',{name:'vipMember',exact:true}).selectOption('false');
  async function evaluate(value: boolean) {
    await page.getByRole('button',{name:'Evaluate',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
    await page.getByRole('button',{name:'Result JSON',exact:true}).click();
    await page.waitForFunction(expected=>JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value ?? '{}').value===expected,value);
  }
  await evaluate(true);
  await page.getByRole('button',{name:'JSON inputs',exact:true}).click();
  await page.getByRole('textbox',{name:'Function arguments',exact:true}).fill('[{"type":"bool","value":true},{"type":"bool","value":true}]');
  await evaluate(false);
  await page.getByRole('button',{name:'Ion inputs',exact:true}).click();
  await page.getByRole('textbox',{name:'Function arguments',exact:true}).fill('[true, false]');
  await evaluate(true);
  await tree.filter({hasText:'welcome'}).click();
  await page.getByRole('heading',{name:'welcome',exact:true}).waitFor();
  await page.getByText('No arguments required',{exact:true}).waitFor();
  await evaluate(true);
  await tree.filter({hasText:'gate'}).click();
  await page.getByRole('button',{name:'Evaluate',exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button',{name:'Local Scheme',exact:true}).click();
  await page.getByRole('button',{name:'Evaluate',exact:true}).waitFor({state:'hidden'});
  await page.getByText('Only public functions can be evaluated.',{exact:true}).waitFor();
  await showSource(page);
  const rejected='pub fn recur(x : Bool) -> Bool { recur(x) }';
  await source.fill(rejected);
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText:'recursive_call'}).waitFor();
  assert.equal(await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value),rejected);
  await openSample(page, 'MoonBit Boolean library');
  assert.equal(await profile.inputValue(),'moonbit-model-stable-v1');
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
  await page.getByText('Source changed · rerun',{exact:true}).waitFor({state:'hidden'});
  await showGenerated(page);
  const navigator=page.getByRole('navigation',{name:'Generated files',exact:true});
  await navigator.waitFor();
  const paths=await navigator.locator('.artifact-file').evaluateAll(items=>items.map(item=>item.getAttribute('aria-label')!));
  assert.deepEqual(paths,['root/moon.mod','root/moon.pkg','root/library.mbt','root/symbols.10n']);
  const artifacts: Record<string,string>={};
  for(const path of paths.filter(path=>path!=='root/symbols.10n')) {
    await navigator.getByRole('button',{name:path,exact:true}).click();
    await page.waitForFunction(path=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|'+path,path);
    artifacts[path]=await page.locator('#output').evaluate(editor=>(editor as CodeEditor).value);
  }
  const archive=unzipSync(await downloadArtifact(page,'Download project','morphir-project.zip',nativeDownloads));
  assert.deepEqual(Object.keys(archive),paths);
  for(const [path,text] of Object.entries(artifacts))assert.equal(strFromU8(archive[path]!),text);
  await navigator.getByRole('button',{name:'root/symbols.10n',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|root/symbols.10n');
  assert.deepEqual(await downloadArtifact(page,'Download file','symbols.10n',nativeDownloads),archive['root/symbols.10n']);
  const unit=strFromU8(await downloadArtifact(page,'Download source unit','main.ion',nativeDownloads));
  assert.match(unit,/moonbit-model-stable-v1/);
  for(const name of ['gate','eligible','welcome','activeUser','vipMember'])assert.ok(unit.includes(name));
  if(process.env.MORPHIR_WORKBENCH_LIBRARY_PROJECT){
    const directory=process.env.MORPHIR_WORKBENCH_LIBRARY_PROJECT;
    await mkdir(directory,{recursive:true});
    for(const path of paths)await writeFile(join(directory,path.replace(/^root\//, '')),archive[path]!);
    await writeFile(join(directory,'main.ion'),unit);
  }
  await navigator.getByRole('button',{name:'root/library.mbt',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|root/library.mbt');
  // The file list is in the right sidebar, so the generated code takes the whole output panel.
  const output=await page.locator('.output-panel').boundingBox(), preview=await page.locator('.artifact-preview').boundingBox();
  assert.equal(await page.locator('.output-panel .artifact-files').count(),0,'The output panel holds no file list');
  assert.ok(preview!.width>=output!.width-2,`Generated code gets the whole output width (${output!.width}px panel, ${preview!.width}px code)`);
  if(process.env.MORPHIR_WORKBENCH_LIBRARY_SCREENSHOT)await page.screenshot({path:process.env.MORPHIR_WORKBENCH_LIBRARY_SCREENSHOT,fullPage:true});
  if(nativeDownloads) {
    const viewport=page.viewportSize();
    const leftOpen=await page.locator('#sidebar-primary').isVisible(), rightOpen=await page.locator('#sidebar-secondary').isVisible();
    await page.setViewportSize({width:390,height:844});
    // Narrow sidebars cover the documents: close both to reach the source header.
    await setExplorer(page,false);
    await setRightSidebar(page,false);
    await runCommand(page, 'Open settings');
    await page.locator('.source-capabilities summary').click();
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Profile controls fit a narrow screen');
    if(process.env.MORPHIR_WORKBENCH_LIBRARY_SCREENSHOT)await page.screenshot({path:process.env.MORPHIR_WORKBENCH_LIBRARY_SCREENSHOT.replace('.png','-mobile.png'),fullPage:true});
    await page.getByRole('button', { name: 'Close settings', exact: true }).click();
    await page.setViewportSize(viewport!);
    await setExplorer(page,leftOpen);
    await setRightSidebar(page,rightOpen);
  }
  await openSample(page, 'MoonBit Boolean');
  assert.equal(await currentSourceProfile(page), 'moonbit-model-stable-v1');
  assert.equal(await profile.inputValue(),'moonbit-model-stable-v1');
  console.log(JSON.stringify({libraryProfile:true,profileDraftsAndUndo:true,publicMultiEntryEvaluation:true,fieldsJsonIon:true,privateEntriesBlocked:true,recursionRecovery:true}));
}

async function downloadArtifact(page: Page, button: string, name: string, nativeDownloads: boolean, click: () => Promise<void> = ()=>page.getByRole('button',{name:button,exact:true}).click()) {
    if (nativeDownloads) {
      const pending=page.waitForEvent('download');
      await click();
      const download=await pending;
      assert.equal(download.suggestedFilename(),name);
      return new Uint8Array(await readFile(await download.path()));
    }
    await page.evaluate(()=>{
      window.artifactDownload=null;
      document.addEventListener('click',async function capture(event){
        const link=(event.target as Element).closest<HTMLAnchorElement>('a[download]');if(!link)return;
        event.preventDefault();document.removeEventListener('click',capture,true);
        window.artifactDownload={name:link.download,bytes:Array.from(new Uint8Array(await(await fetch(link.href)).arrayBuffer()))};
      },true);
    });
    await click();
    await page.waitForFunction(()=>window.artifactDownload!==null);
    const result=await page.evaluate(()=>window.artifactDownload);
    assert.equal(result!.name,name);return new Uint8Array(result!.bytes);
  }

export async function stringWorkflow(page: Page) {
  await showCompile(page);
  await openSample(page, 'MoonBit String library');
  assert.equal(await currentSourceProfile(page),'moonbit-model-stable-v1');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#source')?.value.includes('pub fn greet(name : String)'));
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
  await showModel(page);
  const tree=page.locator('.model-tree .tree-item');
  await tree.filter({hasText:'welcome'}).click();
  await page.getByRole('button',{name:'Typed invocation',exact:true}).click();
  await page.getByRole('button',{name:'JSON inputs',exact:true}).click();
  for(const [enabled,expected] of [[true,'Hello, 😀'],[false,'']] as const) {
    await page.getByRole('textbox',{name:'Function arguments',exact:true}).fill(JSON.stringify([{type:'text',units:[55357,56832]},{type:'bool',value:enabled}]));
    await page.getByRole('button',{name:'Evaluate',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
    await page.getByRole('button',{name:'Result JSON',exact:true}).click();
    await page.waitForFunction(text=>{
      const result=JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value ?? '{}');
      return result.type==='text'&&JSON.stringify(result.units)===JSON.stringify(Array.from({length:text.length},(_,i)=>text.charCodeAt(i)));
    },expected);
  }
  await tree.filter({hasText:'is_morphir'}).click();
  await page.getByRole('button',{name:'JSON inputs',exact:true}).click();
  await page.getByRole('textbox',{name:'Function arguments',exact:true}).fill('[{"type":"text","units":[77,111,114,112,104,105,114]}]');
  await page.getByRole('button',{name:'Evaluate',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
  await page.getByRole('button',{name:'Result JSON',exact:true}).click();
  await page.waitForFunction(()=>JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value ?? '{}').value===true);
  await tree.filter({hasText:'mentions_morphir'}).click();
  await page.getByRole('button',{name:'JSON inputs',exact:true}).click();
  for(const [text,expected] of [['Hello, Morphir',true],['',false],['Hello, 😀',false]] as const) {
    await page.getByRole('textbox',{name:'Function arguments',exact:true}).fill(JSON.stringify([{type:'text',units:Array.from({length:text.length},(_,i)=>text.charCodeAt(i))}]));
    await page.getByRole('button',{name:'Evaluate',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
    await page.getByRole('button',{name:'Result JSON',exact:true}).click();
    await page.waitForFunction(value=>JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value ?? '{}').value===value,expected);
  }
  await showSource(page);
  await showGenerated(page);
  const navigator=page.getByRole('navigation',{name:'Generated files',exact:true});
  await navigator.getByRole('button',{name:'root/library.mbt',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value.includes('@source_string.require_valid'));
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value.includes('@string.contains('));
  console.log(JSON.stringify({stringProfile:true,stringGreeting:true,booleanCondition:true,exactEquality:true,stringPredicates:true,generatedGuards:true}));
}

export async function supportedWorkflow(page: Page) {
  await showCompile(page);
  await openSample(page,'MoonBit library');
  assert.equal(await currentSourceProfile(page),'moonbit-model-stable-v1');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#source')?.value.includes('choose_for'));
  await build(page, 'Compile');
  await page.getByRole('status').filter({hasText: /Model ready|Compiled [1-9]\d*\/[1-9]\d* projects/}).waitFor();
  await showModel(page);
  await page.locator('.model-tree .tree-item').filter({hasText:'choose_for'}).click();
  await page.getByRole('button',{name:'Typed invocation',exact:true}).click();
  await page.getByRole('button',{name:'JSON inputs',exact:true}).click();
  const bounded=(value: string)=>({type:'custom',owner:'morphir/SDK:int#int-32',tag:'morphir/SDK:int#int32',items:[{type:'int',value}]});
  for(const [enabled,expected] of [[true,'-2147483648'],[false,'2147483647']] as const) {
    await page.getByRole('textbox',{name:'Function arguments',exact:true}).fill(JSON.stringify([{type:'text',units:[77,111,114,112,104,105,114]},{type:'bool',value:enabled},bounded('-2147483648'),bounded('2147483647')]));
    await page.getByRole('button',{name:'Evaluate',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
    await page.getByRole('button',{name:'Result JSON',exact:true}).click();
    await page.waitForFunction(value=>{
      const result=JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value??'{}');
      return result.type==='custom'&&result.owner==='morphir/SDK:int#int-32'&&result.items?.[0]?.value===value;
    },expected);
  }
  await page.locator('.model-tree .tree-item').filter({hasText:'precedes'}).click();
  await page.getByRole('textbox',{name:'Function arguments',exact:true}).fill(JSON.stringify([{type:'text',units:[98]},{type:'text',units:[97,97]}]));
  await page.getByRole('button',{name:'Evaluate',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
  await page.waitForFunction(()=>{
    const result=JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value??'{}');
    return result.type==='bool'&&result.value===true;
  });
  const text=(value: string)=>({type:'text',units:Array.from({length:value.length},(_,i)=>value.charCodeAt(i))});
  const invoke=async(name: string,args: unknown[],expected: unknown)=>{
    await page.locator('.model-tree .tree-item').filter({hasText:name}).click();
    if(args.length) {
      await page.getByRole('button',{name:'JSON inputs',exact:true}).click();
      await page.getByRole('textbox',{name:'Function arguments',exact:true}).fill(JSON.stringify(args));
    }
    await page.getByRole('button',{name:'Evaluate',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Function evaluated'}).waitFor();
    await page.getByRole('button',{name:'Result JSON',exact:true}).click();
    await page.waitForFunction(expected=>{
      const actual=JSON.parse(document.querySelector<CodeEditor>('#evaluation-output')?.value??'{}');
      const normalize=(_key: string,value: unknown)=>value&&typeof value==='object'&&!Array.isArray(value)
        ?Object.fromEntries(Object.entries(value).sort(([a],[b])=>a.localeCompare(b))):value;
      return JSON.stringify(actual,normalize)===JSON.stringify(expected,normalize);
    },expected);
  };
  for(const [a,b,expected] of [['b','aa','before'],['aa','b','after'],['😀','😀','same']] as const)
    await invoke('compare_names',[text(a),text(b)],text(expected));
  for(const [name,expected] of [['b',true],['a',true],['aaa',false]] as const)
    await invoke('in_name_range',[text(name),text('a'),text('aa')],{type:'bool',value:expected});
  for(const [name,blocked,expected] of [['Morphir',false,true],['Morphir',true,false],['',false,false]] as const)
    await invoke('should_welcome',[text(name),{type:'bool',value:true},{type:'bool',value:blocked}],{type:'bool',value:expected});
  for(const [a,b,expected] of [['b','aa','-2147483648'],['aa','b','2147483647'],['b','b','-2147483648']] as const)
    await invoke('choose_earlier',[text(a),text(b),bounded('-2147483648'),bounded('2147483647')],bounded(expected));
  await invoke('unicode_sample',[],text('😀é'));
  await showSource(page);
  await showGenerated(page);
  const navigator=page.getByRole('navigation',{name:'Generated files',exact:true});
  await navigator.getByRole('button',{name:'root/library.mbt',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value.includes('/// Build a greeting while preserving the supplied name.'));
  console.log(JSON.stringify({supportedMoonbitProfile:true,mixedBoolStringInt32:true,checkedInt32Results:true,shortlexOrder:true,canonicalLibraryProfile:true,expandedExample:true,sourceDocs:true}));
}
