///|
pub fn read_type(json : Json) -> @model.Type raise {
  if json is Object(fields) && fields.length() != 1 {
    raise @wire.Invalid("unknown_node", "Expected a type variant")
  }
  match json {
    String(text) =>
      return if text.contains("#") {
        @model.Type::Reference(
          @model.TypeAttributes::default(),
          @wire.read_fqname(json),
          [],
        )
      } else {
        @model.Type::Variable(
          @model.TypeAttributes::default(),
          @wire.read_name(json),
        )
      }
    Array(items) =>
      return @model.Type::Tuple(
        @model.TypeAttributes::default(),
        items.map(read_type),
      )
    _ => ()
  }
  let (tag, payload) = variant(json)
  match tag {
    "Variable" => {
      let payload = match payload {
        String(_) | Array(_) => @wire.obj([("name", payload)])
        _ => payload
      }
      payload_fields(payload, ["name"])
      @model.Type::Variable(
        read_type_attributes(attr_payload(payload)),
        @wire.read_name(@wire.field(payload, "name")),
      )
    }
    "Reference" => {
      let payload = match payload {
        String(_) => @wire.obj([("fqname", payload)])
        Array(items) if !items.is_empty() =>
          @wire.obj([
            ("fqname", items[0]),
            ("args", Json::array(items[1:].to_owned())),
          ])
        _ => payload
      }
      payload_fields(payload, ["fqname", "args"])
      @model.Type::Reference(
        read_type_attributes(attr_payload(payload)),
        @wire.read_fqname(@wire.field(payload, "fqname")),
        @wire.array(optional_array(payload, "args")).map(read_type),
      )
    }
    "Union" => {
      let payload = match payload {
        Array(_) => @wire.obj([("alternatives", payload)])
        _ => payload
      }
      payload_fields(payload, ["alternatives"])
      let alternatives = @wire.array(@wire.field(payload, "alternatives"))
      if alternatives.length() < 2 {
        raise @wire.Invalid(
          "invalid_arity", "Union requires at least two alternatives",
        )
      }
      @model.Type::Union(
        read_type_attributes(attr_payload(payload)),
        alternatives.map(read_type),
      )
    }
    "Tuple" => {
      let payload = match payload {
        Array(_) => @wire.obj([("elements", payload)])
        _ => payload
      }
      payload_fields(payload, ["elements"])
      @model.Type::Tuple(
        read_type_attributes(attr_payload(payload)),
        @wire.array(@wire.field(payload, "elements")).map(read_type),
      )
    }
    "Record" => {
      let payload = match payload {
        Object(fields) if fields.contains("fields") => payload
        _ => @wire.obj([("fields", payload)])
      }
      payload_fields(payload, ["fields"])
      @model.Type::Record(
        read_type_attributes(attr_payload(payload)),
        @wire.read_map(
          @wire.field(payload, "fields"),
          @wire.read_name,
          read_type,
        ),
      )
    }
    "ExtensibleRecord" => {
      payload_fields(payload, ["variable", "fields"])
      @model.Type::ExtensibleRecord(
        read_type_attributes(attr_payload(payload)),
        @wire.read_name(@wire.field(payload, "variable")),
        @wire.read_map(
          @wire.field(payload, "fields"),
          @wire.read_name,
          read_type,
        ),
      )
    }
    "Function" => {
      payload_fields(payload, [
        "parameterType", "returnType", "argumentType", "arg", "result",
      ])
      @model.Type::Function(
        read_type_attributes(attr_payload(payload)),
        read_type(
          alias_field(payload, "parameterType", ["argumentType", "arg"]),
        ),
        read_type(alias_field(payload, "returnType", ["result"])),
      )
    }
    "Unit" => {
      payload_fields(payload, [])
      @model.Type::Unit(read_type_attributes(attr_payload(payload)))
    }
    other => raise @wire.Invalid("unknown_node", other)
  }
}

