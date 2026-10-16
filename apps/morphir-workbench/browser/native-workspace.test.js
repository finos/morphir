import { test } from 'node:test';
import assert from 'node:assert/strict';
import { NativeWorkspaceClient } from './native-workspace.js';
import { NativeSession } from './native-session.js';
import { core, descriptor, bridge, failure, version } from './native-test-fixture.js';

const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
function fixture(bytes = Buffer.from(' {"formatVersion":1,"exact":9007199254740993} ')) {
  const calls = []; const localCalls = [];
  const host = { retired: 0, active: null, offset: 0, releaseFailures: 0, valid: true };
  const offer = { cancelled: false, grantId: 'workspace-1', projects: [{ id: 'project-0', name: 'Example', available: true, message: '' }], warnings: [] };
  const handle = body => {
    if (body.action === 'release') {
      if (host.releaseFailures-- > 0) return failure('unavailable', 'unknown');
      if (host.active !== null && body.sequence !== host.active) return failure('conflict', 'none');
      host.active = null; host.retired = Math.max(host.retired, body.sequence); return {};
    }
    if (body.action === 'open') {
      if (body.sequence <= host.retired) return failure('conflict', 'none');
      host.active = body.sequence; host.offset = 0;
      return { sequence: body.sequence, size: bytes.length, filename: 'morphir-ir.ionb', format: 'ion-binary' };
    }
    if (body.action === 'read') {
      assert.equal(body.sequence, host.active); assert.equal(body.offset, host.offset);
      const part = bytes.subarray(host.offset, host.offset + 192 * 1024); host.offset += part.length;
      return { sequence: body.sequence, offset: body.offset, content: part.toString('base64'), done: host.offset === bytes.length };
    }
    return {};
  };
  const session = new NativeSession(bridge(async frame => {
    calls.push(['app:workbench_native', JSON.stringify(frame)]);
    if (!host.valid) throw new Error('stale session');
    if (frame.operation.startsWith('session.')) return { ...descriptor, operations: ['workspace'] };
    assert.equal(frame.sessionId, descriptor.sessionId);
    if (frame.operation === 'workspace.choose') return host.choose ? host.choose() : offer;
    const body = { action: frame.operation.slice('workspace.'.length), ...frame.payload };
    if (host.intercept) return host.intercept(body, handle);
    return handle(body);
  }), 50, core());
  const ready = session.open();
  const check = session.check.bind(session);
  session.check = async () => { await ready; return check(); };
  const local = { cancel() {}, async execute(request) { localCalls.push(request); return { success: true, irSource: '{"formatVersion":4}' }; } };
  return { client: new NativeWorkspaceClient(session, local), host, session, calls, localCalls, offer, handle };
}

test('only exact canonical native capabilities with directly nested jobs offers are admitted', async () => {
  const offer = { profile: 'morphir/workbench/jobs', contractVersion: version, hostId: 'h', sessionId: descriptor.sessionId, providerId: 'p', operations: ['query'] };
  for (const operations of [[], ['jobs'], ['workspace'], ['jobs', 'workspace']]) {
    const value = { ...descriptor, operations, ...(operations.includes('jobs') ? { offer } : {}) };
    const session = new NativeSession(bridge(() => value), 50, core()); await session.open(); await session.check();
  }
  for (const operations of [[''], ['jobs,workspace'], ['workspace', 'jobs'], ['jobs', 'jobs'], ['filesystem'], [null]]) {
    await assert.rejects(new NativeSession(bridge(() => ({ ...descriptor, operations })), 50, core()).open(), /incompatible/);
  }
});

test('native project transfer preserves every byte across chunks and releases before inspection', async () => {
  const bytes = Buffer.alloc(500003, 0x81); bytes.write('9007199254740993');
  const f = fixture(bytes); await f.client.choose();
  const result = await f.client.openProject('project-0');
  assert.equal(f.host.active, null); assert.equal(f.host.retired, 1);
  assert.deepEqual(Buffer.from(result.originalArtifact.content, 'base64'), bytes);
  assert.equal(f.localCalls[0].source, ''); assert.equal(f.localCalls[0].sourceCodec, 'ion-binary');
  assert.equal(f.localCalls[0].sourceBase64, bytes.toString('base64'));
  assert.equal(result.operation, 'project');
});

