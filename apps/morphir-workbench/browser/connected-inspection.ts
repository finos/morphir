import type {ConnectedModelOpening, PendingOriginalInspection, ConnectedChoiceOutcome} from './connected-originals.ts';
import {clickConnectedChoice, type ChoiceDocument, type ConnectedChoice} from './connected-choice-dom.ts';

export type ConnectedBoundary = 'inspection-pending' | 'opening-settled';
export type ConnectedBoundaryOutcome = Readonly<{kind:
  'inspection-pending' | 'originals-only' | 'stored' | 'retired' | 'failed' | 'no-opening' | 'replaced'}>;
export type ConnectedOpeningCapture = OwnedOpeningCapture;
export type CapturedConnectedOpening = OwnedCapturedOpening;
const owned = Symbol('observed-connected-opening');
type BoundaryObservation = Readonly<{kind: 'awaiting'}>
  | Readonly<{kind: 'returned'; value: ConnectedBoundaryOutcome}>
  | Readonly<{kind: 'raised'; error: unknown}>;
type PendingBoundary = Readonly<{boundary: ConnectedBoundary; resolve: (value: ConnectedBoundaryOutcome) => void;
  reject: (error: unknown) => void}>;

/** A captured application owner. It never follows the page's next opening.
 * These are logical boundaries; disposal and whenSettled do not prove joins. */
