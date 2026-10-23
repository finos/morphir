use super::super::{DecodeLimits, Decoder};
use super::*;
use serde_json::{Value, json};

fn scenario(runs: Value) -> input::Scenario {
    let mut raw: Value = serde_json::from_str(include_str!("../pairing/input.json")).unwrap();
    raw["runs"] = runs;
    Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    )
    .decode(&raw.to_string())
    .unwrap()
}
fn client(files: Value, peers: Value, actions: Value) -> Value {
    json!({"role":"model-originals-client", "fixture":{"files":files,"literalPeers":peers},"actions":actions})
}
fn policy() -> ExpansionLimits {
    ExpansionLimits::new(1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000)
}

#[test]
fn whole_scenario_reserves_every_static_recipe_before_materialization() {
    let value = scenario(json!([
        client(
            json!([{"alias":"A","bytes":{"kind":"concat","parts":[{"kind":"hex","hex":"00ff"},{"kind":"utf8","text":"λ"},{"kind":"repeat-u8","byte":3,"length":7}]}}]),
            json!([{"alias":"P","frames":[{"kind":"segments","parts":[{"kind":"literal","text":"é"},{"kind":"repeat","text":"x","count":3}]}],"requests":[{"kind":"literal","text":"req"}]}]),
            json!([{"kind":"checkpoint","name":"First"}])
        ),
        client(
            json!([{"alias":"B","bytes":{"kind":"cycle-u8","seed":2,"length":5}}]),
            json!([]),
            json!([{"kind":"deliver","effect":{"attempt":"A","kind":"capture","ordinal":0},"reply":{"kind":"bytes","value":{"kind":"chunk-indexed-u8","seed":1,"length":4}}}])
        )
    ]));
    let mut owner = ExpansionOwner::new(policy());
    let measured = ScenarioExpansion::measure(&value, &mut owner).unwrap();
    assert_eq!(measured.usage().amount(ExpansionResource::RecipeBytes), 28);
    assert_eq!(measured.usage().amount(ExpansionResource::FrameBytes), 8);
    assert_eq!(
        measured
            .usage()
            .amount(ExpansionResource::LiteralStorageBytes),
        12
    );
    assert_eq!(measured.usage().amount(ExpansionResource::Entries), 2);
    assert!(measured.scenario().same_owner((&value).into()));
}

#[test]
fn late_second_run_failure_is_sticky_and_does_not_reset_on_retry() {
    let value = scenario(json!([
        client(
            json!([{"alias":"A","bytes":{"kind":"utf8","text":"first"}}]),
            json!([]),
            json!([{"kind":"checkpoint","name":"A"}])
        ),
        client(
            json!([]),
            json!([{"alias":"P","frames":[{"kind":"segments","parts":[{"kind":"repeat","text":"X","count":100}]}]}]),
            json!([{"kind":"checkpoint","name":"B"}])
        )
    ]));
    let mut owner = ExpansionOwner::new(ExpansionLimits::new(104, 1000, 1000, 1000, 1000));
    let factories = fixture_bytes::literal_factories();
    assert!(matches!(
        ScenarioExpansion::measure(&value, &mut owner),
        Err(ExpansionError::Resource(ExpansionResource::RecipeBytes))
    ));
    let used = owner.usage();
    assert!(matches!(
        ScenarioExpansion::measure(&value, &mut owner),
        Err(ExpansionError::Resource(ExpansionResource::RecipeBytes))
    ));
    assert_eq!(owner.usage(), used);
    assert_eq!(fixture_bytes::literal_factories(), factories);
    // Positive control exercises the real literal factory, on this test thread.
    crate::workbench::model_originals::FixtureBytes::parse(
        r#"{"kind":"utf8","text":"factory"}"#,
        crate::workbench::model_originals::FixtureByteLimits::new(4096, 1024, 32).unwrap(),
    )
    .unwrap();
    assert_eq!(fixture_bytes::literal_factories(), factories + 1);
}

