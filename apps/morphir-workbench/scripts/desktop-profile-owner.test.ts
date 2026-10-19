import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, readdir, rename, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { NormalPackageExit, TemporaryProfileOwner } from './desktop-profile-owner.ts';

async function fixture(run: (parent: string, owner: TemporaryProfileOwner, profile: string) => Promise<void>) {
  const parent = await mkdtemp(join(tmpdir(), 'morphir-profile-test-'));
  try {
    const owner = await TemporaryProfileOwner.create(parent);
    const profile = join(owner.path, 'proton-cef-owned');
    await mkdir(profile);
    await owner.observe();
    await run(parent, owner, profile);
  } finally { await rm(parent, { recursive: true, force: true }); }
}
const normal = () => {
  const supervised = { code: 0, signal: null, stdout: '', stderr: 'CEF output' };
  return NormalPackageExit.checked(supervised, true);
};

test('failed, signalled and unconfirmed process exits cannot authorize profile removal', async () => fixture(async (_, owner, profile) => {
  await writeFile(join(profile, 'retained'), 'original');
  for (const [exit, quiescent] of [
    [{ code: 1, signal: null }, true], [{ code: 0, signal: 'SIGTERM' }, true], [{ code: 0, signal: null }, false],
  ] as const) assert.throws(() => NormalPackageExit.checked(exit, quiescent));
  assert.equal(await readFile(join(profile, 'retained'), 'utf8'), 'original');
  assert.equal((await readdir(owner.path)).length, 1);
}));
test('owned leftovers are removed after quiescence and attributed to the harness', async () => fixture(async (parent, owner, profile) => {
  await writeFile(join(parent, 'unrelated'), 'keep');
  await mkdir(join(profile, 'BrowserMetrics'));
  await writeFile(join(profile, 'BrowserMetrics', 'metrics.pma'), 'metrics');
  const result = await owner.cleanupAfterExit(normal());
  assert.equal(result.cleanupActor, 'harness'); assert.equal(result.appSelfRemoved, false);
  assert.deepEqual(result.beforeCleanup, ['proton-cef-owned']);
  assert.deepEqual(await readdir(owner.path), []);
  assert.equal(await readFile(join(parent, 'unrelated'), 'utf8'), 'keep');
}));
test('application profile removal is reported separately', async () => fixture(async (_, owner, profile) => {
  await rm(profile, { recursive: true });
  const result = await owner.cleanupAfterExit(normal());
  assert.equal(result.cleanupActor, 'none'); assert.equal(result.appSelfRemoved, true);
  assert.deepEqual(result.beforeCleanup, []);
}));
test('observation tolerates live runtime temporary files without owning them', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'morphir-profile-transient-test-'));
  try {
    const owner = await TemporaryProfileOwner.create(parent);
    const profile = join(owner.path, 'proton-cef-owned'); await mkdir(profile);
    const temporary = join(owner.path, 'runtime-temporary'); await writeFile(temporary, 'live');
    assert.deepEqual(await owner.observe(), ['proton-cef-owned']);
    assert.equal(await readFile(temporary, 'utf8'), 'live');
    await rm(temporary);
    const cleanup = await owner.cleanupAfterExit(normal());
    assert.equal(cleanup.cleanupActor, 'harness');
    assert.deepEqual(cleanup.temporaryRetention, { kind: 'empty' });
  } finally { await rm(parent, { recursive: true, force: true }); }
});
test('observation refuses ambiguous profile candidates', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'morphir-profile-ambiguous-test-'));
  try {
    const owner = await TemporaryProfileOwner.create(parent);
    await mkdir(join(owner.path, 'proton-cef-first'));
    await mkdir(join(owner.path, 'proton-cef-second'));
    await assert.rejects(owner.observe(), /one fresh CEF profile/);
    assert.deepEqual((await readdir(owner.path)).sort(), ['proton-cef-first', 'proton-cef-second']);
  } finally { await rm(parent, { recursive: true, force: true }); }
});
test('profile cleanup preserves and reports nonprofile siblings', async () => fixture(async (_, owner) => {
  const extraction = 'appimage_extracted_fixture';
  await mkdir(join(owner.path, extraction));
  await writeFile(join(owner.path, extraction, 'AppRun'), 'keep');
  const cleanup = await owner.cleanupAfterExit(normal());
  assert.equal(cleanup.cleanupActor, 'harness');
  assert.deepEqual(cleanup.temporaryRetention, { kind: 'preserved', root: owner.path, entries: [extraction] });
  assert.deepEqual(await readdir(owner.path), [extraction]);
  assert.equal(await readFile(join(owner.path, extraction, 'AppRun'), 'utf8'), 'keep');
}));
test('application profile removal is distinct from retained extraction files', async () => fixture(async (_, owner, profile) => {
  await rm(profile, { recursive: true });
  await writeFile(join(owner.path, 'runtime-state'), 'keep');
  const cleanup = await owner.cleanupAfterExit(normal());
  assert.equal(cleanup.appSelfRemoved, true); assert.equal(cleanup.cleanupActor, 'none');
  assert.deepEqual(cleanup.temporaryRetention, { kind: 'preserved', root: owner.path, entries: ['runtime-state'] });
  assert.equal(await readFile(join(owner.path, 'runtime-state'), 'utf8'), 'keep');
}));
test('an unknown CEF profile refuses cleanup before removing the observed profile', async () => fixture(async (_, owner) => {
  await mkdir(join(owner.path, 'proton-cef-other'));
  await assert.rejects(owner.cleanupAfterExit(normal()), /unobserved/);
  assert.deepEqual((await readdir(owner.path)).sort(), ['proton-cef-other', 'proton-cef-owned']);
}));
test('a replaced profile link never redirects removal to an outside directory', async () => fixture(async (parent, owner, profile) => {
  const outside = join(parent, 'outside'); await mkdir(outside);
  await writeFile(join(outside, 'keep'), 'original');
  await rm(profile, { recursive: true }); await symlink(outside, profile, 'junction');
  await assert.rejects(owner.cleanupAfterExit(normal()), /replaced profile/);
  assert.equal(await readFile(join(outside, 'keep'), 'utf8'), 'original');
}));
test('a replaced ordinary root cannot supply a different observed profile', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'morphir-profile-root-test-'));
  try {
    const owner = await TemporaryProfileOwner.create(parent);
    await rename(owner.path, join(parent, 'original'));
    await mkdir(owner.path); await mkdir(join(owner.path, 'proton-cef-replacement'));
    await assert.rejects(owner.observe(), /replaced temporary root/);
    assert.deepEqual(await readdir(owner.path), ['proton-cef-replacement']);
  } finally { await rm(parent, { recursive: true, force: true }); }
});
test('a replaced ordinary root cannot redirect cleanup to matching profile names', async () => fixture(async (parent, owner) => {
  await rename(owner.path, join(parent, 'original'));
  await mkdir(owner.path);
  const replacement = join(owner.path, 'proton-cef-owned'); await mkdir(replacement);
  await writeFile(join(replacement, 'keep'), 'replacement');
  await assert.rejects(owner.cleanupAfterExit(normal()), /replaced temporary root/);
  assert.equal(await readFile(join(replacement, 'keep'), 'utf8'), 'replacement');
}));
test('a replaced ordinary profile is not the observed directory', async () => fixture(async (parent, owner, profile) => {
  await rename(profile, join(parent, 'original-profile'));
  await mkdir(profile); await writeFile(join(profile, 'keep'), 'replacement');
  await assert.rejects(owner.cleanupAfterExit(normal()), /replaced profile/);
  assert.equal(await readFile(join(profile, 'keep'), 'utf8'), 'replacement');
}));
