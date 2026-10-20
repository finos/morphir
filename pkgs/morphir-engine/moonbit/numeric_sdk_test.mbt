///|
test "numeric SDK snapshot pins types and preserves contracts through Ion and execution" {
  let snapshot = files()
  snapshot["morphir.toml"] = snapshot["morphir.toml"].replace(
    old="language='moonbit'",
    new="language='moonbit'\nprofile='moonbit-model-experimental-v1'",
  )
  snapshot["src/Main.mbt"] = "pub fn rounded(v : Double) -> @integer.Integer raise @sdk.SdkError { @basics.round(v) }\npub fn checked(v : Double) -> @integer.Integer? { @int.from_float64_exact(v) }\npub fn exact(v : @integer.Integer) -> Double? { @int.to_float64_exact(v) }"
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let descriptor = plan(engine, snapshot).source_frontends()[0]
  for
    name in [
      "finos/morphir-sdk", "finos/morphir-sdk/int", "finos/morphir-sdk/integer",
      "finos/morphir-sdk/basics",
    ] {
    assert_eq(
      descriptor.dependencies[name],
      "0.1.0+tree:9c83a100383570236b3d781362524008f76dd56d",
    )
  }
  let report = execute(engine, snapshot)
  assert_true(report.successful())
  let registry = @data.Registry::new()
  let unit = registry.decode("ion-binary", {
    unit_id: "Main",
    content: report.artifacts[0].content,
  })
  let suite = @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      {
        "id": "round",
        "entry": "pricing:app/main#rounded",
        "arguments": [{ "type": "float64", "bits": "13832806255468478464" }],
      },
      {
        "id": "fractional",
        "entry": "pricing:app/main#checked",
        "arguments": [{ "type": "float64", "bits": "4609434218613702656" }],
      },
      {
        "id": "exact",
        "entry": "pricing:app/main#checked",
        "arguments": [{ "type": "float64", "bits": "4611686018427387904" }],
      },
      {
        "id": "inexact",
        "entry": "pricing:app/main#exact",
        "arguments": [{ "type": "int", "value": "9007199254740993" }],
      },
    ],
  })
  for format in ["ion-text", "ion-binary"] {
    let replay = registry.decode(format, {
      unit_id: "Main",
      content: registry.encode(format, unit),
    })
    assert_eq(replay.distribution, unit.distribution)
    assert_eq(
      @execution.plan_scheme(replay, suite)
      .evaluate()
      .map(@protocol.Value::to_json),
      [
        { "type": "int", "value": "-1" },
        { "type": "maybe", "case": "nothing" },
        {
          "type": "maybe",
          "case": "just",
          "value": { "type": "int", "value": "2" },
        },
        { "type": "maybe", "case": "nothing" },
      ],
    )
  }
  for
    (source, code) in [
      (
        "pub fn f(v : Double) -> @integer.Integer { @basics.round(v) }", "error_contract",
      ),
      (
        "pub fn f(v : Double) -> Double? { @int.from_float64_exact(v) }", "type_mismatch",
      ),
      (
        "pub fn f(v : Double) -> @integer.Integer? { @other.from_float64_exact(v) }",
        "unknown_binding",
      ),
    ] {
    snapshot["src/Main.mbt"] = source
    let failed = execute(engine, snapshot)
    assert_false(failed.successful())
    assert_true(failed.artifacts.is_empty())
    assert_true(
      failed.diagnostics[0].message.has_prefix("moonbit_frontend." + code + ":"),
    )
  }
  snapshot["src/Main.mbt"] = "pub fn f(v : Double) -> @integer.Integer? { @int.from_float64_exact(v) }"
  snapshot["morphir.toml"] = snapshot["morphir.toml"] +
    "\ncheckpoint_format='morphir-json'"
  let lossy = execute(engine, snapshot)
  assert_false(lossy.successful())
  assert_true(lossy.artifacts.is_empty())
  assert_true(lossy.diagnostics[0].message.contains("data.lossy_conversion"))
}
