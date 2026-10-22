//! Closed bootstrap dimensions only, not a physical browser or grant.
use super::*;

#[test]
fn browser_document_ingress_limits_whole_frame_must_hold_fixed_header() {
    for frame_bytes in [0, 15] {
        let actual = DocumentIngressLimits {
            observation_owners: OWNERS,
            observation_events: EVENTS,
            records: RECORDS,
            journal_bytes: JOURNAL,
            frame_bytes,
            socket_tasks: 6,
            request_tickets: 16,
            request_header_fields: 32,
            request_header_bytes: 1024,
        }
        .dimensions();
        assert!(matches!(actual, Err(
            crate::commands::ui::server::controlled_originals::ControlledHostSetupFault::DocumentLimits
        )), "a bootstrap frame capacity smaller than its fixed header is invalid");
    }
    let actual = DocumentIngressLimits {
        observation_owners: OWNERS,
        observation_events: EVENTS,
        records: RECORDS,
        journal_bytes: JOURNAL,
        frame_bytes: 16,
        socket_tasks: 6,
        request_tickets: 16,
        request_header_fields: 32,
        request_header_bytes: 1024,
    }
    .dimensions();
    assert!(
        actual.is_ok(),
        "the exact fixed-header capacity remains representable"
    );
}
