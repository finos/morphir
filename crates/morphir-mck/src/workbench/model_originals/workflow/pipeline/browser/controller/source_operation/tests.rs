//! Source/physical budget association only. No browser or UI action runs.
use super::super::super::adapter::execution_loans::{
    with_foreign_source_controller_lifetime, with_full_controller_setup,
    with_source_controller_lifetime,
};
use super::super::{
    Limits,
    acquisition::{ControllerFileInput, ControllerTargetInput},
};
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::observation::InstalledObservationResource;
use std::path::Path;

fn target() -> ControllerTargetInput<'static> {
    let file = ControllerFileInput {
        path: Path::new("/private/unopened-controller-file"),
        byte_length: 0,
    };
    ControllerTargetInput {
        chromium: file,
        node: file,
        core_bundle: file,
        entry: file,
        root: Path::new("/private/unopened-controller-root"),
    }
}
fn limits() -> Limits {
    Limits {
        max_frame: 128,
        stderr_capture: 64,
        ..Limits::DEFAULT
    }
}

#[test]
fn source_operation_prepay_01_exact_lifetime_limits_and_target_are_prepared_without_effects() {
    with_source_controller_lifetime(|lifetime, loans| {
        let original_end = lifetime.end();
        let refusal = SourceOperationPrepayment::prepare(&target(), limits(), &lifetime, loans)
            .err()
            .expect("ordinary small work input cannot fund a full controller envelope");
        assert!(
            matches!(
                refusal.test_cause(),
                BrowserInputFault::Receiving(InstalledObservationFault::Resource {
                    kind: InstalledObservationResource::ByteVisits,
                    limit: 8_388_608,
                    ..
                })
            ),
            "the ordinary full-controller refusal must be its explicit work limit: {refusal:?}"
        );
        let sticky = loans
            .business_test_ready()
            .expect_err("the actual cumulative work refusal must remain sticky");
        assert!(
            matches!(
                sticky.test_cause(),
                BrowserInputFault::Receiving(InstalledObservationFault::Resource {
                    kind: InstalledObservationResource::ByteVisits,
                    limit: 8_388_608,
                    ..
                })
            ),
            "the sticky refusal must retain the actual work-limit cause: {sticky:?}"
        );
        assert_eq!(lifetime.end(), original_end);
        eprintln!("ordinary full-controller work refusal: {refusal:?}");
    });
    with_full_controller_setup(|lifetime, loans| {
        let before = loans.business_usage().unwrap();
        let prepared = SourceOperationPrepayment::prepare(&target(), limits(), &lifetime, loans)
            .unwrap_or_else(|cause| panic!("full-controller prepayment refused: {cause:?}"));
        eprintln!(
            "full-controller prepayment usage: before={before:?},after={:?}",
            loans.business_usage().unwrap()
        );
        prepared.validate(&lifetime, limits(), loans).unwrap();
        let other = Limits {
            max_frame: 129,
            ..limits()
        };
        assert!(prepared.validate(&lifetime, other, loans).is_err());
        prepared.validate(&lifetime, limits(), loans).unwrap();
    });
}

#[test]
fn source_operation_prepay_02_foreign_child_refuses_before_resource_or_layout_work() {
    with_foreign_source_controller_lifetime(|lifetime, loans| {
        // If layout/resource arithmetic precedes association, this impossible
        // capture bound would hide the actual foreign-child refusal.
        let impossible = Limits {
            max_frame: usize::MAX,
            ..limits()
        };
        let error = SourceOperationPrepayment::prepare(&target(), impossible, &lifetime, loans)
            .err()
            .unwrap();
        assert_eq!(
            error.source_cause(),
            Some(super::super::super::BrowserSourceFault::ForeignSource)
        );
        loans.reserve_controlled_host_storage(0, 0, 0).unwrap();
    });
}

#[test]
fn source_operation_prepay_03_small_capture_refuses_actual_acquisition_before_filesystem_effects() {
    use super::super::acquisition::{ControllerAcquisitionFault, FundedControllerAcquisition};
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let unopened = base.join("must-not-open");
    with_source_controller_lifetime(|lifetime, loans| {
        let file = ControllerFileInput {
            path: &unopened,
            byte_length: 0,
        };
        let input = ControllerTargetInput {
            chromium: file,
            node: file,
            core_bundle: file,
            entry: file,
            root: &base,
        };
        let undersized = Limits {
            max_frame: super::super::SOURCE_STDOUT_BOUND - 1,
            ..limits()
        };
        let failure = FundedControllerAcquisition::prepare(input, undersized, lifetime, loans)
            .err()
            .expect("an impossible source conversation is refused before acquisition");
        assert!(matches!(
            failure.fault(),
            ControllerAcquisitionFault::Input(_)
        ));
        assert_eq!(failure.held_files(), 0);
        assert_eq!(failure.read_bytes(), 0);
        assert_eq!(failure.observed_eofs(), 0);
        assert_eq!(std::fs::read_dir(&base).unwrap().count(), 0);
    });
}
