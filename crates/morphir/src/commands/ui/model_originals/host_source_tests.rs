//! Prospective genuine native-host route controls, not a second runner/checker.
//! Install as model_originals::host_source_tests. Root owns module wiring.
use super::observation::{
    HostCall, HostObservationLimits, HostSourceObservationScope, WorkerObservationLimits,
};
use super::*;
use crate::commands::ui::{
    prepare_native_ui_observed,
    protocol::project_key,
    provider::{
        SessionCapabilities, WorkspaceCapability,
        native::NativeWorkspaceProvider, originals::OriginalsProvider,
        playground::NativePlaygroundProvider,
    },
    server::BoundUiHost,
};
use cap_std::fs::Dir;
use futures_util::{SinkExt as _, StreamExt as _};
use morphir_common::config::observation::{FileReadWitness, ReadClass, ReadLimits};
use morphir_devkit::ConfigLoadOptions;
use serde_json::{Value, json};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};
type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;
const WAIT: Duration = Duration::from_secs(10);

struct SourceFixture {
    _outer: tempfile::TempDir,
    root: PathBuf,
}
impl SourceFixture {
    fn new(parent: Option<&[u8]>) -> Self {
        let outer = tempfile::tempdir().unwrap();
        let root = outer.path().join("workspace");
        std::fs::create_dir_all(root.join(".morphir/out/compile.dest")).unwrap();
        std::fs::create_dir(root.join("home")).unwrap();
        std::fs::write(
            root.join("morphir.toml"),
            include_bytes!("host_observation_fixtures/project.toml"),
        )
        .unwrap();
        std::fs::write(
            root.join(".morphir/out/compile.json"),
            include_bytes!("host_observation_fixtures/private-record.json"),
        )
        .unwrap();
        std::fs::write(
            root.join(".morphir/out/compile.dest/model.json"),
            include_bytes!("host_observation_fixtures/primary.json"),
        )
        .unwrap();
        std::fs::write(
            root.join(".morphir/out/compile.dest/secret"),
            include_bytes!("host_observation_fixtures/undeclared-sentinel.txt"),
        )
        .unwrap();
        if let Some(bytes) = parent {
            std::fs::write(outer.path().join("morphir.toml"), bytes).unwrap();
        }
        Self {
            _outer: outer,
            root,
        }
    }
    fn held(&self) -> Dir {
        Dir::open_ambient_dir(&self.root, cap_std::ambient_authority()).unwrap()
    }
    fn home(&self) -> crate::home::MorphirHome {
        crate::home::MorphirHome::resolve_from(Some(self.root.join("home").as_os_str()), None)
            .unwrap()
    }
    fn scope(&self) -> HostSourceObservationScope {
        HostSourceObservationScope::bind_native_ui(
            &self.held(),
            &self.root,
            ReadLimits::new(1_000_000, 1_000_000, 16_777_216, 32).unwrap(),
            WorkerObservationLimits::new(64, 4096).unwrap(),
            HostObservationLimits::new(4096).unwrap(),
        )
        .unwrap()
    }
}
struct Files {
    primary: FileReadWitness,
    record: FileReadWitness,
    sentinel: FileReadWitness,
    project: FileReadWitness,
}
fn register_before_discovery(scope: &HostSourceObservationScope, fixture: &SourceFixture) -> Files {
    let held = fixture.held();
    let source = scope.source_scope();
    Files {
        primary: source
            .register_file(&held, Path::new(".morphir/out/compile.dest/model.json"))
            .unwrap(),
        record: source
            .register_file(&held, Path::new(".morphir/out/compile.json"))
            .unwrap(),
        sentinel: source
            .register_file(&held, Path::new(".morphir/out/compile.dest/secret"))
            .unwrap(),
        project: source
            .register_file(&held, Path::new("morphir.toml"))
            .unwrap(),
    }
}
struct RunningHost {
    worker: Option<tokio::task::JoinHandle<Result<(), crate::error::CliError>>>,
    base: String,
    cookie: String,
    source: Value,
    project: String,
    usage: ModelCaptureUsageObserver,
}
impl Drop for RunningHost {
    fn drop(&mut self) {
        if let Some(worker) = &self.worker {
            worker.abort();
        }
    }
}
impl RunningHost {
    async fn from_host(host: BoundUiHost, source: Value, project: String) -> Self {
        let base = host.base_url();
        let launch = host.launch_url();
        let usage = host.model_originals_observer();
        let worker = tokio::spawn(host.serve());
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();
        let response = client.get(launch).send().await.unwrap();
        assert_eq!(response.status(), reqwest::StatusCode::SEE_OTHER);
        let cookie = response.headers()["set-cookie"]
            .to_str()
            .unwrap()
            .split(';')
            .next()
            .unwrap()
            .to_owned();
        Self {
            worker: Some(worker),
            base,
            cookie,
            source,
            project,
            usage,
        }
    }
    async fn connect(&self) -> Socket {
        let mut request = format!("{}/rpc", self.base.replace("http://", "ws://"))
            .into_client_request()
            .unwrap();
        request
            .headers_mut()
            .insert("origin", self.base.parse().unwrap());
        request
            .headers_mut()
            .insert("cookie", self.cookie.parse().unwrap());
        let (mut socket, _) = connect_async(request).await.unwrap();
        send(
            &mut socket,
            1,
            "morphir.session.initialize",
            json!({"protocolVersion":1,"sessionId":"observed-native-session"}),
        )
        .await;
        assert_eq!(reply(&mut socket, 1).await["result"]["protocolVersion"], 1);
        send(
            &mut socket,
            2,
            "morphir.workspace.open",
            json!({"source":self.source}),
        )
        .await;
        let opened = reply(&mut socket, 2).await;
        assert!(
            opened["result"]["snapshot"]["projects"]
                .as_array()
                .unwrap()
                .iter()
                .any(|x| x["id"] == self.project)
        );
        socket
    }
    async fn stop(mut self) {
        let worker = self.worker.take().unwrap();
        worker.abort();
        assert!(
            worker.await.unwrap_err().is_cancelled(),
            "actual listener task join, not a scope-counter inference"
        );
    }
}
async fn send(socket: &mut Socket, id: u64, method: &str, params: Value) {
    socket
        .send(Message::Text(
            json!({"jsonrpc":"2.0","id":id,"method":method,"params":params})
                .to_string()
                .into(),
        ))
        .await
        .unwrap();
}
async fn reply(socket: &mut Socket, id: u64) -> Value {
    tokio::time::timeout(WAIT, async {
        loop {
            match socket.next().await.unwrap().unwrap() {
                Message::Text(text) => {
                    let value: Value = serde_json::from_str(&text).unwrap();
                    assert_eq!(value["id"], id);
                    return value;
                }
                Message::Ping(_) | Message::Pong(_) => {}
                other => panic!("unexpected actual frame: {other:?}"),
            }
        }
    })
    .await
    .unwrap()
}
async fn recover(scope: HostSourceObservationScope) -> super::observation::HostSourceSnapshot {
    tokio::time::timeout(WAIT, async {
        let mut owner = scope;
        loop {
            match owner.try_seal() {
                Ok(snapshot) => return snapshot,
                Err(retained) => {
                    owner = retained.into_scope();
                    tokio::task::yield_now().await;
                }
            }
        }
    })
    .await
    .unwrap()
}
async fn running(fixture: &SourceFixture, scope: &HostSourceObservationScope) -> RunningHost {
    // This MUST be the function used by native run_ui startup, not a new
    // generic scenario adapter. It keeps playground's default config policy.
    let setup = prepare_native_ui_observed(
        fixture.held(),
        &fixture.root,
        "observed-native-session",
        fixture.home(),
        ConfigLoadOptions::project_only(),
        Default::default(),
        scope,
    )
    .unwrap();
    let provider = setup.workspace_provider();
    let source = provider.initial_sources().pop().unwrap();
    let project = project_key(&source, ".");
    let source = serde_json::to_value(source).unwrap();
    let host = BoundUiHost::bind_source_observed(
        "observed-native-session".into(),
        setup.capabilities(),
        Some(setup.originals_provider()),
        scope,
    )
    .await
    .unwrap();
    drop(provider);
    drop(setup);
    RunningHost::from_host(host, source, project).await
}
fn capture_params(host: &RunningHost) -> Value {
    json!({"contractVersion":"0.1.0-draft.1","source":{"providerId":host.source["providerId"],"locator":host.source["locator"]},"projectId":host.project,"scope":"complete","semantic":"none"})
}
async fn released_capture(host: &RunningHost, socket: &mut Socket) -> String {
    send(
        socket,
        3,
        "morphir.model-originals.capture",
        capture_params(host),
    )
    .await;
    let ready = reply(socket, 3).await;
    assert_eq!(ready["result"]["status"], "ready");
    assert_eq!(
        ready["result"]["coverage"],
        json!({"kind":"complete","declaration":"0.1.0-draft.1"})
    );
    assert_eq!(
        ready["result"]["sourceFormatVersion"],
        json!({"status":"reported","release":"4.0.0"})
    );
    assert_eq!(ready["result"]["inventory"]["sourceByteLength"], 111);
    assert_eq!(ready["result"]["origin"]["record"]["byteLength"], 237);
    assert_eq!(
        ready["result"]["origin"]["record"]["sha256"],
        "8002319afb380077c229776ede0d60eb8634ae49308b74420461b34a59f626d1"
    );
    assert_eq!(
        ready["result"]["projection"],
        json!({"status":"not-requested"})
    );
    let capture = ready["result"]["captureId"].as_str().unwrap().to_owned();
    send(
        socket,
        4,
        "morphir.model-originals.release",
        json!({"contractVersion":"0.1.0-draft.1","captureId":capture}),
    )
    .await;
    assert_eq!(reply(socket, 4).await["result"]["status"], "released");
    capture
}

