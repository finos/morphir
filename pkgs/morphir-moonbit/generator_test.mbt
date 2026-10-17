///|
fn single(
  output : @ir.Type,
  body : @ir.Value,
  definition~ : @ir.ValueDefinition? = None,
) -> @generator.Input raise {
  let name = @ir.Name::parse("value")
  let value : @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] = match
    definition {
    Some(definition) =>
      { access: @ir.Access::Public, value: { doc: None, value: definition, }, }
    None => @fixtures.definition(output, body)
  }
  let module_def : @ir.ModuleDefinition = {
    types: Map([]),
    doc: None,
    values: Map::from_array([(name, value)]),
  }
  @generator.Input::new(
    "single",
    @ir.IRFile::new(
      @ir.Distribution::Library(@ir.Path::parse("sample"), Map([]), {
        modules: Map::from_array([
          (
            @ir.Path::parse("main"),
            { access: @ir.Access::Public, value: module_def, },
          ),
        ]),
      }),
    ),
  )
}

///|
fn error(input : @generator.Input) -> (String, String) {
  try {
    ignore(@generator.generate(input))
    ("", "")
  } catch {
    @generator.Invalid(code, context, _) => (code, context)
  }
}

///|
fn library_source(input : @generator.Input) -> String raise {
  let output = @generator.generate(input)
  guard output.artifacts.search_by(a => a.path == "library.mbt") is Some(i) &&
    output.artifacts[i].content is Text(text) else {
    fail("library.mbt")
  }
  text
}

///|
test "a private nominal type that a public signature or public payload names is emitted abstract" {
  let nominal = @fixtures.scalar("sample:main#hidden")
  let hidden_case = @ir.Value::Constructor(
    { ..@fixtures.attrs(), inferred_type: Some(nominal), },
    @ir.FQName::parse("sample:main#hidden-case"),
  )
  let input = single(nominal, hidden_case)
  guard input.ir.distribution
    is Library(package_name, dependencies, package_def) else {
    fail("library")
  }
  let path = @ir.Path::parse("main")
  let entry = package_def.modules[path]
  let types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ] = Map::from_array([
    (
      @ir.Name::parse("hidden"),
      {
        access: @ir.Access::Private,
        value: {
          doc: None,
          value: @ir.TypeDefinition::CustomTypeDefinition([], {
            access: @ir.Access::Private,
            value: Map::from_array([(@ir.Name::parse("hidden-case"), [])]),
          }),
        },
      },
    ),
  ])
  let modules = package_def.modules.copy()
  modules[path] = { ..entry, value: { ..entry.value, types, }, }
  let updated = {
    ..input,
    ir: @ir.IRFile::new(
      @ir.Distribution::Library(package_name, dependencies, { modules, }),
    ),
  }
  assert_eq(error(updated), ("", ""))
  let source = library_source(updated)
  // No visibility modifier: other packages name `Hidden`, but not its constructor.
  assert_true(source.contains("///|\nenum Hidden {"), msg=source)
  assert_true(source.contains("pub fn value()"), msg=source)
  types[@ir.Name::parse("wrapper")] = {
    access: @ir.Access::Public,
    value: {
      doc: None,
      value: @ir.TypeDefinition::CustomTypeDefinition([], {
        access: @ir.Access::Private,
        value: Map::from_array([
          (@ir.Name::parse("wrap"), [(@ir.Name::parse("payload"), nominal)]),
        ]),
      }),
    },
  }
  let wrapper = @fixtures.scalar("sample:main#wrapper")
  let wrap = @ir.Value::Constructor(
    {
      ..@fixtures.attrs(),
      inferred_type: Some(
        @ir.Type::Function(
          { source: None, constraints: Map([]), extensions: Map([]), },
          nominal,
          wrapper,
        ),
      ),
    },
    @ir.FQName::parse("sample:main#wrap"),
  )
  let wrapped = single(
    wrapper,
    @ir.Value::Apply(
      { ..@fixtures.attrs(), inferred_type: Some(wrapper), },
      wrap,
      hidden_case,
    ),
  )
  guard wrapped.ir.distribution is Library(_, _, opaque_def) else {
    fail("library")
  }
  let opaque_entry = opaque_def.modules[path]
  opaque_def.modules[path] = {
    ..opaque_entry,
    value: { ..opaque_entry.value, types, },
  }
  assert_eq(error(wrapped), ("", ""))
  let source = library_source(wrapped)
  assert_true(source.contains("///|\npub enum Wrapper {"), msg=source)
  assert_true(source.contains("///|\nenum Hidden {"), msg=source)
}

