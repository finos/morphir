import type { BinaryLike } from 'node:crypto';
import type { TreeOptions } from './contracts.mjs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {closeSync,constants,fstatSync,lstatSync,openSync,readFileSync,readSync,readdirSync,readlinkSync,realpathSync,writeSync} from 'node:fs';
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

/** Check pinned identity through a bounded, no-follow descriptor, not through
 * PATH. Failures use `${code}_unavailable`, `_changed` and `_limit`. A `copy`
 * destination receives exactly the bytes that were hashed, from the same
 * descriptor, so callers can execute the verified copy rather than the path. */
export function pinnedFileHash(path: string, tick: () => void, code: string, copy?: string): string {
  const before = lstatSync(path);
  if (!before.isFile() || before.size > 536870912) throw Error(`${code}_unavailable`);
  const fd = openSync(path, constants.O_RDONLY | (constants.O_NOFOLLOW || 0) | (constants.O_NONBLOCK || 0));
  const out = copy === undefined ? undefined : openSync(copy, 'wx', 0o600);
  try {
    const opened = fstatSync(fd);
    if (!opened.isFile() || opened.dev !== before.dev || opened.ino !== before.ino) throw Error(`${code}_changed`);
    const digest = createHash('sha256'), buffer = Buffer.alloc(65536);
    let total = 0;
    for (;;) {
      tick();
      const count = readSync(fd, buffer, 0, buffer.length, null);
      if (!count) break;
      total += count; if (total > 536870912) throw Error(`${code}_limit`);
      digest.update(buffer.subarray(0, count));
      if (out !== undefined) writeSync(out, buffer, 0, count);
    }
    const after = fstatSync(fd), named = lstatSync(path);
    if (after.size !== opened.size || after.mtimeMs !== opened.mtimeMs || after.ctimeMs !== opened.ctimeMs ||
      !named.isFile() || named.dev !== opened.dev || named.ino !== opened.ino) throw Error(`${code}_changed`);
    return digest.digest('hex');
  } finally { closeSync(fd); if (out !== undefined) closeSync(out); }
}
