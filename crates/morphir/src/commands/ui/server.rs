//! Strict loopback HTTP boundary for the connected Morphir web app.

use std::{net::SocketAddr, sync::Arc};

use axum::{
    Router,
    body::Body,
    extract::{Path, Query, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Redirect, Response},
    routing::get,
};
use serde::Deserialize;
use tokio::net::TcpListener;

pub(in crate::commands::ui) use super::model_originals::HostPrivateRecordObserver;
use super::model_originals::{CleanupRegistry, HostCaptureCleanupOwner, PrivateRecordRegistry};
use crate::error::CliError;

enum RecordObservationBinding {
    #[cfg(test)]
    Disabled,
    Observed,
    #[cfg(test)]
    ObservedWithCaptureHook(super::model_originals::CaptureWorkerTestHook),
}
#[derive(Clone)]
pub(in crate::commands::ui) enum HostObservationBinding {
    Disabled,
    Source(super::model_originals::observation::HostSourceLease),
    Record {
        source: super::model_originals::observation::HostSourceLease,
        registry: PrivateRecordRegistry,
        cleanup: CleanupRegistry,
        #[cfg(test)]
        capture_hook: Option<super::model_originals::CaptureWorkerTestHook>,
    },
}

use super::{
    assets,
    auth::SessionAuth,
    protocol::{CONNECTED_PROTOCOL_VERSION, InitialView, SessionManifest},
    provider::SessionCapabilities,
    rpc,
};

#[derive(Clone)]
pub(crate) struct UiHostState {
    pub(crate) auth: Arc<SessionAuth>,
    pub(crate) manifest: SessionManifest,
    pub(crate) capabilities: SessionCapabilities,
    pub(crate) initial_view: Option<InitialView>,
    pub(crate) authority: String,
    pub(crate) artifact_capacity: super::artifacts::HostArtifactCapacity,
    pub(crate) original_capacity: super::model_originals::HostModelCaptureCapacity,
    pub(crate) current: super::provider::current::CurrentSessionCapabilities,
    pub(in crate::commands::ui) observation: HostObservationBinding,
}

pub struct BoundUiHost {
    listener: TcpListener,
    router: Router,
    address: SocketAddr,
    launch_token: String,
    manifest: SessionManifest,
    artifact_observer: super::artifacts::ArtifactUsageObserver,
    original_capacity: super::model_originals::HostModelCaptureCapacity,
    workspace_control: super::provider::WorkspaceSessionControl,
    record_observer: Option<HostPrivateRecordObserver>,
    capture_cleanup: Option<HostCaptureCleanupOwner>,
}

impl BoundUiHost {
    pub async fn bind(
        session_id: String,
        capabilities: SessionCapabilities,
    ) -> Result<Self, CliError> {
        Self::bind_with_originals(session_id, capabilities, None).await
    }

    pub(crate) async fn bind_with_originals(
        session_id: String,
        capabilities: SessionCapabilities,
        originals: Option<super::provider::originals::OriginalsProvider>,
    ) -> Result<Self, CliError> {
        Self::bind_configured(
            session_id,
            capabilities,
            originals,
            HostObservationBinding::Disabled,
        )
        .await
    }

