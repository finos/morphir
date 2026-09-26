// Cargo metadata comes from the exact source tag under qualification. Older
// published tags have IR tests only; a partial newer inventory is an error.
export function sourceQualificationTargets(metadata) {
  const engine = metadata.packages.find(pkg => pkg.name === "morphir-mck");
  if (!engine) throw new Error("missing morphir-mck in source tag");
  const available = new Set(engine.targets.filter(target => target.kind.includes("test")).map(target => target.name));
  const kitTest = available.has("runner_parity") ? "runner_parity" : available.has("kit_steps") ? "kit_steps" : null;
  if (!kitTest) throw new Error("missing runner_parity or kit_steps qualification test");
  if (!available.has("transport")) throw new Error("missing transport qualification test");
  const ir = [kitTest, "transport"];
  const packages = ["package_corpus", "package_protocol", "package_runner"];
  const present = packages.filter(name => available.has(name));
  if (present.length !== 0 && present.length !== packages.length) {
    throw new Error("incomplete package qualification test inventory");
  }
  return [...ir, ...present];
}
