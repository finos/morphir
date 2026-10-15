///|
fn library(
  modules : Map[@ir.Path, @ir.AccessControlled[@ir.ModuleDefinition]],
) -> @ir.IRFile {
  @ir.IRFile::new(
    Library(@ir.Path::parse("p") catch { _ => panic() }, Map([]), { modules, }),
  ) catch {
    _ => panic()
  }
}

///|
fn module_with(doc : String?) -> @ir.AccessControlled[@ir.ModuleDefinition] {
  { access: Public, value: { types: Map([]), values: Map([]), doc, }, }
}

///|
test "differences name the module and ignore an empty doc" {
  let m = @ir.Path::parse("m") catch { _ => panic() }
  let a = library(Map::from_array([(m, module_with(Some("")))]))
  let b = library(Map::from_array([(m, module_with(None))]))
  assert_eq(differences(a, b), [])
  let c = library(Map::from_array([(m, module_with(Some("x")))]))
  assert_eq(differences(a, c), ["module m: doc"])
  assert_eq(differences(a, library(Map([]))), ["module m: missing"])
}

///|
fn int_type(source : @ir.SourceLocation?) -> @ir.Type {
  Reference(
    { ..@ir.TypeAttributes::default(), source, },
    @ir.FQName::parse("morphir/SDK:basics#int") catch {
      _ => panic()
    },
    [],
  )
}

///|
fn module_of(
  types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ],
  values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ],
) -> @ir.IRFile {
  let m = @ir.Path::parse("m") catch { _ => panic() }
  library(
    Map::from_array([
      (m, { access: Public, value: { types, values, doc: None, }, }),
    ]),
  )
}

///|
fn float_type() -> @ir.Type {
  Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#float") catch {
      _ => panic()
    },
    [],
  )
}

///|
fn loc() -> @ir.SourceLocation {
  { start_line: 1, start_column: 1, end_line: 1, end_column: 4, }
}

///|
/// A library with the module `m` and one public value.
fn library_with_value(name : String, def : @ir.ValueDefinition) -> @ir.IRFile {
  let name = @ir.Name::parse(name) catch { _ => panic() }
  module_of(
    Map([]),
    Map::from_array([
      (name, { access: Public, value: { doc: Some(""), value: def, }, }),
    ]),
  )
}

///|
test "differences compare body shapes and node types" {
  let int_lit = (t : @ir.Type) => {
    (
      Literal(
        { ..@ir.ValueAttributes::default(), inferred_type: Some(t), },
        IntegerLiteral("1"),
      ) : @ir.Value)
  }
  let float_lit : @ir.Value = Literal(
    { ..@ir.ValueAttributes::default(), inferred_type: Some(float_type()), },
    FloatLiteral(1.0),
  )
  let a = library_with_value(
    "v",
    ExpressionBody([], int_type(None), int_lit(int_type(None))),
  )
  let same = library_with_value(
    "v",
    ExpressionBody([], int_type(Some(loc())), int_lit(int_type(None))),
  )
  assert_eq(differences(a, same), [])
  let other_shape = library_with_value(
    "v",
    ExpressionBody([], int_type(None), float_lit),
  )
  assert_eq(differences(a, other_shape), ["value m#v: body"])
  let other_type = library_with_value(
    "v",
    ExpressionBody([], int_type(None), int_lit(float_type())),
  )
  assert_true(differences(a, other_type).all(line => line.has_prefix("type ")))
  assert_eq(differences(a, other_type).length(), 1)
}

///|
test "differences ignore value attributes and let signature types in the body shape" {
  let x = @ir.Name::parse("x") catch { _ => panic() }
  let k = @ir.Name::parse("k") catch { _ => panic() }
  let typed = (t : @ir.Type) => {
    ..@ir.ValueAttributes::default(),
    inferred_type: Some(t),
  }
  let body = (let_output : @ir.Type, source : @ir.SourceLocation?) => {
    let def : @ir.ValueDefinition = ExpressionBody(
      [],
      let_output,
      Variable({ ..typed(int_type(None)), source, }, x),
    )
    @ir.Value::LetDefinition(
      typed(int_type(None)),
      k,
      def,
      Variable(typed(int_type(None)), x),
    )
  }
  let a = library_with_value(
    "v",
    ExpressionBody(
      [(x, int_type(None))],
      int_type(None),
      body(int_type(None), None),
    ),
  )
  let b = library_with_value(
    "v",
    ExpressionBody(
      [(x, int_type(None))],
      int_type(None),
      body(int_type(None), Some(loc())),
    ),
  )
  assert_eq(differences(a, b), [])
  // A let signature type is not part of the shape: it is a `let signatures` line and a `type` line.
  let c = library_with_value(
    "v",
    ExpressionBody(
      [(x, int_type(None))],
      int_type(None),
      body(float_type(), None),
    ),
  )
  assert_eq(differences(a, c), [
    "value m#v: let signatures", "type value:p:m#v/body/definition:output: expected morphir/SDK:basics#int, found morphir/SDK:basics#float",
  ])
  // Inputs compare by name and declared type; a changed type is also a `type` line.
  let y = @ir.Name::parse("y") catch { _ => panic() }
  let renamed = library_with_value(
    "v",
    ExpressionBody(
      [(y, int_type(None))],
      int_type(None),
      body(int_type(None), None),
    ),
  )
  assert_eq(differences(a, renamed), ["value m#v: inputs"])
  let retyped = library_with_value(
    "v",
    ExpressionBody(
      [(x, float_type())],
      int_type(None),
      body(int_type(None), None),
    ),
  )
  assert_eq(differences(a, retyped), [
    "value m#v: inputs", "type value:p:m#v:input/0: expected morphir/SDK:basics#int, found morphir/SDK:basics#float",
  ])
}

