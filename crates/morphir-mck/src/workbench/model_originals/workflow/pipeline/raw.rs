use serde::de::{IgnoredAny, SeqAccess, Visitor};
use serde::{Deserialize, Deserializer};
use serde_json::value::RawValue;
use std::fmt;

pub(super) use crate::workbench::contract::MODEL_ORIGINALS_VERSION as VERSION;

// Generic bounded-wire classification only. Every operand is borrowed raw;
// there is no selected AST, payload String or checker policy at this boundary.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Header<'a> {
    #[serde(borrow)]
    cases: Option<&'a RawValue>,
    #[serde(borrow)]
    records: Option<&'a RawValue>,
    #[serde(borrow)]
    qualified: Option<&'a RawValue>,
}
pub(in crate::workbench) fn recognizes(raw: &str) -> Result<bool, String> {
    Ok(format_version(raw)?.is_some_and(|version| version == VERSION))
}
pub(in crate::workbench) fn recognizes_report(raw: &str) -> Result<bool, String> {
    Ok(format_version(raw)?
        .is_some_and(|version| super::report_revision::ReportRevision::parse(&version).is_ok()))
}
fn format_version(raw: &str) -> Result<Option<String>, String> {
    let raw: &RawValue = serde_json::from_str(raw).map_err(|e| e.to_string())?;
    // Classification borrows member values without interpreting selected
    // operands. The wire length bounds both scanned bytes and member count.
    // Use the shared duplicate-aware visitor so historical input retains its
    // existing duplicate diagnostics before either report decoder runs.
    let length = raw.get().len().max(1);
    let limits =
        crate::json::strict::ReadWorkLimits::new(length, length).map_err(|e| e.to_string())?;
    let mut work = crate::json::strict::ReadWork::new(limits);
    let members =
        crate::json::strict::raw_members_with_work(raw, &mut work).map_err(|e| e.to_string())?;
    let version = members
        .into_iter()
        .find(|(key, _)| key == "formatVersion")
        .map(|(_, value)| value)
        .ok_or("formatVersion missing")?;
    // Exact supported version is ASCII. Six-byte escaping per source character
    // is the largest JSON spelling that can decode to that fixed string.
    if version.get().len() > VERSION.len() * 6 + 2 {
        return Ok(None);
    }
    let version: String = serde_json::from_str(version.get()).map_err(|e| e.to_string())?;
    Ok(Some(version))
}
struct Count(usize);
impl<'de> Deserialize<'de> for Count {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct Entries;
        impl<'de> Visitor<'de> for Entries {
            type Value = Count;
            fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str("bounded wire entries")
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut sequence: A) -> Result<Count, A::Error> {
                let mut count = 0usize;
                while sequence.next_element::<IgnoredAny>()?.is_some() {
                    count = count.checked_add(1).filter(|n| *n <= 1024).ok_or_else(|| {
                        serde::de::Error::custom("wire inventory exceeds1024 entries")
                    })?;
                }
                Ok(Count(count))
            }
        }
        d.deserialize_seq(Entries)
    }
}
pub(in crate::workbench) fn corpus_count(raw: &str) -> Result<usize, String> {
    let header: Header<'_> = serde_json::from_str(raw).map_err(|e| e.to_string())?;
    let raw = header.cases.ok_or("corpus cases missing")?;
    serde_json::from_str::<Count>(raw.get())
        .map(|n| n.0)
        .map_err(|e| e.to_string())
}
#[derive(Debug, Clone)]
pub(in crate::workbench) struct StoredReport {
    raw: String,
    count: usize,
    claimed_qualified: bool,
}
impl StoredReport {
    pub(in crate::workbench) fn from_json(raw: &str) -> Result<Self, String> {
        if raw.len() > crate::workbench::MAX_REPORT_BYTES {
            return Err("Workbench report exceeds32MiB".into());
        }
        let header: Header<'_> = serde_json::from_str(raw).map_err(|e| e.to_string())?;
        let count =
            serde_json::from_str::<Count>(header.records.ok_or("report records missing")?.get())
                .map_err(|e| e.to_string())?
                .0;
        let claimed_qualified =
            serde_json::from_str::<bool>(header.qualified.ok_or("report qualified missing")?.get())
                .map_err(|e| e.to_string())?;
        let mut owned = String::new();
        owned
            .try_reserve_exact(raw.len())
            .map_err(|_| "report raw retention allocation refused")?;
        owned.push_str(raw);
        Ok(Self {
            raw: owned,
            count,
            claimed_qualified,
        })
    }
    pub(super) fn rendered(raw: String, count: usize) -> Self {
        // Sole caller validates encoded output before allocation/rendering.
        Self {
            raw,
            count,
            claimed_qualified: false,
        }
    }
    pub(in crate::workbench) fn text(&self) -> &str {
        &self.raw
    }
    pub(in crate::workbench) fn qualified(&self) -> bool {
        self.claimed_qualified
    }
    pub(in crate::workbench) fn summary(&self) -> String {
        format!(
            "{} recorded workflow executions; partial source inventory",
            self.count
        )
    }
}
