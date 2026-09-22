// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Resolve case setup only. Callers execute the real CLI and compare the frozen lock.
#[path = "package_mvp.rs"]
pub mod mvp;

use serde::Deserialize;
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
};

pub const ROOT: &str = "example.com/finance/loan-rules@1.0.0";
pub const EXPECTED_LOCK: &str =
    "spec/package/mck/fixtures/mvp-fresh-restore/expected/resolve.lock.json";

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Expected {
    Resolved,
    Refused,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Case {
    pub id: String,
    pub setup: mvp::Setup,
    pub expected: Expected,
    #[serde(default)]
    pub root: Option<String>,
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
    serde_json::from_slice(&fs::read(source.join(mvp::PATH).join("resolve-cases.json")).unwrap())
        .unwrap()
}

pub struct Prepared {
    pub restore: mvp::Prepared,
    pub root: String,
    pub output: PathBuf,
}

fn restore_case(case: &Case) -> mvp::Case {
    mvp::Case {
        id: case.id.clone(),
        setup: if case.setup == mvp::Setup::OccupiedOutput {
            mvp::Setup::Fresh
        } else {
            case.setup
        },
        expected: mvp::Expected::Refused,
        diagnostic: case.diagnostic.clone(),
    }
}

/// Preserve the pre-existing fixture lock while preparing a distinct new lock destination.
pub fn prepare(source: &Path, directory: &Path, case: &Case) -> Prepared {
    let restore = mvp::prepare(source, directory, &restore_case(case));
    let output = directory.join("consumer/morphir.lock");
    if case.setup == mvp::Setup::OccupiedOutput {
        fs::write(&output, mvp::SENTINEL).unwrap();
    }
    Prepared {
        restore,
        root: case.root.clone().unwrap_or_else(|| ROOT.to_owned()),
        output,
    }
}

pub fn after_initialize(case: &Case, prepared: &Prepared) {
    mvp::after_initialize(&restore_case(case), &prepared.restore);
}