///|
test "differences mask morphir-elm placeholders in top-level signatures" {
  let placeholder : @ir.Type = Variable(
    @ir.TypeAttributes::default(),
    @ir.Name::parse("t-0") catch {
      _ => panic()
    },
  )
  let lit = (t : @ir.Type) => {
    (
      Literal(
        { ..@ir.ValueAttributes::default(), inferred_type: Some(t), },
        IntegerLiteral("1"),
      ) : @ir.Value)
  }
  let elm = library_with_value(
    "v",
    ExpressionBody([], placeholder, lit(int_type(None))),
  )
  let ours = library_with_value(
    "v",
    ExpressionBody([], int_type(None), lit(int_type(None))),
  )
  assert_eq(differences(elm, ours), [])
}

///|
test "differences compare access, docs, type definitions and missing items" {
  let f = @ir.Name::parse("f") catch { _ => panic() }
  let t = @ir.Name::parse("t") catch { _ => panic() }
  let value = (access : @ir.Access) => {
    let def : @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] = {
      access,
      value: {
        doc: Some(""),
        value: ExpressionBody(
          [],
          int_type(None),
          Unit(@ir.ValueAttributes::default()),
        ),
      },
    }
    def
  }
  let aliased = (target : @ir.Type) => {
    let def : @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]] = {
      access: Public,
      value: { doc: Some(""), value: TypeAliasDefinition([], target), },
    }
    def
  }
  let expected = module_of(
    Map::from_array([(t, aliased(int_type(Some(loc()))))]),
    Map::from_array([(f, value(Public))]),
  )
  let same = module_of(
    Map::from_array([(t, aliased(int_type(None)))]),
    Map::from_array([(f, value(Public))]),
  )
  assert_eq(differences(expected, same), [])
  let unit_type : @ir.Type = Unit(@ir.TypeAttributes::default())
  let changed = module_of(
    Map::from_array([(t, aliased(unit_type))]),
    Map::from_array([(f, value(Private))]),
  )
  assert_eq(differences(expected, changed), [
    "type m#t: definition", "value m#f: access",
  ])
  let other = @ir.Name::parse("g") catch { _ => panic() }
  let renamed = module_of(Map([]), Map::from_array([(other, value(Public))]))
  assert_eq(differences(expected, renamed), [
    "type m#t: missing", "value m#f: missing", "value m#g: unexpected",
  ])
}

///|
test "differences compare declared signature types exactly, without alias expansion" {
  let x = @ir.Name::parse("x") catch { _ => panic() }
  let id = @ir.Name::parse("id") catch { _ => panic() }
  let string_type : @ir.Type = Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:string#string") catch {
      _ => panic()
    },
    [],
  )
  let id_type : @ir.Type = Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("p:m#id") catch {
      _ => panic()
    },
    [],
  )
  let file = (input : @ir.Type, output : @ir.Type) => {
    let aliased : @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]] = {
      access: Public,
      value: { doc: Some(""), value: TypeAliasDefinition([], string_type), },
    }
    let lit : @ir.Value = Literal(
      { ..@ir.ValueAttributes::default(), inferred_type: Some(string_type), },
      StringLiteral(""),
    )
    let value : @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] = {
      access: Public,
      value: {
        doc: Some(""),
        value: ExpressionBody([(x, input)], output, lit),
      },
    }
    module_of(
      Map::from_array([(id, aliased)]),
      Map::from_array([(@ir.Name::parse("v") catch { _ => panic() }, value)]),
    )
  }
  // `Id` and `String` are the same type after expansion, so there is no `type` line, but morphir-elm writes the
  // declared names from the source.
  let elm = file(id_type, id_type)
  assert_eq(differences(elm, file(id_type, id_type)), [])
  assert_eq(differences(elm, file(string_type, string_type)), [
    "value m#v: inputs", "value m#v: output",
  ])
  // A morphir-elm placeholder position is not compared; the rest of the type is.
  let list = (t : @ir.Type) => {
    (
      Reference(
        @ir.TypeAttributes::default(),
        @ir.FQName::parse("morphir/SDK:list#list") catch {
          _ => panic()
        },
        [t],
      ) : @ir.Type)
  }
  let placeholder : @ir.Type = Variable(
    @ir.TypeAttributes::default(),
    @ir.Name::parse("t-0") catch {
      _ => panic()
    },
  )
  let unannotated = file(list(placeholder), string_type)
  assert_true(
    !differences(unannotated, file(list(string_type), string_type)).contains(
      "value m#v: inputs",
    ),
  )
  assert_true(
    differences(unannotated, file(string_type, string_type)).contains(
      "value m#v: inputs",
    ),
  )
}
