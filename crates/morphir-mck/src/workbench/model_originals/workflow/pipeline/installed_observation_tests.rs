//! Offgraph source-first controls for the proposed receiving owner only.
//! Mount as a new pipeline child after root review; no old tests changed.
//! These tests create no host/process, completed observation or verdict.
use super::installed::observation::*;
use super::*;
use crate::json::strict::Document;
use crate::workbench::configuration::InstalledObservationLimits;

const POLICY: &str = r#"{"rpcFrames":"checker-capture","retainedBytes":128,"stdoutPrefixBytes":10,"stderrPrefixBytes":6,"snapshotReadBytes":8,"byteVisits":128,"records":2}"#;
const ZERO: &str = r#"{"rpcFrames":"checker-capture","retainedBytes":0,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":0,"records":0}"#;
fn limits(raw: &str) -> Result<InstalledObservationLimits, String> {
    InstalledObservationLimits::from_document(&Document::parse_unsigned_counts(raw.as_bytes())?)
}
fn owner(raw: &str) -> InstalledObservationOwner {
    InstalledObservationOwner::new(&limits(raw).unwrap())
}
fn process_limits(stdout: usize, stderr: usize) -> crate::transport::Limits {
    crate::transport::Limits {
        max_frame: stdout,
        stderr_capture: stderr,
        request_timeout: std::time::Duration::from_secs(1),
        session_timeout: std::time::Duration::from_secs(1),
        exit_grace: std::time::Duration::from_secs(1),
        shutdown_grace: std::time::Duration::from_secs(1),
    }
}

#[test]
fn installed_policy_is_closed_canonical_and_zero_has_no_credit() {
    assert!(limits(POLICY).is_ok());
    assert!(limits(ZERO).is_ok());
    for token in ["null", "-0", "-1", "1.0", "1e0", "18446744073709551616"] {
        assert!(
            limits(&POLICY.replace(
                "\"retainedBytes\":128",
                &format!("\"retainedBytes\":{token}")
            ))
            .is_err()
        );
    }
    assert!(limits(&POLICY.replace("\"rpcFrames\":\"checker-capture\",", "")).is_err());
    assert!(limits(&POLICY.replace("checker-capture", "stdout-as-reply")).is_err());
    assert!(limits(&POLICY.replace("\"records\":2", "\"records\":2,\"unknown\":0")).is_err());
    assert!(limits(&POLICY.replace("\"records\":2", "\"records\":2,\"records\":2")).is_err());
}

#[test]
fn installed_requested_process_prefixes_are_cumulative_not_actual_output_sized() {
    let mut owner = owner(POLICY);
    owner
        .reserve_process_prefixes(&process_limits(6, 4))
        .unwrap()
        .commit();
    owner
        .reserve_process_prefixes(&process_limits(4, 2))
        .unwrap()
        .commit();
    assert_eq!(owner.usage().stdout_prefix_bytes(), 10);
    assert_eq!(owner.usage().stderr_prefix_bytes(), 6);
    assert!(matches!(
        owner.reserve_process_prefixes(&process_limits(1, 0)),
        Err(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::StdoutPrefixBytes,
            ..
        })
    ));
    assert_eq!(owner.usage().stdout_prefix_bytes(), 10);
}

#[test]
fn installed_zero_prefix_policy_refuses_before_a_real_spawn_can_be_attempted() {
    let mut owner = owner(ZERO);
    assert!(matches!(
        owner.reserve_process_prefixes(&process_limits(1, 0)),
        Err(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::StdoutPrefixBytes,
            ..
        })
    ));
    assert_eq!(owner.usage().stdout_prefix_bytes(), 0);
    assert!(owner.ready().is_err());
}

#[test]
fn installed_snapshot_read_spans_spend_requested_bytes_even_on_short_reads() {
    let mut owner = owner(POLICY);
    owner.prepare_snapshot_read(5).unwrap().finish(2).unwrap();
    owner.prepare_snapshot_read(3).unwrap().finish(0).unwrap();
    assert_eq!(owner.usage().snapshot_read_bytes(), 8);
    assert!(matches!(
        owner.prepare_snapshot_read(1),
        Err(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::SnapshotReadBytes,
            ..
        })
    ));
    assert_eq!(owner.usage().snapshot_read_bytes(), 8);
}

#[test]
fn installed_snapshot_overreturn_is_refused_without_refund() {
    let mut owner = owner(POLICY);
    assert!(owner.prepare_snapshot_read(3).unwrap().finish(4).is_err());
    assert_eq!(owner.usage().snapshot_read_bytes(), 3);
    assert!(owner.ready().is_err());
}

