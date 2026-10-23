import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {
  openConnectedOriginals, openConnectedModel, PendingInspectionFailure, type ConnectedModelEvent,
  type ConnectedOriginalsEvent, type ConnectedOriginalsOpening,
  type StagedOriginals,
} from './connected-originals.ts';
import {inventoryDigest, type Entry, type Hasher} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';
import {ConnectedInspectionControls} from './connected-inspection.ts';
import {clickConnectedChoice, type ChoiceDocument} from './connected-choice-dom.ts';
import {ModelOriginalsConnectionLimits} from './model-originals-session.ts';

const hash = (): Hasher => {
  const value = createHash('sha256');
  return {update(bytes) { value.update(bytes); }, hex() { return value.digest('hex'); }};
};
const profile = {profile: 'morphir/workbench/model-originals', contractVersion: '0.1.0-draft.1'};
const projectionBytes = Buffer.from('{"formatVersion":4,"distribution":null}');
const bytes = new Map([
  ['model.yaml', Buffer.from('\ufeff# original\r\nformatVersion: 4\r\n')],
  ['notes/empty.bin', Buffer.alloc(0)], ['notes/opaque.bin', Buffer.from([0, 255, 1, 0])],
]);
const entries: Entry[] = [
  {kind: 'file', entryId: 'model', path: 'model.yaml', byteLength: bytes.get('model.yaml')!.length,
    sha256: createHash('sha256').update(bytes.get('model.yaml')!).digest('hex')},
  {kind: 'directory', entryId: 'notes', path: 'notes'},
  {kind: 'directory', entryId: 'empty', path: 'notes/empty'},
  ...['notes/empty.bin', 'notes/opaque.bin'].map(path => ({kind: 'file' as const, entryId: path, path,
    byteLength: bytes.get(path)!.length, sha256: createHash('sha256').update(bytes.get(path)!).digest('hex')})),
];
type Request = {id: number; method: string; params: Record<string, unknown>};

