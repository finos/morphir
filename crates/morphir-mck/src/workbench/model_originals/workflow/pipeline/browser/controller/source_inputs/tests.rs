//! Actual compiler-issued source lifetime, never a caller-issued runtime grant.
use super::super::super::adapter::execution_loans::{
    with_foreign_source_controller_lifetime, with_source_controller_lifetime,
};
use super::*;

#[test]
fn browser_runtime_inputs_01_wrong_length_refuses_before_archive_decode() {
    with_source_controller_lifetime(|lifetime, loans| {
        let failure = SelectedRuntimePackage::prepare(b"not an archive", &lifetime, loans)
            .err()
            .expect("selected artifact length is exact");
        assert!(matches!(
            failure,
            RuntimeAssociationFault::ArchiveLength { .. }
        ));
    });
}

#[test]
fn browser_runtime_inputs_02_foreign_child_precedes_input_inspection_and_spending() {
    with_foreign_source_controller_lifetime(|lifetime, loans| {
        let failure = SelectedRuntimePackage::prepare(b"not an archive", &lifetime, loans)
            .err()
            .expect("actual foreign child");
        assert!(matches!(failure, RuntimeAssociationFault::Input(_)));
    });
}

#[test]
fn browser_runtime_inputs_03_sticky_owner_fault_precedes_archive_shape() {
    with_source_controller_lifetime(|lifetime, loans| {
        assert!(
            loans
                .reserve_controlled_host_storage(usize::MAX, 0, 0)
                .is_err()
        );
        let failure = SelectedRuntimePackage::prepare(b"not an archive", &lifetime, loans)
            .err()
            .expect("same prior cumulative owner fault");
        assert!(matches!(failure, RuntimeAssociationFault::Input(_)));
    });
}

#[test]
fn browser_runtime_inputs_04_exact_length_unselected_archive_fails_integrity() {
    let raw = vec![0; ARCHIVE_BYTES];
    with_source_controller_lifetime(|lifetime, loans| {
        let failure = SelectedRuntimePackage::prepare(&raw, &lifetime, loans)
            .err()
            .expect("length alone never selects a package");
        assert!(matches!(failure, RuntimeAssociationFault::Integrity));
    });
}

#[test]
fn browser_runtime_inputs_05_reuses_portable_paths_without_normalizing_escape_or_links() {
    assert_eq!(
        package_relative(b"package/lib/coreBundle.js").unwrap(),
        "lib/coreBundle.js"
    );
    for path in [
        b"../outside".as_slice(),
        b"other/index.mjs",
        b"package/../outside",
        b"package/./index.mjs",
        b"package/lib//coreBundle.js",
        b"package/lib\\coreBundle.js",
        b"package//index.mjs",
        b"package/CON.js",
        b"package/lib/entry. ",
        b"package/\xff.js",
        b"package/",
        b"package/index.mjs\0",
    ] {
        assert!(
            matches!(
                package_relative(path),
                Err(RuntimeAssociationFault::UnsafePath)
            ),
            "{path:?}"
        );
    }
}

#[test]
#[ignore = "requires explicit actual locked package archive; no installed-tree/browser qualification"]
fn browser_runtime_inputs_06_actual_locked_archive_complete_inventory_and_owned_bytes() {
    use super::super::super::adapter::execution_loans::with_source_controller_limits;
    let input = std::env::var_os("MORPHIR_MCK_BROWSER_PLAYWRIGHT_ARCHIVE")
        .expect("explicit actual locked archive required");
    let mut raw = std::fs::read(input).expect("actual archive read by test harness");
    assert_eq!(raw.len(), ARCHIVE_BYTES);
    let original_first = raw[0];
    with_source_controller_limits(
        br#"{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":4096,"stderrPrefixBytes":4096,"snapshotReadBytes":1048576,"byteVisits":268435456,"records":0}"#,
        |lifetime, loans| {
            let selected = SelectedRuntimePackage::prepare(&raw, &lifetime, loans).unwrap();
            selected.validate(&lifetime, loans).unwrap();
            assert_eq!(selected.files().len(), 115);
            assert_eq!(selected.files().map(|file| file.byte_length()).sum::<u64>(), FILE_BYTES);
            let entry = selected.files().find(|file| file.path() == "index.mjs").unwrap();
            assert_eq!(entry.byte_length(), 1063);
            assert_eq!(entry.mode(), 0o644);
            let core = selected.files().find(|file| file.path() == "lib/coreBundle.js").unwrap();
            assert_eq!(core.byte_length(), 3_585_406);
            let actual = core.sha256().iter().map(|byte| format!("{byte:02x}")).collect::<String>();
            assert_eq!(actual, "829521b67ed7be90c7d6d6098ff39f2241562d47e4ad7ccab13710924a56001d");
            assert!(selected.files().any(|file| file.path() == "lib/utilsBundle.js"));
            assert!(selected.files().any(|file| file.path() == "lib/bootstrap.js"));
            assert!(selected.files().any(|file| file.path() == "package.json"));
            assert!(selected.files().any(|file| file.path() == "browsers.json"));
            raw[0] ^= 1;
            assert_eq!(selected.archive()[0], original_first, "retained artifact owns its bytes");
            // Correct length and previously authentic input never bless changed bytes.
            assert!(matches!(SelectedRuntimePackage::prepare(&raw, &lifetime, loans), Err(RuntimeAssociationFault::Integrity)));
        },
    );
}
