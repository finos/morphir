///|
pub(all) struct LibraryBuildRequest {
  project : @engine.LibraryProject
  snapshot : String
  source_identity : String
  target : String
}

///|
pub(all) struct LibraryBuildLease {
  id : String
  build : (LibraryBuildRequest) -> Json raise
  dispose : () -> Unit raise
}

///|
/// A library build capability is separate from embedded package compilation.
pub(all) struct LibraryBuildProvider {
  contracts : Array[String]
  acquire : () -> LibraryBuildLease raise
}

///|
pub(all) struct ValidatedProject {
  project_id : String
  root : String
  target : String
  source_identity : String
  receipt : String
  evidence : Json
}

///|
fn build_field(value : Json, name : String) -> Json raise {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => raise @config.Invalid("build.invalid_evidence: Expected object")
  }
}

///|
fn build_text(value : Json, name : String) -> String raise {
  match build_field(value, name) {
    String(s) => s
    _ => raise @config.Invalid("build.invalid_evidence: Missing " + name)
  }
}

///|
fn digest_shape(value : String) -> Bool {
  value.length() == 64 &&
  value.to_array().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
fn project_snapshot(
  project : @engine.LibraryProject,
  artifacts : Array[@engine.ContentArtifact],
) -> String raise {
  let paths = project.members.copy()
  paths.sort()
  Json::array(
    paths.map(path => {
      let matches = artifacts.filter(a => a.path == path)
      if matches.length() != 1 {
        raise @config.Invalid("build.invalid_membership: " + path)
      }
      let relative = path[project.root.length() + 1:].to_owned()
      Json::array([
        Json::string(relative),
        match matches[0].content {
          Text(s) => Json::array([Json::string("text"), Json::string(s)])
          Binary(b) =>
            Json::array([
              Json::string("binary"),
              Json::array(
                b.to_array().map(v => Json::number(v.to_int().to_double())),
              ),
            ])
        },
      ])
    }),
  ).stringify()
}

///|
fn receipt_ion(value : Json) -> @ion.IonValue raise {
  // Evidence is deliberately restricted to strings, booleans, objects and arrays.
  match value {
    String(s) => @ion.IonValue::new(@ion.String(s))
    True => @ion.IonValue::new(@ion.Bool(true))
    False => @ion.IonValue::new(@ion.Bool(false))
    Array(xs) => @ion.IonValue::new(@ion.List(xs.map(receipt_ion)))
    Object(fields) => {
      let names = fields.keys().collect()
      names.sort()
      @ion.IonValue::new(
        @ion.Struct(names.map(n => @ion.Field::new(n, receipt_ion(fields[n])))),
      )
    }
    _ =>
      raise @config.Invalid(
        "build.invalid_evidence: Receipt contains unsupported data",
      )
  }
}

///|
fn validate_evidence(
  request : LibraryBuildRequest,
  lease : String,
  evidence : Json,
  compiler_version~ : String = @toolchain.compiler_version,
) -> Unit raise {
  if !(build_field(evidence, "successful") is True) ||
    !(build_field(evidence, "frozen") is True) ||
    build_text(evidence, "leaseId") != lease ||
    build_text(evidence, "projectId") != request.project.id ||
    build_text(evidence, "contract") != request.project.build_contract ||
    build_text(evidence, "sourceIdentity") != request.source_identity ||
    build_text(evidence, "target") != request.target {
    raise @config.Invalid(
      "build.evidence_mismatch: Build does not attest to the requested frozen project",
    )
  }
  if build_text(evidence, "compilerVersion") != compiler_version ||
    !digest_shape(build_text(evidence, "compilerIdentity")) ||
    !digest_shape(build_text(evidence, "coreIdentity")) ||
    !digest_shape(build_text(evidence, "buildIdentity")) {
    raise @config.Invalid(
      "build.toolchain_mismatch: Pinned compiler and identified matching core are required",
    )
  }
  let deps = match build_field(evidence, "dependencies") {
    Array(items) => items
    _ => raise @config.Invalid("build.unresolved_dependency")
  }
  if deps.length() != request.project.dependencies.length() {
    raise @config.Invalid(
      "build.unresolved_dependency: Dependency evidence count differs",
    )
  }
  let seen = Map([])
  for dep in deps {
    let name = build_text(dep, "moduleName")
    if seen.contains(name) || !digest_shape(build_text(dep, "sourceIdentity")) {
      raise @config.Invalid(
        "build.unresolved_dependency: Invalid source identity",
      )
    }
    seen[name] = true
    if !request.project.dependencies.any(required => {
        required.module_name == name &&
        required.version == build_text(dep, "version") &&
        required.semantic_pin == build_text(dep, "semanticPin") &&
        required.api_profile == build_text(dep, "apiProfile")
      }) {
      raise @config.Invalid("build.unresolved_dependency: " + name)
    }
  }
}

///|
fn Host::validate_libraries(
  self : Host,
  report : @engine.ContentReport,
) -> Array[ValidatedProject] raise {
  let validated = []
  let receipts = []
  let leases = Map([])
  for project in report.projects {
    guard project.policy is @engine.Required(target) else { continue }
    if (self.cancelled)() {
      raise @config.Invalid("Cancelled")
    }
    let provider = match self.library_build {
      Some(p) => p
      None =>
        raise @config.Invalid(
          "build.provider_required: Configure a library build provider",
        )
    }
    if !provider.contracts.contains(project.build_contract) {
      raise @config.Invalid(
        "build.unsupported_contract: Provider cannot build " +
        project.build_contract,
      )
    }
    let receipt = project.root + "/build-receipt.ionb"
    if report.artifacts.any(a => a.path == receipt) {
      raise @config.Invalid("build.receipt_collision")
    }
    let snapshot = project_snapshot(project, report.artifacts)
    let source_identity = @identity.sha256(@utf8.encode(snapshot))
    let request : LibraryBuildRequest = {
      project: {
        ..project,
        members: project.members.copy(),
        dependencies: project.dependencies.copy(),
      },
      snapshot,
      source_identity,
      target,
    }
    let lease = (provider.acquire)()
    let mut failure : String? = None
    let mut evidence : Json? = None
    try {
      if lease.id == "" || leases.contains(lease.id) {
        raise @config.Invalid("build.invalid_lease")
      }
      leases[lease.id] = true
      (self.event)(Phase("build " + project.root))
      let result = (lease.build)(request)
      if (self.cancelled)() {
        raise @config.Invalid("Cancelled")
      }
      validate_evidence(request, lease.id, result)
      if project_snapshot(project, report.artifacts) != snapshot {
        raise @config.Invalid(
          "build.source_changed: Source changed during validation",
        )
      }
      evidence = Some(result)
    } catch {
      error => failure = Some(error_message(error))
    }
    (lease.dispose)() catch {
      error =>
        failure = Some(
          failure.unwrap_or("") +
          " build.cleanup_failed: " +
          error_message(error),
        )
    }
    if failure is Some(message) {
      raise @config.Invalid(message)
    }
    if (self.cancelled)() {
      raise @config.Invalid("Cancelled")
    }
    let evidence = evidence.unwrap()
    let fields = match evidence {
      Object(fields) => fields.copy()
      _ => abort("checked evidence")
    }
    fields["profile"] = Json::string("morphir-library-build-v1")
    let bytes = @ion_binary.write_binary_value(
      receipt_ion(Json::object(fields)).with_annotation(
        @ion.SymbolToken::new("morphir_library_build"),
      ),
    )
    receipts.push(@engine.ContentArtifact::{
      path: receipt,
      source: project.source,
      content: @data.Binary(bytes),
      format: "ion-binary",
    })
    validated.push({
      project_id: project.id,
      root: project.root,
      target,
      source_identity,
      receipt,
      evidence,
    })
  }
  // No receipt or publication appears until every required build and disposal succeeds.
  for receipt in receipts {
    report.artifacts.push(receipt)
  }
  validated
}

///|
/// Explicit process adapter. The supplied helper implements library-build-v1.
pub fn LibraryBuildProvider::process(
  program : String,
  helper : String,
  compiler_home : String,
  dependencies : Map[String, String],
  timeout~ : Int32 = 120000,
) -> LibraryBuildProvider raise {
  if !@platform.process_supported() ||
    program == "" ||
    helper == "" ||
    compiler_home == "" ||
    timeout < 1 ||
    timeout > 600000 {
    raise @config.Invalid(
      "build.provider_required: Process, helper, compiler home and bounded timeout are required",
    )
  }
  let supplied = dependencies.copy()
  {
    contracts: ["moonbit-library-v1"],
    acquire: fn() raise {
      let directory = @platform.temporary()
      let request_path = directory + "/request.json"
      let id = @identity.sha256(@utf8.encode(directory))
      {
        id,
        build: fn(request) raise {
          let fields = Map::from_array([
            (
              "timeout",
              Json::number(
                (if timeout < 10 { 1 } else { timeout * 9 / 10 }).to_double(),
              ),
            ),
            ("leaseId", Json::string(id)),
            ("projectId", Json::string(request.project.id)),
            ("contract", Json::string(request.project.build_contract)),
            ("snapshot", Json::string(request.snapshot)),
            ("sourceIdentity", Json::string(request.source_identity)),
            ("target", Json::string(request.target)),
            ("compilerHome", Json::string(compiler_home)),
            (
              "suppliedDependencies",
              Json::object(supplied.map(fn(_, path) { Json::string(path) })),
            ),
            (
              "dependencies",
              Json::array(
                request.project.dependencies.map(d => {
                  Json::object(
                    Map::from_array([
                      ("moduleName", Json::string(d.module_name)),
                      ("version", Json::string(d.version)),
                      ("apiProfile", Json::string(d.api_profile)),
                      ("semanticPin", Json::string(d.semantic_pin)),
                    ]),
                  )
                }),
              ),
            ),
          ])
          @platform.write(request_path, Json::object(fields).stringify())
          let result = @platform.process(
            program,
            [helper, request_path],
            @platform.cwd(),
            "",
            timeout,
          )
          if build_field(result, "exitCode") != Json::number(0.0) {
            raise @config.Invalid(
              (if build_field(result, "exitCode") == Json::number(124.0) {
                "build.deadline: "
              } else {
                "build.compiler_failed: "
              }) +
              build_text(result, "stderr"),
            )
          }
          let output = build_text(result, "stdout")
          if output.length() > 1048576 {
            raise @config.Invalid("build.output_limit")
          }
          @wire.parse(output)
        },
        dispose: fn() raise { dispose_build_tree(directory) },
      }
    },
  }
}

///|
fn dispose_build_tree(path : String) -> Unit raise {
  match @platform.kind(path) {
    0 => ()
    2 => {
      for child in @platform.list(path) {
        if child == "" ||
          child == "." ||
          child == ".." ||
          child.contains("/") ||
          child.contains("\\") {
          raise @config.Invalid("build.invalid_cleanup_path")
        }
        dispose_build_tree(path + "/" + child)
      }
      @platform.remove_dir(path)
    }
    _ => @platform.remove_file(path)
  }
}