// Actual HTTP/WebSocket fixture around the maintained session and receiver.
// It is not a model-originals profile or platform qualification fixture.
function fixture(options: {holdRelease?: boolean; wrongRelease?: boolean; projection?: 'available' | 'unavailable'; invalidHeader?: boolean} = {}) {
  const sources = ['A', 'B'].map(id => ({providerId: 'provider', locator: `workspace:${id}`, displayName: 'Same label'}));
  const requests: Request[] = [];
  let manifestRequests = 0, selected = sources[0]!;
  let release: (() => void) | undefined, disconnect: (() => void) | undefined;
  let sawRelease!: () => void, sawFailure!: () => void;
  const releaseRequested = new Promise<void>(resolve => {sawRelease = resolve;});
  const failed = new Promise<void>(resolve => {sawFailure = resolve;});
  const server = Bun.serve({port: 0,
    fetch(request, server) {
      if (new URL(request.url).pathname === '/api/session') {
        manifestRequests++;
        return Response.json({protocolVersion: 1, sessionId: 'session', webSocketPath: '/rpc',
          providers: [{id: 'provider', name: 'Fixture', kind: 'connected', status: 'available', capabilities: [
            {name: 'morphir/workspace/open', version: '1'},
            {name: profile.profile, version: profile.contractVersion},
          ]}], initialSources: sources});
      }
      if (server.upgrade(request)) return;
      return new Response('Not found', {status: 404});
    },
    websocket: {message(socket, raw) {
      disconnect = () => socket.close();
      const request = JSON.parse(String(raw)) as Request;
      requests.push(request);
      const binding = {sessionId: 'session', source: {providerId: selected.providerId, locator: selected.locator}, projectId: 'project-B'};
      let result: unknown;
      switch (request.method) {
        case 'morphir.session.initialize': result = {protocolVersion: 1}; break;
        case 'morphir.workspace.open': {
          selected = request.params.source as typeof selected;
          result = {snapshot: {id: 'workspace', root: selected, name: 'Same label', configAnchor: null,
            state: 'open', projects: ['A', 'B'].map(id => ({id: `project-${id}`, name: 'Same project', state: 'unloaded'})),
            modelSources: [], knowledgeBaseSources: [], diagnostics: []}};
          break;
        }
        case 'morphir.model-originals.capture': result = {...profile, status: 'ready', binding, captureId: 'capture',
          coverage: {kind: 'complete', declaration: profile.contractVersion},
          origin: {kind: 'compiled', record: {byteLength: 100, sha256: '0'.repeat(64), schema: 1, task: 'compile', module: '',
            ir: {path: 'model.yaml', layout: 'single-file', format: 'yaml', version: 'v4'}}},
          primary: {kind: 'file', path: 'model.yaml'}, companions: [{kind: 'directory', path: 'notes'}],
          sourceFormatVersion: {status: 'reported', release: '4.0.0'}, projection: options.projection === 'available'
            ? {status: 'available', codec: 'morphir-json', byteLength: projectionBytes.length,
              sha256: createHash('sha256').update(projectionBytes).digest('hex'), formatVersion: '4.0.0'}
            : options.projection === 'unavailable' ? {status: 'unavailable', reason: 'invalid_model'} : {status: 'not-requested'},
          inventory: {entryCount: entries.length, fileCount: 3, directoryCount: 2,
            sourceByteLength: [...bytes.values()].reduce((sum, item) => sum + item.length, 0), sha256: inventoryDigest(entries, hash())}}; break;
        case 'morphir.model-originals.inventory': result = {...profile, binding, captureId: 'capture',
          inventorySha256: inventoryDigest(entries, hash()), startIndex: 0, entries, next: {kind: 'complete'}}; break;
        case 'morphir.model-originals.read': {
          const target = request.params.target as {kind: string; entryId?: string};
          const entry = entries.find(item => item.entryId === target.entryId);
          const content = target.kind === 'semantic-projection' ? projectionBytes : bytes.get(entry!.path)!;
          result = {...profile, binding, captureId: 'capture', target: request.params.target,
            offset: 0, nextOffset: content.length, content: content.toString('base64')}; break;
        }
        case 'morphir.model-originals.release': result = {...profile, captureId: options.wrongRelease ? 'foreign' : 'capture', status: 'released'}; break;
        default: throw new Error(`Unexpected fixture method ${request.method}`);
      }
      const reply = () => socket.send(JSON.stringify({jsonrpc: '2.0', id: request.id, result}));
      if (request.method === 'morphir.model-originals.release' && options.holdRelease) {release = reply; sawRelease();}
      else reply();
    }},
  });
  const events: ConnectedOriginalsEvent[] = [];
  const modelEvents: ConnectedModelEvent[] = [];
  const open = (receive: (event: ConnectedOriginalsEvent) => void = event => events.push(event), current = () => true) =>
    openConnectedOriginals({base: new URL(server.url), limits: ModelOriginalsConnectionLimits.create({manifestBytes: 128 * 1024}), makeHash: hash, current, receive(event) {
      if (event.kind === 'failed') sawFailure();
      receive(event);
    }});
  const openModel = (receive: (event: ConnectedModelEvent) => void = event => modelEvents.push(event), current = () => true) =>
    openConnectedModel({base: new URL(server.url), limits: ModelOriginalsConnectionLimits.create({manifestBytes: 128 * 1024}), makeHash: hash,
      // Literal stub controls owner behavior only, not actual header recognition.
      recognizeHeader(actual) {
        assert.deepEqual(Buffer.from(actual), projectionBytes);
        if (options.invalidHeader) throw new Error('actual header dependency refused');
        return '4.0.0';
      },
      current, receive(event) {if (event.kind === 'failed') sawFailure(); receive(event);}});
  return {open, openModel, events, modelEvents, requests, release: () => { assert(release); release(); }, disconnect: () => {assert(disconnect); disconnect();},
    manifests: () => manifestRequests, releaseRequested, failed, stop: () => server.stop(true)};
}
async function selected(opening: Pick<ConnectedOriginalsOpening, 'whenSettled' | 'sourceNames' | 'chooseSource' | 'projectNames' | 'chooseProject'>) {
  await opening.whenSettled();
  assert.deepEqual(opening.sourceNames(), ['Same label', 'Same label']);
  assert.equal(opening.chooseSource(1), 'started'); await opening.whenSettled();
  assert.deepEqual(opening.projectNames(), ['Same project', 'Same project']);
  assert.equal(opening.chooseProject(1), 'started');
}
function received(events: ConnectedOriginalsEvent[]): StagedOriginals {
  const event = events.find(event => event.kind === 'received');
  assert(event?.kind === 'received'); return event.stage;
}

test('actual discovered identities select complete/none and retain exact originals until one adoption', async () => {
  const f = fixture(), opening = f.open();
  try {
    await selected(opening); await opening.whenSettled();
    const stage = received(f.events);
    assert.equal(stage.current(), true); assert.equal(opening.view(), 'queued');
    assert.deepEqual(f.requests.find(request => request.method.endsWith('.capture'))!.params, {
      contractVersion: profile.contractVersion, source: {providerId: 'provider', locator: 'workspace:B'},
      projectId: 'project-B', scope: 'complete', semantic: 'none',
    });
    let adoptions = 0;
    assert.equal(stage.take(payload => {
      adoptions++;
      assert.deepEqual(payload.directories, ['notes', 'notes/empty']);
      assert.deepEqual(payload.sourceFormatVersion, {status: 'reported', release: '4.0.0'});
      assert.deepEqual(payload.files.map(file => [file.path, Buffer.from(file.bytes)]), [...bytes]);
      assert.equal(stage.current(), false);
      assert.equal(stage.take(() => { throw new Error('Reentrant adoption'); }), 'stale');
    }), 'taken');
    assert.equal(adoptions, 1); assert.equal(stage.take(() => adoptions++), 'stale');
    assert.equal(opening.view(), 'retired');
  } finally { opening.dispose(); await f.stop(); }
});

