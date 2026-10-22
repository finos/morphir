//! Native host observations retained by the canonical engine. No peer bytes
//! establish browser actions, client acceptance or physical join authority.
use super::*;
use morphir_mck::workbench::{
    BrowserHostInterruption, BrowserHostIoFailure, BrowserHostManifestFailure,
    BrowserHostPeerFinish, BrowserHostPollState, BrowserHostReadOutcome, BrowserHostSendOutcome,
};
use std::future::poll_fn;

fn record_error(cause: morphir_mck::workbench::BrowserHostTranscriptFault) -> ControlledHostFault {
    ControlledHostFault::Transcript(cause)
}
fn refusal(state: &HostState, cause: ControlledHostFault) -> Response {
    state.fault(cause);
    StatusCode::SERVICE_UNAVAILABLE.into_response()
}

/// A prepared response is the actual owned status/body pair extracted from
/// delivery, not an HTTP send or client acceptance. No core call nests inside
/// the native source lock, and no extra body copy is created by this wrapper.
pub(super) fn manifest_response(state: &HostState) -> Response {
    let port = state.transcript.as_ref().expect("observed path selected");
    let pending = match port.begin_manifest() {
        Ok(pending) => pending,
        Err(cause) => return refusal(state, record_error(cause)),
    };
    let actual = state.source.while_source_active(|| {
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
            .and_then(|status| StatusCode::from_u16(status).ok())
            .ok_or(ControlledHostFault::PeerShape)?;
        Ok((status, body))
    });
    match actual {
        Ok(Ok((status, body))) => {
            if let Err(cause) = pending.prepared(status.as_u16(), body.as_bytes()) {
                return refusal(state, record_error(cause));
            }
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
            response
        }
        Ok(Err(fault)) => {
            let recorded = match fault {
                ControlledHostFault::End => pending.unfinished(BrowserHostInterruption::End),
                ControlledHostFault::Poisoned => {
                    pending.failed(BrowserHostManifestFailure::Poisoned)
                }
                ControlledHostFault::DeliveryTaken => {
                    pending.failed(BrowserHostManifestFailure::DeliveryTaken)
                }
                _ => pending.failed(BrowserHostManifestFailure::Shape),
            };
            state.fault(fault);
            if let Err(cause) = recorded {
                state.fault(record_error(cause));
            }
            StatusCode::SERVICE_UNAVAILABLE.into_response()
        }
        Err(_) => {
            let recorded = pending.unfinished(BrowserHostInterruption::Source);
            state.fault(ControlledHostFault::Source);
            if let Err(cause) = recorded {
                state.fault(record_error(cause));
            }
            StatusCode::SERVICE_UNAVAILABLE.into_response()
        }
    }
}

fn poll_state(started: bool) -> BrowserHostPollState {
    if started {
        BrowserHostPollState::Started
    } else {
        BrowserHostPollState::NotStarted
    }
}
fn interruption(cause: ControlledHostFault) -> BrowserHostInterruption {
    match cause {
        ControlledHostFault::End => BrowserHostInterruption::End,
        _ => BrowserHostInterruption::Source,
    }
}

/// Wrap the actual future poll, not construction or an await-site guess.
async fn measured<F: Future>(
    state: &HostState,
    future: F,
    started: &mut bool,
) -> Result<F::Output, ControlledHostFault> {
    let mut actual = std::pin::pin!(future);
    gated(
        state,
        poll_fn(|context| {
            *started = true;
            actual.as_mut().poll(context)
        }),
    )
    .await
}