///|
pub fn write_type(value : @model.Type) -> Json raise {
  match value {
    Variable(attributes, p0) => {
      let attributes = write_type_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.write_name(p0)
      }
      let fields : Array[(String, Json)] = []
      fields.push(("name", @wire.write_name(p0)))
      expanded("Variable", attributes, fields)
    }
    Reference(attributes, p0, p1) => {
      let attributes = write_type_attributes(attributes)
      if attributes == Json::object(Map([])) {
        if p1.is_empty() {
          return @wire.write_fqname(p0)
        }
        return @wire.tag(
          "Reference",
          Json::array([@wire.write_fqname(p0)] + p1.map(write_type)),
        )
      }
      let fields : Array[(String, Json)] = []
      fields.push(("fqname", @wire.write_fqname(p0)))
      fields.push(("args", Json::array(p1.map(write_type))))
      expanded("Reference", attributes, fields)
    }
    Union(attributes, alternatives) => {
      if alternatives.length() < 2 {
        raise @wire.Invalid(
          "invalid_arity", "Union requires at least two alternatives",
        )
      }
      let attributes = write_type_attributes(attributes)
      let children = Json::array(alternatives.map(write_type))
      if attributes == Json::object(Map([])) {
        return @wire.tag("Union", children)
      }
      expanded("Union", attributes, [("alternatives", children)])
    }
    Tuple(attributes, p0) => {
      let attributes = write_type_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("Tuple", Json::array(p0.map(write_type)))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("elements", Json::array(p0.map(write_type))))
      expanded("Tuple", attributes, fields)
    }
    Record(attributes, p0) => {
      let attributes = write_type_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("fields", @wire.write_map(p0, name_key, write_type)))
      expanded("Record", attributes, fields)
    }
    ExtensibleRecord(attributes, p0, p1) => {
      let attributes = write_type_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("variable", @wire.write_name(p0)))
      fields.push(("fields", @wire.write_map(p1, name_key, write_type)))
      expanded("ExtensibleRecord", attributes, fields)
    }
    Function(attributes, p0, p1) => {
      let attributes = write_type_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("parameterType", write_type(p0)))
      fields.push(("returnType", write_type(p1)))
      expanded("Function", attributes, fields)
    }
    Unit(attributes) => {
      let attributes = write_type_attributes(attributes)
      let fields : Array[(String, Json)] = []
      expanded("Unit", attributes, fields)
    }
  }
}

///|
pub fn read_pattern(json : Json) -> @model.Pattern raise {
  if json is Array(items) {
    return @model.Pattern::TuplePattern(
      @model.ValueAttributes::default(),
      items.map(read_pattern),
    )
  }
  let (tag, payload) = variant(json)
  match tag {
    "WildcardPattern" => {
      payload_fields(payload, [])
      @model.Pattern::WildcardPattern(
        read_value_attributes(attr_payload(payload)),
      )
    }
    "AsPattern" => {
      payload_fields(payload, ["pattern", "name"])
      @model.Pattern::AsPattern(
        read_value_attributes(attr_payload(payload)),
        read_pattern(@wire.field(payload, "pattern")),
        @wire.read_name(@wire.field(payload, "name")),
      )
    }
    "TuplePattern" => {
      let payload = match payload {
        Array(_) => @wire.obj([("patterns", payload)])
        _ => payload
      }
      payload_fields(payload, ["patterns"])
      @model.Pattern::TuplePattern(
        read_value_attributes(attr_payload(payload)),
        @wire.array(@wire.field(payload, "patterns")).map(read_pattern),
      )
    }
    "ConstructorPattern" => {
      payload_fields(payload, ["fqname", "patterns"])
      @model.Pattern::ConstructorPattern(
        read_value_attributes(attr_payload(payload)),
        @wire.read_fqname(@wire.field(payload, "fqname")),
        @wire.array(@wire.field(payload, "patterns")).map(read_pattern),
      )
    }
    "EmptyListPattern" => {
      payload_fields(payload, [])
      @model.Pattern::EmptyListPattern(
        read_value_attributes(attr_payload(payload)),
      )
    }
    "HeadTailPattern" => {
      payload_fields(payload, ["head", "tail"])
      @model.Pattern::HeadTailPattern(
        read_value_attributes(attr_payload(payload)),
        read_pattern(@wire.field(payload, "head")),
        read_pattern(@wire.field(payload, "tail")),
      )
    }
    "LiteralPattern" => {
      let payload = match payload {
        Object(fields) if fields.contains("literal") => payload
        _ => @wire.obj([("literal", payload)])
      }
      payload_fields(payload, ["literal"])
      @model.Pattern::LiteralPattern(
        read_value_attributes(attr_payload(payload)),
        read_pattern_literal(@wire.field(payload, "literal")),
      )
    }
    "UnitPattern" => {
      payload_fields(payload, [])
      @model.Pattern::UnitPattern(read_value_attributes(attr_payload(payload)))
    }
    other => raise @wire.Invalid("unknown_node", other)
  }
}