#[tokio::test]
async fn actual_native_startup_open_capture_revalidation_and_seal_share_one_source_owner() {
    let fixture = SourceFixture::new(None);
    let scope = fixture.scope();
    let files = register_before_discovery(&scope, &fixture);
    let host = running(&fixture, &scope).await;
    let mut socket = host.connect().await;
    let _capture = released_capture(&host, &mut socket).await;
    // Product release checkpoint occurs BEFORE harness/listener teardown.
    assert_eq!(host.usage.usage(), ModelCaptureUsage::default());
    let product = scope.snapshot();
    assert!(
        product.require_source_complete().is_err(),
        "live writer leases cannot seal SDK prefix"
    );
    assert_eq!(product.calls(HostCall::InitialDiscovery), 1);
    assert_eq!(product.calls(HostCall::PlaygroundStartup), 1);
    assert_eq!(product.calls(HostCall::WorkspaceOpen), 1);
    assert_eq!(product.calls(HostCall::OriginalsResolution), 2);
    assert_eq!(product.calls(HostCall::FrozenHeaderProbe), 1);
    assert_eq!(product.calls(HostCall::LegacyModelOpen), 0);
    assert_eq!(product.calls(HostCall::Compile), 0);
    assert_eq!(
        product
            .reads()
            .counts_for(&files.primary)
            .unwrap()
            .content_attempts(),
        1
    );
    assert_eq!(
        product
            .reads()
            .counts_for(&files.primary)
            .unwrap()
            .read_calls(),
        2
    );
    assert_eq!(
        product
            .reads()
            .counts_for(&files.primary)
            .unwrap()
            .returned_bytes(),
        111
    );
    assert_eq!(
        product
            .reads()
            .counts_for(&files.record)
            .unwrap()
            .content_attempts(),
        1
    );
    assert_eq!(
        product
            .reads()
            .counts_for(&files.record)
            .unwrap()
            .read_calls(),
        2
    );
    assert_eq!(
        product
            .reads()
            .counts_for(&files.record)
            .unwrap()
            .returned_bytes(),
        237
    );
    assert_eq!(
        product
            .reads()
            .counts_for(&files.sentinel)
            .unwrap()
            .content_attempts(),
        0
    );
    assert!(
        product
            .reads()
            .counts_for(&files.project)
            .unwrap()
            .content_attempts()
            >= 1
    );
    product.workers().require_joined_cleanup().unwrap();
    socket.close(None).await.unwrap();
    drop(socket);
    host.stop().await;
    let final_snapshot = recover(scope).await;
    final_snapshot.require_source_complete().unwrap();
    final_snapshot.workers().require_joined_cleanup().unwrap();
    assert_eq!(
        final_snapshot
            .reads()
            .counts_for(&files.primary)
            .unwrap()
            .returned_bytes(),
        111
    );
    assert_eq!(
        final_snapshot
            .reads()
            .counts_for(&files.record)
            .unwrap()
            .returned_bytes(),
        237
    );
    assert_eq!(
        final_snapshot
            .reads()
            .counts_for(&files.sentinel)
            .unwrap()
            .content_attempts(),
        0
    );
    // Ambient0 for the full original is STILL a separate required leaf. This
    // component preserves actual default global/system behavior and reports it.
}

