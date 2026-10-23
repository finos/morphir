// Internal component only. No document/host/transport grant or startup wiring.
import type {ObservationState, ProductFact} from './product-observer.ts';

export type JournalCharge = Readonly<{backingBytes: number; slots: number; byteVisits: number}>;
export type JournalLimits = Readonly<{records: number; journalBytes: number; frameBytes: number}>;
type Fault = 'limits' | 'size-overflow' | 'allocation' | 'funding' | 'capacity'
  | 'shape' | 'sequence' | 'encoding' | 'end-state' | 'after-end' | 'record' | 'destination' | 'loss' | 'missing-end';
type CopyResult = Readonly<{kind: 'copied'; bytes: number}> | Readonly<{kind: 'refused'; first: Fault}>;
export interface JournalRecord {readonly byteLength: number; copyInto(destination: Uint8Array): CopyResult;}
type Field = readonly [string, string | number | Fields];
type Fields = readonly Field[];
const u32 = 0xffff_ffff;
// Use actual typed backing length, never a subclass/instance getter claim.
const typedArrayByteLength = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype), 'byteLength')!.get as (this: Uint8Array) => number;
function natural(value: number): boolean {return Number.isSafeInteger(value) && value >= 0;}
function checked(value: number): number {if (!natural(value)) throw 'size-overflow'; return value;}
function text(value: unknown): string {if (typeof value !== 'string') throw 'shape'; return value;}
function number(value: unknown): number {if (typeof value !== 'number' || !natural(value)) throw 'shape'; return value;}
function ordinal(value: unknown): number {const result = number(value); if (result === 0) throw 'shape'; return result;}

/** Only closed fixed fields enter this tree, never a caller object or toJSON. */
function snapshot(fact: ProductFact): {sequence: number; fields: Fields} {
  const kind = fact.kind, sequence = number(fact.sequence), actual = fact.actual;
  const workspace = text(actual.workspace), opening = number(actual.opening);
  const owner: Field[] = [['workspace', workspace], ['opening', opening]];
  const fields: Field[] = [['kind', kind], ['actual', owner]];
  switch (kind) {
    case 'model-closed': case 'workspace-closed': break;
    case 'opening-stored': case 'source-selected': case 'project-selected': case 'transfer-verified':
    case 'inventory-adopted': case 'archive-stored': case 'archive-retirement-requested': case 'archive-settled-retired':
    case 'archive-ready': case 'download-will-request': case 'download-result': {
      const opened = actual as Extract<ProductFact, {kind: 'opening-stored'}>['actual'];
      const attempt = text(opened.attempt), openingOrdinal = ordinal(opened.openingOrdinal);
      owner.push(['attempt', attempt], ['openingOrdinal', openingOrdinal]);
      if (kind === 'source-selected' || kind === 'project-selected' || kind === 'transfer-verified') {
        const selected = fact as Extract<ProductFact, {kind: 'source-selected' | 'project-selected' | 'transfer-verified'}>;
        const sessionId = text(selected.sessionId), providerId = text(selected.providerId), locator = text(selected.locator);
        fields.push(['sessionId', sessionId], ['providerId', providerId], ['locator', locator]);
        if (kind !== 'source-selected') fields.push(['projectId', text((selected as {projectId: string}).projectId)]);
      } else if (kind !== 'opening-stored') {
        const inventory = actual as Extract<ProductFact, {kind: 'inventory-adopted'}>['actual'];
        owner.push(['inventoryRevision', text(inventory.inventoryRevision)]);
        if (kind !== 'inventory-adopted') {
          const archive = actual as Extract<ProductFact, {kind: 'archive-stored' | 'archive-retirement-requested' | 'archive-settled-retired'}>['actual'];
          owner.push(['operationOrdinal', ordinal(archive.operationOrdinal)]);
          if (kind === 'archive-ready' || kind === 'download-will-request' || kind === 'download-result') {
            const ready = actual as Extract<ProductFact, {kind: 'archive-ready' | 'download-will-request'}>['actual'];
            owner.push(['readyOrdinal', ordinal(ready.readyOrdinal)]);
            if (kind === 'download-result') {
              const outcome = (fact as Extract<ProductFact, {kind: 'download-result'}>).outcome, outcomeKind = outcome.kind;
              if (outcomeKind === 'raised') fields.push(['outcome', [['kind', outcomeKind]]]);
              else if (outcomeKind === 'returned') {
                const result = outcome.result;
                if (result !== 'download-requested' && result !== 'retired' && result !== 'failed') throw 'shape';
                fields.push(['outcome', [['kind', outcomeKind], ['result', result]]]);
              } else throw 'shape';
            }
          }
        }
      }
      break;
    }
    default: throw 'shape';
  }
  fields.push(['sequence', sequence]); return {sequence, fields};
}

