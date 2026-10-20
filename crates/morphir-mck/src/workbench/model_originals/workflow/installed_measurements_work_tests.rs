//! Independent source-first private phase control. Fresh explicit UNIT phase
//! owner isolates prepare_protocol; production still uses one cumulative owner.
use super::super::decode::{DecodeLimits, OperandResource};
use super::*;
#[test]
fn reviewed_protocol_field_search_spends_same_decoder_before_comparison() {
    let mut data: serde_json::Value = serde_json::from_str(include_str!(
        "pipeline/installed_client_tests/factual_controls/unit-data.json"
    ))
    .unwrap();
    // Derived cache remains exclusively actual strict-decoded raw DATA.
    data["host"]["events"][1]["event"]["payload"] =
        serde_json::json!("{\"nonmatching-protocol-key\":null}");
    let mut preparation = Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    );
    let raw = data.to_string();
    let document = preparation.literal_with_raw(&raw).unwrap().0;
    let actual = InstalledClientMeasurements::decode(&document, &mut preparation).unwrap();
    // First real key equality compares key.len()+method.len() before absent method;
    // explicit1 cannot authorize it. This is not a calibrated whole-decode cap.
    let mut phase =
        Decoder::new(DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 1, 1_000_000).unwrap());
    assert!(matches!(
        prepare_protocol(&actual.wire, &actual.frames, &mut phase),
        Err(DecodeError::Work(OperandResource::ByteVisits))
    ));
    let before = phase.usage();
    assert!(matches!(
        prepare_protocol(&actual.wire, &actual.frames, &mut phase),
        Err(DecodeError::Work(OperandResource::ByteVisits))
    ));
    assert_eq!(phase.usage(), before);
}
#[test]
fn reviewed_reparse_counts_actual_raw_whitespace_not_only_decoded_strings() {
    let mut data: serde_json::Value = serde_json::from_str(include_str!(
        "pipeline/installed_client_tests/factual_controls/unit-data.json"
    ))
    .unwrap();
    let capture = data["host"]["events"][14]["event"]["payload"]
        .as_str()
        .unwrap()
        .to_owned();
    // One existing request reparse, later Ready is deliberately unavailable.
    //8192 real whitespace bytes alone exceed8191 before its core parse, while
    //all fixed semantic copy spans of this short one-exchange DATA fit8191.
    data["host"]["events"].as_array_mut().unwrap().truncate(3);
    data["host"]["events"][1]["event"]["payload"] =
        serde_json::json!(format!("{capture}{}", " ".repeat(8192)));
    let mut preparation = Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    );
    let raw = data.to_string();
    let document = preparation.literal_with_raw(&raw).unwrap().0;
    let actual = InstalledClientMeasurements::decode(&document, &mut preparation).unwrap();
    let mut phase =
        Decoder::new(DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 8191, 1_000_000).unwrap());
    assert!(matches!(
        prepare_protocol(&actual.wire, &actual.frames, &mut phase),
        Err(DecodeError::Work(OperandResource::ByteVisits))
    ));
}