#[tokio::test]
async fn actual_playground_default_startup_ignored_parent_read_is_measured_even_if_parse_fails() {
    for bytes in [
        include_bytes!("host_observation_fixtures/ambient.toml").as_slice(),
        include_bytes!("host_observation_fixtures/invalid-ambient.toml").as_slice(),
    ] {
        let fixture = SourceFixture::new(Some(bytes));
        let scope = fixture.scope();
        let _files = register_before_discovery(&scope, &fixture);
        let outside =
            Dir::open_ambient_dir(fixture._outer.path(), cap_std::ambient_authority()).unwrap();
        let parent = scope
            .source_scope()
            .register_file(&outside, Path::new("morphir.toml"))
            .unwrap();
        let host = running(&fixture, &scope).await;
        let snapshot = scope.snapshot();
        assert_eq!(snapshot.calls(HostCall::PlaygroundStartup), 1);
        assert!(
            snapshot
                .reads()
                .counts_for(&parent)
                .unwrap()
                .content_attempts()
                >= 1
        );
        assert!(
            snapshot
                .reads()
                .counts_for(&parent)
                .unwrap()
                .returned_bytes()
                >= bytes.len() as u64
        );
        host.stop().await;
        let snapshot = recover(scope).await;
        snapshot.require_source_complete().unwrap();
        assert!(
            snapshot
                .reads()
                .counts(ReadClass::AmbientContent)
                .content_attempts()
                >= 1
        );
        assert!(
            snapshot
                .reads()
                .counts_for(&parent)
                .unwrap()
                .content_attempts()
                >= 1
        );
    }
}

