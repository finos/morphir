//! Source-selected literal client stimulus over the ordinary authenticated host
//! transport. No provider, server implementation or client qualification claim.
mod assets;
#[cfg(test)]
#[path = "controlled_originals/end_tests.rs"]
mod end_tests;
mod ingress;
use super::*;
use crate::commands::ui::{
    auth::PrepaidAuthFault,
    socket_tasks::{
        FixedSocketSetupFault, HostSocketCleanupOwner, SocketCleanupError, SocketDrainOutcome,
        SocketTaskRegistry,
    },
};
use axum::extract::{
    WebSocketUpgrade,
    ws::{Message, WebSocket},
};
use futures_util::StreamExt as _;
use morphir_mck::workbench::{
    BrowserInputError, BrowserLoans, ControlledHostDelivery, ControlledHostStimulus,
};
use std::{alloc::Layout, fmt::Write as _, future::Future, pin::Pin, sync::Mutex, time::Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum ControlledHostFault {
    Source,
    End,
    PeerRequest,
    PeerRead,
    PeerWrite,
    PeerShape,
    DeliveryTaken,
    Poisoned,
    Listener,
    Socket(SocketCleanupError),
    Document(ingress::DocumentIngressFault),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum ControlledHostShutdown {
    Joined,
    JoinedWithFault(ControlledHostFault),
    Pending { first: Option<ControlledHostFault> },
}
#[derive(Debug)]
pub(in crate::commands::ui) enum ControlledHostSetupFault {
    End,
    Funding(BrowserInputError),
    Auth(PrepaidAuthFault),
    SizeOverflow,
    Allocation(std::collections::TryReserveError),
    Io(std::io::Error),
    Header(axum::http::header::InvalidHeaderValue),
    Capacity(super::super::model_originals::MetadataOnlyCapacityFault),
    Registry(FixedSocketSetupFault),
    Source,
    DocumentLimits,
}
type ServeFuture = Pin<Box<dyn Future<Output = Result<(), CliError>> + Send>>;
enum ListenerOwner {
    Bound(ServeFuture),
    Running {
        actual: tokio::task::JoinHandle<Result<(), CliError>>,
        stop_requested: bool,
    },
    Joined(Result<Result<(), CliError>, tokio::task::JoinError>),
    Unserved,
}
enum ActualPeerFault {
    Read(axum::Error),
    Write(axum::Error),
}
enum LaunchDestination {
    ControlledRoot,
    ObservedDocument,
}
impl LaunchDestination {
    fn header(&self) -> HeaderValue {
        match self {
            Self::ControlledRoot => HeaderValue::from_static("/"),
            Self::ObservedDocument => {
                HeaderValue::from_static("/observed/?mode=connected-originals")
            }
        }
    }
}
struct HostState {
    auth: SessionAuth,
    cookie: HeaderValue,
    authority: String,
    origin: String,
    launch_destination: LaunchDestination,
    source: Arc<ControlledHostStimulus>,
    delivery: Mutex<ControlledHostDelivery>,
    tasks: SocketTaskRegistry,
    end: Instant,
    first: Mutex<Option<ControlledHostFault>>,
    actual_peer: Mutex<Option<ActualPeerFault>>,
    assets: Option<assets::HostAssets>,
    document: Option<ingress::DocumentIngress>,
}
impl HostState {
    fn fault(&self, cause: ControlledHostFault) {
        match self.first.lock() {
            Ok(mut first) => {
                first.get_or_insert(cause);
            }
            Err(poison) => {
                poison
                    .into_inner()
                    .get_or_insert(ControlledHostFault::Poisoned);
            }
        }
    }
    fn first(&self) -> Option<ControlledHostFault> {
        match self.first.lock() {
            Ok(first) => *first,
            Err(poison) => {
                let mut first = poison.into_inner();
                first.get_or_insert(ControlledHostFault::Poisoned);
                *first
            }
        }
    }
    fn admission(&self) -> Result<(), ControlledHostFault> {
        if Instant::now() >= self.end {
            return Err(ControlledHostFault::End);
        }
        self.source.admit().map_err(|_| ControlledHostFault::Source)
    }
    fn authenticated(&self, headers: &HeaderMap) -> bool {
        headers
            .get(header::COOKIE)
            .and_then(|v| v.to_str().ok())
            .is_some_and(|v| self.auth.authenticate_cookie_header(v))
    }
}
pub(in crate::commands::ui) struct BoundControlledUiHost {
    listener: ListenerOwner,
    state: Arc<HostState>,
    cleanup: HostSocketCleanupOwner,
    address: SocketAddr,
    base: String,
    launch: String,
    document_decoder: Option<morphir_mck::workbench::BrowserDocumentDecoder>,
}
fn arc_layout<T>() -> Result<Layout, ControlledHostSetupFault> {
    let count = Layout::new::<std::sync::atomic::AtomicUsize>();
    Ok(count
        .extend(count)
        .and_then(|(header, _)| header.extend(Layout::new::<T>()))
        .map_err(|_| ControlledHostSetupFault::SizeOverflow)?
        .0
        .pad_to_align())
}
fn reserve(
    loans: &mut BrowserLoans<'_, '_>,
    bytes: usize,
    slots: usize,
    work: usize,
) -> Result<(), ControlledHostSetupFault> {
    loans
        .reserve_controlled_host_storage(bytes, slots, work)
        .map_err(ControlledHostSetupFault::Funding)
}
fn buffer(loans: &mut BrowserLoans<'_, '_>, n: usize) -> Result<String, ControlledHostSetupFault> {
    reserve(loans, n, 1, n)?;
    let mut text = String::new();
    text.try_reserve_exact(n)
        .map_err(ControlledHostSetupFault::Allocation)?;
    reserve(
        loans,
        text.capacity()
            .checked_sub(n)
            .ok_or(ControlledHostSetupFault::SizeOverflow)?,
        0,
        0,
    )?;
    Ok(text)
}
impl BoundControlledUiHost {
    pub(in crate::commands::ui) async fn bind(
        stimulus: ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
        end: Instant,
    ) -> Result<Self, ControlledHostSetupFault> {
        Self::bind_inner(stimulus, None, None, 2, loans, end).await
    }
    async fn bind_inner(
        stimulus: ControlledHostStimulus,
        assets: Option<assets::HostAssets>,
        document: Option<ingress::DocumentIngress>,
        socket_tasks: usize,
        loans: &mut BrowserLoans<'_, '_>,
        end: Instant,
    ) -> Result<Self, ControlledHostSetupFault> {
        reserve(loans, 0, 0, 0)?;
        stimulus
            .admit()
            .map_err(|_| ControlledHostSetupFault::Source)?;
        if Instant::now() >= end {
            return Err(ControlledHostSetupFault::End);
        }
        let delivery = stimulus
            .prepare_delivery(loans)
            .map_err(ControlledHostSetupFault::Funding)?;
        // Two concrete concurrently retained roles: HTTP driver and its upgrade.
        // This is a fixed admission table, not a new normative concurrency grant.
        let metadata = SocketTaskRegistry::fixed_requested_bytes(socket_tasks)
            .map_err(|e| ControlledHostSetupFault::Registry(FixedSocketSetupFault::Registry(e)))?;
        let capacity =
            super::super::model_originals::HostModelCaptureCapacity::metadata_only(loans, metadata)
                .map_err(ControlledHostSetupFault::Capacity)?;
        let (tasks, cleanup) = SocketTaskRegistry::new_fixed(&capacity, socket_tasks, loans)
            .map_err(ControlledHostSetupFault::Registry)?;
        let (auth, token, cookie) =
            SessionAuth::generate_prepaid(loans, "model-originals-controlled")
                .map_err(ControlledHostSetupFault::Auth)?
                .into_parts();
        // bytes 1.12.1 Shared consists of pointer, capacity and AtomicUsize.
        // Prepay that possible Vec->Bytes/first-clone owner for each transferred
        // literal and the cookie. No allocator/RSS bound is asserted.
        let shared = Layout::new::<*mut u8>()
            .extend(Layout::new::<usize>())
            .and_then(|(l, _)| l.extend(Layout::new::<std::sync::atomic::AtomicUsize>()))
            .map_err(|_| ControlledHostSetupFault::SizeOverflow)?
            .0
            .pad_to_align()
            .size();
        let count = stimulus
            .frames()
            .len()
            .checked_add(2)
            .ok_or(ControlledHostSetupFault::SizeOverflow)?;
        let owners = shared
            .checked_mul(count)
            .ok_or(ControlledHostSetupFault::SizeOverflow)?;
        let state_bytes = arc_layout::<HostState>()?
            .size()
            .checked_add(arc_layout::<ControlledHostStimulus>()?.size())
            .and_then(|n| n.checked_add(std::mem::size_of::<Self>()))
            .and_then(|n| n.checked_add(owners))
            .ok_or(ControlledHostSetupFault::SizeOverflow)?;
        reserve(loans, state_bytes, 2, cookie.len())?;
        let cookie = HeaderValue::from_maybe_shared(axum::body::Bytes::from(cookie.into_bytes()))
            .map_err(ControlledHostSetupFault::Header)?;
        let mut authority = buffer(loans, 15)?;
        let mut origin = buffer(loans, 22)?;
        let mut base = buffer(loans, 22)?;
        let mut launch = buffer(loans, 22 + 14 + token.len())?;
        fn future_size<F>(
            _: impl FnOnce(
                TcpListener,
                Router,
                SocketTaskRegistry,
                Option<(Arc<ControlledHostStimulus>, Instant)>,
            ) -> F,
        ) -> usize {
            std::mem::size_of::<F>()
        }
        reserve(
            loans,
            future_size(super::serve_connections_with_source::<TcpListener>),
            1,
            0,
        )?;
        // All our fixed backing permission above precedes binding. Framework route/task/IO
        // internals remain a separate integration obligation, not an RSS claim.
        let listener = source_polled(
            &stimulus,
            end,
            TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0)),
        )
        .await
        .map_err(|fault| match fault {
            SourcePollFault::End => ControlledHostSetupFault::End,
            SourcePollFault::Source => ControlledHostSetupFault::Source,
        })?
        .map_err(ControlledHostSetupFault::Io)?;
        let address = listener
            .local_addr()
            .map_err(ControlledHostSetupFault::Io)?;
        write!(&mut authority, "{address}").map_err(|_| ControlledHostSetupFault::SizeOverflow)?;
        origin.push_str("http://");
        origin.push_str(&authority);
        base.push_str(&origin);
        launch.push_str(&base);
        launch.push_str("/launch?token=");
        launch.push_str(&token);
        let launch_destination = match (&assets, &document) {
            (Some(_), Some(_)) => LaunchDestination::ObservedDocument,
            _ => LaunchDestination::ControlledRoot,
        };
        let source = Arc::new(stimulus);
        let state = Arc::new(HostState {
            auth,
            cookie,
            authority,
            origin,
            launch_destination,
            source: source.clone(),
            delivery: Mutex::new(delivery),
            tasks: tasks.clone(),
            end,
            first: Mutex::new(None),
            actual_peer: Mutex::new(None),
            assets,
            document,
        });
        let router = Router::new()
            .route("/launch", get(launch_route))
            .route("/api/session", get(manifest_route))
            .route("/rpc", get(upgrade_route))
            .route("/observed/", get(asset_route))
            .route("/observed/{*path}", get(asset_route))
            .route(
                "/_mck/document",
                get(ingress::upgrade_route)
                    .post(ingress::bootstrap_route)
                    .layer(axum::extract::DefaultBodyLimit::max(0)),
            )
            .with_state(state.clone());
        let future =
            super::serve_connections_with_source(listener, router, tasks, Some((source, end)));
        Ok(Self {
            listener: ListenerOwner::Bound(Box::pin(future)),
            state,
            cleanup,
            address,
            base,
            launch,
            document_decoder: None,
        })
    }
    pub(in crate::commands::ui) fn address(&self) -> SocketAddr {
        self.address
    }
    pub(in crate::commands::ui) fn base_url(&self) -> &str {
        &self.base
    }
    pub(in crate::commands::ui) fn launch_url(&self) -> &str {
        &self.launch
    }
    pub(in crate::commands::ui) fn start(&mut self) -> Result<(), ControlledHostFault> {
        self.state.admission()?;
        let runtime =
            tokio::runtime::Handle::try_current().map_err(|_| ControlledHostFault::Listener)?;
        // Gate is held through the actual synchronous spawn installation.
        self.state
            .source
            .while_source_active(|| {
                if Instant::now() >= self.state.end {
                    return Err(ControlledHostFault::End);
                }
                if matches!(self.listener, ListenerOwner::Bound(_)) {
                    let ListenerOwner::Bound(future) =
                        std::mem::replace(&mut self.listener, ListenerOwner::Unserved)
                    else {
                        unreachable!()
                    };
                    self.listener = ListenerOwner::Running {
                        actual: runtime.spawn(future),
                        stop_requested: false,
                    };
                    Ok(())
                } else {
                    Err(ControlledHostFault::Listener)
                }
            })
            .map_err(|_| ControlledHostFault::Source)?
    }
    pub(in crate::commands::ui) async fn shutdown(&mut self) -> ControlledHostShutdown {
        self.cleanup.stop_accepting_upgrades();
        if matches!(self.listener, ListenerOwner::Bound(_)) {
            self.listener = ListenerOwner::Unserved;
        }
        if let ListenerOwner::Running {
            actual,
            stop_requested,
        } = &mut self.listener
        {
            if !actual.is_finished() {
                *stop_requested = true;
                actual.abort();
            }
            let requested = *stop_requested;
            match tokio::time::timeout_at(self.state.end.into(), &mut *actual).await {
                Ok(result) => {
                    let healthy = matches!(&result, Ok(Ok(())))
                        || requested && matches!(&result,Err(error) if error.is_cancelled());
                    if !healthy {
                        self.state.fault(ControlledHostFault::Listener);
                    }
                    self.listener = ListenerOwner::Joined(result);
                }
                Err(_) => {
                    return ControlledHostShutdown::Pending {
                        first: self.state.first(),
                    };
                }
            }
        }
        match self.cleanup.drain(self.state.end.into()).await {
            SocketDrainOutcome::Pending { first_fault } => {
                if let Some(fault) = first_fault {
                    self.state.fault(ControlledHostFault::Socket(fault));
                }
                ControlledHostShutdown::Pending {
                    first: self.state.first(),
                }
            }
            SocketDrainOutcome::JoinedWithFault(fault) => {
                self.state.fault(ControlledHostFault::Socket(fault));
                ControlledHostShutdown::JoinedWithFault(
                    self.state
                        .first()
                        .unwrap_or(ControlledHostFault::Socket(fault)),
                )
            }
            SocketDrainOutcome::Joined => match self.state.first() {
                Some(fault) => ControlledHostShutdown::JoinedWithFault(fault),
                None => ControlledHostShutdown::Joined,
            },
        }
    }
}
async fn asset_route(
    State(state): State<Arc<HostState>>,
    headers: HeaderMap,
    uri: axum::http::Uri,
) -> Response {
    if !state.authenticated(&headers) {
        return unauthorized();
    }
    state
        .source
        .while_source_active(|| {
            if Instant::now() >= state.end {
                return StatusCode::SERVICE_UNAVAILABLE.into_response();
            }
            match &state.assets {
                Some(assets) => assets
                    .response(uri.path())
                    .unwrap_or_else(assets::AssetRouteFault::response),
                None => StatusCode::SERVICE_UNAVAILABLE.into_response(),
            }
        })
        .unwrap_or_else(|_| StatusCode::SERVICE_UNAVAILABLE.into_response())
}
impl Drop for BoundControlledUiHost {
    fn drop(&mut self) {
        if let ListenerOwner::Running { actual, .. } = &self.listener {
            actual.abort();
        }
    }
}
async fn launch_route(
    State(state): State<Arc<HostState>>,
    Query(query): Query<LaunchQuery>,
) -> Response {
    state
        .source
        .while_source_active(|| {
            if Instant::now() >= state.end {
                return StatusCode::SERVICE_UNAVAILABLE.into_response();
            }
            if !state.auth.exchange_launch_token(&query.token) {
                return unauthorized();
            }
            // Both destinations are closed static headers. This avoids a new
            // per-request String owner while preserving the actual 303 exchange.
            let mut response = (
                StatusCode::SEE_OTHER,
                [(header::LOCATION, state.launch_destination.header())],
            )
                .into_response();
            response
                .headers_mut()
                .insert(header::SET_COOKIE, state.cookie.clone());
            secure_headers(response.headers_mut());
            response
        })
        .unwrap_or_else(|_| StatusCode::SERVICE_UNAVAILABLE.into_response())
}
async fn manifest_route(State(state): State<Arc<HostState>>, headers: HeaderMap) -> Response {
    if !state.authenticated(&headers) {
        return unauthorized();
    }
    let result = state.source.while_source_active(|| {
        if Instant::now() >= state.end {
            return Err(ControlledHostFault::End);
        }
        let mut delivery = state
            .delivery
            .lock()
            .map_err(|_| ControlledHostFault::Poisoned)?;
        let (status, body) = delivery
            .take_manifest()
            .map_err(|_| ControlledHostFault::DeliveryTaken)?
            .into_http_input();
        let status = u16::try_from(status)
            .ok()
            .and_then(|s| StatusCode::from_u16(s).ok())
            .ok_or(ControlledHostFault::PeerShape)?;
        let mut response = Response::new(Body::from(body));
        *response.status_mut() = status;
        response.headers_mut().insert(
            header::CONTENT_TYPE,
            HeaderValue::from_static("application/json"),
        );
        response
            .headers_mut()
            .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
        secure_headers(response.headers_mut());
        Ok(response)
    });
    match result {
        Ok(Ok(response)) => response,
        Ok(Err(fault)) => {
            state.fault(fault);
            StatusCode::SERVICE_UNAVAILABLE.into_response()
        }
        Err(_) => StatusCode::SERVICE_UNAVAILABLE.into_response(),
    }
}
async fn upgrade_route(
    State(state): State<Arc<HostState>>,
    headers: HeaderMap,
    upgrade: WebSocketUpgrade,
) -> Response {
    if !state.authenticated(&headers) {
        return unauthorized();
    }
    if headers.get(header::HOST).and_then(|v| v.to_str().ok()) != Some(&state.authority)
        || headers.get(header::ORIGIN).and_then(|v| v.to_str().ok()) != Some(&state.origin)
    {
        return StatusCode::FORBIDDEN.into_response();
    }
    if state.admission().is_err() {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    }
    let tasks = state.tasks.clone();
    let source = state.source.clone();
    let end = state.end;
    let (response, actual) = upgrade
        .max_message_size(rpc::MAX_INBOUND_MESSAGE_BYTES)
        .max_frame_size(rpc::MAX_INBOUND_MESSAGE_BYTES)
        .into_upgrade_future(move |socket| serve_peer(socket, state));
    match source.while_source_active(|| {
        if Instant::now() >= end {
            Err(SocketCleanupError::Closed)
        } else {
            tasks.spawn_upgrade(actual)
        }
    }) {
        Ok(Ok(())) => response,
        _ => StatusCode::SERVICE_UNAVAILABLE.into_response(),
    }
}
async fn gated<F: Future>(state: &HostState, future: F) -> Result<F::Output, ControlledHostFault> {
    source_polled(&state.source, state.end, future)
        .await
        .map_err(|fault| match fault {
            SourcePollFault::End => ControlledHostFault::End,
            SourcePollFault::Source => ControlledHostFault::Source,
        })
}
enum SourcePollFault {
    Source,
    End,
}
async fn source_polled<F: Future>(
    source: &ControlledHostStimulus,
    end: Instant,
    future: F,
) -> Result<F::Output, SourcePollFault> {
    let mut actual = std::pin::pin!(future);
    tokio::time::timeout_at(
        end.into(),
        std::future::poll_fn(|cx| {
            match source.while_source_active(|| {
                // timeout_at polls its inner future before its timer. This
                // actual poll boundary must therefore enforce the fixed end.
                if Instant::now() >= end {
                    std::task::Poll::Ready(Err(SourcePollFault::End))
                } else {
                    actual.as_mut().poll(cx).map(Ok)
                }
            }) {
                Ok(poll) => poll,
                Err(_) => std::task::Poll::Ready(Err(SourcePollFault::Source)),
            }
        }),
    )
    .await
    .map_err(|_| SourcePollFault::End)?
}
async fn serve_peer(mut socket: WebSocket, state: Arc<HostState>) {
    let delivery = match state.delivery.lock() {
        Ok(mut delivery) => delivery
            .take_peer()
            .map_err(|_| ControlledHostFault::DeliveryTaken),
        Err(_) => Err(ControlledHostFault::Poisoned),
    };
    let result = async {
        let (frames, requests) = delivery?.into_script_input();
        if requests
            .as_ref()
            .is_some_and(|requests| requests.len() != frames.len())
        {
            return Err(ControlledHostFault::PeerShape);
        }
        for (index, frame) in frames.into_iter().enumerate() {
            if let Some(requests) = &requests {
                let actual = gated(&state, socket.next())
                    .await?
                    .ok_or(ControlledHostFault::PeerRead)?;
                match actual {
                    Ok(Message::Text(actual)) if actual.as_str() == requests[index] => {}
                    Ok(_) => return Err(ControlledHostFault::PeerRequest),
                    Err(error) => {
                        if let Ok(mut raw) = state.actual_peer.lock() {
                            *raw = Some(ActualPeerFault::Read(error));
                        }
                        return Err(ControlledHostFault::PeerRead);
                    }
                }
            }
            if let Err(error) = gated(&state, socket.send(Message::Text(frame.into()))).await? {
                if let Ok(mut raw) = state.actual_peer.lock() {
                    *raw = Some(ActualPeerFault::Write(error));
                }
                return Err(ControlledHostFault::PeerWrite);
            }
        }
        Ok(())
    }
    .await;
    if let Err(fault) = result {
        state.fault(fault);
    }
}
