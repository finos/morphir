// Private fixed-document adapter. These mirrors account for our requested typed
// backing, logical views and work only. Browser/VM/WebSocket/network allocations
// and physical host/Page/source ownership remain separate obligations.
import {prepareProductJournal, type JournalCharge, type JournalRecord} from './product-fact-journal.ts';
import type {ObservationLimits, ObservationState, ProductFact} from './product-observer.ts';

type Charge = Readonly<{retainedBytes: number; slots: number; byteVisits: number}>;
type Bootstrap = Readonly<{observation: ObservationLimits; records: number; journalBytes: number; frameBytes: number;
  journalCharge: Charge; transportCharge: Charge; credential: string}>;
type Fault = 'bootstrap' | 'funding' | 'journal' | 'attachment' | 'startup' | 'send'
  | 'control-shape' | 'ack' | 'stop' | 'lost-channel' | 'revoked';
type Terminal = Readonly<{kind: 'closed'}> | Readonly<{kind: 'incomplete'; first: Fault}>;
type Phase = 'prepared' | 'connecting' | 'starting' | 'active' | 'draining' | 'end-acknowledged';
type State = Readonly<{kind: Phase}> | Terminal;
type Observer = Readonly<{close(): void; state(): ObservationState}>;
type Starter = (limits: ObservationLimits, receive: (fact: ProductFact) => void) => Promise<Observer>;
const protocol = 'morphir-document-v1', u32 = 0xffff_ffff;
function natural(value: unknown): value is number {return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;}
function checked(value: number): number {if (!natural(value)) throw new Error('Size overflow'); return value;}
function fields(value: unknown, names: readonly string[]): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error('Object required');
  const keys = Object.keys(value);
  if (keys.length !== names.length || keys.some(key => !names.includes(key))) throw new Error('Closed fields required');
  return value as Record<string, unknown>;
}
function count(value: unknown): number {if (!natural(value)) throw new Error('Natural required'); return value;}
function charge(value: unknown): Charge {
  const raw = fields(value, ['retainedBytes', 'slots', 'byteVisits']);
  return Object.freeze({retainedBytes: count(raw.retainedBytes), slots: count(raw.slots), byteVisits: count(raw.byteVisits)});
}
function parse(value: unknown): Bootstrap {
  const raw = fields(value, ['observation', 'records', 'journalBytes', 'frameBytes', 'journalCharge', 'transportCharge', 'credential']);
  const observation = fields(raw.observation, ['owners', 'events']);
  const owners = count(observation.owners), events = count(observation.events);
  const records = count(raw.records), journalBytes = count(raw.journalBytes), frameBytes = count(raw.frameBytes);
  if (checked(records * 8) > u32 || journalBytes > u32 || frameBytes < 16 || frameBytes > u32) throw new Error('Capacity');
  const journalCharge = charge(raw.journalCharge), transportCharge = charge(raw.transportCharge);
  const backing = checked(journalBytes + records * 8);
  if (journalCharge.retainedBytes !== backing || journalCharge.slots !== checked(104 * records + 8) ||
      journalCharge.byteVisits !== checked(backing + records * checked(4218 + 66 * frameBytes) + 8) ||
      transportCharge.retainedBytes !== checked(frameBytes + 16) || transportCharge.slots !== checked(8 + 2 * records) ||
      transportCharge.byteVisits !== checked(frameBytes + 16 + records * checked(2 * frameBytes + 64) + 96)) throw new Error('Mirror');
  const credential = raw.credential;
  if (typeof credential !== 'string' || credential.length !== 43 || !/^[A-Za-z0-9_-]{43}$/.test(credential)) throw new Error('Credential');
  return Object.freeze({observation: Object.freeze({owners, events}), records, journalBytes, frameBytes, journalCharge, transportCharge, credential});
}
class Mirror {
  #remaining: Charge;
  #failed = false;
  constructor(selected: Charge) {this.#remaining = selected;}
  take(retainedBytes: number, slots: number, byteVisits: number): boolean {
    if (this.#failed) return false;
    const remaining = this.#remaining;
    if (![retainedBytes, slots, byteVisits].every(natural) || retainedBytes > remaining.retainedBytes ||
        slots > remaining.slots || byteVisits > remaining.byteVisits) {this.#failed = true; return false;}
    this.#remaining = {retainedBytes: remaining.retainedBytes - retainedBytes, slots: remaining.slots - slots, byteVisits: remaining.byteVisits - byteVisits};
    return true;
  }
}
type Journal = Extract<ReturnType<typeof prepareProductJournal>, {kind: 'prepared'}>['journal'];

export function prepareDocumentChannel(raw: unknown): Readonly<{kind: 'prepared'; channel: DocumentChannel}>
  | Readonly<{kind: 'refused'; first: 'bootstrap' | 'funding'}> {
  let failure: 'bootstrap' | 'funding' = 'bootstrap';
  try {
    const selected = parse(raw), journalMirror = new Mirror(selected.journalCharge), transport = new Mirror(selected.transportCharge);
    failure = 'funding';
    const prepared = prepareProductJournal(selected, (request: JournalCharge) => journalMirror.take(request.backingBytes, request.slots, request.byteVisits));
    if (prepared.kind !== 'prepared' || !transport.take(selected.frameBytes + 16, 4, selected.frameBytes + 16)) return {kind: 'refused', first: failure};
    // Each buffer and each permanent view has been debited before allocation.
    const frame = new Uint8Array(selected.frameBytes), controls = new Uint8Array(16);
    const frameHeader = new DataView(frame.buffer), controlHeader = new DataView(controls.buffer);
    const channel = new DocumentChannel(selected, prepared.journal, transport, frame, controls, frameHeader, controlHeader);
    Object.freeze(channel); return {kind: 'prepared', channel};
  } catch {return {kind: 'refused', first: failure};}
}

class DocumentChannel {
  readonly protocols: readonly string[];
  #state: State = {kind: 'prepared'};
  #socket: WebSocket | undefined;
  #observer: Observer | undefined;
  #inflight: Readonly<{record: JournalRecord; sequence: number; kind: 1 | 2}> | undefined;
  #lastFactAck = 0;
  #pumping = false;
  readonly #closed: Promise<Terminal>;
  readonly #selected: Bootstrap;
  readonly #journal: Journal;
  readonly #transport: Mirror;
  readonly #frame: Uint8Array<ArrayBuffer>;
  readonly #controls: Uint8Array<ArrayBuffer>;
  readonly #frameHeader: DataView;
  readonly #controlHeader: DataView;
  #resolveClosed!: (terminal: Terminal) => void;
  constructor(selected: Bootstrap, journal: Journal, transport: Mirror,
    frame: Uint8Array<ArrayBuffer>, controls: Uint8Array<ArrayBuffer>, frameHeader: DataView, controlHeader: DataView) {
    this.#selected = selected; this.#journal = journal; this.#transport = transport;
    this.#frame = frame; this.#controls = controls; this.#frameHeader = frameHeader; this.#controlHeader = controlHeader;
    this.protocols = Object.freeze([protocol, `morphir-document-key.${selected.credential}`]);
    this.#closed = new Promise(resolve => {this.#resolveClosed = resolve;});
  }
  state(): State {return Object.freeze({...this.#state});}
  whenClosed(): Promise<Terminal> {return this.#closed;}
  #failed(): boolean {return this.#state.kind === 'incomplete' || this.#state.kind === 'closed';}
  #fail(first: Fault): void {
    if (this.#failed()) return;
    this.#state = Object.freeze({kind: 'incomplete', first}); this.#journal.lose();
    // No later DATA/control writes, retries, renewed waits or synthetic Close
    // record. Actual WebSocket close is disposal, not observed completion.
    try {this.#socket?.close();} catch {}
  }
  readonly revoke = (): void => {this.#fail('revoked');};
  readonly #receive = (fact: ProductFact): void => {
    if (this.#failed()) return;
    try {
      this.#journal.receive(fact);
      if (this.#journal.state().kind === 'incomplete') {this.#fail('journal'); return;}
      this.#pump();
    } catch {this.#fail('journal');}
  };
  #pump(): void {
    if (this.#pumping || this.#inflight || this.#failed() || !this.#socket ||
        !['starting', 'active', 'draining'].includes(this.#state.kind)) return;
    this.#pumping = true;
    try {
      const pending = this.#journal.pending();
      if (pending.kind === 'empty') return;
      if (pending.kind === 'incomplete') {this.#fail('journal'); return;}
      if (!this.#transport.take(0, 1, 2 * this.#selected.frameBytes + 16)) {this.#fail('funding'); return;}
      const record = pending.record, copied = record.copyInto(this.#frame);
      if (copied.kind !== 'copied') {this.#fail('journal'); return;}
      const kind = this.#frameHeader.getUint8(1), wide = this.#frameHeader.getBigUint64(4);
      if ((kind !== 1 && kind !== 2) || wide > BigInt(Number.MAX_SAFE_INTEGER)) {this.#fail('journal'); return;}
      this.#inflight = {record, sequence: Number(wide), kind};
      if (this.#socket.readyState !== WebSocket.OPEN || this.#socket.bufferedAmount !== 0) {this.#fail('send'); return;}
      // Exactly one copy and submitted logical view per retained record. ACK
      // must arrive before this reusable backing can be overwritten.
      this.#socket.send(this.#frame.subarray(0, copied.bytes));
    } catch {this.#fail('send');}
    finally {this.#pumping = false;}
  }
  readonly #control = (event: MessageEvent<unknown>): void => {
    if (this.#failed()) return;
    if (!this.#transport.take(0, 1, 48)) {this.#fail('funding'); return;}
    try {
      if (!(event.data instanceof ArrayBuffer) || event.data.byteLength !== 16) {this.#fail('control-shape'); return;}
      this.#controls.set(new Uint8Array(event.data));
      const header = this.#controlHeader, kind = header.getUint8(1), wide = header.getBigUint64(4);
      if (header.getUint8(0) !== 1 || header.getUint16(2) !== 0 || header.getUint32(12) !== 0 ||
          wide > BigInt(Number.MAX_SAFE_INTEGER) || (kind !== 3 && kind !== 4)) {this.#fail('control-shape'); return;}
      const sequence = Number(wide);
      if (kind === 4) {
        if (this.#state.kind !== 'active' || !this.#observer || sequence !== this.#lastFactAck) {this.#fail('stop'); return;}
        this.#state = {kind: 'draining'};
        this.#observer.close(); this.#journal.end(this.#observer.state());
        if (this.#journal.state().kind === 'incomplete') {this.#fail('journal'); return;}
        this.#pump(); return;
      }
      const pending = this.#inflight;
      if (!pending || sequence !== pending.sequence || !this.#journal.advance(pending.record)) {this.#fail('ack'); return;}
      this.#inflight = undefined;
      if (pending.kind === 1) {this.#lastFactAck = sequence; this.#pump();}
      else {this.#state = {kind: 'end-acknowledged'}; this.#socket!.close();}
    } catch {this.#fail('control-shape');}
  };
  async attach(socket: WebSocket, start: Starter): Promise<void> {
    if (this.#state.kind !== 'prepared') throw new Error('Document channel already attached');
    this.#state = {kind: 'connecting'}; this.#socket = socket; socket.binaryType = 'arraybuffer';
    if (socket.readyState !== WebSocket.CONNECTING) {this.#fail('attachment'); throw new Error('Fresh connecting socket required');}
    let rejectOpen!: (cause: unknown) => void;
    const opened = new Promise<void>((resolve, reject) => {
      rejectOpen = reject;
      socket.addEventListener('open', () => resolve(), {once: true});
    });
    socket.addEventListener('message', this.#control);
    socket.addEventListener('error', () => {this.#fail('lost-channel'); rejectOpen(new Error('Document channel failed'));}, {once: true});
    socket.addEventListener('close', event => {
      if (this.#state.kind === 'end-acknowledged' && event.wasClean) {this.#journal.close(); this.#state = Object.freeze({kind: 'closed'});}
      else this.#fail('lost-channel');
      rejectOpen(new Error('Document channel closed'));
      const terminal = this.#state;
      if (terminal.kind === 'closed' || terminal.kind === 'incomplete') this.#resolveClosed(terminal);
      socket.removeEventListener('message', this.#control);
    }, {once: true});
    await opened;
    if (this.#failed() || socket.protocol !== protocol) {this.#fail('attachment'); throw new Error('Document protocol refused');}
    this.#state = {kind: 'starting'};
    try {
      const observer = await start(this.#selected.observation, this.#receive);
      this.#observer = observer;
      if (this.#failed()) return;
      this.#state = {kind: 'active'}; this.#pump();
    } catch (error) {this.#fail('startup'); throw error;}
  }
}
