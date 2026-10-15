///|
/// Evidence for local source claims, separate from ecosystem MCK verification.
pub(all) enum SourceEvidence {
  Declared
  LocalAcceptance
}

///|
pub fn SourceEvidence::name(self : SourceEvidence) -> String {
  match self {
    Declared => "declared"
    LocalAcceptance => "local-acceptance"
  }
}

///|
/// Every source file of one language in a project, for a `PerProject` profile. `package_name` and
/// `exposed_modules` are as written in the project configuration (`project.name` and `project.exposed_modules`);
/// `exposed_modules` is empty when the key is missing. The sources are in path order.
pub(all) struct ProjectSources {
  package_name : @ids.SourcePackageName
  exposed_modules : Array[@ids.SourceModuleName]
  sources : Array[Source]
}

///|
/// How a source profile compiles. `PerFile` compiles each source file to its own unit; the callback gets the
/// source, the unit id and the cancellation check. `PerProject` compiles every source file of a project to one
/// unit, in one call; the unit id is the canonical project name.
pub(all) enum SourceCompile {
  PerFile((Source, String, () -> Bool) -> @data.IRUnit raise)
  PerProject((ProjectSources, String, () -> Bool) -> @data.IRUnit raise)
}

///|
/// `max_documents` is the number of source documents one unit can hold; `None` means no limit.
/// Source behavior descriptions are not an IR feature vocabulary or wire protocol.
pub(all) struct SourceCapabilities {
  summary : String
  supported : Array[String]
  excluded : Array[String]
  max_documents : Int?
  incremental : Bool
  limits : Map[String, Int]
}

///|
pub(all) struct SourceProfile {
  id : @ids.ProfileId
  capabilities : SourceCapabilities
  evidence : SourceEvidence
  dependencies : Map[String, String]
  compile : SourceCompile
  unit_limits : @data.Limits
}

///|
pub(all) struct SourceLanguage {
  id : @ids.LanguageId
  extensions : Array[@ids.FileExtension]
  default_profile : @ids.ProfileId
  profiles : Array[SourceProfile]
}

///|
pub(all) struct SourceProvider {
  id : @ids.ProviderId
  languages : Array[SourceLanguage]
}

///|
fn source_constraint(text : String, kind : String) -> String raise {
  if text == "" ||
    text.length() > 256 ||
    text.to_array().any(c => c.to_int() < 32 || c.to_int() == 127) {
    raise @configuration.Invalid(
      "frontend.invalid_" + kind + ": Expected a bounded nonempty identifier",
    )
  }
  text
}

///|
fn SourceCapabilities::snapshot(
  self : SourceCapabilities,
) -> SourceCapabilities {
  {
    ..self,
    supported: self.supported.copy(),
    excluded: self.excluded.copy(),
    limits: self.limits.copy(),
  }
}

///|
/// Explicit in-process claims; registration and planning never invoke compilers.
pub fn Engine::register_source_provider(
  self : Engine,
  provider : SourceProvider,
) -> Unit raise {
  let provider_id = provider.id.to_string()
  if self.source_providers.contains(provider_id) ||
    self.frontends.contains(provider_id) {
    raise @configuration.Invalid(
      "frontend.registration_conflict: " + provider_id,
    )
  }
  if provider.languages.is_empty() || provider.languages.length() > 64 {
    raise @configuration.Invalid("frontend.invalid_languages: " + provider_id)
  }
  let languages = []
  let seen_languages : Map[@ids.LanguageId, Bool] = Map([])
  for language in provider.languages {
    let language_id = language.id.to_string()
    if seen_languages.contains(language.id) ||
      self.data_formats.contains(language_id) ||
      language_id == "ir-json" {
      raise @configuration.Invalid("frontend.invalid_language: " + language_id)
    }
    seen_languages[language.id] = true
    if language.extensions.is_empty() || language.extensions.length() > 64 {
      raise @configuration.Invalid(
        "frontend.invalid_extensions: " + language_id,
      )
    }
    if language.profiles.is_empty() || language.profiles.length() > 64 {
      raise @configuration.Invalid("frontend.invalid_profiles: " + provider_id)
    }
    let seen : Map[@ids.ProfileId, Bool] = Map([])
    let profiles = []
    for profile in language.profiles {
      if seen.contains(profile.id) {
        raise @configuration.Invalid(
          "frontend.duplicate_profile: " + profile.id.to_string(),
        )
      }
      seen[profile.id] = true
      let c = profile.capabilities
      ignore(source_constraint(c.summary, "capabilities"))
      // No limit is the default. A declared limit is a positive number, with no upper bound.
      let documents_valid = match c.max_documents {
        Some(n) => n > 0
        None => true
      }
      if !documents_valid ||
        c.supported.length() > 64 ||
        c.excluded.length() > 64 ||
        c.limits.length() > 64 ||
        profile.dependencies.length() > 64 {
        raise @configuration.Invalid(
          "frontend.invalid_capabilities: " + profile.id.to_string(),
        )
      }
      for text in c.supported + c.excluded {
        ignore(source_constraint(text, "capabilities"))
      }
      for key, value in c.limits {
        ignore(source_constraint(key, "limits"))
        if value < 0 {
          raise @configuration.Invalid(
            "frontend.invalid_limits: " + profile.id.to_string(),
          )
        }
      }
      for key, value in profile.dependencies {
        ignore(source_constraint(key, "dependency"))
        ignore(source_constraint(value, "dependency"))
      }
      let limits = profile.unit_limits
      if limits.max_bytes <= 0 || limits.max_depth < 0 || limits.max_values <= 0 {
        raise @configuration.Invalid(
          "frontend.invalid_limits: " + profile.id.to_string(),
        )
      }
      profiles.push({
        ..profile,
        capabilities: c.snapshot(),
        dependencies: profile.dependencies.copy(),
      })
    }
    if !seen.contains(language.default_profile) {
      raise @configuration.Invalid(
        "frontend.unknown_default_profile: " +
        language.default_profile.to_string(),
      )
    }
    languages.push({
      ..language,
      profiles,
      extensions: language.extensions.copy(),
    })
  }
  self.source_providers[provider_id] = { ..provider, languages, }
}

