///|
fn print_projects(
  projects : Array[@engine.ProjectInfo],
  frontends : Array[String],
  targets : Array[String],
  mode : OutputMode,
) -> Int32 {
  let matches = projects.filter(project => {
    (
      frontends.is_empty() ||
      (project.frontend is Some(language) && frontends.contains(language))
    ) &&
    (
      targets.is_empty() ||
      (project.target is Some(language) && targets.contains(language))
    )
  })
  let diagnostics = projects
    .filter(p => p.error is Some(_))
    .map(project => {
      let message = project.error.unwrap()
      @platform.stderr(project.relative_path + ": " + message + "\n")
      Json::object(
        Map::from_array([
          ("projectPath", Json::string(project.relative_path)),
          ("message", Json::string(message)),
        ]),
      )
    })
  let successful = diagnostics.is_empty()
  match mode {
    Human => {
      println("NAME\tPATH\tFRONTEND\tTARGET")
      for project in matches {
        println(
          project.name +
          "\t" +
          project.relative_path +
          "\t" +
          project.frontend.unwrap_or("?") +
          "\t" +
          project.target.unwrap_or("?"),
        )
      }
    }
    JSON =>
      println(
        Json::object(
          Map::from_array([
            ("projects", Json::array(matches.map(p => p.to_json()))),
            ("diagnostics", Json::array(diagnostics)),
            ("successful", Json::boolean(successful)),
          ]),
        ).stringify(),
      )
    JSONLines => {
      for project in matches {
        emit_record("project", project.to_json())
      }
      for diagnostic in diagnostics {
        emit_record("diagnostic", diagnostic)
      }
      emit_record(
        "result",
        Json::object(
          Map::from_array([
            ("successful", Json::boolean(successful)),
            ("projectCount", Json::number(matches.length().to_double())),
          ]),
        ),
      )
    }
  }
  if successful {
    0
  } else {
    2
  }
}
