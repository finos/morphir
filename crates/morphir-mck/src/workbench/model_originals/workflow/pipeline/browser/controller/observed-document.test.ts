import assert from "node:assert/strict";
import { createServer } from "node:http";
import { EventEmitter } from "node:events";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { ObservedDocumentOperation, parseObservedLaunch } from "./observed-document.ts";
import type { Page } from "playwright-core";

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((complete, fail) => { resolve = complete; reject = fail; });
  return {promise, resolve, reject};
}

// Reference-ownership/race controls only. These doubles do not execute a Page,
// application, channel or physical browser operation and grant no qualification.
function referenceFixture(checkClock: () => void = () => {}) {
  const target = parseObservedLaunch(`http://127.0.0.1:47123/launch?token=${"A".repeat(43)}`);
  const acquired = deferred<void>(), release = deferred<void>();
  const events = new EventEmitter();
  let address = "about:blank", disposals = 0, evaluations = 0;
  const frame = {url: () => address};
  const pending = deferred<unknown>();
  const actual = {awaitInspectionPending: () => pending.promise, executePendingCore: () => "enqueued",
    awaitOpeningSettled: async () => ({kind: "stored"})};
  const remote = {async dispose() {disposals++; release.resolve();},
    async evaluate(callback: (value: typeof actual) => unknown) {evaluations++; return callback(actual);}};
  const handle = deferred<typeof remote>();
  const page = Object.assign(events, {mainFrame: () => frame, isClosed: () => false, url: () => address,
    async goto() {address = target.documentUrl; events.emit("framenavigated", frame); return {status: () => 200};},
    evaluateHandle() {acquired.resolve(); return handle.promise;}}) as unknown as Page;
  return {operation: new ObservedDocumentOperation(page, target, checkClock), acquired, release, pending,
    supply: () => handle.resolve(remote), disposals: () => disposals, evaluations: () => evaluations};
}

test("late-created remote reference is disposed without restoring startup after disposal", async () => {
  const fixture = referenceFixture();
  const outcome = fixture.operation.start().catch((error: unknown) => error);
  await fixture.acquired.promise;
  fixture.operation.dispose();
  const first = await outcome;
  assert.ok(first instanceof Error);
  fixture.supply();
  await fixture.release.promise;
  assert.equal(fixture.disposals(), 1);
  assert.throws(() => fixture.operation.assertCurrent(), error => error === first);
  await assert.rejects(fixture.operation.executePendingCore(), error => error === first);
  assert.equal(fixture.evaluations(), 0);
});

test("one outstanding fixed operation refuses overlap and retains its first failure", async () => {
  const fixture = referenceFixture();
  fixture.supply();
  await fixture.operation.start();
  const waiting = fixture.operation.awaitInspectionPending().catch((error: unknown) => error);
  const overlap = await fixture.operation.executePendingCore().catch((error: unknown) => error);
  assert.ok(overlap instanceof Error);
  assert.equal(await waiting, overlap);
  fixture.pending.resolve({kind: "inspection-pending"});
  await fixture.release.promise;
  assert.equal(fixture.evaluations(), 1);
  assert.equal(fixture.disposals(), 1);
  await assert.rejects(fixture.operation.awaitOpeningSettled(), error => error === overlap);
  fixture.operation.dispose();
});

test("original deadline failure after handle fulfillment disposes the actual created reference", async () => {
  let stale = false;
  const clockFault = new Error("same original end after reference creation");
  const fixture = referenceFixture(() => {if (stale) throw clockFault;});
  const running = fixture.operation.start().catch((error: unknown) => error);
  await fixture.acquired.promise;
  stale = true;
  fixture.supply();
  assert.equal(await running, clockFault);
  await fixture.release.promise;
  assert.equal(fixture.disposals(), 1);
  assert.throws(() => fixture.operation.assertCurrent(), error => error === clockFault);
  fixture.operation.dispose();
});

test("fixed callback rejection retains the same error and retires its remote reference", async () => {
  const fixture = referenceFixture();
  fixture.supply();
  await fixture.operation.start();
  const running = fixture.operation.awaitInspectionPending().catch((error: unknown) => error);
  const actual = new Error("actual callback rejection boundary");
  fixture.pending.reject(actual);
  assert.equal(await running, actual);
  await fixture.release.promise;
  assert.equal(fixture.disposals(), 1);
  await assert.rejects(fixture.operation.awaitOpeningSettled(), error => error === actual);
  fixture.operation.dispose();
});

