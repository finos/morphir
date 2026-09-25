//! Warm guests for the playground, one per provider id.
//!
//! The one-shot extension boundary pays activation and the MEP handshake on
//! every call; for an installed extension that is a process spawn per click.
//! [`PooledInvoker`] keeps one guest per provider in a
//! [`morphir_host::Pool`] and answers every playground compile and generate
//! over it. A native-direct provider has no guest to keep, so it goes
//! one-shot, through the same functions `morphir compile` and `morphir
//! generate` call.
//!
//! The pool owns reuse, replacement on a changed fingerprint, the single
//! retry after a lost guest, abandon, and idle eviction. This module chooses
//! the path, words the outcome in the CLI's texts, and drives the pool's idle
//! count: the portable pool keeps no clock, so the CLI ticks it.

use std::path::Path;
use std::sync::{Arc, Weak};
use std::time::Duration;

use async_trait::async_trait;
use morphir_extension_sdk::protocol::methods;
use morphir_extension_sdk::{CompileRequest, CompileResult, GenerateRequest, GenerateResult};
use morphir_host::{CallError, HostConfig, InvocationMode, Pool, Resolved};
use serde::{Serialize, de::DeserializeOwned};

use super::playground::ExtensionInvoker;
use crate::error::CliError;
use crate::extensions::guest;

/// An [`ExtensionInvoker`] that keeps one guest per provider across calls.
///
/// Guests are keyed by provider id, not per language or per operation: a
/// guest is one running extension, and an extension serving two languages,
/// or both compile and generate, serves all of them over the same session.
/// Within that key a guest is reused only while the resolution's
/// [`Resolved::fingerprint`] still names the same build.
///
/// A guest nobody has called for [`IDLE_LIMIT`] is stopped in order, as the
/// daemon's session actor stopped an idle session. A background task ticks
/// the pool every [`SWEEP_INTERVAL`] and evicts its idle guests, so an idle
/// guest stops between the limit and the limit plus one interval after its
/// last call ended. A guest with a call in flight is never stopped, however
/// long the call runs, and every guest the sweep stops is closed in order.
pub(super) struct PooledInvoker {
    pool: Arc<Pool<String>>,
}

/// How long a guest may go without a call before it is stopped. The daemon's
/// session actor used the same five minutes.
pub(super) const IDLE_LIMIT: Duration = Duration::from_secs(300);

/// How often the invoker ticks the pool and looks for idle guests.
const SWEEP_INTERVAL: Duration = Duration::from_secs(30);

/// How many pool ticks without a call make a guest idle.
///
/// The pool stamps a use with the tick count at that moment, so a guest used
/// just before a tick is evicted `n - 1` to `n` intervals later. The extra
/// tick keeps the idle time at least [`IDLE_LIMIT`].
const IDLE_TICKS: u64 = IDLE_LIMIT.as_secs() / SWEEP_INTERVAL.as_secs() + 1;

/// Tick `pool` and stop its idle guests every [`SWEEP_INTERVAL`], for as long
/// as the invoker lives.
///
/// The task holds the pool weakly, so it ends once the invoker is dropped.
fn spawn_idle_sweep(pool: Weak<Pool<String>>) {
    let Ok(runtime) = tokio::runtime::Handle::try_current() else {
        tracing::warn!("no async runtime: idle playground guests will not be stopped");
        return;
    };
    runtime.spawn(async move {
        let mut interval = tokio::time::interval(SWEEP_INTERVAL);
        // A late sweep must not replay the ticks it missed back to back: calls
        // made while it was late are stamped with the old count, so a burst of
        // catch-up ticks would make them look idle at once. Delay undercounts
        // instead, which only lets a guest live a little longer.
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        // The first tick completes at once; the sweep starts one interval on.
        interval.tick().await;
        loop {
            interval.tick().await;
            let Some(pool) = pool.upgrade() else {
                return;
            };
            pool.tick();
            pool.evict_idle(IDLE_TICKS).await;
        }
    });
}

