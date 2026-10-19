///|
fn union_type() -> @ir.Type raise {
  Union(Default::default(), [
    Reference(
      Default::default(),
      @ir.FQName::parse("morphir/SDK:string#string"),
      [],
    ),
    Reference(Default::default(), @ir.FQName::parse("morphir/SDK:basics#int"), []),
  ])
}

///|
test "Union inferred type is refused before direct native literal evaluation" {
  let value : @ir.Value = Literal(
    { ..attrs(), inferred_type: Some(union_type()), },
    IntegerLiteral("1"),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  try @backend.evaluate_in(runtime, value) catch {
    @scheme.Unsupported(_) => ()
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union native literal evaluation was accepted")
  }
}

///|
test "Union pattern annotation is refused by direct emission" {
  let p : @ir.Pattern = WildcardPattern({
    ..attrs(),
    inferred_type: Some(union_type()),
  })
  let value : @ir.Value = Lambda(attrs(), p, int("1"))
  try @backend.emit_expression(value) catch {
    @scheme.Unsupported(_) => ()
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union pattern was erased")
  }
}

///|
test "Union signature is refused before selected aliases are pruned" {
  let file = file(ExpressionBody([], union_type(), int("1")))
  try @backend.selected_file(file, @ir.FQName::parse("test:main#main")) catch {
    @backend.SelectedReferenceInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union selected signature was accepted")
  }
}

///|
test "Union registered native entry is refused before host code runs" {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let entry = @ir.FQName::parse("test:main#main")
  let called : Ref[Bool] = { val: false, }
  @backend.register_native(runtime, entry, fn(_rt, _args) raise {
    called.val = true
    @scheme.integer("1")
  })
  let file = file(
    NativeBody([], union_type(), { hint: Arithmetic, description: None, }),
  )
  try @backend.run_file_in(runtime, file, entry, []) catch {
    @scheme.Unsupported(_) => ()
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union native entry was accepted")
  }
  assert_false(called.val)
  try @backend.link_file(runtime, file) catch {
    @scheme.Unsupported(_) => ()
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union file linked")
  }
}

///|
test "Union aliases are checked only when reachable by selected definitions" {
  let initial = file(ExpressionBody([], Unit(Default::default()), int("1")))
  guard initial.distribution is Library(p, deps, d) else {
    fail("not a library")
  }
  let module_name = @ir.Path::parse("main")
  let m = d.modules[module_name]
  let union_ref : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("test:main#hidden"),
    [],
  )
  let types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ] = Map([
    (
      name("hidden"),
      {
        access: Private,
        value: {
          doc: None,
          value: @ir.TypeDefinition::TypeAliasDefinition([], union_type()),
        },
      },
    ),
  ])
  let with_types : @ir.PackageDefinition = {
    modules: Map([(module_name, { ..m, value: { ..m.value, types, }, })]),
  }
  let unused = @ir.IRFile::new(Library(p, deps, with_types))
  ignore(@backend.emit_selected(unused, @ir.FQName::parse("test:main#main")))
  let values = m.value.values.copy()
  values[name("main")] = {
    access: Public,
    value: { doc: None, value: ExpressionBody([], union_ref, int("1")), },
  }
  let used = @ir.IRFile::new(
    Library(p, deps, {
      modules: Map([
        (module_name, { ..m, value: { ..m.value, types, values, }, }),
      ]),
    }),
  )
  try @backend.selected_file(used, @ir.FQName::parse("test:main#main")) catch {
    @backend.SelectedReferenceInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("reachable alias was erased")
  }
}

