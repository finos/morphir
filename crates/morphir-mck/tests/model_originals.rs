//! Boundary tests for the shared checker, independent of any server or client.
use morphir_mck::workbench::model_originals::{Declaration, Parameters, ReadTarget, Request};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

fn capture() -> Value {
    json!({"jsonrpc":"2.0","id":1,"method":"morphir.model-originals.capture","params":{
        "contractVersion":"0.1.0-draft.1","source":{"providerId":"provider-A","locator":"workspace:orders"},
        "projectId":"[\"provider-A\",\"workspace:orders\",\"packages/orders\"]","scope":"complete","semantic":"projection"
    }})
}
fn read() -> Value {
    json!({"jsonrpc":"2.0","id":1,"method":"morphir.model-originals.read","params":{
        "contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":{"kind":"original","entryId":"entry-A"},"offset":0,"maxBytes":65536
    }})
}
#[test]
fn request_identity_preserves_maximum_u64_and_rejects_other_number_syntax() {
    let base = capture().to_string();
    let raw = base.replacen("\"id\":1", "\"id\":18446744073709551615", 1);
    assert_eq!(Request::parse(&raw).unwrap().id().get(), u64::MAX);
    for token in [
        "18446744073709551616",
        "1.0",
        "1e0",
        "-0",
        "-1",
        "null",
        "\"1\"",
    ] {
        let raw = base.replacen("\"id\":1", &format!("\"id\":{token}"), 1);
        assert!(Request::parse(&raw).is_err(), "accepted {token}");
    }
}
#[test]
fn raw_duplicate_members_and_private_number_marker_maps_never_become_authority() {
    for raw in [
        r#"{"jsonrpc":"2.0","id":1,"id":2,"method":"morphir.model-originals.release","params":{"contractVersion":"0.1.0-draft.1","captureId":"c"}}"#,
        r#"{"jsonrpc":"2.0","id":1,"method":"morphir.model-originals.release","params":{"contractVersion":"0.1.0-draft.1","captureId":"c","captureId":"d"}}"#,
        r#"{"jsonrpc":"2.0","id":{"$serde_json::private::Number":"1"},"method":"morphir.model-originals.release","params":{"contractVersion":"0.1.0-draft.1","captureId":"c"}}"#,
        r#"{"jsonrpc":"2.0","id":1,"method":"morphir.model-originals.release","params":{"contractVersion":"0.1.0-draft.1","captureId":"\ud800"}}"#,
    ] {
        assert!(Request::parse(raw).is_err());
    }
}
#[test]
fn identity_limits_measure_utf8_bytes_and_control_categories() {
    let mut frame = capture();
    frame["params"]["source"]["providerId"] = json!("é".repeat(64));
    assert!(Request::parse(&frame.to_string()).is_ok());
    frame["params"]["source"]["providerId"] = json!("é".repeat(65));
    assert!(Request::parse(&frame.to_string()).is_err());
    for id in ["", "bad\n", "bad\u{85}", "bad\u{7f}"] {
        frame["params"]["source"]["providerId"] = json!(id);
        assert!(Request::parse(&frame.to_string()).is_err());
    }
}
#[test]
fn methods_and_parameter_variants_are_closed_and_intention_revealing() {
    let request = Request::parse(&capture().to_string()).unwrap();
    assert!(matches!(request.parameters(), Parameters::Capture { .. }));
    let mut frame = capture();
    frame["method"] = json!("morphir.model-originals.read");
    assert!(Request::parse(&frame.to_string()).is_err());
    let mut frame = capture();
    frame["params"]["companions"] = json!([{"kind":"file","path":"outside"}]);
    assert!(Request::parse(&frame.to_string()).is_err());
    let mut frame = read();
    frame["params"]["target"] = json!({"kind":"semantic-projection"});
    assert!(matches!(
        Request::parse(&frame.to_string()).unwrap().parameters(),
        Parameters::Read {
            target: ReadTarget::SemanticProjection,
            ..
        }
    ));
    frame["params"]["target"]["entryId"] = json!("entry-A");
    assert!(Request::parse(&frame.to_string()).is_err());
}
#[test]
fn counts_are_mathematical_integers_before_any_float_rounding() {
    let base = read().to_string();
    let valid = base.replacen("\"offset\":0", "\"offset\":1.000", 1);
    assert!(Request::parse(&valid).is_ok());
    for token in [
        "0.0000000000000000000000001",
        "67108864.00000000000000001",
        "1e100000",
        "-1",
    ] {
        let raw = base.replacen("\"offset\":0", &format!("\"offset\":{token}"), 1);
        assert!(Request::parse(&raw).is_err(), "accepted {token}");
    }
    for size in [0, 65537] {
        let mut frame = read();
        frame["params"]["maxBytes"] = json!(size);
        assert!(Request::parse(&frame.to_string()).is_err());
    }
}
#[test]
fn complete_request_byte_limit_is_inclusive_before_json_parsing() {
    let raw = capture().to_string();
    let exact = raw.clone() + &" ".repeat(16384 - raw.len());
    assert!(Request::parse(&exact).is_ok());
    assert!(Request::parse(&(exact + " ")).is_err());
}
#[test]
fn declaration_paths_retain_source_profile_scale_and_refuse_aliases_or_overlap() {
    let make = |paths: &[&str]| {
        json!({"contractVersion":"0.1.0-draft.1","companions":paths.iter().map(|p|json!({"kind":"directory","path":p})).collect::<Vec<_>>()}).to_string()
    };
    let long = format!(
        "{}/{}",
        vec!["a".repeat(250); 15].join("/"),
        "b".repeat(235)
    );
    assert_eq!(long.len(), 4000);
    assert!(Declaration::parse(&make(&[&long])).is_ok());
    let too_long = format!("{long}b");
    assert!(Declaration::parse(&make(&[&too_long])).is_err());
    for paths in [
        &["../outside"][..],
        &["a", "a/b"],
        &["A", "a"],
        &["a\\b"],
        &["nul.txt"],
        &["bad\u{85}"],
        &["/outside"],
        &["C:drive"],
    ] {
        assert!(
            Declaration::parse(&make(paths)).is_err(),
            "accepted {paths:?}"
        );
    }
    let too_deep = vec!["a"; 129].join("/");
    assert!(Declaration::parse(&make(&[&too_deep])).is_err());
    assert!(
        Declaration::parse(
            r#"{"contractVersion":"0.1.0-draft.1","companions":[],"companions":[]}"#
        )
        .is_err()
    );
}

#[test]
fn frozen_original_fixtures_preserve_exact_bom_crlf_and_historical_bytes() {
    let directory = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../spec/workbench/model-originals/0.1.0-draft.1/acceptance");
    let manifest: Value = serde_json::from_str(include_str!(
        "../../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/provenance.json"
    ))
    .unwrap();
    let fixtures = manifest["fixtures"].as_array().unwrap();
    assert_eq!(fixtures.len(), 7);
    for fixture in fixtures {
        let bytes = std::fs::read(directory.join(fixture["path"].as_str().unwrap())).unwrap();
        assert_eq!(bytes.len() as u64, fixture["byteLength"].as_u64().unwrap());
        assert_eq!(
            Sha256::digest(&bytes)
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect::<String>(),
            fixture["sha256"].as_str().unwrap()
        );
    }
}
