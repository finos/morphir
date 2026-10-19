//! Independently authored peers exercise the checker, not production effects.
use morphir_mck::workbench::model_originals::{
    FixtureByteLimits, FixtureBytes, InputByteFixture, ObservedRead, PeerReadBounds, PeerReadRun,
    ReadEffectKind,
};
use serde_json::{Value, json};

fn controls() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/peer-read-runs-v1.json"
    ))
    .unwrap()
}
fn small_source() -> FixtureBytes {
    FixtureBytes::parse(
        r#"{"kind":"hex","hex":"000102ff"}"#,
        FixtureByteLimits::new(1024, 4, 32).unwrap(),
    )
    .unwrap()
}
fn plan() -> Value {
    json!({"kind":"read-run","attempt":"opening-A","effectKind":"read-original","firstOrdinal":0,"source":"source-A",
        "expectedRequest":{"method":"morphir.model-originals.read","contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":{"kind":"original","entryId":"entry-A"},"maxBytes":3},
        "window":{"firstOffset":0,"afterOffset":4,"chunkBytes":3,"rows":2},
        "replyParts":controls()["cases"][0]["input"]["replyParts"]})
}
fn bounds() -> PeerReadBounds {
    PeerReadBounds {
        saved_bytes: 1024 * 1024,
        rows: 8192,
        window_bytes: 128 * 1024 * 1024,
        wire_bytes: 256 * 1024 * 1024,
        observer_bytes: 1024 * 1024 * 1024,
    }
}
fn request(id: &str, offset: usize, max: usize) -> String {
    let params = json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":{"kind":"original","entryId":"entry-A"},"offset":offset,"maxBytes":max});
    format!(
        r#"{{"jsonrpc":"2.0","id":{id},"method":"morphir.model-originals.read","params":{params}}}"#
    )
}
fn observed(id: &str, offset: usize, max: usize, ordinal: usize) -> ObservedRead {
    ObservedRead::parse(
        "opening-A",
        ReadEffectKind::Original,
        ordinal,
        &request(id, offset, max),
    )
    .unwrap()
}

#[test]
fn both_rows_match_independently_authored_raw_bytes_and_finish_once() {
    let source = small_source();
    let fixture = InputByteFixture::new("source-A", &source).unwrap();
    let mut run = PeerReadRun::parse(&plan().to_string(), fixture, bounds()).unwrap();
    let expected = controls();
    assert_eq!(
        run.reply(&observed("7", 0, 3, 0)).unwrap(),
        expected["cases"][0]["expected"]["literalRows"][0]
            .as_str()
            .unwrap()
    );
    assert_eq!(
        run.reply(&observed("8", 3, 3, 1)).unwrap(),
        expected["cases"][0]["expected"]["literalRows"][1]
            .as_str()
            .unwrap()
    );
    assert!(run.reply(&observed("8", 3, 3, 1)).is_err());
}

#[test]
fn maximum_u64_correlation_never_rounds_through_a_number() {
    let source = small_source();
    let fixture = InputByteFixture::new("source-A", &source).unwrap();
    let mut p = plan();
    p["window"]["chunkBytes"] = json!(4);
    p["window"]["rows"] = json!(1);
    p["expectedRequest"]["maxBytes"] = json!(4);
    let mut run = PeerReadRun::parse(&p.to_string(), fixture, bounds()).unwrap();
    let reply = run
        .reply(&observed("18446744073709551615", 0, 4, 0))
        .unwrap();
    assert!(reply.starts_with("{\"jsonrpc\":\"2.0\",\"id\":18446744073709551615 ,"));
    assert!(reply.contains("\"content\":\"AAEC/w==\""));
    assert!(
        ObservedRead::parse(
            "opening-A",
            ReadEffectKind::Original,
            0,
            &request("1e0", 0, 4)
        )
        .is_err()
    );
}

