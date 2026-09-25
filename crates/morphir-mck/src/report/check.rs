//! Independent inventory and baseline adjudication for a validated report.
use std::collections::{BTreeSet, HashSet};

use serde::Deserialize;

use super::Outcome;
use super::draft::{DraftReport, Negotiation, Selection, Session};
use crate::ir::run::inventory;
use crate::kit::Kit;
use crate::kit::manifest::LockSource;
use crate::kit::snapshot::collect;

#[derive(Debug, Clone)]
pub struct AllowedFailures(BTreeSet<String>);

impl AllowedFailures {
    pub fn cases(&self) -> &BTreeSet<String> {
        &self.0
    }
    pub fn from_json(text: &str) -> Result<Self, String> {
        #[derive(Deserialize)]
        struct Input {
            cases: Vec<String>,
        }
        let input: Input =
            serde_json::from_str(text).map_err(|e| format!("invalid allowed-failing file: {e}"))?;
        let mut cases = BTreeSet::new();
        let case_id = regex::Regex::new("^[a-z][a-z0-9-]*-[0-9]{4}$").expect("case id pattern");
        for case in input.cases {
            if !case_id.is_match(&case) {
                return Err(format!("invalid allowed case id {case}"));
            }
            if !cases.insert(case.clone()) {
                return Err(format!("duplicate allowed case id {case}"));
            }
        }
        Ok(Self(cases))
    }
}

#[derive(Debug, PartialEq, Eq)]
pub struct CheckedReport {
    pub selected_cases: usize,
    pub records: usize,
    pub allowed_failures: usize,
    pub filtered: bool,
}

pub fn check(
    report: &DraftReport,
    kit: &Kit,
    allowed: &AllowedFailures,
    filter: Option<&str>,
) -> Result<CheckedReport, String> {
    let selection_matches = match (&report.selection, filter) {
        (Selection::All, None) => true,
        (Selection::Filter { pattern, .. }, Some(expected)) => pattern == expected,
        _ => false,
    };
    if !selection_matches {
        return Err("report selection does not match the independently requested scope".into());
    }
    let filter = filter
        .map(regex::Regex::new)
        .transpose()
        .map_err(|e| format!("invalid selection filter: {e}"))?;
    if !matches!(report.execution.session, Session::Finished) {
        return Err(
            "adapter session failed; case allowances cannot waive a session failure".into(),
        );
    }
    let Negotiation::Succeeded { capabilities } = &report.adapter.negotiation else {
        return Err("adapter capabilities were not negotiated".into());
    };
    let snapshot =
        collect(kit).map_err(|e| format!("cannot establish kit snapshot digest: {e}"))?;
    let lock = snapshot.lock(LockSource::Local { revision: None });
    if report.kit.snapshot_digest.as_deref() != Some(lock.snapshot_digest.as_str()) {
        return Err(
            "report kit snapshot digest does not match the independently loaded kit".into(),
        );
    }
    let expected = inventory(kit, capabilities.as_capabilities(), filter.as_ref());
    if expected.len() != report.records.len() {
        return Err(format!(
            "record inventory count: expected {}, found {}",
            expected.len(),
            report.records.len()
        ));
    }
    let mut ordinary_identities = HashSet::new();
    for (index, (entry, record)) in expected.iter().zip(&report.records).enumerate() {
        if !entry.matches(record) {
            return Err(format!(
                "record inventory differs at index {index}: expected {} fence {} {:?}",
                entry.case_id, entry.fence_index, entry.path
            ));
        }
        if let Some(error) = &entry.kit_error
            && (record.result != Outcome::KitError || record.message.as_ref() != Some(error))
        {
            return Err(format!("kit-error inventory differs at index {index}"));
        }
        if entry.kit_error.is_none()
            && !ordinary_identities.insert((
                &record.case_id,
                record.ir_version,
                record.profile,
                record.role,
                record.fence_index,
                record.path,
            ))
        {
            return Err(format!(
                "duplicate ordinary record inventory at index {index}"
            ));
        }
        if (record.result == Outcome::Skipped) != entry.skip.is_some()
            || (entry.skip.is_some() && record.message != entry.skip)
        {
            return Err(format!(
                "illegitimate skip at {} fence {}",
                record.case_id, record.fence_index
            ));
        }
    }
    let selected: BTreeSet<_> = kit
        .cases
        .iter()
        .filter(|c| filter.as_ref().is_none_or(|f| f.is_match(c.id.as_str())))
        .map(|c| c.id.as_str())
        .collect();
    if selected.is_empty() {
        return Err("no cases selected".into());
    }
    if !report.records.iter().any(|r| r.result == Outcome::Pass) {
        return Err("report has no passing record".into());
    }
    for id in &allowed.0 {
        if id != "kit-0000" && !kit.cases.iter().any(|c| c.id.as_str() == id) {
            return Err(format!("unknown allowed case id {id}"));
        }
    }
    let in_scope = |id: &str| {
        filter.is_none()
            || selected.contains(id)
            || expected
                .iter()
                .any(|e| e.kit_error.is_some() && e.case_id == id)
    };
    let scoped: BTreeSet<_> = allowed
        .0
        .iter()
        .filter(|id| in_scope(id))
        .map(String::as_str)
        .collect();
    let failing: BTreeSet<_> = report
        .records
        .iter()
        .filter(|r| matches!(r.result, Outcome::Fail | Outcome::KitError))
        .map(|r| r.case_id.as_str())
        .collect();
    let regressions: Vec<_> = failing.difference(&scoped).copied().collect();
    let stale: Vec<_> = scoped.difference(&failing).copied().collect();
    if !regressions.is_empty() || !stale.is_empty() {
        return Err(format!(
            "baseline mismatch; regressions: {regressions:?}; stale entries: {stale:?}"
        ));
    }
    Ok(CheckedReport {
        selected_cases: selected.len(),
        records: report.records.len(),
        allowed_failures: scoped.len(),
        filtered: filter.is_some(),
    })
}
