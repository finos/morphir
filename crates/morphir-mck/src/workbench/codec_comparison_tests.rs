use super::*;
use serde_json::json;

#[test]
fn codec_comparison_negotiates_only_its_exact_draft_and_json_envelope() {
    let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.26","binding":"fixed","language":"test","operations":["transcode-invocations","compare-values"],"formats":["json"]});
    Capabilities::parse(caps.clone(), "0.1.0-draft.26").unwrap();
    for changed in [
        json!({"formats":["ion-text"]}),
        json!({"operations":["decode-value"]}),
        json!({"contractVersion":"0.1.0-draft.26+build"}),
    ] {
        let mut bad = caps.clone();
        for (key, value) in changed.as_object().unwrap() {
            bad[key] = value.clone();
        }
        assert!(Capabilities::parse(bad, "0.1.0-draft.26").is_err());
    }
}

#[test]
fn codec_comparison_fixed_expectations_and_reports_are_independent() {
    struct Fixed {
        caps: serde_json::Value,
        observations: std::collections::VecDeque<serde_json::Value>,
    }
    impl Testee for Fixed {
        fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            Ok(if request["op"] == "capabilities" {
                self.caps.clone()
            } else {
                self.observations.pop_front().unwrap()
            })
        }
    }
    let path =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.26");
    let raw: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(path.join("cases.json")).unwrap()).unwrap();
    let corpus = load(&path).unwrap();
    let mut fixed = Fixed {
        caps: json!({"suite":"workbench","contractVersion":"0.1.0-draft.26","binding":"infrastructure-only","language":"test","operations":["transcode-invocations","compare-values"],"formats":["json"]}),
        observations: raw["cases"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["expected"].clone())
            .collect(),
    };
    let report = execute(&corpus, &mut fixed);
    assert!(
        report.qualified(),
        "{:?}",
        report
            .as_historical()
            .expect("historical report fixture")
            .errors
    );
    check_report(&path, &Report::from_json(&report.to_json()).unwrap()).unwrap();
    let mut forged: serde_json::Value = serde_json::from_str(&report.to_json()).unwrap();
    forged["records"][0]["observed"]["value"]["invocations"]["calls"][0]["arguments"][0]["value"] =
        json!("43");
    assert!(check_report(&path, &Report::from_json(&forged.to_string()).unwrap()).is_err());
}

#[test]
fn codec_comparison_preserves_opaque_inputs_and_rejects_forged_projection_kinds() {
    let input = json!({"actual":{"$serde_json::private::Number":"123"},"expected":null,"comparison":{"profile":"morphir-comparison-exact-v1"}});
    super::codec_comparison::validate_input(&input, Operation::CompareValues).unwrap();
    assert!(
        super::codec_comparison::validate_input(&input, Operation::TranscodeInvocations).is_err()
    );
    for value in [
        json!({"matches":true,"mismatchPath":"/a"}),
        json!({"matches":false,"mismatchPath":null}),
        json!({"matches":false,"mismatchPath":"unrooted"}),
        json!({"matches":{"$serde_json::private::Number":"1"},"mismatchPath":null}),
    ] {
        assert!(super::codec_comparison::projection(&value, Operation::CompareValues).is_err());
    }
    assert!(
        super::codec_comparison::projection(
            &json!({"matches":true,"mismatchPath":null}),
            Operation::TranscodeInvocations
        )
        .is_err()
    );
    let raw = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../spec/workbench/mck/draft.26/cases.json"),
    )
    .unwrap();
    let mut corpus: serde_json::Value = serde_json::from_str(&raw).unwrap();
    corpus["cases"].as_array_mut().unwrap().truncate(1);
    corpus["cases"][0]["operation"] = json!("compare-values");
    corpus["cases"][0]["input"] = input.clone();
    corpus["cases"][0]["expected"] =
        json!({"status":"invalid","code":"execution.unsupported_value"});
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(temp.path().join("cases.json"), corpus.to_string()).unwrap();
    let loaded = load(temp.path()).unwrap();
    assert_eq!(
        loaded
            .as_historical()
            .expect("historical corpus fixture")
            .cases[0]
            .input,
        input
    );
}

#[test]
fn codec_comparison_opaque_numbers_reach_the_adapter_without_legacy_float_narrowing() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"),r#"{"formatVersion":"0.1.0-draft.26","cases":[{"id":"opaque-number","operation":"compare-values","format":"json","input":{"actual":{"type":"int","value":1e400},"expected":{"type":"int","value":"1"},"comparison":{"profile":"morphir-comparison-exact-v1"}},"expected":{"status":"invalid","code":"execution.invalid_integer"}}]}"#).unwrap();
    let corpus = load(root.path()).unwrap();
    assert_eq!(
        corpus
            .as_historical()
            .expect("historical corpus fixture")
            .cases[0]
            .input["actual"]["value"]
            .to_string(),
        "1e+400"
    );
}

#[test]
fn codec_comparison_json_pointers_accept_newlines_but_reject_invalid_escapes() {
    for path in ["", "/", "/a\nb", "/a~1b~0c", "/~01"] {
        super::codec_comparison::projection(
            &json!({"matches":false,"mismatchPath":path}),
            Operation::CompareValues,
        )
        .unwrap();
    }
    for path in ["no-root", "/~", "/~2", "/a~\nb", "\n"] {
        assert!(
            super::codec_comparison::projection(
                &json!({"matches":false,"mismatchPath":path}),
                Operation::CompareValues
            )
            .is_err(),
            "{path:?}"
        );
    }
}

#[test]
fn codec_binary_source_wrapper_fits_full_production_byte_boundary() {
    let input = json!({"sourceFormat":"ion-binary","source":{"hex":"00".repeat(1048576)},"targetFormat":"json"});
    super::codec_comparison::validate_input(&input, Operation::TranscodeInvocations).unwrap();
}

#[test]
fn codec_operation_specific_kits_publish_exact_canonical_subsets() {
    let base =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.26");
    let combined = load(&base).unwrap();
    for (name, operation) in [
        ("transcode", Operation::TranscodeInvocations),
        ("comparison", Operation::CompareValues),
    ] {
        let subset = load(&base.join(name)).unwrap();
        let expected: Vec<_> = combined
            .as_historical()
            .expect("historical corpus fixture")
            .cases
            .iter()
            .filter(|case| case.operation() == operation)
            .collect();
        assert_eq!(
            subset
                .as_historical()
                .expect("historical corpus fixture")
                .cases
                .len(),
            expected.len()
        );
        for (actual, expected) in subset
            .as_historical()
            .expect("historical corpus fixture")
            .cases
            .iter()
            .zip(expected)
        {
            assert_eq!(actual.id, expected.id);
            assert_eq!(actual.input, expected.input);
            assert_eq!(actual.expected, expected.expected);
        }
    }
}
