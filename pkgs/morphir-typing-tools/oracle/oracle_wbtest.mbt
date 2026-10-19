///|
fn deps() -> Map[@ir.PackageName, @ir.PackageSpecification] {
  Map::from_array([
    (@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification()),
  ])
}

///|
fn classic() -> Array[(String, @ir.IRFile)] {
  [
    ("classic-greeting", @elm_fixtures.classic_greeting()),
    ("classic-rentals-v1", @elm_fixtures.classic_rentals_v1()),
    ("classic-rentals-v2", @elm_fixtures.classic_rentals_v2()),
  ]
}

///|
/// `strip_node_types` keeps the top-level signatures. Classic IR does not separate annotated top-level signatures
/// from inferred ones, so stripping them would give types that are correctly more general than the Elm annotations,
/// for example `comparable` for an `Int` parameter. `strip_node_types` clears every node type. morphir-elm's let
/// placeholders already have the unknown marker from the migration to v4. Inference must then give every node type
/// and every signature type that is not a placeholder, up to variable renaming and alias expansion.
test "criterion B: stripped classic IR infers the morphir-elm types" {
  for entry in classic() {
    let (name, original) = entry
    let filled = @typing.infer(strip_node_types(original), deps(), Fill) catch {
      InferenceFailed(problems) =>
        fail(
          name +
          ": " +
          problems
          .map(p => p.code + " at " + p.node + ": " + p.message)
          .join("; "),
        )
    }
    let mismatches = @typing.compare_types(original, filled, deps())
    assert_eq(mismatches, [], msg=name)
  }
}

///|
/// Fill over fully typed classic IR: every node, patterns included, has a type, and each one is a fact during
/// inference. The fill must succeed and give the same types.
test "fill over fully typed classic IR keeps its types" {
  for entry in classic() {
    let (name, original) = entry
    let filled = @typing.infer(original, deps(), Fill) catch {
      InferenceFailed(problems) =>
        fail(
          name +
          ": " +
          problems
          .map(p => p.code + " at " + p.node + ": " + p.message)
          .join("; "),
        )
    }
    assert_eq(@typing.compare_types(original, filled, deps()), [], msg=name)
  }
}

///|
/// Classic IR is checked strictly. The migration to v4 marks morphir-elm's let placeholders: they are not
/// annotations.
test "criterion C: classic IR passes check unchanged, and a mutation is found" {
  for entry in classic() {
    let (name, original) = entry
    assert_eq(@typing.infer(original, deps(), Check), original, msg=name)
    let (mutated, path) = mutate_first_literal_type(original)
    let codes = try {
      ignore(@typing.infer(mutated, deps(), Check))
      []
    } catch {
      InferenceFailed(problems) => problems.map(p => (p.code, p.node))
    }
    assert_eq(codes, [("annotation_mismatch", path)], msg=name)
  }
}

///|
/// The classic fixtures have no type variable in a node type, so the two mutations of the variables run on
/// elm-shapes: `largest : List a -> Maybe a`, where `a` is a number by its `typeclass`. Its node types come from
/// Fill after `strip_node_types`. Check must find a node whose signature variable is swapped for another one,
/// and a node whose variable lost its class, each at the exact path.
test "criterion C: check finds a swapped rigid variable and a dropped class" {
  let shapes = @typing.infer(
    strip_node_types(@elm_fixtures.shapes()),
    deps(),
    Fill,
  )
  assert_eq(@typing.infer(shapes, deps(), Check), shapes)
  for mutation in [mutate_first_rigid, drop_first_class] {
    let (mutated, path) = mutation(shapes)
    assert_true(path.has_prefix("value:acme/shapes:geometry#largest/"))
    let codes = try {
      ignore(@typing.infer(mutated, deps(), Check))
      []
    } catch {
      InferenceFailed(problems) => problems.map(p => (p.code, p.node))
    }
    assert_eq(codes, [("annotation_mismatch", path)], msg=path)
    // The oracle reports the same node.
    let lines = @typing.compare_types(shapes, mutated, deps())
    assert_eq(lines.length(), 1, msg=path)
    assert_true(lines[0].has_prefix(path + ": expected "))
  }
}

