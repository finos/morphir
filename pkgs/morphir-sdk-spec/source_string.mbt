///|
/// Separate source-runtime extension; does not modify the pinned classic SDK.
pub fn source_string_package_name() -> @ir.PackageName raise {
  @ir.Path::parse("morphir/moonbit-source")
}

///|
pub fn source_string_specification() -> @ir.PackageSpecification raise {
  let attrs = @ir.TypeAttributes::default()
  let text = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:string#string"),
    [],
  )
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
  let values = Map::from_array([
    (
      @ir.Name::parse("require-valid"),
      @ir.Documented::{
        doc: None,
        value: @ir.ValueSpecification::{
          inputs: [
            (@ir.Name::parse("value"), text),
            (@ir.Name::parse("limit"), int),
          ],
          output: text,
          annotations: [],
        },
      },
    ),
    (
      @ir.Name::parse("append-bounded"),
      @ir.Documented::{
        doc: None,
        value: @ir.ValueSpecification::{
          inputs: [
            (@ir.Name::parse("left"), text),
            (@ir.Name::parse("right"), text),
            (@ir.Name::parse("limit"), int),
          ],
          output: text,
          annotations: [],
        },
      },
    ),
    (
      @ir.Name::parse("length-int32"),
      @ir.Documented::{
        doc: None,
        value: @ir.ValueSpecification::{
          inputs: [
            (@ir.Name::parse("value"), text),
            (@ir.Name::parse("limit"), int),
          ],
          output: int32,
          annotations: [],
        },
      },
    ),
    (
      @ir.Name::parse("slice-owned"),
      @ir.Documented::{
        doc: None,
        value: @ir.ValueSpecification::{
          inputs: [
            (@ir.Name::parse("value"), text),
            (@ir.Name::parse("start"), int32),
            (@ir.Name::parse("end"), int32),
            (@ir.Name::parse("limit"), int),
          ],
          output: text,
          annotations: [],
        },
      },
    ),
  ])
  {
    modules: Map::from_array([
      (
        @ir.Path::parse("string"),
        @ir.ModuleSpecification::{
          types: Map([]),
          values,
          doc: None,
          annotations: [],
        },
      ),
    ]),
  }
}