#[tokio::test]
async fn some_observed_discovery_cannot_cover_a_legacy_unobserved_playground_startup() {
    let fixture = SourceFixture::new(Some(include_bytes!(
        "host_observation_fixtures/ambient.toml"
    )));
    let scope = fixture.scope();
    let _files = register_before_discovery(&scope, &fixture);
    let provider = Arc::new(
        NativeWorkspaceProvider::discover_observed(
            fixture.held(),
            &fixture.root,
            "observed-native-session",
            ConfigLoadOptions::project_only(),
            &scope,
        )
        .unwrap()
        .authorize_originals_lookup(cap_std::ambient_authority())
        .unwrap(),
    );
    let source = provider.initial_sources().pop().unwrap();
    let project = project_key(&source, ".");
    let playground = Arc::new(NativePlaygroundProvider::in_workspace(
        fixture.home(),
        &fixture.root,
    ));
    let host = BoundUiHost::bind_source_observed(
        "observed-native-session".into(),
        SessionCapabilities {
            workspace: Some(provider.clone()),
            playground: Some(playground),
            ..Default::default()
        },
        Some(OriginalsProvider::Native(provider.clone())),
        &scope,
    )
    .await
    .unwrap();
    drop(provider);
    let host = RunningHost::from_host(host, serde_json::to_value(source).unwrap(), project).await;
    let mut socket = host.connect().await;
    released_capture(&host, &mut socket).await;
    socket.close(None).await.unwrap();
    drop(socket);
    host.stop().await;
    let snapshot = recover(scope).await;
    assert!(snapshot.reads().total_counts().content_attempts() >= 1);
    assert_eq!(snapshot.calls(HostCall::PlaygroundStartup), 0);
    assert!(
        snapshot.require_source_complete().is_err(),
        "actual unobserved default startup cannot be silently covered by other complete SDK prefixes"
    );
}

