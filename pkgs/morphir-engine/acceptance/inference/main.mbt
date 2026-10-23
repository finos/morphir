///|
/// The MoonBit library of one filled unit, with binary content as an array of byte values.
fn library(name : String, unit : @data.IRUnit) -> Json raise {
  let output = @generator.generate(
    @generator.Input::new(name, unit.distribution),
  )
  {
    "name": name,
    "artifacts": output.artifacts.map(artifact => {
      (
        {
          "path": artifact.path,
          "content": match artifact.content {
            Text(text) => Json::string(text)
            Binary(bytes) =>
              Json::array(
                bytes
                .to_array()
                .map(byte => Json::number(byte.to_int().to_double())),
              )
          },
        } : Json)
    }),
  }
}

///|
/// The MoonBit gap of a corpus program in `moonbit_gaps`. The generator must raise the named code; when it
/// generates the program, the gap is closed and its entry must go.
fn gap(name : String, code : String, unit : @data.IRUnit) -> Json raise {
  let (node, detail) = try
    @generator.generate(@generator.Input::new(name, unit.distribution))
  catch {
    @generator.Invalid(found, node, detail) if found == code => (node, detail)
    error => fail("\{name}: expected \{code}, got \{@debug.to_string(error)}")
  } noraise {
    _ => fail("\{name}: the MoonBit generator accepts it; remove its gap")
  }
  { "name": name, "code": code, "node": node, "detail": detail }
}

///|
/// The Elm project of one filled unit.
fn project(name : String, unit : @data.IRUnit) -> Json raise {
  let output = @elm.generate(name, unit.distribution, @elm.Options::default())
  {
    "name": name,
    "files": output.files.map(file => {
      ({ "path": file.path, "content": file.content } : Json)
    }),
  }
}

///|
/// Compiles each corpus program, fills its types and generates MoonBit and Elm. A failure raises, so that the
/// process exits non-zero.
fn finite_run() -> Json raise {
  let libraries : Array[Json] = []
  let gaps : Array[Json] = []
  let projects : Array[Json] = []
  for entry in corpus {
    let (name, source) = entry
    let file = @frontend.compile_file(
      source,
      package_name="scheme/e2e",
      module_name=name,
    )
    let unit = @engine.infer_unit(
      @data.IRUnit::new(name, file),
      @typing.Fill,
      true,
    )
    match moonbit_gaps.get(name) {
      Some(code) => gaps.push(gap(name, code, unit))
      None =>
        libraries.push(library(name, unit)) catch {
          error => fail("\{name}: \{@debug.to_string(error)}")
        }
    }
    projects.push(project(name, unit)) catch {
      error => fail("\{name}: \{@debug.to_string(error)}")
    }
  }
  ({ "moonbit": libraries, "moonbitGaps": gaps, "elm": projects } : Json)
}