///|
/// `strip_full` also replaces every top-level signature type with an unknown variable, so inference must solve
/// every signature and type every node. Each original corpus must also pass `Check` unchanged, before it is
/// stripped.
test "criterion A: every fixture corpus fills completely" {
  let corpus : Array[(String, @ir.IRFile)] = [
    ("elm-rentals", @elm_fixtures.rentals()),
    ("elm-shapes", @elm_fixtures.shapes()),
  ]
  let moonbit = [
    ("moonbit-library", @fixtures.library()),
    ("moonbit-pricing", @fixtures.pricing()),
    ("moonbit-acceptance", @fixtures.acceptance_library()),
    ("moonbit-invocation", @fixtures.invocation_library()),
    ("moonbit-conformance", @fixtures.conformance()),
    ("moonbit-rust", @fixtures.rust_conformance()),
  ] catch {
    _ => fail("fixture")
  }
  for item in moonbit {
    corpus.push(item)
  }
  for entry in corpus {
    let (name, file) = entry
    let checked = @typing.infer(file, deps(), Check) catch {
      InferenceFailed(problems) =>
        fail(
          name +
          " (check): " +
          problems
          .map(p => p.code + " at " + p.node + ": " + p.message)
          .join("; "),
        )
    }
    assert_eq(checked, file, msg=name)
    let filled = @typing.infer(strip_full(file), deps(), Fill) catch {
      InferenceFailed(problems) =>
        fail(
          name + ": " + problems.map(p => p.code + " at " + p.node).join("; "),
        )
    }
    assert_eq(count_untyped(filled), 0, msg=name)
    assert_eq(marked_signatures(filled), [], msg=name)
  }
}

///|
/// The signature paths of `file` whose types still have a variable with the unknown marker.
fn marked_signatures(file : @ir.IRFile) -> Array[String] {
  let out : Array[String] = []
  visit(file, (_, _, _) => (), (def, path, _) => {
    for entry in signature_entries(def, path) {
      if has_marked_variable(entry.1) {
        out.push(entry.0)
      }
    }
  })
  out
}

///|
fn has_marked_variable(t : @ir.Type) -> Bool {
  let marked = fn(attrs : @ir.TypeAttributes) {
    attrs.extensions.get("morphir.inference") is Some(Text("unknown"))
  }
  match t {
    Variable(attrs, _) => marked(attrs)
    Unit(_) => false
    Reference(_, _, items) | Tuple(_, items) | Union(_, items) =>
      items.iter().any(has_marked_variable)
    Record(_, fields) => fields.values().any(has_marked_variable)
    ExtensibleRecord(attrs, _, fields) =>
      marked(attrs) || fields.values().any(has_marked_variable)
    Function(_, input, output) =>
      has_marked_variable(input) || has_marked_variable(output)
  }
}

///|
/// The top-level signature types of `file`, keyed `<path>:input/<i>` and `<path>:output`, in walk order.
fn top_level_signatures(file : @ir.IRFile) -> Array[(String, @ir.Type)] {
  let out : Array[(String, @ir.Type)] = []
  visit(file, (_, _, _) => (), (def, path, is_let) => {
    if !is_let {
      out.append(signature_entries(def, path))
    }
  })
  out
}

///|
/// The let-signature paths of `file` whose types have a morphir-elm placeholder, in walk order.
fn placeholder_paths(file : @ir.IRFile) -> Array[String] {
  let out : Array[String] = []
  visit(file, (_, _, _) => (), (def, path, is_let) => {
    for entry in signature_entries(def, path) {
      if is_let && has_placeholder(entry.1) {
        out.push(entry.0)
      }
    }
  })
  out
}

///|
/// Whether `t` has a morphir-elm placeholder variable or row variable.
fn has_placeholder(t : @ir.Type) -> Bool {
  let placeholder = @migration.is_classic_placeholder
  match t {
    Variable(_, name) => placeholder(name)
    Unit(_) => false
    Reference(_, _, items) | Tuple(_, items) | Union(_, items) =>
      items.iter().any(has_placeholder)
    Record(_, fields) => fields.values().any(has_placeholder)
    ExtensibleRecord(_, row, fields) =>
      placeholder(row) || fields.values().any(has_placeholder)
    Function(_, input, output) =>
      has_placeholder(input) || has_placeholder(output)
  }
}

///|
test "placeholders: only t-<digits> variables of let signatures are marked" {
  // `pkgs/morphir-typing/compare_files_wbtest.mbt` tests which names are placeholders.
  // classic-greeting has exactly one placeholder signature type: the output of the `discount` let.
  let greeting = @elm_fixtures.classic_greeting()
  assert_eq(placeholder_paths(greeting), [
    "value:elm-compat:main#apply-discount/body/definition:output",
  ])
  // The migration marks only that let signature.
  assert_eq(marked_signatures(greeting), [
    "value:elm-compat:main#apply-discount/body/definition:output",
  ])
  let top_level = top_level_signatures(greeting)
  assert_true(top_level.length() > 0)
  assert_true(top_level.iter().all(e => !has_marked_variable(e.1)))
}

