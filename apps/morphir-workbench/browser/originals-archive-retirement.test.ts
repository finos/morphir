// Actual factory/library lifetime controls. Synthetic bounded inventory input;
// no host, browser-bfcache, frame or campaign completion claim.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createOriginalsArchive, prepareOriginalsArchive, type OriginalArchiveEvent, type OriginalArchiveOperation} from './originals-archive.ts';
import {CheckedArchiveWriter} from './originals-archive-storage.ts';

function operation(): OriginalArchiveOperation {
  const result = createOriginalsArchive({kind: 'connected', entries: 1, rawBytes: 1, archiveNameBytes: 3,
    describe(sink) {sink.file('one', 1);}, copyFiles(sink) {sink.file('one', new Uint8Array([7]));}});
  assert.equal(result.kind, 'prepared');
  if (result.kind !== 'prepared') throw new Error('actual preparation required');
  return result.operation;
}
function retired(events: OriginalArchiveEvent[], owner: OriginalArchiveOperation): void {
  const terminal = events.filter(event => event.kind === 'failed');
  assert.equal(terminal.length, 1, 'one real retirement notification');
  const event = terminal[0]!; assert.equal(event.operation, owner);
  assert.equal(event.kind, 'failed');
  if (event.kind === 'failed') assert.equal(event.failure.kind, 'retired');
}

test('a prepared-retired queued start clears its same caller asynchronously once', async () => {
  const owner = operation(), events: OriginalArchiveEvent[] = [];
  try {
    owner.retire();
    prepareOriginalsArchive(owner, event => events.push(event));
    assert.equal(events.length, 0, 'no inline callback before caller can store its operation');
    await owner.whenSettled(); retired(events, owner);
    assert.equal(events.some(event => event.kind === 'ready'), false);
    owner.retire(); prepareOriginalsArchive(owner, event => events.push(event));
    await owner.whenSettled(); retired(events, owner);
  } finally {owner.retire(); await owner.whenSettled();}
});

test('ready retirement invalidates its actual output and notifies the original callback once after settlement', async () => {
  const owner = operation(), events: OriginalArchiveEvent[] = [];
  try {
    prepareOriginalsArchive(owner, event => events.push(event));
    await owner.whenSettled();
    assert.equal(events.length, 1); const ready = events[0]!; assert.equal(ready.kind, 'ready');
    owner.retire(); assert.equal(events.length, 1, 'retirement notification is deferred');
    await owner.whenSettled(); retired(events, owner);
    if (ready.kind === 'ready') assert.equal(ready.archive.requestDownload().kind, 'retired');
    owner.retire(); await owner.whenSettled(); retired(events, owner);
  } finally {owner.retire(); await owner.whenSettled();}
});

test('retirement cannot notify while the same actual library writer call is still held', {timeout: 15000}, async () => {
  const owner = operation(), events: OriginalArchiveEvent[] = [];
  const write = CheckedArchiveWriter.prototype.writeUint8Array;
  let entered!: () => void, release!: () => void;
  const actualEntry = new Promise<void>(resolve => {entered = resolve;});
  const gate = new Promise<void>(resolve => {release = resolve;}); let held = false;
  CheckedArchiveWriter.prototype.writeUint8Array = async function(chunk) {
    if (!held) {held = true; entered(); await gate;}
    return write.call(this, chunk);
  };
  try {
    prepareOriginalsArchive(owner, event => events.push(event)); await actualEntry;
    owner.retire(); let settled = false;
    const actualSettlement = owner.whenSettled().then(() => {settled = true;});
    await Promise.resolve(); await Promise.resolve();
    assert.equal(settled, false); assert.equal(events.length, 0);
    release(); await actualSettlement; retired(events, owner);
    assert.equal(events.some(event => event.kind === 'ready'), false);
  } finally {release(); owner.retire(); await owner.whenSettled(); CheckedArchiveWriter.prototype.writeUint8Array = write;}
});
