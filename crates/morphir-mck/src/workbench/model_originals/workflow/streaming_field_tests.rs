//! Source-first field DATA formatting, not a process/source/effect proof.
//! Test sink accepts collect_str and records actual fmt::Write error behavior.
use super::decode::{ContentSha256, U64Token};
use super::native_original::{MeasurementVersion, ObservedCount};
use serde::ser::{self, Impossible, Serialize};
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SinkFault {
    EagerString,
    Unexpected,
    Stop,
}
impl fmt::Display for SinkFault {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("test streaming sink fault")
    }
}
impl std::error::Error for SinkFault {}
impl ser::Error for SinkFault {
    fn custom<T: fmt::Display>(_: T) -> Self {
        Self::Unexpected
    }
}
struct Sink {
    bytes: [u8; 96],
    len: usize,
    calls: usize,
    after_error: usize,
    accept: usize,
    stopped: bool,
}
impl Sink {
    fn new(accept: usize) -> Self {
        Self {
            bytes: [0; 96],
            len: 0,
            calls: 0,
            after_error: 0,
            accept,
            stopped: false,
        }
    }
}
impl fmt::Write for Sink {
    fn write_str(&mut self, value: &str) -> fmt::Result {
        self.calls += 1;
        if self.stopped {
            self.after_error += 1;
            return Err(fmt::Error);
        }
        if self.calls > self.accept {
            self.stopped = true;
            return Err(fmt::Error);
        }
        let next = self
            .len
            .checked_add(value.len())
            .filter(|n| *n <= self.bytes.len())
            .ok_or(fmt::Error)?;
        self.bytes[self.len..next].copy_from_slice(value.as_bytes());
        self.len = next;
        Ok(())
    }
}
macro_rules! reject_scalar{($($name:ident($ty:ty)),*$(,)?)=>{$(
    fn $name(self,_:$ty)->Result<(),SinkFault>{Err(SinkFault::Unexpected)}
)*}}
impl ser::Serializer for &mut Sink {
    type Ok = ();
    type Error = SinkFault;
    type SerializeSeq = Impossible<(), SinkFault>;
    type SerializeTuple = Impossible<(), SinkFault>;
    type SerializeTupleStruct = Impossible<(), SinkFault>;
    type SerializeTupleVariant = Impossible<(), SinkFault>;
    type SerializeMap = Impossible<(), SinkFault>;
    type SerializeStruct = Impossible<(), SinkFault>;
    type SerializeStructVariant = Impossible<(), SinkFault>;
    reject_scalar! {serialize_bool(bool),serialize_i8(i8),serialize_i16(i16),serialize_i32(i32),serialize_i64(i64),serialize_i128(i128),serialize_u8(u8),serialize_u16(u16),serialize_u32(u32),serialize_u64(u64),serialize_u128(u128),serialize_f32(f32),serialize_f64(f64),serialize_char(char)}
    fn serialize_str(self, _: &str) -> Result<(), SinkFault> {
        Err(SinkFault::EagerString)
    }
    fn serialize_bytes(self, _: &[u8]) -> Result<(), SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_none(self) -> Result<(), SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_some<T: ?Sized + Serialize>(self, _: &T) -> Result<(), SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_unit(self) -> Result<(), SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_unit_struct(self, _: &'static str) -> Result<(), SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_unit_variant(
        self,
        _: &'static str,
        _: u32,
        _: &'static str,
    ) -> Result<(), SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_newtype_struct<T: ?Sized + Serialize>(
        self,
        _: &'static str,
        _: &T,
    ) -> Result<(), SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_newtype_variant<T: ?Sized + Serialize>(
        self,
        _: &'static str,
        _: u32,
        _: &'static str,
        _: &T,
    ) -> Result<(), SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_seq(self, _: Option<usize>) -> Result<Self::SerializeSeq, SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_tuple(self, _: usize) -> Result<Self::SerializeTuple, SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_tuple_struct(
        self,
        _: &'static str,
        _: usize,
    ) -> Result<Self::SerializeTupleStruct, SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_tuple_variant(
        self,
        _: &'static str,
        _: u32,
        _: &'static str,
        _: usize,
    ) -> Result<Self::SerializeTupleVariant, SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_map(self, _: Option<usize>) -> Result<Self::SerializeMap, SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_struct(
        self,
        _: &'static str,
        _: usize,
    ) -> Result<Self::SerializeStruct, SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn serialize_struct_variant(
        self,
        _: &'static str,
        _: u32,
        _: &'static str,
        _: usize,
    ) -> Result<Self::SerializeStructVariant, SinkFault> {
        Err(SinkFault::Unexpected)
    }
    fn collect_str<T: ?Sized + fmt::Display>(self, value: &T) -> Result<(), SinkFault> {
        fmt::write(self, format_args!("{value}")).map_err(|_| SinkFault::Stop)
    }
}
fn stream(value: &impl Serialize, expected: &[u8], multiple_chunks: bool) {
    let mut stop = Sink::new(0);
    let result = value.serialize(&mut stop);
    assert_eq!(
        result,
        Err(SinkFault::Stop),
        "the field must stream through the real rejecting fmt sink, not construct an eager String before serialize_str"
    );
    assert_eq!(stop.calls, 1);
    assert_eq!(stop.after_error, 0);
    assert_eq!(stop.len, 0);
    let mut complete = Sink::new(usize::MAX);
    value.serialize(&mut complete).unwrap();
    assert_eq!(&complete.bytes[..complete.len], expected);
    assert_eq!(complete.after_error, 0);
    if multiple_chunks {
        let mut after_one = Sink::new(1);
        assert_eq!(value.serialize(&mut after_one), Err(SinkFault::Stop));
        assert_eq!(after_one.calls, 2);
        assert_eq!(after_one.after_error, 0);
        assert!(after_one.len > 0);
        assert!(after_one.len < expected.len());
    }
}
#[test]
fn four_field_spellings_preserve_existing_json_bytes() {
    for (n, text) in [
        (0, "0"),
        (1, "1"),
        (10, "10"),
        (9_007_199_254_740_993, "9007199254740993"),
        (u64::MAX, "18446744073709551615"),
    ] {
        let expected = format!("\"{text}\"");
        assert_eq!(
            serde_json::to_vec(&ObservedCount(n)).unwrap(),
            expected.as_bytes()
        );
        assert_eq!(
            serde_json::to_vec(&U64Token::new(n)).unwrap(),
            expected.as_bytes()
        );
    }
    assert_eq!(
        serde_json::to_vec(&MeasurementVersion::current().unwrap()).unwrap(),
        b"\"0.1.0-draft.1\""
    );
    let digest = ContentSha256::new(std::array::from_fn(|n| n as u8));
    assert_eq!(
        serde_json::to_vec(&digest).unwrap(),
        b"\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\""
    );
}
#[test]
fn observed_count_streams_and_propagates_first_sink_error() {
    stream(&ObservedCount(u64::MAX), b"18446744073709551615", false);
}
#[test]
fn request_token_streams_and_propagates_first_sink_error() {
    stream(&U64Token::new(u64::MAX), b"18446744073709551615", false);
}
#[test]
fn measurement_version_streams_and_stops_between_components() {
    stream(
        &MeasurementVersion::current().unwrap(),
        b"0.1.0-draft.1",
        true,
    );
}
#[test]
fn content_digest_streams_and_stops_between_digits() {
    stream(
        &ContentSha256::new([0xab; 32]),
        b"abababababababababababababababababababababababababababababababab",
        true,
    );
}