#[tokio::test]
async fn required_workspace_open_and_actual_legacy_load_and_compile_entries_are_distinct() {
    let fixture = SourceFixture::new(None);
    let scope = fixture.scope();
    let _files = register_before_discovery(&scope, &fixture);
    let host = running(&fixture, &scope).await;
    let mut socket = host.connect().await;
    let before = scope.snapshot();
    assert_eq!(before.calls(HostCall::WorkspaceOpen), 1);
    assert_eq!(before.calls(HostCall::LegacyModelOpen), 0);
    assert_eq!(before.calls(HostCall::Compile), 0);
    send(
        &mut socket,
        3,
        "morphir.project-model.open",
        json!({"source":host.source,"projectId":host.project}),
    )
    .await;
    let _actual_legacy_result = reply(&mut socket, 3).await;
    let after = scope.snapshot();
    assert_eq!(after.calls(HostCall::LegacyModelOpen), 1);
    assert_eq!(
        after.calls(HostCall::WorkspaceOpen),
        2,
        "native legacy implementation genuinely calls open once more"
    );
    send(&mut socket,4,"morphir.playground.compile",json!({"languageId":"not-an-installed-language","documents":[],"package":{"name":"independent/no-frontend"},"irVersion":"v4","options":{}})).await;
    let _actual_compile_result = reply(&mut socket, 4).await;
    let after = scope.snapshot();
    assert_eq!(after.calls(HostCall::Compile), 1);
    assert_eq!(
        after.calls(HostCall::LegacyModelOpen),
        1,
        "count one actual entry, not RPC+helper twice"
    );
    socket.close(None).await.unwrap();
    drop(socket);
    host.stop().await;
    let final_snapshot = recover(scope).await;
    assert_eq!(final_snapshot.calls(HostCall::Compile), 1);
    assert_eq!(final_snapshot.calls(HostCall::LegacyModelOpen), 1);
    // Optional legacy/extension read routes need observed hooks OR explicit
    // Partial. This nonzero control cannot qualify the original forbidden0 leaf.
}

#[tokio::test]
async fn retained_actual_provider_writer_lease_prevents_final_source_seal() {
    let fixture = SourceFixture::new(None);
    let scope = fixture.scope();
    let _files = register_before_discovery(&scope, &fixture);
    let setup = prepare_native_ui_observed(
        fixture.held(),
        &fixture.root,
        "observed-native-session",
        fixture.home(),
        ConfigLoadOptions::project_only(),
        Default::default(),
        &scope,
    )
    .unwrap();
    let retained = setup.workspace_provider();
    drop(setup);
    let pending = scope.try_seal().err().unwrap();
    let scope = pending.into_scope();
    assert!(scope.snapshot().require_source_complete().is_err());
    drop(retained);
    let snapshot = recover(scope).await;
    assert!(
        snapshot.require_source_complete().is_err(),
        "no genuine bound/observed host invocation occurred"
    );
}

#[tokio::test]
async fn actual_capture_of_independently_declared_sentinel_calibrates_nonzero_content_attempts() {
    let fixture = SourceFixture::new(None);
    std::fs::write(
        fixture.root.join(".morphir/out/compile.json"),
        include_bytes!("host_observation_fixtures/declared-sentinel-record.json"),
    )
    .unwrap();
    let scope = fixture.scope();
    let files = register_before_discovery(&scope, &fixture);
    let host = running(&fixture, &scope).await;
    let mut socket = host.connect().await;
    send(
        &mut socket,
        3,
        "morphir.model-originals.capture",
        capture_params(&host),
    )
    .await;
    let ready = reply(&mut socket, 3).await;
    assert_eq!(ready["result"]["status"], "ready");
    assert_eq!(
        ready["result"]["inventory"]["sourceByteLength"],
        111 + include_bytes!("host_observation_fixtures/undeclared-sentinel.txt").len()
    );
    let capture = ready["result"]["captureId"].as_str().unwrap();
    send(
        &mut socket,
        4,
        "morphir.model-originals.release",
        json!({"contractVersion":"0.1.0-draft.1","captureId":capture}),
    )
    .await;
    assert_eq!(reply(&mut socket, 4).await["result"]["status"], "released");
    assert_eq!(host.usage.usage(), ModelCaptureUsage::default());
    socket.close(None).await.unwrap();
    drop(socket);
    host.stop().await;
    let snapshot = recover(scope).await;
    snapshot.require_source_complete().unwrap();
    snapshot.workers().require_joined_cleanup().unwrap();
    let actual = snapshot.reads().counts_for(&files.sentinel).unwrap();
    assert_eq!(actual.content_attempts(), 1);
    assert_eq!(actual.read_calls(), 2);
    assert_eq!(
        actual.returned_bytes(),
        include_bytes!("host_observation_fixtures/undeclared-sentinel.txt").len() as u64
    );
    // This independent calibration declares that file. It does not rewrite or
    // qualify the original237-byte record, where the same file is undeclared.
}

