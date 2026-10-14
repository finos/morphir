///|
pub(all) struct Lineage {
  retained : Array[(String, String)]
  derived : Array[(String, Array[String])]
  removed : Array[String]
}

///|
pub fn Lineage::identity(unit : IRUnit) -> Lineage raise {
  {
    retained: @identities.nodes(unit.id, unit.distribution).map(id => (id, id)),
    derived: [],
    removed: [],
  }
}

///|
pub(all) struct Rewrite {
  distribution : @ir.IRFile
  lineage : Lineage?
}

///|
pub(all) struct MetadataPolicy {
  propagate : (String, Array[NodeMetadata]) -> @ion.IonValue? raise
}

///|
pub fn MetadataPolicy::retain() -> MetadataPolicy {
  {
    propagate: fn(id, origins) raise {
      if !origins.is_empty() {
        raise Invalid(
          "data.metadata_policy_required",
          "Derived metadata for " + id,
        )
      }
      None
    },
  }
}

///|
pub fn MetadataPolicy::copy_single_origin() -> MetadataPolicy {
  {
    propagate: fn(id, origins) raise {
      if origins.length() > 1 {
        raise Invalid("data.metadata_merge_required", id)
      }
      origins.get(0).map(m => m.data)
    },
  }
}

///|
/// A policy that attaches no metadata to a derived node. Inference uses it: a type that a fill writes has no
/// metadata of its own.
pub fn MetadataPolicy::no_derived() -> MetadataPolicy {
  { propagate: fn(_, _) { None }, }
}

///|
/// The longest proper prefix of `path` cut at a `/` or a `!`, or `None` at a logical root.
fn parent(path : String) -> String? {
  let cut = match (path.rev_find("/"), path.rev_find("!")) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) | (None, Some(a)) => Some(a)
    (None, None) => None
  }
  cut.map(i => path[:i].to_owned())
}

///|
/// Whether `path` is one of `markers` or a path below one. A marker that `path` is below is a prefix of `path` cut
/// at a `/` or a `!`, so the search looks up only those prefixes.
fn below_marker(path : String, markers : Map[String, Bool]) -> Bool {
  let mut p = Some(path)
  while p is Some(q) {
    if markers.contains(q) {
      return true
    }
    p = parent(q)
  }
  false
}

///|
/// The longest proper prefix of `path`, cut at a `/` or a `!`, that `known` has. Logical roots are identities
/// that every file has, so the search ends.
fn origin(path : String, known : Map[String, String]) -> String? {
  let mut p = parent(path)
  while p is Some(q) {
    if known.get(q) is Some(id) {
      return Some(id)
    }
    p = parent(q)
  }
  None
}

///|
/// Checks that `from` and `to` are equal apart from attributes and apart from the nodes below `markers`: every
/// tagged node and every leaf of `from` is in `to`, with the same tag or value.
fn same_shape(
  from : Array[@identities.LogicalNode],
  to : Array[@identities.LogicalNode],
  markers : Map[String, Bool],
) -> Unit raise {
  let tags : Map[String, String] = Map([])
  let leaves : Map[String, Json] = Map([])
  for n in to {
    if n.tag != "" {
      tags[n.path] = n.tag
    }
    if n.leaf is Some((p, v)) && !n.attribute {
      leaves[p] = v
    }
  }
  for n in from {
    if n.attribute || below_marker(n.path, markers) {
      continue
    }
    if n.tag != "" && tags.get(n.path) != Some(n.tag) {
      raise Invalid("data.not_attribute_only", n.path)
    }
    if n.leaf is Some((p, v)) && leaves.get(p) != Some(v) {
      raise Invalid("data.not_attribute_only", p)
    }
  }
}

///|
/// The lineage of a rewrite that changes only attributes and the variables of `before` that carry the unknown
/// marker, such as an inference fill. Nodes are joined by logical path (`@identities.logical_nodes`), so a node
/// keeps its identity when its compact form becomes expanded.
///
/// - A node with the same logical path in both is `retained`. A replaced marker variable is retained, because its
///   replacement has its logical path.
/// - A node only in `after` is `derived` from the nearest node above it that `before` has: a new attribute node
///   from its owner, a node under a replaced marker from the marker.
/// - A node only in `before` is `removed`.
///
/// Any other difference raises `data.not_attribute_only` with the logical path.
pub fn fill_lineage(before : IRUnit, after : @ir.IRFile) -> Lineage raise {
  let from = @identities.logical_nodes(before.id, before.distribution)
  let to = @identities.logical_nodes(before.id, after)
  let markers = Map::from_array(
    from.filter(n => n.marker).map(n => (n.path, true)),
  )
  same_shape(from, to, markers)
  same_shape(to, from, markers)
  let old : Map[String, String] = Map([])
  for n in from {
    old[n.path] = n.id
  }
  let new : Map[String, Bool] = Map([])
  let retained : Array[(String, String)] = []
  let derived : Array[(String, Array[String])] = []
  for n in to {
    new[n.path] = true
    match old.get(n.path) {
      Some(id) => retained.push((id, n.id))
      None =>
        match origin(n.path, old) {
          Some(id) => derived.push((n.id, [id]))
          None => raise Invalid("data.not_attribute_only", n.path)
        }
    }
  }
  let removed = from.filter(n => !new.contains(n.path)).map(n => n.id)
  { retained, derived, removed, }
}