///|
fn Engine::select_source_frontend(
  self : Engine,
  settings : Config,
) -> Frontend? raise {
  let language = settings.frontend
  let legacy = self.frontends.get(language)
  let offers : Map[String, SourceLanguage] = Map([])
  for id, provider in self.source_providers {
    for offered in provider.languages {
      if offered.id.to_string() == language {
        offers[id] = offered
      }
    }
  }
  let ids = offers.keys().collect()
  if legacy is Some(frontend) {
    if self.source_providers.contains(frontend.provider) {
      raise @configuration.Invalid(
        "frontend.registration_conflict: " + frontend.provider,
      )
    }
    ids.push(frontend.provider)
  }
  ids.sort()
  let id = match settings.frontend_provider {
    Some(wanted) => {
      if !ids.contains(wanted) {
        let code = if self.source_providers.contains(wanted) ||
          self.frontends.contains(wanted) {
          "provider_language_mismatch"
        } else {
          "unknown_provider"
        }
        raise @configuration.Invalid(
          "frontend." +
          code +
          ": " +
          wanted +
          " for language " +
          language +
          "; available " +
          ids.join(", "),
        )
      }
      wanted
    }
    None => {
      if ids.is_empty() {
        return None
      }
      if ids.length() != 1 {
        raise @configuration.Invalid(
          "frontend.ambiguous_provider: " +
          language +
          "; choose " +
          ids.join(", "),
        )
      }
      ids[0]
    }
  }
  if offers.get(id) is Some(offered) {
    let available = offered.profiles.map(p => p.id.to_string())
    available.sort()
    let wanted = settings.frontend_profile.unwrap_or(
      offered.default_profile.to_string(),
    )
    let profiles = offered.profiles.filter(p => p.id.to_string() == wanted)
    if profiles.is_empty() {
      raise @configuration.Invalid(
        "frontend.unknown_profile: " +
        wanted +
        " for provider " +
        id +
        " and language " +
        language +
        "; available " +
        available.join(", "),
      )
    }
    let profile = profiles[0]
    return Some({
      extensions: offered.extensions.map(e => e.to_string()),
      compiler: match profile.compile {
        PerFile(run) => UnitCompiler(run, profile.unit_limits)
        PerProject(run) => ProjectCompiler(run, profile.unit_limits)
      },
      provider: id,
      profile: Some(profile.id.to_string()),
      default_profile: profile.id == offered.default_profile,
      available_profiles: available,
      capabilities: Some(profile.capabilities.snapshot()),
      dependencies: profile.dependencies.copy(),
      evidence: profile.evidence,
    })
  }
  let frontend = legacy.unwrap()
  if settings.frontend_profile is Some(wanted) &&
    frontend.profile != Some(wanted) {
    raise @configuration.Invalid(
      "frontend.unknown_profile: " +
      wanted +
      " for provider " +
      id +
      "; available " +
      frontend.available_profiles.join(", "),
    )
  }
  Some(frontend)
}
