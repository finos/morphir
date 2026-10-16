///|
fn closed_fields(
  value : Json,
  names : Array[String],
  code : String,
) -> Map[String, Json] raise {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    fields.keys().all(name => names.contains(name)) else {
    raise @execution.Invalid(code)
  }
  fields
}

///|
fn declaration_name(value : Json, code : String) -> String raise {
  guard value is String(name) && name.length() > 0 else {
    raise @execution.Invalid(code)
  }
  if name.length() > 1024 {
    raise @execution.Invalid("workbench.type_limit")
  }
  name
}

///|
fn declaration_nodes(budget : Ref[Int32]) -> Unit raise {
  budget.val -= 1
  if budget.val < 0 {
    raise @execution.Invalid("workbench.type_limit")
  }
}

///|
fn declaration_array(
  value : Json,
  limit : Int32,
  code : String,
) -> Array[Json] raise {
  guard value is Array(values) else { raise @execution.Invalid(code) }
  if values.length() > limit {
    raise @execution.Invalid("workbench.type_limit")
  }
  values
}

///|
fn declared_type(
  value : Json,
  depth : Int32,
  budget : Ref[Int32],
  references : Array[String],
) -> @execution.ValueType raise {
  declaration_nodes(budget)
  if depth > 64 {
    raise @execution.Invalid("workbench.type_limit")
  }
  let code = "workbench.invalid_type"
  let tag = field(value, "type")
  let names = match tag {
    String("list" | "maybe") => ["type", "item"]
    String("tuple") => ["type", "items"]
    String("record") => ["type", "fields"]
    String("custom") => ["type", "name"]
    String("result") => ["type", "ok", "err"]
    _ => ["type"]
  }
  ignore(closed_fields(value, names, code))
  fn child(value : Json) -> @execution.ValueType raise {
    declared_type(value, depth + 1, budget, references)
  }
  match tag {
    String("int") => Int
    String("bool") => Bool
    String("unit") => Unit
    String("decimal") => Decimal
    String("float64") => Float64
    String("text") => Text
    String("character") => Character
    String("function") =>
      raise @execution.Invalid("execution.boundary_function")
    String("list") => Sequence(child(field(value, "item")))
    String("maybe") => Optional(child(field(value, "item")))
    String("tuple") =>
      Product(declaration_array(field(value, "items"), 1024, code).map(child))
    String("record") => {
      let seen : Map[String, Bool] = Map([])
      let fields = declaration_array(field(value, "fields"), 1024, code).map(item => {
        declaration_nodes(budget)
        ignore(closed_fields(item, ["name", "type"], code))
        let name = declaration_name(field(item, "name"), code)
        if seen.contains(name) {
          raise @execution.Invalid(code)
        }
        seen[name] = true
        (name, child(field(item, "type")))
      })
      Record(fields)
    }
    String("custom") => {
      let name = declaration_name(field(value, "name"), code)
      references.push(name)
      Custom(name)
    }
    String("result") =>
      Outcome(child(field(value, "ok")), child(field(value, "err")))
    _ => raise @execution.Invalid(code)
  }
}

///|
/// Complete the registry and close references collected from all declarations.
/// Named cycles are allowed without expanding inline descriptor depth.
fn declared_definitions(
  value : Json,
  budget : Ref[Int32],
  references : Array[String],
) -> Array[@execution.CustomType] raise {
  let names : Map[String, Bool] = Map([])
  let code = "workbench.invalid_definitions"
  let definitions = declaration_array(value, 256, code).map(item => {
    declaration_nodes(budget)
    ignore(closed_fields(item, ["name", "constructors"], code))
    let name = declaration_name(field(item, "name"), code)
    if names.contains(name) {
      raise @execution.Invalid(code)
    }
    names[name] = true
    let tags : Map[String, Bool] = Map([])
    let constructors = declaration_array(field(item, "constructors"), 256, code).map(variant => {
        declaration_nodes(budget)
        ignore(closed_fields(variant, ["name", "inputs"], code))
        let tag = declaration_name(field(variant, "name"), code)
        if tags.contains(tag) {
          raise @execution.Invalid(code)
        }
        tags[tag] = true
        let inputs = declaration_array(field(variant, "inputs"), 64, code).map(t => {
          declared_type(t, 0, budget, references)
        })
        @execution.ConstructorType::{ name: tag, inputs, }
      },
    )
    @execution.CustomType::{ name, constructors, }
  })
  for reference in references {
    if !names.contains(reference) {
      raise @execution.Invalid("execution.unresolved_custom_type")
    }
  }
  definitions
}

