//! Conditional claim controls bound to the first genuine sealed Node report.
//! Proposed child of pipeline::installed_client_tests. No new live measurement.
//! Historical real DATA is a byte-exact test asset, not a new runtime claim.
use super::*;
use crate::workbench::model_originals::workflow::{
    Decode, installed_measurements::InstalledClientMeasurements,
};
use crate::workbench::{Report, RunConfiguration, check_report_configured};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{fs, path::PathBuf};

const REPORT_SHA: &str = "e218f27f94c099d0683a2e3beeec3aeb568ce35d5c33c79ddf9682d5f832ac98";
const CASES_SHA: &str = "26559149b6a1e67e13a4e59422ebf5e22f399799f3f28eba0b20c7002919e26e";
const POLICY_SHA: &str = "2e210b9a852352118beb755fb0aa74bf08d51b33499a46140fc948d77d1473b4";
const MEASUREMENT: &str = "/records/0/evidence/measurement";
mod mutations {
    include!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/support/installed_sealed_claim_mutations.rs"
    ));
}
use mutations::{MUTATIONS, Mutation, SOURCE, WORKERS, altered};

struct Input {
    root: tempfile::TempDir,
    report_raw: String,
    report: Value,
    cases: String,
    policy_raw: String,
    checker_policy: String,
}
fn read_exact(bytes: &[u8], expected: &str) -> String {
    let sha: String = Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    assert_eq!(sha, expected, "immutable genuine handoff input");
    String::from_utf8(bytes.to_vec()).unwrap()
}
impl Input {
    fn load() -> Self {
        let root = tempfile::tempdir().unwrap();
        let report_raw = read_exact(
            include_bytes!("sealed_claims_controls/node-report.json"),
            REPORT_SHA,
        );
        let cases = read_exact(CORPUS.as_bytes(), CASES_SHA);
        let policy_raw = read_exact(
            include_bytes!("sealed_claims_controls/checker-policy-v3.json"),
            POLICY_SHA,
        );
        fs::create_dir(root.path().join("kit")).unwrap();
        fs::write(root.path().join("kit/cases.json"), cases.as_bytes()).unwrap();
        let report: Value = serde_json::from_str(&report_raw).unwrap();
        let configuration: Value = serde_json::from_str(&policy_raw).unwrap();
        assert_eq!(report["records"].as_array().unwrap().len(), 24);
        assert_eq!(
            report["records"][0]["evidence"]["kind"],
            "client-process-measured"
        );
        assert_eq!(report["errors"][0]["code"], "expected-blocked");
        assert_eq!(report["qualified"], false);
        assert_eq!(
            report.pointer(&format!("{SOURCE}/kind")).unwrap(),
            "sealed-complete"
        );
        assert_eq!(
            report.pointer(&format!("{WORKERS}/kind")).unwrap(),
            "joined-cleanup"
        );
        Self {
            root,
            report_raw,
            report,
            cases,
            policy_raw,
            checker_policy: configuration["checker"].to_string(),
        }
    }
    fn evaluate(&self, report: &Value) -> ObservationError {
        // SAME canonical full24 preparation, actual policy checker fields,
        // decoder, recipe comparisons and CompareOwner as factual controls.
        let source = source(&self.cases);
        let policy = policy(&self.checker_policy);
        let raw = report.pointer(MEASUREMENT).unwrap().to_string();
        let mut result = None;
        prepared_installed_client(
            &source,
            &policy,
            ReviewedSources::installed_client_selected(),
            |inventory, owners| {
                assert_eq!(inventory.len(), 24);
                let document = owners.decode.literal_with_raw(&raw).unwrap().0;
                let actual = InstalledClientMeasurements::decode(&document, &mut owners.decode)
                    .expect("mutation preserves the existing strict wire shape");
                result = Some(
                    inventory
                        .invocation()
                        .compiled_source()
                        .report_context()
                        .check_installed_process(&actual, &mut owners.comparison)
                        .expect_err("original remains unqualified"),
                );
                Ok(())
            },
        )
        .unwrap();
        result.unwrap()
    }
    fn public_replay(&self, raw: &str) -> Result<(), String> {
        let report = Report::from_json(raw)?;
        let configuration = RunConfiguration::from_json(&self.policy_raw)?;
        check_report_configured(&self.root.path().join("kit"), &report, &configuration)
    }
}

