//! Pure interpretation of independently authored fixture bytes. Recipe text is
//! never observed host output or an authority to open files. Parse and preflight
//! the complete flat recipe before decoding even the first literal byte buffer.
use super::{EvidenceError, ExpectedBytes};
use serde_json::Value;
use std::{fmt, num::NonZeroUsize};

#[cfg(test)]
thread_local! {static LITERAL_FACTORIES:std::cell::Cell<usize>=const {std::cell::Cell::new(0)};}
#[cfg(test)]
pub(super) fn literal_factories() -> usize {
    LITERAL_FACTORIES.with(std::cell::Cell::get)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FixtureByteError {
    Limits,
    SavedBytes,
    Json,
    Shape,
    Count,
    Hex,
    Parts,
    ExpandedBytes,
    Window,
}
impl fmt::Display for FixtureByteError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Limits => "fixture byte limits must be positive",
            Self::SavedBytes => "fixture recipe exceeds its saved byte bound",
            Self::Json => "fixture recipe is not strict duplicate-free JSON",
            Self::Shape => "fixture byte recipe differs from its closed representation",
            Self::Count => "fixture count is not an exact bounded nonnegative integer",
            Self::Hex => "fixture hex must have even length and lowercase hexadecimal digits",
            Self::Parts => "fixture concatenation is empty, nested or exceeds its part bound",
            Self::ExpandedBytes => "complete fixture exceeds its expanded byte bound",
            Self::Window => "fixture window exceeds the complete source bounds",
        })
    }
}
impl std::error::Error for FixtureByteError {}

/// Explicit per-recipe checker policy. These bounds count encoded text,
/// resulting bytes and atomic parts, independently of host capacity or RSS.
#[derive(Debug, Clone, Copy)]
pub struct FixtureByteLimits {
    saved: NonZeroUsize,
    expanded: NonZeroUsize,
    parts: NonZeroUsize,
}
impl FixtureByteLimits {
    pub fn new(saved: usize, expanded: usize, parts: usize) -> Result<Self, FixtureByteError> {
        Ok(Self {
            saved: NonZeroUsize::new(saved).ok_or(FixtureByteError::Limits)?,
            expanded: NonZeroUsize::new(expanded).ok_or(FixtureByteError::Limits)?,
            parts: NonZeroUsize::new(parts).ok_or(FixtureByteError::Limits)?,
        })
    }
}

#[derive(Debug)]
enum Atom {
    Literal(Vec<u8>),
    Repeat { byte: u8, length: usize },
    Cycle { seed: u8, length: usize },
    ChunkIndexed { seed: u8, length: usize },
}
impl Atom {
    fn length(&self) -> usize {
        match self {
            Self::Literal(bytes) => bytes.len(),
            Self::Repeat { length, .. }
            | Self::Cycle { length, .. }
            | Self::ChunkIndexed { length, .. } => *length,
        }
    }
    fn fill(&self, offset: usize, target: &mut [u8]) {
        match self {
            Self::Literal(bytes) => target.copy_from_slice(&bytes[offset..offset + target.len()]),
            Self::Repeat { byte, .. } => target.fill(*byte),
            Self::Cycle { seed, .. } => {
                for (index, byte) in target.iter_mut().enumerate() {
                    *byte = seed.wrapping_add((offset + index) as u8);
                }
            }
            Self::ChunkIndexed { seed, .. } => {
                for (index, byte) in target.iter_mut().enumerate() {
                    *byte = seed.wrapping_add(((offset + index) / 65536) as u8);
                }
            }
        }
    }
    fn expected(&self) -> Result<ExpectedBytes<'_>, EvidenceError> {
        match self {
            Self::Literal(bytes) => ExpectedBytes::literal(bytes),
            Self::Repeat { byte, length } => ExpectedBytes::repeat(*byte, *length),
            Self::Cycle { seed, length } => ExpectedBytes::cycle(*seed, *length),
            Self::ChunkIndexed { seed, length } => ExpectedBytes::chunk_indexed(*seed, *length),
        }
    }
}
#[derive(Debug)]
pub struct FixtureBytes {
    atoms: Vec<Atom>,
    length: usize,
}
impl FixtureBytes {
    pub fn parse(text: &str, limits: FixtureByteLimits) -> Result<Self, FixtureByteError> {
        if text.len() > limits.saved.get() {
            return Err(FixtureByteError::SavedBytes);
        }
        let value = crate::json::strict::parse_exact(text).map_err(|_| FixtureByteError::Json)?;
        let values = if value["kind"] == "concat" {
            fields(&value, &["kind", "parts"])?;
            let parts = value["parts"].as_array().ok_or(FixtureByteError::Shape)?;
            if parts.is_empty() || parts.len() > limits.parts.get() {
                return Err(FixtureByteError::Parts);
            }
            parts.as_slice()
        } else {
            std::slice::from_ref(&value)
        };
        let mut length = 0usize;
        let mut plans = Vec::with_capacity(values.len());
        for value in values {
            let plan = Plan::parse(value)?;
            length = length
                .checked_add(plan.length())
                .filter(|length| *length <= limits.expanded.get())
                .ok_or(FixtureByteError::ExpandedBytes)?;
            plans.push(plan);
        }
        // Only literals allocate byte buffers. Large pattern expectations stay
        // compact and compare against actual bytes without generating a copy.
        let atoms = plans.into_iter().map(Plan::decode).collect();
        Ok(Self { atoms, length })
    }
    pub fn byte_length(&self) -> usize {
        self.length
    }
    /// Copy only a requested window of independent input bytes. Preflight the
    /// entire range before modifying the destination, including on overflow.
    pub fn fill_window(&self, offset: usize, target: &mut [u8]) -> Result<(), FixtureByteError> {
        offset
            .checked_add(target.len())
            .filter(|end| *end <= self.length)
            .ok_or(FixtureByteError::Window)?;
        let mut start = 0;
        let mut written = 0;
        for atom in &self.atoms {
            let end = start + atom.length();
            let position = offset + written;
            if written < target.len() && position < end {
                let count = (end - position).min(target.len() - written);
                atom.fill(position - start, &mut target[written..written + count]);
                written += count;
            }
            start = end;
        }
        Ok(())
    }
    /// Reuse the source-correspondence checker, including its original-source
    /// bound. Oversized refusal inputs can parse but cannot become expectations
    /// for a successfully retained original.
    pub fn expected(&self) -> Result<ExpectedBytes<'_>, EvidenceError> {
        ExpectedBytes::segments(
            self.atoms
                .iter()
                .map(Atom::expected)
                .collect::<Result<_, _>>()?,
        )
    }
}

