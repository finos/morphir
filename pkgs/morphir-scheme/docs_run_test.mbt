///|
/// Evaluate the block in a fresh runtime. This chapter has no modules, so a `;; file:` project means nothing here.
fn run_example(files : Array[(String, String)]) -> String raise {
  if files.iter().any(f => f.0 != "") {
    raise @scheme.Invalid(
      "`;; file:` projects are checked only in the Writing models chapter",
    )
  }
  let source = files.map(f => f.1).join("\n")
  @scheme.value_to_string(@scheme.Runtime::new().eval(source))
}

///|
test "a ;; file: project is refused outside the Writing models chapter" {
  let message = try {
    ignore(run_example([("src/a.scm", "1"), ("src/b.scm", "2")]))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(
    message,
    content="`;; file:` projects are checked only in the Writing models chapter",
  )
}
