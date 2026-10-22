//! Real TCP ownership and binding retirement controls, without a browser.
use super::super::*;
use crate::commands::ui::server::controlled_originals_tests::{runtime, with_stimulus};
use futures_util::SinkExt as _;
use std::time::Duration;
use tokio::io::AsyncWriteExt as _;
use tokio_tungstenite::tungstenite::{Message, client::IntoClientRequest as _};

async fn actual_launch(host: &BoundControlledUiHost) -> Result<u16, reqwest::Error> {
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    Ok(client
        .get(host.launch_url())
        .header("Connection", "close")
        .send()
        .await?
        .status()
        .as_u16())
}

#[test]
fn browser_controlled_host_finish_01_actual_tcp_join_retires_exact_binding() {
    let runtime = runtime();
    let ((observed, finish), terminal) = with_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let mut host = BoundControlledUiHost::bind(
                stimulus,
                loans,
                Instant::now() + Duration::from_secs(10),
            )
            .await
            .unwrap();
            host.start().unwrap();
            let observed = actual_launch(&host).await;
            (observed, host.finish_joined().await)
        })
    });
    assert_eq!(observed.unwrap(), 303);
    assert!(matches!(
        finish,
        ControlledHostFinish::Joined(ControlledHostJoined::Clean)
    ));
    assert_eq!(
        terminal,
        morphir_mck::workbench::BrowserSourceTerminal::Quiescent
    );
}

#[test]
fn browser_controlled_host_finish_02_external_state_arc_recovers_same_host_then_retires() {
    let runtime = runtime();
    let ((observed, refusal, same_owner, finish), terminal) = with_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let mut host = BoundControlledUiHost::bind(
                stimulus,
                loans,
                Instant::now() + Duration::from_secs(10),
            )
            .await
            .unwrap();
            host.start().unwrap();
            let observed = actual_launch(&host).await;
            let held = Arc::clone(&host.state);
            match host.finish_joined().await {
                ControlledHostFinish::Retained {
                    host,
                    shutdown,
                    reason,
                } => {
                    let same = Arc::ptr_eq(&held, &host.state) && host.state.source.admit().is_ok();
                    drop(held);
                    (
                        observed,
                        Some((shutdown, reason)),
                        same,
                        host.finish_joined().await,
                    )
                }
                finished => (observed, None, false, finished),
            }
        })
    });
    assert_eq!(observed.unwrap(), 303);
    assert_eq!(
        refusal,
        Some((
            ControlledHostShutdown::Joined,
            ControlledHostFinishRefusal::SharedState
        ))
    );
    assert!(same_owner);
    assert!(matches!(
        finish,
        ControlledHostFinish::Joined(ControlledHostJoined::Clean)
    ));
    assert_eq!(
        terminal,
        morphir_mck::workbench::BrowserSourceTerminal::Quiescent
    );
}

#[test]
fn browser_controlled_host_finish_03_external_source_arc_recovers_same_stimulus_then_retires() {
    let runtime = runtime();
    let ((observed, refusal, same_owner, finish), terminal) = with_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let mut host = BoundControlledUiHost::bind(
                stimulus,
                loans,
                Instant::now() + Duration::from_secs(10),
            )
            .await
            .unwrap();
            host.start().unwrap();
            let observed = actual_launch(&host).await;
            let held = Arc::clone(&host.state.source);
            let state = Arc::as_ptr(&host.state);
            match host.finish_joined().await {
                ControlledHostFinish::Retained {
                    host,
                    shutdown,
                    reason,
                } => {
                    let same = state == Arc::as_ptr(&host.state)
                        && Arc::ptr_eq(&held, &host.state.source)
                        && held.admit().is_ok();
                    drop(held);
                    (
                        observed,
                        Some((shutdown, reason)),
                        same,
                        host.finish_joined().await,
                    )
                }
                finished => (observed, None, false, finished),
            }
        })
    });
    assert_eq!(observed.unwrap(), 303);
    assert_eq!(
        refusal,
        Some((
            ControlledHostShutdown::Joined,
            ControlledHostFinishRefusal::SharedSource
        ))
    );
    assert!(same_owner);
    assert!(matches!(
        finish,
        ControlledHostFinish::Joined(ControlledHostJoined::Clean)
    ));
    assert_eq!(
        terminal,
        morphir_mck::workbench::BrowserSourceTerminal::Quiescent
    );
}

