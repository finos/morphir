// Actual archive factory/encoder and fixed effect, with explicitly unit-only
// DOM/EventTarget stand-ins. No product currentness, host or browser proof.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createProductObservation, type ProductFact} from './product-observer.ts';
import {createOriginalsArchive, prepareOriginalsArchive, type OriginalArchiveEvent} from './originals-archive.ts';

for (const ending of ['retired', 'failed', 'raised'] as const) test(`real closed archive boundary preserves ${ending} with a failing observer`, async () => {
  const descriptors = new Map(['document', 'addEventListener', 'removeEventListener'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  const failure = new Error('actual listener removal failure'), target = new EventTarget();
  Object.defineProperty(globalThis, 'document', {configurable: true, value: {createElement() {throw new Error('unit DOM refusal');}}});
  Object.defineProperty(globalThis, 'addEventListener', {configurable: true, value: target.addEventListener.bind(target)});
  Object.defineProperty(globalThis, 'removeEventListener', {configurable: true, value: (...args: Parameters<EventTarget['removeEventListener']>) => {
    target.removeEventListener(...args); if (ending === 'raised') throw failure;
  }});
  const start = createOriginalsArchive({kind: 'connected', entries: 1, rawBytes: 1, archiveNameBytes: 3,
    describe(sink) {sink.file('one', 1);}, copyFiles(sink) {sink.file('one', new Uint8Array([7]));}});
  assert(start.kind === 'prepared'); const operation = start.operation;
  try {
    const received: OriginalArchiveEvent[] = []; prepareOriginalsArchive(operation, event => received.push(event));
    await operation.whenSettled(); const ready = received.find(event => event.kind === 'ready'); assert(ready?.kind === 'ready');
    if (ending === 'retired') ready.archive.dispose();
    const document = {}, scope = createProductObservation(document), facts: ProductFact[] = [], opening = {};
    scope.attach(document, {owners: 8, events: 16}, fact => {
      facts.push(fact); if (fact.kind === 'download-result') throw new Error('observer failure');
    }); scope.start(document);
    scope.openingStored(opening, 'workspace', 1, '1'); scope.inventoryAdopted(opening, 'workspace', 1, '1', '1');
    scope.archiveStored(operation, 'workspace', 1, '1'); scope.ready(operation, ready.archive);
    if (ending === 'raised') assert.throws(() => scope.requestDownload(operation, ready.archive), error => error === failure);
    else assert.equal(scope.requestDownload(operation, ready.archive).kind, ending);
    const result = facts.find(fact => fact.kind === 'download-result'); assert(result?.kind === 'download-result');
    assert.deepEqual(result.outcome, ending === 'raised' ? {kind: 'raised'} : {kind: 'returned', result: ending});
    assert.deepEqual(scope.state(), {kind: 'incomplete', cause: 'sink-raised'});
  } finally {
    operation.retire(); await operation.whenSettled();
    for (const [key, descriptor] of descriptors) if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);
  }
});
