///|
/// The engine of the local worker: the built-in Scheme frontend and the MoonBit and Elm providers.
fn workbench_engine() -> @engine.Engine raise {
  let engine = @engine.Engine::new()
    ..register_source_provider(@moonbit_adapter.provider())
    ..register_source_provider(@elm_adapter.provider())
  engine
}

///|
/// A display name for the language picker. A language without one shows its id.
fn language_name(language : @ids.LanguageId) -> String {
  match language.to_string() {
    "scheme" => "Morphir Scheme"
    "moonbit" => "MoonBit"
    "elm" => "Elm"
    other => other
  }
}

///|
fn profile_json(profile : @engine.ProfileOffer) -> Json {
  let fields = [
    ("id", @wire.text(profile.id.to_string())),
    (
      "compileKind",
      @wire.text(
        match profile.compile {
          EachFile => "each-file"
          WholeProject => "whole-project"
        },
      ),
    ),
    ("evidence", @wire.text(profile.evidence.name())),
  ]
  match profile.capabilities {
    Some(c) => {
      fields.push(("displayName", @wire.text(c.summary)))
      fields.push(("supported", Json::array(c.supported.map(@wire.text))))
      fields.push(("excluded", Json::array(c.excluded.map(@wire.text))))
    }
    None => fields.push(("displayName", @wire.text(profile.id.to_string())))
  }
  @wire.obj(fields)
}

///|
/// Languages, providers and profiles come from the engine; a registered provider needs no other change.
fn catalog(engine : @engine.Engine) -> Json {
  let frontends = engine
    .languages()
    .map(offer => {
      let fields = [
        ("languageId", @wire.text(offer.language.to_string())),
        ("displayName", @wire.text(language_name(offer.language))),
        (
          "fileExtensions",
          Json::array(offer.extensions.map(e => @wire.text(e.to_string()))),
        ),
        ("irVersions", Json::array([@wire.text("4.0.0")])),
        ("compile", Json::boolean(true)),
        ("providerId", @wire.text(offer.provider.to_string())),
        ("profiles", Json::array(offer.profiles.map(profile_json))),
      ]
      if offer.default_profile is Some(profile) {
        fields.push(("defaultProfile", @wire.text(profile.to_string())))
      }
      @wire.obj(fields)
    })
  let targets : Array[Json] = [
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
  ]
  @wire.obj([
    ("success", Json::boolean(true)),
    ("frontends", Json::array(frontends)),
    ("targets", Json::array(targets)),
  ])
}
