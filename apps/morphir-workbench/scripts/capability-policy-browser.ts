import { once } from 'node:events';
import { resolve } from 'node:path';
import { chromium } from 'playwright';

declare global {
  var morphirCapabilityMck: (source: string) => string;
}

// NDJSON transport only. The same compiled MoonBit adapter executes in Chromium;
// the independent Rust runner owns fixtures, expected results and every verdict.
const compiled = process.argv[2];
if (!compiled) throw new Error('Pass the compiled capability adapter path');
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  await page.route(/^https?:\/\//, (route) => route.abort());
  await page.addScriptTag({ path: resolve(compiled) });
  process.stderr.write(`Capability adapter Chromium ${browser.version()}\n`);
  let pending = Buffer.alloc(0);
  const limit = 2 * 1024 * 1024;
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let stopped = false;
  for await (const chunk of process.stdin) {
    pending = Buffer.concat([pending, Buffer.from(chunk)]);
    let end: number;
    while ((end = pending.indexOf(10)) !== -1) {
      if (end > limit) throw new Error('NDJSON line exceeds 2 MiB');
      const line = decoder.decode(pending.subarray(0, end));
      pending = pending.subarray(end + 1);
      const response = await page.evaluate(
        (source) => globalThis.morphirCapabilityMck(source),
        line,
      );
      if (response === '') {
        stopped = true;
        break;
      }
      if (!process.stdout.write(response + '\n')) {
        await once(process.stdout, 'drain');
      }
    }
    if (stopped) break;
    if (pending.length > limit) throw new Error('NDJSON line exceeds 2 MiB');
  }
  if (!stopped && pending.length !== 0) {
    throw new Error('Incomplete NDJSON line');
  }
} finally {
  await browser.close();
}