test('release reply must validate before staging, and cancellation drops a pending transfer', async () => {
  const f = fixture({holdRelease: true}), opening = f.open();
  try {
    await selected(opening);
    await f.releaseRequested;
    assert.equal(f.events.some(event => event.kind === 'received'), false);
    opening.dispose(); await opening.whenSettled();
    assert.equal(opening.view(), 'retired');
    assert.equal(f.events.some(event => event.kind === 'received'), false);
  } finally { opening.dispose(); await f.stop(); }
});

test('queued delivery keeps the owner alive until adoption, while disconnect invalidates the stage', async () => {
  const f = fixture(), opening = f.open();
  try {
    await selected(opening); await opening.whenSettled();
    const stage = received(f.events); assert(stage.current());
    f.disconnect(); await f.failed;
    assert.equal(stage.take(() => { throw new Error('Disconnected adoption'); }), 'stale');
    assert.equal(opening.view(), 'failed');
  } finally { opening.dispose(); await f.stop(); }
});

test('caller currentness is checked again when the queued handler takes originals', async () => {
  const f = fixture(); let current = true;
  const opening = f.open(undefined, () => current);
  try {
    await selected(opening); await opening.whenSettled();
    const stage = received(f.events); current = false;
    assert.equal(stage.take(() => { throw new Error('Stale adoption'); }), 'stale');
    assert.equal(opening.view(), 'retired');
  } finally { opening.dispose(); await f.stop(); }
});

test('foreign release refuses staging and closes the attempt', async () => {
  const f = fixture({wrongRelease: true}), opening = f.open();
  try {
    await selected(opening); await opening.whenSettled();
    assert.equal(opening.view(), 'failed');
    assert.equal(f.events.some(event => event.kind === 'received'), false);
    assert.equal(f.events.filter(event => event.kind === 'failed').length, 1);
  } finally { opening.dispose(); await f.stop(); }
});

test('invalid choices and overlap cannot manufacture selections or another capture', async () => {
  const f = fixture(), opening = f.open();
  try {
    await opening.whenSettled();
    for (const index of [-1, 0.5, NaN, 2]) assert.equal(opening.chooseSource(index), 'ignored');
    assert.equal(opening.chooseProject(0), 'ignored');
    assert.equal(opening.chooseSource(1), 'started');
    assert.equal(opening.chooseSource(0), 'ignored'); await opening.whenSettled();
    for (const index of [-1, 0.5, Infinity, 2]) assert.equal(opening.chooseProject(index), 'ignored');
    assert.equal(opening.chooseProject(1), 'started'); assert.equal(opening.chooseProject(0), 'ignored');
    await opening.whenSettled();
    assert.equal(f.requests.filter(request => request.method.endsWith('.capture')).length, 1);
  } finally { opening.dispose(); await f.stop(); }
});

test('dispose before discovery performs no HTTP or socket effects', async () => {
  const f = fixture(), opening = f.open();
  try {
    opening.dispose(); opening.dispose(); await opening.whenSettled();
    assert.equal(f.manifests(), 0); assert.equal(f.requests.length, 0); assert.deepEqual(f.events, []);
  } finally { await f.stop(); }
});

test('a delivery exception retires the stage without changing successful release into adoption', async () => {
  const f = fixture(); let stage: StagedOriginals | undefined;
  const opening = f.open(event => {
    if (event.kind === 'received') {stage = event.stage; throw new Error('Handler unavailable');}
  });
  try {
    await selected(opening); await opening.whenSettled();
    assert(stage); assert.equal(stage.current(), false); assert.equal(opening.view(), 'retired');
    assert(f.requests.some(request => request.method.endsWith('.release')));
  } finally { opening.dispose(); await f.stop(); }
});

