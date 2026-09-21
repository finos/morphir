//! Offline presentation of an already validated draft report. This module does
//! not inspect kit inventory, baselines, or compatibility policy.

use std::collections::{BTreeSet, HashMap};
use std::fmt::Write;

use super::draft::{DraftReport, Negotiation, Selection, Session, SessionPhase};
use super::{Outcome, Record, RecordProfile, Role};

/// Render a complete standalone document. Report data only enters escaped HTML
/// text and quoted attributes; the embedded script is fixed and contains no data.
pub fn render(report: &DraftReport) -> String {
    let groups = cases(&report.records);
    let mut out = String::from(
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Morphir MCK report</title><style>",
    );
    out.push_str(include_str!("html.css"));
    out.push_str("</style></head><body><a class=\"skip-link\" href=\"#records\">Skip to records</a><main><header><p class=\"eyebrow\">MORPHIR / COMPATIBILITY KIT</p><h1>IR run report</h1>");
    let binding = match &report.adapter.negotiation {
        Negotiation::Succeeded { capabilities } => capabilities.as_capabilities().binding.as_str(),
        Negotiation::Failed { .. } => "Binding unavailable",
    };
    write!(out, "<p class=\"binding\">{}</p><p class=\"muted\">Started <time>{}</time> <span class=\"separator\">/</span> Report draft <code>{}</code></p></header>", escape(binding), escape(&report.started_at), escape(&report.contract_version)).unwrap();
    out.push_str(
        "<section class=\"overview\" aria-label=\"Run overview\"><div class=\"run-state\">",
    );
    match &report.execution.session {
        Session::Finished => out.push_str("<p class=\"status finished\">Session finished</p><p>The adapter session completed. Record outcomes are shown separately.</p>"),
        Session::Failed { .. } => out.push_str("<p class=\"status fail\">Session failed</p><p>The adapter session reported errors, regardless of individual record outcomes.</p>"),
    }
    match &report.selection {
        Selection::All => out.push_str("<p><strong>All cases selected</strong></p>"),
        Selection::Filter { pattern, .. } => {
            write!(out, "<p><strong>Filtered selection</strong> <span class=\"muted\">rust-regex</span><br><code>{}</code></p>", escape(pattern)).unwrap();
        }
    }
    write!(out, "</div><div class=\"totals\"><p class=\"count\">{} unique cases <span>/</span> {} records</p><p class=\"muted\">Full report totals</p><div class=\"outcomes\">", groups.len(), report.records.len()).unwrap();
    let summary = report.summary();
    for (label, count) in [
        ("pass", summary.pass),
        ("fail", summary.fail),
        ("kit-error", summary.kit_error),
        ("skipped", summary.skipped),
    ] {
        write!(out, "<span class=\"badge {label}\">{count} {label}</span>").unwrap();
    }
    out.push_str("</div></div></section>");
    attention(&mut out, report);
    provenance(&mut out, report);
    out.push_str("<section id=\"records\" aria-labelledby=\"records-heading\"><div class=\"section-heading\"><h2 id=\"records-heading\">Case records</h2><span class=\"muted\">Original order within each case</span></div>");
    filters(&mut out, report);
    write!(out, "<p id=\"shown-count\" role=\"status\" aria-live=\"polite\">Showing {} of {} records across {} of {} cases.</p>", report.records.len(), report.records.len(), groups.len(), groups.len()).unwrap();
    out.push_str("<p id=\"no-matches\" hidden>No records match these browser filters. Clear filters to see the full report.</p>");
    if groups.is_empty() {
        out.push_str("<p class=\"empty\">No records were reported. This does not establish compatibility or coverage.</p>");
    }
    for (case_index, (id, records)) in groups.iter().enumerate() {
        write!(out, "<section class=\"case\" aria-labelledby=\"case-{case_index}\"><h3 id=\"case-{case_index}\"><code>{}</code> <span class=\"muted\">{} records</span></h3><div class=\"table-scroll\"><table><caption class=\"sr-only\">Records for {}</caption><thead><tr><th scope=\"col\">Outcome</th><th scope=\"col\">IR</th><th scope=\"col\">Profile</th><th scope=\"col\">Role</th><th scope=\"col\">Fence</th><th scope=\"col\">Path</th><th scope=\"col\">Duration</th><th scope=\"col\">Diagnostics</th></tr></thead><tbody>", escape(id), records.len(), escape(id)).unwrap();
        for &(index, record) in records {
            record_row(&mut out, index, record);
        }
        out.push_str("</tbody></table></div></section>");
    }
    out.push_str("</section><footer><p>The JSON report remains authoritative. This page presents its recorded results.</p><p>Inventory and baseline not checked by this view.</p></footer></main><script>");
    out.push_str(include_str!("html.js"));
    out.push_str("</script></body></html>\n");
    out
}

fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

type CaseRecords<'a> = Vec<(&'a str, Vec<(usize, &'a Record)>)>;

fn cases(records: &[Record]) -> CaseRecords<'_> {
    let mut groups: CaseRecords<'_> = Vec::new();
    let mut indices = HashMap::new();
    for (index, record) in records.iter().enumerate() {
        let group = *indices.entry(record.case_id.as_str()).or_insert_with(|| {
            groups.push((record.case_id.as_str(), Vec::new()));
            groups.len() - 1
        });
        groups[group].1.push((index, record));
    }
    groups
}

fn attention(out: &mut String, report: &DraftReport) {
    let failures = report
        .records
        .iter()
        .enumerate()
        .filter(|(_, r)| matches!(r.result, Outcome::Fail | Outcome::KitError))
        .collect::<Vec<_>>();
    let failed_session = matches!(report.execution.session, Session::Failed { .. });
    if failures.is_empty() && !failed_session {
        out.push_str("<section class=\"attention quiet\" aria-label=\"Attention summary\"><h2>Attention summary</h2><p>No failing records or session errors were reported.</p></section>");
        return;
    }
    out.push_str("<section class=\"attention\" aria-labelledby=\"attention-heading\"><h2 id=\"attention-heading\">Needs attention</h2><ul>");
    if failed_session {
        out.push_str("<li><a href=\"#session-errors\">Session errors</a></li>");
    }
    for (index, record) in failures {
        write!(
            out,
            "<li><a href=\"#record-{index}\">{} · {} · fence {} · {}</a></li>",
            escape(&record.case_id),
            record.result.as_str(),
            record.fence_index,
            record.path.map_or("unspecified", |p| p.as_str())
        )
        .unwrap();
    }
    out.push_str("</ul>");
    if let Session::Failed { errors } = &report.execution.session {
        out.push_str("<div id=\"session-errors\"><h3>Session errors</h3><dl>");
        for error in errors {
            let phase = match error.phase {
                SessionPhase::Spawn => "spawn",
                SessionPhase::Capabilities => "capabilities",
                SessionPhase::Exchange => "exchange",
                SessionPhase::Shutdown => "shutdown",
            };
            field(out, phase, &error.message);
        }
        out.push_str("</dl></div>");
    }
    if let Negotiation::Failed { message } = &report.adapter.negotiation {
        write!(
            out,
            "<h3>Negotiation failed</h3><p class=\"message\">{}</p>",
            escape(message)
        )
        .unwrap();
    }
    out.push_str("</section>");
}

fn field(out: &mut String, name: &str, value: &str) {
    write!(out, "<dt>{}</dt><dd>{}</dd>", escape(name), escape(value)).unwrap();
}

fn provenance(out: &mut String, report: &DraftReport) {
    out.push_str("<details class=\"provenance\"><summary>Provenance, adapter command and capabilities</summary><div class=\"detail-body\"><h3>Driver and kit</h3><dl>");
    field(
        out,
        "Driver",
        &format!("{} {}", report.driver.name, report.driver.version),
    );
    field(
        out,
        "Driver commit",
        report.driver.commit.as_deref().unwrap_or("Not recorded"),
    );
    field(
        out,
        "Driver dirty",
        if report.driver.dirty { "yes" } else { "no" },
    );
    field(out, "Kit version", &report.kit.version);
    field(
        out,
        "Kit source",
        match report.kit.source {
            super::draft::KitSource::Embedded => "embedded",
            super::draft::KitSource::Vendored => "vendored",
            super::draft::KitSource::Local => "local",
        },
    );
    field(
        out,
        "Kit revision",
        report.kit.revision.as_deref().unwrap_or("Not recorded"),
    );
    field(
        out,
        "Snapshot digest",
        report
            .kit
            .snapshot_digest
            .as_deref()
            .unwrap_or("Not recorded"),
    );
    field(
        out,
        "Corpus hash",
        report.kit.corpus_hash.as_deref().unwrap_or("Not recorded"),
    );
    field(
        out,
        "Kit modified",
        if report.kit.modified { "yes" } else { "no" },
    );
    field(
        out,
        "Strict execution",
        if report.execution.strict { "yes" } else { "no" },
    );
    out.push_str("</dl><h3>Adapter command</h3><p class=\"muted\">Arguments in recorded order</p><ol class=\"command\">");
    for arg in &report.adapter.command {
        write!(out, "<li><code>{}</code></li>", escape(arg)).unwrap();
    }
    out.push_str("</ol><h3>Negotiated capabilities</h3>");
    match &report.adapter.negotiation {
        Negotiation::Succeeded { capabilities } => {
            // JSON is displayed only as escaped text in a pre element, never in script.
            let text = serde_json::to_string_pretty(capabilities).expect("capabilities serialize");
            write!(out, "<pre>{}</pre>", escape(&text)).unwrap();
        }
        Negotiation::Failed { .. } => out.push_str("<p>Unavailable. Negotiation failed.</p>"),
    }
    out.push_str("</div></details>");
}

