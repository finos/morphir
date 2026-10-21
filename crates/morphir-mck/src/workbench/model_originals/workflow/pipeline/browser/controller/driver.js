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

// crates/morphir-mck/src/workbench/model_originals/workflow/pipeline/browser/controller/driver.ts
var [entry, endpoint, artifacts, atText, endText, numerText, denomText] = process.argv.slice(2);
if (process.argv.length !== 9 || !entry || !endpoint || !artifacts) {
  throw new Error("fixed driver arguments required");
}
var clock = parseClock(atText, endText, numerText, denomText);
var previous = clock.calibrated;
function beforeEffect() {
  previous = acceptSample(clock, previous, process.hrtime.bigint());
}
var browser;
var context;
var page;
var first;
async function cleanup() {
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
      first ??= error;
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
    if (sequence === 1 && pending === `1 page
`) {
      beforeEffect();
      context = await browser.newContext();
      beforeEffect();
      page = await context.newPage();
      beforeEffect();
      process.stdout.write(`1 page-created
`);
    } else if (sequence === 2 && pending === `2 close
`) {
      beforeEffect();
      await cleanup();
      if (first)
        throw first;
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
  first ??= error;
}
await cleanup();
if (first) {
  console.error(first);
  process.exitCode = 1;
}