test('model inspection owns a released transfer through held core and actual stored settlement', async () => {
  const f = fixture({holdRelease: true, projection: 'available'}), opening = f.openModel();
  const controls = new ConnectedInspectionControls();
  controls.prepareObserved(); controls.register(opening);
  try {
    const pendingBoundary = opening.whenInspectionPending();
    let pendingObserved = false;
    void pendingBoundary.then(() => {pendingObserved = true;});
    await selected(opening); await f.releaseRequested;
    assert.equal(f.modelEvents.some(event => event.kind === 'inspection'), false);
    f.release(); await opening.whenSettled();
    assert.equal(f.requests.find(request => request.method.endsWith('.capture'))!.params.semantic, 'projection');
    const event = f.modelEvents.find(event => event.kind === 'inspection');
    assert(event?.kind === 'inspection');
    const stage = event.stage;
    assert.equal(pendingObserved, false, 'received projection is not a held genuine core command');
    let takes = 0, enqueues = 0, inspections = 0, cancellations = 0;
    assert.equal(stage.take(payload => {
      takes++;
      assert.deepEqual(payload.files.map(file => [file.path, Buffer.from(file.bytes)]), [...bytes]);
    }), 'taken');
    assert.equal(takes, 1);
    assert(stage.current(), 'taking originals must retain the projection and opening owner');
    assert.equal(stage.take(() => {throw new Error('duplicate originals adoption');}), 'stale');
    assert.equal(controls.hold(stage, () => {enqueues++;}, () => {cancellations++;}), 'held');
    assert.equal((await pendingBoundary).kind, 'inspection-pending');
    assert.deepEqual(await controls.awaitBoundary('inspection-pending'), {kind: 'inspection-pending'});
    assert.strictEqual(opening.currentPendingInspection, stage);
    assert.equal(enqueues, 0);
    assert.equal(inspections, 0);
    assert.equal(controls.executePendingCore(), 'enqueued');
    assert.equal(controls.executePendingCore(), 'ignored');
    assert.equal(enqueues, 1);
    const actualResult = {success: true, ir: {formatVersion: 4}};
    const result = await stage.inspect(async actual => {
      inspections++;
      assert.deepEqual(Buffer.from(actual.copyBytes()), projectionBytes);
      return actualResult;
    });
    assert.strictEqual(result, actualResult);
    assert.equal(inspections, 1);
    assert(stage.current());
    let settled = false;
    const stored = opening.whenOpeningSettled();
    void stored.then(() => {settled = true;});
    await Promise.resolve();
    assert.equal(settled, false, 'actual adapter result alone is not model storage');
    stage.settle();
    assert.equal((await stored).kind, 'stored');
    assert.deepEqual(await controls.awaitBoundary('opening-settled'), {kind: 'stored'});
    assert.equal(stage.current(), false);
    assert.equal(opening.view(), 'retired');
    assert.equal(cancellations, 0);
  } finally {opening.dispose(); await f.stop();}
});

test('ordinary inspection control runs its genuine held command and a replaced boundary cannot report stored', async () => {
  const f = fixture({projection: 'available'});
  const {opening, stage} = await pendingModel(f);
  const controls = new ConnectedInspectionControls();
  try {
    controls.register(opening);
    let enqueues = 0, cancels = 0;
    stage.take(() => {});
    const settled = controls.awaitBoundary('opening-settled');
    assert.equal(controls.hold(stage, () => {enqueues++;}, () => {cancels++;}), 'held');
    assert.equal(enqueues, 1);
    assert.equal(controls.executePendingCore(), 'ignored');
    assert.throws(() => controls.prepareObserved(), /before opening/);
    controls.unregister(opening); opening.dispose();
    assert.deepEqual(await settled, {kind: 'replaced'});
    assert.equal(cancels, 1);
    assert.deepEqual(await controls.awaitBoundary('inspection-pending'), {kind: 'no-opening'});
    controls.revoke(); controls.revoke();
    assert.equal(controls.executePendingCore(), 'ignored');
    assert.deepEqual(await controls.awaitBoundary('inspection-pending'), {kind: 'retired'});
  } finally {opening.dispose(); await f.stop();}
});

async function pendingModel(f: ReturnType<typeof fixture>, current = () => true) {
  const opening = f.openModel(undefined, current);
  await selected(opening); await opening.whenSettled();
  const event = f.modelEvents.find(event => event.kind === 'inspection');
  assert(event?.kind === 'inspection');
  return {opening, stage: event.stage};
}

test('model stage refuses early duplicate and reentrant execution without starting another inspection', async () => {
  const f = fixture({projection: 'available'});
  const {opening, stage} = await pendingModel(f);
  try {
    let inspections = 0, enqueues = 0;
    const perform = async () => {inspections++; return {success: true};};
    assert.equal(stage.hold(() => {throw new Error('originals not retained');}, () => {}), 'ignored');
    await assert.rejects(stage.inspect(perform), cause => cause instanceof PendingInspectionFailure && cause.code === 'not-enqueued');
    stage.take(() => {});
    await assert.rejects(stage.inspect(perform), cause => cause instanceof PendingInspectionFailure && cause.code === 'not-enqueued');
    assert.equal(stage.hold(() => {
      enqueues++;
      assert.equal(stage.executePendingCore(), 'ignored');
    }, () => {}), 'held');
    assert.equal(stage.hold(() => {throw new Error('replacement enqueue');}, () => {}), 'ignored');
    assert.equal(stage.settle(), 'ignored');
    stage.executePendingCore();
    const actual = Promise.withResolvers<{success: boolean}>();
    const first = stage.inspect(() => {inspections++; return actual.promise;});
    await assert.rejects(stage.inspect(perform), cause => cause instanceof PendingInspectionFailure && cause.code === 'already-inspected');
    actual.resolve({success: true}); await first;
    await assert.rejects(stage.inspect(perform), cause => cause instanceof PendingInspectionFailure && cause.code === 'already-inspected');
    assert.equal(enqueues, 1); assert.equal(inspections, 1);
    stage.settle();
  } finally {opening.dispose(); await f.stop();}
});

