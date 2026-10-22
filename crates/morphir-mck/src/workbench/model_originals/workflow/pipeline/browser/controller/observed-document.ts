// Private maintained application operation. No caller-supplied program, module
// URL, producer event, or observation result crosses this boundary.
import type { Frame, JSHandle, Page } from "playwright-core";

export type InspectionPendingOutcome = Readonly<{kind:
  "inspection-pending" | "originals-only" | "retired" | "failed" | "no-opening" | "replaced"}>;
export type OpeningSettledOutcome = Readonly<{kind:
  "stored" | "retired" | "failed" | "no-opening" | "replaced"}>;
export type CoreEnqueueOutcome = "enqueued" | "ignored";
export type ConnectedSelection = Readonly<{providerId: string; locator: string; projectId: string}>;
export type ConnectedChoiceOutcome = Readonly<{kind: "source-selected" | "project-selected" | "not-ready"
  | "unavailable" | "other-selection" | "retired" | "replaced"}>;
type CapturedOpeningControls = ConnectedControls & Readonly<{
  chooseSource(providerId: string, locator: string): Promise<unknown>;
  chooseProject(projectId: string): Promise<unknown>;
  dispose(): void;
  whenSettled(): Promise<void>;
}>;
type OpeningCaptureControls = Readonly<{whenRegistered(): Promise<CapturedOpeningControls>; cancel(): void}>;
type ConnectedControls = Readonly<{
  awaitInspectionPending(): Promise<unknown>;
  executePendingCore(): unknown;
  awaitOpeningSettled(): Promise<unknown>;
}>;
type ActionState = Readonly<{kind: "idle"}> | Readonly<{kind: "pending"}>;

function boundary<K extends string>(value: unknown, allowed: readonly K[]): Readonly<{kind: K}> {
  if (typeof value !== "object" || value === null || Array.isArray(value)
      || Object.keys(value).length !== 1 || !Object.hasOwn(value, "kind") || !("kind" in value)
      || typeof value.kind !== "string" || !allowed.includes(value.kind as K)) {
    throw new Error("observed boundary outcome shape");
  }
  return Object.freeze({kind: value.kind as K});
}

export class ObservedLaunch {
  readonly #launchUrl: string;
  readonly #documentUrl: string;

  private constructor(launchUrl: string, documentUrl: string) {
    this.#launchUrl = launchUrl;
    this.#documentUrl = documentUrl;
    Object.freeze(this);
  }

