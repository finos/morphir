//! Private engine/module controls. No host, fake token or successful DATA.
//! Suggested child of pipeline::installed::adapter, after actual facade exists.
use super::*;
use crate::workbench::{RunConfiguration, run_configured_with_installed_client_adapter};

const CASES: &[u8] = include_bytes!("fixtures/cases24.json");
const CHECKER: &str = include_str!("fixtures/checker-policy.json");

// Private UNIT fixture of a pre-existing owner. No source/auth/task claim.
// The engine must share this actual Arc allocation, never create another Arc.
struct TestGateOwner {
    gate: InvocationGate,
}
impl InvocationGateSource for TestGateOwner {
    fn invocation_gate(&self) -> &InvocationGate {
        &self.gate
    }
    fn wake_observers(&self) { /* no tasks or host exist in these unit controls */
    }
}

#[derive(Clone, Copy)]
enum Finish {
    Return,
    ForgetRun,
    ForgetToken,
    Unwind,
}
struct Probe {
    owner: std::sync::Arc<TestGateOwner>,
    finish: Finish,
    token: Option<InvocationObservation>,
    view: Option<InvocationObservationView>,
    entered: bool,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        assert_eq!(
            run.source().case_id(),
            "single-file-explicit-companion-preserves-opaque-bytes"
        );
        assert_eq!(run.source().original_packet(), "inventory35");
        assert_eq!(run.source().run_index(), 0);
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        drop(projection);
        // Private weak diagnostic, never a runtime grant or public issuer.
        let view = token.test_view();
        assert_eq!(view.state(), InvocationObservationState::Open);
        self.view = Some(view);
        match self.finish {
            Finish::Return => self.token = Some(token),
            Finish::ForgetRun => {
                self.token = Some(token);
                let _forgotten_run = std::mem::ManuallyDrop::new(run);
            }
            Finish::ForgetToken => std::mem::forget(token),
            Finish::Unwind => {
                self.token = Some(token);
                panic!("authored adapter unwind");
            }
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn configuration() -> RunConfiguration {
    RunConfiguration::from_json(&serde_json::json!({
        "kind":"model-originals-installed-client",
        "checker":serde_json::from_str::<serde_json::Value>(CHECKER).unwrap(),
        "observation":{"source":{"attempts":8192,"readCalls":8192,"returnedBytes":67108864,"files":16},"workers":{"attempts":64,"updates":8192},"host":{"updates":8192}},
        "privateRecord":{"retainedBytes":67108864},
        "installedObservation":{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":1048576,"stderrPrefixBytes":1048576,"snapshotReadBytes":16777216,"byteVisits":67108864,"records":8192}
    }).to_string()).unwrap()
}
fn exercise(finish: Finish) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = Probe {
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
        finish,
        token: None,
        view: None,
        entered: false,
    };
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
    }));
    assert!(
        probe.entered,
        "only actual complete24 preparation may issue invocation"
    );
    match finish {
        Finish::Unwind => assert!(result.is_err()),
        _ => assert!(!result.unwrap().unwrap().qualified()),
    }
    assert_eq!(
        probe.view.as_ref().unwrap().state(),
        InvocationObservationState::Revoked
    );
    if let Some(token) = &probe.token {
        assert!(matches!(
            token.check_active(),
            Err(InvocationObservationError::Revoked)
        ));
    }
    // No host/task existed, so no joined/cleanup claim follows from this view.
}
#[test]
fn callback_return_revokes_retained_token() {
    exercise(Finish::Return);
}
#[test]
fn engine_guard_revokes_even_when_public_run_is_forgotten() {
    exercise(Finish::ForgetRun);
}
#[test]
fn engine_guard_revokes_even_when_token_is_forgotten() {
    exercise(Finish::ForgetToken);
}
#[test]
fn engine_guard_revokes_on_real_adapter_unwind() {
    exercise(Finish::Unwind);
}

mod foreign_gate_tests;

mod text_retention_tests;
