//! The selected real compiled INPUT is copied; no expected/core or host proof.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::{
    controlled_input::ControlledHostStimulus, source_scope::BrowserSourceScope,
};

#[test]
fn browser_controlled_input_01_actual_selected_manifest_peer_and_opening_are_preserved() {
    let mut exercised = false;
    prepared_browser_originals::<_, BrowserInputFault>(&source(CORPUS), &configuration(), |clients, loans| {
        clients.visit_clients(loans, |client, loans| {
            if exercised { return Ok(()); }
            let BrowserRuntimeInput::ControlledModelOriginalsHttpV1 { manifest, manifest_byte_limit, peer } = client.fixture().runtime(loans)? else { return Ok(()); };
            let opening = client.actions(loans)?.find(|action| matches!(action.kind(), BrowserActionKind::BeginConnectedOpening { .. }));
            let Some(opening) = opening else { return Ok(()); };
            let BrowserActionKind::BeginConnectedOpening { source, project_id, pending, transfer_limits, .. } = opening.kind() else { unreachable!() };
            let selected = client.fixture().input.literal_peers.0.iter().find(|candidate| candidate.alias.as_str()==peer.as_str()).unwrap();
            let mut scope = BrowserSourceScope::prepare(loans)?;
            let stimulus = ControlledHostStimulus::prepare(&client, loans, &mut scope, opening.position())?;
            assert_eq!(stimulus.manifest_status(), manifest.status.0);
            assert_eq!(stimulus.manifest_byte_limit(), manifest_byte_limit.0);
            let input::Frame::Literal { text } = &manifest.body else { panic!("this exact source control covers literal manifest bytes") };
            assert_eq!(stimulus.manifest_body(), text.as_str());
            assert_eq!(stimulus.peer_alias(), peer.as_str());
            assert_eq!(stimulus.frames().len(), selected.frames.0.len());
            for (actual, input) in stimulus.frames().iter().zip(&selected.frames.0) {
                let input::Frame::Literal { text } = input else { panic!("this exact source control covers literal peer frames") };
                assert_eq!(actual, text.as_str());
            }
            assert_eq!(stimulus.selected_source().provider_id, source.provider_id.as_str());
            assert_eq!(stimulus.selected_source().locator, source.locator.as_str());
            assert_eq!(stimulus.selected_project(), project_id.as_str());
            assert!(matches!(stimulus.opening(), crate::workbench::model_originals::workflow::pipeline::browser::controlled_input::ControlledOpening::BeginConnectedOpening { pending: actual, inventory_max_entries, read_max_bytes }
                if actual == pending.as_str() && *inventory_max_entries == transfer_limits.inventory_max_entries.0 && *read_max_bytes == transfer_limits.read_max_bytes.0));
            assert!(stimulus.admit().is_ok());
            scope.revoke();
            assert!(stimulus.admit().is_err());
            drop(stimulus);
            exercised = true;
            Ok(())
        })
    }).unwrap();
    assert!(
        exercised,
        "a real compiled controlled input plus opening was required"
    );
}

#[test]
fn browser_controlled_input_02_segments_are_copied_as_input_without_json_or_status_normalization() {
    let (mut owners, mut receiving) = crate::workbench::model_originals::workflow::pipeline::browser::funded_workflow_tests::owners(65536, 1000, 65536);
    let mut loans = BrowserOwnerLoans::new(&mut owners, &mut receiving);
    let doc = crate::json::strict::Document::parse_unsigned_counts(br#"{"kind":"segments","parts":[{"kind":"literal","text":"not-json:"},{"kind":"repeat","count":3,"text":"\u03bb"}]}"#).unwrap();
    let mut input_decoder = crate::workbench::model_originals::workflow::Decoder::new(
        crate::workbench::model_originals::workflow::decode::DecodeLimits::new(
            65536, 65536, 1000, 65536, 1000,
        )
        .unwrap(),
    );
    let frame: input::Frame =
        crate::workbench::model_originals::workflow::Decode::decode(&doc, &mut input_decoder)
            .unwrap();
    let copied = ControlledHostStimulus::copy_frame(&frame, &mut loans).unwrap();
    assert_eq!(copied, "not-json:λλλ");
}
