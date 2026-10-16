///|
/// Scheme from a rich unit: the `.scm` text with source comments and the `.symbols.10n` sidecar that carries
/// the unit's metadata unchanged (`pkgs/morphir-scheme/README.md`, "Units, sidecar and source comments").
fn scheme_unit_generation(
  unit : @data.IRUnit,
  source_path : String,
) -> Array[GeneratedFile] raise {
  let output = @backend.emit_unit(
    {
      unit_id: unit.id,
      ir: unit.distribution,
      metadata: unit.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: unit.annotations.copy(),
      provenance: unit.provenance.copy(),
    },
    source_path=Some(source_path),
  )
  [
    {
      path: unit.id + ".scm",
      content: @data.Text(output.source),
      format: "scheme",
    },
    {
      path: unit.id + @backend.SYMBOLS_SUFFIX,
      content: @data.Binary(output.symbols),
      format: "ion-binary",
    },
  ]
}