test("disposal of an outstanding fixed wait cannot be healed by its later callback", async () => {
  const fixture = referenceFixture();
  fixture.supply();
  await fixture.operation.start();
  const running = fixture.operation.awaitInspectionPending().catch((error: unknown) => error);
  fixture.operation.dispose();
  const first = await running;
  assert.ok(first instanceof Error);
  fixture.pending.resolve({kind: "inspection-pending"});
  await fixture.release.promise;
  assert.equal(fixture.disposals(), 1);
  assert.equal(fixture.evaluations(), 1);
  await assert.rejects(fixture.operation.executePendingCore(), error => error === first);
});

test("observed launch accepts only the closed loopback authentication shape", () => {
  const token = "A".repeat(43);
  const target = parseObservedLaunch(`http://127.0.0.1:47123/launch?token=${token}`);
  assert.equal(target.documentUrl, "http://127.0.0.1:47123/observed/?mode=connected-originals");
  assert.equal(parseObservedLaunch(`http://127.0.0.1:80/launch?token=${token}`).documentUrl,
    "http://127.0.0.1/observed/?mode=connected-originals");
  for (const value of [
    `http://localhost:47123/launch?token=${token}`,
    `https://127.0.0.1:47123/launch?token=${token}`,
    `http://127.0.0.1:0/launch?token=${token}`,
    `http://127.0.0.1:65536/launch?token=${token}`,
    `http://u@127.0.0.1:47123/launch?token=${token}`,
    `http://127.0.0.1:47123/launch?token=${token}&x=1`,
    `http://127.0.0.1:47123/launch?token=${token}#x`,
    `http://127.0.0.1:47123/launch?token=${"A".repeat(42)}`,
    `http://127.0.0.1:47123/launch?token=${"A".repeat(42)}B`,
    `http://127.0.0.1:47123/launch?token=${"A".repeat(42)}%41`,
  ]) assert.throws(() => parseObservedLaunch(value), /observed launch shape/);
});

const entry = process.env.MCK_DRIVER_PLAYWRIGHT_ENTRY;
const executablePath = process.env.MCK_DRIVER_CHROMIUM;
const selected = entry && executablePath;
const controls = `export const connectedControls = Object.freeze({
  awaitInspectionPending: async () => ({kind:'inspection-pending'}),
  executePendingCore: () => 'enqueued',
  awaitOpeningSettled: async () => ({kind:'stored'})
});`;