test('dispose and replacement consume held authority and invoke owned cancellation at most once', async () => {
  for (const ending of ['dispose', 'replacement'] as const) {
    const f = fixture({projection: 'available'});
    let current = true;
    const {opening, stage} = await pendingModel(f, () => current);
    try {
      let enqueues = 0, cancels = 0;
      stage.take(() => {});
      stage.hold(() => {enqueues++;}, () => {cancels++; opening.dispose();});
      if (ending === 'dispose') opening.dispose(); else current = false;
      assert.equal(stage.executePendingCore(), 'ignored');
      stage.dispose(); opening.dispose();
      assert.equal(enqueues, 0); assert.equal(cancels, 1);
      assert.equal((await opening.whenOpeningSettled()).kind, 'retired');
      await assert.rejects(stage.inspect(async () => {throw new Error('stale worker started');}),
        cause => cause instanceof PendingInspectionFailure && cause.code === 'stale');
    } finally {opening.dispose(); await f.stop();}
  }
});

test('stale selection before hold cannot retain or enqueue a core command', async () => {
  const f = fixture({projection: 'available'});
  let current = true;
  const {opening, stage} = await pendingModel(f, () => current);
  try {
    let enqueues = 0, cancels = 0;
    stage.take(() => {}); current = false;
    assert.equal(stage.hold(() => {enqueues++;}, () => {cancels++;}), 'ignored');
    assert.equal(stage.executePendingCore(), 'ignored');
    assert.equal(enqueues, 0); assert.equal(cancels, 0);
    assert.equal((await opening.whenInspectionPending()).kind, 'retired');
    assert.equal((await opening.whenOpeningSettled()).kind, 'retired');
  } finally {opening.dispose(); await f.stop();}
});

test('enqueue and adoption exceptions retain their actual identity and cannot leave reusable authority', async () => {
  const f = fixture({projection: 'available'});
  const {opening, stage} = await pendingModel(f);
  const actualError = new Error('actual enqueue failed');
  try {
    let cancels = 0;
    stage.take(() => {});
    stage.hold(() => {throw actualError;}, () => {cancels++; throw new Error('cancel must not replace enqueue error');});
    assert.throws(() => stage.executePendingCore(), cause => cause === actualError);
    assert.equal(stage.executePendingCore(), 'ignored');
    assert.equal(cancels, 1); assert.equal(stage.current(), false);
    assert.equal((await opening.whenOpeningSettled()).kind, 'retired');
  } finally {opening.dispose(); await f.stop();}
  const other = fixture({projection: 'available'});
  const adopted = await pendingModel(other);
  try {
    assert.throws(() => adopted.stage.take(() => {throw actualError;}), cause => cause === actualError);
    assert.equal(adopted.stage.current(), false);
    assert.equal((await adopted.opening.whenInspectionPending()).kind, 'retired');
  } finally {adopted.opening.dispose(); await other.stop();}
});

test('late actual inspection settlements preserve value or thrown identity without resurrecting adoption', async () => {
  for (const ending of ['returned', 'raised'] as const) {
    const f = fixture({projection: 'available'});
    const {opening, stage} = await pendingModel(f);
    try {
      let cancels = 0;
      const actual = Promise.withResolvers<{success: boolean}>();
      const result = {success: true};
      stage.take(() => {}); stage.hold(() => {}, () => {cancels++;}); stage.executePendingCore();
      const inspected = stage.inspect(() => actual.promise);
      opening.dispose(); opening.dispose();
      if (ending === 'returned') {actual.resolve(result); assert.strictEqual(await inspected, result);}
      else {actual.reject(false); await assert.rejects(inspected, cause => cause === false);}
      assert.equal(cancels, 1);
      assert.equal(stage.settle(), 'ignored');
      assert.equal((await opening.whenOpeningSettled()).kind, 'retired');
    } finally {opening.dispose(); await f.stop();}
  }
});

