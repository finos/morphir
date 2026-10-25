///|
pub fn read_literal(json : Json) -> @model.Literal raise {
  match json {
    True | False => return @model.Literal::BoolLiteral(@wire.boolean(json))
    String(text) => return @model.Literal::StringLiteral(text)
    Number(_, ..) => {
      let lexeme = @wire.number_text(json)
      return if lexeme.contains(".") ||
        lexeme.contains("e") ||
        lexeme.contains("E") {
        @model.Literal::FloatLiteral(@wire.float(json))
      } else {
        @model.Literal::IntegerLiteral(lexeme)
      }
    }
    _ => ()
  }
  let (tag, payload) = variant(json)
  if tag == "DocumentLiteral" {
    return @model.Literal::DocumentLiteral(@wire.read_data(payload))
  }
  let payload = match payload {
    Object(_) => {
      @wire.fields(payload, ["value"])
      @wire.field(payload, "value")
    }
    _ => payload
  }
  match tag {
    "BoolLiteral" => @model.Literal::BoolLiteral(@wire.boolean(payload))
    "CharLiteral" => @model.Literal::CharLiteral(@wire.character(payload))
    "StringLiteral" => @model.Literal::StringLiteral(@wire.string(payload))
    "IntegerLiteral" | "WholeNumberLiteral" =>
      @model.Literal::IntegerLiteral(@wire.integer_text(payload))
    "FloatLiteral" => @model.Literal::FloatLiteral(@wire.float(payload))
    "DecimalLiteral" => @model.Literal::DecimalLiteral(@wire.decimal(payload))
    _ => raise @wire.Invalid("unknown_node", tag)
  }
}

///|
pub fn write_literal(value : @model.Literal) -> Json raise {
  match value {
    BoolLiteral(value) => @wire.tag("BoolLiteral", Json(value))
    CharLiteral(value) =>
      @wire.tag("CharLiteral", @wire.text(value.to_string()))
    StringLiteral(value) => @wire.tag("StringLiteral", @wire.text(value))
    IntegerLiteral(value) => {
      let json = @wire.number(value)
      ignore(@wire.integer_text(json))
      @wire.tag("IntegerLiteral", json)
    }
    FloatLiteral(value) => {
      let json = @wire.write_float(value)
      @wire.tag("FloatLiteral", json)
    }
    DecimalLiteral(value) =>
      @wire.tag("DecimalLiteral", @wire.text(@wire.decimal(@wire.text(value))))
    DocumentLiteral(value) =>
      @wire.tag("DocumentLiteral", @wire.write_data(value))
  }
}

///|
pub fn read_pattern_literal(json : Json) -> @model.PatternLiteral raise {
  match read_literal(json) {
    BoolLiteral(value) => @model.PatternLiteral::BoolLiteral(value)
    CharLiteral(value) => @model.PatternLiteral::CharLiteral(value)
    StringLiteral(value) => @model.PatternLiteral::StringLiteral(value)
    IntegerLiteral(value) => @model.PatternLiteral::IntegerLiteral(value)
    FloatLiteral(value) => @model.PatternLiteral::FloatLiteral(value)
    DecimalLiteral(value) => @model.PatternLiteral::DecimalLiteral(value)
    DocumentLiteral(_) =>
      raise @wire.Invalid("invalid_literal", "DocumentLiteral")
  }
}

///|
pub fn write_pattern_literal(value : @model.PatternLiteral) -> Json raise {
  write_literal(
    match value {
      BoolLiteral(value) => @model.Literal::BoolLiteral(value)
      CharLiteral(value) => @model.Literal::CharLiteral(value)
      StringLiteral(value) => @model.Literal::StringLiteral(value)
      IntegerLiteral(value) => @model.Literal::IntegerLiteral(value)
      FloatLiteral(value) => @model.Literal::FloatLiteral(value)
      DecimalLiteral(value) => @model.Literal::DecimalLiteral(value)
    },
  )
}
