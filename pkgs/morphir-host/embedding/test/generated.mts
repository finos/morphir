import assert from 'node:assert/strict';
import {readFile, mkdir, writeFile, readdir} from 'node:fs/promises';
import {join, resolve, basename, dirname} from 'node:path';
import {execFileSync} from 'node:child_process';
import type {PackageAsset, PackageDescription, PackageImport, PackagePin} from '../assembly.mjs';
import {assemblyIdentity, pinPackage, executeAssembly, sha256} from '../assembly.mjs';
import {prepareArtifact,publishArtifact,loadArtifact} from '../artifacts.mjs';
import {createDirectoryArtifactStore} from '../node-artifacts.mjs';
import {createInProcessToolchain} from '../node.mts';
import {compilerVersion} from '../index.mjs';

// Fixture preparation uses Moon's generator and dry-run build plan. This program
// executes none of those compiler commands; it supplies their exact inputs to the
// embedded compiler, then consumes saved artifacts in a separate process.
const directory=resolve(process.argv[2] ?? '.dev/assembly-qualification');
const coreHome=process.argv[3];
assert.ok(coreHome,'Supply the pinned core asset directory');
interface Generated {package:string;modules:number;modelIon:number[];symbols:{fqname:string;name:string}[];artifacts:{path:string;content:string|number[]}[];}
interface CoreGraph {nodes:{module:string;version:string;rel:string}[];edges:{from:number;to:number;alias:string;kinds:string[]}[];}
const generated:Generated=JSON.parse(await readFile(join(directory,'generated.json'),'utf8'));
const graph:CoreGraph=JSON.parse(await readFile(join(directory,'core-graph.json'),'utf8'));
assert.equal(generated.modules,3);
assert.ok(graph.nodes.every(p => p.module === 'moonbitlang/core' && p.version === compilerVersion));
const bundle=join(coreHome,'lib/core/_build/wasm/release/bundle');
const placeholder=(name:string):PackagePin=>({name,sha256:'0'.repeat(64)});
const coreNames=graph.nodes.map(n=>`${n.module}/${n.rel}`);
const coreIndex=new Map(coreNames.map((name,index)=>[name,index]));
const coreDependencies=(index:number):PackageImport[]=>graph.edges.filter(e=>e.from === index && e.kinds.includes('source'))
  .map(e=>({name:e.alias,pin:placeholder(coreNames[e.to]!)}));

