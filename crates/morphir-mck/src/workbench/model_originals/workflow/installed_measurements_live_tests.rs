//! Incremental cache controls, explicit UNIT work owners and no live authority.
use super::super::decode::{DecodeLimits, OperandResource};
use super::*;

fn decoder(visits: usize) -> Decoder {
    Decoder::new(DecodeLimits::new(1_048_576, 1_048_576, 100_000, visits, 100_000).unwrap())
}

#[test]
fn installed_live_cache_retains_invalid_literal_without_inventing_work_fault() {
    let mut owner = decoder(1_048_576);
    let mut live = LiveMeasurements::new();
    live.push_text(
        0,
        0,
        LiveFrame::Received("{not-json".to_owned()),
        &mut owner,
    )
    .unwrap();
    assert_eq!(live.events.len(), 1);
    assert!(live.frames[0].document.is_none());
    assert!(owner.ready().is_ok());
}

#[test]
fn installed_live_cache_refuses_before_growth_on_same_decoder_fault() {
    let mut owner = decoder(1);
    owner.bytes(2).unwrap_err();
    let before = owner.usage();
    let mut live = LiveMeasurements::new();
    assert!(matches!(
        live.push_text(0, 0, LiveFrame::Received("{}".to_owned()), &mut owner),
        Err(DecodeError::Work(OperandResource::ByteVisits))
    ));
    assert!(live.events.is_empty());
    assert_eq!(owner.usage(), before);
}
