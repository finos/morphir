///|
/// Additive MoonBit numeric SDK inventory. The pinned classic specification is
/// copied before extension so its oracle count and declarations remain stable.
pub fn numeric_sdk_specification() -> @ir.PackageSpecification raise {
  let classic = sdk_specification()
  let modules = Map::from_array(classic.modules.iter().collect())
  let int_path = @ir.Path::parse("int")
  let classic_int = modules[int_path]
  let types = Map::from_array(classic_int.types.iter().collect())
  let values = Map::from_array(classic_int.values.iter().collect())
  let attrs = @ir.TypeAttributes::default()
  let exact = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let provenance = @ir.Annotation::Compact(
    @ir.FQName::parse("morphir/moonbit-source:numeric#sdk-extension"),
    Some("morphir-sdk-moonbit-numeric-v1"),
  )
  for
    (name, source_name) in [
      ("byte", "Byte"),
      ("uint-16", "UInt16"),
      ("uint-32", "UInt32"),
      ("uint-64", "UInt64"),
    ] {
    let bounded = @ir.Type::Reference(
      attrs,
      @ir.FQName::parse("morphir/SDK:int#" + name),
      [],
    )
    types[@ir.Name::parse(name)] = @ir.Documented::{
      doc: Some(source_name + " unsigned boundary type"),
      value: @ir.TypeSpecification::{
        annotations: [provenance],
        body: @ir.TypeSpecificationBody::OpaqueTypeSpecification([]),
      },
    }
    values[@ir.Name::parse("from-" + name)] = @ir.Documented::{
      doc: Some("Exact nonnegative widening from " + source_name),
      value: @ir.ValueSpecification::{
        inputs: [(@ir.Name::parse("value"), bounded)],
        output: exact,
        annotations: [provenance],
      },
    }
    values[@ir.Name::parse("to-" + name)] = @ir.Documented::{
      doc: Some("Checked narrowing to " + source_name),
      value: @ir.ValueSpecification::{
        inputs: [(@ir.Name::parse("value"), exact)],
        output: @ir.Type::Reference(
          attrs,
          @ir.FQName::parse("morphir/SDK:maybe#maybe"),
          [bounded],
        ),
        annotations: [provenance],
      },
    }
  }
  let float64 = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#float"),
    [],
  )
  let float32 = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/moonbit-source:float32#float32"),
    [],
  )
  for
    (name, input, output, policy) in [
      ("from-float64-exact", float64, exact, "checked-exact"),
      ("from-float64-truncated", float64, exact, "truncated"),
      ("from-float64-floor", float64, exact, "floor"),
      ("from-float64-ceiling", float64, exact, "ceiling"),
      ("from-float64-rounded", float64, exact, "rounded"),
      ("from-float32-exact", float32, exact, "checked-exact"),
      ("from-float32-truncated", float32, exact, "truncated"),
      ("from-float32-floor", float32, exact, "floor"),
      ("from-float32-ceiling", float32, exact, "ceiling"),
      ("from-float32-rounded", float32, exact, "rounded"),
      ("to-float64-exact", exact, float64, "checked-exact"),
      ("to-float64-rounded", exact, float64, "rounded"),
      ("to-float32-exact", exact, float32, "checked-exact"),
      ("to-float32-rounded", exact, float32, "rounded"),
    ] {
    values[@ir.Name::parse(name)] = @ir.Documented::{
      doc: Some("MoonBit numeric conversion policy: " + policy),
      value: @ir.ValueSpecification::{
        inputs: [(@ir.Name::parse("value"), input)],
        output: if name.has_suffix("exact") || name.has_prefix("from-float") {
          @ir.Type::Reference(
            attrs,
            @ir.FQName::parse("morphir/SDK:maybe#maybe"),
            [output],
          )
        } else {
          output
        },
        annotations: [provenance],
      },
    }
  }
  modules[int_path] = @ir.ModuleSpecification::{
    types,
    values,
    doc: classic_int.doc,
    annotations: classic_int.annotations,
  }
  let decimal = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:decimal#decimal"),
    [],
  )
  let text = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:string#string"),
    [],
  )
  let checked_values = Map([])
  let checked_provenance = @ir.Annotation::Compact(
    @ir.FQName::parse("morphir/moonbit-source:numeric#sdk-extension"),
    Some("morphir-sdk-decimal-checked-v1"),
  )
  for
    (name, inputs) in [
      ("from-string-exact", [text]),
      ("divide", [decimal, decimal]),
      ("divide-with-default", [decimal, decimal, decimal]),
    ] {
    checked_values[@ir.Name::parse(name)] = @ir.Documented::{
      doc: Some(
        "Checked Decimal v1: exact construction; division truncates at -32 with distinct zero-divisor and underflow errors; fallback is opt-in",
      ),
      value: @ir.ValueSpecification::{
        inputs: inputs.mapi((i, ty) => {
          (@ir.Name::parse("arg-" + i.to_string()), ty)
        }),
        output: decimal,
        annotations: [checked_provenance],
      },
    }
  }
  modules[@ir.Path::parse("decimal-checked-v1")] = @ir.ModuleSpecification::{
    types: Map([]),
    values: checked_values,
    doc: None,
    annotations: [checked_provenance],
  }
  { modules, }
}

