///|
pub fn[TA] read_type(
  json : Json,
  ta : (Json) -> TA raise,
) -> @model.Type[TA] raise {
  let a = @wire.array(json)
  if a.is_empty() {
    raise @wire.Invalid("invalid_arity", "Empty node")
  }
  match @wire.string(a[0]) {
    "Variable" => {
      ignore(@wire.tuple(json, 3))
      @model.Variable(ta(a[1]), @wire.read_name(a[2]))
    }
    "Reference" => {
      ignore(@wire.tuple(json, 4))
      @model.Reference(
        ta(a[1]),
        @wire.read_fqname(a[2]),
        @wire.array(a[3]).map(item => read_type(item, ta)),
      )
    }
    "Tuple" => {
      ignore(@wire.tuple(json, 3))
      @model.Tuple(ta(a[1]), @wire.array(a[2]).map(item => read_type(item, ta)))
    }
    "Record" => {
      ignore(@wire.tuple(json, 3))
      @model.Record(
        ta(a[1]),
        @wire.array(a[2]).map(item => @model.Field::{
          name: @wire.read_name(@wire.field(item, "name")),
          tpe: read_type(@wire.field(item, "tpe"), ta),
        }),
      )
    }
    "ExtensibleRecord" => {
      ignore(@wire.tuple(json, 4))
      @model.ExtensibleRecord(
        ta(a[1]),
        @wire.read_name(a[2]),
        @wire.array(a[3]).map(item => @model.Field::{
          name: @wire.read_name(@wire.field(item, "name")),
          tpe: read_type(@wire.field(item, "tpe"), ta),
        }),
      )
    }
    "Function" => {
      ignore(@wire.tuple(json, 4))
      @model.Function(ta(a[1]), read_type(a[2], ta), read_type(a[3], ta))
    }
    "Unit" => {
      ignore(@wire.tuple(json, 2))
      @model.Unit(ta(a[1]))
    }
    other => raise @wire.Invalid("unknown_node", other)
  }
}

///|
pub fn[TA] write_type(
  value : @model.Type[TA],
  ta : (TA) -> Json raise,
) -> Json raise {
  match value {
    Variable(a, p0) =>
      Json::array([@wire.text("Variable"), ta(a), @wire.write_legacy_name(p0)])
    Reference(a, p0, p1) =>
      Json::array([
        @wire.text("Reference"),
        ta(a),
        @wire.write_legacy_fqname(p0),
        Json::array(p1.map(item => write_type(item, ta))),
      ])
    Tuple(a, p0) =>
      Json::array([
        @wire.text("Tuple"),
        ta(a),
        Json::array(p0.map(item => write_type(item, ta))),
      ])
    Record(a, p0) =>
      Json::array([
        @wire.text("Record"),
        ta(a),
        Json::array(
          p0.map(item => {
            @wire.obj([
              ("name", @wire.write_legacy_name(item.name)),
              ("tpe", write_type(item.tpe, ta)),
            ])
          }),
        ),
      ])
    ExtensibleRecord(a, p0, p1) =>
      Json::array([
        @wire.text("ExtensibleRecord"),
        ta(a),
        @wire.write_legacy_name(p0),
        Json::array(
          p1.map(item => {
            @wire.obj([
              ("name", @wire.write_legacy_name(item.name)),
              ("tpe", write_type(item.tpe, ta)),
            ])
          }),
        ),
      ])
    Function(a, p0, p1) =>
      Json::array([
        @wire.text("Function"),
        ta(a),
        write_type(p0, ta),
        write_type(p1, ta),
      ])
    Unit(a) => Json::array([@wire.text("Unit"), ta(a)])
  }
}

