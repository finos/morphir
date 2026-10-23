///|
/// Deterministic consumer checkpoint for installed provider acceptance drivers.
/// Trust provisioning and service selection remain explicit driver operations.
fn finite_run() -> String raise {
  let unit = @data.IRUnit::new("main", @fixtures.input(), metadata=[
    {
      node_id: "value:example:main#ready",
      data: @fixtures.adapter(
        "[" + @fixtures.row("ready", backend="authenticated_ready") + "]",
      ),
    },
  ])
  guard @data.Registry::new().encode("ion-text", unit) is @data.Text(text) else {
    fail("Ion text fixture")
  }
  text
}
