// Fixed physical component. No application scenario, evaluation or source grant.
import { pathToFileURL } from "node:url";
import type { Browser, BrowserContext, Page } from "playwright-core";
import { parseClock, acceptSample } from "./driver-clock";

const [entry, endpoint, artifacts, atText, endText, numerText, denomText] = process.argv.slice(2);
if (process.argv.length !== 9 || !entry || !endpoint || !artifacts) {
  throw new Error("fixed driver arguments required");
}
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
let first: unknown;
async function cleanup(): Promise<void> {
  for (const release of [
    async () => { if (page) { const actual = page; page = undefined; await actual.close(); } },
    async () => { if (context) { const actual = context; context = undefined; await actual.close(); } },
    async () => { if (browser) { const actual = browser; browser = undefined; await actual.close(); } },
  ]) {
    try { await release(); } catch (error) { first ??= error; }
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
    if (sequence === 1 && pending === "1 page\n") {
      beforeEffect();
      context = await browser.newContext();
      beforeEffect();
      page = await context.newPage();
      beforeEffect();
      process.stdout.write("1 page-created\n");
    } else if (sequence === 2 && pending === "2 close\n") {
      beforeEffect();
      await cleanup();
      if (first) throw first;
      beforeEffect();
      process.stdout.write("2 disconnected\n");
    } else throw new Error("command order");
    sequence += 1;
    pending = "";
  }
  if (pending || sequence !== 3) throw new Error("incomplete command stream");
}
try { await main(); } catch (error) { first ??= error; }
await cleanup();
if (first) { console.error(first); process.exitCode = 1; }