enum Plan<'a> {
    Hex(&'a str),
    Utf8(&'a str),
    Pattern(Atom),
}
impl<'a> Plan<'a> {
    fn parse(value: &'a Value) -> Result<Self, FixtureByteError> {
        match value["kind"].as_str() {
            Some("hex") => {
                fields(value, &["kind", "hex"])?;
                let text = value["hex"].as_str().ok_or(FixtureByteError::Shape)?;
                hex_byte_length(text)?;
                Ok(Self::Hex(text))
            }
            Some("utf8") => {
                fields(value, &["kind", "text"])?;
                Ok(Self::Utf8(
                    value["text"].as_str().ok_or(FixtureByteError::Shape)?,
                ))
            }
            Some(kind @ ("repeat-u8" | "cycle-u8" | "chunk-indexed-u8")) => {
                let key = if kind == "repeat-u8" { "byte" } else { "seed" };
                fields(value, &["kind", key, "length"])?;
                // Reuse exact decimal integrality; never round through f64 or
                // deserialize literal marker objects into numeric operands.
                let seed = super::super::artifacts::integer(&value[key], 255)
                    .map_err(|_| FixtureByteError::Count)? as u8;
                let safe = usize::try_from(9_007_199_254_740_991u64).unwrap_or(usize::MAX);
                let length = super::super::artifacts::integer(&value["length"], safe)
                    .map_err(|_| FixtureByteError::Count)?;
                Ok(Self::Pattern(match kind {
                    "repeat-u8" => Atom::Repeat { byte: seed, length },
                    "cycle-u8" => Atom::Cycle { seed, length },
                    _ => Atom::ChunkIndexed { seed, length },
                }))
            }
            Some("concat") => Err(FixtureByteError::Parts),
            _ => Err(FixtureByteError::Shape),
        }
    }
    fn length(&self) -> usize {
        match self {
            Self::Hex(text) => text.len() / 2,
            Self::Utf8(text) => text.len(),
            Self::Pattern(
                Atom::Repeat { length, .. }
                | Atom::Cycle { length, .. }
                | Atom::ChunkIndexed { length, .. },
            ) => *length,
            Self::Pattern(Atom::Literal(bytes)) => bytes.len(),
        }
    }
    fn decode(self) -> Atom {
        #[cfg(test)]
        if matches!(&self, Self::Hex(_) | Self::Utf8(_)) {
            LITERAL_FACTORIES.with(|count| count.set(count.get() + 1));
        }
        fn digit(byte: u8) -> u8 {
            if byte.is_ascii_digit() {
                byte - b'0'
            } else {
                byte - b'a' + 10
            }
        }
        match self {
            Self::Hex(text) => Atom::Literal(
                text.as_bytes()
                    .as_chunks::<2>()
                    .0
                    .iter()
                    .map(|[a, b]| digit(*a) * 16 + digit(*b))
                    .collect(),
            ),
            Self::Utf8(text) => Atom::Literal(text.as_bytes().to_vec()),
            Self::Pattern(atom) => atom,
        }
    }
}
/// Shared exact hex length validation. This does not allocate decoded bytes.
pub(super) fn hex_byte_length(text: &str) -> Result<usize, FixtureByteError> {
    if !text.len().is_multiple_of(2)
        || !text
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(FixtureByteError::Hex);
    }
    Ok(text.len() / 2)
}
fn fields(value: &Value, names: &[&str]) -> Result<(), FixtureByteError> {
    let object = value.as_object().ok_or(FixtureByteError::Shape)?;
    if object.len() == names.len() && names.iter().all(|name| object.contains_key(*name)) {
        Ok(())
    } else {
        Err(FixtureByteError::Shape)
    }
}
