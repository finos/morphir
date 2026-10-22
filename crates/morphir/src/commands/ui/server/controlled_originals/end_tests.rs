//! Actual component boundaries only: no browser/action/Download qualification.
use super::super::controlled_originals_tests::{runtime, with_stimulus};
use super::*;

#[test]
fn browser_controlled_host_end_01_ready_actual_io_is_not_polled_after_original_end() {
    use tokio::io::AsyncWriteExt as _;
    let runtime = runtime();
    let ((result, unread, joined), _) = with_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let end = Instant::now() + std::time::Duration::from_millis(100);
            let mut host = BoundControlledUiHost::bind(stimulus, loans, end)
                .await
                .unwrap();
            let listener = tokio::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
                .await
                .unwrap();
            let address = listener.local_addr().unwrap();
            let (mut writer, (reader, _)) = tokio::time::timeout_at(end.into(), async {
                tokio::try_join!(tokio::net::TcpStream::connect(address), listener.accept())
            })
            .await
            .unwrap()
            .unwrap();
            drop(listener);
            let ready = tokio::time::timeout_at(end.into(), writer.writable()).await;
            tokio::time::sleep_until(end.into()).await;
            let result = if matches!(ready, Ok(Ok(()))) {
                gated(&host.state, writer.write_all(b"x")).await
            } else {
                Err(ControlledHostFault::PeerWrite)
            };
            let unread = reader.try_read(&mut [0_u8; 1]);
            drop(writer);
            drop(reader);
            let joined = host.shutdown().await;
            drop(host);
            (result, unread, joined)
        })
    });
    assert!(matches!(result, Err(ControlledHostFault::End)));
    assert!(
        matches!(unread,Err(error) if error.kind()==std::io::ErrorKind::WouldBlock),
        "ready OS writer must not have received a post-end poll"
    );
    assert_eq!(joined, ControlledHostShutdown::Joined);
}

#[test]
fn browser_controlled_host_end_02_expired_bind_refuses_before_listener_effect() {
    let runtime = runtime();
    let ((expired, cleanup), _) = with_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let end = Instant::now();
            let actual = BoundControlledUiHost::bind(stimulus, loans, end).await;
            match actual {
                Err(ControlledHostSetupFault::End) => (true, None),
                Err(_) => (false, None),
                Ok(mut host) => {
                    // Old implementation's actual owner is disposed before the
                    // intended assertion. No listener/task join is invented.
                    let cleanup = host.shutdown().await;
                    drop(host);
                    (false, Some(cleanup))
                }
            }
        })
    });
    assert!(
        expired,
        "the original already-ended request cannot bind a new listener"
    );
    assert!(cleanup.is_none());
}
