//! Constructor refusal retains the actual source debt and SAME owner fault.
use super::*;

#[test]
fn browser_document_ingress_preparation_overflow_then_same_owner_retry_refuses() {
    let runtime = runtime();
    let ((ready, first, after, retry, joined, unresolved), terminal) =
        with_negative_stimulus(|stimulus, loans| {
            runtime.block_on(async {
                let source = loans.prepare_application_source().unwrap();
                let ready = source.while_source_active(|| ());
                let end = Instant::now() + Duration::from_secs(2);
                let actual = BoundControlledUiHost::bind_with_document_ingress(
                    stimulus,
                    loans,
                    DocumentIngressLimits {
                        observation_owners: OWNERS,
                        observation_events: EVENTS,
                        records: usize::MAX,
                        journal_bytes: JOURNAL,
                        frame_bytes: FRAME,
                        socket_tasks: 6,
                        request_tickets: 16,
                        request_header_fields: 32,
                        request_header_bytes: 1024,
                    },
                    end,
                )
                .await;
                let (first, joined, unresolved) = match actual {
                    Err(cause) => (Some(cause), None, None),
                    Ok(mut host) => {
                        let mut joined = host.shutdown().await;
                        for _ in 0..8 {
                            if !matches!(joined, ControlledHostShutdown::Pending { .. }) {
                                break;
                            }
                            tokio::task::yield_now().await;
                            joined = host.shutdown().await;
                        }
                        let unresolved = if matches!(joined, ControlledHostShutdown::Pending { .. })
                        {
                            Some(host)
                        } else {
                            drop(host);
                            None
                        };
                        (None, Some(joined), unresolved)
                    }
                };
                let after = source.while_source_active(|| ());
                let retry = loans.prepare_application_source();
                let refused_retry = retry.is_err();
                drop(retry);
                drop(source);
                (ready, first, after, refused_retry, joined, unresolved)
            })
        });
    let unresolved = unresolved.map(std::mem::ManuallyDrop::new);
    assert!(
        unresolved.is_none(),
        "unexpected real host retained through cleanup refusal"
    );
    if let Some(joined) = joined {
        assert!(matches!(
            joined,
            ControlledHostShutdown::Joined | ControlledHostShutdown::JoinedWithFault(_)
        ));
    }
    assert_eq!(
        ready,
        Ok(()),
        "actual source was live before the checked constructor plan"
    );
    assert!(
        matches!(first, Some(super::super::super::super::DocumentSetupFault::Host(
        crate::commands::ui::server::controlled_originals::ControlledHostSetupFault::SizeOverflow
    )))
    );
    assert_eq!(
        after,
        Err(morphir_mck::workbench::BrowserSourceFault::Abandoned)
    );
    assert!(
        retry,
        "the SAME cumulative owners cannot retry after consuming unresolved source debt"
    );
    assert!(matches!(terminal, BrowserSourceTerminal::Incomplete { .. }));
}
