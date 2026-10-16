///|
fn ph_name(text : String) -> @current.Name {
  @current.Name::parse(text) catch {
    _ => panic()
  }
}

///|
fn ph_int() -> @current.Type {
  Reference(
    Default::default(),
    @current.FQName::parse("morphir/SDK:basics#int") catch {
      _ => panic()
    },
    [],
  )
}

///|
fn ph_var(text : String) -> @current.Type {
  Variable(Default::default(), ph_name(text))
}

///|
fn ph_typed(t : @current.Type) -> @current.ValueAttributes {
  { source: None, inferred_type: Some(t), extensions: Map([]), }
}

///|
/// `test x = let y z = z in y x`, with the let signature `t8 -> t8` and the top-level input `x : t1`. Every node
/// has an inferred type, so the file can be written as classic IR. `let_var` replaces `t8`.
fn ph_file(let_var~ : @current.Type = ph_var("t-8")) -> @current.IRFile {
  let t8 = let_var
  let let_def : @current.ValueDefinition = ExpressionBody(
    [(ph_name("z"), t8)],
    t8,
    Variable(ph_typed(t8), ph_name("z")),
  )
  let body : @current.Value = LetDefinition(
    ph_typed(ph_int()),
    ph_name("y"),
    let_def,
    Apply(
      ph_typed(ph_int()),
      Variable(ph_typed(Function(Default::default(), t8, t8)), ph_name("y")),
      Variable(ph_typed(ph_var("t-1")), ph_name("x")),
    ),
  )
  let def : @current.ValueDefinition = ExpressionBody(
    [(ph_name("x"), ph_var("t-1"))],
    ph_int(),
    body,
  )
  let module_def : @current.ModuleDefinition = {
    types: Map([]),
    values: Map([
      (
        ph_name("test"),
        { access: Public, value: { doc: Some(""), value: def, }, },
      ),
    ]),
    doc: None,
  }
  @current.IRFile::new(
    Library(@current.Path::parse("example") catch { _ => panic() }, Map([]), {
      modules: Map([
        (
          @current.Path::parse("main") catch {
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
/// The input type and the let-signature input and output types of `example:main#test`.
fn ph_signatures(
  file : @current.IRFile,
) -> (@current.Type, @current.Type, @current.Type) {
  guard file.distribution is Library(_, _, def) else { panic() }
  let m = def.modules
    .get(@current.Path::parse("main") catch { _ => panic() })
    .unwrap()
  let v = m.value.values.get(ph_name("test")).unwrap()
  guard v.value.value
    is ExpressionBody(
      [(_, top)],
      _,
      LetDefinition(_, _, ExpressionBody([(_, z)], out, _), _)
    ) else {
    panic()
  }
  (top, z, out)
}

///|
fn ph_marked(t : @current.Type) -> Bool {
  t is Variable(a, _) && a.is_unknown()
}

///|
test "classic let placeholders are marked in v4 and the marker is dropped on the way back" {
  let v4_text = @current_json.write(ph_file())
  for major in [1U, 2U, 3U] {
    let classic = @migration.migrate(
      @any_json.read(v4_text),
      @version.FormatVersion::baseline(major),
    )
    let current = @migration.to_current(classic)
    let (top, z, out) = ph_signatures(current)
    assert_true(ph_marked(z))
    assert_true(ph_marked(out))
    assert_false(ph_marked(top))
    // The marker does not stop a downgrade, and the classic file does not change.
    let again = @migration.migrate(
      @any_json.read(@current_json.write(current)),
      @version.FormatVersion::baseline(major),
    )
    assert_eq(again, classic)
  }
}

///|
test "names that only look like placeholders are not classic placeholders" {
  for text in ["t-x", "t-1-a", "t", "tt-1", "a-1"] {
    assert_false(@migration.is_classic_placeholder(ph_name(text)))
  }
  for text in ["t-8", "t-123"] {
    assert_true(@migration.is_classic_placeholder(ph_name(text)))
  }
}

///|
test "a v4 file is not changed by to_current" {
  let file = ph_file()
  assert_eq(
    @migration.to_current(@any_json.read(@current_json.write(file))),
    file,
  )
}

///|
test "the marker on a variable that is not a placeholder still stops a downgrade" {
  let a : @current.Type = Variable(
    @current.TypeAttributes::default().with_unknown(),
    ph_name("a"),
  )
  let v4_text = @current_json.write(ph_file(let_var=a))
  for major in [1U, 2U, 3U] {
    let code = try {
      ignore(
        @migration.migrate(
          @any_json.read(v4_text),
          @version.FormatVersion::baseline(major),
        ),
      )
      "accepted"
    } catch {
      error => @wire.diagnostic(error)
    }
    assert_eq(code, "unsupported_attributes_downgrade", msg="v\{major}")
  }
}
