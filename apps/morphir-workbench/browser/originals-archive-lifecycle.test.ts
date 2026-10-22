// Unit lifecycle input only. A real EventTarget routes synthetic pagehide to
// the actual factory-issued operation. No browser/host teardown claim.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createOriginalsArchive, prepareOriginalsArchive, type OriginalArchiveEvent} from './originals-archive.ts';

for (const phase of ['prepared', 'ready'] as const) test(`pagehide retires the same actual archive in ${phase} and removes its listener`, {timeout: 15000}, async () => {
  const addDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'addEventListener');
  const removeDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'removeEventListener');
  const target = new EventTarget();
  const retained = new Set<EventListenerOrEventListenerObject>();
  Object.defineProperty(globalThis, 'addEventListener', {configurable: true, value(type: string, listener: EventListenerOrEventListenerObject) {
    assert.equal(type, 'pagehide'); retained.add(listener); target.addEventListener(type, listener);
  }});
  Object.defineProperty(globalThis, 'removeEventListener', {configurable: true, value(type: string, listener: EventListenerOrEventListenerObject) {
    assert.equal(type, 'pagehide'); retained.delete(listener); target.removeEventListener(type, listener);
  }});
  const start = createOriginalsArchive({kind: 'connected', entries: 1, rawBytes: 1, archiveNameBytes: 3,
    describe(sink) {sink.file('one', 1);}, copyFiles(sink) {sink.file('one', new Uint8Array([7]));}});
  assert.equal(start.kind, 'prepared');
  if (start.kind !== 'prepared') throw new Error('actual factory preparation required');
  const operation = start.operation;
  try {
    let actualReady: Extract<OriginalArchiveEvent, {kind: 'ready'}> | undefined;
    if (phase === 'ready') {
      await new Promise<void>((resolve, reject) => prepareOriginalsArchive(operation, event => {
        if (event.kind === 'failed') {reject(new Error(event.failure.message)); return;}
        actualReady = event; resolve();
      }));
      await operation.whenSettled();
    }
    assert.equal(retained.size, 1, 'actual prepared or queued-ready owner must retain its own listener');
    target.dispatchEvent(new Event('pagehide'));
    if (phase === 'prepared') {
      const events: OriginalArchiveEvent[] = [];
      prepareOriginalsArchive(operation, event => events.push(event));
      await operation.whenSettled();
      assert.equal(events.some(event => event.kind === 'ready'), false);
    } else {
      assert(actualReady); assert.equal(actualReady.archive.requestDownload().kind, 'retired');
    }
    assert.equal(retained.size, 0, 'actual registration is removed, not a join/GC certificate');
  } finally {
    operation.retire(); await operation.whenSettled();
    if (addDescriptor) Object.defineProperty(globalThis, 'addEventListener', addDescriptor); else Reflect.deleteProperty(globalThis, 'addEventListener');
    if (removeDescriptor) Object.defineProperty(globalThis, 'removeEventListener', removeDescriptor); else Reflect.deleteProperty(globalThis, 'removeEventListener');
  }
});
