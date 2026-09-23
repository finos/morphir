// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
#[path = "support/package_fixture/mod.rs"]
#[allow(dead_code, unused_imports)]
mod fixture;
#[path = "support/package_refresh.rs"]
#[allow(dead_code)]
mod refresh;

use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{fs, path::PathBuf};

const FIXTURE: &str = "spec/package/mck/fixtures/mvp-fresh-restore";

fn source() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn frozen_refresh_receipt_identifies_only_authenticated_metadata() {
    let path = source().join(refresh::EXPECTED_RECEIPT);
    assert!(
        path.is_file(),
        "refresh requires an independently frozen receipt"
    );
    let receipt: Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    let signed = fixture::read_files(&source().join(FIXTURE).join("signed")).unwrap();
    let digest = |bytes: &[u8]| {
        let hex: String = Sha256::digest(bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        format!("sha256:{hex}")
    };
    assert_eq!(
        receipt,
        json!({
            "profile": "local-library-mvp",
            "profileVersion": "0.1.0-draft.1",
            "registry": "local",
            "timestampDigest": digest(&signed["registry/metadata/timestamp.json"]),
            "snapshotDigest": digest(&signed["registry/metadata/1.snapshot.json"]),
        })
    );
    assert_eq!(fixture::verify_tuf(&signed, fixture::CLOCK).unwrap(), 4);
    // Envelope formatting and signatures are part of both receipt digests.
    for (field, path) in [
        ("timestampDigest", "registry/metadata/timestamp.json"),
        ("snapshotDigest", "registry/metadata/1.snapshot.json"),
    ] {
        let envelope: Value = serde_json::from_slice(&signed[path]).unwrap();
        assert_ne!(
            receipt[field],
            digest(&serde_json::to_vec(&envelope["signed"]).unwrap())
        );
        assert_ne!(
            receipt[field],
            digest(&serde_json::to_vec(&envelope).unwrap())
        );
    }
}

#[test]
fn refresh_cases_preserve_locks_and_authenticate_metadata_without_package_assets() {
    let corpus = refresh::load(&source());
    assert_eq!(corpus.format_version, "0.1.0-draft.1");
    assert_eq!(corpus.profile, refresh::mvp::PROFILE);
    assert_eq!(corpus.scope, "metadata-only-refresh");
    assert_eq!(corpus.fixture, "signed");
    assert_eq!(corpus.fixed_clock, fixture::CLOCK);
    assert_eq!(corpus.cases.len(), 14);
    assert_eq!(
        corpus
            .cases
            .iter()
            .filter(|case| case.expected == refresh::Expected::Refreshed)
            .count(),
        7
    );
    assert_eq!(corpus.invariants["successReceipt"], "expected/refresh.json");
    assert_eq!(
        corpus.invariants["packageAuthority"],
        "none; no-selection-or-package-authorization"
    );
    let original = fixture::read_files(&source().join(FIXTURE).join("signed")).unwrap();
    let mut ids = std::collections::BTreeSet::new();
    for case in &corpus.cases {
        assert!(ids.insert(&case.id), "duplicate case ID");
        assert_eq!(
            case.diagnostic
                .as_ref()
                .is_some_and(|value| !value.is_empty()),
            case.expected == refresh::Expected::Refused,
            "{} must freeze its refusal reason",
            case.id
        );
        let temporary = tempfile::tempdir().unwrap();
        let prepared = refresh::prepare(&source(), temporary.path(), case);
        assert_eq!(
            prepared.initialize,
            case.setup != refresh::Setup::UninitializedState
        );
        assert_eq!(fs::read(&prepared.lock).unwrap(), original["morphir.lock"]);
        assert!(!prepared.state.exists());
        assert!(!prepared.output.exists());
        assert!(
            fs::read_dir(prepared.output.parent().unwrap())
                .unwrap()
                .next()
                .is_none()
        );
        let actual = fixture::read_files(&temporary.path().canonicalize().unwrap()).unwrap();
        if case.expected == refresh::Expected::Refreshed {
            for (path, bytes) in &original {
                if path.starts_with("registry/metadata/") {
                    assert_eq!(
                        &actual[path], bytes,
                        "{}: metadata bytes must be unchanged",
                        case.id
                    );
                }
            }
        }
        let asset = match case.setup {
            refresh::Setup::DamagedBundle | refresh::Setup::MissingBundle => {
                Some("registry/bundles/")
            }
            refresh::Setup::DamagedPublisherEnvelope | refresh::Setup::MissingPublisherEnvelope => {
                Some("registry/targets/statements/")
            }
            refresh::Setup::DamagedRecord | refresh::Setup::MissingRecord => {
                Some("registry/targets/records/")
            }
            _ => None,
        };
        if let Some(prefix) = asset {
            assert!(original.keys().any(|path| path.starts_with(prefix)));
            for (path, bytes) in &original {
                if path.starts_with(prefix) {
                    match case.setup {
                        refresh::Setup::MissingBundle
                        | refresh::Setup::MissingPublisherEnvelope
                        | refresh::Setup::MissingRecord => assert!(!actual.contains_key(path)),
                        refresh::Setup::DamagedBundle if path.ends_with("/manifest.json") => {
                            assert_eq!(&actual[path], bytes)
                        }
                        _ => assert_ne!(&actual[path], bytes),
                    }
                } else {
                    assert_eq!(
                        &actual[path], bytes,
                        "unrelated input must remain unchanged"
                    );
                }
            }
        }
    }
    assert_eq!(
        fixture::read_files(&source().join(FIXTURE).join("signed")).unwrap(),
        original
    );
}

#[test]
fn refresh_metadata_refusals_are_independently_invalid() {
    for case in refresh::load(&source()).cases {
        if !matches!(
            case.setup,
            refresh::Setup::TamperedSignature | refresh::Setup::ExpiredTimestamp
        ) {
            continue;
        }
        let temporary = tempfile::tempdir().unwrap();
        refresh::prepare(&source(), temporary.path(), &case);
        let files = fixture::read_files(&temporary.path().canonicalize().unwrap()).unwrap();
        let error = fixture::verify_tuf(&files, fixture::CLOCK)
            .unwrap_err()
            .to_string()
            .to_lowercase();
        let reason = if case.setup == refresh::Setup::ExpiredTimestamp {
            "expired"
        } else {
            "signature"
        };
        assert!(error.contains(reason), "{error}");
    }
}

#[test]
fn refresh_state_faults_are_applied_only_after_explicit_initialization() {
    for case in refresh::load(&source()).cases {
        if !matches!(
            case.setup,
            refresh::Setup::MissingEstablishedState
                | refresh::Setup::CorruptState
                | refresh::Setup::UncertainState
        ) {
            continue;
        }
        let temporary = tempfile::tempdir().unwrap();
        let prepared = refresh::prepare(&source(), temporary.path(), &case);
        assert!(prepared.initialize);
        assert!(!prepared.state.exists());
        // Fixture setup timing only. Real state validation belongs to CLI/runtime tests.
        fs::create_dir(&prepared.state).unwrap();
        let database = prepared.state.join("trust.sqlite");
        fs::write(&database, b"prior database bytes").unwrap();
        refresh::after_initialize(&case, &prepared);
        match case.setup {
            refresh::Setup::MissingEstablishedState => assert!(!database.exists()),
            refresh::Setup::CorruptState => {
                assert_eq!(fs::read(database).unwrap(), b"not a SQLite database\n")
            }
            refresh::Setup::UncertainState => {
                assert_eq!(fs::read(database).unwrap(), b"prior database bytes");
                assert_eq!(
                    fs::read(prepared.state.join("operation")).unwrap(),
                    b"unresolved prior operation\n"
                );
            }
            _ => unreachable!(),
        }
        assert!(!prepared.output.exists());
    }
}
