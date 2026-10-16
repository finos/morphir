import { test } from 'node:test';
import assert from 'node:assert/strict';
import { NativeWorkspaceClient } from './native-workspace.js';
import { NativeSession, nativeBridgeVersion } from './native-session.js';

const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
function fixture(bytes = Buffer.from(' {"formatVersion":1,"exact":9007199254740993} ')) {
  const calls = []; const localCalls = [];
  const host = { retired: 0, active: null, offset: 0, releaseFailures: 0, valid: true };
  const offer = { ok: true, cancelled: false, grantId: 'workspace-1', projects: [{ id: 'project-0', name: 'Example', available: true, message: '' }], warnings: [] };
  const handle = body => {
    if (body.action === 'release') {
      if (host.releaseFailures-- > 0) return { ok: false, code: 'workbench.workspace_io' };
      if (host.active !== null && body.sequence !== host.active) return { ok: false, code: 'workbench.workspace_capture' };
      host.active = null; host.retired = Math.max(host.retired, body.sequence); return { ok: true };
    }
    if (body.action === 'open') {
      if (body.sequence <= host.retired) return { ok: false, code: 'workbench.workspace_retired' };
      host.active = body.sequence; host.offset = 0;
      return { ok: true, sequence: body.sequence, size: bytes.length, filename: 'morphir-ir.ionb', format: 'ion-binary' };
    }
    if (body.action === 'read') {
      assert.equal(body.sequence, host.active); assert.equal(body.offset, host.offset);
      const part = bytes.subarray(host.offset, host.offset + 192 * 1024); host.offset += part.length;
      return { ok: true, sequence: body.sequence, offset: body.offset, content: part.toString('base64'), done: host.offset === bytes.length };
    }
    return { ok: true };
  };
  const session = { id: 'native-session-1', timeout: 50, async check() { if (!host.valid) throw new Error('stale session'); },
    async invoke(name, payload) {
      calls.push([name, payload]);
      if (name === 'app:workbench_workspace_choose') { assert.equal(payload, session.id); return host.choose ? host.choose() : offer; }
      assert.equal(name, 'app:workbench_workspace');
      const wrapper = JSON.parse(payload); assert.equal(wrapper.sessionId, session.id);
      const body = JSON.parse(wrapper.body);
      if (host.intercept) return host.intercept(body, handle);
      return handle(body);
    } };
  const local = { cancel() {}, async execute(request) { localCalls.push(request); return { success: true, irSource: '{"formatVersion":4}' }; } };
  return { client: new NativeWorkspaceClient(session, local), host, session, calls, localCalls, offer, handle };
}

test('only exact, unique, canonical native operation lists are admitted', async () => {
  const descriptor = { ok: true, bridgeVersion: nativeBridgeVersion, sessionId: 'native-1', operations: [] };
  for (const operations of [[], ['jobs'], ['workspace'], ['jobs', 'workspace']]) {
    const session = new NativeSession(async () => ({ ...descriptor, operations })); await session.open(); await session.check();
  }
  for (const operations of [[''], ['jobs,workspace'], ['workspace', 'jobs'], ['jobs', 'jobs'], ['filesystem'], [null]]) {
    await assert.rejects(new NativeSession(async () => ({ ...descriptor, operations })).open(), /incompatible/);
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
  const f = fixture(); await f.client.choose(); f.host.choose = () => ({ ok: true, cancelled: true });
  const result = await f.client.choose(); assert.equal(result.cancelled, true); assert.equal(result.projects.length, 1);
  assert.equal(f.calls.filter(([name]) => name.endsWith('_choose')).length, 2);
  assert.ok(f.calls.every(([name, payload]) => !name.endsWith('_choose') || payload === f.session.id));
});

test('late picker completion after explicit cancellation revokes the unaccepted grant', async () => {
  const f = fixture(); const wait = deferred(); f.host.choose = () => wait.promise;
  const choosing = f.client.choose(); await new Promise(setImmediate); await f.client.cancel(); wait.resolve(f.offer);
  await assert.rejects(choosing, /no longer current/);
  assert.equal(f.client.grant, null);
  assert.ok(f.calls.some(([name, source]) => name === 'app:workbench_workspace' && JSON.parse(JSON.parse(source).body).action === 'revoke'));
});

test('invalid chunks fail closed and still release the captured model', async () => {
  for (const mutate of [r => ({ ...r, offset: 1 }), r => ({ ...r, done: false }), r => ({ ...r, content: '%%%%' }), r => ({ ...r, sequence: 99 }), r => ({ ...r, extra: true })]) {
    const f = fixture(); await f.client.choose();
    f.host.intercept = (body, handle) => { const reply = handle(body); return body.action === 'read' ? mutate(reply) : reply; };
    await assert.rejects(f.client.openProject('project-0'), /chunk/);
    assert.equal(f.host.active, null); assert.equal(f.localCalls.length, 0);
  }
});

test('unconfirmed release prevents another open until the same transfer is released', async () => {
  const f = fixture(); await f.client.choose(); f.host.releaseFailures = 2;
  await assert.rejects(f.client.openProject('project-0'));
  await assert.rejects(f.client.openProject('project-0'));
  assert.equal(f.calls.filter(([n, b]) => n === 'app:workbench_workspace' && JSON.parse(JSON.parse(b).body).action === 'open').length, 1);
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
