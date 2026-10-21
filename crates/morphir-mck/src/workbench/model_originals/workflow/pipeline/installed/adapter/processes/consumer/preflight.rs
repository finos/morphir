//! Closed selected-report preflight. No allocation, parser or effect authority.
//! Counts emitted string input before either pinned serde_json encoding pass.
use serde::ser::{self, Serialize};
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum InputFault {
    Limit,
    WorkLimit,
    Unsupported,
}
impl fmt::Display for InputFault {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Limit => "selected report string-input limit",
            Self::WorkLimit => "selected report preflight work limit",
            Self::Unsupported => "unsupported selected report serialization",
        })
    }
}
impl std::error::Error for InputFault {}
impl ser::Error for InputFault {
    fn custom<T: fmt::Display>(_: T) -> Self {
        // Deliberately does not format, copy or allocate the supplied message.
        Self::Unsupported
    }
}
struct StringInput {
    used: usize,
    limit: usize,
    steps: usize,
    step_limit: usize,
}
impl StringInput {
    fn step(&mut self) -> Result<(), InputFault> {
        self.steps = self
            .steps
            .checked_add(1)
            .filter(|n| *n <= self.step_limit)
            .ok_or(InputFault::WorkLimit)?;
        Ok(())
    }
    fn add(&mut self, bytes: usize) -> Result<(), InputFault> {
        self.used = self
            .used
            .checked_add(bytes)
            .filter(|sum| *sum <= self.limit)
            .ok_or(InputFault::Limit)?;
        Ok(())
    }
}
// Only the private closed selected RuntimeReport may call this in production.
// Generic T here permits cfgtest DATA vectors, not arbitrary production plugins.
pub(super) fn check_string_input<T: ?Sized + Serialize>(
    report: &T,
    active_limit: usize,
    issued_steps: usize,
) -> Result<Progress, Refused> {
    // Explicit algorithm work permission, not a proof every fitting report can
    // complete. A work refusal is distinct from encoded-size/string refusal.
    // Production exposes no generic S or caller-supplied independent limit.
    let mut count = StringInput {
        used: 0,
        limit: active_limit,
        steps: 0,
        step_limit: issued_steps,
    };
    let result = report.serialize(&mut count);
    let progress = Progress {
        strings: count.used,
        steps: count.steps,
    };
    result
        .map(|()| progress)
        .map_err(|fault| Refused { fault, progress })
}
#[derive(Debug, Clone, Copy, Default)]
pub(super) struct Progress {
    pub(super) strings: usize,
    pub(super) steps: usize,
}
pub(super) struct Refused {
    pub(super) fault: InputFault,
    pub(super) progress: Progress,
}
macro_rules! scalar {
    ($($name:ident($ty:ty)),* $(,)?) => {$ (
        fn $name(self, _: $ty) -> Result<(), InputFault> { self.step() }
    )*};
}
impl<'a> ser::Serializer for &'a mut StringInput {
    type Ok = ();
    type Error = InputFault;
    type SerializeSeq = Self;
    type SerializeTuple = Self;
    type SerializeTupleStruct = Self;
    type SerializeTupleVariant = Self;
    type SerializeMap = Self;
    type SerializeStruct = Fields<'a>;
    type SerializeStructVariant = Fields<'a>;
    scalar! {
        serialize_bool(bool), serialize_i8(i8), serialize_i16(i16),
        serialize_i32(i32), serialize_i64(i64), serialize_i128(i128),
        serialize_u8(u8), serialize_u16(u16), serialize_u32(u32),
        serialize_u64(u64), serialize_u128(u128),
        serialize_f32(f32), serialize_f64(f64)
    }
    fn serialize_char(self, value: char) -> Result<(), InputFault> {
        self.step()?;
        self.add(value.len_utf8())
    }
    fn serialize_str(self, value: &str) -> Result<(), InputFault> {
        self.step()?;
        self.add(value.len()) // O(1), no UTF8 revalidation/content scan.
    }
    fn serialize_bytes(self, _: &[u8]) -> Result<(), InputFault> {
        // Closed selected report uses ObservedBytes' explicit UTF8/hex shape.
        // Do not silently admit another potentially scanning serializer path.
        Err(InputFault::Unsupported)
    }
    fn serialize_none(self) -> Result<(), InputFault> {
        self.step()
    }
    fn serialize_some<T: ?Sized + Serialize>(self, value: &T) -> Result<(), InputFault> {
        self.step()?;
        value.serialize(self)
    }
    fn serialize_unit(self) -> Result<(), InputFault> {
        self.step()
    }
    fn serialize_unit_struct(self, _: &'static str) -> Result<(), InputFault> {
        self.step()
    }
    fn serialize_unit_variant(
        self,
        _: &'static str,
        _: u32,
        variant: &'static str,
    ) -> Result<(), InputFault> {
        self.step()?;
        self.add(variant.len())
    }
    fn serialize_newtype_struct<T: ?Sized + Serialize>(
        self,
        _: &'static str,
        value: &T,
    ) -> Result<(), InputFault> {
        self.step()?;
        value.serialize(self) // Type name is not emitted by serde_json.
    }
    fn serialize_newtype_variant<T: ?Sized + Serialize>(
        self,
        _: &'static str,
        _: u32,
        variant: &'static str,
        value: &T,
    ) -> Result<(), InputFault> {
        self.step()?;
        self.add(variant.len())?;
        value.serialize(self)
    }
    fn serialize_seq(self, _: Option<usize>) -> Result<Self, InputFault> {
        self.step()?;
        Ok(self)
    }
    fn serialize_tuple(self, _: usize) -> Result<Self, InputFault> {
        self.step()?;
        Ok(self)
    }
    fn serialize_tuple_struct(self, _: &'static str, _: usize) -> Result<Self, InputFault> {
        self.step()?;
        Ok(self)
    }
    fn serialize_tuple_variant(
        self,
        _: &'static str,
        _: u32,
        variant: &'static str,
        _: usize,
    ) -> Result<Self, InputFault> {
        self.step()?;
        self.add(variant.len())?;
        Ok(self)
    }
    fn serialize_map(self, _: Option<usize>) -> Result<Self, InputFault> {
        self.step()?;
        Ok(self)
    }
    fn serialize_struct(self, name: &'static str, _: usize) -> Result<Fields<'a>, InputFault> {
        self.step()?;
        // Pinned serde_json private wrappers emit their value, not the token
        // name/field key. Both raw JSON and arbitrary-precision numeric spelling
        // are counted conservatively by their payload str length, unchanged.
        let kind = match name {
            "$serde_json::private::RawValue" | "$serde_json::private::Number" => FieldKind::Raw,
            _ => FieldKind::Object,
        };
        Ok(Fields { count: self, kind })
    }
    fn serialize_struct_variant(
        self,
        _: &'static str,
        _: u32,
        variant: &'static str,
        _: usize,
    ) -> Result<Fields<'a>, InputFault> {
        self.step()?;
        self.add(variant.len())?;
        Ok(Fields {
            count: self,
            kind: FieldKind::Object,
        })
    }
    fn collect_str<T: ?Sized + fmt::Display>(self, value: &T) -> Result<(), InputFault> {
        self.step()?;
        // Production census must remain exactly the known BorrowedHex Display
        // and fixed, bounded library spellings. No arbitrary formatter claim.
        struct Sink<'a> {
            count: &'a mut StringInput,
            fault: Option<InputFault>,
        }
        impl fmt::Write for Sink<'_> {
            fn write_str(&mut self, value: &str) -> fmt::Result {
                self.count.add(value.len()).map_err(|fault| {
                    self.fault = Some(fault);
                    fmt::Error
                })
            }
        }
        let mut sink = Sink {
            count: self,
            fault: None,
        };
        fmt::write(&mut sink, format_args!("{value}"))
            .map_err(|_| sink.fault.unwrap_or(InputFault::Unsupported))
    }
}
macro_rules! compound {
    ($trait:ident, $method:ident) => {
        impl ser::$trait for &mut StringInput {
            type Ok = ();
            type Error = InputFault;
            fn $method<T: ?Sized + Serialize>(&mut self, value: &T) -> Result<(), InputFault> {
                value.serialize(&mut **self)
            }
            fn end(self) -> Result<(), InputFault> {
                self.step()
            }
        }
    };
}
compound!(SerializeSeq, serialize_element);
compound!(SerializeTuple, serialize_element);
compound!(SerializeTupleStruct, serialize_field);
compound!(SerializeTupleVariant, serialize_field);
impl ser::SerializeMap for &mut StringInput {
    type Ok = ();
    type Error = InputFault;
    fn serialize_key<T: ?Sized + Serialize>(&mut self, value: &T) -> Result<(), InputFault> {
        value.serialize(&mut **self)
    }
    fn serialize_value<T: ?Sized + Serialize>(&mut self, value: &T) -> Result<(), InputFault> {
        value.serialize(&mut **self)
    }
    fn end(self) -> Result<(), InputFault> {
        self.step()
    }
}
enum FieldKind {
    Object,
    Raw,
}
struct Fields<'a> {
    count: &'a mut StringInput,
    kind: FieldKind,
}
impl Fields<'_> {
    fn field<T: ?Sized + Serialize>(
        &mut self,
        key: &'static str,
        value: &T,
    ) -> Result<(), InputFault> {
        self.count.step()?;
        if matches!(self.kind, FieldKind::Object) {
            self.count.add(key.len())?;
        }
        value.serialize(&mut *self.count)
    }
}
macro_rules! fields {
    ($trait:ident) => {
        impl ser::$trait for Fields<'_> {
            type Ok = ();
            type Error = InputFault;
            fn serialize_field<T: ?Sized + Serialize>(
                &mut self,
                key: &'static str,
                value: &T,
            ) -> Result<(), InputFault> {
                self.field(key, value)
            }
            fn end(self) -> Result<(), InputFault> {
                self.count.step()
            }
        }
    };
}
fields!(SerializeStruct);
fields!(SerializeStructVariant);
