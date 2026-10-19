///|
/// The source-width operation is a declared extension, outside the classic SDK.
pub fn source_int32_module_specification() -> @ir.ModuleSpecification raise {
  let attrs = @ir.TypeAttributes::default()
  let int = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let int32 = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:int#int-32"),
    [],
  )
  {
    types: Map([]),
    values: Map::from_array([
      (
        @ir.Name::parse("normalize"),
        @ir.Documented::{
          doc: None,
          value: @ir.ValueSpecification::{
            inputs: [(@ir.Name::parse("value"), int)],
            output: int32,
            annotations: [],
          },
        },
      ),
    ]),
    doc: None,
    annotations: [],
  }
}
