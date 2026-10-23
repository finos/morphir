// Real loopback WebSocket component controls with the genuine observer factory.
// Synthetic document/explicit prepaid inputs only, no native-host/Page/source,
// Download, framework allocator, MCK or profile qualification claim.
// Use the existing Node lane: Bun's WebSocket.close() reports the forced reset
// control as clean1000, so it cannot establish this required abnormal-close case.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import type {AddressInfo} from 'node:net';
import {WebSocketServer, WebSocket as Peer} from 'ws';
import {prepareDocumentChannel} from './product-document-channel.ts';
import {createProductObservation, type ObservationLimits, type ProductFact} from './product-observer.ts';

function bootstrap(records = 8, journalBytes = 8192, frameBytes = 1024) {
  const backing = journalBytes + 8 * records;
  return {observation: {owners: 8, events: 16}, records, journalBytes, frameBytes,
    journalCharge: {retainedBytes: backing, slots: 104 * records + 8, byteVisits: backing + records * (4218 + 66 * frameBytes) + 8},
    transportCharge: {retainedBytes: frameBytes + 16, slots: 8 + 2 * records, byteVisits: frameBytes + 16 + records * (2 * frameBytes + 64) + 96},
    credential: 'A'.repeat(43)};
}
function control(kind: 3 | 4, sequence: number) {
  const bytes = new Uint8Array(16), header = new DataView(bytes.buffer);
  header.setUint8(0, 1); header.setUint8(1, kind); header.setBigUint64(4, BigInt(sequence)); return bytes;
}
function frame(bytes: Uint8Array) {
  const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  assert.equal(header.getUint8(0), 1); assert.equal(header.getUint16(2), 0); assert.equal(header.getUint32(12), bytes.length - 16);
  return {kind: header.getUint8(1), sequence: Number(header.getBigUint64(4)),
    body: JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(16)))};
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve};
}
function bounded<T>(pending: Promise<T>, end: AbortSignal): Promise<T> {
  return new Promise((resolve, reject) => {
    const abort = () => {end.removeEventListener('abort', abort); reject(end.reason);};
    if (end.aborted) {reject(end.reason); return;}
    end.addEventListener('abort', abort, {once: true});
    pending.then(value => {end.removeEventListener('abort', abort); resolve(value);}, error => {
      end.removeEventListener('abort', abort); reject(error);
    });
  });
}
async function endpoint() {
  const server = new WebSocketServer({host: '127.0.0.1', port: 0,
    handleProtocols: protocols => protocols.has('morphir-document-v1') && protocols.size === 2 ? 'morphir-document-v1' : false});
  await once(server, 'listening');
  const connected = deferred<Peer>(), frames: Uint8Array[] = [], notices: (() => void)[] = [];
  let closed = false;
  server.on('connection', peer => {
    peer.on('message', (data, binary) => {
      // Fixture memory only, never the native collector's retention authority.
      if (!binary || frames.length >= 32) {peer.terminate(); return;}
      frames.push(new Uint8Array(data as Buffer)); for (const notify of notices.splice(0)) notify();
    });
    peer.on('close', () => {closed = true; for (const notify of notices.splice(0)) notify();});
    connected.resolve(peer);
  });
  return {url: `ws://127.0.0.1:${(server.address() as AddressInfo).port}/_mck/document`, connected: connected.promise, frames,
    async next(index: number) {
      while (!frames[index]) {if (closed) throw new Error('Peer closed before expected frame'); await new Promise<void>(resolve => notices.push(resolve));}
      return frame(frames[index]!);
    },
    async close() {
      closed = true; for (const notify of notices.splice(0)) notify();
      for (const client of server.clients) client.terminate();
      // Termination happens even after the original operation end. Failure to
      // dispose the fixture is separately reported, never hidden by its timeout.
      await bounded(new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())), AbortSignal.timeout(1000));
    }};
}
function starter(stopped: ReturnType<typeof deferred<void>>) {
  const document = {}, observer = createProductObservation(document);
  return {observer, start: async (limits: ObservationLimits, receive: (fact: ProductFact) => void) => {
    assert.equal(observer.attach(document, limits, receive), 'attached'); observer.start(document);
    observer.openingStored({}, 'workspace', 1, 'attempt');
    return {state: observer.state, close() {observer.close(); stopped.resolve();}};
  }};
}