///|
test "deterministic flattened library preserves public and private symbols" {
  let result = @generator.generate(
    @generator.Input::new("scalars", @fixtures.library()),
  )
  let reordered = @generator.generate(
    @generator.Input::new("scalars", @fixtures.library(reverse=true)),
  )
  assert_eq(result.artifacts, reordered.artifacts)
  assert_eq(result.project, reordered.project)
  assert_eq(result.symbols, reordered.symbols)
  assert_eq(result.symbols.length(), 13)
  assert_eq(result.project.members, [
    "moon.mod", "moon.pkg", "library.mbt", "symbols.10n",
  ])
  assert_true(
    result.symbols.any(s => s.fqname == "pricing:internal#secret" && !s.public),
  )
  assert_true(
    result.symbols.any(s => s.fqname == "pricing:scalars#hidden" && !s.public),
  )
  assert_true(
    result.symbols.any(s => s.fqname == "pricing:other#copy" && s.public),
  )
  assert_eq(
    result.project.dependencies[0].api_profile,
    "morphir-sdk-concrete-v1",
  )
}

///|
test "FQName encoding distinguishes initialisms words package and module boundaries" {
  let identities = [
    "example:main#SDK", "example:main#sdk", "example:main#s-d-k", "example:main#s-dk",
    "example/main:other#sdk", "example:main/other#sdk",
  ]
  let names = Map([])
  for identity in identities {
    let name = @generator.value_name(@ir.FQName::parse(identity))
    assert_false(names.contains(name))
    assert_true(name.has_prefix("v_"))
    names[name] = true
  }
  let malformed : @ir.FQName = {
    package_name: @ir.Path::parse("example"),
    module_name: @ir.Path::parse("main"),
    local_name: @ir.Name::from_words(["SDK"]),
  }
  assert_true(
    try {
      ignore(@generator.value_name(malformed))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "exact decimal construction refuses SDK truncation and float bits remain exact" {
  let decimal = @fixtures.scalar("morphir/SDK:decimal#decimal")
  let valid = single(
    decimal,
    @ir.Value::Literal(
      @fixtures.attrs(),
      @ir.Literal::DecimalLiteral("1.000000000000000000000000000000000"),
    ),
  )
  assert_eq(error(valid).0, "")
  let loss = single(
    decimal,
    @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::DecimalLiteral("1e-33")),
  )
  assert_eq(
    error(loss),
    ("moonbit.literal_precision_loss", "value:sample:main#value/body"),
  )
  let zero = single(
    decimal,
    @ir.Value::Literal(
      @fixtures.attrs(),
      @ir.Literal::DecimalLiteral("-0.000000000000000000000000000000000"),
    ),
  )
  assert_eq(error(zero).0, "")
  let out = @generator.generate(
    @generator.Input::new("scalars", @fixtures.library()),
  )
  let source = match out.artifacts[2].content {
    Text(s) => s
    Binary(_) => fail("Expected source")
  }
  assert_true(source.contains("9223372036854775808UL"))
  assert_true(source.contains("(1UL).reinterpret_as_double()"))
  assert_true(
    source.contains(
      "@integer.parse(\"1234567890123456789012345678901234567890\")",
    ),
  )
}

///|
test "declared and inferred types must agree with scalar bodies" {
  let boolean = @fixtures.scalar("morphir/SDK:basics#bool")
  let integer = @fixtures.scalar("morphir/SDK:basics#int")
  let mismatch = single(
    boolean,
    @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("1")),
  )
  assert_eq(error(mismatch).0, "moonbit.type_mismatch")
  let inferred = { ..@fixtures.attrs(), inferred_type: Some(integer), }
  assert_eq(
    error(
      single(
        boolean,
        @ir.Value::Literal(inferred, @ir.Literal::BoolLiteral(true)),
      ),
    ).0,
    "moonbit.type_mismatch",
  )
  let ambiguous = @ir.Type::Variable(
    { source: None, constraints: Map([]), extensions: Map([]), },
    @ir.Name::parse("number"),
  )
  assert_eq(
    error(
      single(
        ambiguous,
        @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("1")),
      ),
    ).0,
    "moonbit.ambiguous_type",
  )
  let unknown = @fixtures.scalar("morphir/sdk:basics#int")
  assert_eq(
    error(
      single(
        unknown,
        @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("1")),
      ),
    ).0,
    "moonbit.unsupported_type",
  )
}