///|
fn lineage_record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::from_fields(fields.map(p => @ion.Field::new(p.0, p.1)))
}

///|
fn ids_ion(ids : Array[String]) -> @ion.IonValue {
  @ion.IonValue::list(ids.map(@ion.IonValue::string))
}

///|
/// Semantic JSON projection is explicit; rich metadata and annotations never enter it.
pub fn semantic_json(unit : IRUnit) -> String raise {
  @ir_json.write(unit.distribution)
}

///|
pub fn apply_rewrite(
  unit : IRUnit,
  rewrite : Rewrite,
  component : String,
  policy_name : String,
  policy : MetadataPolicy,
) -> IRUnit raise {
  let before = @identities.nodes(unit.id, unit.distribution)
  let after = @identities.nodes(unit.id, rewrite.distribution)
  let lineage = match rewrite.lineage {
    Some(lineage) => lineage
    None if rewrite.distribution == unit.distribution => return unit
    None => raise Invalid("data.lineage_required", component)
  }
  let before_set = Map::from_array(before.map(id => (id, true)))
  let after_set = Map::from_array(after.map(id => (id, true)))
  let sources = Map([])
  let targets = Map([])
  for (source, target) in lineage.retained {
    if !before_set.contains(source) ||
      !after_set.contains(target) ||
      sources.contains(source) ||
      targets.contains(target) {
      raise Invalid("data.invalid_lineage", source + " -> " + target)
    }
    sources[source] = true
    targets[target] = true
  }
  for source in lineage.removed {
    if !before_set.contains(source) || sources.contains(source) {
      raise Invalid("data.invalid_lineage", source)
    }
    sources[source] = true
  }
  for (target, origins) in lineage.derived {
    if !after_set.contains(target) ||
      targets.contains(target) ||
      origins.is_empty() ||
      !origins.all(id => before_set.contains(id)) {
      raise Invalid("data.invalid_lineage", target)
    }
    let seen = Map([])
    for origin in origins {
      if seen.contains(origin) {
        raise Invalid("data.invalid_lineage", "Duplicate origin " + origin)
      }
      seen[origin] = true
    }
    targets[target] = true
  }
  if sources.length() != before.length() || targets.length() != after.length() {
    raise Invalid("data.incomplete_lineage", component)
  }
  let seen = Map([])
  for entry in unit.metadata {
    if !before_set.contains(entry.node_id) || seen.contains(entry.node_id) {
      raise Invalid("data.metadata_identity", entry.node_id)
    }
    seen[entry.node_id] = true
  }
  let metadata = []
  for entry in unit.metadata {
    let target = lineage.retained.iter().find_first(p => p.0 == entry.node_id)
    if target is Some((_, target)) {
      metadata.push({ node_id: target, data: entry.data, })
    }
  }
  for (target, origins) in lineage.derived {
    let propagateed = unit.metadata.filter(m => origins.contains(m.node_id))
    if (policy.propagate)(target, propagateed) is Some(data) {
      metadata.push({ node_id: target, data, })
    }
  }
  let provenance = lineage_record([
    ("component", @ion.IonValue::string(component)),
    ("metadata_policy", @ion.IonValue::string(policy_name)),
    (
      "retained",
      @ion.IonValue::list(
        lineage.retained.map(p => {
          lineage_record([
            ("source", @ion.IonValue::string(p.0)),
            ("target", @ion.IonValue::string(p.1)),
          ])
        }),
      ),
    ),
    (
      "derived",
      @ion.IonValue::list(
        lineage.derived.map(p => {
          lineage_record([
            ("target", @ion.IonValue::string(p.0)),
            ("origins", ids_ion(p.1)),
          ])
        }),
      ),
    ),
    ("removed", ids_ion(lineage.removed)),
    (
      "removed_metadata",
      @ion.IonValue::list(
        unit.metadata
        .filter(m => lineage.removed.contains(m.node_id))
        .map(m => {
          lineage_record([
            ("node_id", @ion.IonValue::string(m.node_id)),
            ("data", m.data),
          ])
        }),
      ),
    ),
  ]).with_annotation(@ion.SymbolToken::new("morphir_rewrite"))
  {
    ..unit,
    distribution: rewrite.distribution,
    metadata,
    provenance: unit.provenance + [provenance],
  }
}
