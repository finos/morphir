//! Decoder mechanisms needed by the independently frozen inputV27 schema.
//! These small domain declarations do not stand in for the complete input schema.
use super::*;
use crate::json::strict::Document;
use std::sync::atomic::{AtomicUsize, Ordering};

static STRING_CALLS: AtomicUsize = AtomicUsize::new(0);
static OBJECT_CALLS: AtomicUsize = AtomicUsize::new(0);
#[derive(Debug)]
pub(super) struct StringProbe;
impl Decode for StringProbe {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        STRING_CALLS.fetch_add(1, Ordering::Relaxed);
        RawJson::decode(value, owner)?;
        Ok(Self)
    }
}
#[derive(Debug)]
pub(super) struct ObjectProbe;
impl Decode for ObjectProbe {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        OBJECT_CALLS.fetch_add(1, Ordering::Relaxed);
        Fields::new(value, &[], owner)?;
        Ok(Self)
    }
}
kind! { ShapeSelection { String(StringProbe), Object(ObjectProbe) } }
record! { OptionalList { alias: FixtureAlias => "alias" } optional { requests: Items<FixtureAlias, 0, 4> => "requests" } }
words! { CaptureAt { Waiting => "shared-lock-waiting" } }
words! { WriterAt { Waiting => "exclusive-lock-waiting" } }
tagged! { CaptureOwner("kind") { Pending => "pending-capture" { pending: FixtureAlias => "pending" } } }
tagged! { WriterOwner("kind") { Writer => "cooperating-writer" { writer: FixtureAlias => "writer" } } }
nested_tagged! { AwaitBoundary("kind" => "await-boundary"; "owner", "kind") {
    Capture => "pending-capture" { owner: CaptureOwner => "owner", at: CaptureAt => "at" },
    Writer => "cooperating-writer" { owner: WriterOwner => "owner", at: WriterAt => "at" }
} }
tagged! { Action("kind") { Tick => "tick" {} } delegates { Await => "await-boundary": AwaitBoundary } }

fn decoder() -> Decoder {
    Decoder::new(DecodeLimits::new(4096, 65536, 4096, 65536, 4096).unwrap())
}