class OwnedCapturedOpening {
  readonly #opening: ConnectedModelOpening;
  readonly #choiceDocument: () => ChoiceDocument;
  #choice: 'idle' | 'pending' = 'idle';
  #state: 'current' | 'retired' | 'replaced' = 'current';
  #inspection: BoundaryObservation = {kind: 'awaiting'};
  #settlement: BoundaryObservation = {kind: 'awaiting'};
  #pending: PendingBoundary | undefined;
  constructor(token: typeof owned, opening: ConnectedModelOpening, choiceDocument: () => ChoiceDocument) {
    if (token !== owned) throw new Error('Use the observed opening capture.');
    this.#opening = opening;
    this.#choiceDocument = choiceDocument;
    // Subscribe once per actual boundary, rather than retaining another
    // unresolved invalidation listener on every successful read.
    void opening.whenInspectionPending().then(value => this.#observe('inspection-pending', {kind: 'returned', value: {kind: value.kind}}),
      error => this.#observe('inspection-pending', {kind: 'raised', error}));
    void opening.whenOpeningSettled().then(value => this.#observe('opening-settled', {kind: 'returned', value}),
      error => this.#observe('opening-settled', {kind: 'raised', error}));
    Object.freeze(this);
  }
  invalidate(token: typeof owned, reason: 'retired' | 'replaced'): void {
    if (token !== owned) throw new Error('Missing opening owner.');
    if (this.#state === 'replaced' || this.#state === reason) return;
    this.#state = reason;
    this.#opening.cancelObservedChoice(reason);
    if (reason === 'replaced') this.#flush();
    // A stored/failed boundary resolved immediately before normal UI cleanup
    // gets its already queued observation first. This is one microtask, with
    // no new timer, deadline or renewed application operation.
    else queueMicrotask(() => this.#flush(true));
  }
  executePendingCore(): 'enqueued' | 'ignored' {
    if (this.#choice !== 'idle') throw new Error('Captured opening already outstanding.');
    return this.#state === 'current' ? this.#opening.currentPendingInspection?.executePendingCore() ?? 'ignored' : 'ignored';
  }
  chooseSource(providerId: string, locator: string): Promise<ConnectedChoiceOutcome> {
    return this.#choose({kind: 'source', providerId, locator});
  }
  chooseProject(projectId: string): Promise<ConnectedChoiceOutcome> {
    return this.#choose({kind: 'project', projectId});
  }
  async #choose(choice: ConnectedChoice): Promise<ConnectedChoiceOutcome> {
    if (this.#state !== 'current') return {kind: this.#state};
    if (this.#pending || this.#choice !== 'idle') throw new Error('Captured opening already outstanding.');
    this.#choice = 'pending';
    const activate = (index: number, count: number): 'clicked' | 'unavailable' => {
      // Check and click in the SAME synchronous turn. A later queued UI message
      // still has to pass the application's actual attempt/owner checks.
      if (this.#state !== 'current') return 'unavailable';
      return clickConnectedChoice(this.#choiceDocument(), choice, index, count);
    };
    try {
      return await (choice.kind === 'source'
        ? this.#opening.observeSourceChoice(choice.providerId, choice.locator, activate)
        : this.#opening.observeProjectChoice(choice.projectId, activate));
    } finally {this.#choice = 'idle';}
  }
  #observe(boundary: ConnectedBoundary, observed: BoundaryObservation): void {
    if (boundary === 'inspection-pending') this.#inspection = observed; else this.#settlement = observed;
    this.#flush();
  }
  #observed(boundary: ConnectedBoundary): BoundaryObservation {
    return boundary === 'inspection-pending' ? this.#inspection : this.#settlement;
  }
  #flush(retiredFallback = false): void {
    const pending = this.#pending;
    if (!pending) return;
    const observed = this.#observed(pending.boundary);
    if (this.#state === 'replaced') {this.#pending = undefined; pending.resolve(Object.freeze({kind: 'replaced'}));}
    else if (observed.kind === 'returned') {this.#pending = undefined; pending.resolve(Object.freeze({kind: observed.value.kind}));}
    else if (observed.kind === 'raised') {this.#pending = undefined; pending.reject(observed.error);}
    else if (this.#state === 'retired' && retiredFallback) {this.#pending = undefined; pending.resolve(Object.freeze({kind: 'retired'}));}
  }
  async awaitBoundary(boundary: ConnectedBoundary): Promise<ConnectedBoundaryOutcome> {
    if (boundary !== 'inspection-pending' && boundary !== 'opening-settled') throw new Error('Invalid connected boundary.');
    if (this.#state === 'replaced') return Object.freeze({kind: 'replaced'});
    if (this.#pending || this.#choice !== 'idle') throw new Error('Captured opening already outstanding.');
    return new Promise((resolve, reject) => {
      this.#pending = {boundary, resolve, reject}; this.#flush();
      if (this.#state === 'retired') queueMicrotask(() => this.#flush(true));
    });
  }
  dispose(): void {this.#opening.dispose();}
  whenSettled(): Promise<void> {return this.#opening.whenSettled();}
}

type CaptureState = Readonly<{kind: 'armed'}> | Readonly<{kind: 'registered'; opening: OwnedCapturedOpening}>
  | Readonly<{kind: 'cancelled'}>;
class OwnedOpeningCapture {
  #state: CaptureState = {kind: 'armed'};
  readonly #registered: Promise<CapturedConnectedOpening>;
  readonly #cancelled: () => void;
  #resolve!: (opening: CapturedConnectedOpening) => void;
  #reject!: (error: unknown) => void;
  constructor(token: typeof owned, cancelled: () => void) {
    if (token !== owned) throw new Error('Use the observed opening capture.');
    this.#cancelled = cancelled;
    this.#registered = new Promise((resolve, reject) => {this.#resolve = resolve; this.#reject = reject;});
    void this.#registered.catch(() => {});
    Object.freeze(this);
  }
  whenRegistered(): Promise<CapturedConnectedOpening> {return this.#registered;}
  register(token: typeof owned, opening: OwnedCapturedOpening): void {
    if (token !== owned || this.#state.kind !== 'armed') throw new Error('Opening capture is not armed.');
    this.#state = {kind: 'registered', opening}; this.#resolve(opening);
  }
  close(token: typeof owned): void {
    if (token !== owned) throw new Error('Missing opening owner.');
    if (this.#state.kind !== 'armed') return;
    this.#state = {kind: 'cancelled'}; this.#reject(new Error('Observed opening controls closed.'));
  }
  cancel(): void {
    const previous = this.#state;
    if (previous.kind === 'cancelled') return;
    this.#state = {kind: 'cancelled'};
    this.#cancelled();
    if (previous.kind === 'registered') previous.opening.dispose();
    else this.#reject(new Error('Opening capture cancelled.'));
  }
}

/** One page's actual opening. Fixed driver controls accept no source, request,
 * module, expected result or producer-selected case identity. */
export class ConnectedInspectionControls {
  readonly #choiceDocument: () => ChoiceDocument;
  #mode: 'ordinary' | 'observed' | 'closed' = 'ordinary';
  #opening: ConnectedModelOpening | undefined;
  #lastRegistered: ConnectedModelOpening | undefined;
  #capture: OwnedOpeningCapture | undefined;
  #pin: OwnedCapturedOpening | undefined;
  constructor(choiceDocument: () => ChoiceDocument = () => document) {this.#choiceDocument = choiceDocument;}
  prepareObserved(): void {
    if (this.#opening || this.#mode === 'closed') throw new Error('Prepare observed inspection before opening a model.');
    this.#mode = 'observed';
  }
  register(opening: ConnectedModelOpening): void {
    if (this.#mode === 'closed') {opening.dispose(); return;}
    if (this.#lastRegistered === opening) return;
    this.#pin?.invalidate(owned, 'replaced'); this.#pin = undefined;
    this.#opening = opening; this.#lastRegistered = opening;
    const capture = this.#capture;
    this.#capture = undefined;
    if (capture) {
      const pin = new OwnedCapturedOpening(owned, opening, this.#choiceDocument);
      this.#pin = pin; capture.register(owned, pin);
    }
  }
  prepareOpeningCapture(): ConnectedOpeningCapture {
    if (this.#mode !== 'observed') throw new Error('Prepare an observed opening capture on the active page.');
    if (this.#capture) throw new Error('Opening capture already armed.');
    const capture = new OwnedOpeningCapture(owned, () => {if (this.#capture === capture) this.#capture = undefined;});
    this.#capture = capture;
    return capture;
  }
  revoke(): void {
    const opening = this.#opening;
    this.#mode = 'closed'; this.#opening = undefined;
    this.#capture?.close(owned); this.#capture = undefined;
    this.#pin?.invalidate(owned, 'retired');
    opening?.dispose();
  }
  unregister(opening: ConnectedModelOpening): void {
    if (this.#opening !== opening) return;
    this.#opening = undefined; this.#pin?.invalidate(owned, 'retired');
  }
  hold(stage: PendingOriginalInspection, enqueue: () => void, cancel: () => void): 'held' | 'ignored' {
    const opening = this.#opening;
    if (!opening || opening.holdInspection(stage, enqueue, cancel) !== 'held') return 'ignored';
    if (this.#mode === 'ordinary') opening.currentPendingInspection?.executePendingCore();
    return 'held';
  }
  executePendingCore(): 'enqueued' | 'ignored' {
    return this.#opening?.currentPendingInspection?.executePendingCore() ?? 'ignored';
  }
  async awaitBoundary(boundary: ConnectedBoundary): Promise<ConnectedBoundaryOutcome> {
    if (boundary !== 'inspection-pending' && boundary !== 'opening-settled') throw new Error('Invalid connected boundary.');
    const opening = this.#opening;
    if (!opening) return Object.freeze({kind: this.#mode === 'closed' ? 'retired' : 'no-opening'});
    const outcome = await (boundary === 'inspection-pending' ? opening.whenInspectionPending() : opening.whenOpeningSettled());
    return Object.freeze({kind: this.#opening === opening ? outcome.kind : 'replaced'});
  }
}

// Build externalizes this one module for both ordinary bootstrap and the fixed
// observed entry, so holding and executing never consult different instances.
export const connectedInspection = new ConnectedInspectionControls();
