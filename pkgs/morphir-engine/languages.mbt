///|
/// How a profile compiles, without its callback: one unit for each file, or one unit for the whole project.
pub(all) enum CompileKind {
  EachFile
  WholeProject
} derive(Eq, Debug)

///|
pub extend CompileKind with Eq::{equal, not_equal}

///|
pub extend CompileKind with @debug.Debug::{to_repr}

///|
/// A source profile without its compile callback. `capabilities` and `unit_limits` are `None` for a frontend from
/// `register_frontend`.
pub(all) struct ProfileOffer {
  id : @ids.ProfileId
  compile : CompileKind
  capabilities : SourceCapabilities?
  evidence : SourceEvidence
  unit_limits : @data.Limits?
}

///|
/// One source language that one provider offers. Two providers of one language give two offers; planning then
/// needs `frontend.provider`.
pub(all) struct LanguageOffer {
  language : @ids.LanguageId
  provider : @ids.ProviderId
  extensions : Array[@ids.FileExtension]
  default_profile : @ids.ProfileId?
  profiles : Array[ProfileOffer]
}

///|
fn kind(compile : SourceCompile) -> CompileKind {
  match compile {
    PerFile(_) => EachFile
    PerProject(_) => WholeProject
  }
}

///|
/// The offer of a frontend from `register_frontend` or `register_unit_frontend`. Their names are not typed yet
/// (`morphir-ukvn.5.32`), so a name that is not a valid id gives no offer.
fn Frontend::offer(self : Frontend, name : String) -> LanguageOffer? {
  try {
    let extensions = []
    for e in self.extensions {
      extensions.push(@ids.FileExtension::parse(e))
    }
    let (compile, unit_limits) = match self.compiler {
      FileCompiler(_) => (EachFile, None)
      UnitCompiler(_, limits) => (EachFile, Some(limits))
      ProjectCompiler(_, limits) => (WholeProject, Some(limits))
    }
    let default_profile = match self.profile {
      Some(text) => Some(@ids.ProfileId::parse(text))
      None => None
    }
    let profiles : Array[ProfileOffer] = match default_profile {
      Some(id) =>
        [
          {
            id,
            compile,
            capabilities: self.capabilities.map(c => c.snapshot()),
            evidence: self.evidence,
            unit_limits,
          },
        ]
      None => []
    }
    Some({
      language: @ids.LanguageId::parse(name),
      provider: @ids.ProviderId::parse(self.provider),
      extensions,
      default_profile,
      profiles,
    })
  } catch {
    _ => None
  }
}

///|
/// Every source language the engine can compile: registered providers, and frontends from `register_frontend`
/// and `register_unit_frontend`, including the built-in `scheme`. The `ir-json` frontend and the data formats are
/// not source languages. One offer per language and provider, sorted by language, then provider. No offer holds a
/// compile callback, so the list is safe to give to any caller and to convert to JSON.
pub fn Engine::languages(self : Engine) -> Array[LanguageOffer] {
  let offers : Array[LanguageOffer] = []
  for _, provider in self.source_providers {
    for language in provider.languages {
      offers.push({
        language: language.id,
        provider: provider.id,
        extensions: language.extensions.copy(),
        default_profile: Some(language.default_profile),
        profiles: language.profiles.map(p => {
          (
            {
              id: p.id,
              compile: kind(p.compile),
              capabilities: Some(p.capabilities.snapshot()),
              evidence: p.evidence,
              unit_limits: Some(p.unit_limits),
            } : ProfileOffer)
        }),
      })
    }
  }
  for name, frontend in self.frontends {
    if name == "ir-json" || self.data_formats.contains(name) {
      continue
    }
    if frontend.offer(name) is Some(offer) {
      offers.push(offer)
    }
  }
  offers.sort_by((a, b) => {
    let by_language = a.language.compare(b.language)
    if by_language != 0 {
      by_language
    } else {
      a.provider.compare(b.provider)
    }
  })
  offers
}