///|
/// Admit the complete bounded declaration graph before decoding boundary data.
fn admit_value(
  input : Json,
  format : Json,
  output~ : Bool = false,
) -> @execution.Value raise {
  ignore(
    closed_fields(
      input,
      ["value", "type", "definitions"],
      "workbench.invalid_request",
    ),
  )
  let budget = Ref(10000)
  let references : Array[String] = []
  let expected = declared_type(field(input, "type"), 0, budget, references)
  let definitions = declared_definitions(
    field(input, "definitions"),
    budget,
    references,
  )
  let value = decode_value(format, field(input, "value"))
  @execution.validate_as(value, expected, definitions, output~)
  value
}

///|
/// Supplied entries are a public allowlist, not evidence of model visibility.
/// Admit every output and unused declaration before decoding the suite.
fn admit_invocations(input : Json, format : Json) -> @execution.Suite raise {
  ignore(
    closed_fields(input, ["suite", "manifest"], "workbench.invalid_request"),
  )
  let (entries, definitions) = admit_manifest(field(input, "manifest"))
  let suite = match format {
    String("json") => @execution.Suite::from_json(field(input, "suite"))
    String("ion-text") => {
      guard field(input, "suite") is String(source) else {
        raise @execution.Invalid("workbench.invalid_request")
      }
      let value = @text.read_ion(source[:]) catch {
        _ => raise @execution.Invalid("workbench.invalid_ion")
      }
      @execution.Suite::from_ion(value)
    }
    _ => raise @execution.Invalid("workbench.invalid_request")
  }
  @execution.validate_invocations(suite, entries, definitions)
  suite
}

///|
fn admit_manifest(
  manifest : Json,
) -> (Array[@execution.PublicEntry], Array[@execution.CustomType]) raise {
  let code = "workbench.invalid_manifest"
  ignore(closed_fields(manifest, ["entries", "definitions"], code))
  let budget = Ref(10000)
  let references : Array[String] = []
  let names : Map[String, Bool] = Map([])
  let entries = declaration_array(field(manifest, "entries"), 1000, code).map(item => {
    declaration_nodes(budget)
    ignore(closed_fields(item, ["name", "inputs", "output"], code))
    let name = declaration_name(field(item, "name"), code)
    if names.contains(name) {
      raise @execution.Invalid(code)
    }
    names[name] = true
    let inputs = declaration_array(field(item, "inputs"), 64, code).map(t => {
      declared_type(t, 0, budget, references)
    })
    let output = declared_type(field(item, "output"), 0, budget, references)
    @execution.PublicEntry::{ name, inputs, output, }
  })
  let definitions = declared_definitions(
    field(manifest, "definitions"),
    budget,
    references,
  )
  (entries, definitions)
}

///|
fn admit_outcomes(input : Json, format : Json) -> @execution.Outcomes raise {
  ignore(
    closed_fields(
      input,
      ["suite", "manifest", "outcomes"],
      "workbench.invalid_request",
    ),
  )
  let (entries, definitions) = admit_manifest(field(input, "manifest"))
  let suite = @execution.Suite::from_json(field(input, "suite"))
  @execution.validate_invocations(suite, entries, definitions)
  let outcomes = match format {
    String("json") => @execution.Outcomes::from_json(field(input, "outcomes"))
    String("ion-text") => {
      guard field(input, "outcomes") is String(source) else {
        raise @execution.Invalid("workbench.invalid_request")
      }
      let value = @text.read_ion(source[:]) catch {
        _ => raise @execution.Invalid("workbench.invalid_ion")
      }
      @execution.Outcomes::from_ion(value)
    }
    _ => raise @execution.Invalid("workbench.invalid_request")
  }
  @execution.validate_outcomes(outcomes, suite, entries, definitions)
  outcomes
}
