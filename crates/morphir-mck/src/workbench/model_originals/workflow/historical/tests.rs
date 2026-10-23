use super::*;
use crate::workbench::model_originals::workflow::{DecodeLimits, Decoder, pairing::PairedRun};

const INPUT: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/cases/inspection-and-search-use-current-local-reference/input.json"
));
const EXPECTED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/cases/inspection-and-search-use-current-local-reference/expected.json"
));

fn owner() -> Decoder {
    Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    )
}

const BROWSER_INPUT: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/cases/browser-import-v4-bom-crlf.json/input.json"
));
const BROWSER_EXPECTED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/cases/browser-import-v4-bom-crlf.json/expected.json"
));
const NATIVE_INPUT: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/cases/native-import-v4-bom-crlf.json/input.json"
));
const NATIVE_EXPECTED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/cases/native-import-v4-bom-crlf.json/expected.json"
));

#[test]
fn historical_operands_02_all_original_pairs_preserve_common_limit_borrows_and_missing_policy() {
    for (input, expected, actions) in [
        (INPUT, EXPECTED, 32),
        (BROWSER_INPUT, BROWSER_EXPECTED, 64),
        (NATIVE_INPUT, NATIVE_EXPECTED, 64),
    ] {
        let mut d = owner();
        let operands = HistoricalClientOperands::decode(input, expected, &mut d).unwrap();
        let pair = operands.paired(&mut d).unwrap();
        let ScenarioRef::Historical(s, version) = pair.scenario() else {
            panic!("historical owner required")
        };
        assert!(pair.scenario().current().is_none());
        let limits = pair.scenario().common_limits();
        assert!(std::ptr::eq(limits.actions, &s.limits.actions));
        assert!(std::ptr::eq(
            limits.observer_byte_visits,
            &s.limits.observer_byte_visits
        ));
        assert_eq!(limits.actions.0, actions);
        assert_eq!(limits.observer_byte_visits.0, 16_777_216);
        assert_eq!(limits.metadata_bytes.0, 1_048_576);
        assert!(
            matches!(pair.scenario().ledger_allowances(),LedgerAllowancesRef::AbsentHistorical(v) if v==version)
        );
        let body = pair.expected().body();
        assert!(std::ptr::eq(body.checks, &operands.expected.checks));
        assert!(std::ptr::eq(
            body.qualification,
            &operands.expected.qualification
        ));
        assert!(std::ptr::eq(body.lineage, &operands.expected.lineage));
        assert!(
            matches!(body.qualification,domain::ExpectedWorkflowModelOriginalsClientQualification::Blocked{obligations} if !obligations.0.is_empty())
        );
        assert!(body.lineage.0.iter().any(|l| matches!(
            l.treatment,
            domain::ExpectedLineageTreatment::Unresolved { .. }
        )));
        assert_eq!(operands.input_raw().get(), input.trim());
        assert_eq!(operands.expected_raw().get(), expected.trim());
    }
}

#[test]
fn historical_operands_03_current_decoders_stay_strict_and_native_import_stays_client_native() {
    for (input, expected) in [
        (INPUT, EXPECTED),
        (BROWSER_INPUT, BROWSER_EXPECTED),
        (NATIVE_INPUT, NATIVE_EXPECTED),
    ] {
        assert!(owner().decode::<input::Scenario>(input).is_err());
        assert!(
            owner()
                .decode::<domain::ExpectedWorkflow>(expected)
                .is_err()
        );
    }
    for (input, expected, native) in [
        (BROWSER_INPUT, BROWSER_EXPECTED, false),
        (NATIVE_INPUT, NATIVE_EXPECTED, true),
    ] {
        let mut d = owner();
        let operands = HistoricalClientOperands::decode(input, expected, &mut d).unwrap();
        let pair = operands.paired(&mut d).unwrap();
        assert_eq!(pair.expected().version(), "author-candidate-11");
        let PairedRun::Client { actions, .. } = pair.run() else {
            panic!("actual client role")
        };
        let via = actions
            .iter()
            .find_map(|a| {
                if let input::ClientAction::StartImport { via, .. } = a {
                    Some(via)
                } else {
                    None
                }
            })
            .unwrap();
        assert_eq!(
            matches!(via, input::ClientActionStartImportVia::Native),
            native
        );
    }
}

fn changed(expected: &str, change: impl FnOnce(&mut serde_json::Value)) -> String {
    let mut v = serde_json::from_str(expected).unwrap();
    change(&mut v);
    v.to_string()
}

