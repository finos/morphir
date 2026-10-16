///|
fn record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::new(
    @ion.Struct(fields.map(pair => @ion.Field::new(pair.0, pair.1))),
  )
}

///|
fn texts(items : Array[String]) -> @ion.IonValue {
  @ion.IonValue::list(items.map(@ion.IonValue::string))
}

///|
/// The symbols sidecar: the unit's annotations, provenance and metadata unchanged, the owned node ids, and one
/// record per emitted define. Scheme names are canonical, so `generated_name` equals `fqname`. The bytes are a
/// pure function of the unit and the emission order.
fn symbol_metadata(unit : Input, symbols : Array[Symbol]) -> Bytes raise {
  let source_nodes = @identities.nodes(unit.unit_id, unit.ir)
  let owned : Map[String, Bool] = Map([])
  for node in source_nodes {
    owned[node] = true
  }
  let value = record([
    ("profile", @ion.IonValue::string(SYMBOLS_PROFILE)),
    ("naming_policy", @ion.IonValue::string("scheme-canonical-identity-v1")),
    ("unit_id", @ion.IonValue::string(unit.unit_id)),
    (
      "source_annotations",
      @ion.IonValue::list(
        unit.annotations.map(token => @ion.IonValue::new(@ion.Symbol(token))),
      ),
    ),
    ("source_provenance", @ion.IonValue::list(unit.provenance)),
    ("source_nodes", texts(source_nodes)),
    (
      "metadata",
      @ion.IonValue::list(
        unit.metadata.map(entry => {
          record([
            ("node_id", @ion.IonValue::string(entry.node_id)),
            ("data", entry.data),
          ])
        }),
      ),
    ),
    (
      "symbols",
      @ion.IonValue::list(
        symbols.map(symbol => {
          let source_node = "value:" + symbol.fqname
          record([
            ("fqname", @ion.IonValue::string(symbol.fqname)),
            ("generated_name", @ion.IonValue::string(symbol.fqname)),
            ("scheme_symbol", @ion.IonValue::string(symbol.scheme_symbol)),
            ("public", @ion.IonValue::bool(symbol.public)),
            ("source_node", @ion.IonValue::string(source_node)),
            (
              "generated_node",
              @ion.IonValue::string("scheme:define:" + symbol.fqname),
            ),
            // Only owned nodes: a native or external value has no `/body`, and an application's declarations
            // have no owned identity.
            (
              "origins",
              texts(
                [source_node, source_node + "/body"].filter(node => {
                  owned.contains(node)
                }),
              ),
            ),
          ])
        }),
      ),
    ),
  ]).with_annotation(@ion.SymbolToken::new("morphir_scheme_symbols"))
  @ion_binary.write_binary_value(value)
}
