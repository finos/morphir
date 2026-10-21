import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WorkspaceFilesRpc, openWorkspaceFilesRpc } from './workspace-files-rpc.ts';
import { core } from './native-test-fixture.ts';

class Socket extends EventTarget {
  readyState = 1; closed = 0; sent: string[] = [];
  handle: (source: string) => void = () => {};
  send(source: string) { this.sent.push(source); this.handle(source); }
  close() { this.closed++; this.readyState = 3; }
  reply(source: unknown) { this.dispatchEvent(new MessageEvent('message', { data: source })); }
}

test('file RPC correlates complete raw envelopes and leaves RPC errors available for status reconciliation', async () => {
  const socket = new Socket(), rpc = new WorkspaceFilesRpc(socket, core());
  socket.handle = source => { const { id } = JSON.parse(source); queueMicrotask(() => socket.reply(JSON.stringify({ jsonrpc: '2.0', id, error: { code: -32603, message: 'Commit reply lost' } }))); };
  await assert.rejects(rpc.call('morphir.workspace-files.exchange', {}), /Commit reply lost/);
  socket.handle = source => { const { id } = JSON.parse(source); queueMicrotask(() => socket.reply(JSON.stringify({ jsonrpc: '2.0', id, result: 'exact file reply' }))); };
  assert.equal(await rpc.call('morphir.workspace-files.exchange', {}), 'exact file reply');
  rpc.dispose(); assert.equal(socket.closed, 1);
});

test('duplicate substituted and oversized envelopes close the owning file connection', async () => {
  for (const reply of ['{"jsonrpc":"2.0","id":1,"id":1,"result":"value"}',
    '{"jsonrpc":"2.0","id":2,"result":"value"}',
    '{"jsonrpc":"2.0","id":1,"result":"value","extra":true}',
    ' '.repeat(2162689), new Uint8Array([1])]) {
    const socket = new Socket(), rpc = new WorkspaceFilesRpc(socket, core());
    socket.handle = () => queueMicrotask(() => socket.reply(reply));
    await assert.rejects(rpc.call('morphir.workspace-files.exchange', {}));
    assert.equal(socket.closed, 1);
    await assert.rejects(rpc.call('morphir.workspace-files.exchange', {}), /unavailable/);
  }
});

test('pending file RPC requests cannot overlap and timeouts retire the owning connection', async () => {
  const socket = new Socket(), rpc = new WorkspaceFilesRpc(socket, core(), 5);
  const pending = rpc.call('morphir.workspace-files.exchange', {});
  await assert.rejects(rpc.call('morphir.workspace-files.exchange', {}), /already/);
  await assert.rejects(pending, /timed out/); assert.equal(socket.closed, 1);
  socket.reply('{"jsonrpc":"2.0","id":1,"result":"late"}');
  await assert.rejects(rpc.call('morphir.workspace-files.exchange', {}), /unavailable/);
});

test('aborted file connection setup closes its own socket and ignores a late open', async () => {
  const socket = new Socket(); socket.readyState = 0;
  const abort = new AbortController(); const opening = openWorkspaceFilesRpc(() => socket, abort.signal);
  abort.abort(); await assert.rejects(opening, /cancelled/);
  socket.readyState = 1; socket.dispatchEvent(new Event('open')); assert.equal(socket.closed, 1);
});
