use super::*;
use crate::commands::ui::{
    protocol::project_key,
    provider::{
        WorkspaceCapability,
        native::NativeWorkspaceProvider,
        originals::{OriginalsProvider, OriginalsSelection},
    },
};
use morphir_devkit::ConfigLoadOptions;
use std::sync::Arc;

// Tests arrange an actual session registration just as the CLI host does.
// The production start method accepts only the opaque selection from that
// owner. Keeping this fixture owner alive is not a production bypass.
pub(in crate::commands::ui) struct FixtureProviderCapture {
    pending: PendingProviderCapture,
    session: crate::commands::ui::provider::current::CurrentSessionCapabilities,
}
impl FixtureProviderCapture {
    pub(in crate::commands::ui) async fn wait(
        self,
    ) -> Result<ModelCaptureCompletion, ProviderCaptureError> {
        self.pending.wait().await
    }
}
impl ModelCaptureConnection {
    pub(in crate::commands::ui) fn start_provider(
        &self,
        provider: OriginalsProvider,
        selection: OriginalsSelection,
        scope: CaptureScope,
    ) -> Result<FixtureProviderCapture, CaptureError> {
        self.start_provider_with(
            provider,
            selection,
            scope,
            CaptureControl::new(),
            Arc::new(FixtureNoopHooks),
        )
    }
    fn start_provider_with(
        &self,
        provider: OriginalsProvider,
        selection: OriginalsSelection,
        scope: CaptureScope,
        control: CaptureControl,
        hooks: Arc<dyn WorkerHooks>,
    ) -> Result<FixtureProviderCapture, CaptureError> {
        use crate::commands::ui::provider::{
            SessionCapabilities, current::CurrentSessionCapabilities,
        };
        let session = CurrentSessionCapabilities::new(SessionCapabilities {
            workspace: Some(provider.workspace()),
            ..Default::default()
        });
        session.register_originals(provider).unwrap();
        let offer = session.select_originals(selection).unwrap();
        let pending = self.start_offered_provider_with(offer, scope, control, hooks)?;
        Ok(FixtureProviderCapture { pending, session })
    }
}
struct FixtureNoopHooks;
impl WorkerHooks for FixtureNoopHooks {}