  get launchUrl(): string { return this.#launchUrl; }
  get documentUrl(): string { return this.#documentUrl; }

  static parse(input: string): ObservedLaunch {
    // Spelling is checked before URL normalization. Port80 is a valid actual
    // host port even though browsers omit it from the resulting document URL.
    const match = /^http:\/\/127\.0\.0\.1:([1-9][0-9]{0,4})\/launch\?token=([A-Za-z0-9_-]{42}[AEIMQUYcgkosw048])$/.exec(input);
    if (!match || Number(match[1]) > 65535) throw new Error("observed launch shape");
    const parsed = new URL(input);
    return new ObservedLaunch(input, `${parsed.origin}/observed/?mode=connected-originals`);
  }
}

export function parseObservedLaunch(input: string): ObservedLaunch {
  // Canonical spelling prevents URL parser normalization from widening this
  // closed private input. Validation is DATA, never a source or effect grant.
  return ObservedLaunch.parse(input);
}

type State =
  | { readonly kind: "prepared" }
  | { readonly kind: "starting" }
  | { readonly kind: "ready" }
  | { readonly kind: "faulted"; readonly error: unknown }
  | { readonly kind: "disposed" };

export class ObservedDocumentOperation {
  readonly #page: Page;
  readonly #frame: Frame;
  readonly #target: ObservedLaunch;
  readonly #checkClock: () => void;
  readonly #invalidated: Promise<never>;
  readonly #rejectInvalidated: (error: unknown) => void;
  #state: State = { kind: "prepared" };
  #commits = 0;
  #controls: JSHandle<ConnectedControls> | undefined;
  #capture: JSHandle<OpeningCaptureControls> | undefined;
  #opening: JSHandle<CapturedOpeningControls> | undefined;
  #action: ActionState = {kind: "idle"};

  constructor(page: Page, target: ObservedLaunch, checkClock: () => void) {
    this.#page = page;
    this.#frame = page.mainFrame();
    this.#target = target;
    this.#checkClock = checkClock;
    let reject!: (error: unknown) => void;
    this.#invalidated = new Promise<never>((_, rejectPromise) => { reject = rejectPromise; });
    this.#rejectInvalidated = reject;
    // A retained guard can fail after readiness, when there is no outstanding
    // race. The original failure is still returned by assertCurrent().
    void this.#invalidated.catch(() => {});
  }

  #fail(error: unknown): unknown {
    if (this.#state.kind === "faulted") return this.#state.error;
    this.#state = { kind: "faulted", error };
    this.#releaseControls();
    this.#releaseCapture(true);
    this.#releaseOpening();
    this.#rejectInvalidated(error);
    return error;
  }

  #release<T>(handle: JSHandle<T>): void {
    // This requests remote-reference disposal. Physical Page/channel/task joins
    // remain the controller's separate responsibility; no completion is inferred.
    try { void handle.dispose().catch(error => { this.#fail(error); }); }
    catch (error) { this.#fail(error); }
  }

  #releaseControls(): void {
    const handle = this.#controls;
    this.#controls = undefined;
    if (handle) this.#release(handle);
  }

  #disposeOpening(handle: JSHandle<CapturedOpeningControls>): void {
    // Cleanup targets the captured owner, including after channel invalidation.
    // A requested remote dispose is not physical cleanup/join evidence.
    try { void handle.evaluate(actual => actual.dispose()).then(() => this.#release(handle), error => {
      this.#fail(error); this.#release(handle);
    }); }
    catch (error) { this.#fail(error); this.#release(handle); }
  }

  #releaseOpening(): void {
    const handle = this.#opening;
    this.#opening = undefined;
    if (handle) this.#disposeOpening(handle);
  }

  #disposeCapture(handle: JSHandle<OpeningCaptureControls>): void {
    try { void handle.evaluate(actual => actual.cancel()).then(() => this.#release(handle), error => {
      this.#fail(error); this.#release(handle);
    }); }
    catch (error) { this.#fail(error); this.#release(handle); }
  }

  #releaseCapture(cancel: boolean): void {
    const handle = this.#capture;
    this.#capture = undefined;
    if (handle) {
      if (cancel) this.#disposeCapture(handle);
      else this.#release(handle);
    }
  }

  readonly #onClose = (): void => { this.#fail(new Error("observed Page closed")); };
  readonly #onCrash = (): void => { this.#fail(new Error("observed Page crashed")); };
  readonly #onNavigation = (frame: Frame): void => {
    if (frame !== this.#frame) return;
    this.#commits += 1;
    if (this.#commits !== 1 || frame.url() !== this.#target.documentUrl) {
      this.#fail(new Error("observed document replaced"));
    }
  };