#[tokio::test]
async fn same_spelling_foreign_host_scope_cannot_bind_actual_prepared_providers() {
    let fixture = SourceFixture::new(None);
    let a = fixture.scope();
    let b = fixture.scope();
    let _a = register_before_discovery(&a, &fixture);
    let _b = register_before_discovery(&b, &fixture);
    let setup = prepare_native_ui_observed(
        fixture.held(),
        &fixture.root,
        "observed-native-session",
        fixture.home(),
        ConfigLoadOptions::project_only(),
        Default::default(),
        &a,
    )
    .unwrap();
    let wrong = BoundUiHost::bind_source_observed(
        "observed-native-session".into(),
        setup.capabilities(),
        Some(setup.originals_provider()),
        &b,
    )
    .await;
    assert!(
        wrong.is_err(),
        "actual provider binding belongs to a different observation owner despite identical labels/root"
    );
    drop(setup);
    let b = recover(b).await;
    assert_eq!(b.reads().total_counts().content_attempts(), 0);
    assert!(b.require_source_complete().is_err());
    let a = recover(a).await;
    assert!(
        a.require_source_complete().is_err(),
        "no actual host was bound for a"
    );
}

#[tokio::test]
async fn host_observer_event_limit_does_not_become_a_source_or_startup_business_quota() {
    let fixture = SourceFixture::new(None);
    let scope = HostSourceObservationScope::bind_native_ui(
        &fixture.held(),
        &fixture.root,
        ReadLimits::new(1_000_000, 1_000_000, 16_777_216, 32).unwrap(),
        WorkerObservationLimits::new(64, 4096).unwrap(),
        HostObservationLimits::new(1).unwrap(),
    )
    .unwrap();
    let _files = register_before_discovery(&scope, &fixture);
    let host = running(&fixture, &scope).await;
    let mut socket = host.connect().await;
    released_capture(&host, &mut socket).await;
    assert_eq!(host.usage.usage(), ModelCaptureUsage::default());
    socket.close(None).await.unwrap();
    drop(socket);
    host.stop().await;
    let snapshot = recover(scope).await;
    assert!(snapshot.require_source_complete().is_err());
    assert_eq!(
        snapshot.calls(HostCall::InitialDiscovery),
        1,
        "retained bounded prefix, not reset/fabricated complete counters"
    );
}

#[tokio::test]
async fn genuine_blocked_capture_disconnect_does_not_read_record_or_primary_or_prove_join() {
    let fixture = SourceFixture::new(None);
    let lock = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(fixture.root.join(".morphir/out/compile.lock"))
        .unwrap();
    fs2::FileExt::lock_exclusive(&lock).unwrap();
    let scope = fixture.scope();
    let files = register_before_discovery(&scope, &fixture);
    let host = running(&fixture, &scope).await;
    let mut socket = host.connect().await;
    send(
        &mut socket,
        3,
        "morphir.model-originals.capture",
        capture_params(&host),
    )
    .await;
    tokio::time::timeout(WAIT, async {
        loop {
            if scope.snapshot().workers().started() == 1 && host.usage.usage().active_workers() == 1
            {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(
        scope
            .snapshot()
            .reads()
            .counts_for(&files.record)
            .unwrap()
            .content_attempts(),
        0
    );
    assert_eq!(
        scope
            .snapshot()
            .reads()
            .counts_for(&files.primary)
            .unwrap()
            .content_attempts(),
        0
    );
    socket.close(None).await.unwrap();
    drop(socket);
    tokio::time::timeout(WAIT, async {
        loop {
            let worker = scope.snapshot().workers();
            if worker.returned_error() == 1 && host.usage.usage() == ModelCaptureUsage::default() {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    // Lock stays held through observed cancellation/real body return. No source
    // read is inferred merely because the product/capture owner was cancelled.
    let product = scope.snapshot();
    assert_eq!(
        product
            .reads()
            .counts_for(&files.record)
            .unwrap()
            .content_attempts(),
        0
    );
    assert_eq!(
        product
            .reads()
            .counts_for(&files.primary)
            .unwrap()
            .content_attempts(),
        0
    );
    assert_eq!(product.workers().owned_handles(), 0);
    assert_eq!(product.workers().dropped_unjoined(), 1);
    assert_eq!(
        product.workers().joined_ok()
            + product.workers().joined_panicked()
            + product.workers().joined_cancelled(),
        0
    );
    assert!(product.workers().require_joined_cleanup().is_err());
    fs2::FileExt::unlock(&lock).unwrap();
    drop(lock);
    host.stop().await;
    let final_snapshot = recover(scope).await;
    assert!(
        final_snapshot.workers().require_joined_cleanup().is_err(),
        "sealed source owner and zero credits do not repair a detached task's missing join"
    );
}
