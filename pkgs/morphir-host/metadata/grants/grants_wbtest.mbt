///|
fn a_grant_document() -> String {
  let digest = "sha256:" + "a".repeat(64)
  "{profile:\"morphir-metadata-host-grants-v1\",workspace:\"/work\",runtime:{node:\"/tools/node\",nodeSha256:\"" +
  digest +
  "\",helper:\"/tools/metadata.mjs\",helperBundleSha256:\"" +
  digest +
  "\"},projects:[{project:\"one\",service:\"/tools/service\",serviceSha256:\"" +
  digest +
  "\",policy:\"../trust/policy.json\",lock:\"../work/one/morphir.lock\",registry:\"/registry\",state:\"/state\"}]}"
}

///|
fn scope() -> @engine.ProjectMetadataScope {
  {
    workspace_root: "",
    project_root: "one",
    project_name: "one",
    request: @config.MetadataProviderRequest::SharedLocalRestore({
      service: { path: "/tools/service", origin: "one/morphir.toml", },
      policy: { path: "../../trust/policy.json", origin: "one/morphir.toml", },
      lock: { path: "morphir.lock", origin: "one/morphir.toml", },
      registry: { path: "/registry", origin: "one/morphir.toml", },
      state: { path: "/state", origin: "one/morphir.toml", },
      assurance: "portable",
      release: "example.com/morphir/naming@1.0.0",
    }),
  }
}

///|
fn refuses(run : () -> Unit raise) -> Unit raise {
  let refused = try {
    run()
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "grants resolve from their own file and selections from each config origin" {
  let grants = Grants::decode(
    @utf8.encode(a_grant_document()),
    IonText,
    "/config/grants.ion",
    "linux",
  )
  let selected = grants.select(scope(), "/work", "/invocation")
  assert_eq(selected.service, "/tools/service")
  assert_eq(selected.policy, "/trust/policy.json")
  assert_eq(selected.lock, "/work/one/morphir.lock")
  guard scope().request
    is @config.MetadataProviderRequest::SharedLocalRestore(request) else {
    fail("request")
  }
  let cli = {
    ..scope(),
    request: @config.MetadataProviderRequest::SharedLocalRestore({
      ..request,
      lock: { path: "../work/one/morphir.lock", origin: "CLI", },
    }),
  }
  assert_eq(grants.select(cli, "/work", "/invocation").lock, selected.lock)
  let global = {
    ..scope(),
    request: @config.MetadataProviderRequest::SharedLocalRestore({
      ..request,
      policy: { path: "policy.json", origin: "/trust/morphir.toml", },
    }),
  }
  assert_eq(
    grants.select(global, "/work", "/invocation").policy,
    selected.policy,
  )
}

///|
test "configuration cannot invent grants or borrow another project or workspace" {
  let grants = Grants::decode(
    @utf8.encode(a_grant_document()),
    IonText,
    "/config/grants.ion",
    "linux",
  )
  refuses(fn() raise {
    ignore(
      grants.select({ ..scope(), project_root: "two", }, "/work", "/invocation"),
    )
  })
  refuses(fn() raise {
    ignore(grants.select(scope(), "/different", "/invocation"))
  })
  guard scope().request
    is @config.MetadataProviderRequest::SharedLocalRestore(request) else {
    fail("request")
  }
  let cases : Array[@config.MetadataPath] = [
    { path: "/other/lock", origin: "one/morphir.toml", },
    { path: "morphir.lock", origin: "MORPHIR_METADATA_LOCK", },
  ]
  for path in cases {
    refuses(fn() raise {
      ignore(
        grants.select(
          {
            ..scope(),
            request: @config.MetadataProviderRequest::SharedLocalRestore({
              ..request,
              lock: path,
            }),
          },
          "/work",
          "/invocation",
        ),
      )
    })
  }
}

///|
test "closed grant shape and platform rules apply to every explicit format" {
  let value = @ion_text.read_ion(a_grant_document()[:])
  let bytes = @binary.write_binary_value(value)
  assert_eq(
    Grants::decode(bytes, IonBinary, "/config/grants.ionb", "linux").select(
      scope(),
      "/work",
      "/invocation",
    ).lock,
    "/work/one/morphir.lock",
  )
  let json = @ion_json.write_json(value)
  assert_eq(
    Grants::decode(@utf8.encode(json), Json, "/config/grants.json", "linux").select(
      scope(),
      "/work",
      "/invocation",
    ).state,
    "/state",
  )
  for
    source in [
      "{}",
      "{profile:\"unknown\"}",
      a_grant_document().replace(old="projects:", new="extra:0,projects:"),
      a_grant_document().replace(
        old="project:\"one\"",
        new="project:\"../two\"",
      ),
      a_grant_document().replace(old="nodeSha256:", new="nodeSha256:tag::"),
    ] {
    refuses(fn() raise {
      ignore(
        Grants::decode(
          @utf8.encode(source),
          IonText,
          "/config/grants.ion",
          "linux",
        ),
      )
    })
  }
  refuses(fn() raise {
    ignore(
      Grants::decode(
        @utf8.encode(a_grant_document()),
        IonText,
        "relative/grants.ion",
        "linux",
      ),
    )
  })
  refuses(fn() raise {
    ignore(
      Grants::decode(
        @utf8.encode(a_grant_document()),
        IonText,
        "/config/grants.ion",
        "wasi",
      ),
    )
  })
}

///|
test "Windows drive and UNC grants require fully qualified paths" {
  assert_eq(
    resolve("../trust/policy.json", "C:/config", Windows),
    "C:/trust/policy.json",
  )
  assert_eq(
    resolve("child/../policy.json", "//server/share/trust", Windows),
    "//server/share/trust/policy.json",
  )
  for path in ["C:relative", "/drive-relative", "\\drive-relative"] {
    refuses(fn() raise { ignore(resolve(path, "C:/config", Windows)) })
  }
  assert_eq(
    selection(
      { path: "morphir.lock", origin: "one/morphir.toml", },
      "C:/work",
      "C:/invocation",
      Windows,
    ),
    "C:/work/one/morphir.lock",
  )
}

///|
test "file origins include explicit JSON Ion and script configuration" {
  let grants = Grants::decode(
    @utf8.encode(a_grant_document()),
    IonText,
    "/config/grants.ion",
    "linux",
  )
  guard scope().request
    is @config.MetadataProviderRequest::SharedLocalRestore(request) else {
    fail("request")
  }
  for
    origin in [
      "one/settings.json", "one/settings.ion", "one/settings.ionb", "one/morphir.config.scm",
      "one/settings.yaml",
    ] {
    let selected = {
      ..scope(),
      request: @config.MetadataProviderRequest::SharedLocalRestore({
        ..request,
        lock: { path: "morphir.lock", origin, },
      }),
    }
    assert_eq(
      grants.select(selected, "/work", "/invocation").lock,
      "/work/one/morphir.lock",
    )
  }
}