pub(super) async fn serve_peer(mut socket: WebSocket, state: Arc<HostState>) {
    let port = state.transcript.as_ref().expect("observed path selected");
    let result = async {
        // Only this actual authenticated upgrade's handler records opened.
        // Neither the requested URL nor an accepted upgrade response does so.
        port.peer_opened().map_err(record_error)?;
        let delivery = match state.delivery.lock() {
            Ok(mut delivery) => delivery
                .take_peer()
                .map_err(|_| ControlledHostFault::DeliveryTaken),
            Err(_) => Err(ControlledHostFault::Poisoned),
        };
        let (frames, requests) = delivery?.into_script_input();
        if requests
            .as_ref()
            .is_some_and(|requests| requests.len() != frames.len())
        {
            return Err(ControlledHostFault::PeerShape);
        }
        for (index, frame) in frames.into_iter().enumerate() {
            if let Some(requests) = &requests {
                let pending = port.begin_read().map_err(record_error)?;
                let mut started = false;
                let actual = measured(&state, socket.next(), &mut started).await;
                let actual = match actual {
                    Ok(Some(Ok(Message::Text(actual)))) => {
                        // Exact actual Text, including a bounded mismatch,
                        // enters the core cache BEFORE source equality checks.
                        pending
                            .finish(BrowserHostReadOutcome::Text(actual.as_bytes()))
                            .map_err(record_error)?;
                        actual
                    }
                    Ok(Some(Ok(message))) => {
                        let outcome = match message {
                            Message::Binary(bytes) => {
                                BrowserHostReadOutcome::Binary { bytes: bytes.len() }
                            }
                            Message::Ping(bytes) => {
                                BrowserHostReadOutcome::Ping { bytes: bytes.len() }
                            }
                            Message::Pong(bytes) => {
                                BrowserHostReadOutcome::Pong { bytes: bytes.len() }
                            }
                            Message::Close(close) => BrowserHostReadOutcome::Close {
                                code: close.as_ref().map(|close| close.code),
                                reason_bytes: close.as_ref().map_or(0, |close| close.reason.len()),
                            },
                            Message::Text(_) => unreachable!("Text handled above"),
                        };
                        pending.finish(outcome).map_err(record_error)?;
                        return Err(ControlledHostFault::PeerRequest);
                    }
                    Ok(Some(Err(error))) => {
                        if let Ok(mut raw) = state.actual_peer.lock() {
                            *raw = Some(ActualPeerFault::Read(error));
                        }
                        state.fault(ControlledHostFault::PeerRead);
                        let recorded = pending.finish(BrowserHostReadOutcome::Failed(
                            BrowserHostIoFailure::Transport,
                        ));
                        if let Err(cause) = recorded {
                            state.fault(record_error(cause));
                        }
                        return Err(ControlledHostFault::PeerRead);
                    }
                    Ok(None) => {
                        pending
                            .finish(BrowserHostReadOutcome::Eof)
                            .map_err(record_error)?;
                        return Err(ControlledHostFault::PeerRead);
                    }
                    Err(cause) => {
                        state.fault(cause);
                        let recorded = pending.finish(BrowserHostReadOutcome::Unfinished {
                            cause: interruption(cause),
                            poll: poll_state(started),
                        });
                        if let Err(error) = recorded {
                            state.fault(record_error(error));
                        }
                        return Err(cause);
                    }
                };
                if actual.as_str() != requests[index] {
                    return Err(ControlledHostFault::PeerRequest);
                }
            }
            let pending = port.begin_reply(frame.as_bytes()).map_err(record_error)?;
            let mut started = false;
            let actual = measured(
                &state,
                socket.send(Message::Text(frame.into())),
                &mut started,
            )
            .await;
            match actual {
                Ok(Ok(())) => pending
                    .finish(BrowserHostSendOutcome::Returned)
                    .map_err(record_error)?,
                Ok(Err(error)) => {
                    if let Ok(mut raw) = state.actual_peer.lock() {
                        *raw = Some(ActualPeerFault::Write(error));
                    }
                    state.fault(ControlledHostFault::PeerWrite);
                    let recorded = pending.finish(BrowserHostSendOutcome::Failed(
                        BrowserHostIoFailure::Transport,
                    ));
                    if let Err(cause) = recorded {
                        state.fault(record_error(cause));
                    }
                    return Err(ControlledHostFault::PeerWrite);
                }
                Err(cause) => {
                    state.fault(cause);
                    let recorded = pending.finish(BrowserHostSendOutcome::Unfinished {
                        cause: interruption(cause),
                        poll: poll_state(started),
                    });
                    if let Err(error) = recorded {
                        state.fault(record_error(error));
                    }
                    return Err(cause);
                }
            }
        }
        Ok(())
    }
    .await;
    // This records actual loop return. If this future is dropped, pending/port
    // Drop leave Incomplete; no destructor fabricates PeerFinished or a send.
    let finish = match result {
        Ok(()) => BrowserHostPeerFinish::ScriptFinished,
        Err(ControlledHostFault::Source) => {
            BrowserHostPeerFinish::Interrupted(BrowserHostInterruption::Source)
        }
        Err(ControlledHostFault::End) => {
            BrowserHostPeerFinish::Interrupted(BrowserHostInterruption::End)
        }
        Err(_) => BrowserHostPeerFinish::Failed,
    };
    if let Err(cause) = result {
        state.fault(cause);
    }
    if let Err(cause) = port.peer_finished(finish) {
        state.fault(record_error(cause));
    }
}

#[cfg(test)]
#[path = "transcript/tests.rs"]
mod tests;