for (const fallback of ['unavailable', 'unusable'] as const)
test(`model ${fallback} fallback retains its original payload until actual stored settlement`, async () => {
  const f = fixture({projection: fallback === 'unavailable' ? 'unavailable' : 'available', invalidHeader: fallback === 'unusable'});
  const opening = f.openModel();
  try {
    await selected(opening); await opening.whenSettled();
    assert.equal((await opening.whenInspectionPending()).kind, 'originals-only');
    assert.equal(opening.currentPendingInspection, undefined);
    const event = f.modelEvents.find(event => event.kind === 'received');
    assert(event?.kind === 'received');
    assert(event.inspectionMessage.length > 0 && event.inspectionMessage.length <= 160);
    assert.equal(opening.settleOriginals(), 'ignored');
    assert.equal(event.stage.take(payload => {
      assert.deepEqual(payload.files.map(file => [file.path, Buffer.from(file.bytes)]), [...bytes]);
    }), 'taken');
    assert.equal(event.stage.take(() => {throw new Error('duplicate fallback payload');}), 'stale');
    assert(event.stage.current());
    assert.equal(opening.view(), 'queued');
    assert.equal(opening.settleOriginals(), 'settled');
    assert.equal((await opening.whenOpeningSettled()).kind, 'stored');
    assert.equal(opening.settleOriginals(), 'ignored');
    assert.equal(event.stage.current(), false);
  } finally {opening.dispose(); await f.stop();}
});

test('failed release and inspection event delivery refusal never create a pending core boundary', async () => {
  for (const fallback of ['verified', 'unavailable', 'unusable'] as const) {
    const wrong = fixture({projection: fallback === 'unavailable' ? 'unavailable' : 'available',
      invalidHeader: fallback === 'unusable', wrongRelease: true}), failed = wrong.openModel();
    try {
      await selected(failed); await failed.whenSettled();
      assert.equal((await failed.whenInspectionPending()).kind, 'failed');
      assert.equal((await failed.whenOpeningSettled()).kind, 'failed');
      assert.equal(wrong.modelEvents.some(event => event.kind === 'inspection' || event.kind === 'received'), false);
    } finally {failed.dispose(); await wrong.stop();}
  }
  const f = fixture({projection: 'available'});
  const opening = f.openModel(event => {if (event.kind === 'inspection') throw new Error('actual event handler unavailable');});
  try {
    await selected(opening); await opening.whenSettled();
    assert.equal((await opening.whenInspectionPending()).kind, 'retired');
    assert.equal((await opening.whenOpeningSettled()).kind, 'retired');
    assert.equal(opening.currentPendingInspection, undefined);
    assert(f.requests.some(request => request.method.endsWith('.release')));
  } finally {opening.dispose(); await f.stop();}
});

test('an armed capture waits for the new actual registration and never returns the previous opening', async () => {
  const f = fixture({projection: 'available'}), controls = new ConnectedInspectionControls();
  controls.prepareObserved();
  const old = f.openModel(), next = f.openModel();
  try {
    controls.register(old);
    const capture = controls.prepareOpeningCapture();
    let delivered = false;
    const registered = capture.whenRegistered().then(pin => {delivered = true; return pin;});
    await Promise.resolve(); assert.equal(delivered, false);
    assert.throws(() => controls.prepareOpeningCapture(), /already armed/);
    controls.register(old);
    await Promise.resolve(); assert.equal(delivered, false, 're-registering the same owner is not a new opening');
    controls.register(next);
    const pin = await registered;
    assert.equal(old.view() === 'retired', false, 'capture itself must not dispose the old application owner');
    pin.dispose(); await pin.whenSettled();
    assert.equal(next.view(), 'retired');
    assert.equal(old.view() === 'retired', false, 'captured cleanup cannot target another owner');
  } finally {controls.revoke(); old.dispose(); next.dispose(); await f.stop();}
});

test('choice identities project actual discovered objects without following stale phases or display names', async () => {
  const f = fixture(), opening = f.open();
  try {
    assert.deepEqual(opening.sourceIdentity(0), []);
    assert.deepEqual(opening.projectIdentity(0), []);
    await opening.whenSettled();
    assert.deepEqual(opening.sourceNames(), ['Same label', 'Same label']);
    assert.deepEqual(opening.sourceIdentity(0), ['provider', 'workspace:A']);
    assert.deepEqual(opening.sourceIdentity(1), ['provider', 'workspace:B']);
    assert(Object.isFrozen(opening.sourceIdentity(1)));
    for (const index of [-1, 2, 0.5, NaN, Infinity]) assert.deepEqual(opening.sourceIdentity(index), []);
    assert.equal(opening.chooseSource(1), 'started');
    assert.deepEqual(opening.sourceIdentity(1), []);
    await opening.whenSettled();
    assert.deepEqual(opening.projectNames(), ['Same project', 'Same project']);
    assert.deepEqual(opening.projectIdentity(0), ['project-A']);
    assert.deepEqual(opening.projectIdentity(1), ['project-B']);
    for (const index of [-1, 2, 0.5, NaN, Infinity]) assert.deepEqual(opening.projectIdentity(index), []);
    assert.equal(opening.chooseProject(1), 'started'); await opening.whenSettled();
    assert.deepEqual(opening.projectIdentity(1), []);
    const request = f.requests.find(request => request.method.endsWith('.capture')); assert(request);
    assert.deepEqual(request.params.source, {providerId: 'provider', locator: 'workspace:B'});
    assert.equal(request.params.projectId, 'project-B');
  } finally {opening.dispose(); await f.stop();}
});

