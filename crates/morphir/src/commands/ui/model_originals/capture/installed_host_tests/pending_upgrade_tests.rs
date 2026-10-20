//! A09 actual on_upgrade future held across real engine callback sealing.
//! Child of the source-first installed_host_tests harness. No token factory,
//! fake socket/transport, lifecycle setter, worker event or sleep.
use super::*;
use crate::commands::ui::installed_observation::InstalledSocketEntryTestHook;

struct EntryGate {
    entered: Option<tokio::sync::oneshot::Receiver<()>>,
    resume: Option<tokio::sync::oneshot::Sender<()>>,
    returned: Option<tokio::sync::oneshot::Receiver<()>>,
}
impl EntryGate {
    fn new() -> (Self, InstalledSocketEntryTestHook) {
        let (entered, observed_entry) = tokio::sync::oneshot::channel();
        let (resume, held_entry) = tokio::sync::oneshot::channel();
        let (returned, observed_return) = tokio::sync::oneshot::channel();
        let hook = InstalledSocketEntryTestHook::new(entered, held_entry, returned);
        (
            Self {
                entered: Some(observed_entry),
                resume: Some(resume),
                returned: Some(observed_return),
            },
            hook,
        )
    }
    async fn entered(&mut self) {
        tokio::time::timeout(WAIT, self.entered.take().unwrap())
            .await
            .unwrap()
            .unwrap();
    }
    fn release(&mut self) {
        if let Some(resume) = self.resume.take() {
            let _ = resume.send(());
        }
    }
    async fn returned(&mut self) {
        tokio::time::timeout(WAIT, self.returned.take().unwrap())
            .await
            .unwrap()
            .unwrap();
    }
}
impl Drop for EntryGate {
    fn drop(&mut self) {
        self.release();
    }
}

// Gate drops first on panic, so the real upgraded future cannot be stranded.
// This is still NOT a JoinHandle for that actual upgraded task.
struct HeldUpgrade {
    gate: EntryGate,
    socket: Socket,
    host: LiveHost,
}
struct PendingUpgradeAdapter {
    held: Option<HeldUpgrade>,
    entered: bool,
}
impl InstalledClientAdapter for PendingUpgradeAdapter {
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
        let held = tokio::runtime::Handle::current().block_on(async {
            let (mut gate, hook) = EntryGate::new();
            let mut host = LiveHost::new_with_socket_entry_hook(&mut run, hook).await;
            // Uses the actual launch-exchanged cookie and actual Host+Origin.
            // Client's HTTP101 is real, but cannot itself issue AuthenticatedConnection.
            let socket = host.connect(None).await.unwrap();
            gate.entered().await;
            assert!(
                host.events.next().now_or_never().is_none(),
                "HTTP101/credential success and held on_upgrade are not an observed socket owner"
            );
            HeldUpgrade { gate, socket, host }
        });
        self.held = Some(held);
        // The CANONICAL ENGINE guard outside this callback must seal now.
        // Neither public Run nor this adapter may manufacture that transition.
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn pending_actual_upgrade_rechecks_same_revoked_gate_before_socket_owner_and_rpc() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut adapter = PendingUpgradeAdapter {
        held: None,
        entered: false,
    };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(
            kit.path(),
            &config(Scenario::LiteralAuth),
            &mut adapter,
        )
    })
    .unwrap();
    assert!(adapter.entered);
    assert!(!report.qualified());
    assert!(
        !report.to_json().contains("client-process-measured"),
        "no successful measurement is fabricated by a held upgrade"
    );
    let mut held = adapter.held.take().unwrap();
    // Actual peer may queue an initializer while the real socket task is held.
    // Already-closed/refused send is also a valid effect of actual revocation.
    let sent=held.socket.send(Message::Text("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.session.initialize\",\"params\":{\"protocolVersion\":1,\"sessionId\":\"same-session-spelling\"}}".into())).await;
    held.gate.release();
    // A real normal body-return milestone removes the release/poll race.
    // It is NOT actual JoinHandle resolution or task-destructor completion.
    held.gate.returned().await;
    tokio::time::timeout(WAIT,async {
        let mut events_open=true;
        loop {
            tokio::select! {
                event=held.host.events.next(),if events_open=>{
                    assert!(event.is_none(),"revoked pending upgrade must emit neither AuthenticatedConnection nor selected RPC facts");
                    events_open=false;
                },
                frame=held.socket.next()=>match frame {
                    None|Some(Ok(Message::Close(_)))=>break,
                    Some(Err(tokio_tungstenite::tungstenite::Error::ConnectionClosed|tokio_tungstenite::tungstenite::Error::AlreadyClosed|tokio_tungstenite::tungstenite::Error::Io(_)))=>break,
                    Some(Ok(Message::Ping(bytes)))=>{let _=held.socket.send(Message::Pong(bytes)).await;},
                    Some(Ok(Message::Pong(_)))=>{},
                    other=>panic!("pending upgrade processed/replied after seal: {other:?}; send={sent:?}"),
                }
            }
        }
    }).await.unwrap();
    assert!(
        held.host.events.next().now_or_never().flatten().is_none(),
        "socket closure may not hide an unconsumed owner/RPC fact"
    );
    drop(held.socket);
    held.host.stop().await;
    // stop() joins only listener and real capture cleanup. Never claim the
    // separate Axum upgraded task joined or the whole source owner Complete.
}