    #[cfg(test)]
    pub(in crate::commands::ui) async fn bind_source_observed(
        session_id: String,
        capabilities: SessionCapabilities,
        originals: Option<super::provider::originals::OriginalsProvider>,
        scope: &super::model_originals::observation::HostSourceObservationScope,
    ) -> Result<Self, CliError> {
        Self::bind_observed(
            session_id,
            capabilities,
            originals,
            scope,
            RecordObservationBinding::Disabled,
        )
        .await
    }
    pub(in crate::commands::ui) async fn bind_record_observed(
        session_id: String,
        capabilities: SessionCapabilities,
        originals: Option<super::provider::originals::OriginalsProvider>,
        scope: &super::model_originals::observation::HostSourceObservationScope,
    ) -> Result<(Self, HostPrivateRecordObserver), CliError> {
        let host = Self::bind_observed(
            session_id,
            capabilities,
            originals,
            scope,
            RecordObservationBinding::Observed,
        )
        .await?;
        let observer = host
            .record_observer
            .clone()
            .expect("observed binding issues observer");
        Ok((host, observer))
    }
    #[cfg(test)]
    pub(in crate::commands::ui) async fn bind_record_observed_with_capture_hook(
        session_id: String,
        capabilities: SessionCapabilities,
        originals: Option<super::provider::originals::OriginalsProvider>,
        scope: &super::model_originals::observation::HostSourceObservationScope,
        hook: super::model_originals::CaptureWorkerTestHook,
    ) -> Result<(Self, HostPrivateRecordObserver), CliError> {
        let host = Self::bind_observed(
            session_id,
            capabilities,
            originals,
            scope,
            RecordObservationBinding::ObservedWithCaptureHook(hook),
        )
        .await?;
        let observer = host
            .record_observer
            .clone()
            .expect("observed binding issues observer");
        Ok((host, observer))
    }

    async fn bind_observed(
        session_id: String,
        capabilities: SessionCapabilities,
        originals: Option<super::provider::originals::OriginalsProvider>,
        scope: &super::model_originals::observation::HostSourceObservationScope,
        records: RecordObservationBinding,
    ) -> Result<Self, CliError> {
        let source = scope.lease();
        let expected = source.identity();
        let identities = [
            capabilities
                .workspace
                .as_ref()
                .and_then(|provider| provider.source_observation_identity()),
            capabilities
                .playground
                .as_ref()
                .and_then(|provider| provider.source_observation_identity()),
        ];
        for identity in identities {
            match identity {
                Some(actual) if !actual.matches(&expected) => {
                    return Err(super::protocol::protocol_error(
                        super::model_originals::observation::HostObservationError::ForeignScope
                            .to_string(),
                    ));
                }
                None => source.mark_incomplete(),
                Some(_) => {}
            }
        }
        if let Some(originals) = &originals {
            match originals.workspace().source_observation_identity() {
                Some(actual) if !actual.matches(&expected) => {
                    return Err(super::protocol::protocol_error(
                        super::model_originals::observation::HostObservationError::ForeignScope
                            .to_string(),
                    ));
                }
                None => source.mark_incomplete(),
                Some(_) => {}
            }
        }
        let observation = match records {
            #[cfg(test)]
            RecordObservationBinding::Disabled => HostObservationBinding::Source(source.clone()),
            RecordObservationBinding::Observed => HostObservationBinding::Record {
                source: source.clone(),
                registry: PrivateRecordRegistry::new(),
                cleanup: CleanupRegistry::new(),
                #[cfg(test)]
                capture_hook: None,
            },
            #[cfg(test)]
            RecordObservationBinding::ObservedWithCaptureHook(hook) => {
                HostObservationBinding::Record {
                    source: source.clone(),
                    registry: PrivateRecordRegistry::new(),
                    cleanup: CleanupRegistry::new(),
                    capture_hook: Some(hook),
                }
            }
        };
        let host = Self::bind_configured(session_id, capabilities, originals, observation).await?;
        source.bound();
        Ok(host)
    }

