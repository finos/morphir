// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Isolated test setup only. The caller executes the real CLI against frozen inputs.
#[path = "package_mvp.rs"]
pub mod mvp;
use serde::Deserialize;
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
};
pub const PATH: &str = "spec/package/mck/fixtures/mvp-scoped-update";
pub const TARGET: &str = "example.com/finance/eligibility";
pub const EXPECTED_LOCK: &str =
    "spec/package/mck/fixtures/mvp-scoped-update/signed/expected/update.lock.json";
#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Setup {
    Fresh,
    ScopeConflict,
    YankedFrozen,
    YankedRoot,
    RevokedFrozen,
    InvalidGraph,
    AcquisitionPin,
    StatementPin,
    TamperedSignature,
    TamperedContent,
    ExpiredTimestamp,
    UninitializedState,
    OccupiedOutput,
    MissingEstablishedState,
    CorruptState,
    UncertainState,
}
#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Expected {
    Updated,
    Refused,
}
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Case {
    pub id: String,
    pub setup: Setup,
    pub targets: Vec<String>,
    pub expected: Expected,
    pub exit_code: i32,
    #[serde(default)]
    pub expected_lock: Option<String>,
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
    pub restore: mvp::Prepared,
    pub targets: Vec<String>,
    pub output: PathBuf,
}
fn copy_tree(source: &Path, destination: &Path) {
    fs::create_dir_all(destination).unwrap();
    for entry in fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let kind = entry.file_type().unwrap();
        assert!(!kind.is_symlink());
        let target = destination.join(entry.file_name());
        if kind.is_dir() {
            copy_tree(&entry.path(), &target)
        } else {
            assert!(kind.is_file());
            fs::copy(entry.path(), target).unwrap();
        }
    }
}
fn edit(path: &Path, mutate: impl FnOnce(&mut Value)) {
    let mut value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    mutate(&mut value);
    fs::write(path, serde_json::to_vec_pretty(&value).unwrap()).unwrap();
}
pub fn prepare(source: &Path, directory: &Path, case: &Case) -> Prepared {
    assert!(fs::read_dir(directory).unwrap().next().is_none());
    copy_tree(&source.join(PATH).join("signed"), directory);
    let restore = mvp::Prepared {
        policy: directory.join("trust-policy.json"),
        initialization_policy: directory.join("initialization-policy.json"),
        root: directory.join("registry/metadata/1.root.json"),
        lock: directory.join("morphir.lock"),
        registry: directory.join("registry"),
        state: directory.join("trust-state"),
        output: directory.join("consumer/libraries"),
        initialize: case.setup != Setup::UninitializedState,
    };
    let output = directory.join("consumer/morphir.lock");
    fs::create_dir_all(output.parent().unwrap()).unwrap();
    match case.setup {
        Setup::ScopeConflict | Setup::YankedFrozen | Setup::YankedRoot | Setup::RevokedFrozen => {
            let variant = match case.setup {
                Setup::ScopeConflict => "scope-conflict",
                Setup::YankedFrozen => "yanked-frozen",
                Setup::YankedRoot => "yanked-root",
                _ => "revoked-frozen",
            };
            copy_tree(
                &directory.join("variants").join(variant),
                &restore.registry.join("metadata"),
            );
        }
        Setup::InvalidGraph => edit(&restore.lock, |v| {
            v["graph"]["nodes"][0]["bindings"][0]["target"]["version"] = "9.9.9".into()
        }),
        Setup::AcquisitionPin => edit(&restore.lock, |v| {
            v["acquisitions"][0]["record"]["digest"] = format!("sha256:{}", "00".repeat(32)).into()
        }),
        Setup::StatementPin => edit(&restore.lock, |v| {
            let e = v["evidence"]
                .as_array_mut()
                .unwrap()
                .iter_mut()
                .find(|e| e["kind"] == "release-statement")
                .unwrap();
            e["digest"] = format!("sha256:{}", "00".repeat(32)).into();
        }),
        Setup::TamperedSignature => {
            for file in ["timestamp.json", "2.timestamp.json"] {
                edit(&restore.registry.join("metadata").join(file), |v| {
                    v["signatures"][0]["sig"] = "00".repeat(64).into()
                });
            }
        }
        Setup::ExpiredTimestamp => {
            let expired = fs::read(directory.join("variants/expired-timestamp.json")).unwrap();
            for file in ["timestamp.json", "2.timestamp.json"] {
                fs::write(restore.registry.join("metadata").join(file), &expired).unwrap();
            }
        }
        Setup::TamperedContent => {
            let lock: Value = serde_json::from_slice(&fs::read(&restore.lock).unwrap()).unwrap();
            let acquisition = lock["acquisitions"]
                .as_array()
                .unwrap()
                .iter()
                .find(|a| a["release"]["packagePath"] == "example.com/finance/sibling")
                .unwrap();
            let path = restore
                .registry
                .join(acquisition["source"]["path"].as_str().unwrap())
                .join("ir.json");
            let mut data = fs::read(&path).unwrap();
            data.push(b'\n');
            fs::write(path, data).unwrap();
        }
        Setup::OccupiedOutput => fs::write(&output, mvp::SENTINEL).unwrap(),
        _ => {}
    }
    fs::copy(&restore.policy, &restore.initialization_policy).unwrap();
    Prepared {
        restore,
        targets: case.targets.clone(),
        output,
    }
}
pub fn after_initialize(case: &Case, prepared: &Prepared) {
    let setup = match case.setup {
        Setup::MissingEstablishedState => mvp::Setup::MissingEstablishedState,
        Setup::CorruptState => mvp::Setup::CorruptState,
        Setup::UncertainState => mvp::Setup::UncertainState,
        _ => mvp::Setup::Fresh,
    };
    mvp::after_initialize(
        &mvp::Case {
            id: case.id.clone(),
            setup,
            expected: mvp::Expected::Refused,
            diagnostic: case.diagnostic.clone(),
        },
        &prepared.restore,
    );
}