test('captured opening wakes on replacement and old cleanup never disposes its successor', async () => {
  const f = fixture({projection: 'available'}), controls = new ConnectedInspectionControls();
  controls.prepareObserved();
  const capture = controls.prepareOpeningCapture(), old = f.openModel(), next = f.openModel();
  try {
    controls.register(old); const pin = await capture.whenRegistered();
    const waiting = pin.awaitBoundary('inspection-pending');
    controls.register(next);
    assert.deepEqual(await waiting, {kind: 'replaced'});
    assert.deepEqual(await pin.awaitBoundary('opening-settled'), {kind: 'replaced'});
    assert.equal(pin.executePendingCore(), 'ignored');
    pin.dispose(); await pin.whenSettled();
    assert.equal(old.view(), 'retired');
    await next.whenSettled(); assert.equal(next.view(), 'sources');
    assert.equal(next.chooseSource(1), 'started');
  } finally {controls.revoke(); old.dispose(); next.dispose(); await f.stop();}
});

test('normal unregistration preserves actual stored settlement without following a new owner', async () => {
  const f = fixture({projection: 'unavailable'}), controls = new ConnectedInspectionControls();
  controls.prepareObserved();
  const capture = controls.prepareOpeningCapture(), opening = f.openModel();
  try {
    controls.register(opening); const pin = await capture.whenRegistered();
    await selected(opening); await opening.whenSettled();
    const event = f.modelEvents.find(event => event.kind === 'received'); assert(event?.kind === 'received');
    event.stage.take(() => {});
    const waiting = pin.awaitBoundary('opening-settled');
    assert.equal(opening.settleOriginals(), 'settled');
    controls.unregister(opening);
    assert.deepEqual(await waiting, {kind: 'stored'});
    assert.deepEqual(await pin.awaitBoundary('opening-settled'), {kind: 'stored'});
    const next = f.openModel();
    controls.register(next);
    try {assert.deepEqual(await pin.awaitBoundary('opening-settled'), {kind: 'replaced'});}
    finally {next.dispose();}
  } finally {controls.revoke(); opening.dispose(); await f.stop();}
});

test('capture cancellation and page revocation refuse later registration and held effects', async () => {
  const f = fixture(), controls = new ConnectedInspectionControls();
  controls.prepareObserved();
  const cancelled = controls.prepareOpeningCapture();
  const cancellation = assert.rejects(cancelled.whenRegistered(), /capture cancelled/);
  cancelled.cancel(); await cancellation;
  const armed = controls.prepareOpeningCapture();
  const revoked = assert.rejects(armed.whenRegistered(), /controls closed/);
  controls.revoke(); await revoked;
  assert.throws(() => controls.prepareOpeningCapture(), /observed opening capture/);
  const late = f.openModel(); controls.register(late);
  assert.equal(late.view(), 'retired');
  await f.stop();
});

test('observed choice resolves only from the same nominal row actually accepted by the opening', async () => {
  const f = fixture(), opening = f.open();
  try {
    let effects = 0;
    assert.deepEqual(await opening.observeSourceChoice('provider', 'workspace:B', () => {effects++; return 'clicked';}), {kind: 'not-ready'});
    assert.equal(effects, 0);
    await opening.whenSettled();
    assert.deepEqual(await opening.observeSourceChoice('provider', 'missing', () => {effects++; return 'clicked';}), {kind: 'unavailable'});
    const pending = opening.observeSourceChoice('provider', 'workspace:B', index => {effects++; assert.equal(index, 1); return 'clicked';});
    let resolved = false; void pending.then(() => {resolved = true;});
    await Promise.resolve(); assert.equal(resolved, false, 'a click is not acceptance');
    assert.equal(opening.chooseSource(1), 'started');
    assert.deepEqual(await pending, {kind: 'source-selected'}); await opening.whenSettled();
    assert.deepEqual(await opening.observeProjectChoice('project-B', index => {
      assert.equal(index, 1); opening.chooseProject(index); return 'clicked';
    }), {kind: 'project-selected'});
    await opening.whenSettled(); assert.equal(effects, 1);
    const request = f.requests.find(request => request.method.endsWith('.capture')); assert(request);
    assert.deepEqual(request.params.source, {providerId: 'provider', locator: 'workspace:B'});
    assert.equal(request.params.projectId, 'project-B');
  } finally {opening.dispose(); await f.stop();}
});

