//! Shared record types, summaries and report operations. [`draft`] is the
//! production report contract. The legacy envelope remains for frozen runner
//! replay evidence during migration; it has no filesystem writer.
//!
//! Members serialize in the order the first driver wrote them, so a report
//! diffs cleanly against one it produced.

use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize, Serializer};

pub mod check;
pub mod draft;
pub mod html;

use crate::transport::protocol::{Diagnostic, PathMode, Stage};

pub const CONTRACT_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Outcome {
    Pass,
    Fail,
    KitError,
    Skipped,
}

impl Outcome {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pass => "pass",
            Self::Fail => "fail",
            Self::KitError => "kit-error",
            Self::Skipped => "skipped",
        }
    }
}

/// A record's profile: a serialization, or the document-tree layout.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RecordProfile {
    Json,
    Yaml,
    Tree,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Canonical,
    Accepted,
    Rejected,
    File,
}

/// A diagnostic as a report carries it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReportDiagnostic {
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage: Option<Stage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cursor: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

impl From<&Diagnostic> for ReportDiagnostic {
    fn from(d: &Diagnostic) -> Self {
        Self {
            code: d.code.clone(),
            stage: d.stage,
            cursor: d.cursor.clone(),
            message: d.message.clone(),
        }
    }
}

/// A millisecond count, written as an integer when it is one, as the first
/// driver's `JSON.stringify` did.
#[derive(Debug, Clone, Copy, PartialEq, Default, Deserialize)]
pub struct Millis(pub f64);

impl Serialize for Millis {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        if self.0.fract() == 0.0 && self.0.abs() < 9.0e15 {
            serializer.serialize_i64(self.0 as i64)
        } else {
            serializer.serialize_f64(self.0)
        }
    }
}

/// One fence's verdict on one path.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Check {
    Spelling,
    Semantic,
    RoundTrip,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Record {
    pub case_id: String,
    pub ir_version: i64,
    pub profile: RecordProfile,
    pub role: Role,
    pub fence_index: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<PathMode>,
    pub result: Outcome,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expected_diagnostic: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub observed_diagnostic: Option<ReportDiagnostic>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub check: Option<Check>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub diff: Option<String>,
    pub duration_ms: Millis,
}

impl Record {
    /// Old reports predate `check` and describe semantic comparisons.
    pub fn check(&self) -> Check {
        self.check.unwrap_or(Check::Semantic)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub contract_version: u32,
    pub binding: String,
    pub language: String,
    /// The adapter's canonical support table, or `unknown` when it never
    /// answered capabilities.
    pub format_versions: String,
    pub driver_version: String,
    pub kit_version: String,
    pub started_at: String,
    pub records: Vec<Record>,
}

/// Counts by outcome.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Summary {
    pub pass: usize,
    pub fail: usize,
    pub kit_error: usize,
    pub skipped: usize,
}

impl Report {
    pub fn summary(&self) -> Summary {
        let mut summary = Summary::default();
        for record in &self.records {
            match record.result {
                Outcome::Pass => summary.pass += 1,
                Outcome::Fail => summary.fail += 1,
                Outcome::KitError => summary.kit_error += 1,
                Outcome::Skipped => summary.skipped += 1,
            }
        }
        summary
    }

    /// `N pass, N fail, N kit-error, N skipped`, as the first driver printed it.
    pub fn summary_line(&self) -> String {
        let s = self.summary();
        format!(
            "{} pass, {} fail, {} kit-error, {} skipped",
            s.pass, s.fail, s.kit_error, s.skipped
        )
    }

    /// Tab-indented JSON with a trailing newline.
    pub fn to_json(&self) -> String {
        format!("{}\n", crate::json::to_tab_json(self))
    }
}

/// The current time as an ISO 8601 UTC timestamp with milliseconds, the form
/// `Date.prototype.toISOString` writes.
pub fn iso_timestamp(time: SystemTime) -> String {
    let since = time.duration_since(UNIX_EPOCH).unwrap_or_default();
    let millis = since.subsec_millis();
    let seconds = since.as_secs();
    let (days, rest) = (seconds / 86_400, seconds % 86_400);
    let (hour, minute, second) = (rest / 3600, rest % 3600 / 60, rest % 60);
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}Z")
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    #[test]
    fn timestamps_read_as_to_iso_string_writes_them() {
        assert_eq!(iso_timestamp(UNIX_EPOCH), "1970-01-01T00:00:00.000Z");
        // 2026-09-19T00:26:48.346Z, the frozen TypeScript report's startedAt.
        let time = UNIX_EPOCH + Duration::from_millis(1_789_777_608_346);
        assert_eq!(iso_timestamp(time), "2026-09-19T00:26:48.346Z");
        assert_eq!(
            iso_timestamp(UNIX_EPOCH + Duration::from_secs(951_782_400)),
            "2000-02-29T00:00:00.000Z"
        );
    }

    #[test]
    fn durations_are_integers_when_whole() {
        assert_eq!(serde_json::to_string(&Millis(0.0)).unwrap(), "0");
        assert_eq!(serde_json::to_string(&Millis(7.5)).unwrap(), "7.5");
    }

    #[test]
    fn records_serialize_in_the_first_drivers_member_order_and_omit_absent_members() {
        let record = Record {
            case_id: "types-0001".into(),
            ir_version: 4,
            profile: RecordProfile::Yaml,
            role: Role::Rejected,
            fence_index: 2,
            path: Some(PathMode::Pinned),
            result: Outcome::KitError,
            expected_diagnostic: Some("x".into()),
            observed_diagnostic: None,
            message: Some("m".into()),
            check: None,
            diff: None,
            duration_ms: Millis(1.0),
        };
        assert_eq!(
            serde_json::to_string(&record).unwrap(),
            r#"{"caseId":"types-0001","irVersion":4,"profile":"yaml","role":"rejected","fenceIndex":2,"path":"pinned","result":"kit-error","expectedDiagnostic":"x","message":"m","durationMs":1}"#
        );
    }
}
