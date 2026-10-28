///|
priv struct GraphFact {
  assertion : Assertion
  object : @ion.IonValue
  data : @ion.IonValue?
  is_json : Bool
}

///|
fn record(entries : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.Ion(@ion.IonValueKind::Struct(entries.map(e => @ion.field(e.0, e.1))))
}

///|
fn object(
  value : @ion.IonValue,
  coercion : String?,
) -> (@ion.IonValue, @ion.IonValue?, Bool) raise {
  if coercion == Some("@json") {
    return (
      record([("@value", value), ("@type", @ion.IonValue::string("@json"))]),
      Some(value),
      true,
    )
  }
  if value.kind() is Struct(_) {
    let parts = fields(value, "fact object")
    if parts.contains("@json") {
      if parts.length() != 1 {
        raise Invalid(
          "metadata.invalid_object", "@json", "A typed data wrapper has exactly one @json member",
        )
      }
      let data = parts["@json"]
      return (
        record([("@value", data), ("@type", @ion.IonValue::string("@json"))]),
        Some(data),
        true,
      )
    }
    if parts.contains("@id") {
      if parts.length() != 1 || coercion == Some("@json") {
        raise Invalid(
          "metadata.invalid_object", "@id", "Node links cannot replace declared typed data",
        )
      }
      ignore(address(text(parts["@id"], "@id")))
      return (value, None, false)
    }
    raise Invalid(
      "metadata.invalid_object", "fact object", "Use @json coercion or the @json or @id object form",
    )
  }
  if coercion == Some("@id") {
    let uri = text(value, "node link")
    ignore(address(uri))
    return (record([("@id", @ion.IonValue::string(uri))]), None, false)
  }
  (record([("@value", value)]), Some(value), false)
}

///|
fn graph(
  metadata : @ion.IonValue,
  context : Context,
  holder : String,
  document : String,
) -> Array[GraphFact] raise {
  let meta = fields(metadata, "$meta")
  let result = []
  if meta.get("@graph") is Some(value) {
    guard value.kind() is List(rows) else {
      raise Invalid(
        "metadata.invalid_graph", document, "@graph must be an array",
      )
    }
    if rows.length() > 100000 {
      raise Invalid(
        "metadata.graph_limit", document, "Graph exceeds 100000 rows",
      )
    }
    for ordinal, row in rows {
      let row = fields(row, document)
      let subject = text(required(row, "@id", document), "graph subject")
      ignore(address(subject))
      let keys = row.keys().collect()
      keys.sort()
      for property in keys {
        if property == "@id" {
          continue
        }
        if property.has_prefix("@") {
          raise Invalid(
            "metadata.unsupported_graph_keyword", property, "Only the default graph is supported",
          )
        }
        let (predicate, coercion) = context.expand(property)
        let objects = if coercion == Some("@json") {
          [row[property]]
        } else {
          match row[property].kind() {
            List(items) => items
            _ => [row[property]]
          }
        }
        for object_ordinal, value in objects {
          if coercion != Some("@json") && value.kind() is Null(_) {
            continue
          }
          let (expanded, data, is_json) = object(value, coercion)
          if result.length() >= 100000 {
            raise Invalid(
              "metadata.graph_limit", document, "Graph exceeds 100000 assertions",
            )
          }
          result.push({
            assertion: {
              holder,
              document,
              carrier: "documentGraph",
              subject,
              predicate,
              property,
              ordinal,
              object_ordinal,
            },
            object: expanded,
            data,
            is_json,
          })
        }
      }
    }
  }
  if meta.get("assertionSources") is Some(value) {
    guard value.kind() is List(rows) else {
      raise Invalid(
        "metadata.invalid_assertion_sources", document, "assertionSources must be an array",
      )
    }
    let selectors : Array[@ion.IonValue] = []
    for row in rows {
      let row = fields(row, document)
      let selector = required(row, "selector", document)
      let parsed = fields(selector, document)
      if parsed.length() != 4 {
        raise Invalid(
          "metadata.invalid_assertion_selector", document, "Supply carrier, subject, predicate and expanded object",
        )
      }
      let carrier = text(required(parsed, "carrier", document), document)
      let subject = text(required(parsed, "subject", document), document)
      let predicate = text(required(parsed, "predicate", document), document)
      let expanded = required(parsed, "object", document)
      if !result.any(f => {
          f.assertion.carrier == carrier &&
          f.assertion.subject == subject &&
          f.assertion.predicate == predicate &&
          f.object.equals(expanded)
        }) {
        raise Invalid(
          "metadata.unmatched_assertion_selector", document, "Match an authored assertion in this document; update selectors when editing facts",
        )
      }
      if selectors.any(s => s.equals(selector)) {
        raise Invalid(
          "metadata.duplicate_assertion_selector", document, "Supply one complete source set per selector",
        )
      }
      selectors.push(selector)
      guard required(row, "sources", document).kind() is List(sources) &&
        !sources.is_empty() else {
        raise Invalid(
          "metadata.invalid_assertion_sources", document, "Supply a nonempty complete source set",
        )
      }
      for source in sources {
        let source = fields(source, document)
        let kind = text(required(source, "kind", document), document)
        if !["document", "compiler", "author"].contains(kind) {
          raise Invalid(
            "metadata.invalid_assertion_sources", document, "Unknown source kind",
          )
        }
        ignore(text(required(source, "ref", document), document))
        if kind == "compiler" {
          ignore(text(required(source, "producer", document), document))
        }
      }
    }
  }
  result
}

///|
fn scoped_context(
  metadata : @ion.IonValue,
  parent : Context,
  capabilities : Capabilities,
  base : String,
) -> Context raise {
  let meta = fields(metadata, "$meta")
  match meta.get("@context") {
    Some(value) =>
      resolve_context(value, parent, capabilities, base, Map([]), Map([]))
    None => parent.copy()
  }
}
