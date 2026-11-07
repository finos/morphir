import type { AddressInfo } from 'node:net';
import type { createBrowserToolchain as BrowserFactory } from '../browser.mjs';
import type * as Assembly from '../assembly.mjs';
import type * as Artifacts from '../artifacts.mjs';
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {chromium} from "playwright";
import {preludeBundle} from "./prelude.mts";

const root = new URL("../",import.meta.url);
const server=createServer(async (req,res)=>{
  try {
    const file=new URL('.'+req.url,root);
    if (!file.href.startsWith(root.href)) throw new Error("Invalid path");
    const content=await readFile(fileURLToPath(file));
    res.setHeader("Content-Type","text/javascript");res.end(content);
  } catch {res.statusCode=404;res.end();}
});
await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
let browser;
try {
  browser=await chromium.launch({headless:true});
  const page=await browser.newPage();
  await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/index.mjs`);
  // The page host supplies the pinned prelude. The package ships no core assets.
  const preludes=Object.fromEntries((['wasm','wasm-gc'] as const).map(t=>{const b=preludeBundle(t);return [t,{mi:[...b.interface],core:[...b.core]}];}));
  const result=await page.evaluate(async(preludes)=>{
    const {createBrowserToolchain}=await import(new URL('/browser.mjs', location.href).href) as { createBrowserToolchain: typeof BrowserFactory };
    const tools=createBrowserToolchain();
    try {
      const {pinPackage,assemblyIdentity,executeAssembly}=await import(new URL('/assembly.mjs',location.href).href) as typeof Assembly;
      const info=await tools.request({operation:'info'});
      const preludeName='moonbitlang/core/prelude';
      const preludeInterface=(target:'wasm'|'wasm-gc')=>new Uint8Array(preludes[target]!.mi);
      const blank={compilerVersion:info.compilerVersion,coreSha256:'0'.repeat(64),sdkSha256:'0'.repeat(64)};
      const preludeRaw={name:preludeName,role:'core' as const,dependencies:[],input:{kind:'prebuilt' as const,interface:preludeInterface('wasm'),
        core:new Uint8Array(preludes.wasm!.core),identity:blank,target:'wasm' as const,optimization:'optimized' as const}};
      const prelude=await pinPackage({...preludeRaw,input:{...preludeRaw.input,identity:await assemblyIdentity(info.compilerVersion,[preludeRaw])}});
      const missing=await tools.request({operation:'compile',files:[['main.mbt','pub fn answer() -> Int { 42 }']],exports:['answer']}).then(()=>'',e=>e instanceof Error ? e.name : String(e));
      const dependency=await pinPackage({name:'browser/library',role:'library',dependencies:[{name:'prelude',pin:prelude.pin}],input:{kind:'source',files:[
        ['lib.mbt','pub fn twice(n : Int32) -> Int32 { n * 2 }']]}});
      const root=await pinPackage({name:'browser/main',role:'library',dependencies:[{name:'math',pin:dependency.pin}],input:{kind:'source',files:[
        ['main.mbt','pub fn answer() -> Int32 { @math.twice(21) }']]}});
      const packages=[root,dependency,prelude];
      const assembled=await executeAssembly(tools,{root:root.pin,packages,identity:await assemblyIdentity(info.compilerVersion,packages),
        target:'wasm',exports:['answer']});
      const assemblyValue=(await tools.request({operation:'run',artifact:assembled.artifact,export:'answer'})).value;
      const {prepareArtifact,loadArtifact}=await import(new URL('/artifacts.mjs',location.href).href) as typeof Artifacts;
      const profile={id:'browser/scalar-v1',sha256:'a'.repeat(64)};
      const saved=await prepareArtifact(assembled,profile,{metadataIon:'source::123456789012345678901234567890'});
      const loaded=await loadArtifact(saved,{targets:['wasm'],profiles:[profile],encodings:['ion']});
      const persistedValue=loaded.invoke('answer');loaded.dispose();
      if (!loaded.metadataIon.includes('source::123456789012345678901234567890')) throw new Error('Ion metadata changed');
      const results=[];
      for (const target of ['wasm','wasm-gc'] as const) {
        const built=await tools.request({operation:'compile',files:[['main.mbt','pub fn answer() -> Int { 42 }']],
          standardInterfaces:[[preludeName,preludeInterface(target)]],exports:['answer'],target});
        if (!built.successful) throw new Error(JSON.stringify(built.diagnostics));
        results.push((await tools.request({operation:'run',artifact:built.artifact!,export:'answer'})).value);
      }
      const invalid=await tools.request({operation:'compile',files:[['bad.mbt','pub fn answer() -> Int { "bad" }']],
        standardInterfaces:[[preludeName,preludeInterface('wasm')]],exports:['answer']});
      const spin=await tools.request({operation:'compile',files:[['main.mbt','pub fn spin() -> Int { while true {}\n0 }']],
        standardInterfaces:[[preludeName,preludeInterface('wasm')]],exports:['spin']});
      const controller=new AbortController();
      const running=tools.request({operation:'run',artifact:spin.artifact!,export:'spin'},{signal:controller.signal});
      setTimeout(()=>controller.abort(),50);
      let cancellation;
      try {await running;} catch(e) {cancellation=e instanceof Error ? e.name : String(e); }
      return {mode:info.mode,missing,assemblyValue,persistedValue,results,invalid:invalid.successful,diagnostics:invalid.diagnostics.length,cancellation};
    } finally {tools.dispose();}
  },preludes);
  assert.deepEqual(result,{mode:'embedded',missing:'PreludeRequiredError',assemblyValue:42,persistedValue:42,results:[42,42],invalid:false,diagnostics:1,cancellation:'AbortError'});
  console.log('Browser embedded compilation, execution, diagnostics and cancellation passed');
} finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}
