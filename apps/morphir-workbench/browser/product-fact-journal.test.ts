// Component controls. Genuine observation/archive factories, synthetic document
// and precharge owner only. No browser, host, transport or qualification claim.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createProductObservation, type ProductFact} from './product-observer.ts';
import {prepareProductJournal, type JournalCharge} from './product-fact-journal.ts';
import {createOriginalsArchive, prepareOriginalsArchive, type OriginalArchiveEvent, type OriginalArchiveOperation} from './originals-archive.ts';

// Hostile getters below are explicit component inputs, never product facts or
// source/session grants. The terminal value comes from the real observer.
for (const site of ['fact-kind', 'end-kind'] as const) {
  test(`a hostile ${site} getter cannot append a suffix after the same real closed END`, () => {
    const actual = journal(), scope = emit(actual); scope.close();
    const first = copied(actual);
    assert.equal(body(first.bytes).value.kind, 'opening-stored');
    assert.equal(actual.advance(first.pending.record), true);
    if (site === 'fact-kind') {
      actual.receive({get kind(): 'model-closed' {actual.end(scope.state()); return 'model-closed';},
        actual: {workspace: 'workspace', opening: 1}, sequence: 2});
    } else {
      actual.end({get kind() {actual.end(scope.state()); return scope.state().kind;}} as ReturnType<typeof scope.state>);
    }
    const observed = actual.state(), suffix: ReturnType<typeof body>[] = [];
    // On the old implementation, preserve the actual emitted END/illegal suffix
    // before the intended assertion. Poisoned journals expose no further bytes.
    if (observed.kind !== 'incomplete') {
      for (;;) {
        const pending = actual.pending(); if (pending.kind !== 'record') break;
        const bytes = new Uint8Array(pending.record.byteLength);
        assert.equal(pending.record.copyInto(bytes).kind, 'copied'); suffix.push(body(bytes));
        assert.equal(actual.advance(pending.record), true);
      }
    }
    console.info(JSON.stringify({componentGetter: site, observed, suffix}, (_, value) => typeof value === 'bigint' ? value.toString() : value));
    assert.deepEqual(observed, {kind: 'incomplete', first: 'after-end', records: 2, facts: 1});
    actual.lose(); actual.end(scope.state());
    actual.receive({kind: 'model-closed', actual: {workspace: 'workspace', opening: 1}, sequence: 2});
    assert.deepEqual(actual.state(), observed);
    assert.deepEqual(actual.pending(), {kind: 'incomplete', first: 'after-end'});
  });
}

function body(bytes: Uint8Array) {
  const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  assert.equal(header.getUint8(0), 1); assert.equal(header.getUint16(2), 0);
  assert.equal(header.getUint32(12), bytes.length - 16);
  return {kind: header.getUint8(1), sequence: header.getBigUint64(4),
    value: JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(16)))};
}

test('real observer callback snapshots one ordered fact and actual closed END', () => {
  const prepared = prepareProductJournal({records: 4, journalBytes: 4096, frameBytes: 1024}, () => true);
  assert.equal(prepared.kind, 'prepared'); if (prepared.kind !== 'prepared') return;
  const journal = prepared.journal, document = {}, observation = createProductObservation(document);
  observation.attach(document, {owners: 4, events: 8}, journal.receive); observation.start(document);
  observation.openingStored({}, 'workspace', 1, 'attempt'); observation.close(); journal.end(observation.state());
  const first = journal.pending(); assert.equal(first.kind, 'record'); if (first.kind !== 'record') return;
  const bytes = new Uint8Array(first.record.byteLength);
  assert.equal(first.record.copyInto(bytes).kind, 'copied');
  assert.deepEqual(body(bytes), {kind: 1, sequence: 1n, value: {kind: 'opening-stored',
    actual: {workspace: 'workspace', opening: 1, attempt: 'attempt', openingOrdinal: 1}, sequence: 1}});
  assert.equal(journal.advance(first.record), true);
  const ending = journal.pending(); assert.equal(ending.kind, 'record'); if (ending.kind !== 'record') return;
  const terminal = new Uint8Array(ending.record.byteLength); ending.record.copyInto(terminal);
  assert.deepEqual(body(terminal), {kind: 2, sequence: 2n, value: {lastSequence: 1, observer: {kind: 'closed'}}});
  assert.equal(journal.advance(ending.record), true);
  assert.deepEqual(journal.pending(), {kind: 'empty'});
  assert.deepEqual(journal.state(), {kind: 'ended', records: 2, facts: 1});
});

