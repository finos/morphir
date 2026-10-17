import {test} from 'node:test';
import assert from 'node:assert/strict';
import {unzipSync, strFromU8} from 'fflate';
import {artifactBytes, projectArchive} from './artifact-download.ts';

const artifacts = [
  {path:'src/User/Main.elm',content:'module User.Main exposing (main)\n\nmain = "雪"\n',binary:false},
  {path:'elm.json',content:'{"type":"package"}\n',binary:false},
  {path:'morphir.json',content:'',binary:false},
];
test('project ZIP preserves every original path and exact UTF-8 file, including empty files', () => {
  const files=unzipSync(projectArchive(artifacts));
  assert.deepEqual(Object.keys(files),artifacts.map(a=>a.path));
  for(const a of artifacts)assert.equal(strFromU8(files[a.path]!),a.content);
  assert.deepEqual(projectArchive(artifacts),projectArchive(artifacts));
});
test('downloads reject escaping, duplicate, colliding and undeclared binary file encodings', () => {
  for(const path of ['../outside.elm','/absolute','src/../outside','src\\Main.elm','C:/Main.elm','src//Main.elm','src/./Main.elm','bad\0path']) {
    assert.throws(()=>artifactBytes([{path,content:'x',binary:false}]),/path/);
  }
  for(const path of ['elm.json','ELM.JSON','src','src/User/Main.elm/child']) {
    assert.throws(()=>artifactBytes([...artifacts,{path,content:'x',binary:false}]),/conflict/);
  }
  assert.throws(()=>projectArchive([...artifacts,{path:'metadata.ionb',content:'opaque',binary:true}]),/binary/);
  assert.throws(()=>artifactBytes([{path:'valid.elm',content:42,binary:false}]),/content/);
  assert.throws(()=>artifactBytes([]),/no generated files/);
});

test('local binary encoding preserves all bytes in file and project exports', () => {
  const bytes = Uint8Array.from({length:256}, (_, i) => i);
  const content = btoa(String.fromCharCode(...bytes));
  const binary = {path:'symbols.10n',content,binary:true,encoding:'base64'};
  assert.deepEqual(artifactBytes([binary])['symbols.10n'],bytes);
  assert.deepEqual(unzipSync(projectArchive([...artifacts,binary]))['symbols.10n'],bytes);
  for (const content of ['garbage!', 'YQ', 'YR==', 'YQ===', 'Y Q==']) {
    assert.throws(()=>artifactBytes([{...binary,content}]),/encoding/);
  }
});
