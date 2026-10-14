///|
fn configured_metadata() -> String {
  "[metadata]\nprovider='shared-local-restore'\nservice='tools/provider'\npolicy='trust/policy.json'\nlock='morphir.lock'\nregistry='registry'\nstate='trust/state'\nassurance='portable'\n[metadata.naming]\nrelease='example.com/morphir/naming@1.2.3'\n"
}

///|
fn metadata_error(text : String) -> String {
  try {
    ignore(
      @config.parse(text, origin="member/morphir.toml").metadata_provider_request(),
    )
    "unexpected success"
  } catch {
    @config.Invalid(message) => message
    other => other.to_string()
  }
}

///|
test "provider request defaults are disabled and preserve unrelated metadata" {
  assert_eq(@config.empty().metadata_provider_request(), @config.Disabled)
  assert_eq(
    @config.parse("[metadata]\nother={version=2}").metadata_provider_request(),
    @config.Disabled,
  )
  assert_eq(
    @config.parse("[metadata]\nprovider='none'").metadata_provider_request(),
    @config.Disabled,
  )
  for
    text in [
      "metadata=42", "[metadata]\nprovider=42", "[metadata]\nprovider='fixture'",
      "[metadata]\nservice='tools/provider'",
    ] {
    let error = metadata_error(text)
    assert_true(error.contains("metadata.invalid_configuration"))
    assert_true(error.contains("member/morphir.toml"))
  }
}

///|
test "provider requests retain each winning configuration origin without granting I/O" {
  let base = @config.parse(configured_metadata(), origin="member/morphir.toml")
  let overlay = @config.parse(
    "[metadata]\npolicy='/user/policy.json'\n[metadata.naming]\nrelease='example.com/morphir/naming@2.0.0'",
    origin="CLI",
  )
  let effective = @config.merge(base, overlay)
  guard effective.metadata_provider_request()
    is @config.SharedLocalRestore(request) else {
    fail("expected explicit restore selection")
  }
  assert_eq(request.policy.path, "/user/policy.json")
  assert_eq(request.policy.origin, "CLI")
  assert_eq(request.service.path, "tools/provider")
  assert_eq(request.service.origin, "member/morphir.toml")
  assert_eq(request.release, "example.com/morphir/naming@2.0.0")
  assert_eq(request.assurance, "portable")
  guard effective.value is @toml.TomlTable(fields) else { fail("table") }
  fields["metadata"] = @toml.TomlTable(Map([]))
  effective.provenance["metadata.policy"] = "later mutation"
  assert_eq(request.policy.path, "/user/policy.json")
  assert_eq(request.policy.origin, "CLI")
  assert_eq(request.release, "example.com/morphir/naming@2.0.0")
}

///|
test "shared restore requires all selections and refuses weaker or unsupported assurance" {
  for
    (key, value) in [
      ("service", "tools/provider"),
      ("policy", "trust/policy.json"),
      ("lock", "morphir.lock"),
      ("registry", "registry"),
      ("state", "trust/state"),
      ("assurance", "portable"),
    ] {
    let line = key + "='" + value + "'\n"
    let error = metadata_error(configured_metadata().replace(old=line, new=""))
    assert_true(error.contains("metadata." + key))
    assert_true(error.contains("is required"))
    assert_true(error.contains("member/morphir.toml"))
    let wrong = metadata_error(
      configured_metadata().replace(old=line, new=key + "=false\n"),
    )
    assert_true(wrong.contains("metadata." + key))
    assert_true(wrong.contains("member/morphir.toml"))
  }
  for assurance in ["hardened", "", "auto"] {
    let error = metadata_error(
      configured_metadata().replace(
        old="assurance='portable'",
        new="assurance='" + assurance + "'",
      ),
    )
    assert_true(error.contains("metadata.assurance"))
  }
}

///|
test "naming provider requires an authority-qualified exact stable release" {
  for
    release in [
      "example.com/morphir/naming@latest", "example.com/morphir/naming@1.2", "example.com/morphir/naming@01.2.3",
      "example.com/morphir/naming@1.2.3-beta.1", "morphir/naming@1.2.3", "example.com/morphir/naming@1.2.3@2.0.0",
      "example.com//naming@1.2.3", "EXAMPLE.com/naming@1.2.3", "example..com/naming@1.2.3",
      "example.com/name--space@1.2.3", "example.com/../naming@1.2.3", "example.com/morphir/naming@1.2.3.4",
      "example.com/morphir/naming@1.-2.3",
    ] {
    let error = metadata_error(
      configured_metadata().replace(
        old="example.com/morphir/naming@1.2.3",
        new=release,
      ),
    )
    assert_true(error.contains("metadata.naming.release"))
  }
  assert_true(
    metadata_error(
      configured_metadata().replace(
        old="release='example.com/morphir/naming@1.2.3'",
        new="",
      ),
    ).contains("is required"),
  )
}

///|
test "provider releases select publisher packages independently of IR names" {
  for
    release in [
      "example.com/morphir/naming@1.2.3", "registry.example.org/metadata/names@100000000000000000000000.0.0",
    ] {
    let document = @config.parse(
      configured_metadata().replace(
        old="example.com/morphir/naming@1.2.3",
        new=release,
      ),
      origin="member/morphir.toml",
    )
    document.validate()
    guard document.metadata_provider_request()
      is @config.SharedLocalRestore(request) else {
      fail("expected a shared restore request")
    }
    assert_eq(request.release, release)
  }
}