///|
pub fn write_pattern(value : @model.Pattern) -> Json raise {
  match value {
    WildcardPattern(attributes) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      expanded("WildcardPattern", attributes, fields)
    }
    AsPattern(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("pattern", write_pattern(p0)))
      fields.push(("name", @wire.write_name(p1)))
      expanded("AsPattern", attributes, fields)
    }
    TuplePattern(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("TuplePattern", Json::array(p0.map(write_pattern)))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("patterns", Json::array(p0.map(write_pattern))))
      expanded("TuplePattern", attributes, fields)
    }
    ConstructorPattern(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("fqname", @wire.write_fqname(p0)))
      fields.push(("patterns", Json::array(p1.map(write_pattern))))
      expanded("ConstructorPattern", attributes, fields)
    }
    EmptyListPattern(attributes) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      expanded("EmptyListPattern", attributes, fields)
    }
    HeadTailPattern(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("head", write_pattern(p0)))
      fields.push(("tail", write_pattern(p1)))
      expanded("HeadTailPattern", attributes, fields)
    }
    LiteralPattern(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("LiteralPattern", write_pattern_literal(p0))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("literal", write_pattern_literal(p0)))
      expanded("LiteralPattern", attributes, fields)
    }
    UnitPattern(attributes) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      expanded("UnitPattern", attributes, fields)
    }
  }
}