// Bounded scalar writer. No full transient JSON string or UTF8 encoding buffer.
class JsonBytes {
  offset = 0;
  readonly #destination: Uint8Array | undefined;
  readonly #start: number;
  constructor(destination?: Uint8Array, start = 0) {this.#destination = destination; this.#start = start;}
  byte(value: number) {if (this.#destination) this.#destination[this.#start + this.offset] = value; this.offset++;}
  ascii(value: string) {for (let i = 0; i < value.length; i++) this.byte(value.charCodeAt(i));}
  string(value: string) {
    this.byte(34);
    for (let i = 0; i < value.length; i++) {
      const unit = value.charCodeAt(i);
      if (unit === 34 || unit === 92) {this.byte(92); this.byte(unit);}
      else if (unit < 32 || (unit >= 0xd800 && unit <= 0xdfff &&
          !(unit <= 0xdbff && i + 1 < value.length && value.charCodeAt(i + 1) >= 0xdc00 && value.charCodeAt(i + 1) <= 0xdfff))) {
        this.ascii('\\u'); for (let shift = 12; shift >= 0; shift -= 4) this.byte('0123456789abcdef'.charCodeAt((unit >>> shift) & 15));
      } else {
        let point = unit;
        if (unit >= 0xd800 && unit <= 0xdbff) point = 0x10000 + ((unit - 0xd800) << 10) + value.charCodeAt(++i) - 0xdc00;
        if (point < 128) this.byte(point);
        else if (point < 2048) {this.byte(0xc0 | (point >>> 6)); this.byte(0x80 | (point & 63));}
        else if (point < 65536) {this.byte(0xe0 | (point >>> 12)); this.byte(0x80 | ((point >>> 6) & 63)); this.byte(0x80 | (point & 63));}
        else {this.byte(0xf0 | (point >>> 18)); this.byte(0x80 | ((point >>> 12) & 63)); this.byte(0x80 | ((point >>> 6) & 63)); this.byte(0x80 | (point & 63));}
      }
    }
    this.byte(34);
  }
  integer(value: number) {
    let digits = 1, remaining = value; while (remaining >= 10) {remaining = Math.floor(remaining / 10); digits++;}
    if (this.#destination) for (let at = this.#start + this.offset + digits - 1; at >= this.#start + this.offset; at--) {
      this.#destination[at] = 48 + value % 10; value = Math.floor(value / 10);
    }
    this.offset += digits;
  }
  object(fields: Fields) {
    this.byte(123); let first = true;
    for (const [key, value] of fields) {
      if (!first) this.byte(44); first = false; this.string(key); this.byte(58);
      if (typeof value === 'string') this.string(value); else if (typeof value === 'number') this.integer(value); else this.object(value);
    }
    this.byte(125);
  }
}
function units(fields: Fields): number {
  let count = 0;
  for (const [, value] of fields) count = checked(count + (typeof value === 'string' ? value.length : typeof value === 'number' ? 0 : units(value)));
  return count;
}

export function prepareProductJournal(limits: JournalLimits, reserve: (request: JournalCharge) => boolean):
  Readonly<{kind: 'prepared'; journal: ProductJournal}> | Readonly<{kind: 'refused'; first: Fault}> {
  let failure: Fault = 'limits';
  try {
    const records = limits.records, journalBytes = limits.journalBytes, frameBytes = limits.frameBytes;
    if (![records, journalBytes, frameBytes].every(natural)) return {kind: 'refused', first: 'limits'};
    failure = 'size-overflow';
    const metadata = checked(records * 8), backingBytes = checked(metadata + journalBytes);
    if (metadata > u32 || journalBytes > u32 || frameBytes > u32) return {kind: 'refused', first: 'size-overflow'};
    failure = 'funding';
    if (reserve(Object.freeze({backingBytes, slots: records * 2, byteVisits: backingBytes})) !== true) return {kind: 'refused', first: 'funding'};
    failure = 'allocation';
    const bytes = new Uint8Array(journalBytes), descriptors = new Uint32Array(records * 2);
    const journal = new ProductJournal(bytes, descriptors, frameBytes, reserve); Object.freeze(journal);
    return {kind: 'prepared', journal};
  } catch {return {kind: 'refused', first: failure};}
}

/** Cumulative fixed typed backing only; JS object/VM/allocator costs unqualified.
 * Cursor advance is local disposal, never an ACK, accepted fact or actual join.
 * This adapter reserve callback is not an independently issued budget/grant. */
class ProductJournal {
  #used = 0;
  #records = 0;
  #facts = 0;
  #cursor = 0;
  #ended = false;
  #charging = false;
  #first: Fault | undefined;
  #current: JournalRecord | undefined;
  readonly #bytes: Uint8Array;
  readonly #descriptors: Uint32Array;
  readonly #frameBytes: number;
  readonly #reserve: (request: JournalCharge) => boolean;
  constructor(bytes: Uint8Array, descriptors: Uint32Array, frameBytes: number, reserve: (request: JournalCharge) => boolean) {
    this.#bytes = bytes; this.#descriptors = descriptors; this.#frameBytes = frameBytes; this.#reserve = reserve;
  }
  #fail(cause: Fault) {this.#first ??= cause; return this.#first;}
  #charge(backingBytes: number, slots: number, byteVisits: number): boolean {
    if (this.#first) return false;
    if (this.#charging) {this.#fail('funding'); return false;}
    this.#charging = true; let accepted = false;
    try {accepted = this.#reserve(Object.freeze({backingBytes, slots, byteVisits})) === true;} catch {}
    finally {this.#charging = false;}
    if (this.#first) return false;
    if (accepted) return true;
    this.#fail('funding'); return false;
  }
  readonly receive = (fact: ProductFact): void => {
    if (this.#first) return; if (this.#ended) {this.#fail('after-end'); return;}
    if (this.#records >= this.#descriptors.length / 2) {this.#fail('capacity'); return;}
    // Fixed maximum schema snapshot metadata and property reads, before getters.
    if (!this.#charge(0, 96, 96)) return;
    try {
      const captured = snapshot(fact);
      if (captured.sequence !== checked(this.#facts + 1)) {this.#fail('sequence'); return;}
      if (this.#append(1, captured.sequence, captured.fields)) this.#facts++;
    } catch (cause) {this.#fail(cause === 'shape' ? 'shape' : cause === 'size-overflow' ? 'size-overflow' : 'encoding');}
  };
  readonly end = (actual: ObservationState): void => {
    if (this.#first) return; if (this.#ended) {this.#fail('after-end'); return;}
    if (!this.#charge(0, 8, 8)) return;
    try {
      const kind = actual.kind;
      if (kind !== 'closed') {this.#fail('end-state'); return;}
      if (this.#append(2, checked(this.#facts + 1), [['lastSequence', this.#facts], ['observer', [['kind', kind]]]])) this.#ended = true;
    } catch {this.#fail('encoding');}
  };
  #append(kind: number, sequence: number, fields: Fields): boolean {
    if (this.#first) return false;
    if (this.#ended) {this.#fail('after-end'); return false;}
    if (this.#records >= this.#descriptors.length / 2) {this.#fail('capacity'); return false;}
    const count = units(fields), upper = checked(512 + checked(count * 6));
    // Fixed schema syntax/numbers fit512; each variable UTF16 unit needs <=6.
    // Pay both measurement and write visits before either content scan.
    // Conservative logical work: UTF16 lookahead/escape reads, fixed syntax,
    // count+write passes,16 header writes and8 descriptor bytes. Not VM/RSS.
    if (!this.#charge(0, 4, checked(checked(upper * 8) + checked(count * 16) + 24))) return false;
    const measure = new JsonBytes(); measure.object(fields);
    if (measure.offset > upper) {this.#fail('size-overflow'); return false;}
    const length = checked(16 + measure.offset);
    if (length > this.#frameBytes || length > this.#bytes.length - this.#used) {this.#fail('capacity'); return false;}
    if (this.#first) return false;
    const offset = this.#used, header = new DataView(this.#bytes.buffer);
    header.setUint8(offset, 1); header.setUint8(offset + 1, kind); header.setUint16(offset + 2, 0);
    header.setUint32(offset + 4, Math.floor(sequence / 0x1_0000_0000)); header.setUint32(offset + 8, sequence % 0x1_0000_0000);
    header.setUint32(offset + 12, measure.offset);
    new JsonBytes(this.#bytes, offset + 16).object(fields);
    this.#descriptors[this.#records * 2] = offset; this.#descriptors[this.#records * 2 + 1] = length;
    this.#used += length; this.#records++; return true;
  }
  pending(): Readonly<{kind: 'record'; record: JournalRecord}> | Readonly<{kind: 'empty'}> | Readonly<{kind: 'incomplete'; first: Fault}> {
    if (this.#first) return {kind: 'incomplete', first: this.#first};
    if (this.#current) return {kind: 'record', record: this.#current};
    if (this.#cursor === this.#records) return {kind: 'empty'};
    if (!this.#charge(0, 2, 2)) return {kind: 'incomplete', first: this.#first!};
    const offset = this.#descriptors[this.#cursor * 2]!, byteLength = this.#descriptors[this.#cursor * 2 + 1]!;
    const record: JournalRecord = Object.freeze({byteLength, copyInto: (destination: Uint8Array): CopyResult => {
      if (this.#first) return {kind: 'refused', first: this.#first};
      if (this.#current !== record) return {kind: 'refused', first: this.#fail('record')};
      try {
        if (!(destination instanceof Uint8Array) || typedArrayByteLength.call(destination) < byteLength) return {kind: 'refused', first: this.#fail('destination')};
        if (!this.#charge(0, 0, byteLength * 2)) return {kind: 'refused', first: this.#first!};
        if (this.#current !== record) return {kind: 'refused', first: this.#fail('record')};
        if (typedArrayByteLength.call(destination) < byteLength) return {kind: 'refused', first: this.#fail('destination')};
        for (let i = 0; i < byteLength; i++) destination[i] = this.#bytes[offset + i]!;
        return {kind: 'copied', bytes: byteLength};
      } catch {return {kind: 'refused', first: this.#fail('destination')};}
    }});
    this.#current = record; return {kind: 'record', record};
  }
  advance(record: JournalRecord): boolean {
    if (this.#first) return false;
    if (!this.#current || record !== this.#current) {this.#fail('record'); return false;}
    this.#current = undefined; this.#cursor++; return true;
  }
  lose(): void {this.#fail('loss');}
  close(): void {if (!this.#ended) this.#fail('missing-end');}
  state() {
    return this.#first ? {kind: 'incomplete' as const, first: this.#first, records: this.#records, facts: this.#facts}
      : {kind: this.#ended ? 'ended' as const : 'open' as const, records: this.#records, facts: this.#facts};
  }
}
