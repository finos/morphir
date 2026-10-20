//! Source-first canonical preparation controls. No process/host/report work.
//! Mount as pipeline/installed_client_tests.rs with cfg(test) mod only.
use super::*;
use crate::workbench::model_originals::workflow::{
    expansion::ExpansionResource, installed_client::OriginalClientLeafValue,
    source_proof::LineageStatus,
};
use std::cell::Cell;

const CORPUS: &str = include_str!("installed_client_controls/cases24.json");
const POLICY: &str = include_str!("installed_client_controls/checker-policy.json");
const SIDE_PATH: &str = "installed-client-first-v1/materialization.json";
const SIDE: &[u8] = include_bytes!("installed_client_controls/materialization.json");
const ID: &str = "single-file-explicit-companion-preserves-opaque-bytes";

fn source(raw: &str) -> Source {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("cases.json"), raw).unwrap();
    Source::new(CorpusSource::load(dir.path()).unwrap()).unwrap()
}
fn policy(raw: &str) -> Policy {
    Policy::from_document(&Document::parse_exact(raw.as_bytes()).unwrap()).unwrap()
}
fn calls_for(raw: &str, sources: ReviewedSources<'_>) -> (Result<(), String>, usize) {
    let calls = Cell::new(0);
    let source = source(raw);
    let policy = policy(POLICY);
    let result = prepared_installed_client(&source, &policy, sources, |inventory, _owners| {
        calls.set(calls.get() + 1);
        assert_eq!(inventory.len(), 24);
        assert_eq!(inventory.invocation().case_id(), ID);
        Ok(())
    });
    (result, calls.get())
}

#[test]
fn canonical_complete24_preparation_lends_one_real_borrowed_client_invocation_only_unproven() {
    let source = source(CORPUS);
    let policy = policy(POLICY);
    let calls = Cell::new(0);
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            calls.set(calls.get() + 1);
            assert_eq!(inventory.len(), 24);
            let run = inventory.invocation();
            assert_eq!(run.case_id(), ID);
            assert_eq!(run.original_packet(), "inventory35");
            assert_eq!(run.original_id(), ID);
            assert_eq!(run.run_index(), 0);
            assert_eq!(
                run.operation(),
                crate::workbench::Operation::ModelOriginalsClient
            );
            assert_eq!(run.lineage(), LineageStatus::Unproven);
            assert_eq!(
                run.input_raw().get(),
                include_str!("installed_client_controls/input.json").trim()
            );
            assert_eq!(
                run.expected_raw().get(),
                include_str!("installed_client_controls/expected.json").trim()
            );

            // These are the maintained compiler's actual proof operands,
            // not reconstructed scenario/identity/expansion plans.
            let core = run.compiled_source();
            assert!(std::ptr::eq(
                core.source().case(),
                inventory.cases()[0].case()
            ));
            assert!(std::ptr::eq(
                core.source().paired().scenario(),
                core.expansion().scenario()
            ));
            assert!(std::ptr::eq(
                core.source().paired().scenario(),
                core.identity_input().scenario()
            ));
            assert!(!core.aliases().definitions().is_empty());
            assert!(owners.closure.usage().definitions > 0);
            assert!(owners.closure.usage().references > 0);
            assert!(
                owners
                    .expansion
                    .usage()
                    .amount(ExpansionResource::FrameBytes)
                    > 0
            );
            // Remaining23 source rows were also actually prepared before
            // this action, including the native declaration row.
            assert_eq!(
                inventory.cases()[1].case().id(),
                "explicit-empty-companion-declaration-is-complete"
            );
            Ok(())
        },
    )
    .unwrap();
    assert_eq!(calls.get(), 1);
}

#[test]
fn original_leaf_values_come_from_the_bound_original_packet_with_exact_pointer_roles() {
    let source = source(CORPUS);
    let policy = policy(POLICY);
    prepared_installed_client(&source, &policy, ReviewedSources::installed_client_selected(), |inventory, _| {
        let run = inventory.invocation();
        let leaves: Vec<_> = run.original_leaf_bindings().collect();
        assert_eq!(leaves.len(), 6);
        let pointers: Vec<_> = leaves.iter().map(|leaf| leaf.source_pointer()).collect();
        assert_eq!(pointers, [
            "/expected/modelOriginalFiles/0", "/expected/modelOriginalFiles/1",
            "/expected/companion/path", "/expected/companion/byteLength",
            "/expected/companion/sha256", "/expected/unrelatedIncluded",
        ]);
        for (index, expected) in [(0, "morphir-ir.json"), (1, "notes/opaque.bin"), (2, "notes/opaque.bin")] {
            let OriginalClientLeafValue::Path(path) = leaves[index].value() else { panic!("typed original path") };
            assert_eq!(path.as_str(), expected);
        }
        assert!(matches!(leaves[3].value(), OriginalClientLeafValue::ByteLength(4)));
        let OriginalClientLeafValue::Sha256(digest) = leaves[4].value() else { panic!("typed original digest") };
        assert_eq!(digest.bytes(), [
            0x3d,0x1f,0x57,0xc9,0x84,0x97,0x8e,0xf9,0x8a,0x18,0x37,0x8c,0x81,0x66,0xc1,0xcb,
            0x8e,0xde,0x02,0xc0,0x3e,0xeb,0x6a,0xee,0x7e,0x2f,0x12,0x1d,0xfe,0xee,0x3e,0x56,
        ]);
        assert!(matches!(leaves[5].value(), OriginalClientLeafValue::Included(false)));
        // The whole unchanged expected operand remains blocked. No UI
        // semantic owner, archive, Close, checker verdict or live grant.
        let expected = run.compiled_source().source().paired().expected();
        assert!(matches!(expected,
            super::super::domain::ExpectedWorkflow::ModelOriginalsClient {
                qualification: super::super::domain::ExpectedWorkflowModelOriginalsClientQualification::Blocked { .. }, ..
            }
        ));
        Ok(())
    }).unwrap();
}