///|
pub fn[VA] read_pattern(
  json : Json,
  va : (Json) -> VA raise,
) -> @model.Pattern[VA] raise {
  let a = @wire.array(json)
  if a.is_empty() {
    raise @wire.Invalid("invalid_arity", "Empty node")
  }
  match @wire.string(a[0]) {
    "wildcard_pattern" => {
      ignore(@wire.tuple(json, 2))
      @model.WildcardPattern(va(a[1]))
    }
    "as_pattern" => {
      ignore(@wire.tuple(json, 4))
      @model.AsPattern(va(a[1]), read_pattern(a[2], va), @wire.read_name(a[3]))
    }
    "tuple_pattern" => {
      ignore(@wire.tuple(json, 3))
      @model.TuplePattern(
        va(a[1]),
        @wire.array(a[2]).map(item => read_pattern(item, va)),
      )
    }
    "constructor_pattern" => {
      ignore(@wire.tuple(json, 4))
      @model.ConstructorPattern(
        va(a[1]),
        @wire.read_fqname(a[2]),
        @wire.array(a[3]).map(item => read_pattern(item, va)),
      )
    }
    "empty_list_pattern" => {
      ignore(@wire.tuple(json, 2))
      @model.EmptyListPattern(va(a[1]))
    }
    "head_tail_pattern" => {
      ignore(@wire.tuple(json, 4))
      @model.HeadTailPattern(
        va(a[1]),
        read_pattern(a[2], va),
        read_pattern(a[3], va),
      )
    }
    "literal_pattern" => {
      ignore(@wire.tuple(json, 3))
      @model.LiteralPattern(va(a[1]), read_literal(a[2]))
    }
    "unit_pattern" => {
      ignore(@wire.tuple(json, 2))
      @model.UnitPattern(va(a[1]))
    }
    other => raise @wire.Invalid("unknown_node", other)
  }
}

///|
pub fn[VA] write_pattern(
  value : @model.Pattern[VA],
  va : (VA) -> Json raise,
) -> Json raise {
  match value {
    WildcardPattern(a) => Json::array([@wire.text("wildcard_pattern"), va(a)])
    AsPattern(a, p0, p1) =>
      Json::array([
        @wire.text("as_pattern"),
        va(a),
        write_pattern(p0, va),
        @wire.write_legacy_name(p1),
      ])
    TuplePattern(a, p0) =>
      Json::array([
        @wire.text("tuple_pattern"),
        va(a),
        Json::array(p0.map(item => write_pattern(item, va))),
      ])
    ConstructorPattern(a, p0, p1) =>
      Json::array([
        @wire.text("constructor_pattern"),
        va(a),
        @wire.write_legacy_fqname(p0),
        Json::array(p1.map(item => write_pattern(item, va))),
      ])
    EmptyListPattern(a) =>
      Json::array([@wire.text("empty_list_pattern"), va(a)])
    HeadTailPattern(a, p0, p1) =>
      Json::array([
        @wire.text("head_tail_pattern"),
        va(a),
        write_pattern(p0, va),
        write_pattern(p1, va),
      ])
    LiteralPattern(a, p0) =>
      Json::array([@wire.text("literal_pattern"), va(a), write_literal(p0)])
    UnitPattern(a) => Json::array([@wire.text("unit_pattern"), va(a)])
  }
}