// Only Moon's generated command spelling is accepted. Never execute text from
// these recipes. Reject unexpected syntax rather than inventing package rules.
function tokens(line:string):string[] {
  return (line.match(/(?:[^\s"']+|'[^']*'|"[^"]*")+/g) ?? []).map(token=>{
    if (/^'[^']*'$/.test(token) || /^"[^"]*"$/.test(token)) return token.slice(1,-1);
    assert.ok(!/["']/.test(token),`Unexpected build-plan quoting: ${token}`);return token;
  });
}
const plan=(await readFile(join(directory,'sdk-build.txt'),'utf8')).trim().split(/\r?\n/).filter(Boolean).map(tokens);
assert.equal(plan.length,4,'Expected complete root/integer/list/basics SDK source closure');
const sdkOutputs=new Map<string,string>();
for (const command of plan) {
  assert.equal(command[1],'build-package');
  const name=command[command.indexOf('-pkg')+1]!;
  assert.ok(name === 'finos/morphir-sdk' || ['integer','list','basics'].some(p=>name === `finos/morphir-sdk/${p}`));
  sdkOutputs.set(command[command.indexOf('-o')+1]!.replace(/\.core$/,'.mi'),name);
}
function imported(value:string):PackageImport {
  const separator=value.lastIndexOf(':');
  assert.ok(separator>0,`Expected aliased interface: ${value}`);
  const path=value.slice(0,separator), name=value.slice(separator+1);
  const corePath=/^\$(?:MOON_HOME|MOON_TOOLCHAIN_ROOT)\/lib\/core\/_build\/wasm\/release\/bundle\/(.+)$/.exec(path);
  if (corePath) {
    const relative=corePath[1]!;
    return {name,pin:placeholder('moonbitlang/core/'+dirname(relative).replaceAll('\\','/'))};
  }
  const pkg=sdkOutputs.get(path);assert.ok(pkg,`Unexpected non-core dependency: ${path}`);
  return {name,pin:placeholder(pkg)};
}
const sdk:PackageDescription[]=[];
for (const command of plan) {
  const name=command[command.indexOf('-pkg')+1]!;
  const files:[string,string][]=[];
  for (const path of command.slice(2)) {
    if (path.startsWith('-')) break;
    assert.ok(path.endsWith('.mbt'));files.push([basename(path),await readFile(path,'utf8')]);
  }
  const dependencies:PackageImport[]=[];
  for (let i=0;i<command.length;i++) if (command[i] === '-i') dependencies.push(imported(command[++i]!));
  sdk.push({name,role:'sdk',dependencies,input:{kind:'source',files}});
}
const imports=(generated.artifacts.find(a=>a.path === 'moon.pkg')!.content as string).split('\n').filter(Boolean).flatMap(line=>{
  if (line === 'import {' || line === '}') return [];
  const found=/^  "([^"]+)" @([A-Za-z_][A-Za-z0-9_]*),$/.exec(line);
  assert.ok(found,`Unexpected generated import declaration: ${line}`);
  return [{name:found[2]!,pin:placeholder(found[1]!)}];
});
imports.push({name:'prelude',pin:placeholder('moonbitlang/core/prelude')});
const modelPackage:PackageDescription={name:generated.package,role:'library',dependencies:imports,
  input:{kind:'source',files:generated.artifacts.filter(a=>a.path.endsWith('.mbt')).map(a=>{
    assert.equal(typeof a.content,'string');return [a.path,a.content as string];
  })}};
const symbol=(fqname:string)=>{const symbol=generated.symbols.find(s=>s.fqname === fqname);assert.ok(symbol);return symbol.name;};
const marker='MORPHIR_UNREACHABLE_ASSEMBLY_QUALIFICATION_'+ '0123456789'.repeat(400);
const driver:PackageDescription={name:'qualification/main',role:'library',dependencies:[
  {name:'model',pin:placeholder(generated.package)},{name:'integer',pin:placeholder('finos/morphir-sdk/integer')},
  {name:'prelude',pin:placeholder('moonbitlang/core/prelude')},
],input:{kind:'source',files:[['driver.mbt',`
fn note_initialization(value : Int32) -> Int32 = "qualification" "init"
let initialized : Int32 = note_initialization(7)
pub fn answer() -> Int32 { try { @integer.to_int(@model.${symbol('pricing:other#total')}()).unwrap() } catch { _ => -1 } }
pub fn cross_module() -> Int32 { try { @integer.to_int(@model.${symbol('pricing:other#copy')}()).unwrap() } catch { _ => -1 } }
pub fn enabled() -> Bool { try @model.${symbol('pricing:scalars#enabled')}() catch { _ => false } }
pub fn initialization() -> Int32 { initialized }
pub fn unused_payload(n : Int32) -> String { if n > 0 { ${JSON.stringify(marker)} } else { "unused" } }
`]]}};
const raw=new Map<string,PackageDescription>([...sdk,modelPackage,driver].map(p=>[p.name,p]));
const pending=[...sdk.flatMap(p=>p.dependencies),...imports,...driver.dependencies].map(d=>d.pin.name).filter(n=>n.startsWith('moonbitlang/core/'));
const requiredCore=new Set<string>();
while (pending.length) {
  const name=pending.pop()!;
  if (requiredCore.has(name)) continue;requiredCore.add(name);
  const index=coreIndex.get(name);assert.notEqual(index,undefined,`Missing pinned core graph node: ${name}`);
  pending.push(...coreDependencies(index!).map(d=>d.pin.name));
}
const blankIdentity={compilerVersion,coreSha256:'0'.repeat(64),sdkSha256:'0'.repeat(64)};
for (const name of requiredCore) {
  const index=coreIndex.get(name)!; const relative=graph.nodes[index]!.rel;
  raw.set(name,{name,role:'core',dependencies:coreDependencies(index),input:{kind:'prebuilt',
    interface:new Uint8Array(await readFile(join(bundle,relative,basename(relative)+'.mi'))),
    core:new Uint8Array(await readFile(join(bundle,relative,basename(relative)+'.core'))),identity:blankIdentity,target:'wasm',optimization:'optimized'}});
}
const identity=await assemblyIdentity(compilerVersion,[...raw.values()]);
const pinned=new Map<string,PackageAsset>();
while (pinned.size<raw.size) {
  const before=pinned.size;
  for (const entry of raw.values()) {
    if (pinned.has(entry.name) || entry.dependencies.some(d=>!pinned.has(d.pin.name))) continue;
    pinned.set(entry.name,await pinPackage({...entry,dependencies:entry.dependencies.map(d=>({...d,pin:pinned.get(d.pin.name)!.pin})),
      input:entry.input.kind === 'prebuilt' ? {...entry.input,identity} : entry.input}));
  }
  assert.notEqual(before,pinned.size,'Cyclic or missing fixture package graph');
}
const packages=[...pinned.values()];const root=pinned.get(driver.name)!.pin;
const profile={id:'morphir/qualification-core-scalar-v1',sha256:await sha256(new TextEncoder().encode('core-wasm functions answer:()->i32,cross_module:()->i32,enabled:()->i32,initialization:()->i32; import qualification.init:(i32)->i32'))};
const tools=createInProcessToolchain();
const report:{optimization:string;bytes:number;packages:number;corePackages:number;modelSha256:string}[]=[];
const envPath=process.env.PATH, envMoon=process.env.MOON_HOME;
try {
  // All acquisition is finished. Compilation may use only the packaged provider.
  process.env.PATH='';delete process.env.MOON_HOME;
  await assert.rejects(executeAssembly(tools,{root,packages:packages.filter(p=>p.name !== 'finos/morphir-sdk/integer'),identity,target:'wasm',exports:['answer']}),/MissingPackage[\s\S]*finos\/morphir-sdk\/integer/);
  const corrupted=structuredClone(packages);
  const damaged=corrupted.find(p=>p.input.kind === 'prebuilt')!;
  if (damaged.input.kind === 'prebuilt') damaged.input.core[0]=damaged.input.core[0]!^1;
  await assert.rejects(executeAssembly(tools,{root,packages:corrupted,identity,target:'wasm',exports:['answer']}),/content mismatch/);
  for (const optimization of ['optimized','unoptimized'] as const) {
    const result=await executeAssembly(tools,{root,packages,identity,target:'wasm',optimization,exports:['answer','cross_module','enabled','initialization']});
    assert.equal(result.packages.length,packages.length);
    assert.equal(new Set(result.packages.map(p=>p.pin.name)).size,packages.length);
    const exports=WebAssembly.Module.exports(await WebAssembly.compile(result.artifact.bytes));
    assert.ok(!exports.some(e=>e.name === 'unused_payload'));
    const bytes=Buffer.from(result.artifact.bytes);
    assert.equal(bytes.includes(Buffer.from(marker,'utf8')),false);
    assert.equal(bytes.includes(Buffer.from(marker,'utf16le')),false);
    const saved=await prepareArtifact(result,profile,{model:{id:'assembly',revision:'fixture-r1',bytes:new Uint8Array(generated.modelIon)},metadataIon:'qualification::{language:"MoonBit", graph:"SDK and core", draft_ir:"4.0.0"}'});
    let initializations=0;
    const loaded=await loadArtifact(saved,{targets:['wasm'],profiles:[profile],encodings:['ion'],imports:{qualification:{init:(n:number)=>{initializations++;return n;}}}});
    try {
      assert.equal(loaded.invoke('answer'),42);assert.equal(loaded.invoke('cross_module'),40);
      assert.equal(loaded.invoke('enabled'),1);assert.equal(loaded.invoke('initialization'),7);
      assert.equal(loaded.invoke('answer'),42);assert.equal(initializations,1);
    } finally {loaded.dispose();}
    const destination=join(directory,optimization);
    await publishArtifact(createDirectoryArtifactStore(destination),saved);
    assert.deepEqual((await readdir(destination)).sort(),['manifest.ion','model.wasm']);
    const consumer=join(directory,`consume-${optimization}.mjs`);
    await writeFile(consumer,`
      import {readDirectoryArtifact} from ${JSON.stringify(new URL('../node-artifacts.mjs',import.meta.url).href)};
      import {loadArtifact} from ${JSON.stringify(new URL('../artifacts.mjs',import.meta.url).href)};
      let calls=0;
      const loaded=await loadArtifact(await readDirectoryArtifact(${JSON.stringify(destination)}),{targets:['wasm'],profiles:[${JSON.stringify(profile)}],encodings:['ion'],imports:{qualification:{init:n=>{calls++;return n;}}}});
      try {if(loaded.invoke('answer')!==42 || loaded.invoke('cross_module')!==40 || loaded.invoke('initialization')!==7 || calls!==1) throw new Error('Fresh generated result mismatch');console.log('fresh generated artifact passed');}
      finally {loaded.dispose();}
    `);
    assert.equal(execFileSync(process.execPath,[consumer],{env:{...process.env,PATH:''},encoding:'utf8'}).trim(),'fresh generated artifact passed');
    report.push({optimization,bytes:result.artifact.bytes.length,packages:packages.length,corePackages:requiredCore.size,modelSha256:saved.record.origin.sha256});
  }
  assert.equal(report[0]!.modelSha256,report[1]!.modelSha256);
  await mkdir(directory,{recursive:true});await writeFile(join(directory,'report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report));
} finally {
  tools.dispose();if (envPath === undefined) delete process.env.PATH;else process.env.PATH=envPath;
  if (envMoon === undefined) delete process.env.MOON_HOME;else process.env.MOON_HOME=envMoon;
}