#[tokio::test]
async fn frozen_header_is_inspected_on_worker_before_private_prepared_publication() {
    let (temp, provider) = native_fixture();
    let original = br#"{"formatVersion":"3.1.0","opaque":"original"}"#;
    let primary = temp.path().join(".morphir/out/compile.dest/model.json");
    std::fs::write(&primary, original).unwrap();
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let (hook, arrived, release) = held_provider(false);
    let pending = owner
        .start_provider_with(
            OriginalsProvider::Native(provider.clone()),
            selected(&provider, "."),
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    assert_eq!(host.usage().active_workers(), 1);
    assert_eq!(host.usage().source_bytes(), original.len());
    // The original snapshot and source evidence must stay paired even when the
    // live primary changes before the real authority revalidation.
    std::fs::write(&primary, br#"{"formatVersion":99}"#).unwrap();
    release.send(()).unwrap();
    let id = pending.wait().await.unwrap().ready().unwrap();
    owner
        .inspect_owned(&id, |sources| {
            assert_eq!(
                sources.source_version(),
                SourceVersionEvidence::Reported(morphir_core::format_version::ReleaseTriplet::new(
                    3, 1, 0
                ))
            );
            assert_eq!(
                sources.file_bytes(sources.primary().path()).unwrap(),
                original
            );
        })
        .unwrap();
    owner.release(&id).unwrap();
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

struct HoldSourceHeader(Arc<HoldProvider>);
impl WorkerHooks for HoldSourceHeader {
    fn before_source_header(&self) {
        self.0.block();
    }
}

#[tokio::test]
async fn disconnect_during_frozen_header_stage_retains_actual_worker_and_source_credits() {
    let (temp, provider) = native_fixture();
    let original = br#"{"formatVersion":4}"#;
    std::fs::write(
        temp.path().join(".morphir/out/compile.dest/model.json"),
        original,
    )
    .unwrap();
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let (hook, arrived, release) = held_provider(false);
    let pending = owner
        .start_provider_with(
            OriginalsProvider::Native(provider.clone()),
            selected(&provider, "."),
            CaptureScope::Primary,
            CaptureControl::new(),
            Arc::new(HoldSourceHeader(hook)),
        )
        .unwrap();
    arrived.await.unwrap();
    let held = host.usage();
    assert_eq!(held.active_workers(), 1);
    assert_eq!(held.captures(), 1);
    assert_eq!(held.source_bytes(), original.len());
    assert!(held.metadata_bytes() >= std::mem::size_of::<SourceVersionEvidence>());
    owner.close();
    drop(pending);
    // The actual blocked worker still owns source bytes, header metadata, the
    // capture slot and work permit. Closing the waiter cannot refund them.
    assert_eq!(host.usage(), held);
    release.send(()).unwrap();
    effects_stopped(&host).await;
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn frozen_tree_header_uses_unique_supported_manifest_not_sidecars_or_descriptor() {
    for ambiguous in [false, true] {
        let (temp, provider) = native_fixture();
        let output = temp.path().join(".morphir/out");
        std::fs::create_dir(output.join("compile.dest/tree")).unwrap();
        std::fs::write(
            output.join("compile.dest/tree/000-first.json"),
            br#"{"formatVersion":99}"#,
        )
        .unwrap();
        std::fs::write(
            output.join("compile.dest/tree/manifest.yml"),
            b"formatVersion: 2\nopaque: preserved\n",
        )
        .unwrap();
        if ambiguous {
            std::fs::write(
                output.join("compile.dest/tree/manifest.json"),
                br#"{"formatVersion":4}"#,
            )
            .unwrap();
        }
        std::fs::write(output.join("compile.json"), br#"{"schema":1,"task":"compile","module":"","completedAt":"now","ir":{"path":"tree","layout":"document-tree","format":"yaml","version":"v4"}}"#).unwrap();
        let host = HostModelCaptureCapacity::default();
        let owner = ModelCaptureConnection::new(host.clone());
        let id = owner
            .start_provider(
                OriginalsProvider::Native(provider.clone()),
                selected(&provider, "."),
                CaptureScope::Primary,
            )
            .unwrap()
            .wait()
            .await
            .unwrap()
            .ready()
            .unwrap();
        owner
            .inspect_owned(&id, |sources| {
                assert_eq!(
                    sources.source_version(),
                    if ambiguous {
                        SourceVersionEvidence::NotReported
                    } else {
                        SourceVersionEvidence::Reported(
                            morphir_core::format_version::ReleaseTriplet::new(2, 0, 0),
                        )
                    }
                )
            })
            .unwrap();
        owner.release(&id).unwrap();
        assert_eq!(host.usage(), ModelCaptureUsage::default());
    }
}

fn native_fixture() -> (tempfile::TempDir, Arc<NativeWorkspaceProvider>) {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(
        temp.path().join("morphir.toml"),
        "[project]\nname='acme/orders'\nversion='1.0.0'\n",
    )
    .unwrap();
    let output = temp.path().join(".morphir/out");
    std::fs::create_dir_all(output.join("compile.dest")).unwrap();
    std::fs::write(
        output.join("compile.dest/model.json"),
        b"actual native captured bytes",
    )
    .unwrap();
    std::fs::write(output.join("compile.json"), br#"{"schema":1,"task":"compile","module":"","completedAt":"now","ir":{"path":"model.json","layout":"single-file","format":"json","version":"v4"}}"#).unwrap();
    let provider = Arc::new(
        NativeWorkspaceProvider::discover_with_options(
            temp.path(),
            "originals-session",
            ConfigLoadOptions::project_only(),
        )
        .unwrap()
        .authorize_originals_lookup(cap_std::ambient_authority())
        .unwrap(),
    );
    (temp, provider)
}

#[tokio::test]
async fn actual_native_provider_resolves_its_owned_source_before_originals_publication() {
    let (_temp, provider) = native_fixture();
    let source = provider.initial_sources().pop().unwrap();
    let selection = OriginalsSelection::parse(&source, &project_key(&source, ".")).unwrap();
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let capture = owner
        .start_provider(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
        )
        .unwrap()
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    assert_eq!(owner.inspect(&capture).unwrap().source_byte_length(), 28);
    assert_eq!(host.usage().active_workers(), 0);
    owner.release(&capture).unwrap();
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn wire_identity_pair_selects_actual_provider_without_fabricated_display_fields() {
    let (_temp, provider) = native_fixture();
    let source = provider.initial_sources().pop().unwrap();
    let selection = OriginalsSelection::parse_identity(
        &source.provider_id,
        &source.locator,
        &project_key(&source, "."),
    )
    .unwrap();
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let capture = owner
        .start_provider(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
        )
        .unwrap()
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    assert_eq!(owner.inspect(&capture).unwrap().source_byte_length(), 28);
    owner.release(&capture).unwrap();
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

fn selected(provider: &NativeWorkspaceProvider, relative: &str) -> OriginalsSelection {
    let source = provider.initial_sources().pop().unwrap();
    OriginalsSelection::parse(&source, &project_key(&source, relative)).unwrap()
}

#[tokio::test]
async fn ordinary_v1_provider_does_not_issue_originals_host_lookup_authority() {
    let (temp, _) = native_fixture();
    let provider = NativeWorkspaceProvider::discover_with_options(
        temp.path(),
        "unissued",
        ConfigLoadOptions::project_only(),
    )
    .unwrap();
    let selection = selected(&provider, ".");
    let source = provider.initial_sources().pop().unwrap();
    assert!(provider.open(&source).await.is_ok());
    assert!(
        !provider
            .manifest()
            .capabilities
            .iter()
            .any(|capability| capability.name.contains("originals"))
    );
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let result = owner
        .start_provider(
            OriginalsProvider::Native(Arc::new(provider)),
            selection,
            CaptureScope::Primary,
        )
        .unwrap()
        .wait()
        .await;
    assert!(
        matches!(result, Err(ProviderCaptureError::Authority(_))),
        "{result:?}"
    );
    assert!(!temp.path().join(".morphir/out/compile.lock").exists());
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn witness_capacity_is_reserved_before_lookup_or_retained_binding_copies() {
    let (temp, provider) = native_fixture();
    let selection = selected(&provider, ".");
    // A lookup would now fail parsing. Zero retained evidence credit must win
    // before this trusted-host effect, rather than returning that parse error.
    std::fs::write(temp.path().join("morphir.toml"), "[invalid").unwrap();
    let host = HostModelCaptureCapacity::with_limits(super::lifecycle::HostLimits {
        metadata: 0,
        ..Default::default()
    });
    let owner = ModelCaptureConnection::new(host.clone());
    let result = owner
        .start_provider(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
        )
        .unwrap()
        .wait()
        .await;
    assert!(
        matches!(
            result,
            Err(ProviderCaptureError::Capture(CaptureError::Capacity))
        ),
        "{result:?}"
    );
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn replaced_startup_root_is_refused_before_replacement_config_parsing() {
    let (temp, provider) = native_fixture();
    let selection = selected(&provider, ".");
    let retired = temp.path().with_extension("retired");
    std::fs::rename(temp.path(), &retired).unwrap();
    std::fs::create_dir(temp.path()).unwrap();
    std::fs::write(temp.path().join("morphir.toml"), "[invalid replacement").unwrap();
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let result = owner
        .start_provider(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
        )
        .unwrap()
        .wait()
        .await;
    let Err(ProviderCaptureError::Authority(error)) = result else {
        panic!("{result:?}")
    };
    assert!(
        error.to_string().contains("workspace root changed"),
        "{error}"
    );
    assert_eq!(host.usage(), ModelCaptureUsage::default());
    std::fs::remove_dir_all(retired).unwrap();
}

#[tokio::test]
async fn newly_matching_workspace_module_cannot_publish_old_private_capture() {
    let root = tempfile::tempdir().unwrap();
    let member = root.path().join("packages/orders");
    std::fs::create_dir_all(&member).unwrap();
    std::fs::write(
        member.join("morphir.toml"),
        "[project]\nname='acme/orders'\nversion='1.0.0'\n",
    )
    .unwrap();
    let exports = tempfile::tempdir().unwrap();
    std::fs::create_dir(exports.path().join("compile.dest")).unwrap();
    std::fs::write(
        exports.path().join("compile.dest/model.json"),
        "original module bytes",
    )
    .unwrap();
    std::fs::write(exports.path().join("compile.json"), br#"{"schema":1,"task":"compile","module":"","completedAt":"R1","ir":{"path":"model.json","layout":"single-file","format":"json","version":"v4"}}"#).unwrap();
    let provider = Arc::new(
        NativeWorkspaceProvider::discover_with_options(
            &member,
            "module-change",
            ConfigLoadOptions::project_only(),
        )
        .unwrap()
        .with_out_overrides(crate::commands::out_context::OutOverrides {
            flag: Some(exports.path().to_owned()),
            env: None,
        })
        .authorize_originals_lookup(cap_std::ambient_authority())
        .unwrap(),
    );
    let selection = selected(&provider, ".");
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let (hook, arrived, release) = held_provider(false);
    let pending = owner
        .start_provider_with(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    std::fs::write(
        root.path().join("morphir.toml"),
        "[workspace]\nmembers=['packages/*']\n",
    )
    .unwrap();
    release.send(()).unwrap();
    assert!(matches!(
        pending.wait().await,
        Err(ProviderCaptureError::Changed)
    ));
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn unrelated_configuration_edit_preserves_binding_and_original_r1_capture() {
    let (temp, provider) = native_fixture();
    let selection = selected(&provider, ".");
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let (hook, arrived, release) = held_provider(false);
    let pending = owner
        .start_provider_with(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    std::fs::write(
        temp.path().join("morphir.toml"),
        "[project]\nname='acme/orders'\nversion='1.0.0'\ndescription='an unrelated description'\n",
    )
    .unwrap();
    // Cooperating compilation has finished after the original shared lock was
    // released. This must not turn immutable R1 into a claim about latest R2.
    std::fs::write(
        temp.path().join(".morphir/out/compile.dest/model.json"),
        "later compile R2 with different original bytes",
    )
    .unwrap();
    release.send(()).unwrap();
    let id = pending.wait().await.unwrap().ready().unwrap();
    assert_eq!(owner.inspect(&id).unwrap().source_byte_length(), 28);
    owner.release(&id).unwrap();
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn current_session_removal_or_replacement_prevents_private_prepared_publication() {
    for change in ["remove", "replace", "reoffer"] {
        let (_temp, provider) = native_fixture();
        let selection = selected(&provider, ".");
        let host = HostModelCaptureCapacity::default();
        let owner = ModelCaptureConnection::new(host.clone());
        let (hook, arrived, release) = held_provider(false);
        let pending = owner
            .start_provider_with(
                OriginalsProvider::Native(provider.clone()),
                selection,
                CaptureScope::Primary,
                CaptureControl::new(),
                hook,
            )
            .unwrap();
        arrived.await.unwrap();
        let (_replacement_temp, replacement) = native_fixture();
        match change {
            "remove" => pending.session.revoke_workspace(),
            "replace" => {
                pending.session.replace_workspace(Some(replacement.clone()));
                pending
                    .session
                    .register_originals(OriginalsProvider::Native(replacement))
                    .unwrap();
            }
            _ => pending
                .session
                .register_originals(OriginalsProvider::Native(provider))
                .unwrap(),
        }
        assert_eq!(pending.session.workspace().is_none(), change == "remove");
        release.send(()).unwrap();
        let result = pending.wait().await;
        assert!(
            matches!(result, Err(ProviderCaptureError::Changed)),
            "{change}: {result:?}"
        );
        assert_eq!(host.usage(), ModelCaptureUsage::default());
    }
}

#[tokio::test]
async fn stale_current_offer_is_refused_before_trusted_lookup() {
    use crate::commands::ui::provider::{SessionCapabilities, current::CurrentSessionCapabilities};
    let (temp, provider) = native_fixture();
    let selection = selected(&provider, ".");
    let session = CurrentSessionCapabilities::new(SessionCapabilities {
        workspace: Some(provider.clone()),
        ..Default::default()
    });
    session
        .register_originals(OriginalsProvider::Native(provider))
        .unwrap();
    let offer = session.select_originals(selection).unwrap();
    session.revoke_workspace();
    std::fs::write(
        temp.path().join("morphir.toml"),
        "[invalid parse would be observable",
    )
    .unwrap();
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    assert!(matches!(
        owner
            .start_offered_provider(offer, CaptureScope::Primary)
            .unwrap()
            .wait()
            .await,
        Err(ProviderCaptureError::Changed)
    ));
    assert!(!temp.path().join(".morphir/out/compile.lock").exists());
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn removed_offers_late_completion_cannot_publish_into_or_release_another_connection() {
    let (_stable_temp, stable_provider) = native_fixture();
    let host = HostModelCaptureCapacity::default();
    let stable = ModelCaptureConnection::new(host.clone());
    let id = stable
        .start_provider(
            OriginalsProvider::Native(stable_provider.clone()),
            selected(&stable_provider, "."),
            CaptureScope::Primary,
        )
        .unwrap()
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    let baseline = host.usage();
    let (_temp, provider) = native_fixture();
    let abandoned = ModelCaptureConnection::new(host.clone());
    let (hook, arrived, release) = held_provider(false);
    let pending = abandoned
        .start_provider_with(
            OriginalsProvider::Native(provider.clone()),
            selected(&provider, "."),
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    pending.session.revoke_workspace();
    assert!(matches!(
        abandoned.inspect(&id),
        Err(CaptureError::UnknownHandle)
    ));
    assert!(matches!(
        abandoned.release(&id),
        Err(CaptureError::UnknownHandle)
    ));
    assert_eq!(stable.inspect(&id).unwrap().source_byte_length(), 28);
    release.send(()).unwrap();
    assert!(matches!(
        pending.wait().await,
        Err(ProviderCaptureError::Changed)
    ));
    assert_eq!(host.usage(), baseline);
    assert_eq!(stable.inspect(&id).unwrap().source_byte_length(), 28);
    stable.release(&id).unwrap();
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

struct HoldFreshCurrent {
    calls: std::sync::atomic::AtomicUsize,
    hold: HoldProvider,
}
impl crate::commands::ui::provider::originals::LookupHooks for HoldFreshCurrent {
    fn after_current(&self) {
        if self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst) == 1 {
            self.hold.block();
        }
    }
}
#[tokio::test]
async fn cancellation_during_actual_fresh_current_keeps_work_and_witness_credit_until_exit() {
    let (_temp, provider) = native_fixture();
    let selection = selected(&provider, ".");
    let (sender, arrived) = tokio::sync::oneshot::channel();
    let (release, receiver) = mpsc::channel();
    let hooks = Arc::new(HoldFreshCurrent {
        calls: std::sync::atomic::AtomicUsize::new(0),
        hold: HoldProvider {
            before: false,
            arrived: Mutex::new(Some(sender)),
            release: Mutex::new(receiver),
        },
    });
    let provider = Arc::new(
        Arc::try_unwrap(provider)
            .ok()
            .unwrap()
            .with_originals_lookup_hooks(hooks),
    );
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let pending = owner
        .start_provider(
            OriginalsProvider::Native(provider.clone()),
            selection.clone(),
            CaptureScope::Primary,
        )
        .unwrap();
    tokio::time::timeout(Duration::from_secs(5), arrived)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(host.usage().active_workers(), 1);
    assert!(host.usage().metadata_bytes() > 0);
    drop(pending);
    owner.close(); // No connection mutex is held across actual resolution.
    assert_eq!(host.usage().active_workers(), 1);
    assert!(host.usage().metadata_bytes() > 0); // Actual witnesses remain owned.
    let other = ModelCaptureConnection::new(host.clone());
    assert!(matches!(
        other.start_provider(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary
        ),
        Err(CaptureError::Capacity)
    ));
    release.send(()).unwrap();
    effects_stopped(&host).await;
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn foreign_source_and_unknown_member_never_open_compile_storage() {
    for field in ["provider", "locator", "project"] {
        let (temp, provider) = native_fixture();
        let mut source = provider.initial_sources().pop().unwrap();
        let mut id = project_key(&source, ".");
        match field {
            "provider" => source.provider_id = "foreign-provider".into(),
            "locator" => source.locator = "workspace:foreign".into(),
            _ => id = project_key(&source, "missing-member"),
        }
        let selection = OriginalsSelection::parse(&source, &id).unwrap();
        let host = HostModelCaptureCapacity::default();
        let owner = ModelCaptureConnection::new(host.clone());
        let result = owner
            .start_provider(
                OriginalsProvider::Native(provider),
                selection,
                CaptureScope::Primary,
            )
            .unwrap()
            .wait()
            .await;
        assert!(
            matches!(result, Err(ProviderCaptureError::Authority(_))),
            "{field}: {result:?}"
        );
        assert!(!temp.path().join(".morphir/out/compile.lock").exists());
        assert_eq!(host.usage(), ModelCaptureUsage::default());
    }
}

use super::lifecycle::WorkerHooks;
use std::{
    sync::{Mutex, mpsc},
    time::Duration,
};
struct HoldProvider {
    before: bool,
    arrived: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    release: Mutex<mpsc::Receiver<()>>,
}
impl HoldProvider {
    fn block(&self) {
        self.arrived
            .lock()
            .unwrap()
            .take()
            .unwrap()
            .send(())
            .unwrap();
        self.release
            .lock()
            .unwrap()
            .recv_timeout(Duration::from_secs(10))
            .unwrap();
    }
}
impl WorkerHooks for HoldProvider {
    fn before_capture(&self) {
        if self.before {
            self.block();
        }
    }
    fn after_capture(&self) {
        if !self.before {
            self.block();
        }
    }
}
fn held_provider(
    before: bool,
) -> (
    Arc<HoldProvider>,
    tokio::sync::oneshot::Receiver<()>,
    mpsc::Sender<()>,
) {
    let (sender, arrived) = tokio::sync::oneshot::channel();
    let (release, receiver) = mpsc::channel();
    (
        Arc::new(HoldProvider {
            before,
            arrived: Mutex::new(Some(sender)),
            release: Mutex::new(receiver),
        }),
        arrived,
        release,
    )
}
async fn effects_stopped(host: &HostModelCaptureCapacity) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while host.usage().active_workers() != 0 {
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn provider_work_is_reserved_before_discovery_and_kept_after_waiter_drop() {
    let (temp, provider) = native_fixture();
    let selection = selected(&provider, ".");
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let (hook, arrived, release) = held_provider(true);
    let pending = owner
        .start_provider_with(
            OriginalsProvider::Native(provider.clone()),
            selection.clone(),
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    assert_eq!(host.usage().active_workers(), 1);
    assert_eq!(host.usage().captures(), 1);
    assert_eq!(host.usage().source_bytes(), 0);
    assert!(!temp.path().join(".morphir/out/compile.lock").exists());
    drop(pending);
    assert_eq!(host.usage().active_workers(), 1);
    let other = ModelCaptureConnection::new(host.clone());
    assert!(matches!(
        other.start_provider(
            OriginalsProvider::Native(provider.clone()),
            selection.clone(),
            CaptureScope::Primary
        ),
        Err(CaptureError::Capacity)
    ));
    release.send(()).unwrap();
    effects_stopped(&host).await;
    assert_eq!(host.usage(), ModelCaptureUsage::default());
    assert!(!temp.path().join(".morphir/out/compile.lock").exists());
    assert!(
        other
            .start_provider(
                OriginalsProvider::Native(provider),
                selection,
                CaptureScope::Primary
            )
            .unwrap()
            .wait()
            .await
            .is_ok()
    );
}

#[tokio::test]
async fn member_removal_after_private_capture_refuses_publication() {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(
        temp.path().join("morphir.toml"),
        "[workspace]\nmembers=['packages/*']\n",
    )
    .unwrap();
    let member = temp.path().join("packages/orders");
    std::fs::create_dir_all(&member).unwrap();
    std::fs::write(
        member.join("morphir.toml"),
        "[project]\nname='acme/orders'\nversion='1.0.0'\n",
    )
    .unwrap();
    let output = temp.path().join(".morphir/out/packages/orders");
    std::fs::create_dir_all(output.join("compile.dest")).unwrap();
    std::fs::write(
        output.join("compile.dest/model.json"),
        b"private member bytes",
    )
    .unwrap();
    std::fs::write(output.join("compile.json"), br#"{"schema":1,"task":"compile","module":"packages/orders","completedAt":"now","ir":{"path":"model.json","layout":"single-file","format":"json","version":"v4"}}"#).unwrap();
    let provider = Arc::new(
        NativeWorkspaceProvider::discover_with_options(
            temp.path(),
            "member-session",
            ConfigLoadOptions::project_only(),
        )
        .unwrap()
        .authorize_originals_lookup(cap_std::ambient_authority())
        .unwrap(),
    );
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let (hook, arrived, release) = held_provider(false);
    let selection = selected(&provider, "packages/orders");
    let pending = owner
        .start_provider_with(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    assert_eq!(host.usage().source_bytes(), 20);
    assert_eq!(host.usage().active_workers(), 1);
    std::fs::remove_file(member.join("morphir.toml")).unwrap();
    release.send(()).unwrap();
    let result = pending.wait().await;
    assert!(
        matches!(result, Err(ProviderCaptureError::Authority(_))),
        "{result:?}"
    );
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn replacement_output_directory_cannot_publish_the_old_private_capture() {
    let (temp, provider) = native_fixture();
    let selection = selected(&provider, ".");
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let (hook, arrived, release) = held_provider(false);
    let pending = owner
        .start_provider_with(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    let output = temp.path().join(".morphir/out");
    std::fs::rename(&output, temp.path().join(".morphir/retired")).unwrap();
    std::fs::create_dir(&output).unwrap();
    release.send(()).unwrap();
    assert!(matches!(
        pending.wait().await,
        Err(ProviderCaptureError::Changed)
    ));
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn close_after_provider_capture_holds_real_worker_credit_until_exit() {
    let (_temp, provider) = native_fixture();
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let selection = selected(&provider, ".");
    let (hook, arrived, release) = held_provider(false);
    let pending = owner
        .start_provider_with(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    assert_eq!(host.usage().source_bytes(), 28);
    owner.close();
    drop(pending);
    assert_eq!(host.usage().source_bytes(), 0);
    assert_eq!(host.usage().captures(), 0);
    assert_eq!(host.usage().active_workers(), 1);
    release.send(()).unwrap();
    effects_stopped(&host).await;
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[cfg(unix)]
#[tokio::test]
async fn configured_symlink_output_never_grants_outside_source_access() {
    let (temp, provider) = native_fixture();
    let selection = selected(&provider, ".");
    let outside = tempfile::tempdir().unwrap();
    std::fs::remove_dir_all(temp.path().join(".morphir/out")).unwrap();
    std::os::unix::fs::symlink(outside.path(), temp.path().join(".morphir/out")).unwrap();
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    assert!(matches!(
        owner
            .start_provider(
                OriginalsProvider::Native(provider),
                selection,
                CaptureScope::Primary
            )
            .unwrap()
            .wait()
            .await,
        Err(ProviderCaptureError::Authority(_))
    ));
    assert!(!outside.path().join("compile.lock").exists());
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn explicit_startup_output_override_is_the_only_extra_directory_grant() {
    let (temp, provider) = native_fixture();
    let override_root = tempfile::tempdir().unwrap();
    std::fs::create_dir(override_root.path().join("compile.dest")).unwrap();
    std::fs::write(
        override_root.path().join("compile.dest/model.json"),
        b"startup override",
    )
    .unwrap();
    std::fs::write(override_root.path().join("compile.json"), br#"{"schema":1,"task":"compile","module":"","completedAt":"now","ir":{"path":"model.json","layout":"single-file","format":"json","version":"v4"}}"#).unwrap();
    let provider = Arc::new(
        Arc::try_unwrap(provider)
            .ok()
            .unwrap()
            .with_out_overrides(crate::commands::out_context::OutOverrides {
                flag: Some(override_root.path().to_owned()),
                env: Some("ignored-env".into()),
            })
            .authorize_originals_lookup(cap_std::ambient_authority())
            .unwrap(),
    );
    let selection = selected(&provider, ".");
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    let id = owner
        .start_provider(
            OriginalsProvider::Native(provider),
            selection,
            CaptureScope::Primary,
        )
        .unwrap()
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    assert_eq!(owner.inspect(&id).unwrap().source_byte_length(), 16);
    assert!(override_root.path().join("compile.lock").exists());
    assert!(!temp.path().join(".morphir/out/compile.lock").exists());
}

#[tokio::test]
async fn missing_compile_output_cannot_fall_back_to_legacy_semantic_open() {
    let (temp, provider) = native_fixture();
    std::fs::remove_dir_all(temp.path().join(".morphir/out")).unwrap();
    std::fs::write(
        temp.path().join("morphir-ir.json"),
        b"legacy bytes must not masquerade as compiled originals",
    )
    .unwrap();
    let selection = selected(&provider, ".");
    let host = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(host.clone());
    assert_eq!(
        owner
            .start_provider(
                OriginalsProvider::Native(provider),
                selection,
                CaptureScope::Primary
            )
            .unwrap()
            .wait()
            .await
            .unwrap(),
        ModelCaptureCompletion::Unavailable(CaptureUnavailable::NotCompiled)
    );
    assert_eq!(host.usage(), ModelCaptureUsage::default());
}
