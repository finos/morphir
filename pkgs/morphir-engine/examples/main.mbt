///|
fn main {
  try {
    let host = @engine.Host::memory(
      Map::from_array([
        (
          "demo/morphir.toml", "[project]\nname = 'demo'\nsource_directory = 'src'\n",
        ),
        ("demo/src/main.scm", "40"),
        (
          "demo/morphir.config.scm", "(pipeline (transform (lambda (file) (ir-rewrite-file file (lambda (node) (if (ir-integer? node) (ir-with-integer node (+ (ir-integer node) 2)) node))))))",
        ),
      ]),
    )
    let report = @engine.Engine::new().run(host, @engine.Project("demo"))
    for diagnostic in report.diagnostics {
      println(diagnostic.stage + ": " + diagnostic.message)
    }
    for artifact in report.artifacts {
      println(artifact.source + " -> " + artifact.path)
      let result = @backend.run_file(
        @ir_json.read(artifact.content),
        @ir.FQName::parse("demo:main#main"),
        [],
      )
      println("result: " + @scheme.value_to_string(result))
    }
  } catch {
    error => println(@scheme.error_message(error))
  }
}