#[test]
fn kind_selection_invokes_only_the_chosen_decoder_and_keeps_the_same_owner() {
    STRING_CALLS.store(0, Ordering::Relaxed);
    OBJECT_CALLS.store(0, Ordering::Relaxed);
    let mut d = decoder();
    assert!(matches!(
        d.decode::<ShapeSelection>(r#""0""#).unwrap(),
        ShapeSelection::String(_)
    ));
    assert_eq!(
        d.usage().literal.values,
        2,
        "outer string and embedded number share accounting"
    );
    assert!(matches!(
        d.decode::<ShapeSelection>("{}").unwrap(),
        ShapeSelection::Object(_)
    ));
    assert_eq!(d.usage().literal.values, 3);
    for raw in ["null", "true", "1", "[]"] {
        assert!(d.decode::<ShapeSelection>(raw).is_err());
    }
    assert!(
        d.decode::<ShapeSelection>(r#""{""#).is_err(),
        "invalid selected string must not fall back to object"
    );
    assert_eq!(STRING_CALLS.load(Ordering::Relaxed), 2);
    assert_eq!(OBJECT_CALLS.load(Ordering::Relaxed), 1);
}

#[test]
fn optional_fields_preserve_absence_empty_and_invalid_null_without_defaults() {
    let mut d = decoder();
    let absent = d.decode::<OptionalList>(r#"{"alias":"A"}"#).unwrap();
    assert_eq!(absent.alias.as_str(), "A");
    assert!(matches!(absent.requests, Presence::Absent));
    let empty = d
        .decode::<OptionalList>(r#"{"alias":"A","requests":[]}"#)
        .unwrap();
    assert!(matches!(empty.requests, Presence::Present(Items(values)) if values.is_empty()));
    let present = d
        .decode::<OptionalList>(r#"{"alias":"A","requests":["B"]}"#)
        .unwrap();
    assert!(
        matches!(present.requests, Presence::Present(Items(values)) if values[0].as_str() == "B")
    );
    for raw in [
        r#"{"alias":"A","requests":null}"#,
        r#"{"alias":"A","extra":[]}"#,
        r#"{"requests":[]}"#,
        r#"{"alias":"A","requests":[],"requests":[]}"#,
    ] {
        assert!(d.decode::<OptionalList>(raw).is_err(), "{raw}");
    }
    let mut d = Decoder::new(DecodeLimits::new(4096, 65536, 4096, 65536, 1).unwrap());
    assert!(matches!(
        d.decode::<OptionalList>(r#"{"alias":"A","requests":["bad/path","B"]}"#),
        Err(DecodeError::Work(OperandResource::Slots))
    ));
}

#[test]
fn nested_owner_selection_keeps_exact_owner_and_boundary_correlation() {
    let mut d = decoder();
    let capture = d.decode::<Action>(r#"{"kind":"await-boundary","owner":{"kind":"pending-capture","pending":"A"},"at":"shared-lock-waiting"}"#).unwrap();
    assert!(matches!(capture, Action::Await(AwaitBoundary::Capture {
        owner: CaptureOwner::Pending { pending }, at: CaptureAt::Waiting,
    }) if pending.as_str() == "A"));
    let writer = d.decode::<Action>(r#"{"kind":"await-boundary","owner":{"kind":"cooperating-writer","writer":"A"},"at":"exclusive-lock-waiting"}"#).unwrap();
    assert!(matches!(writer, Action::Await(AwaitBoundary::Writer {
        owner: WriterOwner::Writer { writer }, at: WriterAt::Waiting,
    }) if writer.as_str() == "A"));
    assert!(matches!(
        d.decode::<Action>(r#"{"kind":"tick"}"#).unwrap(),
        Action::Tick {}
    ));
    for raw in [
        r#"{"kind":"await-boundary","owner":{"kind":"pending-capture","pending":"A"},"at":"exclusive-lock-waiting"}"#,
        r#"{"kind":"await-boundary","owner":{"kind":"cooperating-writer","writer":"A"},"at":"shared-lock-waiting"}"#,
        r#"{"kind":"await-boundary","owner":{"kind":"pending-capture","writer":"A"},"at":"shared-lock-waiting"}"#,
        r#"{"kind":"await-boundary","owner":{"kind":"cooperating-writer","writer":"A","pending":"A"},"at":"exclusive-lock-waiting"}"#,
        r#"{"kind":"await-boundary","owner":null,"at":"shared-lock-waiting"}"#,
        r#"{"kind":"await-boundary","owner":{"kind":"unknown","pending":"A"},"at":"shared-lock-waiting"}"#,
        r#"{"kind":"await-boundary","owner":{"kind":"pending-capture","pending":"A"},"at":"shared-lock-waiting","extra":true}"#,
        r#"{"kind":"tick","owner":{"kind":"pending-capture","pending":"A"},"at":"shared-lock-waiting"}"#,
    ] {
        assert!(d.decode::<Action>(raw).is_err(), "{raw}");
    }
    assert!(d.decode::<AwaitBoundary>(r#"{"kind":"tick","owner":{"kind":"pending-capture","pending":"A"},"at":"shared-lock-waiting"}"#).is_err());
}

#[test]
fn a_latched_resource_fault_precedes_later_kind_or_literal_shape_errors() {
    let mut d = Decoder::new(DecodeLimits::new(4096, 65536, 4096, 1, 4096).unwrap());
    let fault = d.decode::<Text<0, 10>>(r#""AB""#).unwrap_err();
    assert_eq!(fault, DecodeError::Work(OperandResource::ByteVisits));
    let spent = d.usage();
    assert_eq!(
        ShapeSelection::decode(&Document::Null, &mut d).unwrap_err(),
        fault
    );
    assert_eq!(
        discriminator(&Document::Null, "kind", &mut d).unwrap_err(),
        fault
    );
    assert_eq!(
        Literal::decode_literal(&Document::Null, 1_i64, &mut d).unwrap_err(),
        fault
    );
    assert_eq!(d.usage(), spent);
}