#[test]
fn driver_actions_preserve_three_actual_commands_and_snapshot_only_checkpoint_meanings() {
    let source = source(CORPUS);
    let policy = policy(POLICY);
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, _| {
            let run = inventory.invocation();
            let tags: Vec<_> = run.actions().map(|action| action.tag()).collect();
            assert_eq!(
                tags,
                [
                    "prepare-reviewed-fixture",
                    "start-observed-native-host",
                    "run-installed-command",
                    "checkpoint",
                    "write-source-selection",
                    "run-installed-command",
                    "checkpoint",
                    "write-project-selection",
                    "run-installed-command",
                    "checkpoint",
                    "stop-and-join-owned-resources",
                    "checkpoint"
                ]
            );
            let checkpoints: Vec<_> = run
                .actions()
                .filter_map(|action| action.checkpoint_name())
                .collect();
            assert_eq!(
                checkpoints,
                [
                    "client-connected",
                    "client-project-discovered",
                    "client-publication-finished",
                    "client-and-host-joined"
                ]
            );
            assert_eq!(
                run.publication_observation(),
                super::super::installed_client::PublicationObservation::PostExitSnapshotsOnly
            );
            Ok(())
        },
    )
    .unwrap();
}

#[test]
fn complete_inventory_order_missing_row_and_last_row_raw_substitution_refuse_before_invocation() {
    for raw in [
        include_str!("installed_client_controls/wrong-order.json"),
        include_str!("installed_client_controls/missing-last.json"),
        include_str!("installed_client_controls/last-input-space.json"),
        include_str!("installed_client_controls/first-expected-space.json"),
    ] {
        let (result, calls) = calls_for(raw, ReviewedSources::installed_client_selected());
        assert!(result.is_err());
        assert_eq!(calls, 0, "no invocation before whole source preparation");
    }
}

#[test]
fn coherent_wrong_original_or_selected_run_and_wrong_role_refuse_before_invocation() {
    for raw in [
        include_str!("installed_client_controls/wrong-original.json"),
        include_str!("installed_client_controls/wrong-run.json"),
        include_str!("installed_client_controls/wrong-role.json"),
    ] {
        let (result, calls) = calls_for(raw, ReviewedSources::installed_client_selected());
        assert!(result.is_err());
        assert_eq!(calls, 0);
    }
}

#[test]
fn fixed_sidecar_and_original_packet_replacements_cannot_supply_their_own_expected_values() {
    let mut sidecar = SIDE.to_vec();
    sidecar.push(b' '); // valid JSON and same meaning; wrong exact source file
    let original = include_bytes!("installed_client_controls/preceding35.json");
    let mut altered_original = original.to_vec();
    altered_original.push(b' ');
    for (path, bytes) in [
        (SIDE_PATH, sidecar.as_slice()),
        ("preceding35.json", altered_original.as_slice()),
    ] {
        let sources = ReviewedSources::installed_client_selected().with_replacement(path, bytes);
        let (result, calls) = calls_for(CORPUS, sources);
        assert!(result.is_err());
        assert_eq!(calls, 0);
    }
}

#[test]
fn old_fixed_source_selection_does_not_issue_an_installed_client_invocation() {
    for sources in [
        ReviewedSources::selected(),
        ReviewedSources::native_selected(),
    ] {
        let (result, calls) = calls_for(CORPUS, sources);
        assert!(result.is_err());
        assert_eq!(calls, 0);
    }
}

#[test]
fn genuine_cumulative_closure_and_expansion_refusal_precedes_invocation() {
    // Explicit caller policies, not scenario/sidecar claims or new defaults.
    for text in [
        include_str!("installed_client_controls/zero-definitions-policy.json"),
        include_str!("installed_client_controls/zero-frames-policy.json"),
    ] {
        let source = source(CORPUS);
        let policy = policy(text);
        let calls = Cell::new(0);
        let result = prepared_installed_client(
            &source,
            &policy,
            ReviewedSources::installed_client_selected(),
            |_, _| {
                calls.set(calls.get() + 1);
                Ok(())
            },
        );
        assert!(result.is_err());
        assert_eq!(calls.get(), 0);
    }
}

#[cfg(test)]
mod factual;

#[cfg(test)]
mod supplement;

#[cfg(test)]
mod review;

mod witness_role_tests;

mod sealed_claims;
