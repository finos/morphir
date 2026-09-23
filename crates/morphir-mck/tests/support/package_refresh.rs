// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
//! Metadata refresh case setup only. Callers execute the real CLI and compare the frozen receipt.
#[path = "package_mvp.rs"]
pub mod mvp;

use serde::Deserialize;
use serde_json::Value;
use std::{fs, path::Path};

pub const EXPECTED_RECEIPT: &str =
    "spec/package/mck/fixtures/mvp-fresh-restore/expected/refresh.json";

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Setup {
    Fresh,
    TamperedSignature,
    ExpiredTimestamp,
    UninitializedState,
    MissingEstablishedState,
    CorruptState,
    UncertainState,
    HistoricalPolicy,
    DamagedBundle,
    MissingBundle,
    DamagedPublisherEnvelope,
    MissingPublisherEnvelope,
    DamagedRecord,
    MissingRecord,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Expected {
    Refreshed,
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
    serde_json::from_slice(&fs::read(source.join(mvp::PATH).join("refresh-cases.json")).unwrap())
        .unwrap()
}

fn restore_case(case: &Case) -> mvp::Case {
    let setup = match case.setup {
        Setup::TamperedSignature => mvp::Setup::TamperedSignature,
        Setup::ExpiredTimestamp => mvp::Setup::ExpiredTimestamp,
        Setup::UninitializedState => mvp::Setup::UninitializedState,
        Setup::MissingEstablishedState => mvp::Setup::MissingEstablishedState,
        Setup::CorruptState => mvp::Setup::CorruptState,
        Setup::UncertainState => mvp::Setup::UncertainState,
        Setup::HistoricalPolicy => mvp::Setup::HistoricalPolicy,
        Setup::Fresh
        | Setup::DamagedBundle
        | Setup::MissingBundle
        | Setup::DamagedPublisherEnvelope
        | Setup::MissingPublisherEnvelope
        | Setup::DamagedRecord
        | Setup::MissingRecord => mvp::Setup::Fresh,
    };
    mvp::Case {
        id: case.id.clone(),
        setup,
        expected: mvp::Expected::Refused,
        diagnostic: case.diagnostic.clone(),
    }
}

/// Alter only isolated fixture copies; package assets are not inputs to metadata refresh.
pub fn prepare(source: &Path, directory: &Path, case: &Case) -> mvp::Prepared {
    let prepared = mvp::prepare(source, directory, &restore_case(case));
    let asset_directory = match case.setup {
        Setup::DamagedBundle | Setup::MissingBundle => Some("bundles"),
        Setup::DamagedPublisherEnvelope | Setup::MissingPublisherEnvelope => {
            Some("targets/statements")
        }
        Setup::DamagedRecord | Setup::MissingRecord => Some("targets/records"),
        _ => None,
    };
    if let Some(asset_directory) = asset_directory {
        let directory = prepared.registry.join(asset_directory);
        for entry in fs::read_dir(directory).unwrap() {
            let entry = entry.unwrap();
            match case.setup {
                Setup::DamagedBundle => {
                    fs::write(entry.path().join("ir.json"), b"damaged package IR\n").unwrap();
                }
                Setup::MissingBundle => fs::remove_dir_all(entry.path()).unwrap(),
                Setup::DamagedPublisherEnvelope | Setup::DamagedRecord => {
                    fs::write(entry.path(), b"damaged package evidence\n").unwrap();
                }
                Setup::MissingPublisherEnvelope | Setup::MissingRecord => {
                    fs::remove_file(entry.path()).unwrap();
                }
                _ => unreachable!(),
            }
        }
    }
    prepared
}

pub fn after_initialize(case: &Case, prepared: &mvp::Prepared) {
    mvp::after_initialize(&restore_case(case), prepared);
}
