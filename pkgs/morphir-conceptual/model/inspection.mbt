///|
pub(all) enum Inspection {
  InvalidGraph(Array[Diagnostic])
  Inspected(Array[Diagnostic])
}

///|
pub fn Inspection::diagnostics(self : Inspection) -> Array[Diagnostic] {
  match self {
    InvalidGraph(ds) | Inspected(ds) => ds.copy()
  }
}

///|
pub(all) enum Interpretation {
  Check
  Execute
  ValidateTraits
}

///|
fn diagnostic(code : String, path : String) -> Diagnostic {
  { code, path, related_path: None, }
}

///|
fn Graph::closure(
  self : Graph,
  inputs : Map[String, Graph],
) -> (Array[(Graph, String)], Array[Diagnostic]) raise ModelError {
  let reachable = [(self, "")]
  let errors : Array[Diagnostic] = []
  let mut index = 0
  while index < reachable.length() {
    let (current, prefix) = reachable[index]
    index += 1
    for dep in record_list(current.record, "dependencies") {
      let wanted = snapshot(child(dep, "model"))
      let input_id = text(dep, "inputId")
      match inputs.get(input_id) {
        None =>
          errors.push(
            diagnostic("conceptual.missing_resolved_target", prefix + dep.path),
          )
        Some(g) if g.identity != wanted =>
          errors.push(
            diagnostic("conceptual.reference_revision", prefix + dep.path),
          )
        Some(g) => {
          let prior = reachable.filter(pair => pair.0.identity == wanted)
          if prior.is_empty() {
            if reachable.length() >= 128 {
              fail("data.tree_limit", prefix + dep.path)
            }
            reachable.push((g, "/inputs/" + pointer(input_id)))
          } else if !prior[0].0.record.value.equals(g.record.value) {
            errors.push(
              diagnostic("conceptual.reference_revision", prefix + dep.path),
            )
          }
        }
      }
    }
  }
  (reachable, errors)
}

///|
fn Graph::resolve(
  self : Graph,
  reference_value : Reference,
  path : String,
  reachable : Array[(Graph, String)],
  errors : Array[Diagnostic],
) -> (String, Record)? raise ModelError {
  guard reference_value is Resolved(reference_value) else { return None }
  let mut target : Graph? = None
  if reference_value.model == self.identity {
    target = Some(self)
  } else {
    for (g, _) in reachable {
      if g.identity == reference_value.model {
        target = Some(g)
      }
    }
    if target is None {
      let mut missing = false
      for (g, prefix) in reachable {
        for dep in record_list(g.record, "dependencies") {
          if snapshot(child(dep, "model")) == reference_value.model &&
            errors.any(d => {
              d.code == "conceptual.missing_resolved_target" &&
              d.path == prefix + dep.path
            }) {
            missing = true
          }
        }
      }
      errors.push(
        diagnostic(
          if missing {
            "conceptual.missing_resolved_target"
          } else {
            "conceptual.reference_revision"
          },
          path,
        ),
      )
      return None
    }
  }
  let target = target.unwrap()
  for e in target.entities {
    if e.identity.id == reference_value.entity.id {
      if e.identity.revision != reference_value.entity.revision {
        errors.push(diagnostic("conceptual.reference_revision", path))
        return None
      }
      return Some((text(e.record, "kind"), e.record))
    }
  }
  for d in target.definitions {
    if d.identity.id == reference_value.entity.id {
      if d.identity.revision != reference_value.entity.revision {
        errors.push(diagnostic("conceptual.reference_revision", path))
        return None
      }
      return Some(("traitDefinition", d.record))
    }
  }
  errors.push(diagnostic("conceptual.missing_resolved_target", path))
  None
}

