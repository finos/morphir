//! Source-first new private logical-budget operation. No allocator/RSS bound.
use super::super::decode::{DecodeLimits, OperandResource};
use super::*;
#[test]
fn reviewed_inventory_metadata_budget_refuses_low_slots_before_core() {
    let raw = include_str!("pipeline/installed_client_tests/factual_controls/unit-data.json");
    let mut preparation = Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    );
    let document = preparation.literal_with_raw(raw).unwrap().0;
    let actual = InstalledClientMeasurements::decode(&document, &mut preparation).unwrap();
    let facts = actual.protocol.as_ref().unwrap();
    let ready = actual
        .frames
        .iter()
        .find(|frame| frame.event == 16)
        .unwrap()
        .document
        .as_ref()
        .unwrap();
    let page = actual
        .frames
        .iter()
        .find(|frame| frame.event == 19)
        .unwrap()
        .document
        .as_ref()
        .unwrap();
    let mut phase =
        Decoder::new(DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1).unwrap());
    // Actual2 roots alone need2 namespace rows, before entries/prefixes/clone.
    assert!(matches!(
        charge_inventory_metadata(&facts.capture, ready, std::iter::once(page), &mut phase),
        Err(DecodeError::Work(OperandResource::Slots))
    ));
    let before = phase.usage();
    assert!(matches!(
        charge_inventory_metadata(&facts.capture, ready, std::iter::once(page), &mut phase),
        Err(DecodeError::Work(OperandResource::Slots))
    ));
    assert_eq!(phase.usage(), before);
}