#[test]
fn installed_record_zero_exact_and_one_over_are_real_issuance_permissions() {
    let mut zero = owner(ZERO);
    assert!(zero.prepare_record(ObservationRecordRole::Mailbox).is_err());
    assert_eq!(zero.usage().records(), 0);
    let mut owner = owner(POLICY);
    let mailbox = owner
        .prepare_record(ObservationRecordRole::Mailbox)
        .unwrap()
        .issue();
    let process = owner
        .prepare_record(ObservationRecordRole::Process)
        .unwrap()
        .issue();
    assert_eq!(owner.usage().records(), 2);
    drop((mailbox, process));
    assert!(
        owner
            .prepare_record(ObservationRecordRole::Process)
            .is_err()
    );
    assert_eq!(owner.usage().records(), 2);
}

#[test]
fn installed_dropped_ticket_is_abandoned_and_never_refunds_permission() {
    let mut owner = owner(POLICY);
    drop(owner.prepare_snapshot_read(5).unwrap());
    assert_eq!(owner.usage().snapshot_read_bytes(), 5);
    assert!(matches!(
        owner.ready(),
        Err(InstalledObservationFault::Abandoned)
    ));
    assert!(matches!(
        owner.prepare_record(ObservationRecordRole::Process),
        Err(InstalledObservationFault::Abandoned)
    ));
    assert_eq!(owner.usage().records(), 0);
}

#[test]
fn installed_prior_resource_fault_survives_later_abandoned_or_other_requests() {
    let mut owner = owner(ZERO);
    assert!(matches!(
        owner.prepare_snapshot_read(1),
        Err(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::SnapshotReadBytes,
            ..
        })
    ));
    assert!(matches!(
        owner.reserve_process_prefixes(&process_limits(1, 0)),
        Err(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::SnapshotReadBytes,
            ..
        })
    ));
    assert_eq!(owner.usage().stdout_prefix_bytes(), 0);
    assert_eq!(owner.usage().snapshot_read_bytes(), 0);
}

fn checker() -> Owners {
    let raw = include_str!("installed_client_controls/checker-policy.json");
    Policy::from_document(&Document::parse_exact(raw.as_bytes()).unwrap())
        .unwrap()
        .owners()
}

#[test]
fn installed_copy_keeps_actual_literal_bytes_and_charges_obtained_capacity() {
    let mut owner = owner(POLICY);
    let mut existing = checker();
    let literal = [0, 255, 13, 10, 128];
    let kept = prepare_copy(
        &mut owner,
        &mut existing.comparison,
        ObservationBufferRole::CensusMetadata,
        &literal,
    )
    .unwrap()
    .retain()
    .unwrap();
    assert_eq!(kept.as_bytes(), literal);
    assert!(kept.capacity() >= literal.len());
    assert_eq!(
        owner.usage().retained_bytes(),
        u64::try_from(kept.capacity()).unwrap()
    );
    assert_eq!(owner.usage().byte_visits(), 5);
    assert!(owner.ready().is_ok());
}

#[test]
fn installed_copy_one_less_requested_capacity_refuses_before_retention() {
    let mut owner = owner(&POLICY.replace("\"retainedBytes\":128", "\"retainedBytes\":4"));
    let mut existing = checker();
    let literal = [0, 255, 13, 10, 128];
    assert!(matches!(
        prepare_copy(
            &mut owner,
            &mut existing.comparison,
            ObservationBufferRole::CensusMetadata,
            &literal
        ),
        Err(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::RetainedBytes,
            ..
        })
    ));
    assert_eq!(owner.usage().retained_bytes(), 0);
}

#[test]
fn installed_copy_one_less_visit_permission_refuses_actual_five_byte_copy() {
    let mut owner = owner(&POLICY.replace("\"byteVisits\":128", "\"byteVisits\":4"));
    let mut existing = checker();
    let literal = [0, 255, 13, 10, 128];
    assert!(matches!(
        prepare_copy(
            &mut owner,
            &mut existing.comparison,
            ObservationBufferRole::CensusMetadata,
            &literal
        ),
        Err(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::ByteVisits,
            ..
        })
    ));
    assert_eq!(owner.usage().byte_visits(), 0);
}

#[test]
fn installed_prior_real_comparison_fault_precedes_copy_or_installed_spend() {
    use crate::workbench::model_originals::workflow::observation_check::{
        CompareLimits, CompareOwner,
    };
    let mut comparison = CompareOwner::new(CompareLimits::new(0, 0, 0).unwrap());
    assert!(comparison.preflight_owned_text(1).is_err());
    let mut owner = owner(POLICY);
    assert!(matches!(
        prepare_copy(
            &mut owner,
            &mut comparison,
            ObservationBufferRole::CensusMetadata,
            b"x"
        ),
        Err(InstalledObservationFault::PriorFault)
    ));
    assert!(comparison.ready().is_err());
    assert_eq!(owner.usage().retained_bytes(), 0);
    assert_eq!(owner.usage().byte_visits(), 0);
}

// Actual RPC capture aggregation and genuine private-record adoption still
// reuse the existing run Attempt/record_retention controls. These 12 unit
// tests grant no host, source, process, complete observation or checker proof.
