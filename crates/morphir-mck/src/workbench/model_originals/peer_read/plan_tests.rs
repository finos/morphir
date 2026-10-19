use super::*;

fn bounds() -> PeerReadBounds {
    PeerReadBounds {
        saved_bytes: 4096,
        rows: 3,
        window_bytes: 5,
        wire_bytes: 49233,
        observer_bytes: 189,
    }
}

#[test]
fn shared_read_plan_uses_the_actual_window_frame_and_observer_formula() {
    let plan = ReadRunShape::new(5, 0, 0, 5, 2, 3).unwrap();
    let parts = [
        ReplyPartView::Literal("X"),
        ReplyPartView::CorrelatedRequestId,
        ReplyPartView::RowOffset,
        ReplyPartView::RowNextOffset,
        ReplyPartView::Base64Window,
    ];
    let work = plan.measure(parts.into_iter(), bounds().into()).unwrap();
    assert_eq!(work.rows(), 3);
    assert_eq!(work.window_bytes(), 5);
    assert_eq!(work.wire_bytes(), 49233);
    assert_eq!(work.observer_bytes(), 189);
    for resource in [
        PeerReadResource::Rows,
        PeerReadResource::WindowBytes,
        PeerReadResource::WireBytes,
        PeerReadResource::ObserverBytes,
    ] {
        let mut limit = bounds();
        match resource {
            PeerReadResource::Rows => limit.rows -= 1,
            PeerReadResource::WindowBytes => limit.window_bytes -= 1,
            PeerReadResource::WireBytes => limit.wire_bytes -= 1,
            PeerReadResource::ObserverBytes => limit.observer_bytes -= 1,
            PeerReadResource::SavedBytes => unreachable!(),
        }
        assert!(
            matches!(plan.measure(parts.into_iter(),limit.into()),Err(PeerReadError::Resource(actual)) if actual==resource)
        );
    }
}

#[test]
fn read_plan_checks_real_source_end_partial_window_and_ordinal_before_rows() {
    assert!(ReadRunShape::new(5, 8190, 0, 5, 2, 3).is_err());
    assert!(ReadRunShape::new(6, 0, 0, 5, 2, 3).is_err());
    assert!(ReadRunShape::new(5, 0, 0, 6, 2, 3).is_err());
    assert!(ReadRunShape::new(5, 0, 0, 5, 2, 2).is_err());
    assert!(ReadRunShape::new(5, 0, 0, 5, 0, 3).is_err());
    assert!(ReadRunShape::new(64 * 1024 * 1024 + 1, 0, 0, 5, 2, 3).is_err());
    assert!(ReadRunShape::new(6, 0, 0, 4, 2, 2).is_ok());
    assert!(ReadRunShape::new(5, 8189, 0, 5, 2, 3).is_ok());
}
