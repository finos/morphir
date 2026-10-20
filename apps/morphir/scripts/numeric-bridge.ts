import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {isRecord} from '../../../types/data.ts';
import type {NumericBridge} from './test-installed-numeric.ts';

/** Load the already-built test codec; this adapter never builds or installs it. */
export async function loadNumericBridge(repository: string): Promise<NumericBridge> {
  const artifact=join(repository,'_build/js/debug/build/finos/morphir-engine/acceptance/numeric-qualification/numeric-qualification.js');
  assert.ok(existsSync(artifact),'Build the numeric-qualification JS fixture before installed acceptance');
  await import(pathToFileURL(artifact).href);
  const host=globalThis as typeof globalThis & {morphirNumericQualificationFixture?:(request:string)=>string};
  const handler=host.morphirNumericQualificationFixture;assert.ok(handler,'Numeric test codec was not exposed');
  function call<T>(request: unknown): T {
    const response:unknown=JSON.parse(handler!(JSON.stringify(request)));
    assert.ok(isRecord(response));assert.equal(response.ok,true,String(response.error));
    // The compiled fixture uses production Registry/Value decoders before returning.
    return response.value as T;
  }
  const binary=(bytes:Uint8Array)=>({format:'ion-binary',base64:Buffer.from(bytes).toString('base64')});
  return {
    inspect:bytes=>call({op:'inspect',...binary(bytes)}),
    augment:bytes=>call({op:'augment',...binary(bytes)}),
    symbols:bytes=>call({op:'symbols',...binary(bytes)}),
    scheme:(bytes,suite)=>call({op:'scheme',...binary(bytes),suite}),
    cases:rows=>call({op:'cases',rows}),
    conformance:bytes=>call({op:'conformance',...binary(bytes)}),
  };
}
