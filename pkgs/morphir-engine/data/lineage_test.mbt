///|
fn rewrite_fixture() -> @data.IRUnit raise {
  @data.IRUnit::new("pricing", @fixtures.library(), metadata=[
    {
      node_id: "value:pricing:scalars#rate/body",
      data: @ion_text.read_ion(
        "unknown::unknown::{amount:12.340d0,blob:{{/wCA}},nil:null.int,duplicate:1,duplicate:2}",
      ),
    },
  ])
}

///|
fn remove_rate(unit : @data.IRUnit) -> @ir.IRFile raise {
  guard unit.distribution.distribution is Library(name, deps, def) else {
    fail("library")
  }
  let modules = def.modules.copy()
  let key = @ir.Path::parse("scalars")
  let entry = modules[key]
  let values = entry.value.values.copy()
  values.remove(@ir.Name::parse("rate"))
  modules[key] = { ..entry, value: { ..entry.value, values, }, }
  @ir.IRFile::new(@ir.Distribution::Library(name, deps, { modules, }))
}

///|
test "identity preserves rich Ion metadata and ordered annotations without projection" {
  let unit = rewrite_fixture()
  let result = @data.apply_rewrite(
    unit,
    { distribution: unit.distribution, lineage: None, },
    "identity",
    "retain",
    @data.MetadataPolicy::retain(),
  )
  assert_true(result.metadata[0].data.equals(unit.metadata[0].data))
  assert_eq(result.annotations, unit.annotations)
  assert_true(result.provenance.is_empty())
  // A semantic JSON component sees only IR, while a whole-unit export remains loss-aware.
  let projected = @data.semantic_json(unit)
  assert_eq(@ir_json.read(projected), unit.distribution)
  assert_true(
    try {
      ignore(@data.Registry::new().encode("morphir-json", unit))
      false
    } catch {
      @data.Invalid(code, _) => code == "data.lossy_conversion"
      _ => false
    },
  )
}

///|
test "structural rewrites require complete lineage and record removed rich metadata" {
  let unit = rewrite_fixture()
  let distribution = remove_rate(unit)
  assert_true(
    try {
      ignore(
        @data.apply_rewrite(
          unit,
          { distribution, lineage: None, },
          "remove",
          "retain",
          @data.MetadataPolicy::retain(),
        ),
      )
      false
    } catch {
      @data.Invalid(code, _) => code == "data.lineage_required"
      _ => false
    },
  )
  let before = @identities.nodes(unit.id, unit.distribution)
  let after = @identities.nodes(unit.id, distribution)
  let lineage : @data.Lineage = {
    retained: before.filter(id => after.contains(id)).map(id => (id, id)),
    removed: before.filter(id => !after.contains(id)),
    derived: [],
  }
  let result = @data.apply_rewrite(
    unit,
    { distribution, lineage: Some(lineage), },
    "remove-rate",
    "retain",
    @data.MetadataPolicy::retain(),
  )
  assert_true(result.metadata.is_empty())
  assert_eq(result.provenance.length(), 1)
  assert_true(lineage.removed.contains(unit.metadata[0].node_id))
  guard result.provenance[0].kind() is Struct(fields) else {
    fail("provenance")
  }
  let removed = fields
    .iter()
    .find_first(f => f.name().text() == Some("removed_metadata"))
    .unwrap()
    .value()
  guard removed.kind() is List([entry]) else { fail("removed metadata") }
  guard entry.kind() is Struct(entries) else { fail("entry") }
  assert_true(entries[1].value().equals(unit.metadata[0].data))
  for codec in ["ion-text", "ion-binary"] {
    let registry = @data.Registry::new()
    let restored = registry.decode(codec, {
      unit_id: unit.id,
      content: registry.encode(codec, result),
    })
    assert_true(restored.provenance[0].equals(result.provenance[0]))
  }
  let incomplete : @data.Lineage = { retained: [], derived: [], removed: [], }
  assert_true(
    try {
      ignore(
        @data.apply_rewrite(
          unit,
          { distribution, lineage: Some(incomplete), },
          "remove",
          "retain",
          @data.MetadataPolicy::retain(),
        ),
      )
      false
    } catch {
      @data.Invalid(code, _) => code == "data.incomplete_lineage"
      _ => false
    },
  )
}