fn filters(out: &mut String, report: &DraftReport) {
    out.push_str("<form id=\"filters\" hidden><div class=\"filter-grid\"><label for=\"case-search\">Case search<input type=\"search\" id=\"case-search\" placeholder=\"Search case IDs\"></label>");
    select(
        out,
        "outcome-filter",
        "Outcome",
        &["pass", "fail", "kit-error", "skipped"],
    );
    let versions = report
        .records
        .iter()
        .map(|r| r.ir_version)
        .collect::<BTreeSet<_>>()
        .into_iter()
        .map(|v| v.to_string())
        .collect::<Vec<_>>();
    select(
        out,
        "ir-filter",
        "IR version",
        &versions.iter().map(String::as_str).collect::<Vec<_>>(),
    );
    select(out, "profile-filter", "Profile", &["json", "yaml", "tree"]);
    select(
        out,
        "path-filter",
        "Path",
        &["current", "pinned", "unspecified"],
    );
    out.push_str("</div><div class=\"filter-actions\"><button type=\"reset\">Clear filters</button><button type=\"button\" id=\"expand-details\">Expand diagnostics</button><button type=\"button\" id=\"collapse-details\">Collapse diagnostics</button></div></form><p class=\"muted\">Browser filters only change this view. They do not change the original run selection or full report totals.</p><noscript><p>JavaScript is disabled. All records are available below; browser filtering is unavailable.</p></noscript>");
}

fn select(out: &mut String, id: &str, label: &str, values: &[&str]) {
    write!(
        out,
        "<label for=\"{id}\">{label}<select id=\"{id}\"><option value=\"\">All</option>"
    )
    .unwrap();
    for value in values {
        write!(
            out,
            "<option value=\"{}\">{}</option>",
            escape(value),
            escape(value)
        )
        .unwrap();
    }
    out.push_str("</select></label>");
}

fn record_row(out: &mut String, index: usize, r: &Record) {
    let outcome = r.result.as_str();
    let profile = match r.profile {
        RecordProfile::Json => "json",
        RecordProfile::Yaml => "yaml",
        RecordProfile::Tree => "tree",
    };
    let role = match r.role {
        Role::Canonical => "canonical",
        Role::Accepted => "accepted",
        Role::Rejected => "rejected",
        Role::File => "file",
    };
    let path = r.path.map_or("unspecified", |p| p.as_str());
    write!(out, "<tr id=\"record-{index}\" data-case=\"{}\" data-outcome=\"{outcome}\" data-ir=\"{}\" data-profile=\"{profile}\" data-path=\"{path}\"><td><span class=\"badge {outcome}\">{outcome}</span></td><td>{}</td><td>{profile}</td><td>{role}</td><td>{}</td><td>{path}</td><td class=\"duration\">{} ms</td><td>", escape(&r.case_id), r.ir_version, r.ir_version, r.fence_index, r.duration_ms.0).unwrap();
    if r.expected_diagnostic.is_none() && r.observed_diagnostic.is_none() && r.message.is_none() {
        out.push_str("<span class=\"muted\">None recorded</span>");
    } else {
        out.push_str("<details class=\"diagnostic\"><summary>View details</summary><div class=\"detail-body\"><dl>");
        field(
            out,
            "Expected code",
            r.expected_diagnostic.as_deref().unwrap_or("Not recorded"),
        );
        if let Some(diagnostic) = &r.observed_diagnostic {
            field(out, "Observed code", &diagnostic.code);
            field(
                out,
                "Observed stage",
                diagnostic.stage.map_or("Not recorded", |s| s.as_str()),
            );
            field(
                out,
                "Observed cursor",
                diagnostic.cursor.as_deref().unwrap_or("Not recorded"),
            );
            field(
                out,
                "Observed message",
                diagnostic.message.as_deref().unwrap_or("Not recorded"),
            );
        } else {
            field(out, "Observed diagnostic", "Not recorded");
        }
        field(
            out,
            "Runner message",
            r.message.as_deref().unwrap_or("Not recorded"),
        );
        out.push_str("</dl></div></details>");
    }
    out.push_str("</td></tr>");
}
