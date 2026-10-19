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
      import {prepareArtifact,publishArtifact,mepExecutionProfile} from '@morphir/moonbit-toolchain';
      import {createDirectoryArtifactStore} from '@morphir/moonbit-toolchain/node';
      import {fileURLToPath} from 'node:url';
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
        const profile={id:'installed/scalar-v1',sha256:'a'.repeat(64)};
        await publishArtifact(createDirectoryArtifactStore(fileURLToPath(new URL('./saved',import.meta.url))),await prepareArtifact(assembly,profile));
        // A minimal MEP-host fixture with a bounded memory and terminal exit.
        // Real protocol/source behavior is qualified separately on the full guest.
        const wasm=new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,96,0,1,127,3,2,1,0,5,4,1,1,1,1,7,10,1,6,104,97,110,100,108,101,0,0,10,6,1,4,0,65,0,11]);
        const mep=await prepareArtifact({...assembly,exports:['handle'],artifact:{target:'wasm',bytes:wasm}},await mepExecutionProfile());
        await publishArtifact(createDirectoryArtifactStore(fileURLToPath(new URL('./saved-mep',import.meta.url))),mep);
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
    // A fresh runtime needs no compiler payload at all, even when installed as npm.
    rmSync(join(directory,'node_modules/@moonbit/moonc-worker'),{recursive:true,force:true});
    writeFileSync(join(directory,'load.mjs'),`
      import {loadArtifact} from '@morphir/moonbit-toolchain';
      import {readDirectoryArtifact,loadNodeMepAdapter} from '@morphir/moonbit-toolchain/node';
      import {fileURLToPath} from 'node:url';
      const profile={id:'installed/scalar-v1',sha256:'a'.repeat(64)};
      const loaded=await loadArtifact(await readDirectoryArtifact(fileURLToPath(new URL('./saved',import.meta.url))),{
        targets:['wasm'],profiles:[profile],encodings:['ion']});
      try {if(loaded.invoke('answer')!==42) throw new Error('Wrong persisted result');console.log('installed loader passed');}
      finally {loaded.dispose();}
      const mep=await loadNodeMepAdapter(await readDirectoryArtifact(fileURLToPath(new URL('./saved-mep',import.meta.url))));
      try {if((await mep.exchange(new Uint8Array())).kind!=='exit')throw new Error('Missing MEP exit');}
      finally {await mep.dispose();}
    `);
    assert.equal(execFileSync(process.execPath,[join(directory,'load.mjs')],{cwd:directory,env,encoding:'utf8'}).trim(),'installed loader passed');
    assert.equal(execFileSync(process.execPath,[join(directory,'node_modules/@morphir/moonbit-toolchain/node-mep-cli.mjs'),join(directory,'saved-mep')],{
      cwd:directory,env,input:'Content-Length: 0\r\n\r\n',encoding:'utf8',timeout:15000,
    }),'');
  } finally {rmSync(directory,{recursive:true,force:true});}
});