test('a real held ACK admits adjacent callbacks, then STOP closes the same observer before END and actual channel close', {timeout: 10000}, async () => {
  const end = AbortSignal.timeout(8000), wait = <T>(value: Promise<T>) => bounded(value, end);
  const stopped = deferred<void>(), actual = starter(stopped);
  const prepared = prepareDocumentChannel(bootstrap()); assert.equal(prepared.kind, 'prepared');
  if (prepared.kind !== 'prepared') return;
  const peer = await endpoint();
  const channel = prepared.channel, socket = new WebSocket(peer.url, [...channel.protocols]);
  let result: unknown;
  try {
    await wait(channel.attach(socket, actual.start)); const server = await wait(peer.connected);
    const first = await wait(peer.next(0));
    actual.observer.closed('workspace', 1, 'workspace-closed');
    server.send(control(4, 0)); await wait(stopped.promise);
    const stateAtStop = actual.observer.state();
    server.send(control(3, first.sequence)); const second = await wait(peer.next(1));
    server.send(control(3, second.sequence)); const final = await wait(peer.next(2));
    const closed = once(server, 'close'); server.send(control(3, final.sequence));
    const terminal = await wait(channel.whenClosed()); await wait(closed);
    result = {first, second, end: final, terminal, stateAtStop, count: peer.frames.length};
  } finally {actual.observer.close(); socket.close(); await peer.close();}
  assert.deepEqual(result, {
    first: {kind: 1, sequence: 1, body: {kind: 'opening-stored', actual: {workspace: 'workspace', opening: 1, attempt: 'attempt', openingOrdinal: 1}, sequence: 1}},
    second: {kind: 1, sequence: 2, body: {kind: 'workspace-closed', actual: {workspace: 'workspace', opening: 1}, sequence: 2}},
    end: {kind: 2, sequence: 3, body: {lastSequence: 2, observer: {kind: 'closed'}}},
    terminal: {kind: 'closed'}, stateAtStop: {kind: 'closed'}, count: 3,
  });
});

for (const failure of ['lost-ack', 'wrong-ack', 'wrong-stop', 'duplicate-stop', 'text-control', 'control-length', 'reserved', 'wide-sequence', 'unknown-kind'] as const) {
  test(`actual ${failure} poisons the producer without changing later observer calls`, {timeout: 10000}, async () => {
    const end = AbortSignal.timeout(8000), wait = <T>(value: Promise<T>) => bounded(value, end);
    const stopped = deferred<void>(), actual = starter(stopped);
    const prepared = prepareDocumentChannel(bootstrap()); assert.equal(prepared.kind, 'prepared');
    if (prepared.kind !== 'prepared') return;
    const peer = await endpoint();
    const channel = prepared.channel, socket = new WebSocket(peer.url, [...channel.protocols]);
    let result: unknown;
    try {
      await wait(channel.attach(socket, actual.start)); const server = await wait(peer.connected);
      await wait(peer.next(0));
      switch (failure) {
        case 'lost-ack': server.close(); break;
        case 'wrong-ack': server.send(control(3, 2)); break;
        case 'wrong-stop': server.send(control(4, 1)); break;
        case 'duplicate-stop': server.send(control(4, 0)); await wait(stopped.promise); server.send(control(4, 0)); break;
        case 'text-control': server.send('ACK'); break;
        case 'control-length': server.send(new Uint8Array(17)); break;
        case 'reserved': {const bytes = control(3, 1); bytes[2] = 1; server.send(bytes); break;}
        case 'wide-sequence': {const bytes = control(3, 1); new DataView(bytes.buffer).setBigUint64(4, 9007199254740992n); server.send(bytes); break;}
        case 'unknown-kind': {const bytes = control(3, 1); bytes[1] = 5; server.send(bytes); break;}
      }
      const terminal = await wait(channel.whenClosed());
      actual.observer.closed('workspace', 1, 'workspace-closed');
      result = {terminal, count: peer.frames.length, unchanged: channel.state()};
    } finally {actual.observer.close(); socket.close(); await peer.close();}
    const first = failure === 'lost-ack' ? 'lost-channel' : failure === 'wrong-ack' ? 'ack' : failure === 'wrong-stop' || failure === 'duplicate-stop' ? 'stop' : 'control-shape';
    assert.deepEqual(result, {terminal: {kind: 'incomplete', first}, count: 1, unchanged: {kind: 'incomplete', first}});
  });
}