#[test]
fn malformed_global_ranges_versions_and_counts_refuse_before_any_row() {
    let source = small_source();
    for (field, value) in [
        ("rows", json!(0)),
        ("rows", json!(1)),
        ("firstOffset", json!(4)),
        ("afterOffset", json!(5)),
        ("afterOffset", json!(2)),
        ("chunkBytes", json!(0)),
        ("chunkBytes", json!(65537)),
    ] {
        let mut p = plan();
        p["window"][field] = value;
        assert!(
            PeerReadRun::parse(
                &p.to_string(),
                InputByteFixture::new("source-A", &source).unwrap(),
                bounds()
            )
            .is_err(),
            "{field}"
        );
    }
    for (field, value) in [
        ("maxBytes", json!(2)),
        ("contractVersion", json!("0.1.0-draft.2")),
        ("method", json!("morphir.model-originals.release")),
    ] {
        let mut p = plan();
        p["expectedRequest"][field] = value;
        assert!(
            PeerReadRun::parse(
                &p.to_string(),
                InputByteFixture::new("source-A", &source).unwrap(),
                bounds()
            )
            .is_err(),
            "{field}"
        );
    }
}

#[test]
fn input_fixture_membership_is_distinct_from_expected_output() {
    let source = small_source();
    assert!(InputByteFixture::new("expected:verified-originals", &source).is_err());
    let mut p = plan();
    p["source"] = json!("source-B");
    assert!(
        PeerReadRun::parse(
            &p.to_string(),
            InputByteFixture::new("source-A", &source).unwrap(),
            bounds()
        )
        .is_err()
    );
}

#[test]
fn wrong_effect_kind_attempt_ordinal_or_request_cannot_expand_or_advance() {
    let source = small_source();
    let mut run = PeerReadRun::parse(
        &plan().to_string(),
        InputByteFixture::new("source-A", &source).unwrap(),
        bounds(),
    )
    .unwrap();
    for value in [
        ObservedRead::parse(
            "opening-B",
            ReadEffectKind::Original,
            0,
            &request("7", 0, 3),
        )
        .unwrap(),
        ObservedRead::parse(
            "opening-A",
            ReadEffectKind::Projection,
            0,
            &request("7", 0, 3),
        )
        .unwrap(),
        observed("7", 0, 3, 1),
        observed("7", 1, 3, 0),
        observed("7", 0, 2, 0),
    ] {
        assert!(run.reply(&value).is_err());
    }
    assert_eq!(
        run.reply(&observed("7", 0, 3, 0)).unwrap(),
        controls()["cases"][0]["expected"]["literalRows"][0]
    );
}

#[test]
fn full_prefix_and_suffix_leave_the_actual_held_row_explicit() {
    let source = small_source();
    let mut prefix = plan();
    prefix["window"]["afterOffset"] = json!(3);
    prefix["window"]["rows"] = json!(1);
    let mut first = PeerReadRun::parse(
        &prefix.to_string(),
        InputByteFixture::new("source-A", &source).unwrap(),
        bounds(),
    )
    .unwrap();
    assert!(
        first
            .reply(&observed("7", 0, 3, 0))
            .unwrap()
            .contains("\"nextOffset\":3")
    );
    assert!(first.reply(&observed("8", 3, 3, 1)).is_err());
    let mut suffix = plan();
    suffix["window"]["firstOffset"] = json!(3);
    suffix["window"]["rows"] = json!(1);
    suffix["firstOrdinal"] = json!(1);
    let mut last = PeerReadRun::parse(
        &suffix.to_string(),
        InputByteFixture::new("source-A", &source).unwrap(),
        bounds(),
    )
    .unwrap();
    assert!(
        last.reply(&observed("8", 3, 3, 1))
            .unwrap()
            .contains("\"nextOffset\":4")
    );
    // This is literal range proof. Actual cancellation/adoption/cleanup still
    // require the production pending-effect driver; no lifecycle claim here.
}

