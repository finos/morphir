//! Independently fixed capability boundaries for the connected draft.
use super::Capabilities;
use serde_json::{Value, json};

fn parse(version: &str, binding: &str, language: &str, operations: Value, formats: Value) -> bool {
    Capabilities::parse(
        json!({"suite":"workbench","contractVersion":version,"binding":binding,
            "language":language,"operations":operations,"formats":formats}),
        version,
    )
    .is_ok()
}

fn connected(binding: &str, language: &str) -> bool {
    parse(
        "0.1.0-draft.30",
        binding,
        language,
        json!(["model-originals-server"]),
        json!(["json"]),
    )
}

#[test]
fn connected_capabilities_bound_both_identities_by_exact_utf8_bytes() {
    // Expectations use fixed Unicode scalar widths, not decoder output.
    for (text, bytes, accepted) in [
        ("a".repeat(128), 128, true),
        ("a".repeat(129), 129, false),
        ("é".repeat(64), 128, true),
        (format!("{}a", "é".repeat(64)), 129, false),
        ("💫".repeat(32), 128, true),
        (format!("{}a", "💫".repeat(32)), 129, false),
        (String::new(), 0, false),
    ] {
        assert_eq!(text.len(), bytes);
        assert_eq!(connected(&text, "rust"), accepted, "binding bytes={bytes}");
        assert_eq!(
            connected("actual-test-binding", &text),
            accepted,
            "language bytes={bytes}"
        );
    }
}

#[test]
fn connected_capabilities_require_a_nonempty_unique_closed_operation_subset_and_json() {
    for operations in [
        json!(["model-originals-server"]),
        json!(["model-originals-client"]),
        json!(["model-originals-client", "model-originals-server"]),
    ] {
        assert!(parse(
            "0.1.0-draft.30",
            "actual-test-binding",
            "rust",
            operations,
            json!(["json"])
        ));
    }
    for operations in [
        json!([]),
        json!(["model-originals-client", "model-originals-client"]),
        json!(["model-originals-server", "inspect-model"]),
        json!(["model-originals-server", "unknown"]),
    ] {
        assert!(!parse(
            "0.1.0-draft.30",
            "actual-test-binding",
            "rust",
            operations,
            json!(["json"])
        ));
    }
    for formats in [
        json!([]),
        json!(["ion-text"]),
        json!(["json", "ion-text"]),
        json!(["json", "json"]),
    ] {
        assert!(!parse(
            "0.1.0-draft.30",
            "actual-test-binding",
            "rust",
            json!(["model-originals-server"]),
            formats
        ));
    }
}

#[test]
fn connected_capabilities_reject_alias_versions_and_historical_operation_claims() {
    for version in [
        "0.1.0-draft.29",
        "0.1.0-draft.31",
        "0.1.0-draft.030",
        "0.1.0-draft.30+extra",
        "v0.1.0-draft.30",
        "0.1.0",
    ] {
        assert!(!parse(
            version,
            "actual-test-binding",
            "rust",
            json!(["model-originals-client"]),
            json!(["json"])
        ));
    }
    for operation in [
        "inspect-model",
        "export-model-original",
        "artifact-server",
        "artifact-client",
        "decode-value",
    ] {
        assert!(!parse(
            "0.1.0-draft.30",
            "actual-test-binding",
            "rust",
            json!([operation]),
            json!(["json"])
        ));
    }
}

#[test]
fn connected_identity_policy_does_not_change_historical_utf16_limits_or_empty_claims() {
    for (binding, language, accepted) in [
        ("a".repeat(256), "rust".to_owned(), true),
        ("a".repeat(257), "rust".to_owned(), false),
        ("é".repeat(256), "é".repeat(128), true),
        ("binding".to_owned(), "é".repeat(129), false),
    ] {
        assert_eq!(
            parse(
                "0.1.0-draft.29",
                &binding,
                &language,
                json!(["inspect-model"]),
                json!(["json"])
            ),
            accepted
        );
    }
    assert!(parse(
        "0.1.0-draft.29",
        "binding",
        "rust",
        json!([]),
        json!(["json"])
    ));
    assert!(!connected(&"é".repeat(128), "rust"));
}