#[test]
fn historical_operands_04_shared_pairing_refuses_every_origin_and_selection_mismatch() {
    use super::super::pairing::PairError;
    use serde_json::json;
    for (member, value, fault) in [
        ("packet", json!("additive"), PairError::Packet),
        (
            "sha256",
            json!("0000000000000000000000000000000000000000000000000000000000000000"),
            PairError::Digest,
        ),
        ("id", json!("other-original"), PairError::Case),
    ] {
        let expected = changed(EXPECTED, |v| v["origin"][member] = value);
        assert!(
            matches!(HistoricalClientOperands::decode(INPUT,&expected,&mut owner()),Err(HistoricalError::Pair(e)) if e==fault)
        );
    }
    let expected = changed(EXPECTED, |v| v["runIndex"] = json!(1));
    assert!(matches!(
        HistoricalClientOperands::decode(INPUT, &expected, &mut owner()),
        Err(HistoricalError::Pair(PairError::RunIndex))
    ));
    let input = changed(INPUT, |v| {
        v["runs"] = json!([v["runs"][0].clone(), v["runs"][0].clone()])
    });
    let operands = HistoricalClientOperands::decode(&input, &expected, &mut owner()).unwrap();
    assert_eq!(operands.paired(&mut owner()).unwrap().run_index(), 1);
    let role = changed(EXPECTED, |v| v["role"] = json!("model-originals-server"));
    assert!(HistoricalClientOperands::decode(INPUT, &role, &mut owner()).is_err());
}

#[test]
fn historical_operands_05_version_fields_limits_and_unknown_members_are_closed() {
    use serde_json::json;
    for version in [
        "author-candidate-9",
        "author-candidate-12",
        "author-candidate-17",
    ] {
        let expected = changed(EXPECTED, |v| v["version"] = json!(version));
        assert!(HistoricalClientOperands::decode(INPUT, &expected, &mut owner()).is_err());
    }
    let expected = changed(EXPECTED, |v| v["unknown"] = json!(null));
    assert!(HistoricalClientOperands::decode(INPUT, &expected, &mut owner()).is_err());
    let input = changed(INPUT, |v| {
        v["limits"]["ledgerEffectHistoryEntries"] = json!(8192)
    });
    assert!(HistoricalClientOperands::decode(&input, EXPECTED, &mut owner()).is_err());
    let input = changed(INPUT, |v| {
        v["limits"].as_object_mut().unwrap().remove("metadataBytes");
    });
    assert!(HistoricalClientOperands::decode(&input, EXPECTED, &mut owner()).is_err());
    let duplicate = EXPECTED.replacen('{', "{\"version\":\"author-candidate-10\",", 1);
    assert!(HistoricalClientOperands::decode(INPUT, &duplicate, &mut owner()).is_err());
}

#[test]
fn historical_operands_06_typed_vocabulary_rejects_later_extensions_but_raw_json_is_inert() {
    use serde_json::json;
    for (input, expected) in [(INPUT, EXPECTED), (BROWSER_INPUT, BROWSER_EXPECTED)] {
        for kind in [
            "catalog",
            "native-invoke",
            "manifest-fetch",
            "workspace-open",
        ] {
            let expected = changed(
                expected,
                |v| v["checks"] = json!([{"kind":"port-counts","id":"count","attempts":["attempt"],"effectKind":kind,"expected":{"kind":"exact","value":1}}]),
            );
            assert!(matches!(
                HistoricalClientOperands::decode(input, &expected, &mut owner()),
                Err(HistoricalError::Decode(DecodeError::Shape(
                    "historical effect kind"
                )))
            ));
        }
        let expected = changed(
            expected,
            |v| v["lineage"][0]["treatment"] = json!({"kind":"compared-by-decision","checkIds":["check"],"decision":"morphir-etg2.22.1.2.1"}),
        );
        assert!(matches!(
            HistoricalClientOperands::decode(input, &expected, &mut owner()),
            Err(HistoricalError::Decode(DecodeError::Shape(
                "historical lineage treatment"
            )))
        ));
    }
    let newer = changed(
        EXPECTED,
        |v| v["checks"] = json!([{"kind":"model-output-cleared","id":"check","checkpoint":"checkpoint","formerModel":"model"}]),
    );
    assert!(matches!(
        HistoricalClientOperands::decode(INPUT, &newer, &mut owner()),
        Err(HistoricalError::Decode(DecodeError::Shape(
            "historical client check"
        )))
    ));
    let raw = r#"{"kind":"connected-transcript","effectKind":"workspace-open","version":"author-candidate-17"}"#;
    let expected = changed(
        EXPECTED,
        |v| v["checks"] = json!([{"kind":"core-result","id":"core","attempt":"attempt","effect":{"attempt":"attempt","kind":"inspection","ordinal":0},"modelBinding":{"kind":"none"},"projection":{"kind":"exact-json","expectedRawJson":raw,"numberComparison":"exact-token"}}]),
    );
    let operands = HistoricalClientOperands::decode(INPUT, &expected, &mut owner()).unwrap();
    let domain::ExpectedClientCheck::CoreResult {
        projection:
            domain::ExpectedCoreProjection::ExactJson {
                expected_raw_json, ..
            },
        ..
    } = &operands.expected.checks.0[0]
    else {
        panic!("actual raw projection")
    };
    assert_eq!(expected_raw_json.0, raw);
}