///|
test "unsupported distributions bodies and unresolved references fail contextually" {
  let boolean = @fixtures.scalar("morphir/SDK:basics#bool")
  let hole = @ir.Value::Hole(
    @fixtures.attrs(),
    @ir.HoleReason::DeletedDuringRefactor("missing"),
    None,
  )
  assert_eq(error(single(boolean, hole)).0, "moonbit.incomplete_body")
  let reference = @ir.Value::Reference(
    @fixtures.attrs(),
    @ir.FQName::parse("other:main#missing"),
  )
  assert_eq(error(single(boolean, reference)).0, "moonbit.unresolved_reference")
  let specs = @ir.IRFile::new(
    @ir.Distribution::Specs(@ir.Path::parse("sample"), Map([]), {
      modules: Map([]),
    }),
  )
  assert_eq(
    error(@generator.Input::new("specs", specs)).0,
    "moonbit.unsupported_distribution",
  )
  for
    (definition, code) in [
      (
        @ir.ValueDefinition::IncompleteBody(
          [],
          Some(boolean),
          @ir.Incompleteness::Draft,
          None,
        ),
        "moonbit.incomplete_body",
      ),
      (
        @ir.ValueDefinition::NativeBody([], boolean, {
          hint: @ir.NativeHint::Arithmetic,
          description: None,
        }),
        "moonbit.unresolved_implementation",
      ),
      (
        @ir.ValueDefinition::ExternalBody(
          [],
          boolean,
          [{ target_platform: "moonbit", external_name: "unknown", }],
          Some(hole),
        ),
        "moonbit.unresolved_implementation",
      ),
      (
        @ir.ValueDefinition::ExpressionBody(
          [(@ir.Name::parse("input"), boolean)],
          boolean,
          hole,
        ),
        "moonbit.incomplete_body",
      ),
    ] {
    assert_eq(error(single(boolean, hole, definition=Some(definition))).0, code)
  }
  let document = @ir.Value::Literal(
    @fixtures.attrs(),
    @ir.Literal::DocumentLiteral(@ir.Data::Null),
  )
  assert_eq(error(single(boolean, document)).0, "moonbit.unsupported_literal")
  let ir = @fixtures.library()
  guard ir.distribution is Library(name, deps, def) else {
    fail("Expected library")
  }
  let modules = def.modules.copy()
  let module_name = @ir.Path::parse("other")
  let module_def = modules[module_name]
  let values = module_def.value.values.copy()
  values[@ir.Name::parse("copy")] = @fixtures.definition(
    boolean,
    @ir.Value::Reference(
      @fixtures.attrs(),
      @ir.FQName::parse("pricing:scalars#hidden"),
    ),
  )
  modules[module_name] = {
    ..module_def,
    value: { ..module_def.value, values, },
  }
  assert_eq(
    error(
      @generator.Input::new(
        "private",
        @ir.IRFile::new(@ir.Distribution::Library(name, deps, { modules, })),
      ),
    ).0,
    "moonbit.inaccessible_reference",
  )
}