function journal(records = 8, journalBytes = 8192, frameBytes = 2048, reserve: (charge: JournalCharge) => boolean = () => true) {
  const result = prepareProductJournal({records, journalBytes, frameBytes}, reserve);
  assert.equal(result.kind, 'prepared'); if (result.kind !== 'prepared') throw new Error('unit journal preparation refused');
  return result.journal;
}
function emit(actual: ReturnType<typeof journal>, workspace = 'workspace') {
  const document = {}, scope = createProductObservation(document);
  scope.attach(document, {owners: 4, events: 8}, actual.receive); scope.start(document); scope.openingStored({}, workspace, 1, 'attempt');
  return scope;
}
function copied(actual: ReturnType<typeof journal>) {
  const pending = actual.pending(); assert(pending.kind === 'record');
  const bytes = new Uint8Array(pending.record.byteLength); assert.equal(pending.record.copyInto(bytes).kind, 'copied');
  return {pending, bytes};
}

test('real observer strings preserve UTF8, JSON escapes and every lone UTF16 unit', () => {
  const actual = journal(), value = '"\\\u0000\u001f\ufeffé中🦀\ud800x\udfff', scope = emit(actual, value);
  scope.close(); actual.end(scope.state());
  const {bytes} = copied(actual), decoded = body(bytes);
  assert.equal(decoded.value.actual.workspace, value);
  assert.match(new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(16)), /\\ud800x\\udfff/);
});

test('component input getters snapshot once and neither source nor copy destinations alias retained bytes', () => {
  const actual = journal(); let workspaceReads = 0, sequenceReads = 0, kindReads = 0;
  // Explicit unit input seam, not a fabricated positive product/runtime fact.
  const owner = {get workspace() {workspaceReads++; return workspaceReads === 1 ? 'first' : 'later';}, opening: 1, attempt: 'attempt', openingOrdinal: 1};
  const input = {get kind() {kindReads++; return 'opening-stored';}, actual: owner,
    get sequence() {sequenceReads++; return sequenceReads === 1 ? 1 : 8;}} as ProductFact;
  actual.receive(input); owner.attempt = 'changed after receive';
  const first = copied(actual); first.bytes.fill(255); const second = copied(actual);
  assert.equal(second.pending.record, first.pending.record);
  assert.deepEqual(body(second.bytes).value, {kind: 'opening-stored', actual: {workspace: 'first', opening: 1, attempt: 'attempt', openingOrdinal: 1}, sequence: 1});
  assert.deepEqual([workspaceReads, sequenceReads, kindReads], [1, 1, 1]);
});

test('exact frame and cumulative byte boundaries refuse one-over without publishing a partial record or refund', () => {
  const calibration = journal(); emit(calibration); const length = copied(calibration).bytes.length;
  for (const [bytes, frame] of [[length, length], [length - 1, length], [length, length - 1]]) {
    const actual = journal(2, bytes, frame); emit(actual);
    if (bytes === length && frame === length) {
      const first = copied(actual); assert.equal(actual.advance(first.pending.record), true);
      actual.receive({kind: 'model-closed', actual: {workspace: 'workspace', opening: 1}, sequence: 2});
      assert.deepEqual(actual.state(), {kind: 'incomplete', first: 'capacity', records: 1, facts: 1});
    } else assert.deepEqual(actual.state(), {kind: 'incomplete', first: 'capacity', records: 0, facts: 0});
  }
});

test('descriptor metadata is prepaid exactly, one-under refuses before allocation and no terminal slot is hidden', () => {
  for (const available of [16, 15]) {
    const charges: JournalCharge[] = [];
    const result = prepareProductJournal({records: 2, journalBytes: 0, frameBytes: 0}, charge => {
      charges.push(charge); return charge.backingBytes <= available;
    });
    assert.deepEqual(charges, [{backingBytes: 16, slots: 4, byteVisits: 16}]);
    assert.equal(result.kind, available === 16 ? 'prepared' : 'refused');
    if (result.kind === 'refused') assert.equal(result.first, 'funding');
  }
  const zero = journal(0, 0, 0); let reads = 0;
  zero.receive({get kind() {reads++; throw new Error('must not read');}} as unknown as ProductFact);
  assert.equal(reads, 0); assert.deepEqual(zero.state(), {kind: 'incomplete', first: 'capacity', records: 0, facts: 0});
  const document = {}, scope = createProductObservation(document); scope.close();
  const endOnly = journal(1, 128, 128); endOnly.end(scope.state()); assert.equal(endOnly.state().kind, 'ended');
  const noHiddenSlot = journal(0, 128, 128); noHiddenSlot.end(scope.state()); assert.equal(noHiddenSlot.state().kind, 'incomplete');
});

