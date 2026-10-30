import {copyFileSync, existsSync, mkdirSync, statSync} from 'node:fs';
import {dirname, join} from 'node:path';

/** The shared CLI is universal; process and embedded entries own their effects. */
export function cliPackage(target: string): string {
  return target === 'wasm' || target === 'wasm-gc' ? 'apps/morphir/embedded' : 'apps/morphir';
}

export function cliArtifact(build: string, target: string, profile = 'release'): string {
  const root = join(build, target, profile, 'build/morphir/morphir');
  return target === 'wasm' || target === 'wasm-gc'
    ? join(root, 'embedded/embedded.wasm')
    : join(root, target === 'native' ? 'morphir.exe' : 'morphir.js');
}

/** Existing CI artifact consumers receive the same distribution basename. */
export function stageCliArtifact(build: string, target: string): string {
  const source = cliArtifact(build, target);
  if (!existsSync(source) || !statSync(source).isFile() || statSync(source).size === 0) {
    throw new Error(`Missing CLI artifact: ${source}`);
  }
  if (target !== 'wasm' && target !== 'wasm-gc') return source;
  const destination = join(build, target, 'release/build/morphir/morphir/morphir.wasm');
  mkdirSync(dirname(destination), {recursive: true});
  copyFileSync(source, destination);
  if (statSync(destination).size !== statSync(source).size) throw new Error(`Incomplete CLI artifact: ${destination}`);
  return destination;
}