///|
/// Inspect references and representation gaps, without evaluating contracts,
/// checking trait payload assignability, authenticating authors or fetching inputs.
/// Only declared input IDs with exact model revisions grant reference resolution.
fn Graph::inspect_local(
  self : Graph,
  inputs~ : Map[String, Graph] = Map([]),
) -> Inspection raise ModelError {
  let (reachable, errors) = self.closure(inputs)
  let gaps : Array[Diagnostic] = []
  for (reference_value, path) in self.references {
    match reference_value {
      Unresolved(_, _, _) =>
        gaps.push(diagnostic("conceptual.unresolved_reference", path))
      Resolved(_) =>
        ignore(self.resolve(reference_value, path, reachable, errors))
    }
  }
  for (reference_value, path) in self.source_refs {
    let mut found = false
    for source in self.sources {
      if source.id == reference_value.source_id &&
        source.fragments.any(f => f.anchor == reference_value.anchor) {
        found = true
      }
    }
    if !found {
      errors.push(diagnostic("conceptual.missing_resolved_target", path))
    }
  }
  for source in self.sources {
    let document = child(source.record, "document")
    // Digest claims are preserved but cannot pin a source without verification.
    if !document.fields.contains("revision") {
      gaps.push(diagnostic("conceptual.source_unpinned", document.path))
    }
  }
  for r in self.relationships {
    let subject = self.resolve(
      r.subject,
      r.record.path + "/subject",
      reachable,
      [],
    )
    let target = match r.target {
      Unresolved(_, kind, _) => Some((kind, r.record))
      _ => self.resolve(r.target, r.record.path + "/target", reachable, [])
    }
    if subject is Some((sk, sr)) && target is Some((tk, tr)) {
      let valid = match r.predicate {
        "morphir:derivedFrom" => sk == "requirement" && tk == "sourceFragment"
        "morphir:refines" => sk == "requirement" && tk == "intent"
        "morphir:formalizes" => sk == "contract" && tk == "requirement"
        "morphir:governedBy" => sk == "declaration" && tk == "contract"
        "morphir:exercises" => sk == "scenario" && tk == "contract"
        "morphir:implements" => sk == "implementation" && tk == "declaration"
        "morphir:supports" | "morphir:contradicts" =>
          sk == "evidence" && tk == "claim"
        "morphir:represents" =>
          (sk == "dataElement" || sk == "declaration") && tk == "concept"
        _ => {
          gaps.push(
            diagnostic(
              "conceptual.unsupported_semantics",
              r.record.path + "/predicate",
            ),
          )
          true
        }
      }
      if !valid {
        errors.push(diagnostic("conceptual.relationship_kind", r.record.path))
      } else {
        if r.predicate == "morphir:implements" &&
          r.target is Resolved(_) &&
          text(child(tr, "content"), "role") != "function" {
          errors.push(diagnostic("conceptual.relationship_kind", r.record.path))
        }
        if r.predicate == "morphir:governedBy" {
          let role = text(child(sr, "content"), "role")
          if !["type", "function"].contains(role) {
            errors.push(
              diagnostic("conceptual.relationship_kind", r.record.path),
            )
          }
          if r.target is Resolved(_) {
            let c = child(tr, "content")
            let subject = reference(child(c, "subject"))
            let kind = text(c, "clauseKind")
            if subject != r.subject ||
              (["refinement", "invariant"].contains(kind) && role != "type") ||
              (
                ["precondition", "postcondition"].contains(kind) &&
                role != "function"
              ) {
              errors.push(
                diagnostic("conceptual.relationship_kind", r.record.path),
              )
            }
          }
        }
      }
    }
  }
  for e in self.entities {
    let path = e.record.path
    if e.kind is Unknown(_) {
      gaps.push(diagnostic("conceptual.unsupported_semantics", path + "/kind"))
    }
    if e.kind == Requirement {
      let formalizations = self.relationships.filter(r => {
        r.predicate == "morphir:formalizes" &&
        (match r.target {
          Resolved(reference_value) =>
            reference_value.model == self.identity &&
            reference_value.entity == e.identity
          _ => false
        })
      })
      if formalizations.is_empty() {
        gaps.push(diagnostic("conceptual.missing_formalization", path))
      }
      let examples = self.relationships.any(r => {
        r.predicate == "morphir:exercises" &&
        formalizations.any(f => f.subject == r.target)
      })
      if !examples {
        gaps.push(diagnostic("conceptual.missing_examples", path))
      }
    }
    if e.concern("elaboration") is Some(c) && text(c, "state") == "open" {
      for aspect in record_list(c, "aspects") {
        gaps.push(diagnostic("conceptual.open_domain_aspect", aspect.path))
      }
    }
    if e.concern("implementation") is Some(c) && text(c, "state") == "unbound" {
      gaps.push(diagnostic("conceptual.implementation_unbound", c.path))
    }
    if e.kind == Contract {
      gaps.push(
        diagnostic(
          "conceptual.unsupported_semantics",
          path + "/content/expression",
        ),
      )
    }
  }
  for gap in record_list(self.record, "projectionGaps") {
    gaps.push(diagnostic("conceptual.projection_gap", gap.path))
  }
  let required = strings(self.record, "requiredSemantics")
  for i, _ in required {
    gaps.push(
      diagnostic(
        "conceptual.unsupported_semantics",
        "/requiredSemantics/" + i.to_string(),
      ),
    )
  }
  for r in self.records {
    if r.fields.contains("critical") {
      for name in strings(r, "critical") {
        // The preservation reader does not claim interpretation of critical extensions.
        gaps.push(
          diagnostic(
            "conceptual.unsupported_semantics",
            r.path + "/" + pointer(name),
          ),
        )
      }
    }
  }
  for app_index, app in self.applications {
    let target_path = app.record.path + "/target"
    match app.target() {
      ModelTarget(wanted) =>
        if model_target_error(wanted, reachable, inputs) is Some(code) {
          errors.push(diagnostic(code, target_path + "/model"))
        }
      EntityTarget(kind, reference_value) => {
        let expected = if kind == ConceptTarget {
          "concept"
        } else {
          "declaration"
        }
        let valid = match reference_value {
          Unresolved(_, claimed, _) => claimed == expected
          Resolved(_) =>
            match
              self.resolve(reference_value, target_path + "/ref", reachable, []) {
              None => true // The general reference pass reports missing identities.
              Some((actual, record)) =>
                actual == expected &&
                (match kind {
                  ConceptTarget => true
                  TypeTarget => text(child(record, "content"), "role") == "type"
                  FunctionTarget =>
                    text(child(record, "content"), "role") == "function"
                  MemberTarget =>
                    ["field", "parameter", "result"].contains(
                      text(child(record, "content"), "role"),
                    )
                  OperationTarget | ServiceBindingTarget => false
                })
            }
        }
        if !valid {
          errors.push(diagnostic("traits.target_identity_kind", target_path))
        }
      }
      ProfileTarget(kind, _, reference_value) => {
        gaps.push(
          diagnostic(
            "traits.unsupported_target_profile",
            target_path + "/profile",
          ),
        )
        // Only the explicit unresolved kind is structural; foreign profile rules
        // and resolved subject applicability require a separate interpreter.
        if reference_value is Unresolved(_, claimed, _) {
          let expected = if kind == OperationTarget {
            "operation"
          } else {
            "serviceBinding"
          }
          if claimed != expected {
            errors.push(diagnostic("traits.target_identity_kind", target_path))
          }
        }
      }
      ModuleTarget(_, _) =>
        gaps.push(
          diagnostic(
            "conceptual.unsupported_semantics",
            target_path + "/artifact",
          ),
        )
      UnknownTarget(_) =>
        gaps.push(
          diagnostic("conceptual.unsupported_semantics", target_path + "/kind"),
        )
    }
    let interpretation = child(app.record, "interpretation")
    if self.resolve(
        app.definition,
        app.record.path + "/definition",
        reachable,
        [],
      )
      is Some((kind, definition)) {
      if kind != "traitDefinition" {
        errors.push(
          diagnostic("traits.reference_kind", app.record.path + "/definition"),
        )
      } else {
        if text(definition, "multiplicity") == "one" {
          for prior_index in 0..<app_index {
            let prior = self.applications[prior_index]
            if prior.definition == app.definition &&
              same_target(prior.target(), app.target()) &&
              !prior.record.fields["payload"].equals(
                app.record.fields["payload"],
              ) {
              gaps.push({
                code: "traits.application_conflict",
                path: app.record.path,
                related_path: Some(prior.record.path),
              })
            }
          }
        }
        let declared = trait_interpretation(child(definition, "interpretation"))
        let actual = app.interpretation()
        let same = match (declared, actual) {
          (Descriptive, Descriptive) => true
          (Semantic(a), Semantic(b)) =>
            a.length() == b.length() && a.all(p => b.contains(p))
          _ => false
        }
        if !same {
          errors.push(
            diagnostic("traits.interpretation_mismatch", interpretation.path),
          )
        }
      }
    }
    if text(interpretation, "kind") == "semantic" {
      let profiles = strings(interpretation, "profiles")
      if !required.contains(TRAITS_PROFILE) ||
        profiles.any(p => !required.contains(p)) {
        errors.push(
          diagnostic("traits.required_semantics", interpretation.path),
        )
      }
      gaps.push(
        diagnostic("conceptual.unsupported_semantics", interpretation.path),
      )
    }
    if app.definition is Unresolved(_, _, _) {
      gaps.push(
        diagnostic(
          "traits.unresolved_definition",
          app.record.path + "/definition",
        ),
      )
    }
  }
  if errors.is_empty() {
    Inspected(gaps)
  } else {
    InvalidGraph(errors)
  }
}