test('factory limit snapshots preserve first readings and typed overflow or reserve failures', () => {
  let recordReads = 0, byteReads = 0, frameReads = 0;
  const result = prepareProductJournal({get records() {return ++recordReads === 1 ? 0 : Infinity;},
    get journalBytes() {return ++byteReads === 1 ? 0 : Infinity;}, get frameBytes() {return ++frameReads === 1 ? 0 : Infinity;}}, () => true);
  assert.equal(result.kind, 'prepared'); assert.deepEqual([recordReads, byteReads, frameReads], [1, 1, 1]);
  let reserves = 0;
  assert.deepEqual(prepareProductJournal({records: Number.MAX_SAFE_INTEGER, journalBytes: 0, frameBytes: 0}, () => {reserves++; return true;}),
    {kind: 'refused', first: 'size-overflow'});
  assert.equal(reserves, 0);
  assert.deepEqual(prepareProductJournal({records: 0, journalBytes: 0, frameBytes: 0}, () => {throw new Error('owner refused');}), {kind: 'refused', first: 'funding'});
  assert.deepEqual(prepareProductJournal({records: NaN, journalBytes: 0, frameBytes: 0}, () => {reserves++; return true;}), {kind: 'refused', first: 'limits'});
  assert.equal(reserves, 0);
});

test('precharge refusal precedes input getters and actual copy, then remains sticky', () => {
  let allowed = true, inputReads = 0;
  const actual = journal(8, 8192, 2048, () => allowed); allowed = false;
  actual.receive({get kind() {inputReads++; throw new Error('must not read');}} as unknown as ProductFact);
  assert.equal(inputReads, 0); assert.deepEqual(actual.state(), {kind: 'incomplete', first: 'funding', records: 0, facts: 0});
  allowed = true; emit(actual); assert.equal(actual.state().facts, 0);
  const second = journal(8, 8192, 2048, () => allowed); emit(second); const pending = second.pending(); assert(pending.kind === 'record');
  const destination = new Uint8Array(pending.record.byteLength).fill(77); allowed = false;
  assert.deepEqual(pending.record.copyInto(destination), {kind: 'refused', first: 'funding'});
  assert(destination.every(byte => byte === 77));
});

test('malformed unit numeric, sequence and encoding input never escapes or revives', () => {
  for (const sequence of [0, 2, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, -1]) {
    const actual = journal();
    assert.doesNotThrow(() => actual.receive({kind: 'model-closed', actual: {workspace: 'w', opening: 1}, sequence}));
    assert.deepEqual(actual.state(), {kind: 'incomplete', first: sequence === 0 || sequence === 2 ? 'sequence' : 'shape', records: 0, facts: 0});
    actual.lose(); assert.equal(actual.state().first, sequence === 0 || sequence === 2 ? 'sequence' : 'shape');
  }
  const actual = journal();
  assert.doesNotThrow(() => actual.receive({kind: 'model-closed', sequence: 1, get actual() {throw new Error('unit encoding failure');}} as unknown as ProductFact));
  assert.deepEqual(actual.state(), {kind: 'incomplete', first: 'encoding', records: 0, facts: 0});
});

test('actual nonclosed observer END, missing END, loss and after-END facts are incomplete without fabricated records', () => {
  const document = {}, scope = createProductObservation(document); scope.start(document);
  const unobserved = journal(); assert.doesNotThrow(() => unobserved.end(scope.state()));
  assert.deepEqual(unobserved.state(), {kind: 'incomplete', first: 'end-state', records: 0, facts: 0});
  const missing = journal(); emit(missing); missing.close();
  assert.deepEqual(missing.state(), {kind: 'incomplete', first: 'missing-end', records: 1, facts: 1});
  const lost = journal(); emit(lost); lost.lose(); lost.close();
  assert.deepEqual(lost.state(), {kind: 'incomplete', first: 'loss', records: 1, facts: 1});
  const ended = journal(), owner = emit(ended); owner.close(); ended.end(owner.state());
  ended.receive({kind: 'model-closed', actual: {workspace: 'workspace', opening: 1}, sequence: 2});
  assert.deepEqual(ended.state(), {kind: 'incomplete', first: 'after-end', records: 2, facts: 1});
});

