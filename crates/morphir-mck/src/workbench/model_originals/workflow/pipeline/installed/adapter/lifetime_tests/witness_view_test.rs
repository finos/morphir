//! Child of genuine installed adapter lifetime_tests. No live source or fake DATA.
use super::*;
use crate::workbench::model_originals::native::data::FileRole;

struct WitnessProbe {
    entered: bool,
}
impl InstalledClientAdapter for WitnessProbe {
    fn observe(
        &mut self,
        run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        assert_eq!(
            run.source().case_id(),
            "single-file-explicit-companion-preserves-opaque-bytes"
        );
        let fixture = run.fixture();
        let witnesses = fixture.witnesses();
        assert_eq!(witnesses.len(), 3);
        // These paths are source anchors in the unchanged materialization,
        // not new expected byte values or adapter-selected read targets.
        for ((role, path), (wanted_role, wanted_path)) in witnesses.zip([
            (
                FileRole::CompileRecord,
                ".morphir/out/packages/orders/compile.json",
            ),
            (
                FileRole::OriginalPrimary,
                ".morphir/out/packages/orders/compile.dest/morphir-ir.json",
            ),
            (
                FileRole::UndeclaredSentinel,
                ".morphir/out/packages/orders/compile.dest/unrelated.log",
            ),
        ]) {
            assert_eq!(role, wanted_role);
            assert_eq!(path.as_str(), wanted_path);
            assert!(
                fixture.nodes().any(|node| {
                    let (InstalledFixtureNode::Literal { path: actual, .. }
                    | InstalledFixtureNode::ByteSource { path: actual, .. }) = node;
                    std::ptr::eq(actual, path)
                }),
                "the witness borrows an actual compiled node path"
            );
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

#[test]
fn complete24_issuer_lends_three_validated_borrowed_witness_roles_without_source_grants() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = WitnessProbe { entered: false };
    let report =
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
            .unwrap();
    assert!(probe.entered);
    assert!(!report.qualified());
}