///|
fn model_target_error(
  wanted : Snapshot,
  reachable : Array[(Graph, String)],
  inputs : Map[String, Graph],
) -> String? raise ModelError {
  if reachable.any(pair => pair.0.identity == wanted) {
    return None
  }
  let mut wrong_revision = reachable.any(pair => pair.0.identity.id == wanted.id)
  let mut missing_exact = false
  // Only declarations in this owner's closure may consult supplied inputs.
  for (graph, _) in reachable {
    for dep in record_list(graph.record, "dependencies") {
      let declared = snapshot(child(dep, "model"))
      if declared.id == wanted.id {
        if declared.revision != wanted.revision {
          wrong_revision = true
        } else {
          match inputs.get(text(dep, "inputId")) {
            None => missing_exact = true
            Some(g) => if g.identity != wanted { wrong_revision = true }
          }
        }
      }
    }
  }
  Some(
    if missing_exact {
      "conceptual.missing_resolved_target"
    } else if wrong_revision {
      "conceptual.reference_revision"
    } else {
      "conceptual.missing_resolved_target"
    },
  )
}

///|
fn same_target(a : TraitTarget, b : TraitTarget) -> Bool {
  match (a, b) {
    (ModelTarget(a), ModelTarget(b)) => a == b
    (ModuleTarget(a, an), ModuleTarget(b, bn)) => a == b && an == bn
    (EntityTarget(ak, a), EntityTarget(bk, b)) => ak == bk && a == b
    (ProfileTarget(ak, ap, a), ProfileTarget(bk, bp, b)) =>
      ak == bk && ap == bp && a == b
    _ => false
  }
}