test('picker cancellation retains the old project offer; no renderer path reaches the picker', async () => {
  const f = fixture(); await f.client.choose(); f.host.choose = () => ({ cancelled: true });
  const result = await f.client.choose(); assert.equal(result.cancelled, true); assert.equal(result.projects.length, 1);
  assert.equal(f.calls.filter(([, source]) => JSON.parse(source).operation === 'workspace.choose').length, 2);
  assert.ok(f.calls.every(([, source]) => { const f = JSON.parse(source); return f.operation !== 'workspace.choose' || Object.keys(f).sort().join(',') === 'contractVersion,operation,profile,sessionId'; }));
});

test('late picker completion after explicit cancellation revokes the unaccepted grant', async () => {
  const f = fixture(); const wait = deferred(); f.host.choose = () => wait.promise;
  const choosing = f.client.choose(); await new Promise(setImmediate); await f.client.cancel(); wait.resolve(f.offer);
  await assert.rejects(choosing, /no longer current/);
  assert.equal(f.client.grant, null);
  assert.ok(f.calls.some(([, source]) => JSON.parse(source).operation === 'workspace.revoke'));
});

test('invalid chunks fail closed and still release the captured model', async () => {
  for (const mutate of [r => ({ ...r, offset: 1 }), r => ({ ...r, done: false }), r => ({ ...r, content: '%%%%' }), r => ({ ...r, sequence: 99 }), r => ({ ...r, extra: true })]) {
    const f = fixture(); await f.client.choose();
    f.host.intercept = (body, handle) => { const reply = handle(body); return body.action === 'read' ? mutate(reply) : reply; };
    await assert.rejects(f.client.openProject('project-0'), /chunk|incompatible/);
    assert.equal(f.host.active, null); assert.equal(f.localCalls.length, 0);
  }
});

test('unconfirmed release prevents another open until the same transfer is released', async () => {
  const f = fixture(); await f.client.choose(); f.host.releaseFailures = 2;
  await assert.rejects(f.client.openProject('project-0'));
  await assert.rejects(f.client.openProject('project-0'));
  assert.equal(f.calls.filter(([, source]) => JSON.parse(source).operation === 'workspace.open').length, 1);
  assert.equal(f.localCalls.length, 0); assert.deepEqual(f.client.pendingRelease, { grantId: 'workspace-1', sequence: 1 });
  await f.client.openProject('project-0'); assert.equal(f.client.pendingRelease, null); assert.equal(f.host.retired, 2);
});

test('concurrent opens are refused and cancellation waits for active admission cleanup', async () => {
  const f = fixture(); await f.client.choose(); const wait = deferred();
  f.host.intercept = async (body, handle) => { const result = handle(body); if (body.action === 'open') await wait.promise; return result; };
  const opening = f.client.openProject('project-0'); await new Promise(setImmediate);
  await assert.rejects(f.client.openProject('project-0'), /still active/);
  await f.client.cancel(); assert.equal(f.host.retired, 0); wait.resolve();
  await assert.rejects(opening, /no longer current/); assert.equal(f.host.retired, 1); assert.equal(f.host.active, null);
});

test('lost open replies retire their sequence and stale sessions never invoke local inspection', async () => {
  const f = fixture(); await f.client.choose(); f.session.timeout = 5; const wait = deferred();
  f.host.intercept = async (body, handle) => { if (body.action === 'open') await wait.promise; return handle(body); };
  await assert.rejects(f.client.openProject('project-0'), /timed out/); assert.equal(f.host.retired, 1);
  wait.resolve(); await new Promise(setImmediate); assert.equal(f.host.active, null); assert.equal(f.localCalls.length, 0);
  const g = fixture(); await g.client.choose();
  g.host.intercept = (body, handle) => { const reply = handle(body); if (body.action === 'open') g.host.valid = false; return reply; };
  await assert.rejects(g.client.openProject('project-0'), /stale/); assert.equal(g.localCalls.length, 0);
});

test('interactive picker latency is independent of request deadlines', async () => {
  const f = fixture(); f.session.timeout = 5;
  f.host.choose = async () => { await new Promise(resolve => setTimeout(resolve, 25)); return { cancelled: true }; };
  const result = await f.client.choose(); assert.equal(result.cancelled, true);
});
