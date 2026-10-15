///|
fn refused(run : () -> Unit raise) -> String {
  try {
    run()
    "accepted"
  } catch {
    @config.Invalid(message) => message
    error => "unexpected: " + error.to_string()
  }
}

///|
test "language, profile and backend ids are lowercase words" {
  for text in ["elm", "moonbit", "ion-binary", "x1"] {
    assert_eq(@ids.LanguageId::parse(text).to_string(), text)
    assert_eq(@ids.ProfileId::parse(text).to_string(), text)
    assert_eq(@ids.BackendId::parse(text).to_string(), text)
  }
  for text in ["", "Elm", "1elm", "el m", "elm/x", "a".repeat(65)] {
    assert_true(
      refused(fn() raise { ignore(@ids.LanguageId::parse(text)) }).has_prefix(
        "frontend.invalid_language",
      ),
    )
    assert_true(
      refused(fn() raise { ignore(@ids.ProfileId::parse(text)) }).has_prefix(
        "frontend.invalid_profile",
      ),
    )
    assert_true(
      refused(fn() raise { ignore(@ids.BackendId::parse(text)) }).has_prefix(
        "frontend.invalid_backend",
      ),
    )
  }
}

///|
test "provider ids are bounded identifiers" {
  for text in ["finos/morphir-elm", "compiler", "rich"] {
    assert_eq(@ids.ProviderId::parse(text).to_string(), text)
  }
  for text in ["", "a\u0001b", "x".repeat(257)] {
    assert_true(
      refused(fn() raise { ignore(@ids.ProviderId::parse(text)) }).has_prefix(
        "frontend.invalid_provider",
      ),
    )
  }
}

///|
test "file extensions start with a dot and have no separators" {
  assert_eq(@ids.FileExtension::parse(".elm").to_string(), ".elm")
  assert_eq(@ids.FileExtension::parse(".tar.gz").to_string(), ".tar.gz")
  for text in ["", ".", "elm", "./x", ".a\\b", ".a:b", ".a\u0000"] {
    assert_true(
      refused(fn() raise { ignore(@ids.FileExtension::parse(text)) }).has_prefix(
        "frontend.invalid_extensions",
      ),
    )
  }
}

///|
test "source paths are relative with slash separators" {
  assert_eq(
    @ids.SourcePath::parse("My/Pkg/Api.elm").to_string(),
    "My/Pkg/Api.elm",
  )
  for
    text in [
      "", "/abs.elm", "a//b.elm", "./a.elm", "a/../b.elm", "a\\b.elm", "c:x.elm",
      "a/",
    ] {
    assert_true(
      refused(fn() raise { ignore(@ids.SourcePath::parse(text)) }).has_prefix(
        "frontend.invalid_source_path",
      ),
    )
  }
}

///|
test "module names keep their source syntax" {
  assert_eq(
    "Sub.Util" |> @ids.SourceModuleName::parse |> Show::to_string,
    "Sub.Util",
  )
  for text in ["", "A B", "A/B", "A\\B"] {
    assert_true(
      refused(fn() raise { ignore(@ids.SourceModuleName::parse(text)) }).has_prefix(
        "frontend.invalid_module",
      ),
    )
  }
}

///|
test "package names keep their spelling and give a canonical path" {
  let name = @ids.SourcePackageName::parse("Parity.Modules")
  assert_eq(name.to_string(), "Parity.Modules")
  assert_eq(name.to_path().to_canonical(), "parity/modules")
  assert_eq(
    @ids.SourcePackageName::parse("my/pkg").to_path().to_canonical(),
    "my/pkg",
  )
  for text in ["", "a\u0001"] {
    assert_true(
      refused(fn() raise { ignore(@ids.SourcePackageName::parse(text)) }).has_prefix(
        "frontend.invalid_package",
      ),
    )
  }
}

///|
test "canonical_path converts conventional spelling" {
  assert_eq(@ids.canonical_path("My.Pkg"), "my/pkg")
  assert_eq(@ids.canonical_path("parity/modules"), "parity/modules")
  assert_eq(@ids.canonical_path("HTTPServer"), "HTTP-server")
}
