import type { Page, Locator, Request, Response, WebSocket, Browser, BrowserContext } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { unzipSync, strFromU8 } from 'fflate';

// The same generated-file component and worker run in Chromium and packaged CEF.
export async function elmWorkflow(page: Page, { nativeDownloads = true } = {}) {
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('button', { name: 'Compile & inspect', exact: true }).click();
  await page.getByRole('button', { name: 'Elm constant', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<HTMLSelectElement>('select[aria-label="Target"]')?.value === 'elm');
  const target = page.getByRole('combobox', { name: 'Target', exact: true });
  assert.equal(await target.inputValue(), 'elm');
  const inputs = await page.getByRole('combobox', { name: 'Language', exact: true }).locator('option').evaluateAll(items => items.map(item => (item as HTMLOptionElement).value));
  assert.ok(inputs.includes('elm'), 'The catalog offers the Elm frontend');
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('42');
  await page.getByRole('button', { name: 'Compile & run (Scheme)', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  assert.equal(await page.locator('.run-value strong').textContent(), '42');
  await page.getByRole('button', { name: 'Elm constant', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('(define answer 42)'));
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  const ir = JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value));
  assert.ok(ir.distribution);
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  const selector = page.getByRole('navigation', { name: 'Generated files', exact: true });
  await selector.waitFor();
  const paths = await selector.locator('.artifact-file').evaluateAll(items => items.map(item => item.getAttribute('aria-label')!));
  assert.deepEqual(paths, ['src/User/Main.elm', 'elm.json', 'morphir.json']);
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
  assert.equal(JSON.parse(artifacts['elm.json']!).type, 'package');
  assert.ok(JSON.parse(artifacts['morphir.json']!).name);
  await selector.getByRole('button', { name: 'src/User/Main.elm', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|src/User/Main.elm');
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
      await mkdir(join(directory, path, '..'), { recursive: true });
      await writeFile(join(directory, path), unpacked[path]!);
    }
  }
  await target.selectOption('scheme');
  assert.equal(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value), artifacts[paths[0]!], 'Target changes retain the previous generated files');
  await target.selectOption('elm');
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('9223372036854775808');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'elm.int_literal' }).waitFor();
  await page.getByText(/Elm generation failed: elm.int_literal at user:main#main/).first().waitFor();
  assert.equal(await selector.count(), 0);
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  assert.ok(JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value)).distribution, 'Backend refusal retains the compiled model');
  await page.getByRole('button', { name: 'Elm constant', exact: true }).click();
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  await selector.waitFor();
  assert.equal(await selector.locator('.artifact-file').count(), 3, 'Generation recovers after refusal');
  await selector.getByRole('button', { name: 'Collapse src/User/', exact: true }).click();
  await selector.getByRole('button', { name: 'Expand src/User/', exact: true }).waitFor();
  assert.equal(await selector.getByRole('button', { name: 'src/User/Main.elm', exact: true }).isVisible(), false);
  await selector.getByRole('button', { name: 'Expand src/User/', exact: true }).focus();
  await page.keyboard.press('Enter');
  await selector.getByRole('button', { name: 'src/User/Main.elm', exact: true }).waitFor();
  await selector.getByRole('button', { name: 'elm.json', exact: true }).focus();
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|elm.json');
  assert.equal(await selector.getByRole('button', { name: 'elm.json', exact: true }).getAttribute('aria-pressed'), 'true');
  assert.equal(await page.locator('.artifact-breadcrumb').textContent(), 'elm.json');
  await page.getByRole('button', { name: 'Hide generated files', exact: true }).click();
  await page.getByRole('button', { name: 'Show generated files', exact: true }).waitFor();
  assert.equal(await selector.isVisible(), false);
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  await page.getByRole('button', { name: 'Show generated files', exact: true }).click();
  await selector.waitFor();
  assert.equal(await selector.getByRole('button', { name: 'elm.json', exact: true }).getAttribute('aria-pressed'), 'true', 'IR navigation retains the selected file');
  const wasCollapsed = await page.locator('.workbench').evaluate(element => element.classList.contains('collapsed'));
  const controlIcon = page.locator('.artifact-toolbar-title .artifact-icon');
  const iconTransform = await controlIcon.evaluate(element => getComputedStyle(element).transform);
  await page.getByRole('button', { name: 'Toggle sidebar', exact: true }).click();
  await page.waitForFunction(previous => document.querySelector<HTMLElement>('.workbench')!.classList.contains('collapsed') !== previous, wasCollapsed);
  assert.equal(await controlIcon.evaluate(element => getComputedStyle(element).transform), iconTransform, 'Global sidebar changes do not reverse the generated-file control');
  assert.equal(await page.getByRole('button', { name: 'Hide generated files', exact: true }).getAttribute('aria-expanded'), 'true');
  await page.getByRole('button', { name: 'Toggle sidebar', exact: true }).click();
  await page.waitForFunction(previous => document.querySelector<HTMLElement>('.workbench')!.classList.contains('collapsed') === previous, wasCollapsed);
  const source = await page.locator('#source').evaluate(editor => (editor as CodeEditor).value);
  await page.getByRole('button', { name: 'Expand generated files', exact: true }).click();
  await page.locator('.editor-grid.output-expanded').waitFor();
  assert.equal(await page.locator('.source-panel').isVisible(), false);
  assert.equal(await page.locator('#source').evaluate(editor => (editor as CodeEditor).value), source, 'Focus layout retains the mounted source editor');
  if (process.env.MORPHIR_WORKBENCH_OUTPUT_FOCUS_SCREENSHOT) await page.screenshot({ path: process.env.MORPHIR_WORKBENCH_OUTPUT_FOCUS_SCREENSHOT, fullPage: true });
  await page.getByRole('button', { name: 'Restore split view', exact: true }).click();
  await page.locator('.source-panel').waitFor();
  assert.equal(await page.locator('#source').evaluate(editor => (editor as CodeEditor).value), source);
  await selector.getByRole('button', { name: 'src/User/Main.elm', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|src/User/Main.elm');
  if (process.env.MORPHIR_WORKBENCH_ELM_SCREENSHOT) await page.screenshot({ path: process.env.MORPHIR_WORKBENCH_ELM_SCREENSHOT, fullPage: true });
  const viewport = page.viewportSize();
  if (viewport) {
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'Generated files fit mobile width');
    await page.getByRole('button', { name: 'Toggle sidebar' }).click();
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await selector.getByRole('button', { name: 'elm.json', exact: true }).click();
    await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.dataset.document === 'generated|elm.json');
    assert.equal(JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value)).type, 'package');
    await page.setViewportSize(viewport);
  }
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('elm');
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('module Workbench.Main'));
  await page.getByRole('combobox', { name: 'Target', exact: true }).selectOption('moonbit');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#output')?.value.includes('"distribution"'));
  const elmIr = JSON.parse(await page.locator('#output').evaluate(editor => (editor as CodeEditor).value));
  assert.ok(elmIr.distribution, 'The Elm module compiles to IR in the browser');
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('scheme');
  await page.getByRole('combobox', { name: 'Target', exact: true }).selectOption('elm');
  console.log(JSON.stringify({ elmTarget: true, elmInput: true, files: paths, fileWorkspace: true, keyboardSelection: true, independentNavigation: true, focusRetainsSource: true, exactFileAndZipBytes: true, nativeDownloads, refusalRetainsIR: true, schemeEvaluation: true }));
}