///|
test "derived node metadata requires a registered policy and preserves unknown data" {
  let unit = rewrite_fixture()
  let source = unit.metadata[0].node_id
  let identity = @data.Lineage::identity(unit)
  let lineage : @data.Lineage = {
    retained: identity.retained.filter(p => p.0 != source),
    removed: [source],
    derived: [(source, [source])],
  }
  let rewrite : @data.Rewrite = {
    distribution: unit.distribution,
    lineage: Some(lineage),
  }
  assert_true(
    try {
      ignore(
        @data.apply_rewrite(
          unit,
          rewrite,
          "derive",
          "retain",
          @data.MetadataPolicy::retain(),
        ),
      )
      false
    } catch {
      @data.Invalid(code, _) => code == "data.metadata_policy_required"
      _ => false
    },
  )
  let result = @data.apply_rewrite(
    unit,
    rewrite,
    "derive",
    "copy-single-origin",
    @data.MetadataPolicy::copy_single_origin(),
  )
  assert_eq(result.metadata[0].node_id, source)
  assert_true(result.metadata[0].data.equals(unit.metadata[0].data))
  assert_eq(result.metadata[0].data.annotations().map(t => t.text()), [
    Some("unknown"),
    Some("unknown"),
  ])
  assert_eq(result.provenance.length(), 1)
}

///|
fn fl_name(text : String) -> @ir.Name {
  @ir.Name::parse(text) catch {
    _ => panic()
  }
}

///|
fn fl_ref(text : String, args : Array[@ir.Type]) -> @ir.Type {
  Reference(
    Default::default(),
    @ir.FQName::parse(text) catch {
      _ => panic()
    },
    args,
  )
}

///|
fn fl_int() -> @ir.Type {
  fl_ref("morphir/SDK:basics#int", [])
}

///|
fn fl_marked() -> @ir.Type {
  Variable(
    (Default::default() : @ir.TypeAttributes).with_unknown(),
    fl_name("t-0"),
  )
}

///|
/// A library `p` with `m#f = (1, 2)`, output type `output`. With `typed`, the tuple node has an inferred type,
/// so it is written in its expanded form; its literals stay compact.
fn fl_file(
  typed : Bool,
  output : @ir.Type,
  second~ : String = "2",
) -> @ir.IRFile {
  let pair : @ir.Type = Tuple(Default::default(), [fl_int(), fl_int()])
  let attrs : @ir.ValueAttributes = if typed {
    { source: None, inferred_type: Some(pair), extensions: Map([]), }
  } else {
    Default::default()
  }
  let body : @ir.Value = Tuple(attrs, [
    Literal(Default::default(), IntegerLiteral("1")),
    Literal(Default::default(), IntegerLiteral(second)),
  ])
  let def : @ir.ValueDefinition = ExpressionBody([], output, body)
  let module_def : @ir.ModuleDefinition = {
    types: Map([]),
    values: Map([
      (fl_name("f"), { access: Public, value: { doc: None, value: def, }, }),
    ]),
    doc: None,
  }
  @ir.IRFile::new(
    Library(@ir.Path::parse("p") catch { _ => panic() }, Map([]), {
      modules: Map([
        (
          @ir.Path::parse("m") catch {
            _ => panic()
          },
          { access: Public, value: module_def, },
        ),
      ]),
    }),
  ) catch {
    _ => panic()
  }
}

