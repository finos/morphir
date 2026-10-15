///|
/// IR to Elm to IR (criterion B): generates Elm from `input` with the default backend options, compiles the
/// generated sources with `compile_project` (the package name and the exposed modules come from the generated
/// `morphir.json`) and returns `differences(input, output)`. When the backend refuses the input, the result is one
/// `generate: <code> <detail>` line per problem; when the frontend fails, one `compile: <code> <path> <message>` line
/// per problem. `name` is the unit id of the backend.
fn round_trip(name : String, input : @ir.IRFile) -> Array[String] raise {
  let output = @elm.generate(name, input, @elm.Options::default()) catch {
    Refused(problem) => return ["generate: \{problem.code} \{problem.detail}"]
    Failed(problems) =>
      return problems.map(p => "generate: \{p.code} \{p.detail}")
  }
  let sources : Array[@frontend.ElmSource] = []
  let mut manifest : Json = Json::null()
  for file in output.files {
    match file.role {
      Source => {
        guard file.path is [.. "src/", .. rest] else {
          fail("a generated source is not in src/: " + file.path)
        }
        sources.push({ path: rest.to_owned(), content: file.content, })
      }
      MorphirManifest => manifest = @json.parse(file.content)
      ElmManifest => ()
    }
  }
  guard manifest
    is { "name": String(package_name), "exposedModules": Array(exposed), .. } else {
    fail("the generated morphir.json has no name or exposedModules")
  }
  let exposed_modules = exposed.map(m => {
    guard m is String(text) else { fail("an exposed module is not a string") }
    text
  })
  let actual = @frontend.compile_project(sources, package_name, exposed_modules) catch {
    @frontend.ElmFailed(problems) =>
      return problems.map(p => "compile: \{p.code} \{p.path} \{p.message}")
  }
  differences(input, actual)
}

///|
fn round_trip_inputs() -> Array[(String, @ir.IRFile)] raise {
  let inputs : Array[(String, @ir.IRFile)] = [
    ("classic-greeting", @fixtures.classic_greeting()),
    ("classic-rentals-v1", @fixtures.classic_rentals_v1()),
    ("classic-rentals-v2", @fixtures.classic_rentals_v2()),
  ]
  for project in parity_projects() {
    inputs.push(("parity-" + project.name, read_expected(project.expected)))
  }
  inputs
}

///|
test "IR to Elm to IR gives the same IR, except pinned gaps" {
  let gaps = round_trip_gaps()
  let failures : Array[String] = []
  for input in round_trip_inputs() {
    let found = round_trip(input.0, input.1)
    let pinned = gaps.get(input.0).unwrap_or([])
    if found != pinned {
      failures.push(
        input.0 +
        ":\n  found\n    " +
        found.join("\n    ") +
        "\n  pinned\n    " +
        pinned.join("\n    "),
      )
    }
  }
  if !failures.is_empty() {
    fail(failures.join("\n"))
  }
}

///|
test "every pinned round-trip gap names an input" {
  let names = round_trip_inputs().map(i => i.0)
  for name, _ in round_trip_gaps() {
    assert_true(names.contains(name))
  }
}