///|
pub fn read_value(json : Json) -> @model.Value raise {
  match json {
    String(text) =>
      return if text.contains("#") {
        @model.Value::Reference(
          @model.ValueAttributes::default(),
          @wire.read_fqname(json),
        )
      } else {
        @model.Value::Variable(
          @model.ValueAttributes::default(),
          @wire.read_name(json),
        )
      }
    Array(items) =>
      return @model.Value::List(
        @model.ValueAttributes::default(),
        items.map(read_value),
      )
    True | False | Number(_, ..) =>
      return @model.Value::Literal(
        @model.ValueAttributes::default(),
        read_literal(json),
      )
    _ => ()
  }
  let (tag, payload) = variant(json)
  match tag {
    "Literal" => {
      let payload = match payload {
        Object(fields) if fields.contains("literal") => payload
        _ => @wire.obj([("literal", payload)])
      }
      payload_fields(payload, ["literal"])
      @model.Value::Literal(
        read_value_attributes(attr_payload(payload)),
        read_literal(@wire.field(payload, "literal")),
      )
    }
    "Constructor" => {
      let payload = match payload {
        String(_) | Array(_) => @wire.obj([("fqname", payload)])
        _ => payload
      }
      payload_fields(payload, ["fqname"])
      @model.Value::Constructor(
        read_value_attributes(attr_payload(payload)),
        @wire.read_fqname(@wire.field(payload, "fqname")),
      )
    }
    "Tuple" => {
      let payload = match payload {
        Array(_) => @wire.obj([("elements", payload)])
        _ => payload
      }
      payload_fields(payload, ["elements"])
      @model.Value::Tuple(
        read_value_attributes(attr_payload(payload)),
        @wire.array(@wire.field(payload, "elements")).map(read_value),
      )
    }
    "List" => {
      let payload = match payload {
        Array(_) => @wire.obj([("items", payload)])
        _ => payload
      }
      payload_fields(payload, ["items"])
      @model.Value::List(
        read_value_attributes(attr_payload(payload)),
        @wire.array(@wire.field(payload, "items")).map(read_value),
      )
    }
    "Record" => {
      let payload = match payload {
        Object(fields) if fields.contains("fields") => payload
        _ => @wire.obj([("fields", payload)])
      }
      payload_fields(payload, ["fields"])
      @model.Value::Record(
        read_value_attributes(attr_payload(payload)),
        @wire.read_map(
          @wire.field(payload, "fields"),
          @wire.read_name,
          read_value,
        ),
      )
    }
    "Variable" => {
      let payload = match payload {
        String(_) | Array(_) => @wire.obj([("name", payload)])
        _ => payload
      }
      payload_fields(payload, ["name"])
      @model.Value::Variable(
        read_value_attributes(attr_payload(payload)),
        @wire.read_name(@wire.field(payload, "name")),
      )
    }
    "Reference" => {
      let payload = match payload {
        String(_) | Array(_) => @wire.obj([("fqname", payload)])
        _ => payload
      }
      payload_fields(payload, ["fqname"])
      @model.Value::Reference(
        read_value_attributes(attr_payload(payload)),
        @wire.read_fqname(@wire.field(payload, "fqname")),
      )
    }
    "Field" => {
      payload_fields(payload, ["target", "name", "subject", "fieldName"])
      @model.Value::Field(
        read_value_attributes(attr_payload(payload)),
        read_value(alias_field(payload, "target", ["subject"])),
        @wire.read_name(alias_field(payload, "name", ["fieldName"])),
      )
    }
    "FieldFunction" => {
      let payload = match payload {
        String(_) | Array(_) => @wire.obj([("name", payload)])
        _ => payload
      }
      payload_fields(payload, ["name"])
      @model.Value::FieldFunction(
        read_value_attributes(attr_payload(payload)),
        @wire.read_name(@wire.field(payload, "name")),
      )
    }
    "Apply" => {
      payload_fields(payload, ["function", "argument"])
      @model.Value::Apply(
        read_value_attributes(attr_payload(payload)),
        read_value(@wire.field(payload, "function")),
        read_value(@wire.field(payload, "argument")),
      )
    }
    "Lambda" => {
      payload_fields(payload, ["pattern", "body"])
      @model.Value::Lambda(
        read_value_attributes(attr_payload(payload)),
        read_pattern(@wire.field(payload, "pattern")),
        read_value(@wire.field(payload, "body")),
      )
    }
    "LetDefinition" => {
      payload_fields(payload, [
        "name", "definition", "in", "valueName", "valueDefinition", "inValue",
      ])
      @model.Value::LetDefinition(
        read_value_attributes(attr_payload(payload)),
        @wire.read_name(alias_field(payload, "name", ["valueName"])),
        read_definition(alias_field(payload, "definition", ["valueDefinition"])),
        read_value(alias_field(payload, "in", ["inValue"])),
      )
    }
    "LetRecursion" => {
      payload_fields(payload, ["definitions", "in", "inValue"])
      @model.Value::LetRecursion(
        read_value_attributes(attr_payload(payload)),
        @wire.read_map(
          @wire.field(payload, "definitions"),
          @wire.read_name,
          read_definition,
        ),
        read_value(alias_field(payload, "in", ["inValue"])),
      )
    }
    "Destructure" => {
      payload_fields(payload, [
        "pattern", "value", "in", "valueToDestruct", "inValue",
      ])
      @model.Value::Destructure(
        read_value_attributes(attr_payload(payload)),
        read_pattern(@wire.field(payload, "pattern")),
        read_value(alias_field(payload, "value", ["valueToDestruct"])),
        read_value(alias_field(payload, "in", ["inValue"])),
      )
    }
    "IfThenElse" => {
      payload_fields(payload, [
        "condition", "then", "else", "thenBranch", "elseBranch",
      ])
      @model.Value::IfThenElse(
        read_value_attributes(attr_payload(payload)),
        read_value(@wire.field(payload, "condition")),
        read_value(alias_field(payload, "then", ["thenBranch"])),
        read_value(alias_field(payload, "else", ["elseBranch"])),
      )
    }
    "PatternMatch" => {
      payload_fields(payload, ["value", "cases", "branchOutOn"])
      @model.Value::PatternMatch(
        read_value_attributes(attr_payload(payload)),
        read_value(alias_field(payload, "value", ["branchOutOn"])),
        @wire.array(@wire.field(payload, "cases")).map(read_case),
      )
    }
    "UpdateRecord" => {
      payload_fields(payload, ["target", "fields", "subject", "fieldsToUpdate"])
      @model.Value::UpdateRecord(
        read_value_attributes(attr_payload(payload)),
        read_value(alias_field(payload, "target", ["subject"])),
        @wire.read_map(
          alias_field(payload, "fields", ["fieldsToUpdate"]),
          @wire.read_name,
          read_value,
        ),
      )
    }
    "Unit" => {
      payload_fields(payload, [])
      @model.Value::Unit(read_value_attributes(attr_payload(payload)))
    }
    "Hole" => {
      payload_fields(payload, ["reason", "expectedType"])
      @model.Value::Hole(
        read_value_attributes(attr_payload(payload)),
        read_reason(@wire.field(payload, "reason")),
        read_optional(payload, "expectedType", read_type),
      )
    }
    other => raise @wire.Invalid("unknown_node", other)
  }
}