///|
test "Ion symbols retain node metadata ordered annotations and source lexemes" {
  let data = @ion_text.read_ion(
    "unknown::unknown::{scale:12.340d0,blob:{{/wCA}},nil:null.int,fields:{a:1,a:2}}",
  )
  let input = {
    ..@generator.Input::new("scalars", @fixtures.library()),
    annotations: [
      @ion.SymbolToken::new("audit"),
      @ion.SymbolToken::new("audit"),
    ],
    metadata: [{ node_id: "value:pricing:scalars#rate/body", data, }],
  }
  let result = @generator.generate(input)
  let bytes = match result.artifacts[3].content {
    Binary(bytes) => bytes
    Text(_) => fail("Expected binary metadata")
  }
  let value = @ion_binary.read_binary_value(bytes[:])
  guard value.kind() is Struct(fields) else { fail("Expected symbol profile") }
  let by_name = Map([])
  for field in fields {
    by_name[field.name().text().unwrap()] = field.value()
  }
  guard by_name["metadata"].kind() is List([entry]) else {
    fail("Expected metadata")
  }
  guard entry.kind() is Struct(metadata_fields) else { fail("Expected entry") }
  let retained = metadata_fields[1].value()
  assert_true(retained.equals(data))
  assert_eq(retained.annotations().map(token => token.text()), [
    Some("unknown"),
    Some("unknown"),
  ])
  guard by_name["source_ir_json"].kind() is String(source) else {
    fail("Expected source snapshot")
  }
  assert_true(source.contains("+12.3400E-2"))
  assert_true(
    result.symbols.any(symbol => {
      symbol.origins.contains("value:pricing:scalars#rate/body")
    }),
  )
  let invalid = { ..input, metadata: [{ node_id: "unknown", data, }], }
  assert_eq(error(invalid).0, "moonbit.metadata_identity")
}

///|
test "metadata-free constants retain symbol references without a node inventory" {
  let input = single(
    @fixtures.scalar("morphir/SDK:basics#int"),
    @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("42")),
  )
  let result = @generator.generate(input)
  guard result.artifacts[3].content is Binary(bytes) else { fail("symbols") }
  let value = @ion_binary.read_binary_value(bytes[:])
  guard value.kind() is Struct(fields) else { fail("symbol profile") }
  let by_name = Map([])
  for field in fields {
    by_name[field.name().text().unwrap()] = field.value()
  }
  assert_false(by_name.contains("source_nodes"))
  assert_true(by_name["metadata"].equals(@ion.IonValue::list([])))
  guard by_name["symbols"].kind() is List([symbol]) &&
    symbol.kind() is Struct(symbol_fields) else {
    fail("symbol references")
  }
  let references = Map([])
  for field in symbol_fields {
    references[field.name().text().unwrap()] = field.value()
  }
  assert_true(
    references["source_node"].equals(
      @ion.IonValue::string("value:sample:main#value"),
    ),
  )
  assert_true(
    references["origins"].equals(
      @ion.IonValue::list([
        @ion.IonValue::string("value:sample:main#value"),
        @ion.IonValue::string("value:sample:main#value/body"),
      ]),
    ),
  )
}

///|
test "dated symbol metadata retains explicit references and attributes without a node inventory" {
  let attrs = {
    ..@fixtures.attrs(),
    extensions: Map::from_array([("/snow~雪😀", @ir.Data::Text("opaque"))]),
  }
  let scalar = single(
    @fixtures.scalar("morphir/SDK:basics#int"),
    @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral("1")),
  )
  let data = @ion_text.read_ion("audit::{rule:\"retained\", amount:12.340d0}")
  for
    original in [
      @generator.Input::new("unit/雪😀~", @fixtures.library()),
      @generator.Input::new("pricing", @fixtures.pricing()),
      scalar,
    ] {
    // Metadata can address a structural leaf, not just an emitted declaration.
    let node_id = @identities.nodes(original.unit_id, original.ir)
      .last()
      .unwrap()
    let input = { ..original, metadata: [{ node_id, data, }], }
    let result = @generator.generate(input)
    guard result.artifacts[3].content is Binary(bytes) else { fail("symbols") }
    let value = @ion_binary.read_binary_value(bytes[:])
    guard value.kind() is Struct(fields) else { fail("symbol profile") }
    let by_name = Map([])
    for field in fields {
      by_name[field.name().text().unwrap()] = field.value()
    }
    assert_true(
      by_name["profile"].equals(
        @ion.IonValue::string("morphir-moonbit-symbols-2026-10-17"),
      ),
    )
    assert_false(by_name.contains("source_nodes"))
    guard by_name["metadata"].kind() is List([entry]) &&
      entry.kind() is Struct(metadata_fields) else {
      fail("metadata")
    }
    assert_true(
      metadata_fields[0].value().equals(@ion.IonValue::string(node_id)),
    )
    assert_true(metadata_fields[1].value().equals(data))
    guard by_name["source_ir_json"].kind() is String(source) else {
      fail("source IR")
    }
    assert_eq(@json.parse(source), @ir_json.to_json(input.ir))
    guard by_name["symbols"].kind() is List(symbols) else {
      fail("symbol references")
    }
    assert_eq(symbols.length(), result.symbols.length())
    let invalid = { ..input, metadata: [input.metadata[0], input.metadata[0]], }
    assert_eq(error(invalid).0, "moonbit.metadata_identity")
  }
}