test('observed choice retains wrong-row, unavailable, overlap and retirement outcomes without inventing acceptance', async () => {
  const f = fixture(), opening = f.open();
  try {
    await opening.whenSettled();
    assert.deepEqual(await opening.observeSourceChoice('provider', 'workspace:B', () => 'unavailable'), {kind: 'unavailable'});
    const pending = opening.observeSourceChoice('provider', 'workspace:B', () => 'clicked');
    await assert.rejects(opening.observeSourceChoice('provider', 'workspace:A', () => 'clicked'), /choice already outstanding/);
    opening.chooseSource(0);
    assert.deepEqual(await pending, {kind: 'other-selection'}); await opening.whenSettled();
    const project = opening.observeProjectChoice('project-B', () => 'clicked');
    opening.dispose(); assert.deepEqual(await project, {kind: 'retired'});
    assert.deepEqual(await opening.observeProjectChoice('project-B', () => {throw new Error('must not click');}), {kind: 'retired'});
  } finally {opening.dispose(); await f.stop();}
});

test('fixed DOM selection requires one connected enabled exact-identity button at the actual row', () => {
  let clicks = 0;
  const button = (locator: string) => ({disabled: false, isConnected: true,
    getAttribute: (key: string) => key === 'data-model-source-provider' ? 'provider' : locator,
    click: () => {clicks++;}});
  const first = button('workspace:A'), second = button('workspace:B');
  let buttons = [first, second];
  const root = {querySelectorAll: (selector: string) => {
    assert.equal(selector, 'button[data-model-source-provider][data-model-source-locator]'); return buttons;
  }} as unknown as ChoiceDocument;
  const choice = {kind: 'source', providerId: 'provider', locator: 'workspace:B'} as const;
  assert.equal(clickConnectedChoice(root, choice, 1, 2), 'clicked');
  assert.equal(clickConnectedChoice(root, choice, 0, 2), 'unavailable');
  buttons = [second, second]; assert.equal(clickConnectedChoice(root, choice, 1, 2), 'unavailable');
  buttons = [first, second]; second.disabled = true; assert.equal(clickConnectedChoice(root, choice, 1, 2), 'unavailable');
  second.disabled = false; second.isConnected = false; assert.equal(clickConnectedChoice(root, choice, 1, 2), 'unavailable');
  buttons = [first]; assert.equal(clickConnectedChoice(root, choice, 1, 2), 'unavailable');
  buttons = [first, second, {...second, getAttribute: () => {throw new Error('must not scan over-count DOM');}}];
  assert.equal(clickConnectedChoice(root, choice, 1, 2), 'unavailable');
  buttons = []; assert.equal(clickConnectedChoice(root, choice, 0, 0), 'unavailable');
  assert.equal(clicks, 1);
});

test('captured DOM choice awaits actual acceptance, and replacement cancels observation without clicking the successor', async () => {
  const f = fixture(); let clicks = 0;
  let activate: (() => void) | undefined;
  const root = {querySelectorAll: () => ['A', 'B'].map(id => ({disabled: false, isConnected: true,
    getAttribute: (key: string) => key === 'data-model-source-provider' ? 'provider' : `workspace:${id}`,
    click: () => {clicks++; activate?.();}}))} as unknown as ChoiceDocument;
  const controls = new ConnectedInspectionControls(() => root); controls.prepareObserved();
  const capture = controls.prepareOpeningCapture(), opening = f.openModel(), next = f.openModel();
  try {
    controls.register(opening); const pin = await capture.whenRegistered(); await opening.whenSettled();
    const pending = pin.chooseSource('provider', 'workspace:B');
    let resolved = false; void pending.then(() => {resolved = true;});
    await Promise.resolve(); assert.equal(resolved, false);
    await assert.rejects(pin.awaitBoundary('inspection-pending'), /already outstanding/);
    controls.register(next);
    assert.deepEqual(await pending, {kind: 'replaced'});
    assert.deepEqual(await pin.chooseSource('provider', 'workspace:B'), {kind: 'replaced'});
    await next.whenSettled(); assert.equal(next.view(), 'sources'); assert.equal(clicks, 1);
    // The old UI's late message can act only on its old nominal opening.
    activate = () => {opening.chooseSource(1);}; activate();
    assert.equal(next.view(), 'sources');
  } finally {controls.revoke(); opening.dispose(); next.dispose(); await f.stop();}
});
