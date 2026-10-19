//! Independent exact source-schema branch controls. These do not execute UI.
use super::*;
use crate::json::strict::StrictReadError;

fn owner() -> Decoder {
    Decoder::new(DecodeLimits::new(1_048_576, 16_777_216, 100_000, 16_777_216, 100_000).unwrap())
}

#[test]
fn basic_and_controller_fixture_branches_keep_distinct_presence() {
    let basic = owner()
        .decode::<input::ClientFixture>(include_str!("fixture_controls/basic.fixture.json"))
        .unwrap();
    assert!(matches!(basic.mode, input::ClientFixtureMode::Basic));
    let runtime = owner()
        .decode::<input::ClientFixture>(include_str!("fixture_controls/runtime.fixture.json"))
        .unwrap();
    assert!(matches!(
        runtime.mode,
        input::ClientFixtureMode::Runtime { .. }
    ));
    let controller = owner()
        .decode::<input::ClientFixture>(include_str!("fixture_controls/controller.fixture.json"))
        .unwrap();
    assert!(matches!(
        controller.mode,
        input::ClientFixtureMode::IdentityController { .. }
    ));
}

#[test]
fn fixture_alternatives_are_disjoint_and_controller_fields_remain_closed() {
    for raw in [
        include_str!("fixture_controls/runtime-and-controller.fixture.json"),
        include_str!("fixture_controls/runtime-and-controller-valid-runtime.fixture.json"),
        include_str!("fixture_controls/null-controller.fixture.json"),
        include_str!("fixture_controls/extra-field.fixture.json"),
        include_str!("fixture_controls/missing-watch.fixture.json"),
        include_str!("fixture_controls/empty-providers.fixture.json"),
        include_str!("fixture_controls/wrong-kind.fixture.json"),
    ] {
        let result = owner().decode::<input::ClientFixture>(raw);
        if let Err(
            DecodeError::Limits
            | DecodeError::SavedBytes
            | DecodeError::Allocation
            | DecodeError::Work(_)
            | DecodeError::Literal(StrictReadError::Limits | StrictReadError::Work(_)),
        ) = &result
        {
            panic!("resource refusal cannot substitute for invalid source shape: {result:?}");
        }
        assert!(result.is_err());
    }
}

#[test]
fn controller_replies_spend_existing_static_roles_before_each_destination() {
    use super::expansion::{
        ExpansionError, ExpansionLimits, ExpansionOwner, ExpansionResource, ScenarioExpansion,
    };
    // Independent UTF8 lengths [269, 536, 269, 536], frozen before execution.
    let scenario = owner()
        .decode::<input::Scenario>(include_str!("fixture_controls/controller.scenario.json"))
        .unwrap();
    let mut exact = ExpansionOwner::new(ExpansionLimits::new(1610, 0, 1610, 0, 15));
    let measured = ScenarioExpansion::measure(&scenario, &mut exact).unwrap();
    assert_eq!(
        measured.usage().amount(ExpansionResource::RecipeBytes),
        1610
    );
    assert_eq!(
        measured
            .usage()
            .amount(ExpansionResource::LiteralStorageBytes),
        1610
    );
    assert_eq!(measured.usage().amount(ExpansionResource::FrameBytes), 0);
    assert_eq!(measured.usage().amount(ExpansionResource::Entries), 0);
    assert_eq!(measured.usage().amount(ExpansionResource::Visits), 15);
    for (recipe, storage, resource) in [
        (1609, 1610, ExpansionResource::RecipeBytes),
        (1610, 1609, ExpansionResource::LiteralStorageBytes),
    ] {
        let mut owner = ExpansionOwner::new(ExpansionLimits::new(recipe, 0, storage, 0, 15));
        assert_eq!(
            ScenarioExpansion::measure(&scenario, &mut owner).err(),
            Some(ExpansionError::Resource(resource)),
        );
        assert_eq!(owner.usage().amount(resource), 1074);
        let before = owner.usage();
        assert_eq!(
            ScenarioExpansion::measure(&scenario, &mut owner).err(),
            Some(ExpansionError::Resource(resource)),
        );
        assert_eq!(owner.usage(), before);
    }
}
