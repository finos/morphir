import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ArtifactRpcChannel, openArtifactChannel } from './artifact-rpc.ts';

class Socket extends EventTarget {
  readyState = 1;
  sent: string[] = [];
  closes = 0;
  send(source: string) { this.sent.push(source); }
  close() { ++this.closes; this.readyState = 3; this.dispatchEvent(new Event('close')); }
  reply(data: unknown) { this.dispatchEvent(new MessageEvent('message', { data })); }
}

test('artifact connection setup is abortable and closes only its pending socket', async () => {
  const socket = new Socket(); socket.readyState = 0;
  const newer = new Socket(); const abort = new AbortController();
  const connecting = openArtifactChannel(() => socket, abort.signal);
  abort.abort();
  await assert.rejects(connecting, /cancelled/);
  assert.equal(socket.closes, 1); assert.equal(newer.closes, 0);
  socket.readyState = 1; socket.dispatchEvent(new Event('open'));
  assert.equal(socket.sent.length, 0);
});

test('an already cancelled attempt does not create a socket', async () => {
  const abort = new AbortController(); abort.abort(); let created = 0;
  await assert.rejects(openArtifactChannel(() => { ++created; return new Socket(); }, abort.signal), /cancelled/);
  assert.equal(created, 0);
});

test('artifact setup removes abort ownership after opening, leaving cleanup to the controller', async () => {
  const socket = new Socket(); socket.readyState = 0; const abort = new AbortController();
  const connecting = openArtifactChannel(() => socket, abort.signal);
  socket.readyState = 1; socket.dispatchEvent(new Event('open'));
  const channel = await connecting; abort.abort();
  assert.equal(channel.closed, false); assert.equal(socket.closes, 0);
  channel.close(); assert.equal(socket.closes, 1);
});

test('failed, closed and timed-out socket setup is bounded without sending requests', async () => {
  for (const failure of ['error', 'close', 'timeout']) {
    const socket = new Socket(); socket.readyState = 0;
    const connecting = openArtifactChannel(() => socket, new AbortController().signal, 5);
    if (failure !== 'timeout') socket.dispatchEvent(new Event(failure));
    await assert.rejects(connecting, /failed|closed|timed out/);
    assert.equal(socket.closes, 1); assert.equal(socket.sent.length, 0);
  }
});

test('artifact exchanges retain exact raw JSON for the profile decoder', async () => {
  const socket = new Socket();
  const channel = new ArtifactRpcChannel(socket);
  const request = '{"jsonrpc":"2.0","id":18446744073709551615,"method":"morphir.artifacts.read","params":{}}';
  const reply = '{"jsonrpc":"2.0","id":18446744073709551615,"result":{"offset":1e-999,"offset":0,"\\u0063ontent":"AA=="}}';
  const pending = channel.exchange(request);
  assert.equal(socket.sent[0], request);
  socket.reply(reply);
  assert.equal(await pending, reply);
  channel.close();
});

test('an attempt has one pending exchange and never silently queues or resends', async () => {
  const socket = new Socket(); const channel = new ArtifactRpcChannel(socket);
  const first = channel.exchange('{}');
  await assert.rejects(channel.exchange('{}'), /already pending/);
  assert.equal(socket.sent.length, 1);
  socket.reply('{"result":{}}');
  assert.equal(await first, '{"result":{}}');
  channel.close();
});

test('closing an attempt rejects only its own pending exchange', async () => {
  const older = new Socket(); const newer = new Socket();
  const oldChannel = new ArtifactRpcChannel(older); const newChannel = new ArtifactRpcChannel(newer);
  const oldReply = oldChannel.exchange('{}'); const newReply = newChannel.exchange('{}');
  oldChannel.close();
  await assert.rejects(oldReply, /closed/);
  assert.equal(older.closes, 1); assert.equal(newer.closes, 0);
  newer.reply('{}'); await newReply;
  oldChannel.close(); assert.equal(older.closes, 1);
  await assert.rejects(oldChannel.exchange('{}'), /closed/);
  newChannel.close();
});

test('transport loss and timeout close the owning socket without another request', async () => {
  for (const event of ['close', 'error', 'timeout']) {
    const socket = new Socket(); const channel = new ArtifactRpcChannel(socket, 5);
    const pending = channel.exchange('{}');
    if (event !== 'timeout') socket.dispatchEvent(new Event(event));
    await assert.rejects(pending, /closed|disconnected|failed|timed out/);
    assert.equal(socket.sent.length, 1); assert.equal(channel.closed, true);
    assert.equal(socket.closes, 1);
  }
});

test('send failures close the attempt and retain no pending exchange', async () => {
  const socket = new Socket();
  socket.send = () => { throw new Error('cannot write'); };
  const channel = new ArtifactRpcChannel(socket);
  await assert.rejects(channel.exchange('{}'), /cannot write/);
  assert.equal(channel.closed, true); assert.equal(socket.closes, 1);
});

test('request bytes are bounded before any send', async () => {
  const socket = new Socket(); const channel = new ArtifactRpcChannel(socket);
  await assert.rejects(channel.exchange('é'.repeat(524289)), /request.*limit/);
  assert.equal(socket.sent.length, 0);
  const exact = channel.exchange('é'.repeat(524288));
  assert.equal(socket.sent.length, 1);
  socket.reply('{}'); await exact;
  channel.close();
});

test('replies enforce the complete 128 KiB UTF-8 bound and refuse binary frames', async () => {
  for (const source of ['é'.repeat(65537), 'x'.repeat(131073), new ArrayBuffer(1)]) {
    const socket = new Socket(); const channel = new ArtifactRpcChannel(socket);
    const pending = channel.exchange('{}'); socket.reply(source);
    await assert.rejects(pending, /reply.*limit|text/);
    assert.equal(channel.closed, true); assert.equal(socket.closes, 1);
  }
  const socket = new Socket(); const channel = new ArtifactRpcChannel(socket);
  const pending = channel.exchange('{}'); const exact = 'é'.repeat(65536);
  socket.reply(exact); assert.equal(await pending, exact);
  channel.close();
});

test('unexpected replies close an idle attempt and cannot satisfy a later exchange', async () => {
  const socket = new Socket(); const channel = new ArtifactRpcChannel(socket);
  socket.reply('{}');
  await assert.rejects(channel.exchange('{}'), /closed/);
  assert.equal(socket.sent.length, 0); assert.equal(socket.closes, 1);
});