  assertCurrent(): void {
    if (this.#state.kind === "faulted") throw this.#state.error;
    if (this.#state.kind === "disposed") throw new Error("observed operation disposed");
    try {
      this.#checkClock();
      if (this.#page.isClosed() || this.#page.mainFrame() !== this.#frame) {
        throw new Error("observed Page unavailable");
      }
      if (this.#commits !== 0 && this.#page.url() !== this.#target.documentUrl) {
        throw new Error("observed document replaced");
      }
    } catch (error) { throw this.#fail(error); }
  }

  async #effect<T>(effect: () => Promise<T>): Promise<T> {
    this.assertCurrent();
    const result = await Promise.race([effect(), this.#invalidated]);
    this.assertCurrent();
    return result;
  }

  async start(): Promise<void> {
    if (this.#state.kind === "faulted") throw this.#state.error;
    if (this.#state.kind !== "prepared") throw new Error("observed operation already started");
    this.#state = { kind: "starting" };
    this.#page.on("close", this.#onClose);
    this.#page.on("crash", this.#onCrash);
    this.#page.on("framenavigated", this.#onNavigation);
    try {
      const response = await this.#effect(() => this.#page.goto(this.#target.launchUrl, {
        waitUntil: "domcontentloaded", timeout: 0,
      }));
      if (!response || response.status() !== 200 || this.#commits !== 1) {
        throw new Error("observed document navigation refused");
      }
      this.assertCurrent();
      const acquiring = this.#page.evaluateHandle(async () => {
        const originalDocument = document;
        const fixedLocation = `${location.origin}/observed/?mode=connected-originals`;
        if (location.href !== fixedLocation) throw new Error("observed document location");
        // This exact maintained callback and fixed module path are not a caller
        // expression API. Awaiting import includes the entry's top-level await.
        const entry = await import(new URL("/observed/observed-document-entry.js", location.origin).href);
        if (document !== originalDocument || location.href !== fixedLocation) {
          throw new Error("observed document replaced during startup");
        }
        const controls: unknown = entry.connectedControls;
        if (typeof controls !== "object" || controls === null || Array.isArray(controls)
            || Object.keys(controls).length !== 3
            || !Object.hasOwn(controls, "awaitInspectionPending")
            || !Object.hasOwn(controls, "executePendingCore")
            || !Object.hasOwn(controls, "awaitOpeningSettled")
            || !("awaitInspectionPending" in controls) || typeof controls.awaitInspectionPending !== "function"
            || !("executePendingCore" in controls) || typeof controls.executePendingCore !== "function"
            || !("awaitOpeningSettled" in controls) || typeof controls.awaitOpeningSettled !== "function") {
          throw new Error("observed fixed controls shape");
        }
        return controls as ConnectedControls;
      });
      let handle: JSHandle<ConnectedControls>;
      try { handle = await this.#effect(() => acquiring); }
      catch (error) {
        // Race losers still own the reference they may eventually create. A
        // late handle is disposed without restoring readiness or source rights.
        void acquiring.then(late => this.#release(late), () => {});
        throw error;
      }
      try {
        this.assertCurrent();
        this.#controls = handle;
        this.#state = { kind: "ready" };
      } catch (error) { this.#release(handle); throw error; }
    } catch (error) { throw this.#fail(error); }
  }

  async #operation<T>(invoke: (handle: JSHandle<ConnectedControls>) => Promise<unknown>,
    decode: (value: unknown) => T): Promise<T> {
    this.assertCurrent();
    if (this.#state.kind !== "ready" || !this.#controls) {
      throw this.#fail(new Error("observed fixed controls unavailable"));
    }
    if (this.#action.kind !== "idle") {
      throw this.#fail(new Error("observed operation already pending"));
    }
    const handle = this.#controls;
    this.#action = {kind: "pending"};
    try { return decode(await this.#effect(() => invoke(handle))); }
    catch (error) { throw this.#fail(error); }
    finally { this.#action = {kind: "idle"}; }
  }

  awaitInspectionPending(): Promise<InspectionPendingOutcome> {
    return this.#operation(handle => handle.evaluate(actual => actual.awaitInspectionPending()),
      value => boundary(value, ["inspection-pending", "originals-only", "retired", "failed", "no-opening", "replaced"]));
  }

  executePendingCore(): Promise<CoreEnqueueOutcome> {
    return this.#operation(handle => handle.evaluate(actual => actual.executePendingCore()), value => {
      if (value !== "enqueued" && value !== "ignored") throw new Error("observed enqueue outcome shape");
      return value;
    });
  }

  awaitOpeningSettled(): Promise<OpeningSettledOutcome> {
    return this.#operation(handle => handle.evaluate(actual => actual.awaitOpeningSettled()),
      value => boundary(value, ["stored", "retired", "failed", "no-opening", "replaced"]));
  }

  beginConnectedOpening(selection: ConnectedSelection): Promise<ConnectedChoiceOutcome> {
    return this.#operation(async () => {
      if (this.#opening || this.#capture) throw new Error("observed opening already captured");
      this.assertCurrent();
      const acquiring = this.#page.evaluateHandle(async () => {
        const entry = await import(new URL("/observed/observed-document-entry.js", location.origin).href);
        const controls: unknown = entry.openingControls;
        if (typeof controls !== "object" || controls === null || Array.isArray(controls)
            || Object.keys(controls).length !== 1 || !Object.hasOwn(controls, "prepareOpeningCapture")
            || !("prepareOpeningCapture" in controls)
            || typeof controls.prepareOpeningCapture !== "function") throw new Error("observed opening controls shape");
        const capture: unknown = controls.prepareOpeningCapture();
        if (typeof capture !== "object" || capture === null || Array.isArray(capture)
            || Object.keys(capture).length !== 2 || !Object.hasOwn(capture, "whenRegistered")
            || !Object.hasOwn(capture, "cancel") || !("whenRegistered" in capture)
            || typeof capture.whenRegistered !== "function" || !("cancel" in capture)
            || typeof capture.cancel !== "function") throw new Error("observed opening capture shape");
        return capture as OpeningCaptureControls;
      });
      let capture: JSHandle<OpeningCaptureControls>;
      try { capture = await this.#effect(() => acquiring); }
      catch (error) { void acquiring.then(late => this.#disposeCapture(late), () => {}); throw error; }
      this.#capture = capture;
      await this.#effect(() => capture.evaluate(() => {
        // Evaluate through the capture's realm, not a new Page singleton. A
        // context replacement cannot redirect this click into a new document.
        const buttons = document.querySelectorAll<HTMLButtonElement>('button[data-model-connect="originals"]');
        const button = buttons[0];
        if (buttons.length !== 1 || !button?.isConnected || button.disabled || button.hidden
            || button.getClientRects().length === 0) throw new Error("observed Connect unavailable");
        button.click();
      }));
      this.assertCurrent();
      const registered = capture.evaluateHandle(async actual => {
        const owner = await actual.whenRegistered();
        if (typeof owner !== "object" || owner === null || Array.isArray(owner)
            || Object.keys(owner).length !== 7
            || !Object.hasOwn(owner, "chooseSource") || !Object.hasOwn(owner, "chooseProject")
            || !Object.hasOwn(owner, "awaitInspectionPending") || !Object.hasOwn(owner, "executePendingCore")
            || !Object.hasOwn(owner, "awaitOpeningSettled") || !Object.hasOwn(owner, "dispose")
            || !Object.hasOwn(owner, "whenSettled")
            || typeof owner.chooseSource !== "function" || typeof owner.chooseProject !== "function"
            || typeof owner.awaitInspectionPending !== "function" || typeof owner.executePendingCore !== "function"
            || typeof owner.awaitOpeningSettled !== "function" || typeof owner.dispose !== "function"
            || typeof owner.whenSettled !== "function") throw new Error("observed captured opening shape");
        return owner;
      });
      let opening: JSHandle<CapturedOpeningControls>;
      try { opening = await this.#effect(() => registered); }
      catch (error) { void registered.then(late => this.#disposeOpening(late), () => {}); throw error; }
      this.#opening = opening;
      this.#releaseCapture(false);
      await this.#waitChoiceDom("source");
      const source = boundary(await this.#effect(() => opening.evaluate((actual, data) =>
        actual.chooseSource(data.providerId, data.locator), selection)),
        ["source-selected", "not-ready", "unavailable", "other-selection", "retired", "replaced"]);
      if (source.kind !== "source-selected") return source;
      await this.#waitChoiceDom("project");
      return this.#effect(() => opening.evaluate((actual, data) => actual.chooseProject(data.projectId), selection));
    }, value => boundary(value,
      ["project-selected", "not-ready", "unavailable", "other-selection", "retired", "replaced"]));
  }

  async #waitChoiceDom(kind: "source" | "project"): Promise<void> {
    // This fixed rendered-phase wait also covers zero-row choices. It performs
    // no identity scan or selection. Exact
    // attributes, nominal index/count, and actual acceptance belong to the
    // captured owner's maintained chooser, never to this presence result.
    this.assertCurrent();
    const waiting = this.#page.waitForFunction(data => document.querySelector(data === "source"
      ? '[data-model-choice-phase="source"]' : '[data-model-choice-phase="project"]') !== null,
      kind, {timeout: 0});
    let ready: Awaited<typeof waiting>;
    try { ready = await this.#effect(() => waiting); }
    catch (error) { void waiting.then(late => this.#release(late), () => {}); throw error; }
    this.#release(ready);
  }

  awaitCapturedInspectionPending(): Promise<InspectionPendingOutcome> {
    return this.#operation(async () => {
      if (!this.#opening) throw new Error("observed captured opening unavailable");
      return this.#opening.evaluate(actual => actual.awaitInspectionPending());
    }, value => boundary(value, ["inspection-pending", "originals-only", "retired", "failed", "no-opening", "replaced"]));
  }

  dispose(): void {
    if (this.#state.kind === "starting") this.#fail(new Error("observed operation disposed during startup"));
    else if (this.#action.kind === "pending") this.#fail(new Error("observed operation disposed while pending"));
    this.#page.off("close", this.#onClose);
    this.#page.off("crash", this.#onCrash);
    this.#page.off("framenavigated", this.#onNavigation);
    if (this.#state.kind !== "faulted") this.#state = { kind: "disposed" };
    this.#releaseControls();
    this.#releaseCapture(true);
    this.#releaseOpening();
  }
}
