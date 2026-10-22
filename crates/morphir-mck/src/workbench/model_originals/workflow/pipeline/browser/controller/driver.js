// crates/morphir-mck/src/workbench/model_originals/workflow/pipeline/browser/controller/driver.ts
import { pathToFileURL } from "node:url";

// crates/morphir-mck/src/workbench/model_originals/workflow/pipeline/browser/controller/driver-clock.ts
var U64_MAX = 2n ** 64n - 1n;
function integer(text) {
  if (text === undefined || !/^(0|[1-9][0-9]{0,19})$/.test(text))
    throw new Error("clock integer shape");
  const value = BigInt(text);
  if (value > U64_MAX)
    throw new Error("clock integer range");
  return value;
}
function parseClock(at, end, numer, denom) {
  const calibrated = integer(at);
  const fixedEnd = integer(end);
  const numerator = integer(numer);
  const denominator = integer(denom);
  if (numerator === 0n || denominator === 0n || numerator > 4294967295n || denominator > 4294967295n)
    throw new Error("clock ratio");
  const lastQualified = U64_MAX / numerator * numerator / denominator;
  if (calibrated >= fixedEnd || fixedEnd > lastQualified)
    throw new Error("clock export range");
  return { calibrated, end: fixedEnd, lastQualified };
}
function acceptSample(clock, previous, current) {
  if (current < clock.calibrated || current > clock.lastQualified)
    throw new Error("outside calibrated range");
  if (current < previous)
    throw new Error("clock decreased");
  if (current >= clock.end)
    throw new Error("original end elapsed");
  return current;
}

// crates/morphir-mck/src/workbench/model_originals/workflow/pipeline/browser/controller/observed-document.ts
function boundary(value, allowed) {
  if (typeof value !== "object" || value === null || Array.isArray(value) || Object.keys(value).length !== 1 || !Object.hasOwn(value, "kind") || !("kind" in value) || typeof value.kind !== "string" || !allowed.includes(value.kind)) {
    throw new Error("observed boundary outcome shape");
  }
  return Object.freeze({ kind: value.kind });
}

class ObservedLaunch {
  #launchUrl;
  #documentUrl;
  constructor(launchUrl, documentUrl) {
    this.#launchUrl = launchUrl;
    this.#documentUrl = documentUrl;
    Object.freeze(this);
  }
  get launchUrl() {
    return this.#launchUrl;
  }
  get documentUrl() {
    return this.#documentUrl;
  }
  static parse(input) {
    const match = /^http:\/\/127\.0\.0\.1:([1-9][0-9]{0,4})\/launch\?token=([A-Za-z0-9_-]{42}[AEIMQUYcgkosw048])$/.exec(input);
    if (!match || Number(match[1]) > 65535)
      throw new Error("observed launch shape");
    const parsed = new URL(input);
    return new ObservedLaunch(input, `${parsed.origin}/observed/?mode=connected-originals`);
  }
}
function parseObservedLaunch(input) {
  return ObservedLaunch.parse(input);
}

