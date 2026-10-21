import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { Adapter, Manifest, Rpc, WorkRequest } from './contracts.ts';
import { ConnectedWorkspaceFiles, selectFileSource } from './connected-workspace-files.ts';
import { workspaceFilesProfile as profile, workspaceFilesVersion as contractVersion } from './workspace-files.ts';
import { ConnectedAdapter } from './transport.ts';
import { core } from './native-test-fixture.ts';

globalThis.morphirWorkbenchExecutions = core();
const manifest = (): Manifest => ({ protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'host-session',
  providers: [{ id: 'workspace', status: 'available', capabilities: [{ name: profile, version: contractVersion }] }],
  initialSources: [{ providerId: 'workspace', locator: 'workspace://root', displayName: 'Host root' }] });
const descriptor = { features: ['read', 'write', 'directories'], limits: { files: 2000, contentBytes: 16777216,
  frameBytes: 1048576, chunkBytes: 196608, transferBytes: 25165824, grants: 8, directories: 256, pathDepth: 16 } };
function fixture() {
  const calls: { method: string; params: Record<string, unknown> }[] = [];
  const files = { 'morphir.toml': "[workspace]\nmembers=[]\n", 'models/raw.ionb': { encoding: 'base64' as const, content: 'AP+A' } };
  const snapshot = Buffer.from(JSON.stringify({ version: 1, files }));
  let revision = 1, bytes: Buffer[] = [], offset = 0, committed: unknown, lost = false, incompatible = false;
  const saved: unknown[] = [];
  const rpc: Rpc = { async call(method, params) {
    calls.push({ method, params: structuredClone(params) });
    if (method === 'morphir.session.initialize') return {};
    assert.equal(method, 'morphir.workspace-files.exchange');
    assert.equal(params.protocolVersion, 1); assert.equal(params.sessionId, 'host-session');
    assert.deepEqual(params.source, manifest().initialSources[0]);
    const frame = JSON.parse(params.frame as string), p = frame.payload, sequence = p?.sequence;
    let value: unknown;
    switch (frame.operation) {
      case 'session.open': case 'session.check': value = incompatible ? { ...descriptor, features: ['read'] } : descriptor; break;
      case 'workspace.choose-write': value = { cancelled: false, grantId: 'root-grant', revision: 0, name: 'Root' }; break;
      case 'workspace.snapshot': value = { sequence, size: snapshot.length, revision }; break;
      case 'workspace.read': value = { sequence, offset: p.offset, content: snapshot.toString('base64'), done: true }; break;
      case 'workspace.begin-edit': assert.equal(p.baseRevision, revision); bytes = []; offset = 0; value = { sequence, offset }; break;
      case 'workspace.write': assert.equal(p.offset, offset); bytes.push(Buffer.from(p.content, 'base64')); offset += bytes.at(-1)!.length; value = { sequence, offset }; break;
      case 'workspace.commit':
        saved.push(JSON.parse(Buffer.concat(bytes).toString())); committed = { sequence, state: 'committed', revision: ++revision };
        if (lost) { lost = false; throw new Error('Commit reply lost'); }
        value = { sequence, revision }; break;
      case 'workspace.status': value = committed; break;
      case 'workspace.release': case 'workspace.revoke': case 'session.close': value = {}; break;
      default: throw new Error(frame.operation);
    }
    return JSON.stringify({ profile, contractVersion, operation: frame.operation, sessionId: 'file-session', ok: true, value });
  } };
  return { rpc, calls, files, saved, loseCommit() { lost = true; }, incompatible() { incompatible = true; } };
}
const local = (): Adapter & { requests: WorkRequest[] } => ({ requests: [], cancel() {}, dispose() {},
  async initialize() { return { success: true, catalog: { frontends: [{ languageId: 'scheme', irVersions: ['4.0.0'], compile: true }], targets: [] } }; },
  async execute(request) { this.requests.push(request); return { success: true, message: 'Local workspace compiled' }; } });

