import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

// Real selected-Node process control only. No Page, browser or profile is qualified.
test("an expired original end refuses before executing the selected runtime module", async () => {
  const root = await mkdtemp(join(tmpdir(), "morphir-driver-startup-"));
  try {
    const entry = join(root, "selected-runtime.mjs");
    const imported = join(root, "imported");
    await writeFile(entry, 'import { writeFileSync } from "node:fs";\n'
      + 'writeFileSync(new URL("./imported", import.meta.url), "unexpected import");\n'
      + 'throw new Error("selected runtime executed after its original end");\n');
    const calibrated = process.hrtime.bigint();
    const end = calibrated + 1n;
    assert.ok(process.hrtime.bigint() >= end, "the single fixed export is already expired");
    const child = spawnSync(process.execPath, [
      fileURLToPath(new URL("./driver.js", import.meta.url)), entry,
      "http://127.0.0.1:1", root, String(calibrated), String(end), "1", "1",
    ], { timeout: 10000, encoding: "utf8", env: {}, input: "" });
    assert.equal(child.error, undefined);
    assert.equal(child.signal, null);
    assert.equal(child.status, 1);
    assert.equal(existsSync(imported), false, "expired startup must not execute the selected module");
    assert.equal(child.stdout, "");
    assert.match(child.stderr, /original end elapsed/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