test('only the same current record may copy or advance, with insufficient destinations unchanged', () => {
  const first = journal(), second = journal(); emit(first); emit(second);
  const a = first.pending(), b = second.pending(); assert(a.kind === 'record' && b.kind === 'record');
  assert.equal(first.advance(b.record), false); assert.equal(first.state().first, 'record');
  assert.equal(second.advance(b.record), true);
  assert.deepEqual(b.record.copyInto(new Uint8Array(b.record.byteLength)), {kind: 'refused', first: 'record'});
  const short = journal(); emit(short); const next = short.pending(); assert(next.kind === 'record');
  const destination = new Uint8Array(next.record.byteLength - 1).fill(99);
  assert.equal(next.record.copyInto(destination).kind, 'refused'); assert(destination.every(byte => byte === 99));
});

test('the journal never exposes its owned backing as an ordinary property', () => {
  const actual = journal(); emit(actual);
  for (const key of Reflect.ownKeys(actual)) {
    const value: unknown = Reflect.get(actual, key);
    assert.equal(ArrayBuffer.isView(value) || value instanceof ArrayBuffer, false, `backing escaped through ${String(key)}`);
  }
});

test('real callback loss during precharge prevents later publication despite a returned credit', () => {
  let interrupt = false;
  const actual = journal(8, 8192, 2048, () => {if (interrupt) actual.lose(); return true;});
  interrupt = true; const document = {}, scope = createProductObservation(document);
  scope.attach(document, {owners: 4, events: 8}, actual.receive); scope.start(document);
  assert.doesNotThrow(() => scope.openingStored({}, 'workspace', 1, 'attempt'));
  assert.deepEqual(actual.state(), {kind: 'incomplete', first: 'loss', records: 0, facts: 0});
});

test('a current record retired during copy precharge cannot write the destination', () => {
  let interrupt: (() => void) | undefined;
  const actual = journal(8, 8192, 2048, () => {interrupt?.(); return true;}); emit(actual);
  const pending = actual.pending(); assert(pending.kind === 'record');
  interrupt = () => {interrupt = undefined; actual.advance(pending.record);};
  const bytes = new Uint8Array(pending.record.byteLength).fill(17);
  assert.deepEqual(pending.record.copyInto(bytes), {kind: 'refused', first: 'record'});
  assert(bytes.every(byte => byte === 17));
});

test('pure codec DATA covers every closed union branch without source/session grants or workflow claims', () => {
  // These are serialization inputs only, never actual product observations,
  // measured reports, source grants or business acceptance fixtures.
  const label = '"\\\u0001é🦀\ud800', visit = {workspace: label, opening: Number.MAX_SAFE_INTEGER};
  const opening = {...visit, attempt: label, openingOrdinal: Number.MAX_SAFE_INTEGER};
  const inventory = {...opening, inventoryRevision: label}, archive = {...inventory, operationOrdinal: Number.MAX_SAFE_INTEGER};
  const ready = {...archive, readyOrdinal: Number.MAX_SAFE_INTEGER};
  const bodies = [
    {kind: 'opening-stored', actual: opening},
    {kind: 'source-selected', actual: opening, sessionId: label, providerId: label, locator: label},
    ...(['project-selected', 'transfer-verified'] as const).map(kind => ({kind, actual: opening, sessionId: label, providerId: label, locator: label, projectId: label})),
    {kind: 'inventory-adopted', actual: inventory},
    ...(['archive-stored', 'archive-retirement-requested', 'archive-settled-retired'] as const).map(kind => ({kind, actual: archive})),
    ...(['archive-ready', 'download-will-request'] as const).map(kind => ({kind, actual: ready})),
    ...(['download-requested', 'retired', 'failed'] as const).map(result => ({kind: 'download-result', actual: ready, outcome: {kind: 'returned', result}})),
    {kind: 'download-result', actual: ready, outcome: {kind: 'raised'}},
    ...(['model-closed', 'workspace-closed'] as const).map(kind => ({kind, actual: visit})),
  ];
  const actual = journal(32, 32768, 4096);
  for (const [index, value] of bodies.entries()) {
    const input = {...value, sequence: index + 1} as ProductFact;
    actual.receive(input); const {pending, bytes} = copied(actual);
    assert.deepEqual(body(bytes), {kind: 1, sequence: BigInt(index + 1), value: input});
    assert.equal(actual.advance(pending.record), true);
  }
  const document = {}, scope = createProductObservation(document); scope.close(); actual.end(scope.state());
  assert.equal(actual.state().kind, 'ended');
});

