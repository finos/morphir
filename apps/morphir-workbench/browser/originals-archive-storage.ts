import {Writer} from '@zip.js/zip.js';

const maxU64 = (1n << 64n) - 1n;

function u64(value: bigint): bigint {
  if (typeof value !== 'bigint' || value < 0n || value > maxU64) {
    throw new RangeError('Archive size is outside UInt64.');
  }
  return value;
}

function add(left: bigint, right: bigint): bigint {
  return u64(u64(left) + u64(right));
}

function multiply(left: bigint, right: bigint): bigint {
  return u64(u64(left) * u64(right));
}

/** Derived capacities only; profile admission belongs to the inventory adapter. */
export function checkedOutputCapacity(entries: bigint, nameBytes: bigint, rawBytes: bigint): bigint {
  return add(add(add(u64(rawBytes), multiply(4n, nameBytes)), multiply(256n, entries)), 1024n);
}

export function checkedCentralDirectoryCapacity(entries: bigint, nameBytes: bigint): bigint {
  return add(u64(nameBytes), multiply(78n, entries));
}

export function allocationLength(value: bigint): number {
  if (u64(value) > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RangeError('Archive allocation length cannot be represented exactly.');
  }
  return Number(value);
}

type WriterFailureKind = 'capacity' | 'retired' | 'sealed' | 'disposed';

class ArchiveWriterFailure extends Error {
  constructor(readonly kind: WriterFailureKind) {
    super({
      capacity: 'Archive output exceeds its checked capacity.',
      retired: 'Archive encoding was retired.',
      sealed: 'Archive output is already sealed.',
      disposed: 'Archive output was disposed.',
    }[kind]);
    this.name = 'ArchiveWriterFailure';
  }
}

type WriterState =
  | {kind: 'open'; offset: number}
  | {kind: 'sealed'}
  | {kind: 'faulted'; first: Error}
  | {kind: 'disposed'; first: Error};

/** One owned backing. Library input allocation happens before this sink. */
export class CheckedArchiveWriter extends Writer<Uint8Array<ArrayBuffer>> {
  private backing: Uint8Array<ArrayBuffer> | undefined;
  private state: WriterState = {kind: 'open', offset: 0};

  constructor(capacity: number) {
    super();
    if (!Number.isSafeInteger(capacity) || capacity < 0) {
      throw new RangeError('Archive capacity must be an exact natural number.');
    }
    this.backing = new Uint8Array(capacity);
    if (this.backing.byteOffset !== 0 || this.backing.byteLength !== capacity ||
        this.backing.buffer.byteLength !== capacity) {
      throw new RangeError('Archive backing does not match its checked capacity.');
    }
  }

  private fail(kind: WriterFailureKind): Error {
    if (this.state.kind === 'faulted' || this.state.kind === 'disposed') return this.state.first;
    const first = new ArchiveWriterFailure(kind);
    this.state = {kind: 'faulted', first};
    return first;
  }

  override async writeUint8Array(chunk: Uint8Array): Promise<void> {
    if (this.state.kind !== 'open') throw this.fail('sealed');
    const backing = this.backing;
    if (!backing) throw this.fail('disposed');
    const offset = this.state.offset;
    if (chunk.byteLength > backing.byteLength - offset) throw this.fail('capacity');
    // The subtraction check precedes set; no incoming chunk is retained.
    backing.set(chunk, offset);
    this.state = {kind: 'open', offset: offset + chunk.byteLength};
  }

  override async getData(): Promise<Uint8Array<ArrayBuffer>> {
    if (this.state.kind !== 'open') throw this.fail('sealed');
    const backing = this.backing;
    if (!backing) throw this.fail('disposed');
    const used = backing.subarray(0, this.state.offset);
    this.state = {kind: 'sealed'};
    return used;
  }

  retire(): void {
    this.fail('retired');
  }

  dispose(): void {
    const first = this.fail('disposed');
    this.backing = undefined;
    this.state = {kind: 'disposed', first};
  }
}