#[test]
fn historical_operands_07_same_owner_exhaustion_is_sticky_before_repairing_or_redecoding() {
    let mut d =
        Decoder::new(DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 1, 1_000_000).unwrap());
    assert!(matches!(
        HistoricalClientOperands::decode(INPUT, EXPECTED, &mut d),
        Err(HistoricalError::Decode(DecodeError::Work(_)))
    ));
    let used = d.usage();
    assert!(matches!(
        HistoricalClientOperands::decode(BROWSER_INPUT, BROWSER_EXPECTED, &mut d),
        Err(HistoricalError::Decode(DecodeError::Work(_)))
    ));
    assert_eq!(d.usage(), used);
}

#[test]
fn historical_operands_08_pinned_schema_and_original_source_provenance_remain_exact() {
    let manifest = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/preservation.json"
    ));
    let manifest: serde_json::Value = serde_json::from_str(manifest).unwrap();
    for (input, expected, case) in [
        (
            INPUT,
            EXPECTED,
            "inspection-and-search-use-current-local-reference",
        ),
        (
            BROWSER_INPUT,
            BROWSER_EXPECTED,
            "browser-import-v4-bom-crlf.json",
        ),
        (
            NATIVE_INPUT,
            NATIVE_EXPECTED,
            "native-import-v4-bom-crlf.json",
        ),
    ] {
        for (suffix, raw) in [("input.json", input), ("expected.json", expected)] {
            let path = format!("cases/{case}/{suffix}");
            let f = manifest["files"]
                .as_array()
                .unwrap()
                .iter()
                .find(|f| f["path"] == path)
                .unwrap();
            assert_eq!(
                crate::kit::hash::sha256_hex(raw.as_bytes()),
                f["sha256"].as_str().unwrap()
            );
            assert_eq!(raw.len() as u64, f["bytes"].as_u64().unwrap());
        }
    }
    let schemas = [
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/provenance/expected-v10/expected.schema.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/local-historical-first-v1/provenance/expected-v11/expected.schema.json"
        )),
    ];
    for (schema, hash, checks, effects, projections) in [
        (
            schemas[0],
            "041ee483c5d45c8ffb2c170c37ebe932dd54a3eed5c3734f0b34227dbcd791ff",
            15,
            14,
            5,
        ),
        (
            schemas[1],
            "06834f2b4e0613d4db02d845d2dbbb9ae0886b8c8055498a99c3942675f76670",
            17,
            15,
            6,
        ),
    ] {
        assert_eq!(crate::kit::hash::sha256_hex(schema.as_bytes()), hash);
        let schema: serde_json::Value = serde_json::from_str(schema).unwrap();
        assert_eq!(
            schema["$defs"]["ExpectedClientCheck"]["oneOf"]
                .as_array()
                .unwrap()
                .len(),
            checks
        );
        assert_eq!(
            schema["$defs"]["EffectKind"]["enum"]
                .as_array()
                .unwrap()
                .len(),
            effects
        );
        assert_eq!(
            schema["$defs"]["ExpectedCoreProjection"]["oneOf"]
                .as_array()
                .unwrap()
                .len(),
            projections
        );
    }
}

#[test]
fn historical_operands_01_original_explorer_pairs_without_current_version_or_ledger_limits() {
    let mut decoder = owner();
    let operands = HistoricalClientOperands::decode(INPUT, EXPECTED, &mut decoder).unwrap();
    assert_eq!(operands.input_raw().get().as_ptr(), INPUT.trim().as_ptr());
    assert_eq!(
        operands.expected_raw().get().as_ptr(),
        EXPECTED.trim().as_ptr()
    );
    let paired = operands.paired(&mut decoder).unwrap();
    assert_eq!(paired.run_index(), 0);
    assert!(matches!(paired.run(), PairedRun::Client { actions, .. } if actions.len() == 12));
    assert_eq!(paired.expected().version(), "author-candidate-10");
    assert!(matches!(
        paired.scenario().ledger_allowances(),
        LedgerAllowancesRef::AbsentHistorical(HistoricalExpectedVersion::AuthorCandidate10)
    ));
}
