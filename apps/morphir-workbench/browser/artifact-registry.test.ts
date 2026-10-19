import { test } from 'node:test';
import assert from 'node:assert/strict';
import { unzipSync } from 'fflate';
import { artifactBytes, projectArchive } from './artifact-download.ts';
import { ArtifactDownloadRegistry } from './artifact-registry.ts';
import { VerifiedArtifactSet } from './verified-artifacts.ts';
import { captureArtifactGeneration, decodeArtifactGenerateReply, parseArtifactRequestId,
  selectArtifactTransferProfile } from './artifact-client/artifact-transfer.ts';

// Independently authored shared recipes, OpenSSL cross-checked before this registry.
const recipes = [
  { id: 'original', path: 'src/original.txt', kind: 'utf8-text', hex: 'efbbbf2f2f204d6f72706869720d0a6c657420636166c3a9203d2022cf80f09f9880220d0a0d0a',
    byteLength: 39, sha256: '15b81d596c1cb52dc53a64267afb7cf84acb06f72a57ec16d9aa07727b0ec349' },
  { id: 'binary', path: 'data/bytes.bin', kind: 'binary', hex: '00ffc328eda080f5808080fe00', byteLength: 13,
    sha256: '6c28fb3ec520f16a169d49e1b8bd284d6f588047a91455adc1c32d04865e9432' },
  { id: 'invalid', path: 'src/invalid.txt', kind: 'utf8-text', hex: '00ffc328eda080f5808080fe00', byteLength: 13,
    sha256: '6c28fb3ec520f16a169d49e1b8bd284d6f588047a91455adc1c32d04865e9432' },
  { id: 'empty', path: 'data/empty.bin', kind: 'binary', hex: '', byteLength: 0,
    sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' },
];
async function verified(entries = recipes) {
  const selected = selectArtifactTransferProfile({ id: 'playground', status: 'available', capabilities: [
    { name: 'morphir/workbench/artifacts', version: '0.1.0-draft.1' },
  ] });
  if (!selected.ok) throw new Error('Invalid fixture selection');
  const capture = captureArtifactGeneration(selected.value, { sessionId: 'session', target: 'fixture', irVersion: '4' });
  const id = parseArtifactRequestId(2);
  if (!capture.ok || !id.ok) throw new Error('Invalid fixture capture');
  const decoded = decodeArtifactGenerateReply(JSON.stringify({ jsonrpc: '2.0', id: 2, result: {
    status: 'ready', profile: 'morphir/workbench/artifacts', contractVersion: '0.1.0-draft.1', sessionId: 'session',
    providerId: 'playground', generationId: 'generation', producer: { id: 'fixture', version: '1.0.0' }, target: 'fixture', irVersion: '4',
    artifacts: entries.map(({ hex: _hex, ...descriptor }) => descriptor), diagnostics: [],
  } }), capture.value, id.value);
  if (!decoded.ok || decoded.value.status !== 'ready') throw new Error('Invalid fixture manifest');
  const received = new Map(decoded.value.artifacts.map((descriptor, index) => [descriptor.id, Uint8Array.from(Buffer.from(entries[index]!.hex, 'hex'))]));
  return VerifiedArtifactSet.verify(decoded.value, received, { isCurrent: () => true });
}

test('JSON UI roundtrip carries handles and previews while downloads retain original bytes', async () => {
  const registry = new ArtifactDownloadRegistry();
  const display = JSON.parse(JSON.stringify(registry.publish(await verified())));
  assert.equal(display[0].content.charCodeAt(0), 0xfeff);
  assert.match(display[0].content, /\r\n/);
  assert.equal(display[2].previewState, 'invalid-utf8');
  assert.match(display[2].content, /invalid UTF-8/);
  assert.equal(display[1].content, '');
  const archive = unzipSync(projectArchive(display, registry));
  assert.deepEqual(Object.keys(archive), recipes.map(recipe => recipe.path));
  for (let index = 0; index < recipes.length; ++index) {
    const recipe = recipes[index]!;
    assert.deepEqual(archive[recipe.path], Uint8Array.from(Buffer.from(recipe.hex, 'hex')));
    assert.deepEqual(artifactBytes([display[index]], registry)[recipe.path], archive[recipe.path]);
  }
});

test('mutating preview strings and returned buffers cannot alter a verified download or ZIP', async () => {
  const registry = new ArtifactDownloadRegistry(); const display = registry.publish(await verified());
  const original = projectArchive(display, registry);
  for (const file of display) { file.content = 'mutated preview'; file.binary = false; file.previewBase64 = 'AA=='; }
  const leaked = artifactBytes([display[1]], registry)[recipes[1]!.path]!; leaked.fill(0);
  assert.deepEqual(projectArchive(display, registry), original);
});

test('replacement and clear invalidate every older handle without falling back to preview content', async () => {
  const registry = new ArtifactDownloadRegistry(); const files = await verified();
  const older = registry.publish(files); const newer = registry.publish(files);
  assert.throws(() => artifactBytes([older[0]], registry), /stale/);
  assert.doesNotThrow(() => projectArchive(newer, registry));
  registry.clear();
  assert.throws(() => artifactBytes([newer[0]], registry), /no longer/);
});

test('mixed, forged, path-swapped and duplicate selections fail before any archive is produced', async () => {
  const registry = new ArtifactDownloadRegistry(); const files = registry.publish(await verified());
  const other = new ArtifactDownloadRegistry(); const foreign = other.publish(await verified());
  const withPath = { ...files[0], path: 'outside.txt' };
  const withId = { ...files[0], verifiedArtifact: { ...files[0]!.verifiedArtifact!, artifactId: 'forged' } };
  const legacy = { path: 'src/legacy.txt', content: 'unverified', binary: false };
  for (const selection of [[files[0], files[0], files[2], files[3]], [files[0], files[1], files[2], foreign[3]],
    [files[0], files[1], files[2], legacy], [withPath, ...files.slice(1)], [withId, ...files.slice(1)]]) {
    assert.throws(() => projectArchive(selection, registry), /reference|verified/);
  }
  assert.throws(() => projectArchive(files.slice(1), registry), /inventory/);
  assert.throws(() => artifactBytes(files, registry), /inventory/);
  assert.throws(() => artifactBytes([{ path: 'fake.txt', content: 'x', binary: false, encoding: 'verified-bytes' }], registry), /reference/);
});

test('aggregate preview limits preserve full download bytes for a many-file inventory', async () => {
  const entries = Array.from({ length: 32 }, (_, index) => ({ id: `file-${index}`, path: `src/file-${index}.txt`,
    kind: 'utf8-text', hex: '61'.repeat(65537), byteLength: 65537,
    sha256: '008ffc88d3c96a9f307524eb361e47c5222a887fc45fa0c1fb8d429c5c23b430' }));
  const registry = new ArtifactDownloadRegistry(); const files = registry.publish(await verified(entries));
  assert.ok(files.reduce((total, file) => total + file.content.length, 0) <= 1048576);
  assert.ok(files.every(file => file.previewState === 'text-prefix'));
  const archive = unzipSync(projectArchive(files, registry));
  assert.equal(Object.keys(archive).length, 32);
  for (const entry of entries) assert.deepEqual(archive[entry.path], new Uint8Array(65537).fill(97));
});
