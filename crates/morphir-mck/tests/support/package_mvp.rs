// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Shared test-only setup for frozen MVP cases. The caller executes the real CLI.
//! No package implementation, signer, expected-result generator, or runner lives here.
use serde::Deserialize;
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
};

pub const PROFILE: &str = "local-library-mvp:0.1.0-draft.1";
pub const PATH: &str = "spec/package/mck/fixtures/mvp-fresh-restore";
pub const SENTINEL: &[u8] = b"unrelated consumer content\n";

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Setup {
    Fresh,
    TamperedSignature,
    TamperedContent,
    UnauthorizedPublisher,
    UnsafeSource,
    UninitializedState,
    OccupiedOutput,
    HistoricalPolicy,
    ExpiredTimestamp,
    MissingEstablishedState,
    CorruptState,
    UncertainState,
    MismatchedEvidenceDigest,
    MismatchedEvidencePath,
    ExtraBundleEntry,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Expected {
    Restored,
    Refused,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Case {
    pub id: String,
    pub setup: Setup,
    pub expected: Expected,
    #[serde(default)]
    pub diagnostic: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Corpus {
    pub format_version: String,
    pub profile: String,
    pub scope: String,
    pub fixture: String,
    pub fixed_clock: String,
    pub cases: Vec<Case>,
    pub invariants: Value,
}

pub fn load(source: &Path) -> Corpus {
    serde_json::from_slice(&fs::read(source.join(PATH).join("cases.json")).unwrap()).unwrap()
}

pub struct Prepared {
    pub policy: PathBuf,
    pub initialization_policy: PathBuf,
    pub root: PathBuf,
    pub lock: PathBuf,
    pub registry: PathBuf,
    pub state: PathBuf,
    pub output: PathBuf,
    pub initialize: bool,
}

fn copy_tree(source: &Path, destination: &Path) {
    fs::create_dir_all(destination).unwrap();
    for entry in fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let kind = entry.file_type().unwrap();
        assert!(!kind.is_symlink(), "fixture contains a symlink");
        let target = destination.join(entry.file_name());
        if kind.is_dir() {
            copy_tree(&entry.path(), &target);
        } else {
            assert!(kind.is_file(), "fixture contains a special file");
            fs::copy(entry.path(), target).unwrap();
        }
    }
}

fn edit_json(path: &Path, edit: impl FnOnce(&mut Value)) {
    let mut value: Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    edit(&mut value);
    fs::write(path, serde_json::to_vec_pretty(&value).unwrap()).unwrap();
}

/// Prepare one isolated case. `directory` must be a new temporary directory.
pub fn prepare(source: &Path, directory: &Path, case: &Case) -> Prepared {
    assert!(fs::read_dir(directory).unwrap().next().is_none());
    copy_tree(&source.join(PATH).join("signed"), directory);
    let prepared = Prepared {
        policy: directory.join("trust-policy.json"),
        initialization_policy: directory.join("initialization-policy.json"),
        root: directory.join("registry/metadata/1.root.json"),
        lock: directory.join("morphir.lock"),
        registry: directory.join("registry"),
        state: directory.join("trust-state"),
        output: directory.join("consumer/libraries"),
        initialize: case.setup != Setup::UninitializedState,
    };
    fs::create_dir_all(prepared.output.parent().unwrap()).unwrap();
    match case.setup {
        Setup::Fresh
        | Setup::UninitializedState
        | Setup::MissingEstablishedState
        | Setup::CorruptState
        | Setup::UncertainState => {}
        Setup::TamperedSignature => {
            for filename in ["timestamp.json", "1.timestamp.json"] {
                edit_json(
                    &prepared.registry.join("metadata").join(filename),
                    |value| {
                        value["signatures"][0]["sig"] = "00".repeat(64).into();
                    },
                );
            }
        }
        Setup::TamperedContent => {
            let lock: Value = serde_json::from_slice(&fs::read(&prepared.lock).unwrap()).unwrap();
            let bundle = lock["acquisitions"][0]["source"]["path"].as_str().unwrap();
            let ir = prepared.registry.join(bundle).join("ir.json");
            let mut bytes = fs::read(&ir).unwrap();
            bytes.push(b'\n');
            fs::write(ir, bytes).unwrap();
        }
        Setup::UnauthorizedPublisher => {
            // A real authorized repository key is not an authorized release publisher.
            let root: Value = serde_json::from_slice(&fs::read(&prepared.root).unwrap()).unwrap();
            let key = root["signed"]["keys"]
                .as_object()
                .unwrap()
                .values()
                .next()
                .unwrap()["keyval"]["public"]
                .clone();
            edit_json(&prepared.policy, |value| {
                value["publisherRules"][0]["publicKeys"] = serde_json::json!([key]);
            });
        }
        Setup::UnsafeSource => edit_json(&prepared.lock, |value| {
            value["acquisitions"][0]["source"]["path"] = "../escape".into();
        }),
        Setup::OccupiedOutput => {
            fs::create_dir_all(&prepared.output).unwrap();
            fs::write(prepared.output.join("sentinel.txt"), SENTINEL).unwrap();
        }
        Setup::HistoricalPolicy => {}
        Setup::ExpiredTimestamp => {
            let expired = fs::read(directory.join("variants/expired-timestamp.json")).unwrap();
            for filename in ["timestamp.json", "1.timestamp.json"] {
                fs::write(prepared.registry.join("metadata").join(filename), &expired).unwrap();
            }
        }
        Setup::MismatchedEvidenceDigest => edit_json(&prepared.lock, |value| {
            let evidence = value["evidence"]
                .as_array_mut()
                .unwrap()
                .iter_mut()
                .find(|item| item["id"] == "finance-snapshot")
                .unwrap();
            evidence["digest"] = format!("sha256:{}", "00".repeat(32)).into();
        }),
        Setup::MismatchedEvidencePath => edit_json(&prepared.lock, |value| {
            let evidence = value["evidence"]
                .as_array_mut()
                .unwrap()
                .iter_mut()
                .find(|item| item["id"] == "finance-targets")
                .unwrap();
            evidence["path"] = "metadata/2.targets.json".into();
        }),
        Setup::ExtraBundleEntry => {
            let lock: Value = serde_json::from_slice(&fs::read(&prepared.lock).unwrap()).unwrap();
            let bundle = lock["acquisitions"][0]["source"]["path"].as_str().unwrap();
            fs::write(
                prepared.registry.join(bundle).join("undeclared.txt"),
                b"not in manifest\n",
            )
            .unwrap();
        }
    }
    fs::copy(&prepared.policy, &prepared.initialization_policy).unwrap();
    if case.setup == Setup::HistoricalPolicy {
        edit_json(&prepared.policy, |value| {
            value["continuedUse"] = "previous-authorization".into();
        });
    }
    prepared
}

/// Mutations that require an explicitly provisioned store occur only after init succeeds.
pub fn after_initialize(case: &Case, prepared: &Prepared) {
    match case.setup {
        Setup::MissingEstablishedState => {
            fs::remove_file(prepared.state.join("trust.sqlite")).unwrap();
        }
        Setup::CorruptState => {
            fs::write(
                prepared.state.join("trust.sqlite"),
                b"not a SQLite database\n",
            )
            .unwrap();
        }
        Setup::UncertainState => {
            fs::write(
                prepared.state.join("operation"),
                b"unresolved prior operation\n",
            )
            .unwrap();
        }
        _ => {}
    }
}