    async fn bind_configured(
        session_id: String,
        capabilities: SessionCapabilities,
        originals: Option<super::provider::originals::OriginalsProvider>,
        observation: HostObservationBinding,
    ) -> Result<Self, CliError> {
        let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
            .await
            .map_err(CliError::from)?;
        let address = listener.local_addr().map_err(CliError::from)?;
        if address.ip() != std::net::IpAddr::V4(std::net::Ipv4Addr::LOCALHOST) {
            return Err(CliError::Validation {
                message: format!("UI host refused non-loopback bind address {address}"),
            });
        }
        let (auth, launch_token) = SessionAuth::generate(&session_id)?;
        let mut providers = Vec::new();
        let mut initial_sources = Vec::new();
        if let Some(workspace) = &capabilities.workspace {
            providers.push(workspace.manifest());
            initial_sources.extend(workspace.initial_sources());
        }
        if let Some(playground) = &capabilities.playground {
            providers.push(playground.manifest());
        }
        if providers.is_empty() {
            return Err(CliError::Validation {
                message: "A Morphir UI session requires at least one capability".into(),
            });
        }
        let current =
            super::provider::current::CurrentSessionCapabilities::new(capabilities.clone());
        if let Some(provider) = originals {
            let id = provider.workspace().manifest().id;
            current.register_originals(provider)?;
            let offered = providers
                .iter_mut()
                .find(|provider| provider.id == id)
                .ok_or_else(|| {
                    super::protocol::protocol_error("Original-source provider was not offered")
                })?;
            offered
                .capabilities
                .push(super::protocol::WorkbenchCapability {
                    name: super::model_originals::wire::PROFILE.into(),
                    version: super::model_originals::CONTRACT_VERSION.into(),
                });
        }
        let manifest = SessionManifest {
            protocol_version: CONNECTED_PROTOCOL_VERSION,
            web_socket_path: "/rpc".into(),
            session_id,
            providers,
            initial_sources,
        }
        .validate()?;
        let initial_view = capabilities.initial_view;
        let manifest_copy = manifest.clone();
        let artifact_capacity = super::artifacts::HostArtifactCapacity::default();
        let artifact_observer = artifact_capacity.observer();
        let original_capacity = super::model_originals::HostModelCaptureCapacity::default();
        let record_observer = match &observation {
            HostObservationBinding::Record { registry, .. } => Some(registry.observer()),
            HostObservationBinding::Disabled | HostObservationBinding::Source(_) => None,
        };
        let capture_cleanup = match &observation {
            HostObservationBinding::Record { cleanup, .. } => Some(cleanup.control()),
            HostObservationBinding::Disabled | HostObservationBinding::Source(_) => None,
        };
        let workspace_control = current.workspace_control();
        let state = UiHostState {
            auth: Arc::new(auth),
            manifest,
            capabilities,
            initial_view,
            authority: address.to_string(),
            artifact_capacity,
            original_capacity: original_capacity.clone(),
            current,
            observation,
        };
        let router = Router::new()
            .route("/launch", get(exchange_launch_token))
            .route("/api/session", get(session_manifest))
            .route("/rpc", get(rpc::upgrade))
            .route("/", get(index))
            .route("/{*asset}", get(static_asset))
            .with_state(state);
        Ok(Self {
            listener,
            router,
            address,
            launch_token,
            manifest: manifest_copy,
            artifact_observer,
            original_capacity,
            workspace_control,
            record_observer,
            capture_cleanup,
        })
    }

    pub fn address(&self) -> SocketAddr {
        self.address
    }
    /// The actual host owner takes this once before consuming the host in serve.
    /// Dropping the listener is not a proof of upgraded-socket task completion.
    pub(in crate::commands::ui) fn take_capture_cleanup(
        &mut self,
    ) -> Result<HostCaptureCleanupOwner, super::model_originals::CaptureError> {
        self.capture_cleanup
            .take()
            .ok_or(super::model_originals::CaptureError::UnknownHandle)
    }

    pub fn manifest(&self) -> &SessionManifest {
        &self.manifest
    }

    /// Issue a control for the same live workspace registration before serving
    /// consumes this host. Requests cannot construct or obtain this handle.
    pub fn workspace_control(&self) -> super::provider::WorkspaceSessionControl {
        self.workspace_control.clone()
    }

    /// Read-only measurements for local host owners and qualification adapters.
    /// This observer grants neither handles nor generation/publication authority.
    pub fn artifact_observer(&self) -> super::artifacts::ArtifactUsageObserver {
        self.artifact_observer.clone()
    }

    /// Shared resource measurements. This grants no capture or provider authority.
    pub fn model_originals_usage(&self) -> super::model_originals::ModelCaptureUsage {
        self.original_capacity.usage()
    }

    pub fn model_originals_observer(&self) -> super::model_originals::ModelCaptureUsageObserver {
        self.original_capacity.observer()
    }

    pub fn base_url(&self) -> String {
        format!("http://{}", self.address)
    }