///|
fn external_union_file(
  kind : String,
  use_alias : Bool,
  reached : Bool,
) -> @ir.IRFile raise {
  let string : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("morphir/SDK:string#string"),
    [],
  )
  let union : @ir.Type = Union(Default::default(), [string, string])
  let target = if kind.has_prefix("constructor") {
    "morphir/SDK:maybe#just"
  } else if kind == "source-string" {
    "morphir/moonbit-source:string#require-valid"
  } else {
    "morphir/SDK:basics#identity"
  }
  let fq = @ir.FQName::parse(target)
  let hidden : @ir.FQName = { ..fq, local_name: name("hidden"), }
  let required : @ir.Type = if use_alias {
    Reference(Default::default(), hidden, [])
  } else {
    union
  }
  let annotation : @ir.Annotation = Structured(
    @ir.FQName::parse("example:meta#note"),
    [
      Positional(
        Literal(
          { ..attrs(), inferred_type: Some(required), },
          StringLiteral("note"),
        ),
      ),
    ],
  )
  let annotations = if kind.has_suffix("annotation") {
    [annotation]
  } else {
    []
  }
  let types : Map[@ir.Name, @ir.Documented[@ir.TypeSpecification]] = Map([
    (
      name("hidden"),
      {
        doc: None,
        value: { annotations: [], body: TypeAliasSpecification([], union), },
      },
    ),
  ])
  let values : Map[@ir.Name, @ir.Documented[@ir.ValueSpecification]] = Map([])
  if kind.has_prefix("constructor") {
    types[name("maybe")] = {
      doc: None,
      value: {
        annotations,
        body: CustomTypeSpecification(
          [],
          Map([
            (
              name("just"),
              [
                (
                  name("value"),
                  if annotations.is_empty() {
                    required
                  } else {
                    string
                  },
                ),
              ],
            ),
          ]),
        ),
      },
    }
  } else {
    values[fq.local_name] = {
      doc: None,
      value: {
        annotations: if kind == "module-annotation" {
          []
        } else {
          annotations
        },
        inputs: [(name("value"), string)],
        output: if annotations.is_empty() {
          required
        } else {
          string
        },
      },
    }
  }
  let body : @ir.Value = if !reached {
    Literal(attrs(), StringLiteral("ok"))
  } else if kind.has_prefix("constructor") {
    Apply(
      attrs(),
      Constructor(attrs(), fq),
      Literal(attrs(), StringLiteral("ok")),
    )
  } else {
    Apply(
      attrs(),
      Reference(attrs(), fq),
      Literal(attrs(), StringLiteral("ok")),
    )
  }
  let original = file(ExpressionBody([], string, body))
  guard original.distribution is Library(p, deps, d) else { fail("library") }
  deps[fq.package_name] = {
    modules: Map([
      (
        fq.module_name,
        {
          doc: None,
          annotations: if kind == "module-annotation" {
            annotations
          } else {
            []
          },
          types,
          values,
        },
      ),
    ]),
  }
  @ir.IRFile::new(Library(p, deps, d))
}

///|
test "selected emission and execution reject reached dependency signatures and annotations" {
  let entry = @ir.FQName::parse("test:main#main")
  for
    kind in [
      "value", "value-annotation", "constructor", "constructor-annotation", "source-string",
      "module-annotation",
    ] {
    for use_alias in [false, true] {
      let source = external_union_file(kind, use_alias, true)
      try @backend.emit_selected(source, entry) catch {
        @backend.SelectedReferenceInvalid(code) =>
          assert_eq(code, "execution.unsupported_type")
        e => fail("wrong error: " + e.to_string())
      } noraise {
        _ => fail("reached dependency accepted: " + kind)
      }
      let runtime = @scheme.Runtime::new()
      @backend.install(runtime)
      try @backend.run_selected_in(runtime, source, entry, []) catch {
        @backend.SelectedReferenceInvalid(code) =>
          assert_eq(code, "execution.unsupported_type")
        e => fail("wrong error: " + e.to_string())
      } noraise {
        _ => fail("reached dependency executed: " + kind)
      }
      let unused = external_union_file(kind, use_alias, false)
      ignore(@backend.emit_selected(unused, entry))
      assert_eq(
        @scheme.value_to_string(
          @backend.run_selected_in(runtime, unused, entry, []),
        ),
        "\"ok\"",
      )
    }
  }
}
