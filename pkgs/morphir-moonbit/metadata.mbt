///|
fn record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::new(
    @ion.Struct(fields.map(pair => @ion.Field::new(pair.0, pair.1))),
  )
}

///|
fn ion_text(text : String) -> @ion.IonValue {
  @ion.IonValue::new(@ion.String(text))
}

///|
fn texts(items : Array[String]) -> @ion.IonValue {
  @ion.IonValue::new(@ion.List(items.map(ion_text)))
}

///|
fn symbol_metadata(
  input : Input,
  source_ir : String,
  symbols : Array[Symbol],
  owned : Map[String, Bool],
  names : TargetNames,
) -> Bytes raise {
  let metadata = input.metadata.copy()
  metadata.sort_by(fn(a, b) { a.node_id.compare(b.node_id) })
  let seen = Map([])
  for entry in metadata {
    if !owned.contains(entry.node_id) || seen.contains(entry.node_id) {
      raise Invalid(
        "moonbit.metadata_identity",
        entry.node_id,
        "Unknown or duplicate source node identity",
      )
    }
    seen[entry.node_id] = true
  }
  let value = record([
    ("profile", ion_text("morphir-moonbit-symbols-2026-10-17")),
    (
      "naming_policy",
      ion_text(
        if names.style == Readable {
          NAMING_POLICY
        } else {
          "moonbit-legacy-hex-v1"
        },
      ),
    ),
    ("warnings", @ion.IonValue::list(names.warnings.map(w => w.to_ion()))),
    (
      "naming_allocations",
      @ion.IonValue::list(
        names.allocations.map(a => {
          record([
            ("owner", ion_text(a.owner)),
            ("role", ion_text(a.role)),
            (
              "original",
              a.original
              .map(ion_text)
              .unwrap_or(@ion.IonValue::new(@ion.Null(@ion.Null))),
            ),
            (
              "requested",
              a.requested
              .map(ion_text)
              .unwrap_or(@ion.IonValue::new(@ion.Null(@ion.Null))),
            ),
            ("candidate", ion_text(a.candidate)),
            ("allocated", ion_text(a.allocated)),
            ("reason", ion_text(a.reason)),
          ])
        }),
      ),
    ),
    ("unvalidated_predicates", texts(names.facts.unvalidated_predicates)),
    (
      "consumed_naming_facts",
      @ion.IonValue::list(
        names.facts.facts.map(f => {
          record([
            ("owner", ion_text(f.owner)),
            ("provider_revision", ion_text(f.provider_revision)),
            (
              "assertions",
              @ion.IonValue::list(
                f.assertions.map(a => {
                  record([
                    ("holder", ion_text(a.holder)),
                    ("document", ion_text(a.document)),
                    ("carrier", ion_text(a.carrier)),
                    ("subject", ion_text(a.subject)),
                    ("predicate", ion_text(a.predicate)),
                    ("property", ion_text(a.property)),
                    ("ordinal", @ion.IonValue::int(a.ordinal)),
                    ("object_ordinal", @ion.IonValue::int(a.object_ordinal)),
                  ])
                }),
              ),
            ),
          ])
        }),
      ),
    ),
    ("source_provenance", @ion.IonValue::list(input.provenance)),
    ("unit_id", ion_text(input.unit_id)),
    ("source_ir_json", ion_text(source_ir)),
    (
      "source_annotations",
      @ion.IonValue::new(
        @ion.List(
          input.annotations.map(token => @ion.IonValue::new(@ion.Symbol(token))),
        ),
      ),
    ),
    (
      "metadata",
      @ion.IonValue::new(
        @ion.List(
          metadata.map(entry => {
            record([("node_id", ion_text(entry.node_id)), ("data", entry.data)])
          }),
        ),
      ),
    ),
    (
      "symbols",
      @ion.IonValue::new(
        @ion.List(
          symbols.map(symbol => {
            record([
              ("fqname", ion_text(symbol.fqname)),
              ("generated_name", ion_text(symbol.generated_name)),
              ("public", @ion.IonValue::new(@ion.Bool(symbol.public))),
              ("source_node", ion_text(symbol.source_node)),
              ("generated_node", ion_text(symbol.generated_node)),
              ("origins", texts(symbol.origins)),
            ])
          }),
        ),
      ),
    ),
  ]).with_annotation(@ion.SymbolToken::new("morphir_moonbit_symbols"))
  @ion_binary.write_binary_value(value)
}