#[test]
fn all_row_work_is_preflighted_at_exact_and_one_less_bounds() {
    let source = small_source();
    let p = plan().to_string();
    let run = PeerReadRun::parse(
        &p,
        InputByteFixture::new("source-A", &source).unwrap(),
        bounds(),
    )
    .unwrap();
    let work = run.work();
    let exact = PeerReadBounds {
        saved_bytes: p.len(),
        rows: work.rows(),
        window_bytes: work.window_bytes(),
        wire_bytes: work.wire_bytes(),
        observer_bytes: work.observer_bytes(),
    };
    assert!(
        PeerReadRun::parse(
            &p,
            InputByteFixture::new("source-A", &source).unwrap(),
            exact
        )
        .is_ok()
    );
    for small in [
        PeerReadBounds {
            saved_bytes: p.len() - 1,
            ..exact
        },
        PeerReadBounds { rows: 1, ..exact },
        PeerReadBounds {
            window_bytes: 3,
            ..exact
        },
        PeerReadBounds {
            wire_bytes: exact.wire_bytes - 1,
            ..exact
        },
        PeerReadBounds {
            observer_bytes: exact.observer_bytes - 1,
            ..exact
        },
    ] {
        assert!(
            PeerReadRun::parse(
                &p,
                InputByteFixture::new("source-A", &source).unwrap(),
                small
            )
            .is_err()
        );
    }
}

#[test]
fn flat_template_and_numeric_operands_stay_strict_literal_json() {
    let source = small_source();
    for token in [
        "1.00000000000000001",
        "1e1000",
        "-1",
        "{\"$serde_json::private::Number\":\"2\"}",
    ] {
        let p = plan()
            .to_string()
            .replacen("\"rows\":2", &format!("\"rows\":{token}"), 1);
        assert!(
            PeerReadRun::parse(
                &p,
                InputByteFixture::new("source-A", &source).unwrap(),
                bounds()
            )
            .is_err()
        );
    }
    for part in [
        json!({"kind":"literal","text":"x","extra":true}),
        json!({"kind":"segments","parts":[]}),
        json!({"kind":"arbitrary-format","code":"x"}),
    ] {
        let mut p = plan();
        p["replyParts"][0] = part;
        assert!(
            PeerReadRun::parse(
                &p.to_string(),
                InputByteFixture::new("source-A", &source).unwrap(),
                bounds()
            )
            .is_err()
        );
    }
    let p = plan()
        .to_string()
        .replacen("\"rows\":2", "\"rows\":2,\"rows\":2", 1);
    assert!(
        PeerReadRun::parse(
            &p,
            InputByteFixture::new("source-A", &source).unwrap(),
            bounds()
        )
        .is_err()
    );
}

