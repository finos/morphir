///|
fn finite_run(json_mode~ : Bool = false) -> String raise {
  let registry = @data.Registry::new()
  let source = @data.SourceSnapshot::{
    unit_id: "Pricing",
    content: Text(
      "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"pricing\",\"def\":{\"modules\":{}}}}}",
    ),
  }
  let unit = registry.decode("morphir-json", source)
  let checkpoint = registry.checkpoint(unit)
  let restored = registry.decode("ion-binary", {
    unit_id: source.unit_id,
    content: checkpoint,
  })
  assert_eq(restored.distribution, unit.distribution)
  let text = registry.checkpoint(restored, codec="ion-text")
  match text {
    Text(value) => value
    Binary(_) =>
      finite_refuse("Ion text codec returned binary content", json_mode~)
  }
}
