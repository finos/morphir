///|
fn finite_run() -> Json raise {
  let requested = @generator.generate(
    {
      ..@generator.Input::new("sample", @metadata_fixtures.input()),
      metadata: [
        {
          node_id: "value:example:main#ready",
          data: @metadata_fixtures.adapter(
            "[" + @metadata_fixtures.row("ready") + "]",
          ),
        },
      ],
    },
    metadata_capabilities=@metadata_fixtures.capabilities(),
  )
  let naming = @generator.generate(
    @generator.Input::new("naming", @fixtures.naming_library()),
  )
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let historical = @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("historical"), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("main"),
          {
            access: @ir.Access::Public,
            value: {
              types: Map([]),
              doc: None,
              values: Map::from_array([
                (
                  @ir.Name::parse("answer"),
                  @fixtures.definition(
                    int,
                    @ir.Value::Literal(
                      { ..@fixtures.attrs(), inferred_type: Some(int), },
                      @ir.Literal::IntegerLiteral("42"),
                    ),
                  ),
                ),
              ]),
            },
          },
        ),
      ]),
    }),
  )
  let result = @generator.generate(
    @generator.Input::new(
      "pricing-acceptance",
      @ir_json.read(@ir_json.write(@fixtures.acceptance_library())),
    ),
  )
  Json::object(
    Map::from_array([
      ("requestedModule", Json::string(requested.project.module_name)),
      (
        "requestedArtifacts",
        Json::array(
          requested.artifacts.map(a => {
            (
              {
                "path": a.path,
                "content": match a.content {
                  Text(t) => Json::string(t)
                  Binary(b) =>
                    Json::array(
                      b
                      .to_array()
                      .map(n => Json::number(n.to_int().to_double())),
                    )
                },
              } : Json)
          }),
        ),
      ),
      ("moduleName", Json::string(result.project.module_name)),
      ("namingModule", Json::string(naming.project.module_name)),
      (
        "namingSymbols",
        Json::array(
          naming.symbols.map(s => {
            ({ "fqname": s.fqname, "name": s.generated_name } : Json)
          }),
        ),
      ),
      (
        "namingArtifacts",
        Json::array(
          naming.artifacts.map(a => {
            (
              {
                "path": a.path,
                "content": match a.content {
                  Text(t) => Json::string(t)
                  Binary(b) =>
                    Json::array(
                      b
                      .to_array()
                      .map(n => Json::number(n.to_int().to_double())),
                    )
                },
              } : Json)
          }),
        ),
      ),
      (
        "invocationSuite",
        Json::array(
          @execution.Suite::from_json({
            "profile": "morphir-invocations-v1",
            "calls": [
              {
                "id": "subtract",
                "entry": "calls:main#subtract",
                "arguments": [
                  { "type": "int", "value": "9007199254741035" },
                  { "type": "int", "value": "9007199254740993" },
                ],
              },
            ],
          })
          .encode("ion-binary")
          .to_array()
          .map(b => Json::number(b.to_int().to_double())),
        ),
      ),
      (
        "invocationSuite2",
        Json::array(
          @execution.Suite::from_json({
            "profile": "morphir-invocations-v1",
            "calls": [
              {
                "id": "subtract",
                "entry": "calls:main#subtract",
                "arguments": [
                  { "type": "int", "value": "45" },
                  { "type": "int", "value": "3" },
                ],
              },
            ],
          })
          .encode("ion-binary")
          .to_array()
          .map(b => Json::number(b.to_int().to_double())),
        ),
      ),
      ("pricingIR", Json::string(@ir_json.write(@fixtures.pricing()))),
      ("conformanceIR", Json::string(@ir_json.write(@fixtures.conformance()))),
      (
        "rustConformanceIR",
        Json::string(@ir_json.write(@fixtures.rust_conformance())),
      ),
      (
        "rustClassicIR",
        Json::string(
          @versioned_json.write(
            @migration.migrate(
              @versioned.V4(@fixtures.rust_conformance()),
              @version.FormatVersion::baseline(3U),
            ),
          ),
        ),
      ),
      (
        "invocationIR",
        Json::string(@ir_json.write(@fixtures.invocation_library())),
      ),
      (
        "historicalSources",
        Json::array(
          [1U, 2U, 3U].map(major => {
            Json::string(
              @versioned_json.write(
                @migration.migrate(
                  @versioned.V4(historical),
                  @version.FormatVersion::baseline(major),
                ),
              ),
            )
          }),
        ),
      ),
      ("sourceIR", Json::string(@ir_json.write(@fixtures.acceptance_library()))),
      (
        "symbols",
        Json::array(
          result.symbols.map(symbol => {
            Json::object(
              Map::from_array([
                ("fqname", Json::string(symbol.fqname)),
                ("name", Json::string(symbol.generated_name)),
                ("public", Json::boolean(symbol.public)),
              ]),
            )
          }),
        ),
      ),
      (
        "artifacts",
        Json::array(
          result.artifacts.map(artifact => {
            Json::object(
              Map::from_array([
                ("path", Json::string(artifact.path)),
                (
                  "content",
                  match artifact.content {
                    Text(text) => Json::string(text)
                    Binary(bytes) =>
                      Json::array(
                        bytes
                        .to_array()
                        .map(byte => Json::number(byte.to_int().to_double())),
                      )
                  },
                ),
              ]),
            )
          }),
        ),
      ),
    ]),
  )
}
