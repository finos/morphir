import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import type {Interface, Target} from '../api.mjs';
import type {PackageAsset, PackageDescription} from '../assembly.mjs';
import {assemblyIdentity, pinPackage} from '../assembly.mjs';
import {compilerVersion, preludeInterfaceName} from '../index.mjs';

/** The pinned toolchain's own prelude bundle. Hosts supply it; the package ships no core assets. */
export function preludeBundle(target: Target = 'wasm'): {interface: Uint8Array<ArrayBuffer>; core: Uint8Array<ArrayBuffer>} {
  const home = process.env.MOON_HOME;
  assert.ok(home, 'MOON_HOME must select the pinned MoonBit toolchain');
  const directory = join(home, 'lib/core/_build', target, 'release/bundle/prelude');
  return {interface: new Uint8Array(readFileSync(join(directory, 'prelude.mi'))),
    core: new Uint8Array(readFileSync(join(directory, 'prelude.core')))};
}

/** A standard interface entry for compile and build requests. */
export function preludeInterface(target: Target = 'wasm'): Interface {
  return [preludeInterfaceName, preludeBundle(target).interface];
}

/** The prelude as a prebuilt core package for assemblies. Libraries import it as `prelude`. */
export async function preludePackage(target: Target = 'wasm'): Promise<PackageAsset> {
  const bundle = preludeBundle(target);
  const blank = {compilerVersion, coreSha256: '0'.repeat(64), sdkSha256: '0'.repeat(64)};
  const raw: PackageDescription = {name: preludeInterfaceName, role: 'core', dependencies: [],
    input: {kind: 'prebuilt', interface: bundle.interface, core: bundle.core, identity: blank, target, optimization: 'optimized'}};
  // The set identity covers only core and SDK assets, so a prebuilt core can carry it.
  const identity = await assemblyIdentity(compilerVersion, [raw]);
  return pinPackage({...raw, input: {...raw.input, identity} as PackageDescription['input']});
}