///|
pub fn write_value(value : @model.Value) -> Json raise {
  match value {
    Literal(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("Literal", write_literal(p0))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("literal", write_literal(p0)))
      expanded("Literal", attributes, fields)
    }
    Constructor(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("Constructor", @wire.write_fqname(p0))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("fqname", @wire.write_fqname(p0)))
      expanded("Constructor", attributes, fields)
    }
    Tuple(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("Tuple", Json::array(p0.map(write_value)))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("elements", Json::array(p0.map(write_value))))
      expanded("Tuple", attributes, fields)
    }
    List(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("List", Json::array(p0.map(write_value)))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("items", Json::array(p0.map(write_value))))
      expanded("List", attributes, fields)
    }
    Record(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("fields", @wire.write_map(p0, name_key, write_value)))
      expanded("Record", attributes, fields)
    }
    Variable(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("Variable", @wire.write_name(p0))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("name", @wire.write_name(p0)))
      expanded("Variable", attributes, fields)
    }
    Reference(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("Reference", @wire.write_fqname(p0))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("fqname", @wire.write_fqname(p0)))
      expanded("Reference", attributes, fields)
    }
    Field(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("target", write_value(p0)))
      fields.push(("name", @wire.write_name(p1)))
      expanded("Field", attributes, fields)
    }
    FieldFunction(attributes, p0) => {
      let attributes = write_value_attributes(attributes)
      if attributes == Json::object(Map([])) {
        return @wire.tag("FieldFunction", @wire.write_name(p0))
      }
      let fields : Array[(String, Json)] = []
      fields.push(("name", @wire.write_name(p0)))
      expanded("FieldFunction", attributes, fields)
    }
    Apply(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("function", write_value(p0)))
      fields.push(("argument", write_value(p1)))
      expanded("Apply", attributes, fields)
    }
    Lambda(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("pattern", write_pattern(p0)))
      fields.push(("body", write_value(p1)))
      expanded("Lambda", attributes, fields)
    }
    LetDefinition(attributes, p0, p1, p2) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("name", @wire.write_name(p0)))
      fields.push(("definition", write_definition(p1)))
      fields.push(("in", write_value(p2)))
      expanded("LetDefinition", attributes, fields)
    }
    LetRecursion(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(
        ("definitions", @wire.write_map(p0, name_key, write_definition)),
      )
      fields.push(("in", write_value(p1)))
      expanded("LetRecursion", attributes, fields)
    }
    Destructure(attributes, p0, p1, p2) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("pattern", write_pattern(p0)))
      fields.push(("value", write_value(p1)))
      fields.push(("in", write_value(p2)))
      expanded("Destructure", attributes, fields)
    }
    IfThenElse(attributes, p0, p1, p2) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("condition", write_value(p0)))
      fields.push(("then", write_value(p1)))
      fields.push(("else", write_value(p2)))
      expanded("IfThenElse", attributes, fields)
    }
    PatternMatch(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("value", write_value(p0)))
      fields.push(("cases", Json::array(p1.map(write_case))))
      expanded("PatternMatch", attributes, fields)
    }
    UpdateRecord(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("target", write_value(p0)))
      fields.push(("fields", @wire.write_map(p1, name_key, write_value)))
      expanded("UpdateRecord", attributes, fields)
    }
    Unit(attributes) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      expanded("Unit", attributes, fields)
    }
    Hole(attributes, p0, p1) => {
      let attributes = write_value_attributes(attributes)
      let fields : Array[(String, Json)] = []
      fields.push(("reason", write_reason(p0)))
      if p1 is Some(tpe) {
        fields.push(("expectedType", write_type(tpe)))
      }
      expanded("Hole", attributes, fields)
    }
  }
}

///|
fn read_case(json : Json) -> (@model.Pattern, @model.Value) raise {
  @wire.fields(json, ["pattern", "body"])
  (
    read_pattern(@wire.field(json, "pattern")),
    read_value(@wire.field(json, "body")),
  )
}

///|
fn write_case(value : (@model.Pattern, @model.Value)) -> Json raise {
  @wire.obj([
    ("pattern", write_pattern(value.0)),
    ("body", write_value(value.1)),
  ])
}