///|
/// No semantic interpreter is implemented by this codec package. Refusal names
/// the first required fact; successful storage never grants interpretation.
pub fn Graph::require_interpretation(
  self : Graph,
  _operation : Interpretation,
) -> Unit raise ModelError {
  let required = strings(self.record, "requiredSemantics")
  if !required.is_empty() {
    fail("conceptual.unsupported_semantics", "/requiredSemantics/0")
  }
  for r in self.records {
    if r.fields.contains("critical") {
      let names = strings(r, "critical")
      if !names.is_empty() {
        fail(
          "conceptual.unsupported_semantics",
          r.path + "/" + pointer(names[0]),
        )
      }
    }
  }
  for e in self.entities {
    if e.kind == Contract {
      fail(
        "conceptual.unsupported_semantics",
        e.record.path + "/content/expression",
      )
    }
  }
  fail("conceptual.unsupported_semantics", "/operation")
}

///|
/// Inspect the graph and its declared dependency closure. Supplied inputs never
/// widen the scope of another graph: each resolves under its own declarations.
pub fn Graph::inspect(
  self : Graph,
  inputs~ : Map[String, Graph] = Map([]),
) -> Inspection raise ModelError {
  let (reachable, errors) = self.closure(inputs)
  let gaps : Array[Diagnostic] = []
  for (graph, prefix) in reachable {
    let result = graph.inspect_local(inputs~)
    let output = match result {
      InvalidGraph(_) => errors
      Inspected(_) => gaps
    }
    for d in result.diagnostics() {
      let d = {
        ..d,
        path: contextual_path(prefix, d.path),
        related_path: d.related_path.map(p => contextual_path(prefix, p)),
      }
      if !output.contains(d) {
        output.push(d)
      }
    }
  }
  if errors.is_empty() {
    Inspected(gaps)
  } else {
    InvalidGraph(errors)
  }
}

///|
fn contextual_path(prefix : String, path : String) -> String {
  // Closure failures already identify their supplied graph in the global input map.
  if path.has_prefix("/inputs/") {
    path
  } else {
    prefix + path
  }
}
