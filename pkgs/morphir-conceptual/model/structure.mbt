///|
fn validate_digest(r : Record) -> Unit raise ModelError {
  if text(r, "algorithm") != "sha256" {
    fail("conceptual.invalid_record", r.path + "/algorithm")
  }
  let value = text(r, "value")
  if value.length() != 64 ||
    !value.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
    fail("conceptual.invalid_record", r.path + "/value")
  }
}

///|
fn resolved_reference(r : Record) -> ResolvedRef raise ModelError {
  match reference(r) {
    Resolved(value) => value
    Unresolved(_, _, _) => {
      fail("conceptual.invalid_variant", r.path)
      abort("unreachable")
    }
  }
}

///|
fn forbid(r : Record, names : Array[String]) -> Unit raise ModelError {
  for name in names {
    if r.fields.contains(name) {
      fail("conceptual.invalid_variant", r.path + "/" + name)
    }
  }
}

///|
fn trait_interpretation(r : Record) -> TraitInterpretation raise ModelError {
  match text(r, "kind") {
    "descriptive" => {
      forbid(r, ["profiles"])
      Descriptive
    }
    "semantic" => {
      let profiles = strings(r, "profiles")
      let seen : Map[String, Bool] = Map([])
      if profiles.is_empty() {
        fail("conceptual.invalid_record", r.path + "/profiles")
      }
      for p in profiles {
        if seen.contains(p) {
          fail("conceptual.invalid_record", r.path + "/profiles")
        }
        seen[p] = true
      }
      Semantic(
        profiles.map(p => {
          @intent.Id::parse(p) catch {
            _ => abort("validated identifier")
          }
        }),
      )
    }
    _ => {
      fail("conceptual.unsupported_variant", r.path + "/kind")
      abort("unreachable")
    }
  }
}

///|
fn trait_target(r : Record) -> TraitTarget raise ModelError {
  match text(r, "kind") {
    "model" => {
      forbid(r, ["ref", "artifact", "node", "profile"])
      ModelTarget(snapshot(child(r, "model")))
    }
    "module" => {
      forbid(r, ["ref", "model", "profile"])
      ModuleTarget(
        snapshot(child(r, "artifact")),
        text(r, "node", nonempty=true),
      )
    }
    "concept" | "type" | "member" | "function" as name => {
      forbid(r, ["model", "artifact", "node", "profile"])
      let kind = match name {
        "concept" => ConceptTarget
        "type" => TypeTarget
        "member" => MemberTarget
        _ => FunctionTarget
      }
      EntityTarget(kind, reference(child(r, "ref")))
    }
    "operation" | "serviceBinding" as name => {
      forbid(r, ["model", "artifact", "node"])
      ProfileTarget(
        if name == "operation" {
          OperationTarget
        } else {
          ServiceBindingTarget
        },
        id(r, "profile"),
        reference(child(r, "ref")),
      )
    }
    _ => UnknownTarget(r)
  }
}

///|
fn validate_concern(c : Record, name : String) -> Unit raise ModelError {
  let state = text(c, "state")
  match name {
    "implementation" =>
      match state {
        "unbound" => forbid(c, ["binding"])
        "bound" =>
          if reference(child(c, "binding")) is Unresolved(_, _, _) {
            fail("conceptual.invalid_variant", c.path + "/binding")
          }
        _ => fail("conceptual.unsupported_variant", c.path + "/state")
      }
    "elaboration" =>
      match state {
        "open" => {
          forbid(c, ["rationale"])
          if items(c, "aspects").is_empty() {
            fail("conceptual.invalid_record", c.path + "/aspects")
          }
        }
        "settled" => {
          forbid(c, ["aspects"])
          ignore(text(c, "rationale"))
        }
        _ => fail("conceptual.unsupported_variant", c.path + "/state")
      }
    "definition" =>
      match state {
        "completeSpecification" | "completeDefinition" =>
          forbid(c, ["reason", "sourceRefs"])
        "authoredPartial" => {
          ignore(text(c, "reason"))
          ignore(items(c, "sourceRefs"))
        }
        _ => fail("conceptual.unsupported_variant", c.path + "/state")
      }
    "recovery" =>
      match state {
        "clean" => forbid(c, ["sourceRef", "diagnostics"])
        "recovering" => {
          ignore(child(c, "sourceRef"))
          if items(c, "diagnostics").is_empty() {
            fail("conceptual.invalid_record", c.path + "/diagnostics")
          }
        }
        _ => fail("conceptual.unsupported_variant", c.path + "/state")
      }
    "review" => {
      ignore(revision(c, "entityRevision"))
      ignore(revision(c, "modelRevision"))
      match state {
        "unreviewed" | "pending" => forbid(c, ["reviewer", "rationale"])
        "accepted" | "rejected" => {
          ignore(id(c, "reviewer"))
          ignore(text(c, "rationale"))
        }
        _ => fail("conceptual.unsupported_variant", c.path + "/state")
      }
    }
    _ => ()
  }
}

///|
fn tracked_snapshot(
  r : Record,
  records : Array[Record],
) -> Snapshot raise ModelError {
  let result = snapshot(r)
  records.push(r)
  result
}

///|
fn context_records(
  r : Record,
  records : Array[Record],
) -> Unit raise ModelError {
  records.push(r)
  ignore(tracked_snapshot(child(r, "model"), records))
  for name in ["entities", "sources", "implementations"] {
    let seen : Map[String, Bool] = Map([])
    for item in record_list(r, name) {
      let identity = tracked_snapshot(item, records)
      if seen.contains(identity.id.value()) {
        fail("conceptual.duplicate_identity", item.path + "/id")
      }
      seen[identity.id.value()] = true
    }
  }
}

