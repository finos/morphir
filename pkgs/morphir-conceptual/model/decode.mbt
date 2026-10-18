///|
fn record(value : @ion.IonValue, path : String) -> Record raise ModelError {
  let fields : Map[String, @ion.IonValue] = Map([])
  match value.kind() {
    Struct(items) =>
      for item in items {
        let name = match item.name().text() {
          Some(n) => n
          None => {
            fail("data.symbol_catalog_missing", path)
            ""
          }
        }
        if fields.contains(name) {
          fail("conceptual.duplicate_member", path + "/" + pointer(name))
        }
        fields[name] = item.value()
      }
    _ => fail("conceptual.invalid_record", path)
  }
  { value, fields, path, }
}

///|
fn required(r : Record, name : String) -> @ion.IonValue raise ModelError {
  match r.fields.get(name) {
    Some(v) => v
    None => {
      fail("conceptual.missing_field", r.path + "/" + name)
      @ion.IonValue::untyped_null()
    }
  }
}

///|
fn text(
  r : Record,
  name : String,
  nonempty~ : Bool = false,
) -> String raise ModelError {
  let v = required(r, name)
  match v.kind() {
    String(s) if !v.has_annotations() && (!nonempty || !s.is_empty()) => s
    _ => {
      fail("conceptual.invalid_record", r.path + "/" + name)
      ""
    }
  }
}

///|
fn items(r : Record, name : String) -> Array[@ion.IonValue] raise ModelError {
  let v = required(r, name)
  match v.kind() {
    List(xs) if !v.has_annotations() => xs
    _ => {
      fail("conceptual.invalid_record", r.path + "/" + name)
      []
    }
  }
}

///|
fn strings(
  r : Record,
  name : String,
  nonempty~ : Bool = true,
) -> Array[String] raise ModelError {
  items(r, name).map(v => {
    match v.kind() {
      String(s) if !v.has_annotations() && (!nonempty || !s.is_empty()) => s
      _ => {
        fail("conceptual.invalid_record", r.path + "/" + name)
        ""
      }
    }
  })
}

///|
fn child(r : Record, name : String) -> Record raise ModelError {
  record(required(r, name), r.path + "/" + name)
}

///|
fn id(r : Record, name : String) -> Id raise ModelError {
  @intent.Id::parse(text(r, name, nonempty=true)) catch {
    _ => {
      fail("conceptual.invalid_record", r.path + "/" + name)
      abort("unreachable")
    }
  }
}

///|
fn revision(r : Record, name : String) -> Revision raise ModelError {
  @intent.Revision::parse(text(r, name, nonempty=true)) catch {
    _ => {
      fail("conceptual.invalid_record", r.path + "/" + name)
      abort("unreachable")
    }
  }
}

///|
fn snapshot(r : Record) -> Snapshot raise ModelError {
  { id: id(r, "id"), revision: revision(r, "revision"), }
}

///|
fn version(r : Record) -> Unit raise ModelError {
  if text(r, "recordVersion") != RECORD_VERSION {
    fail("conceptual.unsupported_profile", r.path + "/recordVersion")
  }
}

///|
fn reference(r : Record) -> Reference raise ModelError {
  match text(r, "state") {
    "resolved" => {
      for name in ["locator", "expectedKind", "reason", "proposedId"] {
        if r.fields.contains(name) {
          fail("conceptual.invalid_variant", r.path + "/" + name)
        }
      }
      Resolved({
        model: { id: id(r, "modelId"), revision: revision(r, "modelRevision"), },
        entity: {
          id: id(r, "entityId"),
          revision: revision(r, "entityRevision"),
        },
      })
    }
    "unresolved" => {
      for name in ["modelId", "modelRevision", "entityId", "entityRevision"] {
        if r.fields.contains(name) {
          fail("conceptual.invalid_variant", r.path + "/" + name)
        }
      }
      Unresolved(
        text(r, "locator", nonempty=true),
        text(r, "expectedKind", nonempty=true),
        text(r, "reason", nonempty=true),
      )
    }
    _ => {
      fail("conceptual.unsupported_variant", r.path + "/state")
      abort("unreachable")
    }
  }
}

