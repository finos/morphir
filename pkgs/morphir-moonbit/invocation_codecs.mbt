///|
fn boundary_type(t : Lowered) -> @execution.ValueType? {
  fn required(t : Lowered) -> @execution.ValueType raise {
    guard boundary_type(t) is Some(result) else {
      raise Failure("boundary function")
    }
    result
  }
  Some(
    match t {
      Atom(SignedInt32) => @execution.Custom("morphir/SDK:int#int-32")
      Atom(BoundedInteger(name)) => @execution.Custom("morphir/SDK:int#" + name)
      Atom(Integer) => @execution.Int
      Atom(Boolean) => @execution.Bool
      Atom(Unit) => @execution.Unit
      Atom(Decimal) => @execution.Decimal
      Atom(Float) | Atom(Float32) => @execution.Float64
      Atom(Text) => @execution.Text
      Atom(Character) => @execution.Character
      Product(items) => @execution.Product(items.map(required))
      Shape(_, fields) =>
        @execution.Record(fields.map(p => (p.0.to_canonical(), required(p.1))))
      Sequence(item) => @execution.Sequence(required(item))
      Optional(item) => @execution.Optional(required(item))
      Outcome(ok, err) => @execution.Outcome(required(ok), required(err))
      Nominal(name) => @execution.Custom(name.to_canonical())
      Arrow(_, _) => raise Failure("boundary function")
    },
  ) catch {
    _ => None
  }
}

///|
fn decoder(t : Lowered) -> String {
  "decode_" + hex(lower_key(t))
}

///|
fn encoder(t : Lowered) -> String {
  "encode_" + hex(lower_key(t))
}

///|
fn boundary_moon_type(ctx : Lowering, t : Lowered) -> String {
  match t {
    Shape(name, _) => "@model." + name
    Nominal(name) => "@model." + ctx.names.names["type:" + name.to_canonical()]
    Product(items) =>
      "(" + items.map(t => boundary_moon_type(ctx, t)).join(", ") + ")"
    Sequence(item) => "@list.List[" + boundary_moon_type(ctx, item) + "]"
    Optional(item) => "Option[" + boundary_moon_type(ctx, item) + "]"
    Outcome(ok, err) =>
      "Result[" +
      boundary_moon_type(ctx, ok) +
      ", " +
      boundary_moon_type(ctx, err) +
      "]"
    _ => type_source(ctx, t)
  }
}