///|
pub fn[TA, VA] read_value(
  json : Json,
  ta : (Json) -> TA raise,
  va : (Json) -> VA raise,
) -> @model.Value[TA, VA] raise {
  let a = @wire.array(json)
  if a.is_empty() {
    raise @wire.Invalid("invalid_arity", "Empty node")
  }
  match @wire.string(a[0]) {
    "literal" => {
      ignore(@wire.tuple(json, 3))
      @model.Literal(va(a[1]), read_literal(a[2]))
    }
    "constructor" => {
      ignore(@wire.tuple(json, 3))
      @model.Constructor(va(a[1]), @wire.read_fqname(a[2]))
    }
    "tuple" => {
      ignore(@wire.tuple(json, 3))
      @model.Tuple(
        va(a[1]),
        @wire.array(a[2]).map(item => read_value(item, ta, va)),
      )
    }
    "list" => {
      ignore(@wire.tuple(json, 3))
      @model.List(
        va(a[1]),
        @wire.array(a[2]).map(item => read_value(item, ta, va)),
      )
    }
    "record" => {
      ignore(@wire.tuple(json, 3))
      @model.Record(
        va(a[1]),
        @wire.read_map(a[2], @wire.read_name, fn(item) raise {
          read_value(item, ta, va)
        }),
      )
    }
    "variable" => {
      ignore(@wire.tuple(json, 3))
      @model.Variable(va(a[1]), @wire.read_name(a[2]))
    }
    "reference" => {
      ignore(@wire.tuple(json, 3))
      @model.Reference(va(a[1]), @wire.read_fqname(a[2]))
    }
    "field" => {
      ignore(@wire.tuple(json, 4))
      @model.Field(va(a[1]), read_value(a[2], ta, va), @wire.read_name(a[3]))
    }
    "field_function" => {
      ignore(@wire.tuple(json, 3))
      @model.FieldFunction(va(a[1]), @wire.read_name(a[2]))
    }
    "apply" => {
      ignore(@wire.tuple(json, 4))
      @model.Apply(va(a[1]), read_value(a[2], ta, va), read_value(a[3], ta, va))
    }
    "lambda" => {
      ignore(@wire.tuple(json, 4))
      @model.Lambda(va(a[1]), read_pattern(a[2], va), read_value(a[3], ta, va))
    }
    "let_definition" => {
      ignore(@wire.tuple(json, 5))
      @model.LetDefinition(
        va(a[1]),
        @wire.read_name(a[2]),
        read_value_definition(a[3], ta, va),
        read_value(a[4], ta, va),
      )
    }
    "let_recursion" => {
      ignore(@wire.tuple(json, 4))
      @model.LetRecursion(
        va(a[1]),
        @wire.read_map(a[2], @wire.read_name, fn(item) raise {
          read_value_definition(item, ta, va)
        }),
        read_value(a[3], ta, va),
      )
    }
    "destructure" => {
      ignore(@wire.tuple(json, 5))
      @model.Destructure(
        va(a[1]),
        read_pattern(a[2], va),
        read_value(a[3], ta, va),
        read_value(a[4], ta, va),
      )
    }
    "if_then_else" => {
      ignore(@wire.tuple(json, 5))
      @model.IfThenElse(
        va(a[1]),
        read_value(a[2], ta, va),
        read_value(a[3], ta, va),
        read_value(a[4], ta, va),
      )
    }
    "pattern_match" => {
      ignore(@wire.tuple(json, 4))
      @model.PatternMatch(
        va(a[1]),
        read_value(a[2], ta, va),
        @wire.array(a[3]).map(item => {
          let pair = @wire.tuple(item, 2)
          (read_pattern(pair[0], va), read_value(pair[1], ta, va))
        }),
      )
    }
    "update_record" => {
      ignore(@wire.tuple(json, 4))
      @model.UpdateRecord(
        va(a[1]),
        read_value(a[2], ta, va),
        @wire.read_map(a[3], @wire.read_name, fn(item) raise {
          read_value(item, ta, va)
        }),
      )
    }
    "unit" => {
      ignore(@wire.tuple(json, 2))
      @model.Unit(va(a[1]))
    }
    other => raise @wire.Invalid("unknown_node", other)
  }
}

