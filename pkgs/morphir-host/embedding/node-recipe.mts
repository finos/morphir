import {readFile} from 'node:fs/promises';
import {resolve,join,basename,dirname} from 'node:path';
import type {PackageDescription,PackageAsset,PackagePin,PackageImport,AssemblyIdentity} from './assembly.mjs';
import {assemblyIdentity,pinPackage} from './assembly.mjs';
import {compilerVersion} from './index.mjs';

interface CoreGraph {nodes:{module:string;version:string;rel:string}[];edges:{from:number;to:number;alias:string;kinds:string[]}[];}
const placeholder=(name:string):PackagePin=>({name,sha256:'0'.repeat(64)});
/** Decode a bounded subset of Moon's own dry-run recipe; never execute shell text. */
export function recipeTokens(line:string):string[] {
  return (line.match(/(?:[^\s"']+|'[^']*'|"[^"]*")+/g) ?? []).map(token=>{
    if (/^'[^']*'$/.test(token) || /^"[^"]*"$/.test(token)) return token.slice(1,-1);
    if (/["']/.test(token)) throw new Error('Unsupported recipe quoting');return token;
  });
}
interface Recipe {name:string;output:string;files:string[];interfaces:string[];}
export function parseMoonRecipe(source:string):Recipe[] {
  const recipes:Recipe[]=[];
  const unary=new Set(['-o','-pkg','-pkg-type','-std-path','-i','-pkg-sources','-target','-workspace-path','-all-pkgs','-w']);
  for(const line of source.trim().split(/\r?\n/).filter(Boolean)) {
    const tokens=recipeTokens(line);
    if(basename(tokens[0] ?? '') !== 'moonc' || tokens[1] !== 'build-package') throw new Error('Only Moon library build-package recipes are supported');
    const files:string[]=[];let i=2;
    while(i<tokens.length && !tokens[i]!.startsWith('-')) {const path=tokens[i++]!;if(!path.endsWith('.mbt'))throw new Error('Only MoonBit source inputs are supported');files.push(path);}
    const fields=new Map<string,string[]>();
    while(i<tokens.length) {
      const key=tokens[i++]!;
      if(!unary.has(key) || i===tokens.length) throw new Error(`Unsupported recipe option: ${key}`);
      const value=tokens[i++]!;
      if(key === '-w' && value !== '-a' && value !== '-reserved_keyword') throw new Error('Unsupported warning policy');
      if(key !== '-i' && fields.has(key)) throw new Error(`Duplicate recipe option: ${key}`);
      fields.set(key,[...fields.get(key) ?? [],value]);
    }
    const one=(key:string)=>{const values=fields.get(key);if(values?.length !== 1)throw new Error(`Missing recipe option: ${key}`);return values[0]!;};
    if(one('-target') !== 'wasm' || one('-pkg-type') !== 'library' || !files.length) throw new Error('Recipe must describe core-Wasm libraries');
    const name=one('-pkg'),output=one('-o');
    if(!output.endsWith('.core') || recipes.some(r=>r.name === name || r.output===output))throw new Error('Duplicate or invalid recipe output');
    recipes.push({name,output,files,interfaces:fields.get('-i') ?? []});
  }
  if(!recipes.length)throw new Error('Empty recipe');return recipes;
}

/** Acquisition adapter. Supplied recipe source paths are explicit build inputs. */
export async function acquireMoonRecipe(source:string, coreRoot:string, graph:CoreGraph, base=process.cwd()):Promise<{packages:PackageAsset[];identity:AssemblyIdentity}> {
  const recipes=parseMoonRecipe(source);
  const corePin=JSON.parse(await readFile(new URL('../../../tools/moonbit-core-pin.json',import.meta.url),'utf8'));
  if(corePin.compilerVersion !== compilerVersion || !graph.nodes.every(n=>n.module === 'moonbitlang/core' && n.version === corePin.sourceManifestVersion)) throw new Error('Recipe core/compiler pin mismatch');
  const bundle=join(coreRoot,'_build/wasm/release/bundle');
  const coreNames=graph.nodes.map(n=>`${n.module}/${n.rel}`);
  const coreIndex=new Map(coreNames.map((name,index)=>[name,index]));
  const outputs=new Map(recipes.map(r=>[resolve(base,r.output.replace(/\.core$/,'.mi')),r.name]));
  const coreInterfaces=new Map(graph.nodes.map((n,index)=>[resolve(bundle,n.rel,basename(n.rel)+'.mi'),coreNames[index]!]));
  const coreDeps=(index:number):PackageImport[]=>graph.edges.filter(e=>e.from === index && e.kinds.includes('source')).map(e=>({name:e.alias,pin:placeholder(coreNames[e.to]!)}));
  const imported=(value:string):PackageImport=>{
    const separator=value.lastIndexOf(':');if(separator<1)throw new Error('Expected aliased interface');
    const path=value.slice(0,separator).replace(/^\$MOON_HOME\/lib\/core/,coreRoot);
    const name=coreInterfaces.get(resolve(base,path)) ?? outputs.get(resolve(base,path));
    if(!name)throw new Error(`Unresolved recipe interface: ${value}`);
    return {name:value.slice(separator+1),pin:placeholder(name)};
  };
  const raw=new Map<string,PackageDescription>();
  for(const entry of recipes) {
    const files: [string,string][]=[];
    for(let i=0;i<entry.files.length;i++)files.push([`${i}-${basename(entry.files[i]!)}`,await readFile(resolve(base,entry.files[i]!),'utf8')]);
    raw.set(entry.name,{name:entry.name,role:entry.name === 'finos/morphir-sdk' || entry.name.startsWith('finos/morphir-sdk/') ? 'sdk':'library',
      dependencies:entry.interfaces.map(imported),input:{kind:'source',files}});
  }
  const pending=[...raw.values()].flatMap(p=>p.dependencies).map(d=>d.pin.name).filter(n=>coreIndex.has(n));
  const required=new Set<string>();
  while(pending.length){const name=pending.pop()!;if(required.has(name))continue;required.add(name);pending.push(...coreDeps(coreIndex.get(name)!).map(d=>d.pin.name));}
  const blank={compilerVersion,coreSha256:'0'.repeat(64),sdkSha256:'0'.repeat(64)};
  for(const name of required){const index=coreIndex.get(name)!;const rel=graph.nodes[index]!.rel;
    raw.set(name,{name,role:'core',dependencies:coreDeps(index),input:{kind:'prebuilt',identity:blank,target:'wasm',optimization:'optimized',
      interface:new Uint8Array(await readFile(join(bundle,rel,basename(rel)+'.mi'))),core:new Uint8Array(await readFile(join(bundle,rel,basename(rel)+'.core')))}});
  }
  const identity=await assemblyIdentity(compilerVersion,[...raw.values()]);
  const pinned=new Map<string,PackageAsset>();
  while(pinned.size<raw.size){const before=pinned.size;
    for(const p of raw.values())if(!pinned.has(p.name) && p.dependencies.every(d=>pinned.has(d.pin.name))) {
      pinned.set(p.name,await pinPackage({...p,dependencies:p.dependencies.map(d=>({...d,pin:pinned.get(d.pin.name)!.pin})),
        input:p.input.kind==='prebuilt'?{...p.input,identity}:p.input}));
    }
    if(before===pinned.size)throw new Error('Recipe has missing or cyclic packages');
  }
  return {packages:[...pinned.values()],identity};
}
