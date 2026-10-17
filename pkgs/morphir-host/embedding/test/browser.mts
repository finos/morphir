import type { AddressInfo } from 'node:net';
import type { createBrowserToolchain as BrowserFactory } from '../browser.mjs';
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {chromium} from "playwright";

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
  const result=await page.evaluate(async()=>{
    const {createBrowserToolchain}=await import(new URL('/browser.mjs', location.href).href) as { createBrowserToolchain: typeof BrowserFactory };
    const tools=createBrowserToolchain();
    try {
      const info=await tools.request({operation:'info'});
      const results=[];
      for (const target of ['wasm','wasm-gc'] as const) {
        const built=await tools.request({operation:'compile',files:[['main.mbt','pub fn answer() -> Int { 42 }']],exports:['answer'],target});
        if (!built.successful) throw new Error(JSON.stringify(built.diagnostics));
        results.push((await tools.request({operation:'run',artifact:built.artifact!,export:'answer'})).value);
      }
      const invalid=await tools.request({operation:'compile',files:[['bad.mbt','pub fn answer() -> Int { "bad" }']],exports:['answer']});
      const spin=await tools.request({operation:'compile',files:[['main.mbt','pub fn spin() -> Int { while true {}\n0 }']],exports:['spin']});
      const controller=new AbortController();
      const running=tools.request({operation:'run',artifact:spin.artifact!,export:'spin'},{signal:controller.signal});
      setTimeout(()=>controller.abort(),50);
      let cancellation;
      try {await running;} catch(e) {cancellation=e instanceof Error ? e.name : String(e); }
      return {mode:info.mode,results,invalid:invalid.successful,diagnostics:invalid.diagnostics.length,cancellation};
    } finally {tools.dispose();}
  });
  assert.deepEqual(result,{mode:'embedded',results:[42,42],invalid:false,diagnostics:1,cancellation:'AbortError'});
  console.log('Browser embedded compilation, execution, diagnostics and cancellation passed');
} finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}