///|
fn exact_nat(
  r : Record,
  name : String,
  positive~ : Bool = false,
) -> Unit raise ModelError {
  let v = required(r, name)
  match v.kind() {
    Int(n) if !v.has_annotations() &&
      !n.to_string().has_prefix("-") &&
      (!positive || n.to_string() != "0") => ()
    _ => fail("conceptual.invalid_record", r.path + "/" + name)
  }
}

///|
fn producer(r : Record, records : Array[Record]) -> Unit raise ModelError {
  ignore(id(r, "id"))
  ignore(text(r, "version", nonempty=true))
  ignore(id(r, "profile"))
  records.push(r)
}

///|
fn content_records(
  kind : EntityKind,
  c : Record,
  records : Array[Record],
) -> Unit raise ModelError {
  match kind {
    Claim | Evidence => context_records(child(c, "context"), records)
    _ => ()
  }
  match kind {
    Declaration => {
      let role = text(c, "role")
      if !["function", "type", "field", "parameter", "result"].contains(role) {
        fail("conceptual.unsupported_variant", c.path + "/role")
      }
      if role == "function" || role == "type" {
        ignore(strings(c, "typeParameters"))
      }
      if c.fields.contains("representation") {
        let r = child(c, "representation")
        records.push(r)
        match text(r, "state") {
          "known" => {
            forbid(r, ["reason"])
            ignore(required(r, "type"))
            if !["public", "defining-module"].contains(text(r, "access")) {
              fail("conceptual.unsupported_variant", r.path + "/access")
            }
          }
          "undecided" => {
            forbid(r, ["type", "access"])
            ignore(text(r, "reason"))
          }
          _ => fail("conceptual.unsupported_variant", r.path + "/state")
        }
      }
    }
    Contract => {
      if !["refinement", "invariant", "precondition", "postcondition"].contains(
          text(c, "clauseKind"),
        ) {
        fail("conceptual.unsupported_variant", c.path + "/clauseKind")
      }
      let expression = child(c, "expression")
      match text(expression, "state") {
        "resolved" => {
          forbid(expression, ["reason"])
          ignore(id(expression, "profile"))
          ignore(required(expression, "ast"))
        }
        "unresolved" => {
          forbid(expression, ["profile", "ast"])
          ignore(text(expression, "reason"))
        }
        _ => fail("conceptual.unsupported_variant", expression.path + "/state")
      }
      if c.fields.contains("compiledArtifact") {
        let artifact = child(c, "compiledArtifact")
        records.push(artifact)
        ignore(tracked_snapshot(child(artifact, "artifact"), records))
        producer(child(artifact, "compiler"), records)
        ignore(revision(artifact, "contractRevision"))
        for binding in record_list(artifact, "argumentMap") {
          records.push(binding)
          ignore(id(binding, "binderId"))
          exact_nat(binding, "position")
        }
      }
    }
    Scenario => {
      let origin = child(c, "origin")
      match text(origin, "kind") {
        "authored" => {
          forbid(origin, ["generator", "configuration", "seed"])
          ignore(id(origin, "author"))
        }
        "generated" => {
          forbid(origin, ["author"])
          let generator = child(origin, "generator")
          ignore(id(generator, "id"))
          ignore(text(generator, "version", nonempty=true))
          records.push(generator)
          ignore(required(origin, "configuration"))
        }
        _ => fail("conceptual.unsupported_variant", origin.path + "/kind")
      }
    }
    Implementation => {
      ignore(tracked_snapshot(child(c, "artifact"), records))
      if !["declared", "supplied"].contains(text(c, "availability")) {
        fail("conceptual.unsupported_variant", c.path + "/availability")
      }
    }
    Evidence =>
      match text(c, "evidenceKind") {
        "run" => {
          ignore(id(c, "valueProfile"))
          ignore(required(c, "input"))
          let output = child(c, "output")
          records.push(output)
          match text(output, "state") {
            "observed" => {
              forbid(output, ["reason"])
              ignore(required(output, "value"))
            }
            "absent" => {
              forbid(output, ["value"])
              if !["notInvoked", "executionError", "missingResult"].contains(
                  text(output, "reason"),
                ) {
                fail("conceptual.unsupported_variant", output.path + "/reason")
              }
            }
            _ => fail("conceptual.unsupported_variant", output.path + "/state")
          }
          for clause in record_list(c, "clauses") {
            records.push(clause)
            ignore(id(clause, "entityId"))
            ignore(revision(clause, "entityRevision"))
            ignore(text(clause, "observation"))
          }
          producer(child(c, "evaluator"), records)
          let environment = child(c, "environment")
          records.push(environment)
          ignore(text(environment, "target"))
          ignore(required(environment, "configuration"))
          let limits = child(c, "limits")
          records.push(limits)
          exact_nat(limits, "steps", positive=true)
          exact_nat(limits, "depth", positive=true)
        }
        "analysis" => {
          producer(child(c, "analyzer"), records)
          ignore(required(c, "scope"))
          ignore(required(c, "result"))
        }
        "review" => {
          ignore(id(c, "reviewer"))
          ignore(text(c, "decision"))
          ignore(text(c, "rationale"))
        }
        _ => fail("conceptual.unsupported_variant", c.path + "/evidenceKind")
      }
    _ => ()
  }
}
