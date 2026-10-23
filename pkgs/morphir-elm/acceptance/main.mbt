///|
fn project(
  name : String,
  ir : @ir.IRFile,
  options : @elm.Options,
) -> Json raise {
  let output = @elm.generate(name, ir, options)
  Json::object(
    Map::from_array([
      ("name", Json::string(name)),
      (
        "files",
        Json::array(
          output.files.map(f => {
            Json::object(
              Map::from_array([
                ("path", Json::string(f.path)),
                ("content", Json::string(f.content)),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
}

///|
fn finite_run() -> Json raise {
  let model = @elm.Options::default()
  let todo = { ..model, placeholders: DebugTodo, }
  let projects = [
    project("rentals", @fixtures.rentals(), model),
    project("shapes", @fixtures.shapes(), model),
    project("specs", @fixtures.specs(), todo),
    project("classic-greeting", @fixtures.classic_greeting(), model),
    project("classic-rentals-v1", @fixtures.classic_rentals_v1(), model),
    project("classic-rentals-v2", @fixtures.classic_rentals_v2(), model),
    project("sdk-tour", @fixtures.sdk_tour(), model),
  ]
  Json::object(Map::from_array([("projects", Json::array(projects))]))
}