///|
test "limits and cancellation stop generation before it returns artifacts" {
  let input = @generator.Input::new("scalars", @fixtures.library())
  let failure = try {
    ignore(
      @generator.generate(
        input,
        limits=Some({ max_declarations: 1, max_bytes: 100000, }),
      ),
    )
    ""
  } catch {
    @generator.Invalid(code, _, _) => code
  }
  assert_eq(failure, "moonbit.declaration_limit")
  let failure = try {
    ignore(
      @generator.generate(
        input,
        limits=Some({ max_declarations: 100, max_bytes: 20, }),
      ),
    )
    ""
  } catch {
    @generator.Invalid(code, _, _) => code
  }
  assert_eq(failure, "moonbit.byte_limit")
  let generated = @generator.generate(input)
  let mut total_bytes = 0
  for artifact in generated.artifacts {
    total_bytes += match artifact.content {
      Text(text) => @utf8.encode(text).length()
      Binary(bytes) => bytes.length()
    }
  }
  let failure = try {
    ignore(
      @generator.generate(
        input,
        limits=Some({ max_declarations: 100, max_bytes: total_bytes - 1, }),
      ),
    )
    ("", "")
  } catch {
    @generator.Invalid(code, _, message) => (code, message)
  }
  assert_eq(
    failure,
    ("moonbit.byte_limit", "Generated artifacts exceed the byte budget"),
  )
  assert_eq(
    @generator.generate(
      input,
      limits=Some({ max_declarations: 100, max_bytes: total_bytes, }),
    ).artifacts,
    generated.artifacts,
  )
  let failure = try {
    ignore(@generator.generate(input, cancelled=fn() { true }))
    ""
  } catch {
    @generator.Invalid(code, _, _) => code
  }
  assert_eq(failure, "moonbit.cancelled")
}

///|
test "multi module pricing lowers concrete records functions and constructors" {
  let output = @generator.generate(
    @generator.Input::new("pricing", @fixtures.pricing()),
  )
  assert_true(output.symbols.any(s => s.fqname == "pricing:results#mapped-sum"))
  assert_true(output.invocations.any(e => e.fqname == "pricing:quotes#reprice"))
  assert_true(
    output.invocations.any(e => e.fqname == "pricing:boundaries#result"),
  )
  assert_true(
    output.invocation_rejections.contains(
      ("pricing:quotes#captured", "execution.boundary_function"),
    ),
  )
}

///|
test "compound lowering rejects generic open and unsupported SDK types" {
  let a : @ir.TypeAttributes = {
    source: None,
    constraints: Map([]),
    extensions: Map([]),
  }
  let open = @ir.Type::ExtensibleRecord(a, @ir.Name::parse("row"), Map([]))
  assert_eq(
    error(single(open, @ir.Value::Unit(@fixtures.attrs()))).0,
    "moonbit.unsupported_type",
  )
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let unknown = @ir.Value::Reference(
    { ..@fixtures.attrs(), inferred_type: Some(int), },
    @ir.FQName::parse("morphir/SDK:basics#unknown"),
  )
  assert_eq(error(single(int, unknown)).0, "moonbit.unsupported_sdk")
  let function = @ir.Type::Function(a, int, int)
  let wrong = @ir.Value::Reference(
    { ..@fixtures.attrs(), inferred_type: Some(function), },
    @ir.FQName::parse("morphir/SDK:basics#add"),
  )
  assert_eq(error(single(function, wrong)).0, "moonbit.sdk_signature")
}