///|
pub fn source_integer_specification() -> @ir.PackageSpecification raise {
  let attrs = @ir.TypeAttributes::default()
  let exact = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let modules = Map([])
  modules[@ir.Path::parse("numeric")] = @ir.ModuleSpecification::{
    types: Map::from_array([
      (
        @ir.Name::parse("sdk-extension"),
        @ir.Documented::{
          doc: Some("Versioned MoonBit numeric SDK provenance marker"),
          value: @ir.TypeSpecification::{
            annotations: [],
            body: @ir.TypeSpecificationBody::OpaqueTypeSpecification([]),
          },
        },
      ),
    ]),
    values: Map([]),
    doc: None,
    annotations: [],
  }
  let boolean = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#bool"),
    [],
  )
  let integer_values = Map([])
  for
    (name, arity, boolean_result) in [
      ("add", 2, false),
      ("subtract", 2, false),
      ("multiply", 2, false),
      ("negate", 1, false),
      ("require-budget", 1, false),
      ("equal", 2, true),
      ("not-equal", 2, true),
      ("less-than", 2, true),
      ("less-than-or-equal", 2, true),
      ("greater-than", 2, true),
      ("greater-than-or-equal", 2, true),
    ] {
    integer_values[@ir.Name::parse(name)] = @ir.Documented::{
      doc: Some("Bounded exact MoonBit source integer operation"),
      value: @ir.ValueSpecification::{
        inputs: if arity == 1 {
          [(@ir.Name::parse("value"), exact)]
        } else {
          [(@ir.Name::parse("left"), exact), (@ir.Name::parse("right"), exact)]
        },
        output: if boolean_result {
          boolean
        } else {
          exact
        },
        annotations: [
          @ir.Annotation::Compact(
            @ir.FQName::parse("morphir/moonbit-source:numeric#sdk-extension"),
            Some("morphir-moonbit-source-integer-v1"),
          ),
        ],
      },
    }
  }
  modules[@ir.Path::parse("integer")] = @ir.ModuleSpecification::{
    types: Map([]),
    values: integer_values,
    doc: None,
    annotations: [],
  }
  for
    (module_name, type_name) in [
      ("int16", "int-16"),
      ("int64", "int-64"),
      ("byte", "byte"),
      ("uint16", "uint-16"),
      ("uint32", "uint-32"),
      ("uint64", "uint-64"),
    ] {
    modules[@ir.Path::parse(module_name)] = @ir.ModuleSpecification::{
      types: Map([]),
      values: Map::from_array([
        (
          @ir.Name::parse("normalize"),
          @ir.Documented::{
            doc: Some("MoonBit source-width normalization"),
            value: @ir.ValueSpecification::{
              inputs: [(@ir.Name::parse("value"), exact)],
              output: @ir.Type::Reference(
                attrs,
                @ir.FQName::parse("morphir/SDK:int#" + type_name),
                [],
              ),
              annotations: [
                @ir.Annotation::Compact(
                  @ir.FQName::parse(
                    "morphir/moonbit-source:numeric#sdk-extension",
                  ),
                  Some("morphir-moonbit-source-integer-v1"),
                ),
              ],
            },
          },
        ),
      ]),
      doc: None,
      annotations: [],
    }
  }
  { modules, }
}

///|
/// Binary32 source operations are separate from the classic Float64 SDK oracle.
pub fn source_float_specification() -> @ir.PackageSpecification raise {
  let attrs = @ir.TypeAttributes::default()
  let float32 = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/moonbit-source:float32#float32"),
    [],
  )
  let float64 = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#float"),
    [],
  )
  let boolean = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#bool"),
    [],
  )
  let provenance = @ir.Annotation::Compact(
    @ir.FQName::parse("morphir/moonbit-source:numeric#sdk-extension"),
    Some("morphir-moonbit-source-float-v1"),
  )
  let values = Map([])
  values[@ir.Name::parse("from-float64")] = @ir.Documented::{
    doc: Some("Round Float64 to source binary32"),
    value: @ir.ValueSpecification::{
      inputs: [(@ir.Name::parse("value"), float64)],
      output: float32,
      annotations: [provenance],
    },
  }
  for
    (name, arity, is_boolean) in [
      ("add", 2, false),
      ("subtract", 2, false),
      ("multiply", 2, false),
      ("divide", 2, false),
      ("negate", 1, false),
      ("round-boundary", 1, false),
      ("equal", 2, true),
      ("not-equal", 2, true),
      ("less-than", 2, true),
      ("less-than-or-equal", 2, true),
      ("greater-than", 2, true),
      ("greater-than-or-equal", 2, true),
    ] {
    values[@ir.Name::parse(name)] = @ir.Documented::{
      doc: Some("MoonBit source binary32 operation"),
      value: @ir.ValueSpecification::{
        inputs: if arity == 1 {
          [(@ir.Name::parse("value"), float32)]
        } else {
          [
            (@ir.Name::parse("left"), float32),
            (@ir.Name::parse("right"), float32),
          ]
        },
        output: if is_boolean {
          boolean
        } else {
          float32
        },
        annotations: [provenance],
      },
    }
  }
  {
    modules: Map::from_array([
      (
        @ir.Path::parse("float32"),
        @ir.ModuleSpecification::{
          types: Map::from_array([
            (
              @ir.Name::parse("float32"),
              @ir.Documented::{
                doc: Some("MoonBit source IEEE binary32"),
                value: @ir.TypeSpecification::{
                  annotations: [provenance],
                  body: @ir.TypeSpecificationBody::OpaqueTypeSpecification([]),
                },
              },
            ),
          ]),
          values,
          doc: None,
          annotations: [provenance],
        },
      ),
    ]),
  }
}
