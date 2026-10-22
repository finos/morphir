// Pure checked arithmetic and actual internal sink controls.
// Internal exports are not global bridge APIs, Ready constructors or source grants.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {CheckedArchiveWriter, checkedOutputCapacity, checkedCentralDirectoryCapacity, allocationLength} from './originals-archive-storage.ts';

test('S09 output and central envelopes preserve checked UInt64 arithmetic before numeric allocation lengths', () => {
  assert.equal(checkedOutputCapacity(1n, 2n, 3n), 1291n);
  assert.equal(checkedCentralDirectoryCapacity(1n, 2n), 80n);
  assert.equal(allocationLength(1291n), 1291);
  const max = (1n << 64n) - 1n;
  // Synthetic arithmetic operands deliberately exceed admitted Connected sizes.
  // They isolate each primitive, not a reachable valid-profile overflow.
  assert.throws(() => checkedOutputCapacity(1n, max, 0n), RangeError);
  assert.throws(() => checkedOutputCapacity(1n, 0n, max), RangeError);
  assert.throws(() => checkedCentralDirectoryCapacity(1n, max), RangeError);
  assert.throws(() => checkedCentralDirectoryCapacity(max, 0n), RangeError);
  assert.throws(() => checkedOutputCapacity(-1n, 0n, 0n), RangeError);
  assert.throws(() => allocationLength(BigInt(Number.MAX_SAFE_INTEGER) + 1n), RangeError);
});

test('S10 actual sink rejects an excess chunk before copying it and retains the same first failure', async () => {
  const sink = new CheckedArchiveWriter(4);
  try {
    const chunk = new Uint8Array([1, 2]);
    const actualWrite = sink.writeUint8Array(chunk); chunk.fill(9); await actualWrite;
    await sink.writeUint8Array(new Uint8Array([3, 4]));
    // Unit-only readonly observation of actual internal backing, never a global
    // Ready API. No diagnostic constructor or alternate writer implementation.
    const backing = Reflect.get(sink, 'backing') as Uint8Array;
    assert(backing instanceof Uint8Array);
    let first: unknown;
    try {await sink.writeUint8Array(new Uint8Array([5]));} catch (failure) {first = failure;}
    assert(first instanceof Error); assert.deepEqual([...backing], [1, 2, 3, 4]);
    await assert.rejects(sink.writeUint8Array(new Uint8Array()), failure => failure === first);
    await assert.rejects(sink.getData(), failure => failure === first);
  } finally {sink.dispose();}
});

test('S11 successful internal sink finish preserves actual full backing without a final slice', async () => {
  const sink = new CheckedArchiveWriter(9);
  try {
    await sink.writeUint8Array(new Uint8Array([7, 8]));
    const backing = Reflect.get(sink, 'backing') as Uint8Array;
    const used = await sink.getData();
    assert.equal(used.buffer, backing.buffer); assert.equal(used.byteLength, 2);
    assert.equal(used.buffer.byteLength, 9);
    await assert.rejects(sink.writeUint8Array(new Uint8Array([1])));
  } finally {sink.dispose();}
});
