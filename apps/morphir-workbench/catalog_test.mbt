///|
test "the catalog lists every language the engine compiles" {
  let catalog = @pipeline.execute({ "operation": "catalog" })
  @expect.expect_all(s => {
    let ids = @wire.array(@wire.field(catalog, "frontends")).map(f => {
      @wire.string(@wire.field(f, "languageId"))
    })
    s.expect(ids, label="languages").to_equal(["elm", "moonbit", "scheme"])
    s
    .expect(catalog, label="catalog")
    .to_contain_json({
      "frontends": [
        {
          "languageId": "elm",
          "providerId": "finos/morphir-elm",
          "defaultProfile": "library",
          "profiles": [
            {
              "compileKind": "whole-project",
              "displayName": "Elm 0.19.1 project",
            },
          ],
        },
        { "languageId": "moonbit" },
        { "languageId": "scheme" },
      ],
    })
  })
}

///|
test "a provider registered in the worker engine appears in the catalog" {
  let engine = @engine.Engine::new()
  engine.register_source_provider({
    id: @ids.ProviderId::parse("test/rich"),
    languages: [
      {
        id: @ids.LanguageId::parse("rich"),
        extensions: [@ids.FileExtension::parse(".rich")],
        default_profile: @ids.ProfileId::parse("basic"),
        profiles: [
          {
            id: @ids.ProfileId::parse("basic"),
            capabilities: {
              summary: "Rich test",
              supported: [],
              excluded: [],
              max_documents: None,
              incremental: false,
              limits: Map([]),
            },
            evidence: @engine.Declared,
            dependencies: Map([]),
            compile: @engine.PerFile(fn(_, id, _) raise {
              @data.IRUnit::new(id, @fixtures.library())
            }),
            unit_limits: @data.Limits::default(),
          },
        ],
      },
    ],
  })
  let catalog = @pipeline.execute_with(engine, { "operation": "catalog" })
  // The engine also has the built-in Scheme frontend; languages() sorts `rich` before `scheme`.
  @expect.expect(catalog, label="catalog")
  .at("frontends[0]")
  .to_contain_json({
    "languageId": "rich",
    "displayName": "rich",
    "providerId": "test/rich",
    "profiles": [
      { "id": "basic", "compileKind": "each-file", "displayName": "Rich test" },
    ],
  })
}