///|
pub fn[TA, VA] write_value(
  value : @model.Value[TA, VA],
  ta : (TA) -> Json raise,
  va : (VA) -> Json raise,
) -> Json raise {
  match value {
    Literal(a, p0) =>
      Json::array([@wire.text("literal"), va(a), write_literal(p0)])
    Constructor(a, p0) =>
      Json::array([
        @wire.text("constructor"),
        va(a),
        @wire.write_legacy_fqname(p0),
      ])
    Tuple(a, p0) =>
      Json::array([
        @wire.text("tuple"),
        va(a),
        Json::array(p0.map(item => write_value(item, ta, va))),
      ])
    List(a, p0) =>
      Json::array([
        @wire.text("list"),
        va(a),
        Json::array(p0.map(item => write_value(item, ta, va))),
      ])
    Record(a, p0) =>
      Json::array([
        @wire.text("record"),
        va(a),
        @wire.write_map(
          p0,
          fn(key) raise { @wire.write_legacy_name(key) },
          fn(item) raise { write_value(item, ta, va) },
          legacy=true,
        ),
      ])
    Variable(a, p0) =>
      Json::array([@wire.text("variable"), va(a), @wire.write_legacy_name(p0)])
    Reference(a, p0) =>
      Json::array([
        @wire.text("reference"),
        va(a),
        @wire.write_legacy_fqname(p0),
      ])
    Field(a, p0, p1) =>
      Json::array([
        @wire.text("field"),
        va(a),
        write_value(p0, ta, va),
        @wire.write_legacy_name(p1),
      ])
    FieldFunction(a, p0) =>
      Json::array([
        @wire.text("field_function"),
        va(a),
        @wire.write_legacy_name(p0),
      ])
    Apply(a, p0, p1) =>
      Json::array([
        @wire.text("apply"),
        va(a),
        write_value(p0, ta, va),
        write_value(p1, ta, va),
      ])
    Lambda(a, p0, p1) =>
      Json::array([
        @wire.text("lambda"),
        va(a),
        write_pattern(p0, va),
        write_value(p1, ta, va),
      ])
    LetDefinition(a, p0, p1, p2) =>
      Json::array([
        @wire.text("let_definition"),
        va(a),
        @wire.write_legacy_name(p0),
        write_value_definition(p1, ta, va),
        write_value(p2, ta, va),
      ])
    LetRecursion(a, p0, p1) =>
      Json::array([
        @wire.text("let_recursion"),
        va(a),
        @wire.write_map(
          p0,
          fn(key) raise { @wire.write_legacy_name(key) },
          fn(item) raise { write_value_definition(item, ta, va) },
          legacy=true,
        ),
        write_value(p1, ta, va),
      ])
    Destructure(a, p0, p1, p2) =>
      Json::array([
        @wire.text("destructure"),
        va(a),
        write_pattern(p0, va),
        write_value(p1, ta, va),
        write_value(p2, ta, va),
      ])
    IfThenElse(a, p0, p1, p2) =>
      Json::array([
        @wire.text("if_then_else"),
        va(a),
        write_value(p0, ta, va),
        write_value(p1, ta, va),
        write_value(p2, ta, va),
      ])
    PatternMatch(a, p0, p1) =>
      Json::array([
        @wire.text("pattern_match"),
        va(a),
        write_value(p0, ta, va),
        Json::array(
          p1.map(item => {
            Json::array([write_pattern(item.0, va), write_value(item.1, ta, va)])
          }),
        ),
      ])
    UpdateRecord(a, p0, p1) =>
      Json::array([
        @wire.text("update_record"),
        va(a),
        write_value(p0, ta, va),
        @wire.write_map(
          p1,
          fn(key) raise { @wire.write_legacy_name(key) },
          fn(item) raise { write_value(item, ta, va) },
          legacy=true,
        ),
      ])
    Unit(a) => Json::array([@wire.text("unit"), va(a)])
  }
}

///|
pub fn read_literal(value : Json) -> @model.Literal raise {
  let a = @wire.tuple(value, 2)
  let json = a[1]
  match @wire.string(a[0]) {
    "bool_literal" | "BoolLiteral" => @model.BoolLiteral(@wire.boolean(json))
    "char_literal" | "CharLiteral" => @model.CharLiteral(@wire.character(json))
    "string_literal" | "StringLiteral" =>
      @model.StringLiteral(@wire.string(json))
    "whole_number_literal" | "WholeNumberLiteral" =>
      @model.WholeNumberLiteral(@wire.integer_text(json))
    "float_literal" | "FloatLiteral" => @model.FloatLiteral(@wire.float(json))
    "decimal_literal" | "DecimalLiteral" =>
      @model.DecimalLiteral(@wire.decimal(json))
    other => raise @wire.Invalid("unknown_node", other)
  }
}

///|
pub fn write_literal(literal : @model.Literal) -> Json raise {
  match literal {
    BoolLiteral(value) => Json::array([@wire.text("BoolLiteral"), Json(value)])
    CharLiteral(value) =>
      Json::array([@wire.text("CharLiteral"), @wire.text(value.to_string())])
    StringLiteral(value) =>
      Json::array([@wire.text("StringLiteral"), @wire.text(value)])
    WholeNumberLiteral(value) =>
      Json::array([@wire.text("WholeNumberLiteral"), @wire.write_integer(value)])
    FloatLiteral(value) =>
      Json::array([@wire.text("FloatLiteral"), @wire.write_float(value)])
    DecimalLiteral(value) =>
      Json::array([
        @wire.text("DecimalLiteral"),
        @wire.text(@wire.decimal(@wire.text(value))),
      ])
  }
}
