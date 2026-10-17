///|
fn scheme_input(value : @protocol.Value) -> @scheme.Value raise {
  match value {
    Integer(n) => @scheme.integer(n.to_string())
    Boolean(b) => @scheme.Boolean(b)
    Unit => @scheme.Unit
    Decimal(n, e) =>
      @scheme.Tagged("decimal", [@scheme.Text(@protocol.decimal_source(n, e))])
    Float64(bits) =>
      @scheme.Number(@scheme.Number::Real(bits.reinterpret_as_double()))
    Text(units) | Character(units) =>
      @scheme.Tagged(
        if value is Text(_) {
          "sdk-text"
        } else {
          "sdk-character"
        },
        [@scheme.Vector(units.map(n => @scheme.integer(n.to_string())))],
      )
    Sequence(items) => @scheme.list(items.map(scheme_input))
    Product(items) => @scheme.Vector(items.map(scheme_input))
    Record(fields) =>
      @scheme.Record(Map(fields.map(p => (p.0, scheme_input(p.1)))))
    Constructor(owner, tag, items) => {
      if owner == "morphir/SDK:int#int-32" {
        validate_sdk_boundary(value)
      }
      @scheme.Tagged(tag, items.map(scheme_input))
    }
    Optional(None) => @scheme.Tagged("morphir/SDK:maybe#nothing", [])
    Optional(Some(v)) =>
      @scheme.Tagged("morphir/SDK:maybe#just", [scheme_input(v)])
    Outcome(Ok(v)) => @scheme.Tagged("morphir/SDK:result#ok", [scheme_input(v)])
    Outcome(Err(v)) =>
      @scheme.Tagged("morphir/SDK:result#err", [scheme_input(v)])
    ModelError(_) => raise @protocol.Invalid("execution.model_error_argument")
  }
}

///|
fn scheme_output(
  value : @scheme.Value,
  expected : @protocol.ValueType,
  definitions : Array[@protocol.CustomType],
  depth : Int32,
) -> @protocol.Value raise {
  if depth > 64 {
    raise @protocol.Invalid("execution.value_limit")
  }
  fn child(
    v : @scheme.Value,
    t : @protocol.ValueType,
  ) -> @protocol.Value raise {
    scheme_output(v, t, definitions, depth + 1)
  }
  fn units(values : Array[@scheme.Value]) -> Array[Int32] raise {
    values.map(v => {
      guard v is Number(Integer(n)) else {
        raise @protocol.Invalid("execution.evaluator_utf16")
      }
      if n.compare_int(0) < 0 || n.compare_int(65535) > 0 {
        raise @protocol.Invalid("execution.evaluator_utf16")
      }
      n.to_int()
    })
  }
  match (value, expected) {
    (Number(Integer(n)), Int) => @protocol.Integer(n)
    (Boolean(b), Bool) => @protocol.Boolean(b)
    (Unit, Unit) => @protocol.Unit
    (Number(Real(n)), Float64) => @protocol.Float64(n.reinterpret_as_uint64())
    (Tagged("decimal", [Text(source)]), Decimal) => {
      guard @decimal.from_string(source) is Some(d) else {
        raise @protocol.Invalid("execution.evaluator_decimal")
      }
      @protocol.Decimal(d.coefficient, d.exponent)
    }
    (Text(source), Text) =>
      @protocol.Text(
        @sdk.Text::from_string(source).to_units().map(n => n.to_int()),
      )
    (Character(c), Character) =>
      @protocol.Character(
        @sdk.Character::from_char(c).to_units().map(n => n.to_int()),
      )
    (Tagged("sdk-text", [Vector(values)]), Text) =>
      @protocol.Text(units(values))
    (Tagged("sdk-character", [Vector(values)]), Character) =>
      @protocol.Character(units(values))
    (_, Sequence(t)) =>
      @protocol.Sequence(value.to_array().map(v => child(v, t)))
    (Vector(values), Product(types)) => {
      if values.length() != types.length() {
        raise @protocol.Invalid("execution.evaluator_tuple_arity")
      }
      let items = []
      for i, v in values {
        items.push(child(v, types[i]))
      }
      @protocol.Product(items)
    }
    (Record(fields), Record(types)) => {
      if fields.length() != types.length() {
        raise @protocol.Invalid("execution.evaluator_record_fields")
      }
      @protocol.Record(
        types.map(p => {
          guard fields.get(p.0) is Some(v) else {
            raise @protocol.Invalid("execution.evaluator_record_field: " + p.0)
          }
          (p.0, child(v, p.1))
        }),
      )
    }
    (Tagged(tag, values), Custom(owner)) => {
      guard definitions.filter(d => d.name == owner).get(0) is Some(definition) else {
        raise @protocol.Invalid("execution.unresolved_custom_type: " + owner)
      }
      guard definition.constructors.filter(c => c.name == tag).get(0)
        is Some(variant) else {
        raise @protocol.Invalid("execution.evaluator_constructor")
      }
      if values.length() != variant.inputs.length() {
        raise @protocol.Invalid("execution.evaluator_constructor_arity")
      }
      let items = []
      for i, v in values {
        items.push(child(v, variant.inputs[i]))
      }
      @protocol.Constructor(owner, tag, items)
    }
    (Tagged("morphir/SDK:maybe#nothing", []), Optional(_)) =>
      @protocol.Optional(None)
    (Tagged("morphir/SDK:maybe#just", [v]), Optional(t)) =>
      @protocol.Optional(Some(child(v, t)))
    (Tagged("morphir/SDK:result#ok", [v]), Outcome(ok, _)) =>
      @protocol.Outcome(Ok(child(v, ok)))
    (Tagged("morphir/SDK:result#err", [v]), Outcome(_, err)) =>
      @protocol.Outcome(Err(child(v, err)))
    _ => raise @protocol.Invalid("execution.evaluator_type: " + expected.name())
  }
}
