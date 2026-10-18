///|
/// Attach the draft conceptual graph to its existing unit metadata owner.
/// An occupied owner, including another graph, is never overwritten implicitly.
pub fn IRUnit::with_conceptual_graph(
  self : IRUnit,
  graph : @model.Graph,
) -> IRUnit raise {
  for i, entry in self.metadata {
    if entry.node_id == "unit:" + self.id {
      raise Invalid(
        "conceptual.metadata_owner_conflict",
        "/existingMetadata/" + i.to_string() + "/nodeId",
      )
    }
  }
  self.validate()
  let result = {
    ..self,
    metadata: [
      ..self.metadata,
      { node_id: "unit:" + self.id, data: graph.to_ion(), },
    ],
  }
  result.validate()
  result
}

///|
/// Read the graph at the unit owner, leaving unrelated metadata untouched.
/// Existing graph-free profiles return None. A recognized malformed graph fails.
pub fn IRUnit::conceptual_graph(self : IRUnit) -> @model.Graph? raise {
  let mut owned : @ion.IonValue? = None
  for i, entry in self.metadata {
    if entry.node_id == "unit:" + self.id {
      if owned is Some(_) {
        raise Invalid(
          "conceptual.metadata_owner_conflict",
          "/metadata/" + i.to_string() + "/node_id",
        )
      }
      owned = Some(entry.data)
    }
  }
  guard owned is Some(value) else { return None }
  guard value.kind() is Struct(fields) else { return None }
  let conceptual = fields.any(f => {
    f.name().text() == Some("profile") &&
    (match f.value().kind() {
      String(s) => s.has_prefix("morphir-conceptual/")
      _ => false
    })
  })
  if conceptual {
    Some(@model.Graph::decode(value))
  } else {
    None
  }
}

///|
/// Extract public Library signatures while retaining the complete conceptual
/// graph and carrier facts. Metadata whose owner disappears makes projection
/// lossy and is refused. This does not evaluate or lower conceptual content.
pub fn IRUnit::conceptual_specification(self : IRUnit) -> IRUnit raise {
  self.validate()
  ignore(self.conceptual_graph())
  let distribution = match self.distribution.distribution {
    Specs(_, _, _) => return self
    Application(_, _, _, _) =>
      raise Invalid(
        "conceptual.unsupported_projection", "Application projection requires a separate linking policy",
      )
    Library(name, dependencies, definition) => {
      let modules : Map[@ir.ModuleName, @ir.ModuleSpecification] = Map([])
      for module_name, module_entry in definition.modules {
        if module_entry.access != @ir.Access::Public {
          continue
        }
        let types : Map[@ir.Name, @ir.Documented[@ir.TypeSpecification]] = Map([])
        let values : Map[@ir.Name, @ir.Documented[@ir.ValueSpecification]] = Map([],
        )
        for name, entry in module_entry.value.types {
          if entry.access != @ir.Access::Public {
            continue
          }
          let body = match entry.value.value {
            TypeAliasDefinition(params, body) =>
              @ir.TypeSpecificationBody::TypeAliasSpecification(params, body)
            CustomTypeDefinition(params, constructors) =>
              if constructors.access == @ir.Access::Public {
                @ir.TypeSpecificationBody::CustomTypeSpecification(
                  params,
                  constructors.value,
                )
              } else {
                @ir.TypeSpecificationBody::OpaqueTypeSpecification(params)
              }
            IncompleteTypeDefinition(_, _, _) =>
              raise Invalid(
                "data.lossy_conversion",
                "Public incomplete type has no complete specification: " +
                name.to_canonical(),
              )
          }
          types[name] = {
            doc: entry.value.doc,
            value: { annotations: [], body, },
          }
        }
        for name, entry in module_entry.value.values {
          if entry.access != @ir.Access::Public {
            continue
          }
          let specification = match entry.value.value.to_specification() {
            Some(specification) => specification
            None =>
              raise Invalid(
                "data.lossy_conversion",
                "Public value has no output type: " + name.to_canonical(),
              )
          }
          values[name] = { doc: entry.value.doc, value: specification, }
        }
        modules[module_name] = {
          annotations: [],
          types,
          values,
          doc: module_entry.value.doc,
        }
      }
      @ir.Distribution::Specs(name, dependencies, { modules, })
    }
  }
  let distribution = @ir.IRFile::new(
    distribution,
    format_version=self.distribution.format_version,
  )
  let owners = @identities.nodes(self.id, distribution)
  for entry in self.metadata {
    if !owners.contains(entry.node_id) {
      raise Invalid(
        "data.lossy_conversion",
        "Projection removes metadata owner: " + entry.node_id,
      )
    }
  }
  let result = {
    ..self,
    distribution,
    metadata: self.metadata.copy(),
    annotations: self.annotations.copy(),
    provenance: self.provenance.copy(),
  }
  result.validate()
  result
}