#[test]
fn byte_windows_cross_atomic_patterns_without_expanding_the_source() {
    let bytes=FixtureBytes::parse(r#"{"kind":"concat","parts":[{"kind":"repeat-u8","byte":7,"length":2},{"kind":"cycle-u8","seed":254,"length":4},{"kind":"hex","hex":"aabb"},{"kind":"utf8","text":"é"}]}"#,FixtureByteLimits::new(1024,10,4).unwrap()).unwrap();
    let mut target = [0; 7];
    bytes.fill_window(1, &mut target).unwrap();
    assert_eq!(target, [7, 254, 255, 0, 1, 170, 187]);
    let mut unicode = [0; 2];
    bytes.fill_window(8, &mut unicode).unwrap();
    assert_eq!(unicode, [195, 169]);
    let mut unchanged = [42; 3];
    assert!(bytes.fill_window(8, &mut unchanged).is_err());
    assert_eq!(unchanged, [42; 3]);
    assert!(bytes.fill_window(usize::MAX, &mut unchanged).is_err());
    assert_eq!(unchanged, [42; 3]);
    bytes.fill_window(10, &mut []).unwrap();
}

#[test]
fn repeated_payload_slots_each_contribute_to_observer_work() {
    let source = small_source();
    let mut p = plan();
    p["window"]["chunkBytes"] = json!(4);
    p["window"]["rows"] = json!(1);
    p["expectedRequest"]["maxBytes"] = json!(4);
    p["replyParts"] = json!([
        {"kind":"literal","text":"abc"},
        {"kind":"base64-window"},
        {"kind":"base64-window"}
    ]);
    let input = p.to_string();
    let mut run = PeerReadRun::parse(
        &input,
        InputByteFixture::new("source-A", &source).unwrap(),
        bounds(),
    )
    .unwrap();
    // 3*4 input visits + 8 base64 bytes + 2*19 full-frame visits.
    assert_eq!(run.work().observer_bytes(), 58);
    assert_eq!(
        run.reply(&observed("7", 0, 4, 0)).unwrap(),
        "abcAAEC/w==AAEC/w=="
    );
    let denied = PeerReadBounds {
        observer_bytes: 57,
        ..bounds()
    };
    assert!(
        PeerReadRun::parse(
            &input,
            InputByteFixture::new("source-A", &source).unwrap(),
            denied
        )
        .is_err()
    );
}

#[test]
fn all_independent_successor_range_controls_preserve_their_expected_outcomes() {
    let cases: Value = serde_json::from_str(include_str!(
        "../../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/peer-read-runs-v2.json"
    ))
    .unwrap();
    let source = small_source();
    for case in &cases["cases"].as_array().unwrap()[..6] {
        let input = &case["input"];
        let mut p = plan();
        for (target, source) in [
            ("firstOffset", "O"),
            ("afterOffset", "E"),
            ("chunkBytes", "C"),
            ("rows", "R"),
        ] {
            p["window"][target] = input[source].clone();
        }
        p["expectedRequest"]["maxBytes"] = input["maxBytes"].clone();
        if let Some(version) = input.get("contractVersion") {
            p["expectedRequest"]["contractVersion"] = version.clone();
        }
        let result = PeerReadRun::parse(
            &p.to_string(),
            InputByteFixture::new("source-A", &source).unwrap(),
            bounds(),
        );
        assert_eq!(
            result.is_ok(),
            case["expected"]["preflightAccepted"] == true,
            "{}",
            case["id"]
        );
    }
}

#[test]
fn original_and_projection_runs_preflight_both_full_64mib_streams() {
    let source = FixtureBytes::parse(
        r#"{"kind":"chunk-indexed-u8","seed":0,"length":67108864}"#,
        FixtureByteLimits::new(1024, 67108864, 1).unwrap(),
    )
    .unwrap();
    let mut p = plan();
    p["window"] = json!({"firstOffset":0,"afterOffset":67108864,"chunkBytes":65536,"rows":1024});
    p["expectedRequest"]["maxBytes"] = json!(65536);
    p["replyParts"] = json!([{"kind":"base64-window"}]);
    let original = PeerReadRun::parse(
        &p.to_string(),
        InputByteFixture::new("source-A", &source).unwrap(),
        bounds(),
    )
    .unwrap();
    p["effectKind"] = json!("read-projection");
    p["expectedRequest"]["target"] = json!({"kind":"semantic-projection"});
    let mut projection = PeerReadRun::parse(
        &p.to_string(),
        InputByteFixture::new("source-A", &source).unwrap(),
        bounds(),
    )
    .unwrap();
    assert_eq!(original.work().rows() + projection.work().rows(), 2048);
    assert_eq!(
        original.work().window_bytes() + projection.work().window_bytes(),
        134217728
    );
    assert_eq!(
        original.work().wire_bytes() + projection.work().wire_bytes() - 2048 * 16384,
        178962432
    );
    let raw = r#"{"jsonrpc":"2.0","id":9,"method":"morphir.model-originals.read","params":{"contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":{"kind":"semantic-projection"},"offset":0,"maxBytes":65536}}"#;
    let row = ObservedRead::parse("opening-A", ReadEffectKind::Projection, 0, raw).unwrap();
    assert_eq!(row.raw_request(), raw);
    let rendered = projection.reply(&row).unwrap();
    assert_eq!(rendered.len(), 87384);
    assert!(rendered[..87382].bytes().all(|byte| byte == b'A'));
    assert_eq!(&rendered[87382..], "==");
    let mut crossing = [0; 4];
    source.fill_window(65534, &mut crossing).unwrap();
    assert_eq!(crossing, [0, 0, 1, 1]);
}
