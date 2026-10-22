import assert from "node:assert/strict";
import { createServer } from "node:http";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { ObservedDocumentOperation, parseObservedLaunch } from "./observed-document.ts";

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

test("actual selected Page waits for fixed module fulfillment and refuses stale lifecycle", {
  skip: selected ? false : "requires explicit selected Playwright and Chromium paths",
  timeout: 30000,
}, async (t) => {
  const { chromium } = await import(pathToFileURL(entry!).href);
  const browser = await chromium.launch({ executablePath, headless: true });
  let moduleText = "await fetch('/gate'); globalThis.fixedModuleReturned = true;";
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
      moduleText = "export const completed = true;";
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
      moduleText = "await fetch('/gate');";
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
