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
  let mut previous = @config.empty()
  let sources : Array[@lander_config.ConfigSource] = []
  for index, (path, content) in documents {
    previous = @config.merge(previous, @config.parse(content, origin=path))
    sources.push(
      @lander_config.ConfigSource::parsed_file(
        path,
        @lander_toml.parse(content, origin=path),
        priority=index,
      ),
    )
  }
  let adopted = @lander_config.build(sources)
  let differences = []
  for key, origin in previous.provenance {
    let expected = previous.json(key)
    let actual : Json = @lander_config.bind(adopted, key) catch {
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
    let origins = adopted.origins(@lander_config.KeyPath::parse(key))
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