///|
test "power dispatch accepts integer and float signatures and rejects mixed inputs" {
  let a : @ir.TypeAttributes = {
    source: None,
    constraints: Map([]),
    extensions: Map([]),
  }
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let float = @fixtures.scalar("morphir/SDK:basics#float")
  let name = @ir.FQName::parse("morphir/SDK:basics#power")
  for t in [int, float] {
    let signature = @ir.Type::Function(a, t, @ir.Type::Function(a, t, t))
    assert_eq(
      error(
        single(
          signature,
          @ir.Value::Reference(
            { ..@fixtures.attrs(), inferred_type: Some(signature), },
            name,
          ),
        ),
      ).0,
      "",
    )
  }
  let mixed = @ir.Type::Function(a, float, @ir.Type::Function(a, int, float))
  assert_eq(
    error(
      single(
        mixed,
        @ir.Value::Reference(
          { ..@fixtures.attrs(), inferred_type: Some(mixed), },
          name,
        ),
      ),
    ).0,
    "moonbit.sdk_signature",
  )
}

///|
test "tuples lists maybe and result use concrete type parameter order" {
  let a : @ir.TypeAttributes = {
    source: None,
    constraints: Map([]),
    extensions: Map([]),
  }
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let bool = @fixtures.scalar("morphir/SDK:basics#bool")
  let one = @ir.Value::Literal(
    @fixtures.attrs(),
    @ir.Literal::IntegerLiteral("1"),
  )
  let tuple = @ir.Type::Tuple(a, [int, bool])
  assert_eq(
    error(
      single(
        tuple,
        @ir.Value::Tuple(@fixtures.attrs(), [
          one,
          @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::BoolLiteral(true)),
        ]),
      ),
    ).0,
    "",
  )
  let list = @ir.Type::Reference(
    a,
    @ir.FQName::parse("morphir/SDK:list#list"),
    [int],
  )
  assert_eq(
    error(single(list, @ir.Value::List(@fixtures.attrs(), [one]))).0,
    "",
  )
  let maybe = @ir.Type::Reference(
    a,
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [int],
  )
  assert_eq(
    error(
      single(
        maybe,
        @ir.Value::Constructor(
          @fixtures.attrs(),
          @ir.FQName::parse("morphir/SDK:maybe#nothing"),
        ),
      ),
    ).0,
    "",
  )
  let result = @ir.Type::Reference(
    a,
    @ir.FQName::parse("morphir/SDK:result#result"),
    [bool, int],
  )
  let ok_constructor = @ir.Value::Constructor(
    {
      ..@fixtures.attrs(),
      inferred_type: Some(@ir.Type::Function(a, int, result)),
    },
    @ir.FQName::parse("morphir/SDK:result#ok"),
  )
  let out = @generator.generate(
    single(result, @ir.Value::Apply(@fixtures.attrs(), ok_constructor, one)),
  )
  guard out.artifacts[2].content is Text(source) else { fail("source") }
  assert_true(source.contains("Result[@integer.Integer, Bool]"))
}

