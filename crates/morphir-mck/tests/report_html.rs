use morphir_mck::report::{draft::DraftReport, html::render};
use serde_json::{Value, json};

fn example() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/ir/mck/report-draft.example.json"
    ))
    .unwrap()
}

fn html(value: Value) -> String {
    render(&DraftReport::from_value(value).unwrap())
}

#[test]
fn mixed_records_count_cases_separately_and_preserve_case_and_record_order() {
    let mut value = example();
    let mut records = Vec::new();
    for (case, result, fence) in [
        ("z-case-0001", "pass", 0),
        ("a-case-0001", "fail", 1),
        ("z-case-0001", "kit-error", 2),
        ("a-case-0001", "skipped", 3),
    ] {
        let mut record = value["records"][0].clone();
        record["caseId"] = json!(case);
        record["result"] = json!(result);
        record["fenceIndex"] = json!(fence);
        records.push(record);
    }
    value["records"] = json!(records);
    let output = html(value);
    assert!(output.contains("2 unique cases"));
    assert!(output.contains("4 records"));
    for result in ["pass", "fail", "kit-error", "skipped"] {
        assert!(output.contains(&format!("1 {result}")));
    }
    assert!(output.contains("href=\"#record-1\""));
    assert!(output.contains("href=\"#record-2\""));
    assert!(output.find("id=\"record-0\"").unwrap() < output.find("id=\"record-2\"").unwrap());
    assert!(output.find("id=\"record-2\"").unwrap() < output.find("id=\"record-1\"").unwrap());
    assert!(output.contains("Session finished"));
    assert!(output.contains("Inventory and baseline not checked by this view"));
}

#[test]
fn shutdown_failure_stays_visible_even_when_all_records_pass() {
    let mut value = example();
    value["execution"]["session"] = json!({"status":"failed","errors":[{"phase":"shutdown","message":"adapter exit status 12"}]});
    let output = html(value);
    assert!(output.contains("Session failed"));
    assert!(output.contains("shutdown"));
    assert!(output.contains("adapter exit status 12"));
    assert!(output.contains("1 pass"));
    assert!(output.contains("href=\"#session-errors\""));
}

#[test]
fn failed_negotiation_and_filtered_empty_selection_are_explicit() {
    let mut value = example();
    value["adapter"]["negotiation"] =
        json!({"status":"failed","message":"No capabilities received"});
    value["execution"]["session"] =
        json!({"status":"failed","errors":[{"phase":"capabilities","message":"Unexpected EOF"}]});
    value["selection"] = json!({"kind":"filter","syntax":"rust-regex","pattern":"^missing$"});
    value["records"] = json!([]);
    let output = html(value);
    for text in [
        "Binding unavailable",
        "Negotiation failed",
        "No capabilities received",
        "Unexpected EOF",
        "Filtered selection",
        "^missing$",
        "0 unique cases",
        "0 records",
        "No records were reported",
    ] {
        assert!(output.contains(text), "missing {text}");
    }
}

#[test]
fn diagnostics_and_runner_messages_are_available_without_javascript() {
    let mut value = example();
    value["records"][0]["expectedDiagnostic"] = json!("EXPECTED_CODE");
    value["records"][0]["observedDiagnostic"] = json!({"code":"OBSERVED_CODE","stage":"semantic","cursor":"$.payload[3]","message":"Observed detail"});
    value["records"][0]["message"] = json!("Runner detail");
    let output = html(value);
    for text in [
        "Expected code",
        "EXPECTED_CODE",
        "Observed code",
        "OBSERVED_CODE",
        "semantic",
        "$.payload[3]",
        "Observed detail",
        "Runner detail",
        "canonical",
        "current",
        "0.5 ms",
        "morphir-adapter",
        "--stdio",
        "2.0.0-draft.1",
        "2026-09-20T10:30:00.000Z",
    ] {
        assert!(output.contains(text), "missing {text}");
    }
    assert!(output.contains("<details"));
    assert!(output.contains("<dt>Check</dt><dd>semantic</dd>"));
    assert!(output.contains("<table"));
}

#[test]
fn optional_diff_and_check_render_safely_in_static_details() {
    let mut value = example();
    value["records"][0]["check"] = json!("round-trip");
    value["records"][0]["diff"] = json!("--- expected\n-old <script>\n+new & value\n");
    let output = html(value);
    assert!(output.contains("round-trip"));
    assert!(output.contains("class=\"diff-remove\""));
    assert!(output.contains("class=\"diff-add\""));
    assert!(output.contains("&lt;script&gt;"));
    assert!(output.contains("&amp; value"));
    assert!(!output.contains("-old <script>"));
}

#[test]
fn hostile_strings_remain_inert_and_unicode_is_preserved() {
    let mut value = example();
    let attack = "</script><img src=x onerror='alert(1)'> & \"雪 λ\"";
    value["adapter"]["command"] = json!([attack]);
    value["records"][0]["message"] = json!(attack);
    value["records"][0]["observedDiagnostic"] =
        json!({"code":attack,"cursor":attack,"message":attack});
    let output = html(value);
    assert!(!output.contains(attack));
    assert!(output.contains(
        "&lt;/script&gt;&lt;img src=x onerror=&#39;alert(1)&#39;&gt; &amp; &quot;雪 λ&quot;"
    ));
    assert_eq!(output.matches("<script>").count(), 1);
    assert_eq!(output.matches("</script>").count(), 1);
    let script = output
        .split("<script>")
        .nth(1)
        .unwrap()
        .split("</script>")
        .next()
        .unwrap();
    assert!(!script.contains("雪"));
    assert!(!script.contains("innerHTML"));
    assert!(!script.contains("fetch("));
}

#[test]
fn offline_document_has_labeled_filters_and_full_static_content() {
    let output = html(example());
    assert!(output.starts_with("<!doctype html>"));
    assert!(output.contains("<html lang=\"en\">"));
    assert!(!output.contains("<link"));
    assert!(!output.contains("src=\"http"));
    for id in [
        "case-search",
        "outcome-filter",
        "ir-filter",
        "profile-filter",
        "path-filter",
    ] {
        assert!(output.contains(&format!("for=\"{id}\"")));
        assert!(output.contains(&format!("id=\"{id}\"")));
    }
    assert!(output.contains("Browser filters only change this view"));
    assert!(output.contains("JSON report remains authoritative"));
    assert!(output.contains("Showing 1 of 1 records"));
    assert!(output.contains("@media print"));
}