fn check(mutation: Mutation) {
    let input = Input::load();
    let report = altered(&input.report, mutation);
    let cause = input.evaluate(&report);
    let replay = input.public_replay(&report.to_string());
    eprintln!("{}: cause={cause:?}; public={replay:?}", mutation.name());
    assert_eq!(
        format!("{cause:?}"),
        mutation.expected(),
        "exact same-checker cause"
    );
    if matches!(mutation, Mutation::OpenSourceWithJoinedWorkers) {
        replay.expect("weaker source with joined workers stays valid unqualified evidence");
    } else {
        assert_eq!(replay.unwrap_err(), "saved first failure differs");
    }
}
#[test]
fn sealed_b00_genuine_node_report_replays_without_new_positive_data() {
    let input = Input::load();
    assert_eq!(
        input.evaluate(&input.report),
        ObservationError::ExpectedBlocked
    );
    input.public_replay(&input.report_raw).unwrap();
}
macro_rules! control {
    ($name:ident, $mutation:ident) => {
        #[test]
        fn $name() {
            check(Mutation::$mutation);
        }
    };
}
control!(sealed_s01_prefix_mismatch, PrefixMismatch);
control!(sealed_s02_prefix_overflow, PrefixOverflow);
control!(sealed_s03a_duplicate_role, DuplicateRole);
control!(sealed_s03b_missing_role, MissingRole);
control!(sealed_s03c_foreign_path, ForeignPath);
control!(sealed_s04_sentinel_attempt, SentinelAttempt);
control!(sealed_s05a_record_minimum, RecordMinimum);
control!(sealed_s05b_primary_minimum, PrimaryMinimum);
control!(sealed_s06_witness_overflow, WitnessOverflow);
control!(
    sealed_w01_sealed_with_observed_workers,
    SealedWithObservedWorkers
);
control!(sealed_w02a_owned_handle, OwnedHandle);
control!(sealed_w02b_dropped_handle, DroppedHandle);
control!(sealed_w03_empty_joined, EmptyJoined);
control!(sealed_w04a_normal_join_mismatch, NormalJoinMismatch);
control!(sealed_w04b_panic_join_mismatch, PanicJoinMismatch);
control!(sealed_w04c_body_mismatch, BodyMismatch);
control!(sealed_w04d_cancel_mismatch, CancelMismatch);
control!(sealed_w04e_normal_overflow, NormalOverflow);
control!(sealed_w04f_cancel_overflow, CancelOverflow);
control!(sealed_w05a_all_cancelled_despite_ready_record, AllCancelled);
control!(
    sealed_w05b_all_returned_error_despite_ready_record,
    AllReturnedError
);
control!(
    sealed_w06a_open_source_all_cancelled_cannot_corroborate_selected_ready,
    OpenAllCancelled
);
control!(
    sealed_w06b_open_source_all_returned_error_cannot_corroborate_selected_ready,
    OpenAllReturnedError
);
control!(
    sealed_c01_open_source_with_joined_workers,
    OpenSourceWithJoinedWorkers
);

#[test]
#[ignore = "explicit mutation export only; not a checker runtime or role qualification"]
fn sealed_export_exact_actual_report_mutations() {
    let input = Input::load();
    let output = PathBuf::from(
        std::env::var_os("MORPHIR_MCK_SEALED_MUTATIONS_OUT")
            .expect("explicit new absolute export directory required"),
    );
    assert!(output.is_absolute());
    fs::create_dir(&output).expect("refuse existing output and partial overwrite");
    fs::write(
        output.join("b00-original.json"),
        input.report_raw.as_bytes(),
    )
    .unwrap();
    let mut manifest = Vec::new();
    for mutation in MUTATIONS {
        let report = altered(&input.report, mutation);
        let bytes = serde_json::to_vec(&report).unwrap();
        fs::write(output.join(format!("{}.json", mutation.name())), &bytes).unwrap();
        manifest.push(json!({"id":mutation.name(),"expectedCause":mutation.expected()}));
    }
    fs::write(
        output.join("mutations.json"),
        serde_json::to_vec_pretty(&manifest).unwrap(),
    )
    .unwrap();
}
