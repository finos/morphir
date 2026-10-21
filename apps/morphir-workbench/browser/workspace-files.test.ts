import { test } from 'node:test';
import assert from 'node:assert/strict';
import { NativeFilesClient, workspaceFilesProfile as profile, workspaceFilesVersion as contractVersion } from './workspace-files.ts';
import { core } from './native-test-fixture.ts';
import type { Invoke, WorkRequest } from './contracts.ts';
const descriptor = { features: ['read', 'write', 'directories'], limits: { files: 2000, contentBytes: 16777216, frameBytes: 1048576,
  chunkBytes: 196608, transferBytes: 25165824, grants: 8, directories: 256, pathDepth: 16 } };
const workspace = (text = '11'): NonNullable<WorkRequest['workspace']> => ({ version: 1, files: { 'main.scm': text }, openFile: null });
type Frame = { operation: string; sessionId?: string; payload?: Record<string, unknown> };
function fixture(snapshotSource?: string) {
  let revision = 1, upload = '', committed: unknown;
  const calls: Frame[] = [], saves: unknown[] = [];
  let lostCommit = false, badCommit = false;
  const inventory = Buffer.from(snapshotSource ?? JSON.stringify({ version: 1, files: workspace().files }));
  const invoke: Invoke = async (_name, source) => {
    const frame: Frame = JSON.parse(source); calls.push(frame);
    const p = frame.payload!, sequence = p?.sequence;
    let value: unknown;
    switch (frame.operation) {
      case 'session.open': case 'session.check': value = descriptor; break;
      case 'workspace.choose-write': value = { cancelled: false, grantId: 'folder-1', revision: 0, name: 'Workspace' }; break;
      case 'workspace.snapshot': value = { sequence, size: inventory.length, revision }; break;
      case 'workspace.read': value = { sequence, offset: p.offset, content: inventory.toString('base64'), done: true }; break;
      case 'workspace.begin-edit': assert.equal(p.baseRevision, revision); upload = ''; value = { sequence, offset: 0 }; break;
      case 'workspace.write': assert.equal(p.offset, Buffer.from(upload, 'base64').length); upload += p.content; value = { sequence, offset: Buffer.from(upload, 'base64').length }; break;
      case 'workspace.commit':
        saves.push(JSON.parse(Buffer.from(upload, 'base64').toString()));
        committed = { sequence, state: 'committed', revision: ++revision };
        if (lostCommit) { lostCommit = false; throw new Error('Reply lost'); }
        value = badCommit ? { sequence, revision, extra: true } : { sequence, revision }; break;
      case 'workspace.status': if (badCommit) throw new Error('Status lost'); value = committed; break;
      case 'workspace.release': case 'workspace.revoke': case 'workspace.cancel-picker': case 'session.close': value = {}; break;
      default: throw new Error(frame.operation);
    }
    return JSON.stringify({ profile, contractVersion, operation: frame.operation, sessionId: 'files-page', ok: true, value });
  };
  return { invoke, calls, saves, loseCommit() { lostCommit = true; }, corruptCommit() { badCommit = true; } };
}

test('a missing commit acknowledgement reconciles status without resubmitting an edit', async () => {
  const host = fixture(), client = new NativeFilesClient(host.invoke, core());
  await client.open(); const opened = await client.choose(); assert.ok(opened);
  assert.deepEqual(opened.workspace, workspace());
  host.loseCommit(); assert.equal(await client.save(opened.authority.grantId, workspace('22')), 2);
  assert.equal(host.calls.filter(c => c.operation === 'workspace.commit').length, 1);
  assert.equal(host.calls.filter(c => c.operation === 'workspace.status').length, 1);
  assert.equal(await client.save(opened.authority.grantId, workspace('33')), 3); client.dispose();
});

test('queued saves capture bytes immediately and use the preceding acknowledged revision', async () => {
  const host = fixture(), client = new NativeFilesClient(host.invoke, core());
  await client.open(); const opened = (await client.choose())!;
  const changed = workspace('22'); const first = client.save(opened.authority.grantId, changed);
  changed.files['main.scm'] = '33'; const second = client.save(opened.authority.grantId, changed);
  changed.files['main.scm'] = '44';
  assert.deepEqual(await Promise.all([first, second]), [2, 3]);
  assert.deepEqual(host.saves, [{ version: 1, files: workspace('22').files }, { version: 1, files: workspace('33').files }]); client.dispose();
});

test('incompatible commit and unavailable reconciliation block every later save', async () => {
  const host = fixture(), client = new NativeFilesClient(host.invoke, core());
  await client.open(); const opened = (await client.choose())!; host.corruptCommit();
  await assert.rejects(client.save(opened.authority.grantId, workspace('22')), /Status lost/);
  await assert.rejects(client.save(opened.authority.grantId, workspace('33')), /reconciliation/);
  assert.equal(host.calls.filter(c => c.operation === 'workspace.begin-edit').length, 1); client.dispose();
});

test('wrong sessions and expanded descriptors never establish a file channel', async () => {
  for (const value of [{ ...descriptor, unexpected: true }, { ...descriptor, features: ['read'] }]) {
    const client = new NativeFilesClient(async () => JSON.stringify({ profile, contractVersion, operation: 'session.open', sessionId: 'page', ok: true, value }), core());
    await assert.rejects(client.open(), /incompatible/); client.dispose();
  }
  const host = fixture(); const client = new NativeFilesClient(async (name, source) => {
    const raw = JSON.parse(await host.invoke(name, source) as string);
    if (raw.operation === 'session.check') raw.sessionId = 'replacement';
    return JSON.stringify(raw);
  }, core());
  await client.open(); await assert.rejects(client.choose(), /incompatible/);
  assert.equal(host.calls.filter(c => c.operation === 'workspace.choose-write').length, 0); client.dispose();
});

test('cancelling while session admission waits cannot launch a late folder picker', async () => {
  const host = fixture();
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const client = new NativeFilesClient(async (name, source) => {
    const reply = await host.invoke(name, source);
    if (JSON.parse(source).operation === 'session.check') await gate;
    return reply;
  }, core());
  await client.open(); const pending = client.choose();
  await new Promise(setImmediate); await client.cancelPicker(); release();
  await assert.rejects(pending, /cancelled/);
  assert.equal(host.calls.filter(c => c.operation === 'workspace.choose-write').length, 0); client.dispose();
});


test('downloaded inventories reject duplicate paths escapes and noncanonical bytes before publication', async () => {
  for (const inventory of [
    '{"version":1,"files":{"a":"first","a":"second"}}',
    '{"version":1,"files":{"../outside":"value"}}',
    '{"version":1,"files":{"a":{"encoding":"base64","content":"YR=="}}}',
    '{"version":1,"files":{},"openFile":"injected"}',
  ]) {
    const host = fixture(inventory), client = new NativeFilesClient(host.invoke, core());
    await client.open(); await assert.rejects(client.choose(), /inventory/);
    assert.equal(host.calls.some(c => c.operation === 'workspace.revoke'), true);
    assert.equal(host.calls.some(c => c.operation === 'workspace.begin-edit'), false); client.dispose();
  }
});
