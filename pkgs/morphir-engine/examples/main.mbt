///|
fn finite_run(json_mode~ : Bool = false) -> Json raise {
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
  let diagnostics : Array[Json] = []
  let artifacts : Array[Json] = []
  for diagnostic in report.diagnostics {
    diagnostics.push({
      "stage": diagnostic.stage,
      "message": diagnostic.message,
    })
    if !json_mode {
      println(diagnostic.stage + ": " + diagnostic.message)
    }
  }
  for artifact in report.artifacts {
    if !json_mode {
      println(artifact.source + " -> " + artifact.path)
    }
    let result = @backend.run_file(
      @ir_json.read(artifact.content),
      @ir.FQName::parse("demo:main#main"),
      [],
    )
    let evaluation = @scheme.value_to_string(result)
    artifacts.push({
      "source": artifact.source,
      "path": artifact.path,
      "evaluation": evaluation,
    })
    if !json_mode {
      println("result: " + evaluation)
    }
  }
  { "diagnostics": diagnostics, "artifacts": artifacts }
}
