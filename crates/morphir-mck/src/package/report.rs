use super::{Capabilities, Contract, Kit, Operation};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ResultKind {
    Pass,
    Fail,
    Skipped,
    KitError,
}
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Record {
    pub case_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub operation: Option<Operation>,
    pub result: ResultKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KitIdentity {
    pub format_version: Contract,
    pub content_hash: String,
}
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub suite: &'static str,
    pub contract_version: Contract,
    pub driver_version: String,
    pub kit: KitIdentity,
    pub started_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub testee: Option<Capabilities>,
    pub records: Vec<Record>,
}
impl Report {
    pub(super) fn new(kit: &Kit, driver_version: &str, started_at: &str) -> Self {
        Self {
            suite: "package",
            contract_version: kit.contract,
            driver_version: driver_version.into(),
            kit: KitIdentity {
                format_version: kit.contract,
                content_hash: kit.content_hash.to_string(),
            },
            started_at: started_at.into(),
            testee: None,
            records: Vec::new(),
        }
    }
    pub fn kit_error(kit: &Kit, driver_version: &str, started_at: &str) -> Self {
        let mut report = Self::new(kit, driver_version, started_at);
        report.error(
            "package-kit",
            if kit.errors.is_empty() {
                "empty kit".into()
            } else {
                kit.errors.join("; ")
            },
        );
        report
    }
    pub fn adapter_error(
        kit: &Kit,
        driver_version: &str,
        started_at: &str,
        message: impl Into<String>,
    ) -> Self {
        let mut report = Self::new(kit, driver_version, started_at);
        report.error("package-adapter", message.into());
        report
    }
    pub(super) fn error(&mut self, id: &str, message: String) {
        self.records.push(Record {
            case_id: id.into(),
            operation: None,
            result: ResultKind::KitError,
            message: Some(message),
        });
    }
    pub fn exit_code(&self) -> i32 {
        if !self.records.is_empty() && self.records.iter().all(|r| r.result == ResultKind::Pass) {
            0
        } else {
            1
        }
    }
    pub fn summary(&self) -> BTreeMap<ResultKind, usize> {
        let mut counts = BTreeMap::new();
        for record in &self.records {
            *counts.entry(record.result).or_default() += 1;
        }
        counts
    }
    pub fn summary_line(&self) -> String {
        let counts = self.summary();
        format!(
            "{} pass, {} fail, {} kit-error, {} skipped",
            counts.get(&ResultKind::Pass).unwrap_or(&0),
            counts.get(&ResultKind::Fail).unwrap_or(&0),
            counts.get(&ResultKind::KitError).unwrap_or(&0),
            counts.get(&ResultKind::Skipped).unwrap_or(&0)
        )
    }
}
