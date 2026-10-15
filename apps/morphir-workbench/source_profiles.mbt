///|
priv struct CompiledSource {
  unit : @data.IRUnit
  profile : String
  provider : String
}

///|
fn source_constraint(request : Json, key : String) -> String? raise {
  match @wire.optional(request, key) {
    None => None
    Some(String(value)) => Some(value)
    _ => raise @scheme.Invalid("frontend.invalid_selection: " + key)
  }
}

///|
/// In-process selection uses the registered provider's defaults and callbacks.
fn compile_source(request : Json, source : String) -> CompiledSource raise {
  let provider = @moonbit_adapter.provider()
  if source_constraint(request, "frontendProvider") is Some(wanted) &&
    wanted != provider.id.to_string() {
    raise @scheme.Invalid("frontend.unknown_provider: " + wanted)
  }
  let language = provider.languages[0]
  let wanted = source_constraint(request, "frontendProfile").unwrap_or(
    language.default_profile.to_string(),
  )
  let offered = language.profiles.filter(profile => {
    profile.id.to_string() == wanted
  })
  if offered.is_empty() {
    raise @scheme.Invalid("frontend.unknown_profile: " + wanted)
  }
  let profile = offered[0]
  let run = match profile.compile {
    @engine.PerFile(run) => run
    @engine.PerProject(_) =>
      raise @scheme.Invalid(
        "frontend.unsupported_profile: " + profile.id.to_string(),
      )
  }
  let unit = run(
    {
      path: "main.mbt",
      relative_path: "main.mbt",
      content: source,
      package_name: "user",
      module_name: "main",
    },
    "main",
    fn() { false },
  )
  unit.validate(limits=profile.unit_limits)
  { unit, profile: profile.id.to_string(), provider: provider.id.to_string(), }
}

///|
/// Profiles and capability text come from the adapter, never a UI copy.
fn source_catalog() -> Json raise {
  let provider = @moonbit_adapter.provider()
  let language = provider.languages[0]
  let profiles = language.profiles.map(profile => {
    let c = profile.capabilities
    @wire.obj([
      ("id", @wire.text(profile.id.to_string())),
      ("displayName", @wire.text(c.summary)),
      ("supported", Json::array(c.supported.map(@wire.text))),
      ("excluded", Json::array(c.excluded.map(@wire.text))),
      ("evidence", @wire.text(profile.evidence.name())),
    ])
  })
  @wire.obj([
    ("success", Json::boolean(true)),
    (
      "frontends",
      Json::array([
        {
          "languageId": "scheme",
          "displayName": "Morphir Scheme",
          "fileExtensions": [".scm"],
          "irVersions": ["4.0.0"],
          "compile": true,
        },
        @wire.obj([
          ("languageId", @wire.text(language.id.to_string())),
          ("displayName", @wire.text("MoonBit")),
          (
            "fileExtensions",
            Json::array(language.extensions.map(e => @wire.text(e.to_string()))),
          ),
          ("irVersions", Json::array([@wire.text("4.0.0")])),
          ("compile", Json::boolean(true)),
          ("providerId", @wire.text(provider.id.to_string())),
          ("defaultProfile", @wire.text(language.default_profile.to_string())),
          ("profiles", Json::array(profiles)),
        ]),
      ]),
    ),
    (
      "targets",
      Json::array([
        {
          "target": "scheme",
          "displayName": "Scheme",
          "irVersions": ["4.0.0"],
          "generate": true,
        },
        {
          "target": "elm",
          "displayName": "Elm",
          "irVersions": ["4.0.0"],
          "generate": true,
        },
        {
          "target": "moonbit",
          "displayName": "MoonBit",
          "irVersions": ["4.0.0"],
          "generate": true,
        },
      ]),
    ),
  ])
}
