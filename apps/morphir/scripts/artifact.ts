import {copyFileSync, existsSync, mkdirSync, statSync} from 'node:fs';
import {dirname, join} from 'node:path';

/** The shared CLI is universal; each entry owns its target's effects and worker launchers. */
export function cliPackage(target: string): string {
  if (target === 'wasm' || target === 'wasm-gc') return 'apps/morphir/embedded';
  return target === 'js' ? 'apps/morphir/node' : 'apps/morphir';
}

export function cliArtifact(build: string, target: string, profile = 'release'): string {
  const root = join(build, target, profile, 'build/morphir/morphir');
  if (target === 'wasm' || target === 'wasm-gc') return join(root, 'embedded/embedded.wasm');
  return join(root, target === 'native' ? 'morphir.exe' : 'node/node.js');
}

/** Existing CI artifact consumers receive the same distribution basename. */
export function stageCliArtifact(build: string, target: string): string {
  const source = cliArtifact(build, target);
  if (!existsSync(source) || !statSync(source).isFile() || statSync(source).size === 0) {
    throw new Error(`Missing CLI artifact: ${source}`);
  }
  if (target === 'native') return source;
  const destination = join(build, target, `release/build/morphir/morphir/morphir.${target === 'js' ? 'js' : 'wasm'}`);
  mkdirSync(dirname(destination), {recursive: true});
  copyFileSync(source, destination);
  if (statSync(destination).size !== statSync(source).size) throw new Error(`Incomplete CLI artifact: ${destination}`);
  return destination;
}