    pub fn launch_url(&self) -> String {
        format!("{}/launch?token={}", self.base_url(), self.launch_token)
    }

    pub async fn serve(self) -> Result<(), CliError> {
        axum::serve(self.listener, self.router)
            .await
            .map_err(CliError::from)
    }

    #[cfg(test)]
    pub(crate) fn into_parts(self) -> (TcpListener, Router) {
        (self.listener, self.router)
    }
}

#[derive(Deserialize)]
struct LaunchQuery {
    token: String,
}

async fn exchange_launch_token(
    State(state): State<UiHostState>,
    Query(query): Query<LaunchQuery>,
) -> Response {
    if !state.auth.exchange_launch_token(&query.token) {
        return unauthorized();
    }
    let target = state
        .initial_view
        .map_or_else(|| "/".to_owned(), |view| format!("/{}", view.hash()));
    let mut response = Redirect::to(&target).into_response();
    response.headers_mut().insert(
        header::SET_COOKIE,
        HeaderValue::from_str(&state.auth.session_cookie())
            .expect("generated session cookies contain visible ASCII"),
    );
    secure_headers(response.headers_mut());
    response
}

async fn session_manifest(State(state): State<UiHostState>, headers: HeaderMap) -> Response {
    if !authenticated(&state, &headers) {
        return unauthorized();
    }
    let mut response = axum::Json(state.manifest).into_response();
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    secure_headers(response.headers_mut());
    response
}

async fn index(State(state): State<UiHostState>, headers: HeaderMap) -> Response {
    serve_asset(&state, &headers, "index.html")
}

async fn static_asset(
    State(state): State<UiHostState>,
    headers: HeaderMap,
    Path(path): Path<String>,
) -> Response {
    serve_asset(&state, &headers, &path)
}

fn serve_asset(state: &UiHostState, headers: &HeaderMap, path: &str) -> Response {
    if !authenticated(state, headers) {
        return unauthorized();
    }
    let Some(asset) = assets::asset(path) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let mut response = Response::new(Body::from(asset.bytes));
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static(asset.content_type),
    );
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static(if asset.immutable {
            "public, max-age=31536000, immutable"
        } else {
            "no-cache"
        }),
    );
    secure_headers(response.headers_mut());
    response
}

pub(crate) fn authenticated(state: &UiHostState, headers: &HeaderMap) -> bool {
    headers
        .get(header::COOKIE)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|cookie| state.auth.authenticate_cookie_header(cookie))
}

pub(crate) fn unauthorized() -> Response {
    let mut response = StatusCode::UNAUTHORIZED.into_response();
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    secure_headers(response.headers_mut());
    response
}