///|
fn invocation_codecs(
  ctx : Lowering,
  entries : Array[InvocationEntry],
) -> (String, Array[@execution.CustomType]) raise {
  let visited = Map([])
  let source = []
  let definitions = []
  let invalid = "raise @execution.Invalid(\"execution.wrong_type\")"
  fn emit(t : Lowered) -> Unit raise {
    let key = lower_key(t)
    if visited.contains(key) {
      return
    }
    visited[key] = true
    let (decode, encode) = match t {
      Atom(SignedInt32) => {
        definitions.push(@execution.CustomType::{
          name: "morphir/SDK:int#int-32",
          constructors: [
            { name: "morphir/SDK:int#int32", inputs: [@execution.Int], },
          ],
        })
        (
          "match v { Constructor(\"morphir/SDK:int#int-32\", \"morphir/SDK:int#int32\", [Integer(n)]) => { guard @int.to_int32(@integer.from_bigint(n)) is Some(value) else { raise @execution.Invalid(\"execution.int32_range\") }; value }; _ => " +
          invalid +
          " }",
          "@execution.Constructor(\"morphir/SDK:int#int-32\", \"morphir/SDK:int#int32\", [@execution.Integer(@integer.to_bigint(@int.from_int32(v)))])",
        )
      }
      Atom(BoundedInteger(name)) => {
        let compact = name.replace(old="-", new="")
        let tag = "morphir/SDK:int#" +
          (if name.has_prefix("int-") { compact } else { name })
        let owner = "morphir/SDK:int#" + name
        let function = if name == "byte" { "byte" } else { compact }
        definitions.push(@execution.CustomType::{
          name: owner,
          constructors: [{ name: tag, inputs: [@execution.Int], }],
        })
        (
          "match v { Constructor(" +
          quote(owner) +
          ", " +
          quote(tag) +
          ", [Integer(n)]) => { guard @int.to_" +
          function +
          "(@integer.from_bigint(n)) is Some(value) else { raise @execution.Invalid(\"execution." +
          compact +
          "_range\") }; value }; _ => " +
          invalid +
          " }",
          "@execution.Constructor(" +
          quote(owner) +
          ", " +
          quote(tag) +
          ", [@execution.Integer(@integer.to_bigint(@int.from_" +
          function +
          "(v)))])",
        )
      }
      Atom(Integer) =>
        (
          "match v { Integer(n) => @integer.from_bigint(n); _ => " +
          invalid +
          " }",
          "@execution.Integer(@integer.to_bigint(v))",
        )
      Atom(Boolean) =>
        (
          "match v { Boolean(b) => b; _ => " + invalid + " }",
          "@execution.Boolean(v)",
        )
      Atom(Unit) =>
        ("match v { Unit => (); _ => " + invalid + " }", "@execution.Unit")
      Atom(Float) =>
        (
          "match v { Float64(bits) => bits.reinterpret_as_double(); _ => " +
          invalid +
          " }",
          "@execution.Float64(v.reinterpret_as_uint64())",
        )
      Atom(Float32) => {
        ctx.imports["source_float"] = true
        (
          "match v { Float64(bits) => @source_float.round32(bits.reinterpret_as_double()); _ => " +
          invalid +
          " }",
          "@execution.Float64(@source_float.round32(v).reinterpret_as_uint64())",
        )
      }
      Atom(Decimal) =>
        (
          "match v { Decimal(n, e) => { let (n, e) = @execution.normalize_decimal(n,e); guard @decimal.from_string(@execution.decimal_source(n,e)) is Some(d) else { " +
          invalid +
          " }; if d.coefficient != n || d.exponent != e { raise @execution.Invalid(\"execution.decimal_precision\") }; d }; _ => " +
          invalid +
          " }",
          "@execution.Decimal(v.coefficient, v.exponent)",
        )
      Atom(Text) =>
        (
          "match v { Text(units) => @sdk.Text::from_units(units.map(n => n.to_uint16())); _ => " +
          invalid +
          " }",
          "@execution.Text(v.to_units().map(n => n.to_int()))",
        )
      Atom(Character) =>
        (
          "match v { Character(units) => @sdk.Character::from_units(units.map(n => n.to_uint16())); _ => " +
          invalid +
          " }",
          "@execution.Character(v.to_units().map(n => n.to_int()))",
        )
      Sequence(item) => {
        emit(item)
        (
          "match v { Sequence(items) => @list.from_array(items.map(" +
          decoder(item) +
          ")); _ => " +
          invalid +
          " }",
          "@execution.Sequence(@list.to_array(v).map(" + encoder(item) + "))",
        )
      }
      Optional(item) => {
        emit(item)
        (
          "match v { Optional(item) => item.map(" +
          decoder(item) +
          "); _ => " +
          invalid +
          " }",
          "@execution.Optional(v.map(" + encoder(item) + "))",
        )
      }
      Outcome(ok, err) => {
        emit(ok)
        emit(err)
        (
          "match v { Outcome(Ok(item)) => Ok(" +
          decoder(ok) +
          "(item)); Outcome(Err(item)) => Err(" +
          decoder(err) +
          "(item)); _ => " +
          invalid +
          " }",
          "@execution.Outcome(match v { Ok(item) => Ok(" +
          encoder(ok) +
          "(item)); Err(item) => Err(" +
          encoder(err) +
          "(item)) })",
        )
      }
      Product(items) => {
        for item in items {
          emit(item)
        }
        let inputs = []
        let outputs = []
        for i, item in items {
          inputs.push(decoder(item) + "(items[" + i.to_string() + "])")
          outputs.push(encoder(item) + "(v." + i.to_string() + ")")
        }
        (
          "match v { Product(items) => { if items.length() != " +
          items.length().to_string() +
          " { " +
          invalid +
          " }; (" +
          inputs.join(", ") +
          ") }; _ => " +
          invalid +
          " }",
          "@execution.Product([" + outputs.join(", ") + "])",
        )
      }
      Shape(name, fields) => {
        let inputs = []
        let outputs = []
        for (field, item) in fields {
          emit(item)
          inputs.push(
            field_name(ctx, name, field) +
            ": " +
            decoder(item) +
            "(record_field(items, " +
            quote(field.to_canonical()) +
            "))",
          )
          outputs.push(
            "(" +
            quote(field.to_canonical()) +
            ", " +
            encoder(item) +
            "(v." +
            field_name(ctx, name, field) +
            "))",
          )
        }
        (
          "match v { Record(items) => { if items.length() != " +
          fields.length().to_string() +
          " { " +
          invalid +
          " }; @model." +
          name +
          "::{" +
          inputs.join(", ") +
          ",} }; _ => " +
          invalid +
          " }",
          "@execution.Record([" + outputs.join(", ") + "])",
        )
      }
      Nominal(name) => {
        let constructors = ctx.constructors
          .keys()
          .collect()
          .filter(n => ctx.constructors[n].output == t)
        constructors.sort_by(fn(a, b) {
          a.to_canonical().compare(b.to_canonical())
        })
        let inputs = []
        let outputs = []
        let shapes = []
        for ctor in constructors {
          let entry = ctx.constructors[ctor]
          if !entry.public {
            raise Invalid(
              "moonbit.inaccessible_constructor",
              name.to_canonical(),
              "Invocation requires public constructors",
            )
          }
          let arguments = []
          let patterns = []
          let values = []
          for i, item in entry.inputs {
            emit(item)
            arguments.push(decoder(item) + "(items[" + i.to_string() + "])")
            patterns.push("x" + i.to_string())
            values.push(encoder(item) + "(x" + i.to_string() + ")")
          }
          let generated = "@model." +
            ctx.names.names["constructor:" + ctor.to_canonical()]
          inputs.push(
            quote(ctor.to_canonical()) +
            " => { if items.length() != " +
            entry.inputs.length().to_string() +
            " { " +
            invalid +
            " }; " +
            generated +
            (if arguments.is_empty() {
              ""
            } else {
              "(" + arguments.join(", ") + ")"
            }) +
            " }",
          )
          outputs.push(
            generated +
            (if patterns.is_empty() {
              ""
            } else {
              "(" + patterns.join(", ") + ")"
            }) +
            " => @execution.Constructor(" +
            quote(name.to_canonical()) +
            ", " +
            quote(ctor.to_canonical()) +
            ", [" +
            values.join(", ") +
            "])",
          )
          shapes.push(@execution.ConstructorType::{
            name: ctor.to_canonical(),
            inputs: entry.inputs.map(item => boundary_type(item).unwrap()),
          })
        }
        definitions.push(@execution.CustomType::{
          name: name.to_canonical(),
          constructors: shapes,
        })
        (
          "match v { Constructor(owner, tag, items) => { if owner != " +
          quote(name.to_canonical()) +
          " { " +
          invalid +
          " }; match tag { " +
          inputs.join("; ") +
          "; _ => " +
          invalid +
          " } }; _ => " +
          invalid +
          " }",
          "match v { " + outputs.join("; ") + " }",
        )
      }
      Arrow(_, _) =>
        raise Invalid(
          "moonbit.boundary_function", key, "Functions cannot cross the invocation boundary",
        )
    }
    let moon_type = boundary_moon_type(ctx, t)
    source.push(
      "///|\nfn " +
      decoder(t) +
      "(v : @execution.Value) -> " +
      moon_type +
      " raise { " +
      decode +
      " }\n///|\nfn " +
      encoder(t) +
      "(v : " +
      moon_type +
      ") -> @execution.Value { " +
      encode +
      " }\n",
    )
  }
  for entry in entries {
    let d = ctx.values[@ir.FQName::parse(entry.fqname)]
    for (_, t) in d.inputs {
      emit(t)
    }
    emit(d.output)
  }
  definitions.sort_by(fn(a, b) { a.name.compare(b.name) })
  (source.join("\n"), definitions)
}

///|
fn boundary_supported(
  ctx : Lowering,
  t : Lowered,
  seen : Map[String, Bool],
) -> Bool {
  let key = lower_key(t)
  if seen.contains(key) {
    return true
  }
  seen[key] = true
  match t {
    Arrow(_, _) => false
    Atom(_) => true
    Product(items) => items.all(t => boundary_supported(ctx, t, seen))
    Shape(_, fields) => fields.all(p => boundary_supported(ctx, p.1, seen))
    Sequence(t) | Optional(t) => boundary_supported(ctx, t, seen)
    Outcome(ok, err) =>
      boundary_supported(ctx, ok, seen) && boundary_supported(ctx, err, seen)
    Nominal(_) =>
      ctx.constructors
      .values()
      .all(c => {
        c.output != t ||
        (c.public && c.inputs.all(t => boundary_supported(ctx, t, seen)))
      })
  }
}
