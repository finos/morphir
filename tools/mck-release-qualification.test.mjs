import assert from "node:assert/strict";
import test from "node:test";
import { sourceQualificationTargets } from "./mck-release-qualification.mjs";

function metadata(names) {
  return { packages: [{ name: "morphir-mck", targets: names.map(name => ({ name, kind: ["test"] })) }] };
}

const ir = ["runner_parity", "transport"];
const packages = ["package_corpus", "package_protocol", "package_runner"];

test("older IR-only tags retain their existing qualification tests", () => {
  assert.deepEqual(sourceQualificationTargets(metadata(ir)), ir);
});

test("package-capable tags require all package source checks", () => {
  assert.deepEqual(sourceQualificationTargets(metadata([...packages, ...ir, "unrelated"])), [...ir, ...packages]);
});

test("a partial package test inventory fails instead of silently reducing qualification", () => {
  for (const absent of packages) {
    assert.throws(() => sourceQualificationTargets(metadata([...ir, ...packages.filter(name => name !== absent)])), /incomplete package qualification/);
  }
});

test("missing engine or IR tests fail qualification preparation", () => {
  assert.throws(() => sourceQualificationTargets({ packages: [] }), /missing morphir-mck/);
  assert.throws(() => sourceQualificationTargets(metadata(["transport"])), /missing runner_parity/);
  const input = metadata(ir);
  input.packages[0].targets[0].kind = ["bin"];
  assert.throws(() => sourceQualificationTargets(input), /missing runner_parity/);
});
