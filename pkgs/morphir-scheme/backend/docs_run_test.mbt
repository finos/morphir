///|
/// Evaluate the block in a runtime with the backend installed. The block is Scheme text, not a model file, so a
/// `;; file:` project means nothing here.
fn run_example(files : Array[(String, String)]) -> String raise {
  if files.iter().any(f => f.0 != "") {
    raise @scheme.Invalid(
      "`;; file:` projects are checked only in the Writing models chapter",
    )
  }
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @scheme.value_to_string(runtime.eval(files.map(f => f.1).join("\n")))
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
