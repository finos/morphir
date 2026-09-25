//! Metadata records in the production consolidated report envelope.
use std::collections::BTreeSet;

use regex::Regex;
use serde_json::{Value, json};

use super::run::{MetadataRun, valid_capabilities};
use crate::kit::Kit;
use crate::kit::manifest::LockSource;
use crate::kit::snapshot::collect;
use crate::report::check::AllowedFailures;
use crate::report::draft;

pub struct MetadataReport(Value);

pub fn render(report: &MetadataReport) -> String {
    fn escape(value: &str) -> String {
        value.chars().fold(String::new(), |mut out, ch| {
            out.push_str(match ch {
                '&' => "&amp;",
                '<' => "&lt;",
                '>' => "&gt;",
                '"' => "&quot;",
                '\'' => "&#39;",
                _ => {
                    out.push(ch);
                    return out;
                }
            });
            out
        })
    }
    let mut html = String::from(
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Morphir MCK metadata report</title></head><body><main><h1>Metadata compatibility report</h1>",
    );
    html.push_str(&format!("<p>{}</p><ol>", escape(&report.summary_line())));
    if let Some(records) = report.value()["records"].as_array() {
        for record in records {
            html.push_str(&format!(
                "<li><strong>{}</strong>: {}",
                escape(record["caseId"].as_str().unwrap_or_default()),
                escape(record["result"].as_str().unwrap_or_default())
            ));
            if let Some(message) = record["message"].as_str() {
                html.push_str(&format!(" — {}", escape(message)));
            }
            html.push_str("</li>");
        }
    }
    html.push_str("</ol></main></body></html>\n");
    html
}

impl MetadataReport {
    pub fn from_json(text: &str) -> Result<Self, String> {
        let value: Value = serde_json::from_str(text).map_err(|e| e.to_string())?;
        Self::from_value(value)
    }

    pub fn from_value(value: Value) -> Result<Self, String> {
        draft::validate_schema(&value).map_err(|e| e.to_string())?;
        if value["suite"] != "metadata" {
            return Err("metadata suite report required".into());
        }
        if value["adapter"]["negotiation"]["status"] == "succeeded" {
            valid_capabilities(&value["adapter"]["negotiation"]["capabilities"])?;
        } else if value["adapter"]["negotiation"]["status"] != "failed" {
            return Err("invalid adapter negotiation".into());
        }
        let negotiation_failed = value["adapter"]["negotiation"]["status"] == "failed";
        let session_has_negotiation_error = value["execution"]["session"]["errors"]
            .as_array()
            .is_some_and(|errors| {
                errors
                    .iter()
                    .any(|error| error["phase"] == "spawn" || error["phase"] == "capabilities")
            });
        if negotiation_failed != session_has_negotiation_error {
            return Err("adapter negotiation and execution session disagree".into());
        }
        if negotiation_failed
            && value["records"]
                .as_array()
                .is_some_and(|records| records.iter().any(|record| record["result"] != "kit-error"))
        {
            return Err("failed negotiation permits only kit-error metadata records".into());
        }
        Ok(Self(value))
    }

    pub fn value(&self) -> &Value {
        &self.0
    }

    pub fn to_json(&self) -> String {
        format!("{}\n", crate::json::to_tab_json(&self.0))
    }

    pub fn summary_line(&self) -> String {
        let count = |kind: &str| {
            self.0["records"]
                .as_array()
                .into_iter()
                .flatten()
                .filter(|r| r["result"] == kind)
                .count()
        };
        format!(
            "{} pass, {} fail, {} kit-error, {} skipped",
            count("pass"),
            count("fail"),
            count("kit-error"),
            count("skipped")
        )
    }
}

pub fn assemble(
    run: &MetadataRun,
    kit: Value,
    command: Vec<String>,
    filter: Option<&str>,
    strict: bool,
    started_at: &str,
    failures: (Option<&str>, Option<&str>),
) -> Result<MetadataReport, String> {
    let (spawn_error, shutdown_error) = failures;
    let negotiation = match &run.capabilities {
        Some(caps) => json!({"status":"succeeded","capabilities":caps["capabilities"]}),
        None => {
            json!({"status":"failed","message":run.failure.as_deref().unwrap_or("adapter negotiation failed")})
        }
    };
    let mut errors = Vec::new();
    if let Some(message) = spawn_error {
        errors.push(json!({"phase":"spawn","message":message}));
    } else if let Some(message) = &run.failure {
        errors.push(json!({"phase":if run.capabilities.is_some() {"exchange"} else {"capabilities"},"message":message}));
    }
    if let Some(message) = shutdown_error {
        errors.push(json!({"phase":"shutdown","message":message}));
    }
    let session = if errors.is_empty() {
        json!({"status":"finished"})
    } else {
        json!({"status":"failed","errors":errors})
    };
    let selection = filter.map_or(
        json!({"kind":"all"}),
        |pattern| json!({"kind":"filter","syntax":"rust-regex","pattern":pattern}),
    );
    MetadataReport::from_value(json!({
        "contractVersion":draft::CONTRACT_VERSION,"suite":"metadata","startedAt":started_at,
        "driver":crate::provenance::Driver::current(),"kit":kit,
        "adapter":{"command":command,"negotiation":negotiation},
        "selection":selection,"execution":{"strict":strict,"session":session},"records":run.records,
    }))
}

