import {open, lstat, mkdir, mkdtemp, rename, rm, readFile, unlink} from 'node:fs/promises';
import {dirname, join, basename, resolve} from 'node:path';
import type {ArtifactStore, ManifestEncoding, SavedArtifact} from './artifacts.mjs';

async function absent(path:string) {
  try {await lstat(path);} catch (error) {
    if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') return;
    throw error;
  }
  throw new Error(`Artifact destination already exists: ${path}`);
}

/** Same-directory staging + rename publishes the complete pair atomically.
 * An exclusive cooperative-writer lock prevents racing publications. A crash
 * can leave a .publish.lock file; inspect it before removing a stale lock.
 */
export function createDirectoryArtifactStore(path:string):ArtifactStore {
  const destination=resolve(path);
  return {async begin() {
    await mkdir(dirname(destination),{recursive:true});
    const lockPath=destination+'.publish.lock';
    const lock=await open(lockPath,'wx');
    let staging:string|undefined;
    let phase:'staging'|'committed'|'aborted'='staging';
    let released=false;
    const written=new Set<string>();
    const release=async () => {if (released) return;await lock.close();await unlink(lockPath);released=true;};
    try {
      await lock.writeFile(JSON.stringify({pid:process.pid,destination})+'\n'); await lock.sync();
      await absent(destination);
      staging=await mkdtemp(join(dirname(destination),`.${basename(destination)}-staging-`));
    } catch (error) {await release();throw error;}
    return {
      async write(name,bytes) {
        if (!staging || phase !== 'staging' || !['model.wasm','manifest.ion','manifest.json'].includes(name) || written.has(name)) throw new Error('Invalid artifact transaction write');
        const handle=await open(join(staging,name),'wx');
        try {await handle.writeFile(bytes);await handle.sync();written.add(name);}
        finally {await handle.close();}
      },
      async commit() {
        if (!staging || phase !== 'staging' || written.size !== 2 || !written.has('model.wasm') ||
          (written.has('manifest.ion') === written.has('manifest.json'))) throw new Error('Incomplete artifact transaction');
        await absent(destination);
        await rename(staging,destination);
        phase='committed';staging=undefined;
        await release();
      },
      async abort() {
        if (phase !== 'staging') return;
        try {if (staging) await rm(staging,{recursive:true,force:true});staging=undefined;phase='aborted';}
        finally {await release();}
      },
    };
  }};
}

/** No compiler, toolchain installation or build cache is consulted. */
export async function readDirectoryArtifact(path:string, encoding:ManifestEncoding='ion'):Promise<SavedArtifact> {
  if (encoding !== 'ion' && encoding !== 'json') throw new TypeError('Unsupported manifest encoding');
  const [wasm,manifest]=await Promise.all([readFile(join(path,'model.wasm')),readFile(join(path,encoding === 'ion' ? 'manifest.ion' : 'manifest.json'))]);
  return {wasm:new Uint8Array(wasm),manifest:new Uint8Array(manifest),encoding};
}
