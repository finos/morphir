//! OFFGRAPH real authenticated host port controls, not installed process proof.
//! Proposed child of model_originals::capture. No events/Readers/fake token.
use super::*;
use crate::commands::{
    out_context::OutOverrides,
    ui::{
        installed_observation::{
            HostEventKind, HostEventRefusal, InstalledHostObservation, PendingHostEvent,
            RetainedHostEvent,
        },
        model_originals::{
            CaptureWorkerTestHook, HostCaptureCleanupOwner, ModelCaptureUsage,
            observation::{
                HostObservationLimits, HostSourceObservationScope, WorkerObservationLimits,
            },
        },
        native_startup::{PreparedNativeUi, prepare_native_ui_observed},
        protocol::project_key,
        provider::WorkspaceCapability as _,
        server::BoundUiHost,
    },
};
use futures_util::{FutureExt as _, SinkExt as _, StreamExt as _};
use morphir_common::config::observation::{FileReadWitness, ReadLimits};
use morphir_devkit::ConfigLoadOptions;
use morphir_mck::workbench::{
    RunConfiguration,
    model_originals::{
        installed::{
            InstalledAdapterError, InstalledClientAdapter, InstalledClientMeasurements,
            InstalledClientRun, InstalledFixtureNode,
        },
        native::data,
    },
    run_configured_with_installed_client_adapter,
};
use serde_json::{Value, json};
use std::{future::Future, path::PathBuf, sync::Mutex, time::Duration};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};

const CASES: &[u8] = include_bytes!("fixtures/cases24.json");
const CHECKER: &str = include_str!("fixtures/checker-policy.json");
const WAIT: Duration = Duration::from_secs(5);
mod pending_upgrade_tests;
type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

#[derive(Clone, Copy)]
enum Scenario {
    LiteralAuth,
    Queued,
    Ready,
    RefuseReady,
    AbandonReady,
    RefuseFrame,
    Abandoned,
    Foreign,
    RevokedHost,
}
struct Adapter {
    scenario: Scenario,
    entered: bool,
    escaped: Option<LiveHost>,
}
impl InstalledClientAdapter for Adapter {
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
        self.escaped =
            tokio::runtime::Handle::current().block_on(component(self.scenario, &mut run));
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn config(scenario: Scenario) -> RunConfiguration {
    let mut checker: Value = serde_json::from_str(CHECKER).unwrap();
    if matches!(scenario, Scenario::RefuseFrame) {
        checker["capture"]["requestBytes"] = 1u64.into();
    }
    RunConfiguration::from_json(&json!({"kind":"model-originals-installed-client","checker":checker,
        "observation":{"source":{"attempts":8192,"readCalls":8192,"returnedBytes":67108864,"files":16},"workers":{"attempts":64,"updates":8192},"host":{"updates":8192}},
        "privateRecord":{"retainedBytes":if matches!(scenario,Scenario::RefuseReady){0}else{67108864}},
        "installedObservation":{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":1048576,"stderrPrefixBytes":1048576,"snapshotReadBytes":16777216,"byteVisits":67108864,"records":8192}
    }).to_string()).unwrap()
}
async fn exercise(scenario: Scenario) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut adapter = Adapter {
        scenario,
        entered: false,
        escaped: None,
    };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(kit.path(), &config(scenario), &mut adapter)
    })
    .unwrap();
    assert!(adapter.entered);
    assert!(!report.qualified());
    assert!(
        !report.to_json().contains("client-process-measured"),
        "host components fabricate no successful measurement"
    );
    if let Some(mut host) = adapter.escaped.take() {
        // The actual canonical callback has ended. Old cookie/Host/Origin all
        // remain correct, but SAME engine-owned state is now revoked.
        assert!(
            host.connect(None).await.is_err(),
            "no new authenticated connection after callback seal"
        );
        assert!(
            host.events.next().now_or_never().flatten().is_none(),
            "revoked auth must issue no observed connection"
        );
        host.stop().await;
    }
}