test("actual selected Page waits for fixed module fulfillment and refuses stale lifecycle", {
  skip: selected ? false : "requires explicit selected Playwright and Chromium paths",
  timeout: 30000,
}, async (t) => {
  const { chromium } = await import(pathToFileURL(entry!).href);
  const browser = await chromium.launch({ executablePath, headless: true });
  let moduleText = "await fetch('/gate'); globalThis.fixedModuleReturned = true;" + controls;
  let gate: import("node:http").ServerResponse | undefined;
  let gateRequested: (() => void) | undefined;
  let moduleRequested: (() => void) | undefined;
  const server = createServer((request, response) => {
    if (request.url?.startsWith("/launch?")) {
      response.writeHead(303, { location: "/observed/?mode=connected-originals" }).end();
    } else if (request.url === "/observed/?mode=connected-originals") {
      response.writeHead(200, { "content-type": "text/html" }).end("<!doctype html><body>fixed test document<script type=\"module\" src=\"/observed/observed-document-entry.js\"></script></body>");
    } else if (request.url === "/observed/observed-document-entry.js") {
      response.writeHead(200, { "content-type": "text/javascript" }).end(moduleText);
      moduleRequested?.();
    } else if (request.url === "/gate") {
      gate = response;
      gateRequested?.();
    } else response.writeHead(404).end();
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  const target = parseObservedLaunch(`http://127.0.0.1:${address.port}/launch?token=${"A".repeat(43)}`);
  try {
    await t.test("load plus inserted script is insufficient while top-level await is held", async () => {
      const context = await browser.newContext();
      const page = await context.newPage();
      let loaded = false;
      page.once("load", () => { loaded = true; });
      let returned = false;
      const operation = new ObservedDocumentOperation(page, target, () => {});
      const requested = new Promise<void>((resolve) => { moduleRequested = resolve; });
      const gateArrived = new Promise<void>((resolve) => { gateRequested = resolve; });
      const running = operation.start().then(() => { returned = true; });
      await requested;
      await page.waitForLoadState("load");
      assert.equal(loaded, true);
      await page.evaluate(() => {
        const script = document.createElement("script");
        script.type = "module";
        script.textContent = "import '/observed/observed-document-entry.js';";
        document.head.append(script);
      });
      assert.equal(returned, false);
      await gateArrived;
      assert.ok(gate);
      gate.end("released");
      await running;
      operation.assertCurrent();
      assert.equal(await page.evaluate(() => (globalThis as any).fixedModuleReturned), true);
      await assert.rejects(operation.start(), /already started/);
      operation.dispose();
      await context.close();
    });
    await t.test("startup rejection stays the first failure", async () => {
      moduleText = "throw new Error('actual startup rejected');";
      const context = await browser.newContext();
      const page = await context.newPage();
      const operation = new ObservedDocumentOperation(page, target, () => {});
      const first = await operation.start().catch((error) => error);
      assert.match(first.message, /actual startup rejected/);
      await page.close();
      assert.throws(() => operation.assertCurrent(), (error) => error === first);
      operation.dispose();
      await context.close();
    });
    for (const expression of ["undefined", "false"] as const) {
      await t.test(`actual module rejecting ${expression} cannot become successful startup`, async () => {
        moduleText = `throw ${expression};`;
        const context = await browser.newContext();
        const page = await context.newPage();
        const operation = new ObservedDocumentOperation(page, target, () => {});
        const outcome = await operation.start().then(
          () => ({ kind: "returned" as const }),
          (error: unknown) => ({ kind: "raised" as const, error }),
        );
        assert.equal(outcome.kind, "raised");
        if (outcome.kind !== "raised") throw new Error("startup unexpectedly returned");
        // Playwright presents the browser's primitive rejection as an Error.
        // Retain that actual boundary object rather than projecting success.
        assert.ok(outcome.error instanceof Error);
        await page.close();
        assert.throws(() => operation.assertCurrent(), (error) => error === outcome.error);
        operation.dispose();
        await context.close();
      });
    }
    for (const thrown of [undefined, null, false, 0]) {
      await t.test(`actual clock callback failure ${String(thrown)} retains its closed failed state`, async () => {
        const context = await browser.newContext();
        const page = await context.newPage();
        const operation = new ObservedDocumentOperation(page, target, () => { throw thrown; });
        const outcome = await operation.start().then(
          () => ({ kind: "returned" as const }),
          (error: unknown) => ({ kind: "raised" as const, error }),
        );
        assert.equal(outcome.kind, "raised");
        if (outcome.kind !== "raised") throw new Error("startup unexpectedly returned");
        assert.equal(outcome.error, thrown);
        let repeat: { kind: "returned" } | { kind: "raised"; error: unknown } = { kind: "returned" };
        try { operation.assertCurrent(); } catch (error) { repeat = { kind: "raised", error }; }
        assert.equal(repeat.kind, "raised");
        if (repeat.kind === "raised") assert.equal(repeat.error, thrown);
        operation.dispose();
        await context.close();
      });
    }
    await t.test("retained readiness refuses an actual same-URL replacement", async () => {
      moduleText = controls;
      const context = await browser.newContext();
      const page = await context.newPage();
      const operation = new ObservedDocumentOperation(page, target, () => {});
      await operation.start();
      operation.assertCurrent();
      await page.reload();
      assert.throws(() => operation.assertCurrent(), /observed document replaced/);
      operation.dispose();
      await context.close();
    });
    await t.test("original clock is checked after actual module fulfillment", async () => {
      moduleText = "await fetch('/gate');" + controls;
      const context = await browser.newContext();
      const page = await context.newPage();
      let stale = false;
      const clockFault = new Error("original end elapsed after fulfillment");
      const operation = new ObservedDocumentOperation(page, target, () => { if (stale) throw clockFault; });
      const gateArrived = new Promise<void>((resolve) => { gateRequested = resolve; });
      const outcome = operation.start().catch((error) => error);
      await gateArrived;
      stale = true;
      gate!.end("released");
      assert.equal(await outcome, clockFault);
      assert.throws(() => operation.assertCurrent(), (error) => error === clockFault);
      operation.dispose();
      await context.close();
    });
    await t.test("fixed controls return actual closed outcomes on the retained current Page", async () => {
      moduleText = controls;
      const context = await browser.newContext();
      const page = await context.newPage();
      const operation = new ObservedDocumentOperation(page, target, () => {});
      try {
        await operation.start();
        assert.deepEqual(await operation.awaitInspectionPending(), {kind: "inspection-pending"});
        assert.equal(await operation.executePendingCore(), "enqueued");
        assert.deepEqual(await operation.awaitOpeningSettled(), {kind: "stored"});
      } finally { operation.dispose(); await context.close(); }
    });
    for (const [method, value] of [
      ["awaitInspectionPending", "({kind:'stored'})"],
      ["awaitInspectionPending", "({kind:'inspection-pending',extra:true})"],
      ["awaitOpeningSettled", "({kind:'inspection-pending'})"],
      ["executePendingCore", "'executed'"],
    ] as const) {
      await t.test(`actual ${method} refuses an unknown or mismatched result ${value}`, async () => {
        moduleText = `export const connectedControls = Object.freeze({
          awaitInspectionPending: async () => ({kind:'inspection-pending'}),
          executePendingCore: () => 'enqueued', awaitOpeningSettled: async () => ({kind:'stored'}),
          ${method}: async () => ${value}
        });`;
        const context = await browser.newContext();
        const page = await context.newPage();
        const operation = new ObservedDocumentOperation(page, target, () => {});
        try {
          await operation.start();
          const first = await operation[method]().catch((error: unknown) => error);
          assert.ok(first instanceof Error);
          assert.throws(() => operation.assertCurrent(), error => error === first);
          await assert.rejects(operation.executePendingCore(), error => error === first);
        } finally { operation.dispose(); await context.close(); }
      });
    }
    for (const interruption of ["navigate", "close", "dispose", "clock"] as const) {
      await t.test(`actual pending fixed wait rejects ${interruption} without later readiness`, async () => {
        moduleText = `export const connectedControls = Object.freeze({
          awaitInspectionPending: async () => {await fetch('/gate'); return {kind:'inspection-pending'};},
          executePendingCore: () => 'enqueued', awaitOpeningSettled: async () => ({kind:'stored'})
        });`;
        const context = await browser.newContext();
        const page = await context.newPage();
        let stale = false;
        const clockFault = new Error("original end during actual fixed wait");
        const operation = new ObservedDocumentOperation(page, target, () => {if (stale) throw clockFault;});
        try {
          await operation.start();
          const entered = new Promise<void>(resolve => {gateRequested = resolve;});
          const waiting = operation.awaitInspectionPending().catch((error: unknown) => error);
          await entered;
          if (interruption === "navigate") await page.reload();
          else if (interruption === "close") await page.close();
          else if (interruption === "dispose") operation.dispose();
          else {
            stale = true;
            assert.throws(() => operation.assertCurrent(), error => error === clockFault);
          }
          const first = await waiting;
          assert.ok(first instanceof Error);
          if (interruption === "clock") assert.equal(first, clockFault);
          gate?.end("late actual wait completion");
          assert.throws(() => operation.assertCurrent(), error => error === first);
          await assert.rejects(operation.executePendingCore(), error => error === first);
        } finally {gate?.end(); operation.dispose(); await context.close();}
      });
    }
    await t.test("disposal during startup cannot later produce readiness", async () => {
      moduleText = "await new Promise(() => {});";
      const context = await browser.newContext();
      const page = await context.newPage();
      const operation = new ObservedDocumentOperation(page, target, () => {});
      const requested = new Promise<void>((resolve) => { moduleRequested = resolve; });
      const outcome = operation.start().catch((error) => error);
      await requested;
      operation.dispose();
      const failure = await outcome;
      assert.match(failure.message, /disposed during startup/);
      assert.throws(() => operation.assertCurrent(), (error) => error === failure);
      await context.close();
    });
    for (const action of ["navigate", "close", "crash", "clock"] as const) {
      await t.test(`${action} refuses completion while fixed module is pending`, async () => {
        moduleText = "await new Promise(() => {});";
        const context = await browser.newContext();
        const page = await context.newPage();
        let stale = false;
        const clockFault = new Error("original end elapsed");
        const operation = new ObservedDocumentOperation(page, target, () => { if (stale) throw clockFault; });
        const requested = new Promise<void>((resolve) => { moduleRequested = resolve; });
        const running = operation.start();
        // Install rejection handling before deliberately invalidating the real Page.
        const outcome = running.catch((error) => error);
        await requested;
        if (action === "navigate") await page.goto(target.documentUrl);
        else if (action === "close") await page.close();
        else if (action === "crash") {
          const session = await context.newCDPSession(page);
          // The actual target crash event, rather than a command-response that
          // Chromium need not send after crashing, is this control's boundary.
          void session.send("Page.crash").catch(() => {});
        }
        else {
          stale = true;
          assert.throws(() => operation.assertCurrent(), (error) => error === clockFault);
        }
        const failure = await outcome;
        assert.ok(failure instanceof Error);
        if (action === "clock") assert.equal(failure, clockFault);
        assert.throws(() => operation.assertCurrent(), (error) => error === failure);
        operation.dispose();
        await context.close();
      });
    }
  } finally {
    gate?.end();
    await browser.close();
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
});
