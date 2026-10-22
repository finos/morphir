// Fixed physical component and one closed observed application operation.
// Neither launch spelling nor application completion creates a source grant.
import { pathToFileURL } from "node:url";
import type { Browser, BrowserContext, Page } from "playwright-core";
import { parseClock, acceptSample } from "./driver-clock";
import { ObservedDocumentOperation, parseObservedLaunch } from "./observed-document";

const [entry, endpoint, artifacts, atText, endText, numerText, denomText, variant, launchUrl,
  providerId, locator, projectId] = process.argv.slice(2);
if (![9, 11, 14].includes(process.argv.length) || !entry || !endpoint || !artifacts) {
  throw new Error("fixed driver arguments required");
}
const observedTarget = process.argv.length !== 9
  ? ((process.argv.length === 11 && variant === "observed-workbench")
      || (process.argv.length === 14 && variant === "observed-source-opening")) && launchUrl
    ? parseObservedLaunch(launchUrl)
    : (() => { throw new Error("fixed driver launch variant"); })()
  : undefined;
const openingSelection = process.argv.length === 14
  ? providerId && locator && projectId ? Object.freeze({providerId, locator, projectId})
    : (() => {throw new Error("fixed source selection arguments");})()
  : undefined;
// This binary is selected and hashed by Rust. The basis is qualified only for
// that Node24.22 Darwin binary, not arbitrary Node runtimes or platforms.
const clock = parseClock(atText, endText, numerText, denomText);
let previous = clock.calibrated;
function beforeEffect(): void {
  previous = acceptSample(clock, previous, process.hrtime.bigint());
}
let browser: Browser | undefined;
let context: BrowserContext | undefined;
let page: Page | undefined;
let observedDocument: ObservedDocumentOperation | undefined;
type FirstFailure = { readonly kind: "none" } | { readonly kind: "failed"; readonly error: unknown };
let first: FirstFailure = { kind: "none" };
function retainFirst(error: unknown): void {
  if (first.kind === "none") first = { kind: "failed", error };
}
function retainedFailure(): FirstFailure { return first; }
async function cleanup(): Promise<void> {
  // Intentional cleanup retires the retained lifecycle guard before closing
  // the SAME actual Page. A startup/business failure remains the first error.
  observedDocument?.dispose();
  for (const release of [
    async () => { if (page) { const actual = page; page = undefined; await actual.close(); } },
    async () => { if (context) { const actual = context; context = undefined; await actual.close(); } },
    async () => { if (browser) { const actual = browser; browser = undefined; await actual.close(); } },
  ]) {
    try { await release(); } catch (error) { retainFirst(error); }
  }
}
async function main(): Promise<void> {
  const { chromium } = await import(pathToFileURL(entry!).href) as typeof import("playwright-core");
  beforeEffect();
  browser = await chromium.connectOverCDP(endpoint!, { artifactsDir: artifacts!, isLocal: true });
  beforeEffect();
  process.stdout.write("attached\n");
  let sequence = 1;
  let pending = "";
  for await (const chunk of process.stdin) {
    // The closed command's maximum is eight ASCII bytes. No arbitrary payload.
    const bytes = chunk as Buffer;
    if (bytes.length + pending.length > 8 || bytes.some((byte) => byte > 127)) throw new Error("command shape");
    pending += bytes.toString("ascii");
    if (!pending.endsWith("\n")) continue;
    if (sequence === 1 && pending === (observedTarget ? "1 start\n" : "1 page\n")) {
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
        process.stdout.write("1 document-started\n");
      } else process.stdout.write("1 page-created\n");
    } else if (openingSelection && sequence === 2 && pending === "2 open\n") {
      if (!observedDocument) throw new Error("observed document unavailable");
      const actual = await observedDocument.beginConnectedOpening(openingSelection);
      observedDocument.assertCurrent();
      beforeEffect();
      process.stdout.write(`2 ${actual.kind}\n`);
    } else if (openingSelection && sequence === 3 && pending === "3 wait\n") {
      if (!observedDocument) throw new Error("observed document unavailable");
      const actual = await observedDocument.awaitCapturedInspectionPending();
      observedDocument.assertCurrent();
      beforeEffect();
      process.stdout.write(`3 ${actual.kind}\n`);
    } else if (sequence === (openingSelection ? 4 : 2) && pending === (openingSelection ? "4 close\n" : "2 close\n")) {
      observedDocument?.assertCurrent();
      beforeEffect();
      await cleanup();
      if (first.kind === "failed") throw first.error;
      beforeEffect();
      process.stdout.write(openingSelection ? "4 disconnected\n" : "2 disconnected\n");
    } else throw new Error("command order");
    sequence += 1;
    pending = "";
  }
  if (pending || sequence !== (openingSelection ? 5 : 3)) throw new Error("incomplete command stream");
}
try { await main(); } catch (error) { retainFirst(error); }
await cleanup();
const finalFailure = retainedFailure();
if (finalFailure.kind === "failed") {
  // Playwright navigation errors can include the one-use launch credential.
  // Keep the actual first error internally; the closed observed variant does
  // not serialize that error or its URL into process diagnostics.
  console.error(observedTarget ? "fixed observed document driver failed" : finalFailure.error);
  process.exitCode = 1;
}