class ObservedDocumentOperation {
  #page;
  #frame;
  #target;
  #checkClock;
  #invalidated;
  #rejectInvalidated;
  #state = { kind: "prepared" };
  #commits = 0;
  #controls;
  #action = { kind: "idle" };
  constructor(page, target, checkClock) {
    this.#page = page;
    this.#frame = page.mainFrame();
    this.#target = target;
    this.#checkClock = checkClock;
    let reject;
    this.#invalidated = new Promise((_, rejectPromise) => {
      reject = rejectPromise;
    });
    this.#rejectInvalidated = reject;
    this.#invalidated.catch(() => {});
  }
  #fail(error) {
    if (this.#state.kind === "faulted")
      return this.#state.error;
    this.#state = { kind: "faulted", error };
    this.#releaseControls();
    this.#rejectInvalidated(error);
    return error;
  }
  #release(handle) {
    try {
      handle.dispose().catch((error) => {
        this.#fail(error);
      });
    } catch (error) {
      this.#fail(error);
    }
  }
  #releaseControls() {
    const handle = this.#controls;
    this.#controls = undefined;
    if (handle)
      this.#release(handle);
  }
  #onClose = () => {
    this.#fail(new Error("observed Page closed"));
  };
  #onCrash = () => {
    this.#fail(new Error("observed Page crashed"));
  };
  #onNavigation = (frame) => {
    if (frame !== this.#frame)
      return;
    this.#commits += 1;
    if (this.#commits !== 1 || frame.url() !== this.#target.documentUrl) {
      this.#fail(new Error("observed document replaced"));
    }
  };
  assertCurrent() {
    if (this.#state.kind === "faulted")
      throw this.#state.error;
    if (this.#state.kind === "disposed")
      throw new Error("observed operation disposed");
    try {
      this.#checkClock();
      if (this.#page.isClosed() || this.#page.mainFrame() !== this.#frame) {
        throw new Error("observed Page unavailable");
      }
      if (this.#commits !== 0 && this.#page.url() !== this.#target.documentUrl) {
        throw new Error("observed document replaced");
      }
    } catch (error) {
      throw this.#fail(error);
    }
  }
  async#effect(effect) {
    this.assertCurrent();
    const result = await Promise.race([effect(), this.#invalidated]);
    this.assertCurrent();
    return result;
  }
  async start() {
    if (this.#state.kind === "faulted")
      throw this.#state.error;
    if (this.#state.kind !== "prepared")
      throw new Error("observed operation already started");
    this.#state = { kind: "starting" };
    this.#page.on("close", this.#onClose);
    this.#page.on("crash", this.#onCrash);
    this.#page.on("framenavigated", this.#onNavigation);
    try {
      const response = await this.#effect(() => this.#page.goto(this.#target.launchUrl, {
        waitUntil: "domcontentloaded",
        timeout: 0
      }));
      if (!response || response.status() !== 200 || this.#commits !== 1) {
        throw new Error("observed document navigation refused");
      }
      this.assertCurrent();
      const acquiring = this.#page.evaluateHandle(async () => {
        const originalDocument = document;
        const fixedLocation = `${location.origin}/observed/?mode=connected-originals`;
        if (location.href !== fixedLocation)
          throw new Error("observed document location");
        const entry = await import(new URL("/observed/observed-document-entry.js", location.origin).href);
        if (document !== originalDocument || location.href !== fixedLocation) {
          throw new Error("observed document replaced during startup");
        }
        const controls = entry.connectedControls;
        if (typeof controls !== "object" || controls === null || Array.isArray(controls) || Object.keys(controls).length !== 3 || !Object.hasOwn(controls, "awaitInspectionPending") || !Object.hasOwn(controls, "executePendingCore") || !Object.hasOwn(controls, "awaitOpeningSettled") || !("awaitInspectionPending" in controls) || typeof controls.awaitInspectionPending !== "function" || !("executePendingCore" in controls) || typeof controls.executePendingCore !== "function" || !("awaitOpeningSettled" in controls) || typeof controls.awaitOpeningSettled !== "function") {
          throw new Error("observed fixed controls shape");
        }
        return controls;
      });
      let handle;
      try {
        handle = await this.#effect(() => acquiring);
      } catch (error) {
        acquiring.then((late) => this.#release(late), () => {});
        throw error;
      }
      try {
        this.assertCurrent();
        this.#controls = handle;
        this.#state = { kind: "ready" };
      } catch (error) {
        this.#release(handle);
        throw error;
      }
    } catch (error) {
      throw this.#fail(error);
    }
  }
  async#operation(invoke, decode) {
    this.assertCurrent();
    if (this.#state.kind !== "ready" || !this.#controls) {
      throw this.#fail(new Error("observed fixed controls unavailable"));
    }
    if (this.#action.kind !== "idle") {
      throw this.#fail(new Error("observed operation already pending"));
    }
    const handle = this.#controls;
    this.#action = { kind: "pending" };
    try {
      return decode(await this.#effect(() => invoke(handle)));
    } catch (error) {
      throw this.#fail(error);
    } finally {
      this.#action = { kind: "idle" };
    }
  }
  awaitInspectionPending() {
    return this.#operation((handle) => handle.evaluate((actual) => actual.awaitInspectionPending()), (value) => boundary(value, ["inspection-pending", "originals-only", "retired", "failed", "no-opening", "replaced"]));
  }
  executePendingCore() {
    return this.#operation((handle) => handle.evaluate((actual) => actual.executePendingCore()), (value) => {
      if (value !== "enqueued" && value !== "ignored")
        throw new Error("observed enqueue outcome shape");
      return value;
    });
  }
  awaitOpeningSettled() {
    return this.#operation((handle) => handle.evaluate((actual) => actual.awaitOpeningSettled()), (value) => boundary(value, ["stored", "retired", "failed", "no-opening", "replaced"]));
  }
  dispose() {
    if (this.#state.kind === "starting")
      this.#fail(new Error("observed operation disposed during startup"));
    else if (this.#action.kind === "pending")
      this.#fail(new Error("observed operation disposed while pending"));
    this.#page.off("close", this.#onClose);
    this.#page.off("crash", this.#onCrash);
    this.#page.off("framenavigated", this.#onNavigation);
    if (this.#state.kind !== "faulted")
      this.#state = { kind: "disposed" };
    this.#releaseControls();
  }
}

// crates/morphir-mck/src/workbench/model_originals/workflow/pipeline/browser/controller/driver.ts
var [entry, endpoint, artifacts, atText, endText, numerText, denomText, variant, launchUrl] = process.argv.slice(2);
if (process.argv.length !== 9 && process.argv.length !== 11 || !entry || !endpoint || !artifacts) {
  throw new Error("fixed driver arguments required");
}
var observedTarget = process.argv.length === 11 ? variant === "observed-workbench" && launchUrl ? parseObservedLaunch(launchUrl) : (() => {
  throw new Error("fixed driver launch variant");
})() : undefined;
var clock = parseClock(atText, endText, numerText, denomText);
var previous = clock.calibrated;
function beforeEffect() {
  previous = acceptSample(clock, previous, process.hrtime.bigint());
}
var browser;
var context;
var page;
var observedDocument;
var first = { kind: "none" };
function retainFirst(error) {
  if (first.kind === "none")
    first = { kind: "failed", error };
}
function retainedFailure() {
  return first;
}
async function cleanup() {
  observedDocument?.dispose();
  for (const release of [
    async () => {
      if (page) {
        const actual = page;
        page = undefined;
        await actual.close();
      }
    },
    async () => {
      if (context) {
        const actual = context;
        context = undefined;
        await actual.close();
      }
    },
    async () => {
      if (browser) {
        const actual = browser;
        browser = undefined;
        await actual.close();
      }
    }
  ]) {
    try {
      await release();
    } catch (error) {
      retainFirst(error);
    }
  }
}
async function main() {
  const { chromium } = await import(pathToFileURL(entry).href);
  beforeEffect();
  browser = await chromium.connectOverCDP(endpoint, { artifactsDir: artifacts, isLocal: true });
  beforeEffect();
  process.stdout.write(`attached
`);
  let sequence = 1;
  let pending = "";
  for await (const chunk of process.stdin) {
    const bytes = chunk;
    if (bytes.length + pending.length > 8 || bytes.some((byte) => byte > 127))
      throw new Error("command shape");
    pending += bytes.toString("ascii");
    if (!pending.endsWith(`
`))
      continue;
    if (sequence === 1 && pending === (observedTarget ? `1 start
` : `1 page
`)) {
      beforeEffect();
      context = await browser.newContext();
      beforeEffect();
      page = await context.newPage();
      beforeEffect();
      if (observedTarget) {
        observedDocument = new ObservedDocumentOperation(page, observedTarget, beforeEffect);
        await observedDocument.start();
        observedDocument.assertCurrent();
        beforeEffect();
        process.stdout.write(`1 document-started
`);
      } else
        process.stdout.write(`1 page-created
`);
    } else if (sequence === 2 && pending === `2 close
`) {
      observedDocument?.assertCurrent();
      beforeEffect();
      await cleanup();
      if (first.kind === "failed")
        throw first.error;
      beforeEffect();
      process.stdout.write(`2 disconnected
`);
    } else
      throw new Error("command order");
    sequence += 1;
    pending = "";
  }
  if (pending || sequence !== 3)
    throw new Error("incomplete command stream");
}
try {
  await main();
} catch (error) {
  retainFirst(error);
}
await cleanup();
var finalFailure = retainedFailure();
if (finalFailure.kind === "failed") {
  console.error(observedTarget ? "fixed observed document driver failed" : finalFailure.error);
  process.exitCode = 1;
}