for (const completion of ['healthy-empty', 'lost-end-ack', 'zero-records', 'nonclosed-observer'] as const) {
  test(`actual STOP with ${completion} preserves terminal meaning`, {timeout: 10000}, async () => {
    const end = AbortSignal.timeout(8000), wait = <T>(value: Promise<T>) => bounded(value, end);
    const stopped = deferred<void>(), actual = starter(stopped);
    const raw = completion === 'zero-records' ? bootstrap(0, 0, 16) : bootstrap();
    if (completion === 'nonclosed-observer') raw.observation.events = 0;
    const prepared = prepareDocumentChannel(raw); assert.equal(prepared.kind, 'prepared');
    if (prepared.kind !== 'prepared') return;
    const peer = await endpoint();
    const channel = prepared.channel, socket = new WebSocket(peer.url, [...channel.protocols]);
    let result: unknown;
    try {
      if (completion === 'healthy-empty' || completion === 'zero-records') {
        await wait(channel.attach(socket, async (limits, receive) => {
          const document = {}, observer = createProductObservation(document);
          observer.attach(document, limits, receive); observer.start(document);
          return {state: observer.state, close: observer.close};
        }));
      } else await wait(channel.attach(socket, actual.start));
      const server = await wait(peer.connected);
      if (completion === 'lost-end-ack') {
        const fact = await wait(peer.next(0)); server.send(control(3, fact.sequence));
        // ACK then STOP share the actual ordered channel and use the advanced
        // FACT cursor. END retention without its ACK cannot be healthy.
        server.send(control(4, 1)); await wait(peer.next(1)); server.close();
      } else {
        server.send(control(4, 0));
        if (completion === 'healthy-empty') {const terminal = await wait(peer.next(0)); server.send(control(3, terminal.sequence));}
      }
      result = {terminal: await wait(channel.whenClosed()), frames: peer.frames.map(frame)};
    } finally {actual.observer.close(); socket.close(); await peer.close();}
    const terminal = completion === 'healthy-empty' ? {kind: 'closed'}
      : {kind: 'incomplete', first: completion === 'lost-end-ack' ? 'lost-channel' : 'journal'};
    assert.equal((result as {terminal: {kind: string}}).terminal.kind, terminal.kind);
    assert.deepEqual((result as {terminal: unknown}).terminal, terminal);
    if (completion === 'healthy-empty') assert.deepEqual((result as {frames: unknown}).frames,
      [{kind: 2, sequence: 1, body: {lastSequence: 0, observer: {kind: 'closed'}}}]);
  });
}

test('actual startup raises the identical application error and disposes its channel', {timeout: 10000}, async () => {
  const end = AbortSignal.timeout(8000), wait = <T>(value: Promise<T>) => bounded(value, end);
  const prepared = prepareDocumentChannel(bootstrap());
  assert.equal(prepared.kind, 'prepared'); if (prepared.kind !== 'prepared') return;
  const peer = await endpoint();
  const channel = prepared.channel, socket = new WebSocket(peer.url, [...channel.protocols]), original = new Error('Application startup');
  let raised: unknown, terminal: unknown;
  try {
    try {await wait(channel.attach(socket, async () => {throw original;}));} catch (error) {raised = error;}
    terminal = await wait(channel.whenClosed());
  } finally {socket.close(); await peer.close();}
  assert.equal(raised, original); assert.deepEqual(terminal, {kind: 'incomplete', first: 'startup'});
});

