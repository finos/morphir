// Private maintained application operation. No caller-supplied program, module
// URL, producer event, or observation result crosses this boundary.
import type { Frame, JSHandle, Page } from "playwright-core";

export type InspectionPendingOutcome = Readonly<{kind:
  "inspection-pending" | "originals-only" | "retired" | "failed" | "no-opening" | "replaced"}>;
export type OpeningSettledOutcome = Readonly<{kind:
  "stored" | "retired" | "failed" | "no-opening" | "replaced"}>;
export type CoreEnqueueOutcome = "enqueued" | "ignored";
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
    this.#rejectInvalidated(error);
    return error;
  }

  #release(handle: JSHandle<ConnectedControls>): void {
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

  dispose(): void {
    if (this.#state.kind === "starting") this.#fail(new Error("observed operation disposed during startup"));
    else if (this.#action.kind === "pending") this.#fail(new Error("observed operation disposed while pending"));
    this.#page.off("close", this.#onClose);
    this.#page.off("crash", this.#onCrash);
    this.#page.off("framenavigated", this.#onNavigation);
    if (this.#state.kind !== "faulted") this.#state = { kind: "disposed" };
    this.#releaseControls();
  }
}
