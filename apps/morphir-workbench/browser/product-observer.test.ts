// Synthetic observation-scope controls only. No product/host facts are minted.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createProductObservation, type ProductFact} from './product-observer.ts';

test('standard document starts unobserved and cannot attach after startup', () => {
  const document = {}, scope = createProductObservation(document);
  scope.start(document);
  assert.deepEqual(scope.state(), {kind: 'unobserved'});
  assert.equal(scope.attach(document, {owners: 4, events: 8}, () => {}), 'late');
});

test('attachment is one-use and belongs to the actual document', () => {
  const document = {}, scope = createProductObservation(document);
  const facts: ProductFact[] = [];
  assert.equal(scope.attach({}, {owners: 4, events: 8}, fact => facts.push(fact)), 'foreign-document');
  assert.equal(scope.attach(document, {owners: 4, events: 8}, fact => facts.push(fact)), 'attached');
  assert.equal(scope.attach(document, {owners: 4, events: 8}, () => {}), 'already-attached');
  scope.start(document);
  assert.deepEqual(scope.state(), {kind: 'active'});
  assert.deepEqual(facts, []);
});

test('sink failure is closed incomplete, never escapes or revives', () => {
  const document = {}, scope = createProductObservation(document);
  scope.attach(document, {owners: 4, events: 8}, () => {throw new Error('sink failure');});
  scope.start(document);
  assert.doesNotThrow(() => scope.openingStored({}, 'workspace', 1, '1'));
  assert.deepEqual(scope.state(), {kind: 'incomplete', cause: 'sink-raised'});
  assert.equal(scope.attach(document, {owners: 4, events: 8}, () => {}), 'late');
});

test('finite owner and event exhaustion are sticky incomplete without retained history', () => {
  for (const [limits, cause] of [[{owners: 0, events: 2}, 'owner-limit'], [{owners: 2, events: 0}, 'event-limit']] as const) {
    const document = {}, scope = createProductObservation(document), facts: ProductFact[] = [];
    scope.attach(document, limits, fact => facts.push(fact)); scope.start(document);
    scope.openingStored({}, 'workspace', 1, '1');
    assert.deepEqual(scope.state(), {kind: 'incomplete', cause});
    scope.openingStored({}, 'workspace', 1, '2'); assert.deepEqual(facts, []);
  }
});

test('observer receives frozen metadata projections rather than mutable physical owners', () => {
  const document = {}, scope = createProductObservation(document), facts: ProductFact[] = [];
  scope.attach(document, {owners: 4, events: 8}, fact => facts.push(fact)); scope.start(document);
  const actual = {}; scope.openingStored(actual, 'workspace', 1, '1');
  scope.inventoryAdopted(actual, 'workspace', 1, '1', '2');
  scope.archiveStored({}, 'workspace', 1, '2');
  assert.equal(facts.length, 3);
  for (const fact of facts) {assert(Object.isFrozen(fact)); assert(Object.isFrozen(fact.actual)); assert.notEqual(fact.actual, actual);}
  scope.close(); assert.deepEqual(scope.state(), {kind: 'closed'});
});

test('actual ready identity is required for an operation download association', () => {
  const document = {}, scope = createProductObservation(document), facts: ProductFact[] = [], opening = {}, operation = {}, ready = {};
  scope.attach(document, {owners: 8, events: 16}, fact => facts.push(fact)); scope.start(document);
  scope.openingStored(opening, 'workspace', 1, '1'); scope.inventoryAdopted(opening, 'workspace', 1, '1', '1');
  scope.archiveStored(operation, 'workspace', 1, '1'); scope.ready(operation, ready);
  scope.download(operation, {}, {kind: 'returned', result: 'download-requested'});
  assert.deepEqual(scope.state(), {kind: 'incomplete', cause: 'owner-mismatch'});
  assert.equal(facts.some(fact => fact.kind === 'download-result'), false);
});

for (const zero of ['owners', 'events'] as const) test(`attachment snapshots changing ${zero} once and preserves zero`, () => {
  const document = {}, scope = createProductObservation(document), facts: ProductFact[] = [];
  let ownerReads = 0, eventReads = 0;
  const limits = {
    get owners() {return ++ownerReads === 1 ? (zero === 'owners' ? 0 : 4) : Infinity;},
    get events() {return ++eventReads === 1 ? (zero === 'events' ? 0 : 8) : Infinity;},
  };
  assert.equal(scope.attach(document, limits, fact => facts.push(fact)), 'attached'); scope.start(document);
  scope.openingStored({}, 'workspace', 1, '1');
  assert.deepEqual(scope.state(), {kind: 'incomplete', cause: zero === 'owners' ? 'owner-limit' : 'event-limit'});
  assert.deepEqual(facts, []); assert.equal(ownerReads, 1); assert.equal(eventReads, 1);
});

test('invalid first getter readings refuse without installing a sink', () => {
  for (const invalid of ['owners', 'events'] as const) {
    const document = {}, scope = createProductObservation(document);
    let ownerReads = 0, eventReads = 0;
    const limits = {
      get owners() {return ++ownerReads === 1 && invalid === 'owners' ? Infinity : 0;},
      get events() {return ++eventReads === 1 && invalid === 'events' ? NaN : 0;},
    };
    assert.throws(() => scope.attach(document, limits, () => {}), RangeError);
    assert.equal(ownerReads, 1); assert.equal(eventReads, 1);
    assert.equal(scope.attach(document, {owners: 0, events: 0}, () => {}), 'attached');
  }
});
