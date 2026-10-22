//! Literal filesystem ownership controls. No browser or product action runs.
use super::super::adapter::execution_loans::with_source_controller_lifetime;
use super::super::adapter::execution_loans::{
    with_foreign_source_controller_lifetime, with_full_controller_setup,
    with_revoked_full_controller_setup,
};
use super::acquisition::{
    ControllerAcquisitionFault, ControllerFileInput, ControllerTargetInput,
    FundedControllerAcquisition,
};
use super::*;
use std::os::unix::fs::symlink;

fn input<'a>(file: &'a Path, root: &'a Path, length: u64) -> ControllerTargetInput<'a> {
    let file = ControllerFileInput {
        path: file,
        byte_length: length,
    };
    ControllerTargetInput {
        chromium: file,
        node: file,
        core_bundle: file,
        entry: file,
        root,
    }
}
fn limits() -> Limits {
    Limits {
        max_frame: 128,
        stderr_capture: 64,
        ..Limits::DEFAULT
    }
}
fn actual_file(root: &Path) -> PathBuf {
    let path = root.join("actual");
    fs::write(&path, b"x").unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
    path
}
#[test]
fn source_acquisition_01_declared_length_refuses_before_hash_read_and_retains_held_file() {
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let file = actual_file(&base);
    with_full_controller_setup(|lifetime, loans| {
        let prepared =
            FundedControllerAcquisition::prepare(input(&file, &base, 2), limits(), lifetime, loans)
                .unwrap_or_else(|failure| {
                    panic!(
                        "controller acquisition preparation refused: {:?}",
                        failure.fault()
                    )
                });
        eprintln!(
            "full-controller acquisition usage: {:?}",
            loans.business_usage().unwrap()
        );
        let failure = prepared
            .acquire()
            .err()
            .expect("actual held length differs");
        assert!(matches!(
            failure.fault(),
            ControllerAcquisitionFault::Length {
                declared: 2,
                actual: 1
            }
        ));
        assert_eq!(failure.read_bytes(), 0);
        assert_eq!(failure.observed_eofs(), 0);
        assert!(failure.held_files() > 0);
        assert!(!root.path().join("profile").exists());
    });
}
#[test]
fn source_acquisition_02_symlink_parent_and_raw_dot_paths_never_read_target() {
    enum Boundary {
        SymlinkParent,
        RawDot,
    }
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let outside_base = outside.path().canonicalize().unwrap();
    let file = actual_file(&outside_base);
    symlink(&outside_base, base.join("alias")).unwrap();
    for (boundary, path) in [
        (Boundary::SymlinkParent, base.join("alias/actual")),
        (Boundary::RawDot, file.parent().unwrap().join("./actual")),
    ] {
        with_full_controller_setup(|lifetime, loans| {
            let failure = match FundedControllerAcquisition::prepare(
                input(&path, &base, 1),
                limits(),
                lifetime,
                loans,
            ) {
                Ok(prepared) => prepared.acquire().err().expect("no-follow acquisition"),
                Err(failure) => failure,
            };
            assert_eq!(failure.read_bytes(), 0);
            assert!(!root.path().join("profile").exists());
            match boundary {
                Boundary::SymlinkParent => {
                    assert!(
                        matches!(failure.fault(), ControllerAcquisitionFault::Io(_)),
                        "the held no-follow walk must refuse the symlink: {:?}",
                        failure.fault()
                    );
                    assert!(failure.held_files() > 0);
                }
                Boundary::RawDot => assert!(
                    matches!(failure.fault(), ControllerAcquisitionFault::Shape),
                    "raw dot components must be refused before opening: {:?}",
                    failure.fault()
                ),
            }
        });
    }
}
#[test]
fn source_acquisition_03_partial_create_cleanup_refuses_foreign_replacement_and_keeps_caller_root()
{
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let file = actual_file(&base);
    with_full_controller_setup(|lifetime, loans| {
        let prepared =
            FundedControllerAcquisition::prepare(input(&file, &base, 1), limits(), lifetime, loans)
                .unwrap_or_else(|failure| {
                    panic!(
                        "controller acquisition preparation refused: {:?}",
                        failure.fault()
                    )
                });
        let mut failure = prepared
            .acquire()
            .err()
            .expect("literal node is not selected clock binary");
        assert!(matches!(failure.fault(), ControllerAcquisitionFault::Clock));
        assert_eq!(failure.read_bytes(), 1);
        assert_eq!(failure.observed_eofs(), 1);
        assert!(root.path().join("profile").is_dir());
        fs::rename(
            root.path().join("profile"),
            root.path().join("retained-profile"),
        )
        .unwrap();
        fs::create_dir(root.path().join("profile")).unwrap();
        assert!(!failure.cleanup_owned_entries().is_complete());
        let refused = failure.cleanup_record(0).unwrap();
        assert_eq!(
            refused.identity,
            super::acquisition::CleanupIdentity::Replacement
        );
        assert_eq!(
            refused.unlink,
            super::acquisition::CleanupUnlink::NotAttempted
        );
        let sibling = failure.cleanup_record(1).unwrap();
        assert_eq!(
            sibling.identity,
            super::acquisition::CleanupIdentity::Matched
        );
        assert_eq!(sibling.unlink, super::acquisition::CleanupUnlink::Returned);
        assert!(
            root.path().join("profile").is_dir(),
            "foreign replacement survives"
        );
        assert!(root.path().is_dir(), "caller root is borrowed");
        assert!(
            !root.path().join("artifacts").exists(),
            "independent owned sibling can retire"
        );
    });
}
#[test]
fn source_acquisition_04_capture_funding_refuses_before_any_filesystem_effect() {
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let missing = base.join("missing");
    with_source_controller_lifetime(|lifetime, loans| {
        let too_large = Limits {
            max_frame: 32 * 1024 * 1024,
            ..limits()
        };
        let failure = FundedControllerAcquisition::prepare(
            input(&missing, &base, 1),
            too_large,
            lifetime,
            loans,
        )
        .err()
        .expect("same cumulative owner refuses requested capture");
        assert!(matches!(
            failure.fault(),
            ControllerAcquisitionFault::Input(_)
        ));
        assert_eq!(failure.held_files(), 0);
        assert_eq!(failure.read_bytes(), 0);
        assert!(!root.path().join("profile").exists());
    });
}