///|
test "fill_lineage retains every old identity and derives the new attribute nodes" {
  let before = @data.IRUnit::new("u", fl_file(false, fl_int()))
  let after = fl_file(true, fl_int())
  let lineage = @data.fill_lineage(before, after)
  assert_eq(lineage.removed, [])
  assert_eq(
    lineage.retained.length(),
    @identities.nodes("u", before.distribution).length(),
  )
  assert_true(lineage.derived.length() > 0)
  assert_true(lineage.derived.iter().all(d => d.1.length() == 1))
  // The tuple's second item moves from `/Tuple/1` to `/Tuple/elements/1` and keeps its identity.
  assert_true(
    lineage.retained.contains(
      ("value:p:m#f/body/Tuple/1", "value:p:m#f/body/Tuple/elements/1"),
    ),
  )
}

///|
test "metadata survives compact to expanded" {
  let data = @ion_text.read_ion("{note:\"second item\"}")
  let before = @data.IRUnit::new("u", fl_file(false, fl_int()), metadata=[
    { node_id: "value:p:m#f/body/Tuple/1", data, },
  ])
  let after = fl_file(true, fl_int())
  let result = @data.apply_rewrite(
    before,
    { distribution: after, lineage: Some(@data.fill_lineage(before, after)), },
    "inference",
    "inference",
    @data.MetadataPolicy::no_derived(),
  )
  assert_eq(result.metadata.length(), 1)
  assert_eq(result.metadata[0].node_id, "value:p:m#f/body/Tuple/elements/1")
  assert_true(result.metadata[0].data.equals(data))
}

///|
test "a marker variable that becomes List Int is retained, and its new nodes are derived from it" {
  let before = @data.IRUnit::new("u", fl_file(false, fl_marked()))
  let after = fl_file(false, fl_ref("morphir/SDK:list#list", [fl_int()]))
  let lineage = @data.fill_lineage(before, after)
  let marker = "value:p:m#f/output"
  assert_true(lineage.retained.contains((marker, marker)))
  assert_true(
    lineage.derived
    .iter()
    .any(d => d.0 == marker + "/Reference/1" && d.1 == [marker]),
  )
  // Only the marker's own content is gone, in each identity family.
  assert_true(lineage.removed.iter().all(id => id.contains("/Variable")))
  assert_true(lineage.removed.length() > 0)
}

///|
test "a change that is not an attribute or a marker is refused" {
  let before = @data.IRUnit::new("u", fl_file(false, fl_int()))
  let changed = fl_file(true, fl_int(), second="3")
  let refused = try {
    ignore(@data.fill_lineage(before, changed))
    false
  } catch {
    @data.Invalid(code, _) => code == "data.not_attribute_only"
    _ => false
  }
  assert_true(refused)
}

///|
/// A tuple type of 11 items: Int, apart from item 1, which is the marker variable when `marked`, and item 10,
/// which is `tenth`.
fn fl_eleven(marked : Bool, tenth~ : @ir.Type = fl_int()) -> @ir.Type {
  let items : Array[@ir.Type] = Array::makei(11, i => {
    if i == 1 && marked {
      fl_marked()
    } else if i == 10 {
      tenth
    } else {
      fl_int()
    }
  })
  Tuple(Default::default(), items)
}

///|
test "a node below a marker is skipped, and a sibling whose path starts with the marker's path is not" {
  // The marker is `output/items/1`; `output/items/10` starts with that text but is not below it.
  let before = @data.IRUnit::new("u", fl_file(false, fl_eleven(true)))
  let filled = @data.fill_lineage(before, fl_file(false, fl_eleven(false)))
  assert_true(filled.removed.length() > 0)
  assert_true(filled.removed.iter().all(id => id.contains("/Tuple/1/Variable")))
  let changed = fl_file(
    false,
    fl_eleven(false, tenth=fl_ref("morphir/SDK:basics#float", [])),
  )
  let refused = try {
    ignore(@data.fill_lineage(before, changed))
    None
  } catch {
    @data.Invalid(code, path) => Some((code, path))
    _ => None
  }
  guard refused is Some((code, path)) else { fail("not refused") }
  assert_eq(code, "data.not_attribute_only")
  assert_true(path.contains("/output/items/10"))
}
