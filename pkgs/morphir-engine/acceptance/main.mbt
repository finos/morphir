///|
fn finite_run(json_mode~ : Bool = false) -> Json raise {
  let registry = @data.Registry::new()
  let unit = @data.IRUnit::new("model", @fixtures.conformance())
  let text = match registry.encode("ion-text", unit) {
    Text(text) => text
    Binary(_) => finite_refuse("Expected text", json_mode~)
  }
  let bytes = match registry.encode("ion-binary", unit) {
    Binary(bytes) => bytes
    Text(_) => finite_refuse("Expected bytes", json_mode~)
  }
  (
    {
      "ionText": text,
      "ionBinary": bytes.to_array().map(b => b.to_int()),
      "naming": naming_fixtures(),
    } : Json)
}