test('a destination byteLength getter cannot manufacture backing or a copied result', () => {
  const actual = journal(); emit(actual); const pending = actual.pending(); assert(pending.kind === 'record');
  let getterReads = 0;
  class MisreportedDestination extends Uint8Array {
    override get byteLength() {getterReads++; return pending.kind === 'record' ? pending.record.byteLength : 0;}
  }
  const destination = new MisreportedDestination(0);
  assert.deepEqual(pending.record.copyInto(destination), {kind: 'refused', first: 'destination'});
  assert.equal(destination.length, 0); assert.equal(getterReads, 0);
});

for (const ending of ['returned', 'raised'] as const) test(`actual archive ${ending} boundary retains its adjacent burst behind a held cursor`, async () => {
  const prepared = prepareProductJournal({records: 16, journalBytes: 16384, frameBytes: 2048}, () => true);
  assert.equal(prepared.kind, 'prepared'); if (prepared.kind !== 'prepared') return;
  const journal = prepared.journal, facts: ProductFact[] = [], document = {}, scope = createProductObservation(document), opening = {};
  const descriptors = new Map(['document', 'addEventListener', 'removeEventListener'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  const failure = new Error('actual listener removal failure'), target = new EventTarget();
  let owned: OriginalArchiveOperation | undefined;
  try {
    Object.defineProperty(globalThis, 'document', {configurable: true, value: {createElement() {throw new Error('unit DOM refusal');}}});
    Object.defineProperty(globalThis, 'addEventListener', {configurable: true, value: target.addEventListener.bind(target)});
    Object.defineProperty(globalThis, 'removeEventListener', {configurable: true, value: (...args: Parameters<EventTarget['removeEventListener']>) => {
      target.removeEventListener(...args); if (ending === 'raised') throw failure;
    }});
    const start = createOriginalsArchive({kind: 'connected', entries: 1, rawBytes: 1, archiveNameBytes: 3,
      describe(sink) {sink.file('one', 1);}, copyFiles(sink) {sink.file('one', new Uint8Array([7]));}});
    assert.equal(start.kind, 'prepared'); if (start.kind !== 'prepared') return;
    const operation = start.operation; owned = operation;
    const received: OriginalArchiveEvent[] = []; prepareOriginalsArchive(operation, event => received.push(event));
    await operation.whenSettled(); const ready = received.find(event => event.kind === 'ready'); assert(ready?.kind === 'ready');
    scope.attach(document, {owners: 8, events: 16}, fact => {facts.push(fact); journal.receive(fact);}); scope.start(document);
    scope.openingStored(opening, 'workspace', 1, 'attempt');
    const held = journal.pending(); assert.equal(held.kind, 'record');
    scope.inventoryAdopted(opening, 'workspace', 1, 'attempt', 'revision');
    scope.archiveStored(operation, 'workspace', 1, 'revision'); scope.ready(operation, ready.archive);
    if (ending === 'raised') assert.throws(() => scope.requestDownload(operation, ready.archive), error => error === failure);
    else assert.equal(scope.requestDownload(operation, ready.archive).kind, 'failed');
    assert.deepEqual(facts.slice(-2).map(fact => fact.kind), ['download-will-request', 'download-result']);
    const result = facts.at(-1); assert(result?.kind === 'download-result');
    assert.deepEqual(result.outcome, ending === 'raised' ? {kind: 'raised'} : {kind: 'returned', result: 'failed'});
    scope.close(); journal.end(scope.state());
    assert.equal(journal.pending().kind, 'record');
    if (held.kind === 'record') {
      const same = journal.pending(); assert(same.kind === 'record'); assert.equal(same.record, held.record);
    }
  } finally {
    try {owned?.retire();} finally {
      try {await owned?.whenSettled();} finally {
        for (const [key, descriptor] of descriptors) if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);
      }
    }
  }
  // Actual archive encoding/retirement and unit globals settle before the RED oracle.
  assert.deepEqual(journal.state(), {kind: 'ended', records: facts.length + 1, facts: facts.length});
  for (const actual of facts) {
    const pending = journal.pending(); assert(pending.kind === 'record');
    const bytes = new Uint8Array(pending.record.byteLength); assert.equal(pending.record.copyInto(bytes).kind, 'copied');
    assert.deepEqual(body(bytes).value, actual); assert.equal(journal.advance(pending.record), true);
  }
});