///|
test "the oracle reports a changed node type" {
  let original = @elm_fixtures.classic_rentals_v1()
  let (mutated, path) = mutate_first_literal_type(original)
  let lines = @typing.compare_types(original, mutated, deps())
  assert_eq(lines.length(), 1)
  assert_true(lines[0].has_prefix(path + ": expected "))
  assert_eq(@typing.compare_types(original, original, deps()), [])
  assert_true(count_untyped(strip_node_types(original)) > 0)
  assert_true(count_untyped(strip_full(original)) > 0)
  // `strip_full` marks every top-level signature type, and `strip_node_types` marks none.
  let top_level = fn(file : @ir.IRFile) {
    top_level_signatures(file).map(e => e.0)
  }
  assert_true(top_level(original).length() > 0)
  assert_eq(marked_signatures(strip_full(original)), top_level(original))
  assert_eq(marked_signatures(strip_node_types(original)), [])
  assert_eq(count_untyped(original), 0)
}

///|
fn type_ref(fq : String, args : Array[@ir.Type]) -> @ir.Type {
  Reference(
    Default::default(),
    @ir.FQName::parse(fq) catch {
      _ => abort(fq)
    },
    args,
  )
}

///|
fn path_of(text : String) -> @ir.Path {
  @ir.Path::parse(text) catch {
    _ => abort(text)
  }
}

///|
test "C3: compare_types reports a let signature that differs outside its placeholder" {
  // classic-greeting's `discount` let has the output `t-8`. Write it as `List t-8`: the inferred output is not a
  // list, so the oracle reports the path. Before, any let signature type with a placeholder was skipped.
  let original = @elm_fixtures.classic_greeting()
  let filled = @typing.infer(strip_node_types(original), deps(), Fill)
  let at = "value:elm-compat:main#apply-discount/body/definition"
  let changed = map_declarations(original, (def, root) => {
    let walker : Walker = {
      node: (a, _, _) => a,
      signature: (def, path) => {
        guard path == at && def is ExpressionBody(xs, out, body) else { def }
        ExpressionBody(xs, type_ref("morphir/SDK:list#list", [out]), body)
      },
    }
    walker.definition(def, root)
  })
  let lines = @typing.compare_types(changed, filled, deps())
  assert_eq(lines.length(), 1)
  assert_true(lines[0].has_prefix(at + ":output: expected "))
  assert_eq(@typing.compare_types(original, filled, deps()), [])
}

///|
test "C2: inference and the oracle do not walk bundled bodies or IncompleteBody values" {
  // An application bundles classic-greeting with its node types stripped. Its own module has one draft value,
  // `draft : () = <Draft> ()`. Bundled bodies are trusted and an incomplete value is not inferred, so Fill
  // writes no type into either, and the oracle does not count their nodes.
  guard strip_node_types(@elm_fixtures.classic_greeting()).distribution
    is Library(dep_name, _, dep_def) else {
    fail("library")
  }
  let unit_type : @ir.Type = Unit(Default::default())
  let draft = @ir.ValueDefinition::IncompleteBody(
    [],
    Some(unit_type),
    Draft,
    Some(Unit(Default::default())),
  )
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map::from_array([
    (
      @ir.Name::from_words(["draft"]),
      { access: Public, value: { doc: None, value: draft, }, },
    ),
  ])
  let own : @ir.PackageDefinition = {
    modules: Map::from_array([
      (
        path_of("m"),
        { access: Public, value: { types: Map([]), values, doc: None, }, },
      ),
    ]),
  }
  let app = @ir.IRFile::new(
    Application(
      path_of("acme/main"),
      Map::from_array([(dep_name, dep_def)]),
      own,
      Map([]),
    ),
  )
  let filled = @typing.infer(app, deps(), Fill)
  guard filled.distribution is Application(_, bundled, def, _) else {
    fail("application")
  }
  assert_true(bundled.get(dep_name) == Some(dep_def))
  let after = def.modules[path_of("m")].value.values[@ir.Name::from_words([
      "draft",
    ])].value.value
  assert_eq(after, draft)
  assert_true(count_untyped(dep_def_file(dep_name, dep_def)) > 0)
  assert_eq(count_untyped(filled), 0)
}

///|
fn dep_def_file(
  name : @ir.PackageName,
  def : @ir.PackageDefinition,
) -> @ir.IRFile {
  @ir.IRFile::new(Library(name, Map([]), def)) catch {
    _ => abort("bad file")
  }
}
