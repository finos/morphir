import assert from "node:assert/strict";
import { test } from "node:test";
import { verifyReleaseVersion } from "./mck-release-version.mjs";

test("accepts the released CLI's colored banner before its final version line", () => {
  const output = "\u001b[38;5;33mMorphir\u001b[39m\n  v0.4.0-beta.2 (built 2026-09-21)\n\nmorphir 0.4.0-beta.2\n";
  for (const text of [output, output.replaceAll("\n", "\r\n")]) {
    assert.equal(verifyReleaseVersion(text, "0.4.0-beta.2"), "morphir 0.4.0-beta.2");
  }
});

test("rejects a mismatched version even when the banner names the expected release", () => {
  assert.throws(() => verifyReleaseVersion("v0.4.0-beta.2\nmorphir 0.4.0-beta.1", "0.4.0-beta.2"), /version mismatch/);
});

test("requires an exact final version line", () => {
  for (const text of ["", "v0.4.0-beta.2", "morphir 0.4.0-beta.20", "morphir 0.4.0-beta.2\nfailed"]) {
    assert.throws(() => verifyReleaseVersion(text, "0.4.0-beta.2"), /version mismatch/);
  }
  assert.equal(verifyReleaseVersion("morphir 0.4.0-beta.2", "0.4.0-beta.2"), "morphir 0.4.0-beta.2");
});