fn secure_headers(headers: &mut HeaderMap) {
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        header::REFERRER_POLICY,
        HeaderValue::from_static("no-referrer"),
    );
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::commands::ui::protocol::{
        InspectResult, PlaygroundCatalog, PlaygroundCompileParams, PlaygroundCompileResult,
        PlaygroundGenerateParams, PlaygroundGenerateResult, ProjectModelOpenResult, ProviderKind,
        ProviderManifest, ProviderStatus, WorkbenchSourceRef, WorkspaceSnapshot,
    };
    use crate::commands::ui::provider::{
        PlaygroundCapability, WorkspaceCapability, native::NativeWorkspaceProvider,
    };

    fn fixture() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../ecosystem/morphir-rust/tests/fixtures/workspace-discovery/valid-monorepo")
    }

    pub(crate) struct StubWorkspace;

    #[async_trait::async_trait]
    impl WorkspaceCapability for StubWorkspace {
        fn manifest(&self) -> ProviderManifest {
            ProviderManifest {
                id: "workspace".into(),
                name: "Stub Workspace".into(),
                kind: ProviderKind::Connected,
                status: ProviderStatus::Available,
                capabilities: Vec::new(),
                provenance: None,
            }
        }

        fn initial_sources(&self) -> Vec<WorkbenchSourceRef> {
            Vec::new()
        }

        async fn inspect(&self, _source: &WorkbenchSourceRef) -> Result<InspectResult, CliError> {
            Err(CliError::Validation {
                message: "StubWorkspace does not implement inspect".into(),
            })
        }

        async fn open(&self, _source: &WorkbenchSourceRef) -> Result<WorkspaceSnapshot, CliError> {
            Err(CliError::Validation {
                message: "StubWorkspace does not implement open".into(),
            })
        }

        async fn load_project_model(
            &self,
            _source: &WorkbenchSourceRef,
            _project_id: &str,
        ) -> Result<ProjectModelOpenResult, CliError> {
            Err(CliError::Validation {
                message: "StubWorkspace does not implement load_project_model".into(),
            })
        }
    }

    pub(crate) struct StubPlayground;

    #[async_trait::async_trait]
    impl PlaygroundCapability for StubPlayground {
        fn manifest(&self) -> ProviderManifest {
            ProviderManifest {
                id: "playground".into(),
                name: "Stub Playground".into(),
                kind: ProviderKind::Connected,
                status: ProviderStatus::Available,
                capabilities: Vec::new(),
                provenance: None,
            }
        }

        async fn catalog(&self) -> Result<PlaygroundCatalog, CliError> {
            Ok(PlaygroundCatalog::default())
        }

        async fn compile(
            &self,
            _params: PlaygroundCompileParams,
        ) -> Result<PlaygroundCompileResult, CliError> {
            Ok(PlaygroundCompileResult {
                success: true,
                ir_version: None,
                ir: None,
                diagnostics: Vec::new(),
                modules: Vec::new(),
            })
        }

        async fn generate(
            &self,
            _params: PlaygroundGenerateParams,
        ) -> Result<PlaygroundGenerateResult, CliError> {
            Ok(PlaygroundGenerateResult {
                success: true,
                artifacts: Vec::new(),
                diagnostics: Vec::new(),
            })
        }
    }

    #[tokio::test]
    async fn a_manifest_lists_only_the_capabilities_present() {
        let host = BoundUiHost::bind(
            "test-session".into(),
            SessionCapabilities {
                playground: Some(Arc::new(StubPlayground)),
                ..Default::default()
            },
        )
        .await
        .unwrap();

        let manifest = host.manifest();

        assert_eq!(manifest.providers.len(), 1);
        assert_eq!(manifest.providers[0].id, "playground");
        assert!(manifest.initial_sources.is_empty());
    }

    #[tokio::test]
    async fn a_session_with_both_capabilities_lists_both_providers() {
        let host = BoundUiHost::bind(
            "test-session".into(),
            SessionCapabilities {
                workspace: Some(Arc::new(StubWorkspace)),
                playground: Some(Arc::new(StubPlayground)),
                ..Default::default()
            },
        )
        .await
        .unwrap();

        let ids: Vec<&str> = host
            .manifest()
            .providers
            .iter()
            .map(|p| p.id.as_str())
            .collect();

        assert!(ids.contains(&"playground"));
        assert_eq!(ids.len(), 2);
    }

    #[tokio::test]
    async fn binding_with_no_capabilities_is_rejected() {
        let error =
            match BoundUiHost::bind("test-session".into(), SessionCapabilities::default()).await {
                Ok(_) => panic!("binding with no capabilities should be rejected"),
                Err(error) => error,
            };

        assert!(
            error.to_string().contains("at least one capability"),
            "unexpected error: {error}"
        );
    }

    #[tokio::test]
    async fn launch_redirects_to_root_with_no_initial_view() {
        let host = BoundUiHost::bind(
            "test-session".into(),
            SessionCapabilities {
                workspace: Some(Arc::new(StubWorkspace)),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        let launch_url = host.launch_url();
        let (listener, router) = host.into_parts();
        let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();

        let exchanged = client.get(&launch_url).send().await.unwrap();

        assert_eq!(exchanged.status(), StatusCode::SEE_OTHER);
        assert_eq!(exchanged.headers()[header::LOCATION], "/");

        server.abort();
    }

    #[tokio::test]
    async fn launch_redirects_to_the_initial_view_hash_when_one_is_set() {
        let host = BoundUiHost::bind(
            "test-session".into(),
            SessionCapabilities {
                workspace: Some(Arc::new(StubWorkspace)),
                initial_view: Some(InitialView::Playground),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        let launch_url = host.launch_url();
        let (listener, router) = host.into_parts();
        let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();

        let exchanged = client.get(&launch_url).send().await.unwrap();

        assert_eq!(exchanged.status(), StatusCode::SEE_OTHER);
        assert_eq!(exchanged.headers()[header::LOCATION], "/#/playground");

        server.abort();
    }

    #[tokio::test]
    async fn binds_only_ipv4_loopback_and_exchanges_launch_auth_once() {
        let provider = Arc::new(
            NativeWorkspaceProvider::discover(&fixture(), "session-1")
                .expect("fixture should discover"),
        );
        let host = BoundUiHost::bind(
            "session-1".into(),
            SessionCapabilities {
                workspace: Some(provider),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        assert_eq!(host.address().ip(), std::net::Ipv4Addr::LOCALHOST);
        let launch_url = host.launch_url();
        let base_url = host.base_url();
        let (listener, router) = host.into_parts();
        let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();

        assert_eq!(
            client
                .get(format!("{base_url}/"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            client
                .get(format!("{base_url}/launch?token=wrong"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
        let exchanged = client.get(&launch_url).send().await.unwrap();
        assert_eq!(exchanged.status(), StatusCode::SEE_OTHER);
        let cookie = exchanged
            .headers()
            .get(header::SET_COOKIE)
            .unwrap()
            .to_str()
            .unwrap()
            .to_owned();
        assert!(cookie.contains("HttpOnly; SameSite=Strict; Path=/"));
        assert_eq!(
            client.get(&launch_url).send().await.unwrap().status(),
            StatusCode::UNAUTHORIZED
        );
        let cookie_pair = cookie.split(';').next().unwrap();
        let manifest = client
            .get(format!("{base_url}/api/session"))
            .header(header::COOKIE, cookie_pair)
            .send()
            .await
            .unwrap();
        assert_eq!(manifest.status(), StatusCode::OK);
        assert_eq!(manifest.headers()[header::CACHE_CONTROL], "no-store");

        server.abort();
    }

    #[tokio::test]
    async fn concurrent_hosts_accept_distinct_session_cookies() {
        let first = BoundUiHost::bind(
            "session-1".into(),
            SessionCapabilities {
                workspace: Some(Arc::new(
                    NativeWorkspaceProvider::discover(&fixture(), "session-1").unwrap(),
                )),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        let second = BoundUiHost::bind(
            "session-2".into(),
            SessionCapabilities {
                workspace: Some(Arc::new(
                    NativeWorkspaceProvider::discover(&fixture(), "session-2").unwrap(),
                )),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        let launches = [first.launch_url(), second.launch_url()];
        let bases = [first.base_url(), second.base_url()];
        let (first_listener, first_router) = first.into_parts();
        let (second_listener, second_router) = second.into_parts();
        let first_task =
            tokio::spawn(async move { axum::serve(first_listener, first_router).await.unwrap() });
        let second_task =
            tokio::spawn(async move { axum::serve(second_listener, second_router).await.unwrap() });
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();

        let mut pairs = Vec::new();
        for launch in launches {
            let response = client.get(launch).send().await.unwrap();
            pairs.push(
                response.headers()[header::SET_COOKIE]
                    .to_str()
                    .unwrap()
                    .split(';')
                    .next()
                    .unwrap()
                    .to_owned(),
            );
        }
        assert_ne!(pairs[0].split('=').next(), pairs[1].split('=').next());

        let combined = pairs.join("; ");
        for base in bases {
            assert_eq!(
                client
                    .get(format!("{base}/api/session"))
                    .header(header::COOKIE, &combined)
                    .send()
                    .await
                    .unwrap()
                    .status(),
                StatusCode::OK,
            );
        }

        first_task.abort();
        second_task.abort();
    }
}
