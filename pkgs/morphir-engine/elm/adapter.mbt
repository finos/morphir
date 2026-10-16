///|
pub const PROVIDER : String = "finos/morphir-elm"

///|
pub const PROFILE : String = "library"

///|
/// Parses a constant that cannot fail, because `provider()` does not raise.
fn[T, E : Error] constant(parse : (String) -> T raise E, text : String) -> T {
  parse(text) catch {
    _ => abort("invalid constant: " + text)
  }
}

///|
/// The unit limits of the Elm provider. One unit holds a whole project, so the byte budget is larger than the
/// default of `@data.Limits`. The depth and value budgets are the identity limits of `@identities.nodes` (depth
/// 128, 100000 nodes): `IRUnit::validate` applies them whatever the unit limits are, so a larger budget here would
/// not be reachable (`morphir-ukvn.5.22.3.24`). The checkpoint backend encodes with the limits of its codec registry.
pub fn default_unit_limits() -> @data.Limits {
  { max_bytes: 16 * 1024 * 1024, max_depth: 128, max_values: 100000, }
}

///|
/// The Elm provider: language `elm`, extension `.elm`, profile `library`. The profile compiles every Elm module of
/// a project to one unit with `@frontend.compile_project`, keeping every module that the output names
/// (`Referenced`), so that generated code builds. The project name is the dotted package name and
/// `exposed_modules` holds the exposed modules relative to the package, as in `morphir.json`.
pub fn provider(
  unit_limits~ : @data.Limits = default_unit_limits(),
) -> @engine.SourceProvider {
  let library : @engine.SourceProfile = {
    id: constant(@ids.ProfileId::parse, PROFILE),
    dependencies: { "moonrockz/krueger": "0.5.0" },
    evidence: @engine.LocalAcceptance,
    unit_limits,
    capabilities: {
      summary: "Elm 0.19.1 project",
      max_documents: None,
      incremental: false,
      supported: [
        "Elm 0.19.1 modules of one package", "elm/core modules that the Morphir SDK covers",
        "Morphir.SDK modules", "Type inference of every value and pattern",
      ],
      excluded: [
        "Ports, effect modules and GLSL", "Debug and infix declarations", "Third-party Elm packages",
        "morphir.json dependencies",
      ],
      limits: {
        "unitBytes": unit_limits.max_bytes,
        "unitDepth": unit_limits.max_depth,
        "unitValues": unit_limits.max_values,
      },
    },
    compile: @engine.PerProject(fn(project, unit_id, cancelled) raise {
      if cancelled() {
        raise @engine.Rejected("elm.cancelled", "Cancelled", None)
      }
      let sources = project.sources.map(s => {
        ({ path: s.relative_path, content: s.content, } : @frontend.ElmSource)
      })
      let file = @frontend.compile_project(
        sources,
        project.package_name.to_string(),
        project.exposed_modules.map(m => m.to_string()),
        output=Referenced,
      ) catch {
        @frontend.ElmFailed(problems) =>
          raise @engine.RejectedSources(
            problems.map(p => {
              (
                {
                  code: p.code,
                  detail: p.message,
                  path: p.path,
                  location: p.location,
                } : @engine.SourceProblem)
            }),
          )
      }
      @data.IRUnit::new(unit_id, file)
    }),
  }
  {
    id: constant(@ids.ProviderId::parse, PROVIDER),
    languages: [
      {
        id: constant(@ids.LanguageId::parse, "elm"),
        extensions: [constant(@ids.FileExtension::parse, ".elm")],
        default_profile: constant(@ids.ProfileId::parse, PROFILE),
        profiles: [library],
      },
    ],
  }
}

///|
/// Registers the Elm provider. The engine core does not register it by default.
pub fn register(
  engine : @engine.Engine,
  unit_limits~ : @data.Limits = default_unit_limits(),
) -> Unit raise {
  engine.register_source_provider(provider(unit_limits~))
}
