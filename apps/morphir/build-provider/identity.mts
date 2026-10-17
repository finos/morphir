import type { BinaryLike } from 'node:crypto';
import type { TreeOptions } from './contracts.mjs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,readdirSync,realpathSync,lstatSync,readlinkSync} from 'node:fs';
import {join} from 'node:path';
import {isWithin} from './paths.mjs';
export const hash=(value: BinaryLike)=>createHash('sha256').update(value).digest('hex');
export const fileIdentity=(path: string)=>hash(readFileSync(path));
export const excluded=new Set(['.git','node_modules','.mooncakes','_build']);
export function treeIdentity(root: string,{core=false,includeBuild=core,check=()=>{}}: TreeOptions = {}) {
  const entries: string[][]=[];root=realpathSync(root);
  function walk(relative: string) {
    check();
    for(const entry of readdirSync(join(root,relative),{withFileTypes:true}).sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0)) {
      if(excluded.has(entry.name)&&!(includeBuild&&entry.name==='_build'))continue;
      const path=relative?relative+'/'+entry.name:entry.name,absolute=join(root,path);
      if(entry.isDirectory())walk(path);
      else if(entry.isFile())entries.push([path,'file',fileIdentity(absolute)]);
      else if(entry.isSymbolicLink()&&core) {
        const target=realpathSync(absolute);assert.ok(isWithin(root,target),'Core link escapes installation');
        assert.ok(lstatSync(target).isFile(),'Core links must identify files');
        entries.push([path,'link',readlinkSync(absolute),fileIdentity(target)]);
      } else throw Error('Unsupported dependency entry: '+path);
    }
  }
  walk('');return hash(JSON.stringify(entries));
}
