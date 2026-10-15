///|
priv enum OutputMode {
  Human
  JSON
  JSONLines
}

///|
fn emit_record(kind : String, data : Json) -> Unit {
  println(
    Json::object(
      Map::from_array([("type", Json::string(kind)), ("data", data)]),
    ).stringify(),
  )
}

///|
fn emit_workspace(value : Json, mode : OutputMode) -> Unit {
  match mode {
    JSON => println(value.stringify())
    JSONLines => {
      guard value is Object(fields) else { return }
      let metadata : Map[String, Json] = Map([])
      for key, item in fields {
        if key != "projects" && key != "validated" {
          metadata[key] = item
        }
      }
      emit_record("workspace", Json::object(metadata))
      if fields.get("projects") is Some(Array(projects)) {
        for project in projects {
          emit_record("project", project)
        }
      }
    }
    Human => ()
  }
}

///|
fn emit_plan(
  sources : Array[String],
  destinations : Array[String],
  boundaries : Array[@engine.BoundarySelection],
  mode : OutputMode,
  components? : Array[@engine.ComponentBoundary] = [],
  frontends? : Array[@engine.SourceFrontendSelection] = [],
) -> Unit {
  if mode is Human && frontends.any(f => f.capabilities is Some(_)) {
    println(
      "Plan: " +
      sources.length().to_string() +
      " source(s), " +
      destinations.length().to_string() +
      " destination(s)",
    )
    for frontend in frontends {
      println(frontend.source + " -> unit " + frontend.unit_id)
      println(
        "  Language: " + frontend.language + "; provider: " + frontend.provider,
      )
      println(
        "  Profile: " +
        frontend.profile.unwrap_or("unspecified") +
        (if frontend.default_profile { " (default)" } else { "" }) +
        "; evidence: " +
        frontend.evidence.name(),
      )
      if frontend.capabilities is Some(c) {
        println(
          "  " +
          c.summary +
          "; documents per unit: " +
          documents_per_unit(c) +
          "; incremental: " +
          c.incremental.to_string(),
        )
        println("  Supports: " + c.supported.join("; "))
        println("  Excludes: " + c.excluded.join("; "))
        let names = c.limits.keys().collect()
        names.sort()
        println(
          "  Limits: " +
          names.map(k => k + "=" + c.limits[k].to_string()).join(", "),
        )
      }
    }
    for boundary in boundaries {
      println(
        "  " +
        boundary.source +
        ": " +
        boundary.input_format +
        " -> " +
        boundary.output_format,
      )
    }
    for component in components {
      println(
        "  Component: " +
        component.name +
        "; metadata: " +
        component.metadata_policy,
      )
    }
    for destination in destinations {
      println("  Destination: " + destination)
    }
  } else if mode is JSONLines {
    for frontend in frontends {
      emit_record("frontend", frontend_json(frontend))
    }
    for component in components {
      emit_record("component", component_json(component))
    }
    for boundary in boundaries {
      emit_record("boundary", boundary_json(boundary))
    }
    for path in sources {
      emit_record("source", Json::string(path))
    }
    for path in destinations {
      emit_record("destination", Json::string(path))
    }
    emit_record(
      "plan",
      Json::object(
        Map::from_array([
          ("sourceCount", Json::number(sources.length().to_double())),
          ("destinationCount", Json::number(destinations.length().to_double())),
        ]),
      ),
    )
  } else {
    // Retain the existing dry-run JSON output in human mode.
    println(
      Json::object(
        Map::from_array([
          ("frontends", Json::array(frontends.map(frontend_json))),
          ("boundaries", Json::array(boundaries.map(boundary_json))),
          ("components", Json::array(components.map(component_json))),
          ("sources", Json::array(sources.map(Json::string))),
          ("destinations", Json::array(destinations.map(Json::string))),
        ]),
      ).stringify(),
    )
  }
}

///|
fn emit_result(value : Json, mode : OutputMode) -> Unit {
  if mode is JSONLines {
    guard value is Object(fields) else { return }
    for
      (key, kind) in [
        ("frontends", "frontend"),
        ("boundaries", "boundary"),
        ("components", "component"),
        ("artifactDetails", "accepted"),
        ("projects", "generated"),
        ("validated", "validated"),
        ("diagnostics", "diagnostic"),
        ("warnings", "warning"),
        ("artifacts", "artifact"),
        ("committed", "committed"),
        ("publicationDetails", "published"),
      ] {
      if fields.get(key) is Some(Array(items)) {
        for item in items {
          emit_record(kind, item)
        }
      }
    }
    let summary : Map[String, Json] = Map([])
    for key, item in fields {
      if key != "diagnostics" &&
        key != "warnings" &&
        key != "artifacts" &&
        key != "committed" &&
        key != "publicationDetails" &&
        key != "boundaries" &&
        key != "components" &&
        key != "frontends" &&
        key != "artifactDetails" &&
        key != "projects" &&
        key != "validated" {
        summary[key] = item
      }
    }
    emit_record("result", Json::object(summary))
  } else {
    println(value.stringify())
  }
}

///|
fn print_error(message : String, mode : OutputMode) -> Unit {
  let value = Json::object(
    Map::from_array([
      ("successful", Json::boolean(false)),
      ("error", Json::string(message)),
      ("committed", Json::array([])),
    ]),
  )
  match mode {
    JSON => println(value.stringify())
    JSONLines => emit_record("error", value)
    Human => ()
  }
}

