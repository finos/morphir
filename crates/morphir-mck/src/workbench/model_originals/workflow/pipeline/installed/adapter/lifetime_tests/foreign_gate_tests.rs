//! Same already-Open owner must survive another real configured callback's refusal.
use super::*;
struct Other {
    owner: std::sync::Arc<TestGateOwner>,
    entered: bool,
}
impl InstalledClientAdapter for Other {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let source: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        assert!(
            run.issue_host_observation(std::sync::Arc::downgrade(&source))
                .is_err()
        );
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
struct Original {
    owner: std::sync::Arc<TestGateOwner>,
    token: Option<InvocationObservation>,
}
impl InstalledClientAdapter for Original {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        let source: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let token = run
            .issue_host_observation(std::sync::Arc::downgrade(&source))
            .unwrap();
        let kit = tempfile::tempdir().unwrap();
        std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
        let mut other = Other {
            owner: self.owner.clone(),
            entered: false,
        };
        let report =
            run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut other)
                .unwrap();
        assert!(other.entered);
        assert!(!report.qualified());
        assert!(
            token.check_active().is_ok(),
            "failed foreign issuance must not revoke the original Open gate"
        );
        self.token = Some(token);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn refused_second_invocation_does_not_revoke_actual_first_gate() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut original = Original {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        token: None,
    };
    let report =
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut original)
            .unwrap();
    assert!(!report.qualified());
    assert_eq!(
        original.token.unwrap().check_active(),
        Err(InvocationObservationError::Revoked)
    );
}