test('file source selection requires one exact available provider offer and root', () => {
  assert.equal(selectFileSource(manifest()).kind, 'selected');
  for (const change of [
    (m: Manifest) => { m.providers[0]!.capabilities = []; },
    (m: Manifest) => { m.providers[0]!.status = 'unavailable'; },
    (m: Manifest) => { m.providers[0]!.capabilities[0]!.version = 'future'; },
    (m: Manifest) => { m.providers[0]!.capabilities.push({ name: profile, version: 'future' }); },
    (m: Manifest) => { m.initialSources.push({ ...m.initialSources[0]!, locator: 'workspace://other' }); },
    (m: Manifest) => { m.sessionId = ''; },
  ]) { const m = manifest(); change(m); assert.equal(selectFileSource(m).kind, 'read-only'); }
});

test('connected frames bind captured source and session and reconcile a lost commit once', async () => {
  const host = fixture(), selection = selectFileSource(manifest()); assert.equal(selection.kind, 'selected');
  if (selection.kind !== 'selected') throw new Error('selection');
  const client = new ConnectedWorkspaceFiles(host.rpc, selection, core());
  selection.source.locator = 'workspace://injected'; selection.sessionId = 'injected';
  const opened = await client.open(); assert.equal(opened.fileAuthority?.kind, 'connected-write');
  assert.deepEqual(opened.workspaceFiles?.files, host.files);
  host.loseCommit();
  assert.equal(await client.save(opened.fileAuthority!.grantId, { version: 1, files: { ...host.files, 'src/main.scm': '42' }, openFile: null }), 2);
  assert.equal(host.calls.filter(c => JSON.parse(c.params.frame as string).operation === 'workspace.commit').length, 1);
  assert.deepEqual(host.saved, [{ version: 1, files: { ...host.files, 'src/main.scm': '42' } }]);
  await assert.rejects(async () => client.save('other-grant', opened.workspaceFiles!), /no longer current/);
  client.dispose();
});

test('connected adapter opens accepted files and compiles the captured tree locally', async () => {
  const host = fixture(), worker = local(), adapter = new ConnectedAdapter(host.rpc, manifest(), worker);
  const initialized = await adapter.initialize();
  assert.equal(initialized.connected, true); assert.equal(initialized.fileAuthority?.kind, 'connected-write');
  assert.equal(initialized.catalog.frontends[0]?.languageId, 'scheme');
  const request: WorkRequest = { operation: 'compile-workspace', workspace: initialized.workspaceFiles! };
  await adapter.execute(request); request.workspace!.files['morphir.toml'] = 'changed later';
  assert.equal(worker.requests[0]?.workspace?.files['morphir.toml'], host.files['morphir.toml']);
  assert.equal(await adapter.saveWorkspace(initialized.fileAuthority!.grantId, initialized.workspaceFiles!), 2);
  adapter.dispose();
});

test('old and incompatible hosts retain read-only behavior without acquiring write authority', async () => {
  const host = fixture(), old = manifest(); old.providers[0]!.capabilities = [];
  const adapter = new ConnectedAdapter(host.rpc, old, local());
  const initialized = await adapter.initialize(); assert.equal(initialized.fileAuthority, undefined);
  assert.match(initialized.workspaceReadOnlyReason!, /does not advertise/);
  assert.deepEqual(host.calls.map(c => c.method), ['morphir.session.initialize']);
  await assert.rejects(adapter.saveWorkspace('invented', { version: 1, files: {}, openFile: null }), /no writable/); adapter.dispose();
  const bad = fixture(); bad.incompatible();
  const fallback = new ConnectedAdapter(bad.rpc, manifest(), local());
  const result = await fallback.initialize(); assert.equal(result.fileAuthority, undefined); assert.match(result.message, /read only/);
  assert.equal(bad.calls.some(c => JSON.parse(c.params.frame as string || '{}').operation === 'workspace.choose-write'), false);
  fallback.dispose();
});
