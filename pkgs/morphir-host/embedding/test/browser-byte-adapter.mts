// Qualification transport to a real browser host. The shared runner still owns
// its protocol session, corpus, observations, verdict and independent recheck.
import {createServer} from 'node:http';
import type {AddressInfo} from 'node:net';
import {readFile,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {readDirectoryArtifact} from '../node-artifacts.mjs';
import {serveByteAdapter} from '../node-byte-adapter.mjs';
import type {ByteAdapter,ByteExchange,ResponseDiagnostic} from '../byte-adapter.mjs';

const [directory,profile,receipt]=process.argv.slice(2);
if(!directory || (profile !== 'bytes-v1' && profile !== 'bytes-diagnostics-v1'))throw new Error('Supply artifact and exact profile');
const saved=await readDirectoryArtifact(directory);
const root=new URL('../',import.meta.url);
const server=createServer(async(req,res)=>{
  try {
    const file=new URL('.'+req.url,root);
    if(!file.href.startsWith(root.href) || !file.pathname.endsWith('.mjs'))throw new Error('Invalid host module path');
    res.setHeader('Content-Type','text/javascript');res.end(await readFile(file));
  } catch {res.statusCode=404;res.end();}
});
await new Promise<void>(done=>server.listen(0,'127.0.0.1',done));
let browser;
let version='';
let requests=0;
try {
  browser=await chromium.launch({headless:true});
  version=browser.version();
  const page=await browser.newPage();
  await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/byte-adapter.mjs`);
  await page.evaluate(async({wasm,manifest,encoding,profile})=>{
    const {loadByteAdapter}=await import(new URL('/byte-adapter.mjs',location.href).href) as typeof import('../byte-adapter.mjs');
    const {preflight}=await import(new URL('/dist/test/saved-byte-preflight.mjs',location.href).href) as typeof import('./saved-byte-preflight.mjs');
    const saved={wasm:new Uint8Array(wasm),manifest:new Uint8Array(manifest),encoding};
    await preflight(saved,profile === 'bytes-v1'?'bytes-v1':'bytes-diagnostics-v1',loadByteAdapter);
    const context=globalThis as typeof globalThis & {codec:ByteAdapter;events:ResponseDiagnostic[]};
    context.events=[];
    context.codec=await loadByteAdapter(saved,
      profile === 'bytes-v1'?{profile:'bytes-v1'}:{profile:'bytes-diagnostics-v1',diagnostics:event=>{context.events.push(event);}});
  },{wasm:[...saved.wasm],manifest:[...saved.manifest],encoding:saved.encoding,profile});
  await serveByteAdapter({
    async exchange(request):Promise<ByteExchange> {
      const result=await page.evaluate(bytes=>{
        const context=globalThis as typeof globalThis & {codec:ByteAdapter;events:ResponseDiagnostic[]};
        const value=context.codec.exchange(new Uint8Array(bytes));
        const events=context.events.splice(0);
        return {kind:value.kind,bytes:value.kind === 'response'?[...value.bytes]:[],events};
      },[...request]);
      requests++;
      for(const event of result.events)process.stderr.write(JSON.stringify(event)+'\n');
      return result.kind === 'exit'?{kind:'exit'}:{kind:'response',bytes:new Uint8Array(result.bytes)};
    },
    async dispose() {
      await page.evaluate(()=>{(globalThis as typeof globalThis & {codec:ByteAdapter}).codec.dispose();});
    },
  });
} finally {
  await browser?.close();
  await new Promise<void>((done,reject)=>server.close(error=>error?reject(error):done()));
}
if(receipt)await writeFile(receipt,JSON.stringify({host:'chromium',version,requests,preflight:'passed',shutdown:'passed'})+'\n');
