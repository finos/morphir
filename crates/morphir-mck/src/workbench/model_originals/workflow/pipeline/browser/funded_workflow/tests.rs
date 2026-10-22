//! Fixed backing storage controls only, not a BrowserRun or physical effects.
use super::{funded_workflow::BrowserPhysicalBuffers, inputs::BrowserOwnerLoans};
use crate::{
    json::strict::Document,
    transport::Limits,
    workbench::{
        configuration::InstalledObservationLimits,
        model_originals::workflow::{
            decode::{DecodeError, OperandResource},
            pipeline::browser::inputs::BrowserInputFault,
            pipeline::{
                installed::observation::{
                    InstalledObservationFault, InstalledObservationOwner,
                    InstalledObservationResource,
                },
                policy::{Owners, Policy},
            },
        },
    },
};
const CHECKER: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
));
const WINDOW: usize = 13;
#[path = "source_scope_tests.rs"]
mod source_scope_tests;
fn limits() -> Limits {
    Limits {
        max_frame: 17,
        stderr_capture: 11,
        ..Limits::DEFAULT
    }
}
fn requested() -> usize {
    std::mem::size_of::<BrowserPhysicalBuffers>() + 3 * 17 + 2 * 11 + WINDOW
}
pub(super) fn owners(
    retained: usize,
    slots: usize,
    visits: usize,
) -> (Owners, InstalledObservationOwner) {
    let mut checker: serde_json::Value = serde_json::from_str(CHECKER).unwrap();
    checker["decode"]["slots"] = slots.into();
    let checker = Policy::from_document(
        &Document::parse_unsigned_counts(checker.to_string().as_bytes()).unwrap(),
    )
    .unwrap()
    .owners();
    let counts = format!(
        r#"{{"rpcFrames":"checker-capture","retainedBytes":{retained},"stdoutPrefixBytes":1000,"stderrPrefixBytes":1000,"snapshotReadBytes":0,"byteVisits":{visits},"records":0}}"#
    );
    let receiving = InstalledObservationOwner::new(
        &InstalledObservationLimits::from_document(
            &Document::parse_unsigned_counts(counts.as_bytes()).unwrap(),
        )
        .unwrap(),
    );
    (checker, receiving)
}
#[test]
fn funded_browser_01_zero_one_short_storage_refuses_before_any_fixed_buffer_result() {
    for retained in [0, requested() - 1] {
        let (mut owner, mut receiving) = owners(retained, 100, 1000);
        let fault = BrowserPhysicalBuffers::prepare(
            &mut BrowserOwnerLoans::new(&mut owner, &mut receiving),
            limits(),
            WINDOW,
        )
        .err()
        .unwrap();
        assert!(
            matches!(fault,BrowserInputFault::Receiving(InstalledObservationFault::Resource{kind:InstalledObservationResource::RetainedBytes,used:0,requested:amount,..}) if amount==requested() as u64)
        );
        assert_eq!(receiving.usage().retained_bytes(), 0);
        assert_eq!(receiving.usage().byte_visits(), 0);
        let used = (owner.decode.usage(), receiving.usage());
        let retry = BrowserPhysicalBuffers::prepare(
            &mut BrowserOwnerLoans::new(&mut owner, &mut receiving),
            limits(),
            usize::MAX,
        )
        .err()
        .unwrap();
        assert!(matches!(
            retry,
            BrowserInputFault::Receiving(InstalledObservationFault::Resource {
                kind: InstalledObservationResource::RetainedBytes,
                ..
            })
        ));
        assert_eq!(
            (owner.decode.usage(), receiving.usage()),
            used,
            "first refusal wins before later overflow or work"
        );
    }
}
#[test]
fn funded_browser_02_zero_one_short_slots_refuses_before_storage_or_initialization() {
    for (slots, used_slots) in [(1, 1), (5, 0)] {
        let (mut owner, mut receiving) = owners(requested(), slots, 1000);
        owner.decode.slots(used_slots).unwrap();
        let fault = BrowserPhysicalBuffers::prepare(
            &mut BrowserOwnerLoans::new(&mut owner, &mut receiving),
            limits(),
            WINDOW,
        )
        .err()
        .unwrap();
        assert!(matches!(
            fault,
            BrowserInputFault::Decode(DecodeError::Work(OperandResource::Slots))
        ));
        assert_eq!(owner.decode.usage().slots, used_slots);
        assert_eq!(receiving.usage().retained_bytes(), 0);
        assert_eq!(receiving.usage().byte_visits(), 0);
    }
}
#[test]
fn funded_browser_03_actual_capacities_initialized_lengths_and_same_owner_loans() {
    let (mut owner, mut receiving) = owners(requested(), 100, 1000);
    let decoder = std::ptr::from_ref(&owner.decode);
    let storage = std::ptr::from_ref(&receiving);
    let comparison = std::ptr::from_ref(&owner.comparison);
    let mut loans = BrowserOwnerLoans::new(&mut owner, &mut receiving);
    {
        let (actual_decode, actual_receiving, actual_comparison) = loans.physical_owners().unwrap();
        assert!(std::ptr::eq(actual_decode, decoder));
        assert!(std::ptr::eq(actual_receiving, storage));
        assert!(std::ptr::eq(actual_comparison, comparison));
    }
    let buffers = BrowserPhysicalBuffers::prepare(&mut loans, limits(), WINDOW).unwrap();
    assert_eq!(buffers.lengths(), [0, 0, 0, 0, 17, WINDOW]);
    let capacities = buffers.capacities();
    for (actual, minimum) in capacities.into_iter().zip([17, 11, 17, 11, 17, WINDOW]) {
        assert!(actual >= minimum);
    }
    drop(loans);
    assert_eq!(
        receiving.usage().retained_bytes(),
        (std::mem::size_of::<BrowserPhysicalBuffers>() + capacities.into_iter().sum::<usize>())
            as u64
    );
    assert_eq!(owner.decode.usage().slots, 6);
    assert_eq!(receiving.usage().stdout_prefix_bytes(), 34);
    assert_eq!(receiving.usage().stderr_prefix_bytes(), 22);
    assert_eq!(receiving.usage().byte_visits(), 30);
    assert_eq!(owner.decode.usage().byte_visits, 30);
}
#[test]
fn funded_browser_04_cumulative_storage_not_refunded_and_prior_work_refusal_sticky() {
    let (mut owner, mut receiving) = owners(requested() * 2, 100, 1000);
    for _ in 0..2 {
        let buffers = BrowserPhysicalBuffers::prepare(
            &mut BrowserOwnerLoans::new(&mut owner, &mut receiving),
            limits(),
            WINDOW,
        )
        .unwrap();
        drop(buffers);
    }
    let refused = BrowserPhysicalBuffers::prepare(
        &mut BrowserOwnerLoans::new(&mut owner, &mut receiving),
        limits(),
        WINDOW,
    )
    .err()
    .unwrap();
    assert!(matches!(
        refused,
        BrowserInputFault::Receiving(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::RetainedBytes,
            ..
        })
    ));
    let used = (owner.decode.usage(), receiving.usage());
    assert!(
        BrowserPhysicalBuffers::prepare(
            &mut BrowserOwnerLoans::new(&mut owner, &mut receiving),
            limits(),
            WINDOW
        )
        .is_err()
    );
    assert_eq!((owner.decode.usage(), receiving.usage()), used);
    let (mut owner, mut receiving) = owners(requested(), 100, 29);
    let refused = BrowserPhysicalBuffers::prepare(
        &mut BrowserOwnerLoans::new(&mut owner, &mut receiving),
        limits(),
        WINDOW,
    )
    .err()
    .unwrap();
    assert!(matches!(
        refused,
        BrowserInputFault::Receiving(InstalledObservationFault::Resource {
            kind: InstalledObservationResource::ByteVisits,
            ..
        })
    ));
    let used = (owner.decode.usage(), receiving.usage());
    assert!(
        BrowserPhysicalBuffers::prepare(
            &mut BrowserOwnerLoans::new(&mut owner, &mut receiving),
            limits(),
            WINDOW
        )
        .is_err()
    );
    assert_eq!((owner.decode.usage(), receiving.usage()), used);
}
