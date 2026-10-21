//! Additional implementation validation against genuine prepared inputs.
//! Authored after the initial seven; not claimed as pre-implementation RED.
use super::*;

#[test]
fn browser_projection_01_actual_runtime_empty_files_and_peers_lend_same_inputs_with_paid_visits() {
    let mut supported = 0;
    let mut file_count = 0;
    let mut peer_count = 0;
    prepared_browser_originals::<_, BrowserInputFault>(&source(CORPUS), &configuration(), |inventory, loans| {
        inventory.visit_clients(loans, |client, loans| {
            let fixture = client.fixture();
            let before = loans.owners.closure.usage().structural_visits;
            match (fixture.runtime(loans)?, &fixture.input.mode) {
                (BrowserRuntimeInput::ControlledModelOriginalsHttpV1 { manifest, manifest_byte_limit, peer },
                    crate::workbench::model_originals::workflow::input::ClientFixtureMode::Runtime {
                        runtime: crate::workbench::model_originals::workflow::input::ClientRuntime::ControlledModelOriginalsHttpV1 {
                            manifest: actual, manifest_byte_limit: actual_limit, peer: actual_peer,
                        }
                    }) => {
                    supported += 1;
                    assert!(std::ptr::eq(manifest, actual));
                    assert!(std::ptr::eq(manifest_byte_limit, actual_limit));
                    assert!(std::ptr::eq(peer, actual_peer));
                }
                (BrowserRuntimeInput::Unsupported, actual) => assert!(!matches!(actual,
                    crate::workbench::model_originals::workflow::input::ClientFixtureMode::Runtime {
                        runtime: crate::workbench::model_originals::workflow::input::ClientRuntime::ControlledModelOriginalsHttpV1 { .. }
                    })),
                _ => panic!("foreign runtime must not be relabeled originals HTTP"),
            }
            let files = fixture.files(loans)?;
            assert_eq!(files.len(), fixture.input.files.0.len());
            for (view, actual) in files.zip(&fixture.input.files.0) {
                file_count += 1;
                assert!(std::ptr::eq(view.alias(), &actual.alias));
                assert!(std::ptr::eq(view.bytes(), &actual.bytes));
            }
            let peers = fixture.peers(loans)?;
            assert_eq!(peers.len(), fixture.input.literal_peers.0.len());
            for (view, actual) in peers.zip(&fixture.input.literal_peers.0) {
                peer_count += 1;
                assert!(std::ptr::eq(view.alias(), &actual.alias));
                assert!(std::ptr::eq(view.frames(), actual.frames.0.as_slice()));
                match (view.requests(), &actual.requests) {
                    (None, crate::workbench::model_originals::workflow::Presence::Absent) => {},
                    (Some(view), crate::workbench::model_originals::workflow::Presence::Present(actual)) => assert!(std::ptr::eq(view, actual.0.as_slice())),
                    _ => panic!("preserve optional input requests exactly"),
                }
            }
            assert_eq!(loans.owners.closure.usage().structural_visits - before,
                1 + fixture.input.files.0.len() + fixture.input.literal_peers.0.len());
            for alias in client.input_aliases(loans)? {
                assert!(std::ptr::eq(alias.alias(), alias.definition.alias));
                assert!(matches!((alias.position(), alias.definition.position),
                    (BrowserInputPosition::Fixture, SourcePosition::Fixture)
                    | (BrowserInputPosition::Action(_), SourcePosition::Action(_))));
                if let (BrowserInputPosition::Action(view), SourcePosition::Action(actual)) = (alias.position(), alias.definition.position) {
                    assert_eq!(view, actual);
                }
            }
            Ok(())
        })
    }).unwrap();
    assert!(
        supported > 0,
        "actual controlled originals fixture was exercised"
    );
    assert_eq!(
        file_count, 0,
        "current selected file tables are empty; no nonempty-file coverage"
    );
    assert!(peer_count > 0, "actual input peers were exercised");
}

#[test]
fn browser_projection_02_actual_first_work_refusal_survives_every_later_view_request() {
    let policy: serde_json::Value = serde_json::from_str(CHECKER).unwrap();
    let limit = usize::try_from(policy["closure"]["structuralVisits"].as_u64().unwrap()).unwrap();
    let calls = Cell::new(0);
    let result = prepared_browser_originals::<_, BrowserInputFault>(
        &source(CORPUS),
        &configuration(),
        |inventory, loans| {
            inventory.visit_clients(loans, |client, loans| {
                calls.set(calls.get() + 1);
                let refused = loans.visits(limit).unwrap_err();
                assert!(matches!(
                    refused,
                    BrowserInputFault::Closure(ClosureError::Resource(Resource::StructuralVisits))
                ));
                let before = (
                    loans.owners.closure.usage(),
                    loans.owners.decode.usage(),
                    loans.receiving.usage(),
                    loans.owners.comparison.usage(),
                );
                assert!(matches!(
                    client.actions(loans),
                    Err(BrowserInputFault::Closure(ClosureError::Resource(
                        Resource::StructuralVisits
                    )))
                ));
                assert!(matches!(
                    client.input_aliases(loans),
                    Err(BrowserInputFault::Closure(ClosureError::Resource(
                        Resource::StructuralVisits
                    )))
                ));
                assert!(matches!(
                    client.fixture().runtime(loans),
                    Err(BrowserInputFault::Closure(ClosureError::Resource(
                        Resource::StructuralVisits
                    )))
                ));
                assert!(matches!(
                    client.fixture().files(loans),
                    Err(BrowserInputFault::Closure(ClosureError::Resource(
                        Resource::StructuralVisits
                    )))
                ));
                assert!(matches!(
                    client.fixture().peers(loans),
                    Err(BrowserInputFault::Closure(ClosureError::Resource(
                        Resource::StructuralVisits
                    )))
                ));
                assert_eq!(
                    before,
                    (
                        loans.owners.closure.usage(),
                        loans.owners.decode.usage(),
                        loans.receiving.usage(),
                        loans.owners.comparison.usage()
                    )
                );
                Err(refused)
            })
        },
    );
    assert!(matches!(
        result,
        Err(BrowserPreparationFault::Preparation(
            PreparationFault::Callback(BrowserInputFault::Closure(ClosureError::Resource(
                Resource::StructuralVisits
            )))
        ))
    ));
    assert_eq!(calls.get(), 1);
}

#[test]
fn browser_projection_03_wrong_configuration_is_typed_before_any_callback() {
    let calls = Cell::new(0);
    let result = prepared_browser_originals::<_, BrowserInputFault>(
        &source(CORPUS),
        &RunConfiguration::from_json(r#"{"kind":"historical"}"#).unwrap(),
        |_, _| {
            calls.set(calls.get() + 1);
            Ok(())
        },
    );
    assert!(matches!(
        result,
        Err(BrowserPreparationFault::WrongConfiguration)
    ));
    assert_eq!(calls.get(), 0);
}