#[test]
fn browser_controlled_host_finish_04_expired_pending_shutdown_preserves_owner_and_debt() {
    // One thread keeps the genuine pending listener unpolled between wall-clock
    // expiry and the first finish attempt. No fake task or joined state is used.
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let ((registered, refusal, same_owner, cleanup, finish), terminal) =
        with_stimulus(|stimulus, loans| {
            runtime.block_on(async {
                let end = Instant::now() + Duration::from_millis(500);
                let mut host = BoundControlledUiHost::bind(stimulus, loans, end)
                    .await
                    .unwrap();
                host.start().unwrap();
                let mut peer = tokio::net::TcpStream::connect(host.address())
                    .await
                    .unwrap();
                peer.write_all(b"GET /api/session HTTP/1.1\r\n")
                    .await
                    .unwrap();
                while host.cleanup.retained_tasks() == 0 && Instant::now() < end {
                    tokio::time::sleep(Duration::from_millis(1)).await;
                }
                let registered = host.cleanup.retained_tasks() > 0;
                let address = Arc::as_ptr(&host.state);
                std::thread::sleep(
                    end.saturating_duration_since(Instant::now()) + Duration::from_millis(1),
                );
                match host.finish_joined().await {
                    ControlledHostFinish::Retained {
                        mut host,
                        shutdown,
                        reason,
                    } => {
                        let same = address == Arc::as_ptr(&host.state)
                            && host.state.source.admit().is_ok();
                        drop(peer);
                        // Test cleanup can await the retained actual handles after
                        // expiry. It does not extend the production action deadline.
                        let cleanup =
                            tokio::time::timeout(Duration::from_secs(5), host.cleanup.join()).await;
                        (
                            registered,
                            Some((shutdown, reason)),
                            same,
                            Some(cleanup),
                            host.finish_joined().await,
                        )
                    }
                    finished => {
                        drop(peer);
                        (registered, None, false, None, finished)
                    }
                }
            })
        });
    assert!(registered);
    assert!(matches!(
        refusal,
        Some((
            ControlledHostShutdown::Pending { .. },
            ControlledHostFinishRefusal::Pending
        ))
    ));
    assert!(same_owner);
    assert!(matches!(
        cleanup,
        Some(Ok(
            SocketDrainOutcome::Joined | SocketDrainOutcome::JoinedWithFault(_)
        ))
    ));
    assert!(matches!(finish, ControlledHostFinish::Joined(_)));
    assert_eq!(
        terminal,
        morphir_mck::workbench::BrowserSourceTerminal::Quiescent
    );
}

#[test]
fn browser_controlled_host_finish_05_plain_drop_still_retains_abandoned_debt() {
    let runtime = runtime();
    let ((), terminal) = with_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let host = BoundControlledUiHost::bind(
                stimulus,
                loans,
                Instant::now() + Duration::from_secs(10),
            )
            .await
            .unwrap();
            drop(host);
        })
    });
    assert_eq!(
        terminal,
        morphir_mck::workbench::BrowserSourceTerminal::Incomplete {
            first: morphir_mck::workbench::BrowserSourceFault::Abandoned,
            bindings: 1,
        }
    );
}

#[test]
fn browser_controlled_host_finish_06_actual_peer_fault_is_preserved_after_join_and_retirement() {
    let runtime = runtime();
    let ((observed, first, finish), terminal) = with_stimulus(|stimulus, loans| {
        assert!(
            stimulus.requests().is_some(),
            "genuine source requires requests"
        );
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(10);
            let mut host = BoundControlledUiHost::bind(stimulus, loans, end)
                .await
                .unwrap();
            host.start().unwrap();
            let observed = async {
                let client = reqwest::Client::builder()
                    .redirect(reqwest::redirect::Policy::none())
                    .build()?;
                let response = client
                    .get(host.launch_url())
                    .header("Connection", "close")
                    .send()
                    .await?;
                let cookie = response
                    .headers()
                    .get(reqwest::header::SET_COOKIE)
                    .ok_or_else(|| std::io::Error::other("actual cookie missing"))?
                    .to_str()?
                    .split(';')
                    .next()
                    .unwrap()
                    .to_owned();
                drop(response);
                let mut request = format!("ws://{}/rpc", host.address()).into_client_request()?;
                request.headers_mut().insert("Cookie", cookie.parse()?);
                request
                    .headers_mut()
                    .insert("Origin", host.base_url().parse()?);
                let (mut peer, _) = tokio_tungstenite::connect_async(request).await?;
                // Actual binary input cannot equal the selected literal Text request.
                peer.send(Message::Binary(vec![0].into())).await?;
                while host.state.first().is_none() && Instant::now() < end {
                    tokio::time::sleep(Duration::from_millis(1)).await;
                }
                drop(peer);
                Ok::<_, Box<dyn std::error::Error + Send + Sync>>(())
            }
            .await;
            let first = host.state.first();
            (observed, first, host.finish_joined().await)
        })
    });
    observed.unwrap();
    assert_eq!(first, Some(ControlledHostFault::PeerRequest));
    assert!(matches!(
        finish,
        ControlledHostFinish::Joined(ControlledHostJoined::Fault(
            ControlledHostFault::PeerRequest
        ))
    ));
    assert_eq!(
        terminal,
        morphir_mck::workbench::BrowserSourceTerminal::Quiescent
    );
}

#[test]
fn browser_controlled_host_finish_07_in_place_retirement_is_inert_on_retry_and_validation() {
    // Bookkeeping only. No physical owner is created in this source fixture.
    let ((first, retry, admission, validation), terminal) = with_stimulus(|mut stimulus, loans| {
        let first = stimulus.retire_after_join_in_place();
        let retry = stimulus.retire_after_join_in_place();
        let admission = stimulus.admit();
        let validation = loans.validate_controlled_source(&stimulus);
        (first, retry, admission, validation)
    });
    assert_eq!(first, Ok(()));
    assert_eq!(
        retry,
        Err(morphir_mck::workbench::BrowserSourceFault::Revoked)
    );
    assert_eq!(
        admission,
        Err(morphir_mck::workbench::BrowserSourceFault::Revoked)
    );
    assert!(validation.is_err());
    assert_eq!(
        terminal,
        morphir_mck::workbench::BrowserSourceTerminal::Quiescent
    );
}