impl PooledInvoker {
    /// An invoker that introduces the CLI to every guest with `config`, and
    /// stops a guest after [`IDLE_LIMIT`] without a call.
    pub(super) fn new(config: HostConfig) -> Self {
        let pool = Arc::new(Pool::new(config));
        spawn_idle_sweep(Arc::downgrade(&pool));
        Self { pool }
    }

    /// Answer one call over the provider's pooled guest.
    async fn call<P, R>(
        &self,
        workspace: &Path,
        resolved: &Resolved,
        method: &str,
        request: &P,
    ) -> Result<R, CliError>
    where
        P: Serialize + Sync,
        R: DeserializeOwned,
    {
        let provider = resolved.info().id.clone();
        let open = {
            let resolved = resolved.clone();
            let workspace = workspace.to_path_buf();
            move || {
                let resolved = resolved.clone();
                let workspace = workspace.clone();
                async move { resolved.connect(&workspace).await }
            }
        };
        self.pool
            .call(&provider, &resolved.fingerprint(), open, method, request)
            .await
            .map_err(|error| match error {
                CallError::Rejected(error) => CliError::Extension {
                    message: guest::rejected_text(&provider, method, error),
                },
                CallError::Failed(error) | CallError::Invalid(error) => CliError::Extension {
                    message: format!(
                        "Provider '{provider}' failed during '{method}': {}",
                        guest::failure_text(error)
                    ),
                },
                // A guest that does not start already carries the CLI's whole
                // message (see `guest::connect`).
                CallError::Connect(error) => CliError::Extension {
                    message: error.to_string(),
                },
                CallError::Handshake(error) => guest::failure(&provider, "initialize", error),
                other => CliError::Extension {
                    message: format!("Provider '{provider}' failed during '{method}': {other}"),
                },
            })
    }
}

#[async_trait]
impl ExtensionInvoker for PooledInvoker {
    async fn compile(
        &self,
        working_directory: &Path,
        resolved: &Resolved,
        request: CompileRequest,
    ) -> Result<CompileResult, CliError> {
        match resolved.invocation_mode() {
            InvocationMode::NativeDirect => {
                crate::extensions::invoke_frontend(working_directory, resolved, request).await
            }
            _ => {
                self.call(working_directory, resolved, methods::COMPILE, &request)
                    .await
            }
        }
    }

    async fn generate(
        &self,
        working_directory: &Path,
        resolved: &Resolved,
        request: GenerateRequest,
    ) -> Result<GenerateResult, CliError> {
        match resolved.invocation_mode() {
            InvocationMode::NativeDirect => {
                crate::extensions::invoke_backend(working_directory, resolved, request).await
            }
            _ => {
                self.call(working_directory, resolved, methods::GENERATE, &request)
                    .await
            }
        }
    }

    /// A timed-out call may have left its guest wedged on the hung exchange.
    /// The pool forgets the guest, so the next request opens a fresh one.
    async fn abandon(&self, provider: &str) {
        self.pool.abandon(&provider.to_owned()).await;
    }
}

