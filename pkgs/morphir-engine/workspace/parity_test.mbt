///|
/// Frozen fixture text is verified against the tracked sources by CLI acceptance.
fn toml_corpus() -> Array[(String, String)] raise {
  guard @json.parse(toml_corpus_json) is Array(rows) else {
    fail("Configuration corpus")
  }
  rows.map(row => {
    guard row is Object(fields) &&
      fields.get("path") is Some(String(path)) &&
      fields.get("text") is Some(String(text)) else {
      fail("Configuration corpus entry")
    }
    (path, text)
  })
}

///|
/// Compare explicit source loading only. Discovery is deliberately not copied.
fn parity_differences(
  documents : Array[(String, String)],
) -> Array[String] raise {
  let mut previous = old_empty()
  let sources : Array[@lander.ConfigSource] = []
  for index, (path, content) in documents {
    previous = old_merge(previous, old_parse(content, origin=path))
    sources.push(
      @lander.ConfigSource::parsed_file(
        path,
        @toml_format.parse(content, origin=path),
        priority=index,
      ),
    )
  }
  let adopted = @lander.build(sources)
  let differences = []
  for key, origin in previous.provenance {
    let expected = previous.json(key)
    let actual : Json = @lander.bind(adopted, key) catch {
      error => {
        differences.push(key + ": value unavailable: " + error.message())
        continue
      }
    }
    if expected != Some(actual) {
      differences.push(
        key +
        ": value differs: " +
        expected.map(value => value.stringify()).unwrap_or("<missing>") +
        " / " +
        actual.stringify(),
      )
    }
    let origins = adopted.origins(@lander.KeyPath::parse(key))
    let winning = origins
      .last()
      .map(value => value.location.unwrap_or(value.source))
    if winning != Some(origin) {
      differences.push(
        key +
        ": origin differs: " +
        origin +
        " / " +
        winning.unwrap_or("<missing>"),
      )
    }
  }
  for (key, _) in adopted.provenance() {
    let path = key.names().join(".")
    if !previous.provenance.contains(path) {
      differences.push(path + ": additional adopted leaf")
    }
  }
  differences
}

///|
test "published manifest loading preserves every tracked legacy fixture project value" {
  guard @json.parse(json_corpus_json) is Array(rows) else {
    fail("JSON corpus")
  }
  assert_eq(rows.length(), 23)
  for row in rows {
    guard row is Object(fields) &&
      fields.get("path") is Some(String(path)) &&
      fields.get("text") is Some(String(text)) else {
      fail("JSON corpus entry")
    }
    let fixture = tree([("morphir.json", text)])
    let warnings = []
    let (defaults, expected) = old_legacy(fixture, "", warnings)
    let adopted = @workspace.discover(fixture)
    let actual = adopted.projects[0].document
    for (key, origin) in expected.provenance {
      assert_eq(actual.json(key), expected.json(key), msg=path + ": " + key)
      assert_eq(actual.provenance.get(key), Some(origin), msg=path + ": " + key)
    }
    for (key, origin) in defaults.provenance {
      assert_eq(actual.json(key), defaults.json(key), msg=path + ": " + key)
      assert_eq(actual.provenance.get(key), Some(origin), msg=path + ": " + key)
    }
    assert_eq(adopted.warnings, warnings, msg=path)
  }
}

///|
test "published TOML loading matches all tracked configuration fixture leaves and origins" {
  let corpus = toml_corpus()
  assert_eq(corpus.length(), 3)
  for entry in corpus {
    let differences = parity_differences([entry])
    assert_eq(differences, [], msg=entry.0 + "\n" + differences.join("\n"))
  }
}

///|
test "published merge retains replaced lists inherited leaves and winning origins" {
  assert_eq(
    parity_differences([
      (
        "defaults.toml", "[workspace]\nmembers=['one','two']\n[frontend]\nlanguage='scheme'\n[project]\nname='λ😀'\n[custom]\nenabled=true\ncount=42\nscale=1.25\n",
      ),
      (
        "project.toml", "[workspace]\nmembers=['three']\n[project]\nname='Replaced'\n",
      ),
      ("user.toml", "[custom]\nenabled=false\n"),
    ]),
    [],
  )
}

///|
fn old_shared(document : OldDocument) -> OldDocument {
  let value = match document.value {
    TomlTable(fields) => {
      let copy = fields.copy()
      copy.remove("project")
      copy.remove("workspace")
      @toml.TomlTable(copy)
    }
    other => other
  }
  let provenance = document.provenance.filter(fn(path, _) {
    path != "project" &&
    path != "workspace" &&
    !path.has_prefix("project.") &&
    !path.has_prefix("workspace.")
  })
  { value, provenance, }
}

///|
test "production configuration conventions match every old fixture value and winning origin" {
  let files = Map([])
  for (path, text) in toml_corpus() {
    let relative = path.split("monorepo/").last().unwrap().to_owned()
    files[relative] = text
  }
  let workspace = @workspace.discover(@workspace.Tree::from_files(files))
  let base = old_parse(files["morphir.toml"], origin="morphir.toml")
  let defaults = old_parse(
    "[workspace]\nout_dir = '.morphir/out'\n[frontend]\nlanguage = 'scheme'\n[project]\nsource_directory = 'src'\n[ir]\nformat_version = 4\nlayout = 'single-file'\nformat = 'json'\n",
    origin="defaults",
  )
  let expected : Array[(String, OldDocument, @config.Document)] = [
    ("workspace", old_merge(defaults, base), workspace.document),
  ]
  for project in workspace.projects {
    let path = project.root + "/morphir.toml"
    expected.push(
      (
        path,
        old_merge(
          old_merge(defaults, old_shared(base)),
          old_parse(files[path], origin=path),
        ),
        project.document,
      ),
    )
  }
  let differences = []
  for (name, previous, adopted) in expected {
    for key, origin in previous.provenance {
      if previous.json(key) != adopted.json(key) {
        differences.push(name + " " + key + ": value differs")
      }
      if adopted.provenance.get(key) != Some(origin) {
        differences.push(name + " " + key + ": origin differs")
      }
    }
    for key, _ in adopted.provenance {
      if !previous.provenance.contains(key) {
        differences.push(name + " " + key + ": additional leaf")
      }
    }
  }
  assert_eq(differences, [], msg=differences.join("\n"))
}