struct Fixture {
    _temporary: tempfile::TempDir,
    root: PathBuf,
}
impl Fixture {
    fn from_run(run: &mut InstalledClientRun<'_>) -> Self {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().canonicalize().unwrap();
        // These paths and recipes are borrowed from SAME compiled plan. No
        // copied expected object or adapter-authored primary/record is used.
        for node in run.fixture().nodes() {
            let (path, bytes) = match node {
                InstalledFixtureNode::Literal { path, bytes }
                | InstalledFixtureNode::ByteSource { path, bytes, .. } => (path, bytes),
            };
            let target = root.join(path.as_str());
            std::fs::create_dir_all(target.parent().unwrap()).unwrap();
            let recipe = run.materialize_fixture_bytes(bytes).unwrap();
            let mut file = std::fs::File::create(target).unwrap();
            let mut offset = 0;
            let mut window = [0u8; 65_536];
            while offset < recipe.byte_length() {
                let count = window.len().min(recipe.byte_length() - offset);
                recipe.fill_window(offset, &mut window[..count]).unwrap();
                file.write_all(&window[..count]).unwrap();
                offset += count;
            }
        }
        std::fs::create_dir(root.join("test-home")).unwrap();
        Self {
            _temporary: temporary,
            root,
        }
    }
    fn held(&self) -> Dir {
        Dir::open_ambient_dir(&self.root, cap_std::ambient_authority()).unwrap()
    }
}
struct LiveHost {
    _fixture: Fixture,
    scope: HostSourceObservationScope,
    _startup: PreparedNativeUi,
    record: FileReadWitness,
    sentinel: FileReadWitness,
    base: String,
    cookie: String,
    source: Value,
    project: String,
    events: InstalledHostObservation,
    cleanup: Option<HostCaptureCleanupOwner>,
    socket_cleanup: crate::commands::ui::socket_tasks::SocketCleanup,
    usage: super::super::ModelCaptureUsageObserver,
    listener: Option<tokio::task::JoinHandle<Result<(), crate::error::CliError>>>,
}
impl LiveHost {
    async fn new(run: &mut InstalledClientRun<'_>, gate: Option<CaptureWorkerTestHook>) -> Self {
        Self::bind(
            run,
            match gate {
                Some(hook) => TestHostHook::Capture(hook),
                None => TestHostHook::None,
            },
        )
        .await
    }
    async fn new_with_socket_entry_hook(
        run: &mut InstalledClientRun<'_>,
        hook: crate::commands::ui::installed_observation::InstalledSocketEntryTestHook,
    ) -> Self {
        Self::bind(run, TestHostHook::SocketEntry(hook)).await
    }
    async fn bind(run: &mut InstalledClientRun<'_>, hook: TestHostHook) -> Self {
        let fixture = Fixture::from_run(run);
        let scope = HostSourceObservationScope::bind_native_ui(
            &fixture.held(),
            &fixture.root,
            ReadLimits::new(8192, 8192, 67108864, 16).unwrap(),
            WorkerObservationLimits::new(64, 8192).unwrap(),
            HostObservationLimits::new(8192).unwrap(),
        )
        .unwrap();
        let record = scope
            .source_scope()
            .register_file(
                &fixture.held(),
                Path::new(".morphir/out/packages/orders/compile.json"),
            )
            .unwrap();
        let sentinel = scope
            .source_scope()
            .register_file(
                &fixture.held(),
                Path::new(".morphir/out/packages/orders/compile.dest/unrelated.log"),
            )
            .unwrap();
        // SAME existing source owner's inline dormant gate. Registration is
        // after real Invocation+Mailbox credits and before discovery/auth.
        let token = run
            .issue_host_observation(scope.invocation_projection())
            .unwrap();
        let startup = prepare_native_ui_observed(
            fixture.held(),
            &fixture.root,
            "same-session-spelling",
            crate::home::MorphirHome::resolve_from(
                Some(fixture.root.join("test-home").as_os_str()),
                None,
            )
            .unwrap(),
            ConfigLoadOptions::default(),
            OutOverrides::default(),
            &scope,
        )
        .unwrap();
        let source = startup
            .workspace_provider()
            .initial_sources()
            .pop()
            .unwrap();
        let project = project_key(&source, "packages/orders");
        let source = serde_json::to_value(source).unwrap();
        let (mut host, events) = match hook {
            TestHostHook::None => {
                BoundUiHost::bind_installed_observed(
                    "same-session-spelling".into(),
                    startup.capabilities(),
                    Some(startup.originals_provider()),
                    &scope,
                    token,
                )
                .await
            }
            TestHostHook::Capture(gate) => {
                BoundUiHost::bind_installed_observed_with_capture_hook(
                    "same-session-spelling".into(),
                    startup.capabilities(),
                    Some(startup.originals_provider()),
                    &scope,
                    token,
                    gate,
                )
                .await
            }
            TestHostHook::SocketEntry(hook) => {
                BoundUiHost::bind_installed_observed_with_socket_entry_hook(
                    "same-session-spelling".into(),
                    startup.capabilities(),
                    Some(startup.originals_provider()),
                    &scope,
                    token,
                    hook,
                )
                .await
            }
        }
        .unwrap();
        let base = host.base_url();
        let launch = host.launch_url();
        let usage = host.model_originals_observer();
        let cleanup = host.take_capture_cleanup().unwrap();
        let socket_cleanup = crate::commands::ui::socket_tasks::SocketCleanup::Pending(
            host.take_socket_cleanup().unwrap(),
        );
        let listener = tokio::spawn(host.serve());
        let response = tokio::time::timeout(
            WAIT,
            reqwest::Client::builder()
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .unwrap()
                .get(launch)
                .send(),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(response.status(), reqwest::StatusCode::SEE_OTHER);
        let cookie = response.headers()["set-cookie"]
            .to_str()
            .unwrap()
            .split(';')
            .next()
            .unwrap()
            .to_owned();
        Self {
            _fixture: fixture,
            scope,
            _startup: startup,
            record,
            sentinel,
            base,
            cookie,
            source,
            project,
            events,
            cleanup: Some(cleanup),
            socket_cleanup,
            usage,
            listener: Some(listener),
        }
    }
    async fn connect(
        &self,
        change: Option<(&str, &str)>,
    ) -> Result<Socket, tokio_tungstenite::tungstenite::Error> {
        let mut request = format!("{}/rpc", self.base.replace("http://", "ws://"))
            .into_client_request()
            .unwrap();
        request
            .headers_mut()
            .insert("origin", self.base.parse().unwrap());
        request
            .headers_mut()
            .insert("cookie", self.cookie.parse().unwrap());
        if let Some((key, value)) = change {
            request.headers_mut().insert(
                key.parse::<tokio_tungstenite::tungstenite::http::HeaderName>()
                    .unwrap(),
                value.parse().unwrap(),
            );
        }
        tokio::time::timeout(WAIT, connect_async(request))
            .await
            .unwrap()
            .map(|(socket, _)| socket)
    }
    async fn stop(&mut self) {
        self.socket_cleanup.stop_accepting_upgrades();
        self.events.close();
        let listener = self.listener.take().unwrap();
        listener.abort();
        assert!(listener.await.unwrap_err().is_cancelled());
        assert_eq!(
            self.socket_cleanup
                .drain(tokio::time::Instant::now() + WAIT)
                .await,
            crate::commands::ui::socket_tasks::SocketDrainOutcome::Joined,
        );
        self.cleanup
            .take()
            .unwrap()
            .drain(tokio::time::Instant::now() + WAIT)
            .await
            .unwrap_or_else(|_| panic!("actual capture cleanup must drain before deadline"));
        tokio::time::timeout(WAIT, async {
            while self.usage.usage() != ModelCaptureUsage::default() {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        assert_eq!(self.usage.usage(), ModelCaptureUsage::default());
        assert!(
            self.scope.snapshot().require_source_complete().is_err(),
            "retained startup writers and unjoined HTTP drivers may never claim Complete"
        );
    }
}
enum TestHostHook {
    None,
    Capture(CaptureWorkerTestHook),
    SocketEntry(crate::commands::ui::installed_observation::InstalledSocketEntryTestHook),
}
impl Drop for LiveHost {
    fn drop(&mut self) {
        if let Some(task) = &self.listener {
            task.abort();
        }
    }
}

// Drives SAME receiver with SAME mutable run. No run owner crosses a spawned
// task, no held payload borrow crosses await, and no acknowledgement boolean.
async fn drive<F: Future>(
    events: &mut InstalledHostObservation,
    run: &mut InstalledClientRun<'_>,
    operation: F,
    count: usize,
) -> (F::Output, Vec<RetainedHostEvent>) {
    tokio::time::timeout(WAIT, async {
        tokio::pin!(operation); let mut result=None; let mut facts=Vec::new();
        while result.is_none()||facts.len()<count {
            tokio::select! {
                output=&mut operation, if result.is_none()=>result=Some(output),
                event=events.next()=>{
                    let event=event.expect("actual event port");
                    let fact=if event.kind()==HostEventKind::ReadyOpportunity {event.adopt_ready(run).unwrap()}else{event.retain(run).unwrap()};
                    facts.push(fact);
                }
            }
        }
        (result.unwrap(),facts)
    }).await.unwrap()
}
async fn connect(
    host: &mut LiveHost,
    run: &mut InstalledClientRun<'_>,
) -> (Socket, RetainedHostEvent) {
    // Borrow URL/cookie independently, not the mutable host receiver.
    let base = host.base.clone();
    let cookie = host.cookie.clone();
    let operation = async move {
        let mut request = format!("{}/rpc", base.replace("http://", "ws://"))
            .into_client_request()
            .unwrap();
        request
            .headers_mut()
            .insert("origin", base.parse().unwrap());
        request
            .headers_mut()
            .insert("cookie", cookie.parse().unwrap());
        connect_async(request).await.unwrap().0
    };
    let (socket, mut facts) = drive(&mut host.events, run, operation, 1).await;
    assert_eq!(facts[0].kind(), HostEventKind::AuthenticatedConnection);
    (socket, facts.remove(0))
}
async fn response(socket: &mut Socket) -> String {
    loop {
        match socket.next().await.unwrap().unwrap() {
            Message::Text(text) => return text.to_string(),
            Message::Ping(_) | Message::Pong(_) => {}
            other => panic!("unexpected socket outcome {other:?}"),
        }
    }
}
async fn exchange(
    host: &mut LiveHost,
    socket: &mut Socket,
    run: &mut InstalledClientRun<'_>,
    raw: &str,
    ready: bool,
) -> (Value, Vec<RetainedHostEvent>) {
    let operation = async {
        socket
            .send(Message::Text(raw.to_owned().into()))
            .await
            .unwrap();
        response(socket).await
    };
    let (reply, facts) = drive(&mut host.events, run, operation, if ready { 4 } else { 3 }).await;
    let received = facts
        .iter()
        .find(|f| f.kind() == HostEventKind::ReceivedText)
        .unwrap();
    assert_eq!(received.body().unwrap().as_bytes(), raw.as_bytes());
    let prepared = facts
        .iter()
        .find(|f| f.kind() == HostEventKind::PreparedSend)
        .unwrap();
    assert_eq!(prepared.body().unwrap().as_bytes(), reply.as_bytes());
    let outcome = facts
        .iter()
        .find(|f| f.kind() == HostEventKind::SendOutcome)
        .unwrap();
    assert_eq!(outcome.prepared_event().unwrap(), prepared.key());
    assert_eq!(
        outcome.send_outcome(),
        Some(crate::commands::ui::installed_observation::SendOutcome::Completed)
    );
    (serde_json::from_str(&reply).unwrap(), facts)
}
async fn initialize(host: &mut LiveHost, socket: &mut Socket, run: &mut InstalledClientRun<'_>) {
    let (reply,_)=exchange(host,socket,run," {\"jsonrpc\":\"2.0\", \"id\":1,\"method\":\"morphir.session.initialize\",\"params\":{\"protocolVersion\":1,\"sessionId\":\"same-session-spelling\"}} ",false).await;
    assert_eq!(reply["result"]["protocolVersion"], 1);
}
async fn component(scenario: Scenario, run: &mut InstalledClientRun<'_>) -> Option<LiveHost> {
    let mut gate = Gate::new();
    let hook = if matches!(scenario, Scenario::Queued) {
        Some(gate.hook())
    } else {
        None
    };
    let mut host = LiveHost::new(run, hook).await;
    if matches!(scenario, Scenario::RevokedHost) {
        return Some(host);
    }
    if matches!(scenario, Scenario::LiteralAuth) {
        for (key, value) in [
            ("cookie", "wrong=value"),
            ("origin", "http://127.0.0.1:1"),
            ("host", "127.0.0.1:1"),
        ] {
            assert!(host.connect(Some((key, value))).await.is_err());
            assert!(
                host.events.next().now_or_never().is_none(),
                "denied upgrades issue no event/source association"
            );
        }
    }
    let (mut socket, association) = connect(&mut host, run).await;
    if matches!(
        scenario,
        Scenario::RefuseFrame | Scenario::Abandoned | Scenario::Foreign
    ) {
        socket.send(Message::Text("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.session.initialize\",\"params\":{\"protocolVersion\":1,\"sessionId\":\"same-session-spelling\"}}".into())).await.unwrap();
        let pending = tokio::time::timeout(WAIT, host.events.next())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(pending.kind(), HostEventKind::ReceivedText);
        assert!(
            host.events.next().now_or_never().is_none(),
            "one pending slot gives backpressure"
        );
        match scenario {
            Scenario::RefuseFrame => assert!(pending.retain(run).is_err()),
            Scenario::Abandoned => drop(pending),
            Scenario::Foreign => foreign(pending),
            _ => unreachable!(),
        }
        assert!(
            !matches!(
                tokio::time::timeout(WAIT, socket.next()).await.unwrap(),
                Some(Ok(Message::Text(_)))
            ),
            "unretained ingress cannot parse/send a successful reply"
        );
        drop(socket);
        host.stop().await;
        return None;
    }
    initialize(&mut host, &mut socket, run).await;
    if matches!(scenario, Scenario::LiteralAuth) {
        // Same invocation credential can own more than one actual connection.
        // Distinct socket identities, not PIDs, distinguish ID1 reuse.
        let (mut second, second_association) = connect(&mut host, run).await;
        assert_ne!(association.connection(), second_association.connection());
        initialize(&mut host, &mut second, run).await;
        second.close(None).await.unwrap();
        drop(second);
        // Duplicate-bearing malformed Text is still one exact raw observation.
        let raw = " {\"jsonrpc\":\"2.0\",\"id\":18446744073709551615,\"method\":\"morphir.model-originals.capture\",\"params\":{\"semantic\":\"none\",\"semantic\":\"none\"}} ";
        let (reply, facts) = exchange(&mut host, &mut socket, run, raw, false).await;
        assert!(reply.get("error").is_some());
        assert_eq!(
            facts
                .iter()
                .filter(|f| f.kind() == HostEventKind::ReceivedText)
                .count(),
            1
        );
    } else {
        let open=json!({"jsonrpc":"2.0","id":2,"method":"morphir.workspace.open","params":{"source":host.source}}).to_string();
        let (opened, _) = exchange(&mut host, &mut socket, run, &open, false).await;
        assert!(
            opened["result"]["snapshot"]["projects"]
                .as_array()
                .unwrap()
                .iter()
                .any(|p| p["id"] == host.project)
        );
        let capture=json!({"jsonrpc":"2.0","id":3,"method":"morphir.model-originals.capture","params":{"contractVersion":"0.1.0-draft.1","source":{"providerId":host.source["providerId"],"locator":host.source["locator"]},"projectId":host.project,"scope":"complete","semantic":"none"}}).to_string();
        socket
            .send(Message::Text(capture.clone().into()))
            .await
            .unwrap();
        let received = tokio::time::timeout(WAIT, host.events.next())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(received.kind(), HostEventKind::ReceivedText);
        received.retain(run).unwrap();
        let queued = if matches!(scenario, Scenario::Queued) {
            gate.entered().await;
            let raw = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"morphir.workspace.open\",\"params\":{\"source\":null}}";
            socket.send(Message::Text(raw.into())).await.unwrap();
            let observed = tokio::time::timeout(WAIT, host.events.next())
                .await
                .unwrap()
                .unwrap();
            assert_eq!(observed.kind(), HostEventKind::ReceivedText);
            observed
                .with_text(|actual| assert_eq!(actual, raw))
                .unwrap();
            let fact = observed.retain(run).unwrap();
            gate.release();
            Some(fact)
        } else {
            None
        };
        let ready = tokio::time::timeout(WAIT, host.events.next())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(ready.kind(), HostEventKind::ReadyOpportunity);
        let pointer = ready
            .with_ready_record(|raw| {
                assert_eq!(raw.len(), 474);
                raw.as_ptr()
            })
            .unwrap();
        assert_eq!(host.usage.usage().active_workers(), 1);
        assert!(
            socket.next().now_or_never().is_none(),
            "actual Ready gate precedes reply send"
        );
        if matches!(scenario, Scenario::RefuseReady | Scenario::AbandonReady) {
            if matches!(scenario, Scenario::RefuseReady) {
                assert!(ready.adopt_ready(run).is_err());
            } else {
                drop(ready);
            }
            assert!(
                !matches!(
                    tokio::time::timeout(WAIT, socket.next()).await.unwrap(),
                    Some(Ok(Message::Text(_)))
                ),
                "failed or abandoned actual record adoption cannot send Ready"
            );
            drop(socket);
            host.stop().await;
            return None;
        }
        let adopted = ready.adopt_ready(run).unwrap();
        let (id, record) = adopted.ready().unwrap();
        let data::Bytes::Utf8 { text } = record else {
            panic!("same zero-copy Text validator")
        };
        assert_eq!(text.as_str().as_ptr(), pointer);
        assert_eq!(host.usage.usage().active_workers(), 0);
        let count = if queued.is_some() { 4 } else { 2 };
        let (replies, facts) = drive(
            &mut host.events,
            run,
            async {
                let first = response(&mut socket).await;
                let second = if queued.is_some() {
                    Some(response(&mut socket).await)
                } else {
                    None
                };
                (first, second)
            },
            count,
        )
        .await;
        assert_eq!(
            serde_json::from_str::<Value>(&replies.0).unwrap()["result"]["status"],
            "ready"
        );
        if let Some(second) = replies.1 {
            assert_eq!(serde_json::from_str::<Value>(&second).unwrap()["id"], 4);
        }
        assert_eq!(
            facts
                .iter()
                .filter(|f| f.kind() == HostEventKind::ReceivedText)
                .count(),
            0,
            "queued.take never records a second ingress"
        );
        let release=json!({"jsonrpc":"2.0","id":5,"method":"morphir.model-originals.release","params":{"contractVersion":"0.1.0-draft.1","captureId":id.as_str()}}).to_string();
        let (reply, _) = exchange(&mut host, &mut socket, run, &release, false).await;
        assert_eq!(reply["result"]["status"], "released");
        assert_eq!(
            host.scope
                .snapshot()
                .reads()
                .counts_for(&host.record)
                .unwrap()
                .returned_bytes(),
            474
        );
        assert_eq!(
            host.scope
                .snapshot()
                .reads()
                .counts_for(&host.sentinel)
                .unwrap()
                .content_attempts(),
            0
        );
        drop(adopted);
    }
    socket.close(None).await.unwrap();
    drop(socket);
    host.stop().await;
    None
}
fn foreign(event: PendingHostEvent) {
    struct Other {
        event: Option<PendingHostEvent>,
        entered: bool,
    }
    impl InstalledClientAdapter for Other {
        fn observe(
            &mut self,
            mut run: InstalledClientRun<'_>,
        ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
            self.entered = true;
            assert!(matches!(
                self.event.take().unwrap().retain(&mut run),
                Err(HostEventRefusal::ForeignInvocation)
            ));
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut adapter = Other {
        event: Some(event),
        entered: false,
    };
    let report = run_configured_with_installed_client_adapter(
        kit.path(),
        &config(Scenario::LiteralAuth),
        &mut adapter,
    )
    .unwrap();
    assert!(adapter.entered);
    assert!(!report.qualified());
}
struct Gate {
    entered: Option<tokio::sync::oneshot::Receiver<()>>,
    release: Option<std::sync::mpsc::Sender<()>>,
    hook: CaptureWorkerTestHook,
}
impl Gate {
    fn new() -> Self {
        let (send, entered) = tokio::sync::oneshot::channel();
        let (release, receive) = std::sync::mpsc::channel();
        let send = Mutex::new(Some(send));
        let receive = Mutex::new(receive);
        Self {
            entered: Some(entered),
            release: Some(release),
            hook: CaptureWorkerTestHook::new(Arc::new(move || {
                if let Some(send) = send.lock().unwrap().take() {
                    let _ = send.send(());
                }
                receive.lock().unwrap().recv().unwrap();
            })),
        }
    }
    fn hook(&self) -> CaptureWorkerTestHook {
        self.hook.clone()
    }
    async fn entered(&mut self) {
        tokio::time::timeout(WAIT, self.entered.take().unwrap())
            .await
            .unwrap()
            .unwrap();
    }
    fn release(&mut self) {
        if let Some(release) = self.release.take() {
            let _ = release.send(());
        }
    }
}
impl Drop for Gate {
    fn drop(&mut self) {
        self.release();
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn actual_auth_raw_text_and_once_serialized_reply_share_invocation() {
    exercise(Scenario::LiteralAuth).await;
}
#[tokio::test(flavor = "multi_thread")]
async fn capture_wait_queued_text_is_observed_only_at_physical_receive() {
    exercise(Scenario::Queued).await;
}
#[tokio::test(flavor = "multi_thread")]
async fn actual_ready_retains_same_record_and_permit_until_adoption_before_reply() {
    exercise(Scenario::Ready).await;
}
#[tokio::test(flavor = "multi_thread")]
async fn actual_ready_receiving_capacity_refusal_drops_bytes_before_original_permit() {
    exercise(Scenario::RefuseReady).await;
}
#[tokio::test(flavor = "multi_thread")]
async fn abandoned_actual_ready_gate_retires_record_and_never_sends_ready() {
    exercise(Scenario::AbandonReady).await;
}
#[tokio::test(flavor = "multi_thread")]
async fn real_frame_receiving_refusal_precedes_parse_and_send() {
    exercise(Scenario::RefuseFrame).await;
}
#[tokio::test(flavor = "multi_thread")]
async fn abandoned_ack_closes_real_socket_without_successful_reply() {
    exercise(Scenario::Abandoned).await;
}
#[tokio::test(flavor = "multi_thread")]
async fn same_spelling_fresh_canonical_invocation_cannot_ack_foreign_event() {
    exercise(Scenario::Foreign).await;
}
#[tokio::test(flavor = "multi_thread")]
async fn escaped_actual_host_cookie_cannot_issue_connections_after_callback_seal() {
    exercise(Scenario::RevokedHost).await;
}

mod lock_order_tests;

mod pending_receiver_tests;

mod utf8_budget_tests;
