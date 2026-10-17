///|
/// Check the files as one project in one runtime: compile each file in file mode as the module its path names,
/// load the emitted text of every file in order, then run the last file's `main` when it has trailing
/// expressions. A file can therefore refer to a definition of an earlier file by its qualified name.
fn run_example(files : Array[(String, String)]) -> String raise {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let mut last : (@ir.IRFile, String)? = None
  for file in files {
    let module_name = module_of(file.0)
    let ir = @frontend.compile_file(file.1, module_name~)
    ignore(runtime.eval(@backend.emit_file(ir)))
    last = Some((ir, module_name))
  }
  guard last is Some((ir, module_name)) && has_main(ir) else { return "" }
  @scheme.value_to_string(
    @backend.run_file_in(
      runtime,
      ir,
      @ir.FQName::parse("user:" + module_name + "#main"),
      [],
    ),
  )
}

///|
fn module_of(path : String) -> String {
  if path == "" {
    return "main"
  }
  let p = if path.has_prefix("src/") { path[4:].to_owned() } else { path }
  match p.rev_find(".") {
    Some(i) => p[:i].to_owned()
    None => p
  }
}

///|
fn has_main(ir : @ir.IRFile) -> Bool raise {
  guard ir.distribution is Library(_, _, definition) else { return false }
  let main = @ir.Name::parse("main")
  definition.modules.values().any(m => m.value.values.contains(main))
}

///|
test "the files of a project are checked as one project" {
  let result = run_example([
    ("src/util.scm", "(define (inc x) (+ x 1))"),
    ("src/main.scm", "(user:util#inc 41)"),
  ])
  inspect(result, content="42")
}