///|
test "a module uses the exposed values and constructors of a private module of the package" {
  let attrs = @fixtures.attrs()
  let boolean = @fixtures.scalar("morphir/SDK:basics#bool")
  let flag_name = @ir.FQName::parse("sample:inner#flag")
  let flag = @ir.Type::Reference(
    { source: None, constraints: Map([]), extensions: Map([]), },
    flag_name,
    [],
  )
  let on = @ir.FQName::parse("sample:inner#on")
  let types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ] = Map::from_array([
    (
      @ir.Name::parse("flag"),
      {
        access: @ir.Access::Public,
        value: {
          doc: None,
          value: @ir.TypeDefinition::CustomTypeDefinition([], {
            access: @ir.Access::Public,
            value: Map::from_array([(@ir.Name::parse("on"), [])]),
          }),
        },
      },
    ),
  ])
  let inner : @ir.ModuleDefinition = {
    types,
    doc: None,
    values: Map::from_array([
      (
        @ir.Name::parse("one"),
        @fixtures.definition(
          boolean,
          @ir.Value::Literal(attrs, @ir.Literal::BoolLiteral(true)),
        ),
      ),
    ]),
  }
  let on_value = @ir.Value::Constructor(
    { ..attrs, inferred_type: Some(flag), },
    on,
  )
  let matched = @ir.Value::PatternMatch(attrs, on_value, [
    (
      @ir.Pattern::ConstructorPattern(
        { ..attrs, inferred_type: Some(flag), },
        on,
        [],
      ),
      @ir.Value::Literal(attrs, @ir.Literal::BoolLiteral(true)),
    ),
  ])
  let main : @ir.ModuleDefinition = {
    types: Map([]),
    doc: None,
    values: Map::from_array([
      (
        @ir.Name::parse("reader"),
        @fixtures.definition(
          boolean,
          @ir.Value::Reference(
            { ..attrs, inferred_type: Some(boolean), },
            @ir.FQName::parse("sample:inner#one"),
          ),
        ),
      ),
      (@ir.Name::parse("matcher"), @fixtures.definition(boolean, matched)),
    ]),
  }
  let input = @generator.Input::new(
    "inner",
    @ir.IRFile::new(
      @ir.Distribution::Library(@ir.Path::parse("sample"), Map([]), {
        modules: Map::from_array([
          (
            @ir.Path::parse("inner"),
            { access: @ir.Access::Private, value: inner, },
          ),
          (
            @ir.Path::parse("main"),
            { access: @ir.Access::Public, value: main, },
          ),
        ]),
      }),
    ),
  )
  assert_eq(error(input), ("", ""))
}

///|
/// A package as the Elm frontend makes it when an exposed module names `sig` and `sig` names `deep` only in public
/// signatures: `sig` is Public and `deep` is Private. `deep` has the exposed type `Box`, the exposed alias `Boxed`,
/// the type `Sealed` with private constructors and the private value `secret`. `sig_values` are the values of `sig`.
fn private_module_package(
  sig_values : Array[
    (@ir.Name, @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]]),
  ],
) -> @generator.Input raise {
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  fn custom(
    access : @ir.Access,
    case_name : String,
  ) -> @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]] raise {
    {
      access: @ir.Access::Public,
      value: {
        doc: None,
        value: @ir.TypeDefinition::CustomTypeDefinition([], {
          access,
          value: Map::from_array([
            (@ir.Name::parse(case_name), [(@ir.Name::parse("n"), int)]),
          ]),
        }),
      },
    }
  }
  let deep : @ir.ModuleDefinition = {
    types: Map::from_array([
      (@ir.Name::parse("box"), custom(@ir.Access::Public, "box")),
      (@ir.Name::parse("sealed"), custom(@ir.Access::Private, "sealed")),
      (
        @ir.Name::parse("boxed"),
        {
          access: @ir.Access::Public,
          value: {
            doc: None,
            value: @ir.TypeDefinition::TypeAliasDefinition(
              [],
              @fixtures.scalar("my/pkg:deep#box"),
            ),
          },
        },
      ),
    ]),
    doc: None,
    values: Map::from_array([
      (
        @ir.Name::parse("secret"),
        @fixtures.definition(
          int,
          @ir.Value::Literal(
            { ..@fixtures.attrs(), inferred_type: Some(int), },
            @ir.Literal::IntegerLiteral("1"),
          ),
          access=@ir.Access::Private,
        ),
      ),
    ]),
  }
  let sig : @ir.ModuleDefinition = {
    types: Map([]),
    doc: None,
    values: Map::from_array(sig_values),
  }
  @generator.Input::new(
    "my/pkg",
    @ir.IRFile::new(
      @ir.Distribution::Library(@ir.Path::parse("my/pkg"), Map([]), {
        modules: Map::from_array([
          (
            @ir.Path::parse("deep"),
            { access: @ir.Access::Private, value: deep, },
          ),
          (@ir.Path::parse("sig"), { access: @ir.Access::Public, value: sig, }),
        ]),
      }),
    ),
  )
}