test('actual abnormal close after END ACK remains incomplete', {timeout: 10000}, async () => {
  const end = AbortSignal.timeout(8000), wait = <T>(value: Promise<T>) => bounded(value, end);
  const prepared = prepareDocumentChannel(bootstrap());
  assert.equal(prepared.kind, 'prepared'); if (prepared.kind !== 'prepared') return;
  const peer = await endpoint();
  const channel = prepared.channel, socket = new WebSocket(peer.url, [...channel.protocols]);
  let atReset: unknown, terminal: unknown, closure: unknown;
  socket.addEventListener('close', event => {closure = {clean: event.wasClean, code: event.code};}, {once: true});
  try {
    await wait(channel.attach(socket, async (limits, receive) => {
      const document = {}, observer = createProductObservation(document);
      observer.attach(document, limits, receive); observer.start(document);
      return {state: observer.state, close: observer.close};
    }));
    const server = await wait(peer.connected); server.send(control(4, 0));
    const final = await wait(peer.next(0));
    // Runs after the producer's actual END ACK handler, before the peer can
    // answer its close handshake. No fabricated CloseEvent or producer state.
    socket.addEventListener('message', () => {atReset = channel.state(); server.terminate();}, {once: true});
    server.send(control(3, final.sequence)); terminal = await wait(channel.whenClosed());
  } finally {socket.close(); await peer.close();}
  assert.deepEqual(atReset, {kind: 'end-acknowledged'}); assert.deepEqual(closure, {clean: false, code: 1006});
  assert.deepEqual(terminal, {kind: 'incomplete', first: 'lost-channel'});
});

test('bootstrap capacities and mirrors are closed and exact before any socket or startup effect', () => {
  for (const change of [
    (input: ReturnType<typeof bootstrap>) => {input.journalCharge.slots--;},
    (input: ReturnType<typeof bootstrap>) => {input.transportCharge.retainedBytes--;},
    (input: ReturnType<typeof bootstrap>) => {input.records = Number.MAX_SAFE_INTEGER;},
    (input: ReturnType<typeof bootstrap>) => {input.frameBytes = 15;},
    (input: ReturnType<typeof bootstrap>) => {input.credential = 'bad';},
  ]) {const input = bootstrap(); change(input); assert.equal(prepareDocumentChannel(input).kind, 'refused');}
  assert.equal(prepareDocumentChannel({...bootstrap(), unknown: 1}).kind, 'refused');
  assert.equal(prepareDocumentChannel(bootstrap(0, 0, 16)).kind, 'prepared', 'zero records have no hidden END descriptor');
});

for (const ending of ['settled', 'stop', 'revoked', 'lost-channel', 'actual-error'] as const)
test(`fixed controls retain only the actual starter owner and its active channel: ${ending}`, {timeout: 10000}, async () => {
  const end = AbortSignal.timeout(8000), wait = <T>(value: Promise<T>) => bounded(value, end);
  const prepared = prepareDocumentChannel(bootstrap());
  assert.equal(prepared.kind, 'prepared'); if (prepared.kind !== 'prepared') return;
  const peer = await endpoint(), channel = prepared.channel, socket = new WebSocket(peer.url, [...channel.protocols]);
  const document = {}, observer = createProductObservation(document), pending = deferred<Readonly<{kind: 'stored'}>>();
  const actualError = new Error('actual boundary failure');
  let executed = 0, awaited = 0;
  const actual = Object.freeze({state: observer.state, close: observer.close,
    async awaitConnectedBoundary(boundary: 'inspection-pending' | 'opening-settled') {
      awaited++;
      if (boundary === 'inspection-pending') return {kind: 'inspection-pending'} as const;
      if (ending === 'actual-error') throw actualError;
      return pending.promise;
    }, executePendingCore() {executed++; return 'enqueued' as const;}});
  try {
    assert.throws(() => channel.connectedControls(actual), /actual active starter/);
    await wait(channel.attach(socket, async (limits, receive) => {
      observer.attach(document, limits, receive); observer.start(document); return actual;
    }));
    const server = await wait(peer.connected);
    assert.throws(() => channel.connectedControls({...actual}), /actual active starter/);
    const controls = channel.connectedControls(actual);
    assert.equal(channel.connectedControls(actual), controls, 'one retained control owner');
    assert.deepEqual(Object.keys(controls).sort(), ['awaitInspectionPending', 'awaitOpeningSettled', 'executePendingCore']);
    assert.deepEqual(await wait(controls.awaitInspectionPending()), {kind: 'inspection-pending'});
    assert.equal(controls.executePendingCore(), 'enqueued');
    const settlement = controls.awaitOpeningSettled();
    if (ending === 'actual-error') await assert.rejects(settlement, error => error === actualError);
    else {
      await assert.rejects(controls.awaitInspectionPending(), /already outstanding/);
      assert.throws(() => controls.executePendingCore(), /already outstanding/);
      if (ending === 'settled') {
        pending.resolve({kind: 'stored'}); assert.deepEqual(await wait(settlement), {kind: 'stored'});
      } else {
        const refused = assert.rejects(settlement, /channel inactive/);
        if (ending === 'stop') server.send(control(4, 0));
        else if (ending === 'revoked') channel.revoke();
        else server.terminate();
        await wait(refused);
        assert.throws(() => controls.executePendingCore(), /channel inactive/);
        await assert.rejects(controls.awaitInspectionPending(), /channel inactive/);
        pending.resolve({kind: 'stored'});
        await Promise.resolve();
        assert.throws(() => controls.executePendingCore(), /channel inactive/);
      }
    }
    assert.equal(executed, 1); assert.equal(awaited, 2, 'no second waiter or late application call');
  } finally {observer.close(); socket.close(); await peer.close();}
});

