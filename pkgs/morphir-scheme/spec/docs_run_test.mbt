///|
/// A package form is read and printed; any other block is a lone type in package `my/pkg`, module `m`.
/// A printed package is joined onto one line, so a one-line `;; =>` can state it.
/// A specification is one block, so a `;; file:` project means nothing here.
fn run_example(files : Array[(String, String)]) -> String raise {
  if files.iter().any(f => f.0 != "") {
    raise @scheme.Invalid(
      "`;; file:` projects are checked only in the Writing models chapter",
    )
  }
  let source = files.map(f => f.1).join("\n")
  try {
    if source.contains("(package ") {
      let (name, spec) = @spec.read_package(source)
      @spec.print_package(name, spec)
      .split("\n")
      .map(line => line.trim_start(chars=" ").to_owned())
      .collect()
      .join(" ")
    } else {
      let t = @spec.read_type_text(
        source,
        package_name="my/pkg",
        module_path="m",
      )
      @spec.print_type(t, package_name=@ir.Path::parse("my/pkg"))
    }
  } catch {
    @spec.SpecError(line~, column~, message~) =>
      raise @scheme.Invalid("\{line}:\{column}: \{message}")
    e => raise e
  }
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
