//! Cumulative logical JSON-input work. This is a checker resource policy,
//! not a production parsing quota, physical allocation or process RSS claim.
use super::Work;
use std::{fmt, num::NonZeroUsize};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ReadWorkResource {
    DecodeBytes,
    Values,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum StrictReadError {
    Limits,
    Json(String),
    Work(ReadWorkResource),
}
impl fmt::Display for StrictReadError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Limits => f.write_str("JSON work limits must be positive"),
            Self::Json(error) => f.write_str(error),
            Self::Work(_) => f.write_str("JSON input exceeds its cumulative checker work budget"),
        }
    }
}
impl std::error::Error for StrictReadError {}

#[derive(Debug, Clone, Copy)]
pub(crate) struct ReadWorkLimits {
    decode_bytes: NonZeroUsize,
    values: NonZeroUsize,
}
impl ReadWorkLimits {
    pub(crate) fn new(decode_bytes: usize, values: usize) -> Result<Self, StrictReadError> {
        Ok(Self {
            decode_bytes: NonZeroUsize::new(decode_bytes).ok_or(StrictReadError::Limits)?,
            values: NonZeroUsize::new(values).ok_or(StrictReadError::Limits)?,
        })
    }
}
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(crate) struct ReadWorkUsage {
    pub(crate) decode_bytes: usize,
    pub(crate) values: usize,
}

/// One owner spans every document in a workflow decode. DecodeBytes counts
/// logical input bytes requested by each serde/number decode, including repeated
/// container and child decodes. Values charges the root and each child before
/// its key or raw reference is buffered. Failed work remains spent; exhaustion
/// is sticky. No default policy or independent owner clone is provided.
pub(crate) struct ReadWork {
    limits: ReadWorkLimits,
    usage: ReadWorkUsage,
    fault: Option<ReadWorkResource>,
}
impl ReadWork {
    pub(crate) fn new(limits: ReadWorkLimits) -> Self {
        Self {
            limits,
            usage: ReadWorkUsage::default(),
            fault: None,
        }
    }
    pub(crate) fn usage(&self) -> ReadWorkUsage {
        self.usage
    }
    pub(super) fn error(&self, error: String) -> StrictReadError {
        self.fault
            .map_or(StrictReadError::Json(error), StrictReadError::Work)
    }
    fn charge(&mut self, resource: ReadWorkResource, count: usize) -> Result<(), String> {
        if let Some(fault) = self.fault {
            return Err(StrictReadError::Work(fault).to_string());
        }
        let (used, limit) = match resource {
            ReadWorkResource::DecodeBytes => {
                (&mut self.usage.decode_bytes, self.limits.decode_bytes.get())
            }
            ReadWorkResource::Values => (&mut self.usage.values, self.limits.values.get()),
        };
        let Some(next) = used.checked_add(count).filter(|next| *next <= limit) else {
            self.fault = Some(resource);
            return Err(StrictReadError::Work(resource).to_string());
        };
        *used = next;
        Ok(())
    }
}
impl Work for ReadWork {
    fn decode(&mut self, bytes: usize) -> Result<(), String> {
        self.charge(ReadWorkResource::DecodeBytes, bytes)
    }
    fn value(&mut self) -> Result<(), String> {
        self.charge(ReadWorkResource::Values, 1)
    }
}