// The playground holds its invoker as `Arc<dyn ExtensionInvoker>` across
// tasks. `#[async_trait]` already makes every method's future `Send`; this
// keeps the invoker itself shareable.
const _: () = {
    const fn shareable<T: Send + Sync>() {}
    shareable::<PooledInvoker>();
};

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_extension_sdk::protocol::{InitializeParams, RpcError};
    use morphir_extension_sdk::{
        CompileOptions, CompilePackage, ExtensionCapabilities, ExtensionInfo, NativeExtension,
        SourceDocument, SourceSet,
    };
    use morphir_gleam_binding::GleamExtension;
    use morphir_host::{
        CapabilityMetadataScope, ChannelCause, ChannelState, GuestConnection, GuestSource,
        HostError, InvocationPolicy, Negotiated, ProviderOrigin, Registry,
    };
    use morphir_host_native::NativeSource;
    use serde_json::json;
    use std::collections::{HashMap, VecDeque};
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::time::Duration;

    /// What the scripted guest does with its next call.
    enum Fault {
        /// The session breaks under the call.
        Lose,
        /// The guest refuses the call; the session stays usable.
        Reject,
        /// The call never answers.
        Hang,
        /// The call answers after this long.
        Delay(Duration),
        /// The guest answers with a result that does not decode.
        Garble,
        /// The session breaks under the call, and from then on no guest
        /// starts: every later start fails with this text.
        LoseForGood(&'static str),
    }

    /// What a test tells the scripted guests to do, and what it observes.
    #[derive(Default)]
    struct Script {
        opens: AtomicUsize,
        closes: AtomicUsize,
        faults: Mutex<VecDeque<Fault>>,
        refuse_start: Mutex<Option<String>>,
        refuse_handshake: AtomicBool,
    }

    impl Script {
        fn with_faults(faults: impl IntoIterator<Item = Fault>) -> Arc<Self> {
            let script = Self::default();
            script.faults.lock().unwrap().extend(faults);
            Arc::new(script)
        }

        fn opens(&self) -> usize {
            self.opens.load(Ordering::SeqCst)
        }

        fn closes(&self) -> usize {
            self.closes.load(Ordering::SeqCst)
        }
    }

    /// The built-in Gleam provider as a source whose guests follow a
    /// [`Script`]. Under `ProtocolOnly` it resolves to `NativeMep`, so calls
    /// reach a real Gleam guest over MEP through the pool.
    struct ScriptedSource {
        inner: NativeSource,
        incarnation: Option<String>,
        script: Arc<Script>,
    }

    #[async_trait]
    impl GuestSource for ScriptedSource {
        fn info(&self) -> &ExtensionInfo {
            self.inner.info()
        }

        fn capabilities(&self) -> &ExtensionCapabilities {
            self.inner.capabilities()
        }

        fn origin(&self) -> ProviderOrigin {
            self.inner.origin()
        }

        fn capability_metadata_scope(&self) -> CapabilityMetadataScope {
            self.inner.capability_metadata_scope()
        }

        fn invocation_mode(&self, policy: InvocationPolicy) -> InvocationMode {
            self.inner.invocation_mode(policy)
        }

        fn native(&self) -> Option<&NativeExtension> {
            self.inner.native()
        }

        fn incarnation(&self) -> Option<&str> {
            self.incarnation.as_deref()
        }

        async fn connect(&self, workspace: &Path) -> Result<Box<dyn GuestConnection>, HostError> {
            self.script.opens.fetch_add(1, Ordering::SeqCst);
            if let Some(message) = self.script.refuse_start.lock().unwrap().clone() {
                return Err(HostError::Invalid(message));
            }
            Ok(Box::new(ScriptedConnection {
                inner: self.inner.connect(workspace).await?,
                script: Arc::clone(&self.script),
            }))
        }
    }

    struct ScriptedConnection {
        inner: Box<dyn GuestConnection>,
        script: Arc<Script>,
    }

    #[async_trait]
    impl GuestConnection for ScriptedConnection {
        async fn open(&mut self, params: InitializeParams) -> Result<Negotiated, HostError> {
            if self.script.refuse_handshake.load(Ordering::SeqCst) {
                return Err(HostError::Invalid("refused the handshake".into()));
            }
            self.inner.open(params).await
        }

        async fn call(
            &mut self,
            method: &str,
            params: serde_json::Value,
        ) -> Result<serde_json::Value, CallError> {
            let fault = self.script.faults.lock().unwrap().pop_front();
            match fault {
                Some(Fault::Lose) => Err(CallError::Failed(HostError::Channel {
                    message: "guest went away".into(),
                    state: ChannelState::Stopped,
                    cause: ChannelCause::Transport,
                })),
                Some(Fault::Reject) => Err(CallError::Rejected(HostError::Rpc(RpcError {
                    code: -32001,
                    message: "does not compile".into(),
                    data: None,
                }))),
                Some(Fault::Hang) => std::future::pending().await,
                Some(Fault::Delay(delay)) => {
                    tokio::time::sleep(delay).await;
                    self.inner.call(method, params).await
                }
                Some(Fault::Garble) => Ok(json!("not a compile result")),
                Some(Fault::LoseForGood(message)) => {
                    *self.script.refuse_start.lock().unwrap() = Some(message.into());
                    Err(CallError::Failed(HostError::Channel {
                        message: "guest went away".into(),
                        state: ChannelState::Stopped,
                        cause: ChannelCause::Transport,
                    }))
                }
                None => self.inner.call(method, params).await,
            }
        }

        async fn close(&mut self) -> Result<(), HostError> {
            self.script.closes.fetch_add(1, Ordering::SeqCst);
            self.inner.close().await
        }
    }

    fn registry(script: &Arc<Script>, incarnation: Option<&str>) -> Registry {
        let gleam = NativeExtension::builder(GleamExtension)
            .with_frontend()
            .with_backend()
            .with_workspace()
            .finish()
            .unwrap();
        let mut registry = Registry::new();
        registry
            .register(Arc::new(ScriptedSource {
                inner: NativeSource::new(gleam),
                incarnation: incarnation.map(str::to_owned),
                script: Arc::clone(script),
            }))
            .unwrap();
        registry
    }

    fn frontend(registry: &Registry, policy: InvocationPolicy) -> Resolved {
        registry.resolve_frontend("gleam", "4.0.0", policy).unwrap()
    }

    fn backend(registry: &Registry, policy: InvocationPolicy) -> Resolved {
        registry.resolve_backend("gleam", "4.0.0", policy).unwrap()
    }

    fn invoker() -> PooledInvoker {
        PooledInvoker::new(crate::commands::extension::host_config())
    }

    fn compile_request(output_dir: &Path) -> CompileRequest {
        CompileRequest {
            language_id: "gleam".into(),
            sources: SourceSet {
                root: Some("file:///workspace/src".into()),
                documents: vec![SourceDocument {
                    uri: "file:///workspace/src/main.gleam".into(),
                    language_id: "gleam".into(),
                    version: 1,
                    text: "pub fn hello() {\n  \"world\"\n}\n".into(),
                }],
            },
            package: CompilePackage {
                name: "example/hello".into(),
                exposed_modules: Some(vec![]),
            },
            dependencies: vec![],
            baseline: None,
            options: CompileOptions {
                types_only: false,
                ir_version: "4.0.0".into(),
                extra: HashMap::from([
                    ("outputDir".into(), json!(output_dir)),
                    ("emitParseStage".into(), json!(false)),
                    ("emitParseStageFatal".into(), json!(false)),
                ]),
            },
        }
    }

    fn message(error: CliError) -> String {
        match error {
            CliError::Extension { message } => message,
            other => panic!("expected an extension error, got {other:?}"),
        }
    }

    // A native-direct provider is an in-process function call: there is no
    // guest to keep warm, so the call goes one-shot and opens nothing.
    #[tokio::test]
    async fn a_direct_provider_goes_one_shot() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        let registry = registry(&script, None);
        let invoker = invoker();

        let compiled = invoker
            .compile(
                temp.path(),
                &frontend(&registry, InvocationPolicy::PreferDirect),
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap();
        let generated = invoker
            .generate(
                temp.path(),
                &backend(&registry, InvocationPolicy::PreferDirect),
                GenerateRequest {
                    ir: compiled.ir.unwrap(),
                    target: "gleam".into(),
                    options: HashMap::new(),
                },
            )
            .await
            .unwrap();

        assert!(generated.success);
        assert_eq!(script.opens(), 0);
    }

    // Requirement: this module's whole purpose. Repeated compiles and a
    // generate ride one guest, and answer exactly as the one-shot path does:
    // reuse changes the cost of a call, never its result.
    #[tokio::test]
    async fn compiles_and_a_generate_share_one_guest_and_answer_like_one_shot() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        let registry = registry(&script, None);
        let invoker = invoker();
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let request = compile_request(&temp.path().join("compile"));

        let first = invoker
            .compile(temp.path(), &resolved, request.clone())
            .await
            .unwrap();
        let second = invoker
            .compile(temp.path(), &resolved, request.clone())
            .await
            .unwrap();
        let generated = invoker
            .generate(
                temp.path(),
                &backend(&registry, InvocationPolicy::ProtocolOnly),
                GenerateRequest {
                    ir: first.ir.clone().unwrap(),
                    target: "gleam".into(),
                    options: HashMap::new(),
                },
            )
            .await
            .unwrap();
        assert_eq!(script.opens(), 1);

        let one_shot = crate::extensions::invoke_frontend(
            temp.path(),
            &frontend(&registry, InvocationPolicy::PreferDirect),
            request,
        )
        .await
        .unwrap();
        assert_eq!(
            serde_json::to_value(&first).unwrap(),
            serde_json::to_value(&second).unwrap()
        );
        assert_eq!(
            serde_json::to_value(&second).unwrap(),
            serde_json::to_value(&one_shot).unwrap()
        );
        assert!(generated.success);
    }

    // A guest that breaks under a call is a fact about the guest, not the
    // request: the request gets exactly one more try on a fresh guest.
    #[tokio::test]
    async fn a_lost_guest_is_reopened_and_the_call_retried_once() {
        let temp = tempfile::tempdir().unwrap();
        let script = Script::with_faults([Fault::Lose]);
        let registry = registry(&script, None);

        let compiled = invoker()
            .compile(
                temp.path(),
                &frontend(&registry, InvocationPolicy::ProtocolOnly),
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap();

        assert!(compiled.success);
        assert_eq!(script.opens(), 2);
    }

    // A guest lost twice in a row is a provider problem the user must see,
    // and it is not kept: the next call opens fresh.
    #[tokio::test]
    async fn a_guest_lost_twice_surfaces_the_failure_and_is_not_kept() {
        let temp = tempfile::tempdir().unwrap();
        let script = Script::with_faults([Fault::Lose, Fault::Lose]);
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let invoker = invoker();

        let error = invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap_err();
        assert_eq!(
            message(error),
            "Provider 'morphir-gleam' failed during 'morphir.frontend.compile': Extension error: guest went away"
        );

        invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap();
        assert_eq!(script.opens(), 3);
    }

    // A rejection is the guest answering: the caller sees the rejected text,
    // and the guest stays warm for the next call.
    #[tokio::test]
    async fn a_rejection_surfaces_and_keeps_the_guest() {
        let temp = tempfile::tempdir().unwrap();
        let script = Script::with_faults([Fault::Reject]);
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let invoker = invoker();

        let error = invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap_err();
        assert_eq!(
            message(error),
            "Provider 'morphir-gleam' rejected 'morphir.frontend.compile': Extension error: RPC error -32001: does not compile"
        );

        invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap();
        assert_eq!(script.opens(), 1);
    }

    // A result that does not decode is the guest's answer, not a lost guest:
    // the same build would answer the same way, so the call is not retried.
    // The guest is stopped in order and the next call opens a fresh one.
    #[tokio::test]
    async fn a_result_that_does_not_decode_is_not_retried() {
        let temp = tempfile::tempdir().unwrap();
        let script = Script::with_faults([Fault::Garble]);
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let invoker = invoker();

        let error = invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap_err();
        assert_eq!(
            message(error),
            "Provider 'morphir-gleam' failed during 'morphir.frontend.compile': JSON error: invalid type: string \"not a compile result\", expected struct CompileResult"
        );
        assert_eq!(script.opens(), 1);
        assert_eq!(script.closes(), 1);

        invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap();
        assert_eq!(script.opens(), 2);
    }

    #[tokio::test]
    async fn abandoning_a_provider_forgets_its_guest() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let invoker = invoker();

        for abandon in [false, true, false] {
            invoker
                .compile(
                    temp.path(),
                    &resolved,
                    compile_request(&temp.path().join("compile")),
                )
                .await
                .unwrap();
            if abandon {
                invoker.abandon("morphir-gleam").await;
            }
        }

        assert_eq!(script.opens(), 2);
    }

    // When the playground's patience runs out it drops the call. The hung
    // guest goes with it: a timed-out call leaves no cached guest, so the
    // next request opens a fresh one and keeps it. (That the playground also
    // abandons the provider is pinned by
    // `abandoning_a_provider_forgets_its_guest`.)
    #[tokio::test]
    async fn a_timed_out_call_leaves_no_cached_guest() {
        let temp = tempfile::tempdir().unwrap();
        let script = Script::with_faults([Fault::Hang]);
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let invoker = invoker();
        // Long enough that the guest opens and takes the `Hang` fault even
        // on a loaded machine; the call never answers, so the bound is what
        // ends it. The later calls are bounded too, so a failure here fails
        // the test instead of hanging it.
        let bound = Duration::from_secs(5);
        let compile = || {
            invoker.compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
        };

        let timed_out = tokio::time::timeout(bound, compile()).await;
        assert!(timed_out.is_err(), "the scripted guest never answers");

        let compiled = tokio::time::timeout(bound, compile())
            .await
            .expect("a fresh guest answers")
            .unwrap();
        assert!(compiled.success);
        tokio::time::timeout(bound, compile())
            .await
            .expect("the fresh guest answers again")
            .unwrap();
        assert_eq!(script.opens(), 2);
    }

    // A guest nobody calls for the idle limit is stopped in order, as the
    // daemon's session actor stopped an idle session, and the next call opens
    // a fresh one.
    #[tokio::test(start_paused = true)]
    async fn an_idle_guest_is_stopped_and_the_next_call_opens_a_fresh_one() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let invoker = invoker();

        invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap();
        tokio::time::sleep(IDLE_LIMIT + 2 * SWEEP_INTERVAL).await;
        assert_eq!(script.closes(), 1, "the idle guest is shut down in order");

        invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap();
        assert_eq!(script.opens(), 2);
    }

    // The pool counts idle time in whole sweep intervals. A call made just
    // before a sweep is stamped with the count before that sweep, so without
    // the extra tick in `IDLE_TICKS` its guest would stop one interval short
    // of the idle limit. The guest lives at least the idle limit.
    #[tokio::test(start_paused = true)]
    async fn a_guest_used_just_before_a_sweep_lives_at_least_the_idle_limit() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let start = tokio::time::Instant::now();
        let invoker = invoker();

        let called_at = start + SWEEP_INTERVAL - Duration::from_secs(1);
        tokio::time::sleep_until(called_at).await;
        invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap();
        assert!(
            tokio::time::Instant::now() < start + SWEEP_INTERVAL,
            "the call ends before the first sweep"
        );

        tokio::time::sleep_until(called_at + IDLE_LIMIT - Duration::from_secs(10)).await;
        assert_eq!(script.closes(), 0, "the guest is kept for the idle limit");

        tokio::time::sleep_until(called_at + IDLE_LIMIT + 2 * SWEEP_INTERVAL).await;
        assert_eq!(script.closes(), 1, "the idle guest is shut down in order");
    }

    // The idle limit runs from the last call, not from when the guest
    // started: a guest called within the limit each time is kept.
    #[tokio::test(start_paused = true)]
    async fn a_guest_used_within_the_idle_limit_is_kept() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let invoker = invoker();

        for _ in 0..3 {
            invoker
                .compile(
                    temp.path(),
                    &resolved,
                    compile_request(&temp.path().join("compile")),
                )
                .await
                .unwrap();
            tokio::time::sleep(IDLE_LIMIT - SWEEP_INTERVAL).await;
        }

        assert_eq!(script.closes(), 0);
        assert_eq!(script.opens(), 1);
    }

    // A call that runs longer than the idle limit is working, not idle: its
    // guest is not stopped under it, and it stays warm afterwards.
    #[tokio::test(start_paused = true)]
    async fn a_call_longer_than_the_idle_limit_keeps_its_guest() {
        let temp = tempfile::tempdir().unwrap();
        let script = Script::with_faults([Fault::Delay(2 * IDLE_LIMIT)]);
        let registry = registry(&script, None);
        let resolved = frontend(&registry, InvocationPolicy::ProtocolOnly);
        let invoker = invoker();

        for _ in 0..2 {
            invoker
                .compile(
                    temp.path(),
                    &resolved,
                    compile_request(&temp.path().join("compile")),
                )
                .await
                .unwrap();
        }

        assert_eq!(script.closes(), 0);
        assert_eq!(script.opens(), 1);
    }

    // A reinstall under the same id resolves to another build. The guest the
    // old build opened must not serve it.
    #[tokio::test]
    async fn a_changed_fingerprint_replaces_the_guest() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        let before = frontend(
            &registry(&script, Some("a")),
            InvocationPolicy::ProtocolOnly,
        );
        let after = frontend(
            &registry(&script, Some("b")),
            InvocationPolicy::ProtocolOnly,
        );
        assert_ne!(before.fingerprint(), after.fingerprint());
        let invoker = invoker();

        for resolved in [&before, &after, &after] {
            invoker
                .compile(
                    temp.path(),
                    resolved,
                    compile_request(&temp.path().join("compile")),
                )
                .await
                .unwrap();
        }

        assert_eq!(script.opens(), 2);
    }

    // A guest that does not start already carries the CLI's whole message,
    // such as an installed provider's verification failure.
    #[tokio::test]
    async fn a_guest_that_does_not_start_reports_its_own_text() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        *script.refuse_start.lock().unwrap() =
            Some("Failed to verify installed provider 'morphir-gleam': digest mismatch".into());
        let registry = registry(&script, None);

        let error = invoker()
            .compile(
                temp.path(),
                &frontend(&registry, InvocationPolicy::ProtocolOnly),
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap_err();

        assert_eq!(
            message(error),
            "Failed to verify installed provider 'morphir-gleam': digest mismatch"
        );
    }

    // A lost guest whose replacement does not start: the caller gets the
    // start failure's own text, not a handshake or "failed during" text.
    #[tokio::test]
    async fn a_replacement_that_does_not_start_reports_its_own_text() {
        let temp = tempfile::tempdir().unwrap();
        let script = Script::with_faults([Fault::LoseForGood(
            "Failed to verify installed provider 'morphir-gleam': digest mismatch",
        )]);
        let registry = registry(&script, None);

        let error = invoker()
            .compile(
                temp.path(),
                &frontend(&registry, InvocationPolicy::ProtocolOnly),
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap_err();

        assert_eq!(
            message(error),
            "Failed to verify installed provider 'morphir-gleam': digest mismatch"
        );
        assert_eq!(script.opens(), 2);
    }

    #[tokio::test]
    async fn a_refused_handshake_reads_as_an_initialize_failure() {
        let temp = tempfile::tempdir().unwrap();
        let script = Arc::new(Script::default());
        script.refuse_handshake.store(true, Ordering::SeqCst);
        let registry = registry(&script, None);

        let error = invoker()
            .compile(
                temp.path(),
                &frontend(&registry, InvocationPolicy::ProtocolOnly),
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap_err();

        assert_eq!(
            message(error),
            "Provider 'morphir-gleam' failed during initialize: Extension error: refused the handshake"
        );
    }

    // A real installed guest through the pool: its rejection and its
    // verification failure read as they do on the one-shot path.
    #[cfg(unix)]
    #[tokio::test]
    async fn an_installed_provider_keeps_its_texts_through_the_pool() {
        let temp = tempfile::tempdir().unwrap();
        let (guest, record) = crate::extensions::installed_fixture::rejecting_frontend();
        let (home, snapshot) =
            crate::extensions::installed_fixture::install_process(temp.path(), record, &guest);
        let registry =
            crate::extensions::extension_registry_for(&home, [snapshot.clone()], Some("fixture"))
                .unwrap();
        let resolved = frontend(&registry, InvocationPolicy::PreferDirect);
        let invoker = invoker();

        let rejected = invoker
            .compile(
                temp.path(),
                &resolved,
                compile_request(&temp.path().join("compile")),
            )
            .await
            .unwrap_err();
        assert_eq!(
            message(rejected),
            "Provider 'fixture' rejected 'morphir.frontend.compile': Extension error: RPC error -32001: does not compile"
        );

        invoker.abandon("fixture").await;
        crate::extensions::installed_fixture::tamper(&home, &snapshot);
        let unverified = message(
            invoker
                .compile(
                    temp.path(),
                    &resolved,
                    compile_request(&temp.path().join("compile")),
                )
                .await
                .unwrap_err(),
        );
        assert!(
            unverified.starts_with("Failed to verify installed provider 'fixture': "),
            "{unverified}"
        );
        assert!(unverified.contains("digest mismatch"), "{unverified}");
    }
}
