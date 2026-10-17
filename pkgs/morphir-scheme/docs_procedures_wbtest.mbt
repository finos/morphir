///|
test "every built-in procedure is documented, and every documented one exists" {
  let registered = Runtime::new().natives.keys().collect()
  registered.sort()
  let documented = documented_procedures.copy()
  documented.sort()
  @expect.expect_all(s => {
    s
    .expect(
      registered.filter(n => !documented.contains(n)),
      label="undocumented",
    )
    .to_be_empty()
    s
    .expect(
      documented.filter(n => !registered.contains(n)),
      label="documented but missing",
    )
    .to_be_empty()
  })
}
