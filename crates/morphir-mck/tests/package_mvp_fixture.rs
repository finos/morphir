// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
#[path = "support/package_fixture/mod.rs"]
#[allow(dead_code, unused_imports)]
mod fixture;
#[path = "support/package_mvp.rs"]
#[allow(dead_code)]
mod mvp;

use serde_json::Value;
use std::{fs, path::PathBuf};

fn source() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn signed_libraries_are_real_v4_documents() {
    let schema: Value = serde_json::from_slice(
        &fs::read(source().join("website/static/schemas/morphir-ir-v4.json")).unwrap(),
    )
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    for name in ["eligibility", "loan-rules"] {
        let ir: Value = serde_json::from_slice(
            &fs::read(source().join(format!(
                "spec/package/mck/fixtures/two-libraries/{name}/ir.json"
            )))
            .unwrap(),
        )
        .unwrap();
        let errors: Vec<_> = validator.iter_errors(&ir).map(|e| e.to_string()).collect();
        assert!(errors.is_empty(), "{name}: {errors:#?}");
    }
}

#[test]
fn mvp_profile_freezes_separate_first_restore_outcomes() {
    let path = source().join("spec/package/mck/fixtures/mvp-fresh-restore/cases.json");
    assert!(
        path.is_file(),
        "first-restore MVP outcomes must be frozen separately"
    );
    let cases: Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    assert_eq!(cases["profile"], mvp::PROFILE);
    assert_eq!(cases["scope"], "fresh-exact-lock-restore");
    assert!(
        cases["cases"]
            .as_array()
            .is_some_and(|cases| !cases.is_empty())
    );
}

#[test]
fn mvp_positive_metadata_remains_fresh_through_2099() {
    let frozen = fixture::read_files(&source().join(fixture::mvp::PATH)).unwrap();
    assert_eq!(
        fixture::verify_tuf(&frozen, "2099-01-01T00:00:00Z").unwrap(),
        4
    );
}

#[test]
fn mvp_fixture_reproduces_and_independently_authenticates() {
    assert_eq!(fixture::mvp::PROFILE, mvp::PROFILE);
    let generated = fixture::mvp::generate_mvp(&source()).unwrap();
    fixture::check_files(&source().join(fixture::mvp::PATH), &generated).unwrap();
    let frozen = fixture::read_files(&source().join(fixture::mvp::PATH)).unwrap();
    assert_eq!(fixture::verify_tuf(&frozen, fixture::CLOCK).unwrap(), 4);
    let historical = fixture::read_files(&source().join(fixture::SIGNED_PATH)).unwrap();
    fixture::verify_relationships(&source(), &historical).unwrap();
    for (path, bytes) in &frozen {
        if path.starts_with("registry/bundles/") || path.starts_with("registry/targets/") {
            assert_eq!(historical[path], *bytes, "preserved signed fixture: {path}");
        }
    }
    let lock: Value = serde_json::from_slice(&frozen["morphir.lock"]).unwrap();
    let mut old_lock: Value = serde_json::from_slice(&historical["morphir.lock"]).unwrap();
    for evidence in old_lock["evidence"].as_array_mut().unwrap() {
        if evidence["kind"] != "release-statement" {
            let path = format!("registry/{}", evidence["path"].as_str().unwrap());
            evidence["digest"] = fixture::signing::digest(&frozen[&path]).into();
        }
    }
    assert_eq!(lock, old_lock, "only re-signed role evidence pins change");
    let mut expected_policy: Value =
        serde_json::from_slice(&historical["trust-policy.json"]).unwrap();
    expected_policy["continuedUse"] = "fresh-metadata".into();
    let root: Value = serde_json::from_slice(&frozen["registry/metadata/1.root.json"]).unwrap();
    expected_policy["repositories"][0]["identity"] =
        fixture::signing::digest(&serde_json::to_vec(&root["signed"]).unwrap()).into();
    expected_policy["repositories"][0]["bootstrapRoot"]["digest"] =
        fixture::signing::digest(&frozen["registry/metadata/1.root.json"]).into();
    assert_eq!(
        serde_json::from_slice::<Value>(&frozen["trust-policy.json"]).unwrap(),
        expected_policy
    );
}

#[test]
fn example_copies_exactly_the_fifteen_mvp_inputs() {
    let frozen = fixture::read_files(&source().join(fixture::mvp::PATH)).unwrap();
    let inputs: fixture::Files = frozen
        .into_iter()
        .filter(|(path, _)| {
            path.starts_with("registry/")
                || matches!(path.as_str(), "morphir.lock" | "trust-policy.json")
        })
        .collect();
    assert_eq!(inputs.len(), 15);
    let example = source().join("examples/package/local-library-restore");
    assert_eq!(
        fixture::read_files(&example.join("fixture")).unwrap(),
        inputs
    );
    assert_eq!(
        fs::read(example.join("golden/decision.gleam")).unwrap(),
        fs::read(source().join(mvp::PATH).join("expected/decision.gleam")).unwrap()
    );
}

