//! Focused closed-shape/comparison envelope controls. Coverage only, not RED.
use super::*;

#[test]
fn browser_document_ingress_shape_oversized_member_table_and_long_unknown_key_refuse_without_ack() {
    let bodies = [
        br#"{"a":0,"b":0,"c":0,"d":0,"e":0,"f":0,"sequence":2,"actual":{"workspace":"unit","opening":0},"kind":"model-closed"}"#.to_vec(),
        format!(r#"{{"{}":0,"sequence":2,"actual":{{"workspace":"unit","opening":0}},"kind":"model-closed"}}"#, "x".repeat(96)).into_bytes(),
    ];
    for body in bodies {
        let fact = literal_frame(1, 1, FACT_BODY);
        let terminal_frame = literal_frame(2, 2, END_BODY);
        let invalid = literal_frame(1, 2, &body);
        let runtime = runtime();
        let ((observed, collected, closes, joined, unresolved), source) =
            with_negative_stimulus(|stimulus, loans| {
                runtime.block_on(async {
                    let end = Instant::now() + Duration::from_secs(20);
                    let mut host = BoundControlledUiHost::bind_with_document_ingress(
                        stimulus,
                        loans,
                        limits(),
                        end,
                    )
                    .await
                    .unwrap();
                    let mut peers = Vec::new();
                    let state = Arc::clone(&host.state);
                    let setup = match host.start() {
                        Ok(()) => open_literal_channel(&host, &mut peers, end).await,
                        Err(_) => Err(failure("actual host start failed")),
                    };
                    let (observed, collected) = match setup {
                        Ok(upgraded) => {
                            let (observed, collected) = tokio::join!(
                                reject_literal(
                                    Scenario::UnknownField,
                                    &mut peers,
                                    &state,
                                    (&fact, &terminal_frame, &invalid),
                                    upgraded,
                                    end
                                ),
                                tokio::time::timeout_at(end.into(), host.collect_document(loans)),
                            );
                            (observed, Some(collected))
                        }
                        Err(cause) => (Err(cause), None),
                    };
                    drop(state);
                    let (closes, joined, unresolved) = finish_actual(host, peers, end).await;
                    (observed, collected, closes, joined, unresolved)
                })
            });
        let (observed, _) = assert_negative(
            Run {
                observed,
                collected,
                stop: None,
                close_attempts: closes,
                joined,
                unresolved: unresolved.map(std::mem::ManuallyDrop::new),
                source,
            },
            DocumentIngressFault::Shape,
            1,
        );
        assert_eq!(observed.first_ack, Some(literal_frame(3, 1, &[])));
        assert!(observed.second_ack.is_none());
    }
}