test('captured controls share the page-wide pending slot and keep old cleanup after channel loss', {timeout: 10000}, async () => {
  const end = AbortSignal.timeout(8000), wait = <T>(value: Promise<T>) => bounded(value, end);
  const prepared = prepareDocumentChannel(bootstrap());
  assert.equal(prepared.kind, 'prepared'); if (prepared.kind !== 'prepared') return;
  const peer = await endpoint(), channel = prepared.channel, socket = new WebSocket(peer.url, [...channel.protocols]);
  const document = {}, observer = createProductObservation(document);
  const registered = deferred<typeof pin>(), boundary = deferred<Readonly<{kind: 'inspection-pending'}>>();
  let disposed = 0, cancelled = 0, capturedCalls = 0, ordinaryCalls = 0;
  const pin = {awaitBoundary: async () => {capturedCalls++; return boundary.promise;},
    chooseSource: async () => ({kind: 'source-selected'} as const),
    chooseProject: async () => ({kind: 'project-selected'} as const),
    executePendingCore: () => {capturedCalls++; return 'enqueued' as const;},
    dispose: () => {disposed++;}, whenSettled: async () => {}};
  const actual = {state: observer.state, close: observer.close,
    awaitConnectedBoundary: async () => {ordinaryCalls++; return {kind: 'retired'} as const;},
    executePendingCore: () => {ordinaryCalls++; return 'ignored' as const;},
    prepareOpeningCapture: () => ({whenRegistered: () => registered.promise, cancel: () => {cancelled++;}})};
  try {
    await wait(channel.attach(socket, async (limits, receive) => {
      observer.attach(document, limits, receive); observer.start(document); return actual;
    }));
    const page = channel.connectedControls(actual), captures = channel.openingControls(actual);
    assert.throws(() => channel.openingControls({...actual}), /actual active starter/);
    const capture = captures.prepareOpeningCapture();
    const registering = capture.whenRegistered();
    assert.throws(() => page.executePendingCore(), /already outstanding/);
    registered.resolve(pin); const captured = await wait(registering);
    assert.equal(await capture.whenRegistered(), captured, 'one wrapper for the same actual capture');
    assert.deepEqual(await captured.chooseSource('provider', 'locator'), {kind: 'source-selected'});
    const pending = captured.awaitInspectionPending();
    await assert.rejects(page.awaitOpeningSettled(), /already outstanding/);
    await assert.rejects(captured.chooseProject('project'), /already outstanding/);
    assert.throws(() => captured.executePendingCore(), /already outstanding/);
    boundary.resolve({kind: 'inspection-pending'});
    assert.deepEqual(await wait(pending), {kind: 'inspection-pending'});
    assert.equal(captured.executePendingCore(), 'enqueued');
    const late = captured.awaitOpeningSettled();
    const invalidated = assert.rejects(late, /channel inactive/);
    channel.revoke();
    await wait(invalidated);
    assert.throws(() => captured.executePendingCore(), /channel inactive/);
    await assert.rejects(captured.awaitOpeningSettled(), /channel inactive/);
    await assert.rejects(captured.chooseSource('provider', 'locator'), /channel inactive/);
    captured.dispose(); await wait(captured.whenSettled()); capture.cancel();
    assert.equal(disposed, 1); assert.equal(cancelled, 1);
    assert.equal(capturedCalls, 3); assert.equal(ordinaryCalls, 0);
  } finally {observer.close(); socket.close(); await peer.close();}
});
