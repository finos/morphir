// Additional controls, separate from the frozen independent parity corpus.

///|
test "tree sidecars with matching stems do not change model semantics" {
  for version in ["3.1.0", "4.0.0"] {
    for extension in ["json", "yaml", "yml"] {
      let files : Map[String, String] = Map([
        (
          "manifest." + extension,
          "{\"formatVersion\":\"" +
          version +
          "\",\"distribution\":\"Library\",\"package\":\"parity\",\"pathBudget\":64}",
        ),
        (
          "pkg/parity/main/module." + extension,
          "{\"formatVersion\":\"" +
          version +
          "\",\"path\":\"main\",\"types\":[],\"values\":[]}",
        ),
      ])
      let baseline = @codec.to_json(@yaml.read_tree(files))
      for prefix in ["", "docs/", "pkg-not-model/", "deps-not-model/"] {
        // Sidecars need not parse as model documents or match its codec/version.
        files[prefix + "notes.json"] = "{\"formatVersion\":999}\r\n"
        files[prefix + "notes.yaml"] = "# independent notes\r\nnotes: [unfinished\r\n"
        files[prefix + "notes.yml"] = "more notes λ\n"
      }
      let actual = @yaml.read_tree(files) catch {
        @wire.Invalid(code, detail) => fail(code + ": " + detail)
        error => raise error
      }
      assert_eq(@codec.to_json(actual), baseline)
    }
  }
}

///|
test "tree relevant logical documents still refuse codec duplicates" {
  for stem in ["manifest", "pkg/parity/main/module", "deps/sdk/@/main/module"] {
    for extension in ["json", "yml"] {
      let files : Map[String, String] = Map([
        (
          "manifest.yaml", "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 4000\ndependencies: [sdk]\n",
        ),
        (
          "pkg/parity/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
        ),
        (
          "deps/sdk/@/main/module.yaml", "formatVersion: 4\npath: main\ntypes: []\nvalues: []\n",
        ),
      ])
      files[stem + "." + extension] = "{}"
      let (code, detail) = try {
        ignore(@yaml.read_tree(files))
        ("accepted", "")
      } catch {
        @wire.Invalid(code, detail) => (code, detail)
        _ => ("other_refusal", "")
      }
      assert_eq(code, "invalid_distribution_shape")
      assert_eq(
        detail,
        stem + "#: Ambiguous physical files for one logical document",
      )
    }
  }
}

///|
test "ignored tree sidecars still obey physical path source and file bounds" {
  let manifest = "formatVersion: 4\ndistribution: Library\npackage: parity\npathBudget: 64\n"
  for path in ["../notes.json", "/notes.yaml", "docs/../notes.yml"] {
    let files : Map[String, String] = Map([
      ("manifest.yaml", manifest),
      (path, "notes"),
    ])
    let code = try {
      ignore(@yaml.read_tree(files))
      "accepted"
    } catch {
      @wire.Invalid(code, _) => code
      _ => "other_refusal"
    }
    assert_eq(code, "invalid_distribution_shape")
  }
  let files : Map[String, String] = Map([
    ("manifest.yaml", manifest),
    ("notes.json", "λ"),
    ("notes.yaml", "λ"),
  ])
  let code = try {
    ignore(
      @yaml.read_tree(files, limits={
        ..@yaml.Limits::default(),
        max_bytes: manifest.length() + 3,
      }),
    )
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_eq(code, "yaml_source_limit")
  for index = 0; index < 4096; index = index + 1 {
    files["notes-" + index.to_string() + ".json"] = ""
  }
  let code = try {
    ignore(@yaml.read_tree(files))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
    _ => "other_refusal"
  }
  assert_eq(code, "yaml_source_limit")
}
