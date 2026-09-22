// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
#[path = "support/package_fixture/mod.rs"]
#[allow(dead_code, unused_imports)]
mod fixture;
#[path = "support/package_resolve.rs"]
#[allow(dead_code)]
mod resolve;

use serde_json::{Value, json};
use std::{fs, path::PathBuf};

const FIXTURE: &str = "spec/package/mck/fixtures/mvp-fresh-restore";

fn source() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn frozen_resolve_lock_preserves_the_independently_signed_graph_and_pins() {
    let path = source().join(FIXTURE).join("expected/resolve.lock.json");
    assert!(
        path.is_file(),
        "resolve requires an independently frozen full lock"
    );
    let bytes = fs::read(path).unwrap();
    let actual: Value = serde_json::from_slice(&bytes).unwrap();
    let signed = fixture::read_files(&source().join(FIXTURE).join("signed")).unwrap();
    let mut expected: Value = serde_json::from_slice(&signed["morphir.lock"]).unwrap();
    expected["registries"] = json!([{"id":"local", "snapshot":"snapshot"}]);
    for acquisition in expected["acquisitions"].as_array_mut().unwrap() {
        acquisition["registry"] = "local".into();
        acquisition["statement"] = match acquisition["release"]["packagePath"].as_str().unwrap() {
            "example.com/finance/eligibility" => "statement-0",
            "example.com/finance/loan-rules" => "statement-1",
            other => panic!("unexpected fixture release: {other}"),
        }
        .into();
    }
    for item in expected["evidence"].as_array_mut().unwrap() {
        item["registry"] = "local".into();
        item["id"] = match item["id"].as_str().unwrap() {
            "eligibility-statement" => "statement-0",
            "loan-rules-statement" => "statement-1",
            "finance-root" => "root",
            "finance-snapshot" => "snapshot",
            "finance-targets" => "targets",
            "finance-timestamp" => "timestamp",
            other => panic!("unexpected fixture evidence: {other}"),
        }
        .into();
    }
    expected["evidence"]
        .as_array_mut()
        .unwrap()
        .sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    assert_eq!(
        actual, expected,
        "only locally assigned evidence IDs change"
    );
    let mut pretty = serde_json::to_vec_pretty(&actual).unwrap();
    pretty.push(b'\n');
    assert_eq!(bytes, pretty, "lexically ordered object keys and final LF");
    assert_eq!(
        fs::read(source().join("examples/package/local-library-restore/golden/resolve.lock.json"))
            .unwrap(),
        bytes,
        "the runnable example uses the independently frozen lock"
    );
    assert_eq!(fixture::verify_tuf(&signed, fixture::CLOCK).unwrap(), 4);
}

#[test]
fn resolve_cases_prepare_new_lock_destinations_without_changing_the_input_lock() {
    let corpus = resolve::load(&source());
    assert_eq!(corpus.profile, resolve::mvp::PROFILE);
    assert_eq!(corpus.scope, "fresh-exact-root-resolve");
    assert_eq!(corpus.cases.len(), 13);
    assert_eq!(
        corpus
            .cases
            .iter()
            .filter(|case| case.expected == resolve::Expected::Resolved)
            .count(),
        1
    );
    let original = fixture::read_files(&source().join(FIXTURE).join("signed")).unwrap();
    let mut ids = std::collections::BTreeSet::new();
    for case in &corpus.cases {
        assert!(ids.insert(&case.id), "duplicate case ID");
        assert_eq!(
            case.diagnostic
                .as_ref()
                .is_some_and(|value| !value.is_empty()),
            case.expected == resolve::Expected::Refused,
            "{} must freeze its refusal reason",
            case.id
        );
        let temporary = tempfile::tempdir().unwrap();
        let prepared = resolve::prepare(&source(), temporary.path(), case);
        assert_eq!(
            fs::read(&prepared.restore.lock).unwrap(),
            original["morphir.lock"]
        );
        assert_ne!(prepared.restore.lock, prepared.output);
        assert!(prepared.output.parent().unwrap().is_dir());
        assert!(
            !prepared.restore.output.exists(),
            "resolve must not prepare a restore tree"
        );
        if case.setup == resolve::mvp::Setup::OccupiedOutput {
            assert_eq!(fs::read(&prepared.output).unwrap(), resolve::mvp::SENTINEL);
        } else {
            assert!(!prepared.output.exists());
        }
        if let Some(root) = &case.root {
            assert_eq!(root, "example.com/finance/loan-rules@9.9.9");
            assert_eq!(prepared.root, *root);
        } else {
            assert_eq!(prepared.root, resolve::ROOT);
        }
    }
    assert_eq!(
        fixture::read_files(&source().join(FIXTURE).join("signed")).unwrap(),
        original
    );
}

#[test]
fn resolve_state_mutations_run_only_after_initialization() {
    for case in resolve::load(&source()).cases {
        if !matches!(
            case.setup,
            resolve::mvp::Setup::MissingEstablishedState
                | resolve::mvp::Setup::CorruptState
                | resolve::mvp::Setup::UncertainState
        ) {
            continue;
        }
        let temporary = tempfile::tempdir().unwrap();
        let prepared = resolve::prepare(&source(), temporary.path(), &case);
        assert!(prepared.restore.initialize);
        assert!(!prepared.restore.state.exists());
        // This tests only fixture setup timing, not SQLite or runtime state validation.
        fs::create_dir(&prepared.restore.state).unwrap();
        let database = prepared.restore.state.join("trust.sqlite");
        fs::write(&database, b"prior database bytes").unwrap();
        resolve::after_initialize(&case, &prepared);
        match case.setup {
            resolve::mvp::Setup::MissingEstablishedState => assert!(!database.exists()),
            resolve::mvp::Setup::CorruptState => {
                assert_eq!(fs::read(database).unwrap(), b"not a SQLite database\n")
            }
            resolve::mvp::Setup::UncertainState => {
                assert_eq!(fs::read(database).unwrap(), b"prior database bytes");
                assert_eq!(
                    fs::read(prepared.restore.state.join("operation")).unwrap(),
                    b"unresolved prior operation\n"
                );
            }
            _ => unreachable!(),
        }
        assert!(!prepared.output.exists());
    }
}