///|
fn entity_kind(name : String) -> EntityKind {
  match name {
    "intent" => Intent
    "requirement" => Requirement
    "concept" => Concept
    "dataElement" => DataElement
    "sourceFragment" => SourceFragment
    "declaration" => Declaration
    "contract" => Contract
    "scenario" => Scenario
    "implementation" => Implementation
    "claim" => Claim
    "evidence" => Evidence
    other => Unknown(other)
  }
}

///|
fn record_list(r : Record, name : String) -> Array[Record] raise ModelError {
  items(r, name).mapi((i, v) => {
    record(v, r.path + "/" + name + "/" + i.to_string())
  })
}

///|
/// Decode bounded structural records while leaving opaque values uninterpreted.
/// Semantic validity is reported separately by inspect, never implied by decode.
pub fn Graph::decode(value : @ion.IonValue) -> Graph raise ModelError {
  let pending = [(value, 0)]
  let mut count = 0
  while pending.pop() is Some((v, depth)) {
    count += 1
    if depth > 128 || count > 100000 {
      fail("data.tree_limit", "")
    }
    match v.kind() {
      List(xs) | Sexp(xs) =>
        for x in xs {
          pending.push((x, depth + 1))
        }
      Struct(fs) =>
        for f in fs {
          pending.push((f.value(), depth + 1))
        }
      _ => ()
    }
  }
  let root = record(copy_value(value), "")
  version(root)
  if text(root, "profile") != PROFILE {
    fail("conceptual.unsupported_profile", "/profile")
  }
  let records = [root]
  let identity = tracked_snapshot(child(root, "model"), records)
  ignore(strings(root, "requiredSemantics"))
  for dep in record_list(root, "dependencies") {
    ignore(tracked_snapshot(child(dep, "model"), records))
    ignore(id(dep, "inputId"))
    records.push(dep)
  }
  for gap in record_list(root, "projectionGaps") {
    ignore(id(gap, "entityId"))
    ignore(text(gap, "reason"))
    ignore(id(gap, "requiredCapability"))
    records.push(gap)
  }
  let sources : Array[Source] = []
  let entities : Array[Entity] = []
  let relationships : Array[Relationship] = []
  let capabilities : Array[Record] = []
  let definitions : Array[TraitDefinition] = []
  let applications : Array[TraitApplication] = []
  let references : Array[(Reference, String)] = []
  let source_refs : Array[(SourceRef, String)] = []
  let seen : Map[String, String] = Map([])
  fn register(r : Record) -> Unit raise ModelError {
    version(r)
    let name = text(r, "id", nonempty=true)
    let path = r.path + "/id"
    if seen.get(name) is Some(earlier) {
      fail("conceptual.duplicate_identity", path, related_path=Some(earlier))
    }
    seen[name] = path
    records.push(r)
  }
  fn refs(r : Record) -> Unit raise ModelError {
    for sr in record_list(r, "sourceRefs") {
      source_refs.push(
        ({ source_id: id(sr, "sourceId"), anchor: id(sr, "anchor"), }, sr.path),
      )
      records.push(sr)
    }
  }
  fn ref_field(r : Record, name : String) -> Reference raise ModelError {
    let rr = child(r, name)
    let result = reference(rr)
    references.push((result, rr.path))
    records.push(rr)
    result
  }
  fn resolved_ref_field(r : Record, name : String) -> Unit raise ModelError {
    let rr = child(r, name)
    references.push((Resolved(resolved_reference(rr)), rr.path))
    records.push(rr)
  }
  for r in record_list(root, "sources") {
    register(r)
    let document = child(r, "document")
    ignore(id(document, "id"))
    if document.fields.contains("revision") {
      ignore(revision(document, "revision"))
    }
    if document.fields.contains("digest") {
      let digest = child(document, "digest")
      validate_digest(digest)
      records.push(digest)
    }
    records.push(document)
    ignore(text(r, "locator"))
    let fragments : Array[Fragment] = []
    let anchors : Map[String, Bool] = Map([])
    for f in record_list(r, "fragments") {
      let anchor = id(f, "anchor")
      if anchors.contains(anchor.value()) {
        fail("conceptual.duplicate_identity", f.path + "/anchor")
      }
      anchors[anchor.value()] = true
      fragments.push({ anchor, text: text(f, "text"), })
      records.push(f)
    }
    match text(r, "resolution") {
      "retained" =>
        if fragments.is_empty() {
          fail("conceptual.invalid_record", r.path + "/fragments")
        }
      "unresolved" => ignore(text(r, "reason", nonempty=true))
      _ => fail("conceptual.unsupported_variant", r.path + "/resolution")
    }
    sources.push({ record: r, id: id(r, "id"), fragments, })
  }
  for r in record_list(root, "entities") {
    register(r)
    refs(r)
    let identity = snapshot(r)
    let kind = entity_kind(text(r, "kind", nonempty=true))
    ignore(text(r, "name"))
    let content = match kind {
      Unknown(_) => {
        ignore(required(r, "content"))
        None
      }
      _ => Some(child(r, "content"))
    }
    if content is Some(c) {
      records.push(c)
      content_records(kind, c, records)
      match kind {
        Intent => ignore(text(c, "text"))
        Requirement => {
          ignore(id(c, "category"))
          ignore(text(c, "text"))
        }
        Concept => ignore(strings(c, "aliases", nonempty=false))
        SourceFragment =>
          source_refs.push(
            ({ source_id: id(c, "sourceId"), anchor: id(c, "anchor"), }, c.path),
          )
        Declaration => {
          ignore(text(c, "role", nonempty=true))
          if c.fields.contains("signature") {
            let signature = child(c, "signature")
            records.push(signature)
            records.push(child(signature, "inputs"))
            ignore(required(signature, "output"))
          }
          if c.fields.contains("parent") {
            resolved_ref_field(c, "parent")
          }
          if c.fields.contains("representation") {
            records.push(child(c, "representation"))
          }
        }
        Contract => {
          ignore(text(c, "clauseKind", nonempty=true))
          resolved_ref_field(c, "subject")
          let notation = child(c, "notation")
          ignore(id(notation, "profile"))
          ignore(text(notation, "text"))
          records.push(notation)
          let expression = child(c, "expression")
          ignore(text(expression, "state", nonempty=true))
          records.push(expression)
          for b in record_list(c, "binders") {
            ignore(id(b, "id"))
            ignore(text(b, "role"))
            ignore(text(b, "name"))
            ignore(required(b, "type"))
            records.push(b)
          }
        }
        Scenario => {
          ignore(id(c, "valueProfile"))
          ignore(required(c, "inputs"))
          ignore(required(c, "expected"))
          records.push(child(c, "origin"))
        }
        Implementation => {
          ignore(snapshot(child(c, "artifact")))
          ignore(text(c, "fqName"))
          ignore(text(c, "availability"))
        }
        Claim => {
          resolved_ref_field(c, "subject")
          ignore(text(c, "proposition"))
          ignore(id(c, "author"))
          ignore(required(c, "scope"))
          records.push(child(c, "context"))
        }
        Evidence => {
          ignore(text(c, "evidenceKind"))
          ignore(text(c, "origin"))
          records.push(child(c, "context"))
        }
        _ => ()
      }
    }
    for
      concern in [
        "elaboration", "definition", "recovery", "review", "implementation",
      ] {
      if r.fields.get(concern) is Some(v) {
        let c = record(v, r.path + "/" + concern)
        validate_concern(c, concern)
        ignore(text(c, "state", nonempty=true))
        records.push(c)
        if c.fields.contains("sourceRefs") {
          refs(c)
        }
        if concern == "implementation" && c.fields.contains("binding") {
          ignore(ref_field(c, "binding"))
        }
        if concern == "elaboration" && c.fields.contains("aspects") {
          for aspect in record_list(c, "aspects") {
            ignore(id(aspect, "id"))
            ignore(text(aspect, "question"))
            ignore(text(aspect, "rationale"))
            refs(aspect)
            records.push(aspect)
          }
        }
        if concern == "recovery" && c.fields.contains("diagnostics") {
          for d in record_list(c, "diagnostics") {
            ignore(text(d, "code"))
            ignore(text(d, "message"))
            records.push(d)
            if d.fields.contains("span") {
              let span = child(d, "span")
              records.push(span)
              exact_nat(span, "start")
              exact_nat(span, "end")
              ignore(text(span, "unit"))
            }
          }
          let sr = child(c, "sourceRef")
          source_refs.push(
            (
              { source_id: id(sr, "sourceId"), anchor: id(sr, "anchor"), },
              sr.path,
            ),
          )
          records.push(sr)
        }
      }
    }
    entities.push({ record: r, identity, kind, content, })
  }
  for r in record_list(root, "relationships") {
    register(r)
    refs(r)
    let subject = ref_field(r, "subject")
    if subject is Unresolved(_, _, _) {
      fail("conceptual.invalid_variant", r.path + "/subject")
    }
    relationships.push({
      record: r,
      id: id(r, "id"),
      predicate: text(r, "predicate", nonempty=true),
      subject,
      target: ref_field(r, "target"),
    })
  }
  for r in record_list(root, "capabilities") {
    register(r)
    ignore(tracked_snapshot(child(r, "provider"), records))
    ignore(text(r, "profile", nonempty=true))
    ignore(strings(r, "operations"))
    ignore(strings(r, "semanticProfiles"))
    let limits = child(r, "limits")
    records.push(limits)
    for name in ["bytes", "depth", "values"] {
      exact_nat(limits, name, positive=true)
    }
    capabilities.push(r)
  }
  if root.fields.get("traits") is Some(v) {
    let traits = record(v, "/traits")
    version(traits)
    if text(traits, "profile") != TRAITS_PROFILE {
      fail("conceptual.unsupported_profile", "/traits/profile")
    }
    records.push(traits)
    for r in record_list(traits, "definitions") {
      register(r)
      refs(r)
      ignore(text(r, "name"))
      ignore(strings(r, "targets"))
      ignore(text(r, "multiplicity"))
      let schema = child(r, "payloadSchema")
      ignore(tracked_snapshot(child(schema, "artifact"), records))
      ignore(text(schema, "fqName"))
      ignore(items(schema, "typeArguments"))
      ignore(text(schema, "dataProfile"))
      records.push(schema)
      records.push(child(r, "interpretation"))
      if r.fields.contains("referenceBindings") {
        for b in record_list(r, "referenceBindings") {
          records.push(b)
        }
      }
      let definition = TraitDefinition::{ record: r, identity: snapshot(r), }
      ignore(definition.interpretation())
      ignore(definition.multiplicity())
      definitions.push(definition)
    }
    for r in record_list(traits, "applications") {
      register(r)
      refs(r)
      let definition = ref_field(r, "definition")
      let target = child(r, "target")
      ignore(text(target, "kind", nonempty=true))
      records.push(target)
      for name in ["model", "artifact"] {
        if target.fields.contains(name) {
          ignore(tracked_snapshot(child(target, name), records))
        }
      }
      if target.fields.contains("ref") {
        ignore(ref_field(target, "ref"))
      }
      ignore(required(r, "payload"))
      records.push(child(r, "interpretation"))
      let provenance = child(r, "provenance")
      ignore(text(provenance, "origin"))
      ignore(text(provenance, "agent"))
      refs(provenance)
      records.push(provenance)
      if provenance.fields.contains("derivedFrom") {
        for rr in record_list(provenance, "derivedFrom") {
          references.push((Resolved(resolved_reference(rr)), rr.path))
          records.push(rr)
        }
      }
      let application = TraitApplication::{
        record: r,
        identity: snapshot(r),
        definition,
        provenance,
      }
      ignore(application.interpretation())
      ignore(application.target())
      if application.origin() is Derived &&
        (
          !provenance.fields.contains("derivedFrom") ||
          items(provenance, "derivedFrom").is_empty()
        ) {
        fail("conceptual.invalid_record", provenance.path + "/derivedFrom")
      }
      applications.push(application)
    }
  }
  for r in records {
    if r.fields.contains("critical") {
      let names = strings(r, "critical")
      let seen : Map[String, Bool] = Map([])
      for name in names {
        if seen.contains(name) || !r.fields.contains(name) {
          fail("conceptual.invalid_record", r.path + "/critical")
        }
        seen[name] = true
      }
    }
  }
  {
    record: root,
    identity,
    sources,
    entities,
    relationships,
    capabilities,
    definitions,
    applications,
    references,
    source_refs,
    records,
  }
}
