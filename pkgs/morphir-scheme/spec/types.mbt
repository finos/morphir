///|
fn type_attrs() -> @ir.TypeAttributes {
  { source: None, constraints: Map([]), extensions: Map([]), }
}

///|
fn variable(name : @ir.Name) -> @ir.Type {
  let constraints : Map[String, @ir.Data] = Map([])
  if class_of(name) is Some(class) {
    constraints["typeclass"] = Text(class)
  }
  Variable({ ..type_attrs(), constraints, }, name)
}

///|
fn check_head(
  ctx : Context,
  at : @scheme.Located,
  head : String,
) -> Unit raise SpecError {
  if head.has_suffix("!") {
    ctx.fail(at, "`\{head}` is reserved for macros")
  }
}

///|
fn read_type(ctx : Context, at : @scheme.Located) -> @ir.Type raise SpecError {
  match at.datum {
    Symbol(text) =>
      if text.contains("#") {
        Reference(type_attrs(), read_reference(ctx, at, text), [])
      } else {
        check_head(ctx, at, text)
        variable(read_name(ctx, at))
      }
    Sequence([], None) => Unit(type_attrs())
    Sequence(_, None) => {
      let head = at.children[0]
      let rest = at.children[1:].to_owned()
      guard symbol(head) is Some(text) else {
        ctx.fail(at, "expected a type form")
      }
      check_head(ctx, at, text)
      match text {
        "union" => {
          if rest.length() < 2 {
            ctx.fail(at, "a union needs at least two types")
          }
          Union(type_attrs(), rest.map(t => read_type(ctx, t)))
        }
        "->" => {
          if rest.length() < 2 {
            ctx.fail(at, "a function type needs at least two types")
          }
          let types = rest.map(t => read_type(ctx, t))
          let mut result = types[types.length() - 1]
          for i = types.length() - 2; i >= 0; i = i - 1 {
            result = Function(type_attrs(), types[i], result)
          }
          result
        }
        "tuple" => {
          if rest.length() < 2 {
            ctx.fail(at, "a tuple needs at least two types")
          }
          Tuple(type_attrs(), rest.map(t => read_type(ctx, t)))
        }
        "record" => {
          let (extension, field_forms) = match rest {
            [first, .. tail] if symbol(first) is Some(_) =>
              (Some(read_name(ctx, first)), tail.to_owned())
            _ => (None, rest)
          }
          let fields : Map[@ir.Name, @ir.Type] = Map([])
          for field in field_forms {
            guard field.children is [name_form, type_form] else {
              ctx.fail(field, "a record field is (name type)")
            }
            let name = read_name(ctx, name_form)
            if fields.contains(name) {
              ctx.fail(field, "duplicate field `\{name.to_canonical()}`")
            }
            fields[name] = read_type(ctx, type_form)
          }
          match extension {
            Some(r) => ExtensibleRecord(type_attrs(), r, fields)
            None => Record(type_attrs(), fields)
          }
        }
        _ if text.contains("#") =>
          Reference(
            type_attrs(),
            read_reference(ctx, head, text),
            rest.map(t => read_type(ctx, t)),
          )
        _ => ctx.fail(at, "unknown type form `\{text}`")
      }
    }
    _ => ctx.fail(at, "expected a type")
  }
}

///|
pub fn read_type_text(
  text : String,
  package_name~ : String,
  module_path~ : String,
) -> @ir.Type raise SpecError {
  let forms = @scheme.parse_program_located(text) catch {
    @scheme.SchemeError::Syntax(message, offset) => {
      let (line, column) = @scheme.line_column(text, offset)
      raise SpecError(line~, column~, message~)
    }
    e => raise SpecError(line=1, column=1, message=e.to_string())
  }
  guard forms is [form] else {
    raise SpecError(line=1, column=1, message="expected one type")
  }
  let package_path = @ir.Path::parse(package_name) catch {
    _ =>
      raise SpecError(
        line=1,
        column=1,
        message="invalid package name `\{package_name}`",
      )
  }
  let module_ = @ir.Path::parse(module_path) catch {
    _ =>
      raise SpecError(
        line=1,
        column=1,
        message="invalid module name `\{module_path}`",
      )
  }
  ignore(module_)
  let ctx = { source: text, package_name: package_path, }
  read_type(ctx, form)
}