#[test]
fn frozen_case_set_prepares_isolated_real_directories() {
    let corpus = mvp::load(&source());
    assert_eq!(corpus.profile, mvp::PROFILE);
    assert_eq!(corpus.scope, "fresh-exact-lock-restore");
    assert_eq!(corpus.cases.len(), 15, "frozen first-restore inventory");
    assert_eq!(
        corpus
            .cases
            .iter()
            .filter(|case| case.expected == mvp::Expected::Restored)
            .count(),
        1
    );
    let mut ids = std::collections::BTreeSet::new();
    let original = fixture::read_files(&source().join(fixture::mvp::PATH)).unwrap();
    for case in &corpus.cases {
        assert!(ids.insert(case.id.clone()), "duplicate case ID");
        assert_eq!(
            case.diagnostic
                .as_ref()
                .is_some_and(|diagnostic| !diagnostic.is_empty()),
            case.expected == mvp::Expected::Refused,
            "{} must fix the specific refusal reason",
            case.id
        );
        let temporary = tempfile::tempdir().unwrap();
        let prepared = mvp::prepare(&source(), temporary.path(), case);
        assert!(prepared.lock.is_file() && prepared.policy.is_file() && prepared.root.is_file());
        assert!(prepared.output.parent().unwrap().is_dir());
        assert_eq!(
            prepared.initialize,
            case.setup != mvp::Setup::UninitializedState
        );
        if case.setup == mvp::Setup::OccupiedOutput {
            assert_eq!(
                fs::read(prepared.output.join("sentinel.txt")).unwrap(),
                mvp::SENTINEL
            );
        } else {
            assert!(!prepared.output.exists());
        }
    }
    assert_eq!(
        fixture::read_files(&source().join(fixture::mvp::PATH)).unwrap(),
        original
    );
}

#[test]
fn rejection_mutations_are_independently_invalid_for_the_intended_reason() {
    for case in mvp::load(&source()).cases {
        if !matches!(
            case.setup,
            mvp::Setup::TamperedSignature | mvp::Setup::ExpiredTimestamp
        ) {
            continue;
        }
        let temporary = tempfile::tempdir().unwrap();
        mvp::prepare(&source(), temporary.path(), &case);
        let files = fixture::read_files(&temporary.path().canonicalize().unwrap()).unwrap();
        let error = fixture::verify_tuf(&files, fixture::CLOCK)
            .unwrap_err()
            .to_string();
        if case.setup == mvp::Setup::ExpiredTimestamp {
            assert!(error.to_lowercase().contains("expired"), "{error}");
        } else {
            assert!(error.to_lowercase().contains("signature"), "{error}");
        }
    }
}

#[test]
fn non_metadata_mutations_preserve_repository_authentication() {
    for case in mvp::load(&source()).cases {
        if !matches!(
            case.setup,
            mvp::Setup::TamperedContent
                | mvp::Setup::UnauthorizedPublisher
                | mvp::Setup::MismatchedEvidenceDigest
                | mvp::Setup::MismatchedEvidencePath
                | mvp::Setup::ExtraBundleEntry
        ) {
            continue;
        }
        let temporary = tempfile::tempdir().unwrap();
        let prepared = mvp::prepare(&source(), temporary.path(), &case);
        let files = fixture::read_files(&temporary.path().canonicalize().unwrap()).unwrap();
        assert_eq!(fixture::verify_tuf(&files, fixture::CLOCK).unwrap(), 4);
        let policy: Value = serde_json::from_slice(&fs::read(&prepared.policy).unwrap()).unwrap();
        let keys: Vec<String> = policy["publisherRules"][0]["publicKeys"]
            .as_array()
            .unwrap()
            .iter()
            .map(|key| key.as_str().unwrap().to_owned())
            .collect();
        for (path, bytes) in &files {
            if path.starts_with("registry/targets/statements/") {
                let envelope = serde_json::from_slice(bytes).unwrap();
                assert_eq!(
                    fixture::verify_dsse(&envelope, &keys, 1),
                    case.setup != mvp::Setup::UnauthorizedPublisher
                );
            }
        }
        if case.setup == mvp::Setup::TamperedContent {
            let lock: Value = serde_json::from_slice(&fs::read(prepared.lock).unwrap()).unwrap();
            let bundle = lock["acquisitions"][0]["source"]["path"].as_str().unwrap();
            let manifest: Value =
                serde_json::from_slice(&files[&format!("registry/{bundle}/manifest.json")])
                    .unwrap();
            let payload = &files[&format!("registry/{bundle}/ir.json")];
            assert_ne!(
                manifest["content"]["ir.json"],
                fixture::signing::digest(payload)
            );
            // The content mutation preserves valid JSON so decoding is not its rejection reason.
            serde_json::from_slice::<Value>(payload).unwrap();
        }
    }
}