///|
fn boundary_json(boundary : @engine.BoundarySelection) -> Json {
  Json::object(
    Map::from_array([
      ("source", Json::string(boundary.source)),
      ("unitId", Json::string(boundary.unit_id)),
      ("inputFormat", Json::string(boundary.input_format)),
      ("outputFormat", Json::string(boundary.output_format)),
      (
        "profile",
        match boundary.profile {
          Some(p) => Json::string(p)
          None => Json::null()
        },
      ),
      ("readBytes", Json::boolean(boundary.read_bytes)),
      ("writeBytes", Json::boolean(boundary.write_bytes)),
    ]),
  )
}

///|
fn frontend_json(frontend : @engine.SourceFrontendSelection) -> Json {
  Json::object(
    Map::from_array([
      ("source", Json::string(frontend.source)),
      ("unitId", Json::string(frontend.unit_id)),
      ("frontend", Json::string(frontend.frontend)),
      ("language", Json::string(frontend.language)),
      ("provider", Json::string(frontend.provider)),
      ("defaultProfile", Json::boolean(frontend.default_profile)),
      (
        "availableProfiles",
        Json::array(frontend.available_profiles.map(Json::string)),
      ),
      ("evidence", Json::string(frontend.evidence.name())),
      (
        "capabilities",
        frontend.capabilities.map(capabilities_json).unwrap_or(Json::null()),
      ),
      (
        "profile",
        match frontend.profile {
          Some(p) => Json::string(p)
          None => Json::null()
        },
      ),
      (
        "dependencies",
        Json::object(
          frontend.dependencies.map(fn(_, version) { Json::string(version) }),
        ),
      ),
      ("outputContract", Json::string(frontend.output_contract)),
    ]),
  )
}

///|
fn artifact_json(artifact : @engine.ContentArtifact) -> Json {
  let (encoding, size) = match artifact.content {
    Text(text) => ("text", @utf8.encode(text).length())
    Binary(bytes) => ("binary", bytes.length())
  }
  Json::object(
    Map::from_array([
      ("path", Json::string(artifact.path)),
      ("source", Json::string(artifact.source)),
      ("format", Json::string(artifact.format)),
      ("encoding", Json::string(encoding)),
      ("bytes", Json::number(size.to_double())),
      ("status", Json::string("accepted")),
    ]),
  )
}

///|
fn project_json(project : @engine.LibraryProject) -> Json {
  Json::object(
    Map::from_array([
      ("id", Json::string(project.id)),
      ("source", Json::string(project.source)),
      ("root", Json::string(project.root)),
      ("members", Json::array(project.members.map(Json::string))),
      ("buildContract", Json::string(project.build_contract)),
      (
        "validation",
        Json::string(
          match project.policy {
            SourceOnly => "source-only"
            Required(_) => "required"
          },
        ),
      ),
      ("status", Json::string("generated")),
    ]),
  )
}

///|
fn validated_json(value : @host.ValidatedProject) -> Json {
  Json::object(
    Map::from_array([
      ("projectId", Json::string(value.project_id)),
      ("root", Json::string(value.root)),
      ("target", Json::string(value.target)),
      ("sourceIdentity", Json::string(value.source_identity)),
      ("receipt", Json::string(value.receipt)),
      ("status", Json::string("validated")),
      ("evidence", value.evidence),
    ]),
  )
}

///|
fn component_json(value : @engine.ComponentBoundary) -> Json {
  Json::object(
    Map::from_array([
      ("name", Json::string(value.name)),
      ("transport", Json::string(value.transport)),
      ("metadataPolicy", Json::string(value.metadata_policy)),
    ]),
  )
}

///|
fn capabilities_json(c : @engine.SourceCapabilities) -> Json {
  Json::object(
    Map::from_array([
      ("summary", Json::string(c.summary)),
      ("supported", Json::array(c.supported.map(Json::string))),
      ("excluded", Json::array(c.excluded.map(Json::string))),
      (
        "maxDocuments",
        match c.max_documents {
          Some(n) => Json::number(n.to_double())
          None => Json::null()
        },
      ),
      ("incremental", Json::boolean(c.incremental)),
      (
        "limits",
        Json::object(
          c.limits.map(fn(_, value) { Json::number(value.to_double()) }),
        ),
      ),
    ]),
  )
}

///|
/// The number of documents one unit can hold, as the CLI prints it. `None` is "no limit", never a number.
fn documents_per_unit(c : @engine.SourceCapabilities) -> String {
  match c.max_documents {
    Some(n) => n.to_string()
    None => "no limit"
  }
}

///|
fn warning_json(warning : @engine.Diagnostic) -> Json {
  let fields = Map::from_array([
    ("path", Json::string(warning.path)),
    ("stage", Json::string(warning.stage)),
    ("severity", Json::string("warning")),
    ("message", Json::string(warning.message)),
  ])
  if warning.details is Some(details) {
    fields["code"] = Json::string(details.code)
    fields["fix"] = Json::string(details.fix)
    fields["locations"] = Json::array(
      details.locations.map(loc => {
        Json::object(
          Map::from_array([
            ("owner", Json::string(loc.owner)),
            ("original", Json::string(loc.original)),
            ("allocated", Json::string(loc.allocated)),
            (
              "source",
              match loc.source {
                None => Json::null()
                Some(s) =>
                  Json::object(
                    Map::from_array([
                      ("startLine", Json::number(s.start_line.to_double())),
                      ("startColumn", Json::number(s.start_column.to_double())),
                      ("endLine", Json::number(s.end_line.to_double())),
                      ("endColumn", Json::number(s.end_column.to_double())),
                    ]),
                  )
              },
            ),
          ]),
        )
      }),
    )
  }
  Json::object(fields)
}