// Exercise the same language/draft/evaluation boundary in browser and packaged CEF.
export async function moonbitWorkflow(page: Page, { nativeDownloads = true } = {}) {
  await page.getByRole('button', {name:'Try Morphir',exact:true}).click();
  await page.getByRole('button', {name:'Compile & inspect',exact:true}).click();
  if (!await page.locator('#context-navigation').isVisible()) await page.getByRole('button',{name:'Toggle sidebar',exact:true}).click();
  const language = page.getByRole('combobox', {name:'Language',exact:true});
  const target = page.getByRole('combobox', {name:'Target',exact:true});
  const sourceEditor = page.getByRole('textbox', {name:'Source editor',exact:true});
  await language.selectOption('scheme');
  const schemeDraft = '; Retained Scheme draft\n(define answer 42)';
  await sourceEditor.fill(schemeDraft);
  await language.selectOption('moonbit');
  await page.waitForFunction(() => document.querySelector<CodeEditor>('#source')?.value.includes('pub fn eligible'));
  assert.equal(await page.locator('#source').getAttribute('data-language'),'moonbit');
  await page.getByText('main.mbt', {exact:true}).waitFor();
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
  await target.selectOption('moonbit');
  assert.equal(await page.getByRole('button',{name:'Evaluate in Explorer',exact:true}).isEnabled(),false);
  assert.deepEqual(await page.locator('.toolbar-actions .primary:visible').allTextContents(),['Compile'],'Compile leads when the layout cannot run');
  await page.getByRole('button',{name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Model ready'}).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button',{name:'Generated',exact:true}).click();
  const navigator = page.getByRole('navigation',{name:'Generated files',exact:true});
  await navigator.locator('.artifact-file').first().waitFor();
  const paths = await navigator.locator('.artifact-file').evaluateAll(items=>items.map(item=>item.getAttribute('aria-label')!));
  assert.deepEqual(paths,['moon.mod','moon.pkg','library.mbt','symbols.10n']);
  await navigator.getByRole('button',{name:'library.mbt',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|library.mbt');
  assert.equal(await page.locator('#output').getAttribute('data-language'),'moonbit');
  assert.ok(await page.locator('#output .cm-line span').count()>0,'Generated MoonBit has highlighting');
  const source = await page.locator('#output').evaluate(editor=>(editor as CodeEditor).value);
  const download=(button: string,name: string)=>downloadArtifact(page,button,name,nativeDownloads);
  const archive=unzipSync(await download('Download project','morphir-project.zip'));
  assert.deepEqual(Object.keys(archive),paths);
  assert.equal(strFromU8(archive['library.mbt']!),source);
  assert.deepEqual(Array.from(archive['symbols.10n']!.slice(0,4)),[224,1,0,234]);
  await navigator.getByRole('button',{name:'symbols.10n',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.value==='Binary artifact: text preview unavailable');
  assert.deepEqual(await download('Download file','symbols.10n'),archive['symbols.10n']);
  const unit=strFromU8(await download('Download source unit','main.ion'));
  assert.match(unit,/morphir_pipeline/);assert.match(unit,/moonbit-model-bool-v1/);assert.match(unit,/eligible/);
  if(process.env.MORPHIR_WORKBENCH_MOONBIT_PROJECT){
    const directory=process.env.MORPHIR_WORKBENCH_MOONBIT_PROJECT;
    await mkdir(directory,{recursive:true});
    for(const path of paths)await writeFile(join(directory,path),archive[path]!);
    await writeFile(join(directory,'main.ion'),unit);
  }
  await page.getByRole('button',{name:'Model Explorer',exact:true}).click();
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
  await page.getByRole('button',{name:'Try Morphir',exact:true}).click();
  await sourceEditor.fill('pub fn answer(x : Int) -> Int { x }');
  await page.getByRole('button',{name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'moonbit_frontend.unsupported_type'}).waitFor();
  assert.equal(await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value),'pub fn answer(x : Int) -> Int { x }');
  await page.getByRole('button',{name:'MoonBit Boolean',exact:true}).click();
  await page.getByRole('button',{name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Model ready'}).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  const moonbitDraft=await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value);
  await page.getByRole('button',{name:'Worksheet',exact:true}).click();
  await page.getByRole('button',{name:'Run worksheet',exact:true}).waitFor();
  assert.equal(await language.inputValue(),'scheme','Worksheet explicitly belongs to Scheme');
  await sourceEditor.fill('(+ 20 22)');
  await page.getByRole('button',{name:'Run worksheet',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Worksheet finished'}).waitFor();
  await page.getByRole('button',{name:'Compile & inspect',exact:true}).click();
  await page.waitForFunction(expected=>document.querySelector<CodeEditor>('#source')?.value===expected,moonbitDraft);
  assert.equal(await language.inputValue(),'moonbit');
  await language.selectOption('scheme');
  await page.waitForFunction(expected=>document.querySelector<CodeEditor>('#source')?.value===expected,schemeDraft);
  await target.selectOption('scheme');
  if(process.env.MORPHIR_WORKBENCH_MOONBIT_SCREENSHOT){
    await page.getByRole('button',{name:'MoonBit Boolean',exact:true}).click();
    await page.getByRole('button',{name:'Compile',exact:true}).click();
    await page.getByRole('status').filter({hasText:'Model ready'}).waitFor();
    await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
    await navigator.getByRole('button',{name:'library.mbt',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|library.mbt');
    await page.screenshot({path:process.env.MORPHIR_WORKBENCH_MOONBIT_SCREENSHOT,fullPage:true});
    await language.selectOption('scheme');await target.selectOption('scheme');
  }
  // Replacing a MoonBit model selects the replacement model's runtime, even
  // when the prior model selected typed admission automatically or manually.
  await sourceEditor.fill('(define (double x) (* x 2))\n(double 21)');
  await page.getByRole('button',{name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Model ready'}).waitFor();
  await page.getByText('Source changed · rerun', {exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button',{name:'Morphir IR',exact:true}).click();
  await page.getByRole('textbox',{name:'Morphir IR',exact:true}).waitFor();
  const schemeIr=await page.locator('#output').evaluate(editor=>(editor as CodeEditor).value);
  await page.getByRole('button',{name:'Model Explorer',exact:true}).click();
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
  await page.getByRole('status').filter({hasText:'Model ready'}).waitFor();
  // The import command clears selection when its fresh worker reply arrives.
  await page.waitForFunction(()=>document.querySelectorAll<HTMLElement>('.model-tree .tree-item[aria-pressed="true"]').length===0);
  await page.locator('.model-tree .tree-item[title="user:main#main"]').click();
  assert.equal(await page.getByRole('button',{name:'Local Scheme',exact:true}).getAttribute('aria-pressed'),'true');
  await page.getByRole('button',{name:'Try Morphir',exact:true}).click();
  console.log(JSON.stringify({moonbitInput:'moonbit-model-bool-v1',moonbitGeneration:true,languageDraftsAndUndo:true,worksheetIndependent:true,typedPublicEvaluation:true,richIonUnit:true,exactTextAndBinaryExports:true,replacementModelResetsRuntime:true,nativeDownloads}));
}

export async function libraryWorkflow(page: Page, {nativeDownloads = true} = {}) {
  await page.getByRole('button', {name:'Try Morphir',exact:true}).click();
  await page.getByRole('button', {name:'Compile & inspect',exact:true}).click();
  if (!await page.locator('#context-navigation').isVisible()) await page.getByRole('button',{name:'Toggle sidebar',exact:true}).click();
  const language=page.getByRole('combobox',{name:'Language',exact:true});
  const profile=page.getByRole('combobox',{name:'Source profile',exact:true});
  const source=page.getByRole('textbox',{name:'Source editor',exact:true});
  await language.selectOption('moonbit');
  assert.equal(await language.locator('option[value="moonbit"]').count(),1);
  await profile.selectOption('moonbit-model-bool-v1');
  const seed='pub fn seed(active : Bool) -> Bool { active }';
  await source.fill(seed);
  await profile.selectOption('moonbit-model-bool-library-v1');
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#source')?.value.includes('pub fn welcome'));
  const library=await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value);
  await source.press('ControlOrMeta+End');await source.press('Enter');await source.pressSequentially('// library draft');
  const edited=await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value);
  await profile.selectOption('moonbit-model-bool-v1');
  await page.waitForFunction(text=>document.querySelector<CodeEditor>('#source')?.value===text,seed);
  await profile.selectOption('moonbit-model-bool-library-v1');
  await page.waitForFunction(text=>document.querySelector<CodeEditor>('#source')?.value===text,edited);
  await source.press('ControlOrMeta+z');
  await page.waitForFunction(()=>!document.querySelector<CodeEditor>('#source')?.value.includes('library draft'));
  await source.fill(library);
  await page.locator('.source-capabilities summary').focus();
  await page.keyboard.press('Enter');
  assert.equal(await page.locator('.source-capabilities').getAttribute('open'),'','Profile details open from the keyboard');
  await page.getByText('Direct same-file calls, including forward and zero-input calls', {exact:false}).first().waitFor();
  await page.getByRole('button',{name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Model ready'}).waitFor();
  await page.getByText('Source changed · rerun',{exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button',{name:'Model Explorer',exact:true}).click();
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
  await page.getByRole('button',{name:'Try Morphir',exact:true}).click();
  const rejected='pub fn recur(x : Bool) -> Bool { recur(x) }';
  await source.fill(rejected);
  await page.getByRole('button',{name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'recursive_call'}).waitFor();
  assert.equal(await page.locator('#source').evaluate(editor=>(editor as CodeEditor).value),rejected);
  await page.getByRole('button',{name:'MoonBit library',exact:true}).click();
  assert.equal(await profile.inputValue(),'moonbit-model-bool-library-v1');
  await page.getByRole('button',{name:'Compile',exact:true}).click();
  await page.getByRole('status').filter({hasText:'Model ready'}).waitFor();
  await page.getByText('Source changed · rerun',{exact:true}).waitFor({state:'hidden'});
  await page.getByRole('button',{name:'Generated',exact:true}).click();
  const navigator=page.getByRole('navigation',{name:'Generated files',exact:true});
  await navigator.waitFor();
  const paths=await navigator.locator('.artifact-file').evaluateAll(items=>items.map(item=>item.getAttribute('aria-label')!));
  assert.deepEqual(paths,['moon.mod','moon.pkg','library.mbt','symbols.10n']);
  const artifacts: Record<string,string>={};
  for(const path of paths.filter(path=>path!=='symbols.10n')) {
    await navigator.getByRole('button',{name:path,exact:true}).click();
    await page.waitForFunction(path=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|'+path,path);
    artifacts[path]=await page.locator('#output').evaluate(editor=>(editor as CodeEditor).value);
  }
  const archive=unzipSync(await downloadArtifact(page,'Download project','morphir-project.zip',nativeDownloads));
  assert.deepEqual(Object.keys(archive),paths);
  for(const [path,text] of Object.entries(artifacts))assert.equal(strFromU8(archive[path]!),text);
  await navigator.getByRole('button',{name:'symbols.10n',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|symbols.10n');
  assert.deepEqual(await downloadArtifact(page,'Download file','symbols.10n',nativeDownloads),archive['symbols.10n']);
  const unit=strFromU8(await downloadArtifact(page,'Download source unit','main.ion',nativeDownloads));
  assert.match(unit,/moonbit-model-bool-library-v1/);
  for(const name of ['gate','eligible','welcome','activeUser','vipMember'])assert.ok(unit.includes(name));
  if(process.env.MORPHIR_WORKBENCH_LIBRARY_PROJECT){
    const directory=process.env.MORPHIR_WORKBENCH_LIBRARY_PROJECT;
    await mkdir(directory,{recursive:true});
    for(const path of paths)await writeFile(join(directory,path),archive[path]!);
    await writeFile(join(directory,'main.ion'),unit);
  }
  await navigator.getByRole('button',{name:'library.mbt',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<CodeEditor>('#output')?.dataset.document==='generated|library.mbt');
  const files=await navigator.boundingBox(), preview=await page.locator('.artifact-preview').boundingBox();
  assert.ok(preview!.width>=2.75*files!.width,`Generated code gets most of the output width (${files!.width}px list, ${preview!.width}px code)`);
  if(process.env.MORPHIR_WORKBENCH_LIBRARY_SCREENSHOT)await page.screenshot({path:process.env.MORPHIR_WORKBENCH_LIBRARY_SCREENSHOT,fullPage:true});
  if(nativeDownloads) {
    const viewport=page.viewportSize();
    await page.setViewportSize({width:390,height:844});
    await page.getByRole('button',{name:'Toggle sidebar',exact:true}).click();
    await page.locator('.workbench.collapsed').waitFor();
    await page.locator('.source-capabilities summary').click();
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Profile controls fit a narrow screen');
    if(process.env.MORPHIR_WORKBENCH_LIBRARY_SCREENSHOT)await page.screenshot({path:process.env.MORPHIR_WORKBENCH_LIBRARY_SCREENSHOT.replace('.png','-mobile.png'),fullPage:true});
    await page.setViewportSize(viewport!);
    await page.getByRole('button',{name:'Toggle sidebar',exact:true}).click();
    await page.locator('.workbench:not(.collapsed)').waitFor();
  }
  await page.getByRole('button',{name:'MoonBit Boolean',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector<HTMLSelectElement>('select[aria-label="Source profile"]')?.value==='moonbit-model-bool-v1');
  assert.equal(await profile.inputValue(),'moonbit-model-bool-v1');
  console.log(JSON.stringify({libraryProfile:true,profileDraftsAndUndo:true,publicMultiEntryEvaluation:true,fieldsJsonIon:true,privateEntriesBlocked:true,recursionRecovery:true}));
}

async function downloadArtifact(page: Page, button: string, name: string, nativeDownloads: boolean) {
    if (nativeDownloads) {
      const pending=page.waitForEvent('download');
      await page.getByRole('button',{name:button,exact:true}).click();
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
    await page.getByRole('button',{name:button,exact:true}).click();
    await page.waitForFunction(()=>window.artifactDownload!==null);
    const result=await page.evaluate(()=>window.artifactDownload);
    assert.equal(result!.name,name);return new Uint8Array(result!.bytes);
  }