///|
/// `C b`, where the constructor `C` named `name` makes a value of type `result` from an `Int`.
fn apply_constructor(name : String, result : @ir.Type) -> @ir.Value raise {
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  @ir.Value::Apply(
    { ..@fixtures.attrs(), inferred_type: Some(result), },
    @ir.Value::Constructor(
      {
        ..@fixtures.attrs(),
        inferred_type: Some(
          @ir.Type::Function(
            { source: None, constraints: Map([]), extensions: Map([]), },
            int,
            result,
          ),
        ),
      },
      @ir.FQName::parse(name),
    ),
    @ir.Value::Variable(
      { ..@fixtures.attrs(), inferred_type: Some(int), },
      @ir.Name::parse("b"),
    ),
  )
}

///|
/// A public value of `sig` with one input of type `input` and body `body`, of type `Int` unless `output` says.
fn sig_value(
  name : String,
  input : @ir.Type,
  body : @ir.Value,
  output~ : @ir.Type? = None,
) -> (@ir.Name, @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]]) raise {
  (
    @ir.Name::parse(name),
    {
      access: @ir.Access::Public,
      value: {
        doc: None,
        value: @ir.ValueDefinition::ExpressionBody(
          [(@ir.Name::parse("b"), input)],
          output.unwrap_or(@fixtures.scalar("morphir/SDK:basics#int")),
          body,
        ),
      },
    },
  )
}

///|
test "review I1: a public signature names an exposed type of a private module, which is emitted abstract" {
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let one = @ir.Value::Literal(
    { ..@fixtures.attrs(), inferred_type: Some(int), },
    @ir.Literal::IntegerLiteral("1"),
  )
  let box = @fixtures.scalar("my/pkg:deep#box")
  let record = @ir.Type::Record(
    { source: None, constraints: Map([]), extensions: Map([]), },
    Map::from_array([(@ir.Name::parse("b"), box)]),
  )
  let input = private_module_package([
    sig_value("g", box, one),
    sig_value("h", @fixtures.scalar("my/pkg:deep#boxed"), one),
    sig_value("k", record, one),
    // `make b = Box b`: the exposed constructor of a private module.
    sig_value(
      "make",
      int,
      apply_constructor("my/pkg:deep#box", box),
      output=Some(box),
    ),
  ])
  assert_eq(error(input), ("", ""))
  let source = library_source(input)
  // Abstract: no visibility modifier, so other packages name `Box` but not its constructor.
  assert_true(source.contains("///|\nenum Box {"), msg=source)
  assert_false(source.contains("pub(all) enum Box"), msg=source)
  assert_false(source.contains("pub enum Box"), msg=source)
  // Nothing public names `Sealed`, so it stays private.
  assert_true(source.contains("///|\npriv enum Sealed {"), msg=source)
  assert_true(source.contains("pub fn g()"), msg=source)
  assert_true(source.contains("pub fn h()"), msg=source)
  assert_true(source.contains("pub fn k()"), msg=source)
}

///|
test "review I1: a private value or constructor of a private module is still out of reach of another module" {
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let secret = @ir.Value::Reference(
    { ..@fixtures.attrs(), inferred_type: Some(int), },
    @ir.FQName::parse("my/pkg:deep#secret"),
  )
  assert_eq(
    error(private_module_package([sig_value("g", int, secret)])),
    ("moonbit.inaccessible_reference", "value:my/pkg:sig#g/body"),
  )
  let closed = @fixtures.scalar("my/pkg:deep#sealed")
  let construct = apply_constructor("my/pkg:deep#sealed", closed)
  assert_eq(
    error(
      private_module_package([
        sig_value("g", int, construct, output=Some(closed)),
      ]),
    ).0,
    "moonbit.inaccessible_reference",
  )
}
