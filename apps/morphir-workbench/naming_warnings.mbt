///|
/// Private worker projection of the shared warning contract. Parser coordinates
/// stay exact; the view converts zero-based columns for display only.
fn naming_warning(warning : @diagnostics.Warning) -> Json {
  @wire.obj([
    ("code", @wire.text(warning.code)),
    ("stage", @wire.text(warning.stage)),
    ("message", @wire.text(warning.message)),
    ("fix", @wire.text(warning.fix)),
    ("coordinateProfile", @wire.text("moonbit-parser-position-v1")),
    (
      "locations",
      Json::array(
        warning.locations.map(loc => {
          @wire.obj([
            ("owner", @wire.text(loc.owner)),
            ("original", @wire.text(loc.original)),
            ("allocated", @wire.text(loc.allocated)),
            (
              "source",
              match loc.source {
                None => Json::null()
                Some(s) =>
                  @wire.obj([
                    ("startLine", Json::number(s.start_line.to_double())),
                    ("startColumn", Json::number(s.start_column.to_double())),
                    ("endLine", Json::number(s.end_line.to_double())),
                    ("endColumn", Json::number(s.end_column.to_double())),
                  ])
              },
            ),
          ])
        }),
      ),
    ),
  ])
}

///|
fn source_warnings(provenance : Array[@ion.IonValue]) -> Json raise {
  Json::array(
    provenance.filter_map(value => {
      @diagnostics.warning_from_ion(value).map(naming_warning)
    }),
  )
}
