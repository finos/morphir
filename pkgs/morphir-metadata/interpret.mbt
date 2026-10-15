///|
/// Interpret the explicit engine adapter without changing any authored Ion.
/// This is not a native IR 4.1/Ion codec or a general JSON-LD processor.
pub fn interpret(
  file : @ir.IRFile,
  unit_id : String,
  entries : Array[MetadataEntry],
  capabilities? : Capabilities = Capabilities::unavailable(),
) -> Interpretation raise {
  let owners : Map[String, String] = Map([])
  if file.distribution is Library(package_name, _, definition) {
    for module_name, module_def in definition.modules {
      for name, _ in module_def.value.values {
        let fqname : @ir.FQName = {
          package_name,
          module_name,
          local_name: name,
        }
        owners[value_uri(file, fqname)] = "value:" + fqname.to_canonical()
      }
    }
  }
  let owned = Map::from_array(
    @identities.nodes(unit_id, file).map(id => (id, true)),
  )
  let facts : Map[String, NamingFact] = Map([])
  let unvalidated : Map[String, Bool] = Map([])
  let restored : Map[String, String] = Map([])
  for entry in entries {
    if !entry.data.annotations().any(a => a.text() == Some(ADAPTER_PROFILE)) {
      continue
    }
    if !owned.contains(entry.node_id) {
      raise Invalid(
        "metadata.invalid_holder",
        entry.node_id,
        "Attach the adapter to an owned engine node; graph subjects remain separate",
      )
    }
    let payload = fields(entry.data, entry.node_id)
    let document = text(
      required(payload, "document", entry.node_id),
      entry.node_id,
    )
    let document_address = address(document)
    if document_address.fragment != "/distribution" {
      raise Invalid(
        "metadata.invalid_document_owner", document, "Supply the containing document's distribution URI, separate from its subjects",
      )
    }
    let base = match payload.get("contextBase") {
      Some(value) => text(value, "contextBase")
      None => ""
    }
    let parent = match payload.get("@context") {
      Some(value) =>
        resolve_context(
          value,
          Context::new(),
          capabilities,
          base,
          Map([]),
          Map([]),
        )
      None => Context::new()
    }
    let metadata = required(payload, "$meta", entry.node_id)
    let context = scoped_context(metadata, parent, capabilities, base)
    for fact in graph(metadata, context, entry.node_id, document) {
      let predicate = fact.assertion.predicate
      if !is_target_names_predicate(predicate) {
        unvalidated[predicate] = true
        continue
      }
      let (subject, parsed) = declaration(fact.assertion.subject)
      let expected = value_uri(file, subject)
      if parsed.revision is Some(_) ||
        parsed.format != file.format_version.to_release_string() ||
        !owners.contains(expected) ||
        expected != fact.assertion.subject {
        raise Invalid(
          "metadata.unresolved_subject",
          fact.assertion.subject,
          "Name an existing, current ValueDefinition in this exact input; do not reuse body or storage paths",
        )
      }
      if !fact.is_json || fact.data is None {
        raise Invalid(
          "metadata.invalid_target_names", predicate, "Wrap one frontend/backend record in @json or declare @json coercion",
        )
      }
      let names = TargetNames::from_ion(
        fact.data.unwrap(),
        owner=fact.assertion.subject,
        language_ids=false,
      )
      let revision = match restored.get(predicate) {
        Some(revision) => revision
        None => {
          guard capabilities.restore_library is Some(restore) else {
            raise Invalid(
              "metadata.provider_unavailable", predicate, "Configure a host capability that freshly authenticates and restores the signed provider Library; metadata and matching digests cannot grant trust",
            )
          }
          let revision = observed_provider(
            predicate,
            restore(predicate),
            capabilities,
          )
          restored[predicate] = revision
          revision
        }
      }
      if !capabilities.target_names_interpreter {
        raise Invalid(
          "metadata.required_interpreter_unavailable", predicate, "Register target-name-language-ids before generation; the authored fact remains preserved",
        )
      }
      ignore(
        TargetNames::from_ion(fact.data.unwrap(), owner=fact.assertion.subject),
      )
      let owner = owners[expected]
      if facts.get(owner) is Some(old) {
        if old.names != names || old.provider_revision != revision {
          raise Invalid(
            "metadata.conflicting_target_names",
            owner,
            "Conflicting assertions from '" +
            old.assertions[0].document +
            "' and '" +
            document +
            "'; retain one consistent frontend/backend record",
          )
        }
        old.assertions.push(fact.assertion)
      } else {
        facts[owner] = {
          owner,
          names,
          assertions: [fact.assertion],
          provider_revision: revision,
        }
      }
    }
  }
  let keys = facts.keys().collect()
  keys.sort()
  let unknown = unvalidated.keys().collect()
  unknown.sort()
  { facts: keys.map(k => facts[k]), unvalidated_predicates: unknown, }
}
