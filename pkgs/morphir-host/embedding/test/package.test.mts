import { npmCli } from '../../../../tests/npm.ts';
import assert from "node:assert/strict";
import {test} from "node:test";
import {execFileSync} from "node:child_process";
import {mkdtempSync,rmSync,writeFileSync,readdirSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";

test("installed npm package compiles without a CLI",()=>{
  const directory=mkdtempSync(join(tmpdir(),"morphir-embedding-package-"));
  const source=fileURLToPath(new URL("../",import.meta.url));
  const npm=(args: string[])=>execFileSync(process.execPath,[npmCli,...args],{cwd:source,encoding:"utf8"});
  try {
    npm(["pack","--pack-destination",directory]);
    // Pack the already pinned compiler so a clean runner needs no registry metadata.
    npm(["pack","./node_modules/@moonbit/moonc-worker","--ignore-scripts","--pack-destination",directory]);
    const tarballs=readdirSync(directory).filter(p=>p.endsWith('.tgz')).map(p=>join(directory,p));
    npm(["install","--prefix",directory,"--cache",join(directory,"cache"),"--ignore-scripts","--offline","--no-audit","--no-fund",...tarballs]);
    writeFileSync(join(directory,"check.mjs"), `
      import {createNodeToolchain} from '@morphir/moonbit-toolchain/node';
      import {pinPackage,assemblyIdentity,executeAssembly,compilerVersion} from '@morphir/moonbit-toolchain';
      const tools=createNodeToolchain();
      try {
        const built=await tools.request({operation:'compile',files:[['main.mbt','pub fn answer() -> Int { 42 }']],exports:['answer']});
        const result=await tools.request({operation:'run',artifact:built.artifact,export:'answer'});
        if(result.value!==42) throw new Error('Unexpected result');
        const dependency=await pinPackage({name:'installed/library',role:'library',dependencies:[],input:{kind:'source',files:[['lib.mbt','pub fn twice(n : Int32) -> Int32 { n * 2 }']]}});
        const root=await pinPackage({name:'installed/main',role:'library',dependencies:[{name:'math',pin:dependency.pin}],input:{kind:'source',files:[['main.mbt','pub fn answer() -> Int32 { @math.twice(21) }']]}});
        const packages=[root,dependency];
        const assembly=await executeAssembly(tools,{root:root.pin,packages,identity:await assemblyIdentity(compilerVersion,packages),target:'wasm',exports:['answer']});
        if((await tools.request({operation:'run',artifact:assembly.artifact,export:'answer'})).value!==42) throw new Error('Unexpected assembly result');
        console.log('installed embedding passed');
      } finally {tools.dispose();}
    `);
    // The packed declarations must resolve through the actual npm exports and
    // retain request/result correlation, without this repository's ambient types.
    writeFileSync(join(directory,"tsconfig.json"), JSON.stringify({compilerOptions:{
      target:"ES2022", module:"Preserve", moduleResolution:"bundler", strict:true,
      noEmit:true, types:[], lib:["ES2022","DOM"],
    }, include:["consumer.ts"]}));
    const typed = `import {createNodeToolchain} from '@morphir/moonbit-toolchain/node';
      const toolchain = createNodeToolchain();
      const built = await toolchain.request({operation:'compile',files:[['main.mbt','pub fn answer() -> Int { 42 }']]});
      if (!built.artifact) throw new Error("Compilation failed");
      const bytes: Uint8Array = built.artifact.bytes;
      toolchain.dispose();
`;
    writeFileSync(join(directory,"consumer.ts"), typed);
    execFileSync("bun", ["check", "-p", join(directory,"tsconfig.json")], {cwd:directory, stdio:"pipe", encoding:"utf8"});
    writeFileSync(join(directory,"consumer.ts"), typed + "const invalid: string = built.artifact.bytes;\n");
    assert.throws(() => execFileSync("bun", ["check", "-p", join(directory,"tsconfig.json")], {cwd:directory, stdio:"pipe", encoding:"utf8"}));
    const env: NodeJS.ProcessEnv={...process.env,PATH:''};
    delete env.MOON_HOME;
    assert.equal(execFileSync(process.execPath,[join(directory,"check.mjs")],{cwd:directory,env,encoding:"utf8"}).trim(),'installed embedding passed');
  } finally {rmSync(directory,{recursive:true,force:true});}
});