#[test]
fn source_acquisition_05_nonempty_private_tree_and_symlinks_cleanup_without_outside_traversal() {
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let file = actual_file(&base);
    fs::write(outside.path().join("must-remain"), b"outside").unwrap();
    with_full_controller_setup(|lifetime, loans| {
        let prepared =
            FundedControllerAcquisition::prepare(input(&file, &base, 1), limits(), lifetime, loans)
                .unwrap_or_else(|failure| {
                    panic!(
                        "controller acquisition preparation refused: {:?}",
                        failure.fault()
                    )
                });
        let mut failure = prepared.acquire().err().expect("literal node pin refusal");
        let nested = base.join("profile/Default/cache");
        fs::create_dir_all(&nested).unwrap();
        fs::write(nested.join("actual-cache"), b"literal profile bytes").unwrap();
        symlink(outside.path(), base.join("profile/outside-link")).unwrap();
        assert!(
            failure.cleanup_owned_entries().is_complete(),
            "bounded owned descendants retire before their roots"
        );
        let plan = failure
            .descendant_cleanup()
            .expect("same funded cleanup owner");
        assert_eq!(plan.first_fault(), None);
        assert_eq!(plan.record_count(), 4);
        let link = (0..plan.record_count())
            .filter_map(|index| plan.record(index))
            .find(|entry| entry.name == b"outside-link")
            .unwrap();
        assert_eq!(link.kind, super::acquisition::CleanupEntryKind::Symlink);
        assert_eq!(
            link.opened,
            super::acquisition::CleanupDirectoryOpen::NotAttempted
        );
        assert_eq!(
            link.discovered,
            super::acquisition::CleanupIdentity::Matched
        );
        assert_eq!(link.identity, super::acquisition::CleanupIdentity::Matched);
        assert_eq!(link.unlink, super::acquisition::CleanupUnlink::Returned);
        assert!(!base.join("profile").exists());
        assert!(!base.join("artifacts").exists());
        assert_eq!(
            fs::read(outside.path().join("must-remain")).unwrap(),
            b"outside"
        );
        assert!(
            matches!(failure.fault(), ControllerAcquisitionFault::Clock),
            "cleanup never rewrites original failure"
        );
    });
}
#[test]
fn source_acquisition_06_foreign_child_refuses_before_paths_funding_or_effects() {
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let missing = base.join("missing");
    with_foreign_source_controller_lifetime(|lifetime, loans| {
        let failure = FundedControllerAcquisition::prepare(
            input(&missing, &base, 1),
            limits(),
            lifetime,
            loans,
        )
        .err()
        .expect("foreign relation");
        assert!(matches!(
            failure.fault(),
            ControllerAcquisitionFault::Input(_)
        ));
        assert_eq!(failure.held_files(), 0);
        assert_eq!(failure.read_bytes(), 0);
        assert!(!base.join("profile").exists());
    });
}
#[test]
fn source_acquisition_07_revocation_after_funding_refuses_before_actual_open() {
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let file = actual_file(&base);
    with_revoked_full_controller_setup(
        |lifetime, loans| {
            FundedControllerAcquisition::prepare(input(&file, &base, 1), limits(), lifetime, loans)
                .unwrap_or_else(|failure| {
                    panic!(
                        "controller acquisition preparation refused: {:?}",
                        failure.fault()
                    )
                })
        },
        |prepared| {
            let failure = prepared.acquire().err().expect("actual SAME child revoked");
            assert!(matches!(
                failure.fault(),
                ControllerAcquisitionFault::Input(error) if matches!(error.source_cause(),Some(super::super::adapter::BrowserSourceFault::Revoked))
            ));
            assert_eq!(failure.held_files(), 0);
            assert_eq!(failure.read_bytes(), 0);
            assert!(!base.join("profile").exists());
        },
    );
}
#[test]
fn source_acquisition_08_actual_partial_cleanup_remains_available_after_revocation() {
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let file = actual_file(&base);
    with_revoked_full_controller_setup(
        |lifetime, loans| {
            FundedControllerAcquisition::prepare(input(&file, &base, 1), limits(), lifetime, loans)
                .unwrap_or_else(|failure| {
                    panic!(
                        "controller acquisition preparation refused: {:?}",
                        failure.fault()
                    )
                })
                .acquire()
                .err()
                .expect("actual literal pin refusal")
        },
        |failure| {
            let cleaned = failure
                .finish_cleanup()
                .unwrap_or_else(|_| panic!("owned cleanup after revoke"));
            assert!(matches!(cleaned.fault(), ControllerAcquisitionFault::Clock));
            assert!(
                matches!(cleaned.release(),super::acquisition::SourceFileRelease::HandlesReleasedUnverified {handles} if handles>=7)
            );
            let (mut lifetime, evidence) = cleaned.into_parts();
            assert!(lifetime.while_active(|| ()).is_err());
            lifetime.retire_after_join_in_place().unwrap();
            assert!(matches!(
                evidence.fault(),
                ControllerAcquisitionFault::Clock
            ));
            assert!(!base.join("profile").exists());
            assert!(!base.join("artifacts").exists());
            assert!(base.is_dir(), "caller root survives");
        },
    );
}
#[test]
fn source_acquisition_09_cleanup_capacity_retains_actual_debt_without_fresh_work_or_quota() {
    let root = tempfile::tempdir().unwrap();
    let base = root.path().canonicalize().unwrap();
    let file = actual_file(&base);
    with_full_controller_setup(|lifetime, loans| {
        let mut failure =
            FundedControllerAcquisition::prepare(input(&file, &base, 1), limits(), lifetime, loans)
                .unwrap_or_else(|failure| {
                    panic!(
                        "controller acquisition preparation refused: {:?}",
                        failure.fault()
                    )
                })
                .acquire()
                .err()
                .expect("actual literal pin refusal");
        let capacity = failure.descendant_cleanup().unwrap().capacity();
        eprintln!(
            "full-controller cleanup fixture: capacity={capacity},usage={:?}",
            loans.business_usage().unwrap()
        );
        for index in 0..=capacity {
            fs::write(base.join("profile").join(format!("actual-{index}")), []).unwrap();
        }
        assert!(!failure.cleanup_owned_entries().is_complete());
        let plan = failure.descendant_cleanup().unwrap();
        assert!(matches!(
            plan.first_fault(),
            Some(super::acquisition::CleanupFault::Capacity)
        ));
        assert_eq!(plan.record_count(), capacity);
        assert!(base.join("profile").is_dir());
        assert!(
            !failure.cleanup_owned_entries().is_complete(),
            "no retry beyond prepaid attempt"
        );
        assert_eq!(
            failure.descendant_cleanup().unwrap().record_count(),
            capacity
        );
    });
}