pub fn check(
    report: &MetadataReport,
    kit: &Kit,
    allowed: &AllowedFailures,
    filter: Option<&str>,
) -> Result<crate::report::check::CheckedReport, String> {
    let value = report.value();
    match filter {
        Some(pattern)
            if value["selection"]
                != json!({"kind":"filter","syntax":"rust-regex","pattern":pattern}) =>
        {
            return Err("report selection does not match the independently requested scope".into());
        }
        None if value["selection"] != json!({"kind":"all"}) => {
            return Err("report selection does not match the independently requested scope".into());
        }
        _ => {}
    }
    if value["execution"]["session"]["status"] != "finished" {
        return Err(
            "adapter session failed; case allowances cannot waive a session failure".into(),
        );
    }
    if value["adapter"]["negotiation"]["status"] != "succeeded" {
        return Err("adapter capabilities were not negotiated".into());
    }
    let snapshot = collect(kit).map_err(|e| e.to_string())?;
    let lock = snapshot.lock(LockSource::Local { revision: None });
    if value["kit"]["snapshotDigest"] != lock.snapshot_digest.as_str() {
        return Err(
            "report kit snapshot digest does not match the independently loaded kit".into(),
        );
    }
    let source = kit
        .source
        .read("spec/ir/mck/metadata-contract-draft.json")
        .map_err(|e| e.to_string())?
        .ok_or("missing metadata corpus")?;
    let corpus: Value = serde_json::from_slice(&source).map_err(|e| e.to_string())?;
    let all_cases = corpus["cases"].as_array().ok_or("missing metadata cases")?;
    let all_ids = all_cases
        .iter()
        .filter_map(|case| case["id"].as_str())
        .collect::<BTreeSet<_>>();
    for id in allowed.cases() {
        if !all_ids.contains(id.as_str()) {
            return Err(format!("unknown allowed metadata case id {id}"));
        }
    }
    let regex = filter
        .map(Regex::new)
        .transpose()
        .map_err(|e| e.to_string())?;
    let selected = all_cases
        .iter()
        .filter(|case| {
            regex
                .as_ref()
                .is_none_or(|f| f.is_match(case["id"].as_str().unwrap_or_default()))
        })
        .collect::<Vec<_>>();
    if selected.is_empty() {
        return Err("no cases selected".into());
    }
    let records = value["records"].as_array().ok_or("missing records")?;
    if records.len() != selected.len() {
        return Err("metadata record inventory count differs".into());
    }
    let capabilities = &value["adapter"]["negotiation"]["capabilities"];
    let mut failing = BTreeSet::new();
    let mut passing = false;
    for (case, record) in selected.iter().zip(records) {
        if record["caseId"] != case["id"]
            || record["operation"] != case["operation"]
            || record["targets"] != case["targets"]
        {
            return Err(format!(
                "metadata record identity differs at {}",
                case["id"]
            ));
        }
        let supported = super::run::claims_case(capabilities, case);
        if supported == (record["result"] == "skipped") {
            return Err(format!("illegitimate metadata skip at {}", case["id"]));
        }
        if !supported && record["message"] != "unsupported metadata target tuple" {
            return Err(format!("metadata skip reason differs at {}", case["id"]));
        }
        if record["result"] == "pass" {
            passing = true;
        }
        if record["result"] == "fail" || record["result"] == "kit-error" {
            failing.insert(case["id"].as_str().unwrap_or_default());
        }
    }
    if !passing {
        return Err("report has no passing metadata record".into());
    }
    let selected_ids = selected
        .iter()
        .filter_map(|case| case["id"].as_str())
        .collect::<BTreeSet<_>>();
    let scoped = allowed
        .cases()
        .iter()
        .map(String::as_str)
        .filter(|id| selected_ids.contains(id))
        .collect::<BTreeSet<_>>();
    if failing != scoped {
        return Err(format!(
            "metadata baseline mismatch; failing: {failing:?}; allowed: {scoped:?}"
        ));
    }
    Ok(crate::report::check::CheckedReport {
        selected_cases: selected.len(),
        records: records.len(),
        allowed_failures: scoped.len(),
        filtered: filter.is_some(),
    })
}
