///|
// This fixture goes through the production generator. It includes public and
// private modules, a cross-module reference and an actual external SDK call.
fn main raise {
  let file = @fixtures.library()
  guard file.distribution is Library(name, dependencies, definition) else {
    abort("Expected library")
  }
  let integer = @fixtures.scalar("morphir/SDK:basics#int")
  let modules = definition.modules.copy()
  let scalar_module = modules[@ir.Path::parse("scalars")]
  let scalar_values = Map::from_array([
    (
      @ir.Name::parse("huge"),
      @fixtures.definition(
        integer,
        @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("40")),
      ),
    ),
    (
      @ir.Name::parse("enabled"),
      scalar_module.value.values[@ir.Name::parse("enabled")],
    ),
  ])
  modules[@ir.Path::parse("scalars")] = {
    ..scalar_module,
    value: { ..scalar_module.value, values: scalar_values, },
  }
  let other = modules[@ir.Path::parse("other")]
  let values = other.value.values.copy()
  let attrs = @ir.TypeAttributes::default()
  let signature = @ir.Type::Function(
    attrs,
    integer,
    @ir.Type::Function(attrs, integer, integer),
  )
  let add = @ir.Value::Reference(
    { ..@fixtures.attrs(), inferred_type: Some(signature), },
    @ir.FQName::parse("morphir/SDK:basics#add"),
  )
  values[@ir.Name::parse("total")] = @fixtures.definition(
    integer,
    @ir.Value::Apply(
      @fixtures.attrs(),
      @ir.Value::Apply(
        @fixtures.attrs(),
        add,
        @ir.Value::Reference(
          @fixtures.attrs(),
          @ir.FQName::parse("pricing:scalars#huge"),
        ),
      ),
      @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("2")),
    ),
  )
  modules[@ir.Path::parse("other")] = {
    ..other,
    value: { ..other.value, values, },
  }
  let model = @ir.IRFile::new(
    @ir.Distribution::Library(name, dependencies, { modules, }),
  )
  let generated = @generator.generate(@generator.Input::new("assembly", model))
  // IRUnit is the existing codec adapter, not a new pipeline domain type.
  let model_bytes = match
    @data.Registry::new().encode(
      "ion-binary",
      @data.IRUnit::new("assembly", model),
    ) {
    Binary(bytes) => bytes
    Text(_) => abort("Expected binary Ion model")
  }
  println(
    (
      {
        "package": generated.project.module_name,
        "modules": modules.length(),
        "modelIon": model_bytes.to_array().map(b => b.to_int()),
        "symbols": generated.symbols.map(s => {
          ({ "fqname": s.fqname, "name": s.generated_name } : Json)
        }),
        "artifacts": generated.artifacts.map(a => {
          (
            {
              "path": a.path,
              "content": match a.content {
                Text(s) => Json::string(s)
                Binary(b) =>
                  Json::array(
                    b.to_array().map(b => Json::number(b.to_int().to_double())),
                  )
              },
            } : Json)
        }),
      } : Json).stringify(),
  )
}
