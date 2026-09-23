use super::{MvpResult, MvpRun};
use std::fmt::Write;

impl MvpRun {
    /// Offline view of the report data. Rendering makes no compatibility claim.
    pub fn render_html(&self) -> String {
        let mut out = String::from(
            "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Morphir MCK package report</title><style>",
        );
        out.push_str(include_str!("../../report/html.css"));
        out.push_str("</style></head><body><a class=\"skip-link\" href=\"#records\">Skip to records</a><main><header><p class=\"eyebrow\">MORPHIR / COMPATIBILITY KIT</p><h1>MVP local Library report</h1>");
        write!(out, "<p class=\"muted\">{} · Report draft <code>{}</code> · Started <time>{}</time></p></header>", escape(&self.profile), escape(&self.contract_version), escape(&self.started_at)).unwrap();
        let (passes, failures, errors) =
            self.records
                .iter()
                .fold((0, 0, 0), |(p, f, e), record| match record.result {
                    MvpResult::Pass => (p + 1, f, e),
                    MvpResult::Fail => (p, f + 1, e),
                    MvpResult::KitError => (p, f, e + 1),
                });
        write!(out, "<section class=\"overview\" aria-label=\"Run overview\"><div class=\"run-state\"><h2>Required inventory</h2><p class=\"count\">{} required cases</p><p>{passes} pass, {failures} fail, {errors} kit-error</p></div><div class=\"totals\"><h2>Run context</h2><p>Scope: {}</p><p>Kit hash: <code>{}</code></p><p>Adapter: {}</p></div></section>", self.records.len(), escape(&self.scope), escape(&self.kit_hash), self.testee.as_ref().map_or_else(|| "Unavailable".into(), |caps| escape(&caps.implementation))).unwrap();
        if let Some(error) = &self.adapter_error {
            write!(out, "<section class=\"attention\"><h2>Adapter session failed</h2><p class=\"message\">{}</p></section>", escape(error)).unwrap();
        }
        out.push_str("<details class=\"provenance\"><summary>Driver, adapter command and capabilities</summary><div class=\"detail-body\"><dl>");
        field(
            &mut out,
            "Driver",
            &format!("{} {}", self.driver.name, self.driver.version),
        );
        field(
            &mut out,
            "Commit",
            self.driver.commit.as_deref().unwrap_or("Not recorded"),
        );
        field(
            &mut out,
            "Dirty",
            if self.driver.dirty { "yes" } else { "no" },
        );
        field(
            &mut out,
            "Request timeout",
            &format!("{} ms", self.adapter.request_timeout_ms),
        );
        field(
            &mut out,
            "Session timeout",
            &format!("{} ms", self.adapter.session_timeout_ms),
        );
        out.push_str("</dl><h3>Adapter command</h3><ol class=\"command\">");
        for arg in &self.adapter.command {
            write!(out, "<li><code>{}</code></li>", escape(arg)).unwrap();
        }
        out.push_str("</ol><h3>Negotiated capabilities</h3>");
        if let Some(caps) = &self.testee {
            let text = serde_json::to_string_pretty(caps).expect("capabilities serialize");
            write!(out, "<pre>{}</pre>", escape(&text)).unwrap();
        } else {
            out.push_str("<p>Unavailable. Negotiation failed.</p>");
        }
        out.push_str("</div></details><section id=\"records\"><div class=\"section-heading\"><h2>Required cases</h2></div><div class=\"table-scroll\"><table><thead><tr><th scope=\"col\">Result</th><th scope=\"col\">Case</th><th scope=\"col\">Diagnostic</th></tr></thead><tbody>");
        for record in &self.records {
            let result = match record.result {
                MvpResult::Pass => "pass",
                MvpResult::Fail => "fail",
                MvpResult::KitError => "kit-error",
            };
            write!(out, "<tr><td><span class=\"badge {result}\">{result}</span></td><td><code>{}</code></td><td class=\"message\">{}</td></tr>", escape(&record.case_id), escape(record.message.as_deref().unwrap_or(""))).unwrap();
        }
        out.push_str("</tbody></table></div></section><footer><p>JSON is authoritative. Rendering does not check the independent inventory.</p></footer></main></body></html>\n");
        out
    }
}

fn field(out: &mut String, name: &str, value: &str) {
    write!(out, "<dt>{}</dt><dd>{}</dd>", escape(name), escape(value)).unwrap();
}

fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