#[test]
fn repeated_frames_use_checked_arithmetic_without_iterating_repeat_count() {
    let value = scenario(json!([client(
        json!([]),
        json!([{"alias":"P","frames":[{"kind":"segments","parts":[{"kind":"repeat","text":"", "count":9007199254740991u64}]}]}]),
        json!([{"kind":"checkpoint","name":"A"}])
    )]));
    let mut owner = ExpansionOwner::new(policy());
    let measured = ScenarioExpansion::measure(&value, &mut owner).unwrap();
    assert_eq!(measured.usage().amount(ExpansionResource::RecipeBytes), 0);
    assert!(measured.usage().amount(ExpansionResource::Visits) < 20);
    let mut raw: Value = serde_json::from_str(include_str!("../pairing/input.json")).unwrap();
    raw["runs"] = json!([client(
        json!([]),
        json!([{"alias":"P","frames":[{"kind":"segments","parts":[{"kind":"repeat","text":"x".repeat(16384),"count":9007199254740991u64}]}]}]),
        json!([{"kind":"checkpoint","name":"A"}])
    )]);
    let value: input::Scenario = Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    )
    .decode(&raw.to_string())
    .unwrap();
    let mut owner = ExpansionOwner::new(ExpansionLimits::new(
        u64::MAX,
        u64::MAX,
        u64::MAX,
        u64::MAX,
        u64::MAX,
    ));
    assert!(matches!(
        ScenarioExpansion::measure(&value, &mut owner),
        Err(ExpansionError::Arithmetic(ExpansionResource::RecipeBytes))
    ));
}

#[test]
fn entry_series_reserves_all_generated_entries_and_each_repeated_file_payload() {
    let value = scenario(
        json!([{"role":"model-originals-server","fixture":{"grants":[{"alias":"Root","nodes":[{"kind":"entry-series","parent":"","prefix":"f","suffix":".json","first":0,"count":3,"decimalWidth":2,"entry":{"kind":"file","bytes":{"kind":"utf8","text":"é"}}}]}],"providers":[],"guests":[],"records":[],"startup":{"cwd":"Root","outputOverride":{"kind":"none"}}},"actions":[{"kind":"checkpoint","name":"A"}]}]),
    );
    let mut owner = ExpansionOwner::new(policy());
    let measured = ScenarioExpansion::measure(&value, &mut owner).unwrap();
    assert_eq!(measured.usage().amount(ExpansionResource::Entries), 3);
    assert_eq!(measured.usage().amount(ExpansionResource::RecipeBytes), 6);
    assert_eq!(
        measured
            .usage()
            .amount(ExpansionResource::LiteralStorageBytes),
        6
    );
    let mut owner = ExpansionOwner::new(ExpansionLimits::new(100, 100, 100, 2, 100));
    assert!(matches!(
        ScenarioExpansion::measure(&value, &mut owner),
        Err(ExpansionError::Resource(ExpansionResource::Entries))
    ));
}

#[test]
fn every_run_uses_the_same_actual_read_plan_and_cumulative_explicit_limits() {
    let run = client(
        json!([{"alias":"Source","bytes":{"kind":"cycle-u8","seed":0,"length":5}}]),
        json!([]),
        json!([{
            "kind":"read-run","attempt":"Opening","effectKind":"read-original","firstOrdinal":0,"source":"Source",
            "expectedRequest":{"method":"morphir.model-originals.read","contractVersion":"0.1.0-draft.1","captureId":"C","target":{"kind":"original","entryId":"E"},"maxBytes":2},
            "window":{"firstOffset":0,"afterOffset":5,"chunkBytes":2,"rows":3},
            "replyParts":[{"kind":"literal","text":"X"},{"kind":"correlated-request-id"},{"kind":"row-offset"},{"kind":"row-next-offset"},{"kind":"base64-window"}]
        }]),
    );
    let value = scenario(json!([run.clone(), run]));
    let mut denied = ExpansionOwner::new(policy());
    assert!(matches!(
        ScenarioExpansion::measure(&value, &mut denied),
        Err(ExpansionError::Resource(ExpansionResource::ReadRows))
    ));
    let mut owner =
        ExpansionOwner::new(policy().with_reads(ReadExpansionLimits::new(6, 10, 98466, 378)));
    let plan = ScenarioExpansion::measure(&value, &mut owner).unwrap();
    assert_eq!(plan.usage().amount(ExpansionResource::ReadRows), 6);
    assert_eq!(plan.usage().amount(ExpansionResource::ReadWindowBytes), 10);
    assert_eq!(plan.usage().amount(ExpansionResource::ReadWireBytes), 98466);
    assert_eq!(
        plan.usage().amount(ExpansionResource::ReadObserverBytes),
        378
    );
    let mut owner =
        ExpansionOwner::new(policy().with_reads(ReadExpansionLimits::new(5, 10, 98466, 378)));
    assert!(matches!(
        ScenarioExpansion::measure(&value, &mut owner),
        Err(ExpansionError::Resource(ExpansionResource::ReadRows))
    ));
}
