//! Saved transcript controls use independent peers; no runtime is qualified.
use morphir_mck::workbench::model_originals::{
    CaptureCompletion, ConnectedCaptureExpectation, ExpectedBytes, ExpectedOriginalEntry,
    ExpectedOriginals, ExpectedProjection, ExpectedProjectionState, ProjectionRefusal,
    ProjectionWorkLimits, Request, SessionId, Transcript, TranscriptLimits,
};
use serde_json::{Value, json};

fn packet() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/wire49.json"
    ))
    .unwrap()
}
fn literal(text: String) -> Value {
    json!({"kind":"literal","text":text})
}
fn exchange(method: &str, params: Value, result: Value) -> Value {
    json!({"request":json!({"jsonrpc":"2.0","id":1,"method":format!("morphir.model-originals.{method}"),"params":params}).to_string(),"reply":literal(json!({"jsonrpc":"2.0","id":1,"result":result}).to_string())})
}
fn fixture() -> Value {
    let packet = packet();
    let mut exchanges = vec![
        json!({"request":packet["cases"][0]["input"]["request"].to_string(),"reply":literal(json!({"jsonrpc":"2.0","id":1,"result":packet["cases"][0]["expected"]["summary"]}).to_string())}),
    ];
    for i in 0..2 {
        exchanges.push(exchange("inventory",json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","startIndex":i*2,"maxEntries":2}),packet["cases"][1]["input"]["pages"][i].clone()));
    }
    for (target, chunk) in [
        (
            json!({"kind":"original","entryId":"entry-model"}),
            packet["cases"][11]["expected"]["chunk"].clone(),
        ),
        (json!({"kind":"original","entryId":"entry-opaque"}), {
            let mut chunk = packet["cases"][11]["expected"]["chunk"].clone();
            chunk["target"] = json!({"kind":"original","entryId":"entry-opaque"});
            chunk["content"] = json!("AAEC/w==");
            chunk["nextOffset"] = json!(4);
            chunk
        }),
        (
            json!({"kind":"semantic-projection"}),
            packet["cases"][12]["expected"]["chunk"].clone(),
        ),
    ] {
        exchanges.push(exchange("read",json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":target,"offset":0,"maxBytes":65536}),chunk));
    }
    let release = exchange(
        "release",
        json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A"}),
        json!({"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","captureId":"capture-A","status":"released"}),
    );
    exchanges.extend([release.clone(), release]);
    json!({"exchanges":exchanges})
}
fn limits() -> TranscriptLimits {
    TranscriptLimits::new(16 * 1024 * 1024, 256 * 1024 * 1024, 4096).unwrap()
}
fn check(value: &Value, session: &str, completion: CaptureCompletion) -> Result<(), String> {
    let packet = packet();
    let model = packet["cases"][0]["input"]["sourceFiles"][0]["content"]
        .as_str()
        .unwrap();
    let originals = ExpectedOriginals::new(vec![
        ExpectedOriginalEntry::file(
            "morphir-ir.json",
            ExpectedBytes::literal(model.as_bytes()).unwrap(),
        )
        .unwrap(),
        ExpectedOriginalEntry::directory("notes").unwrap(),
        ExpectedOriginalEntry::directory("notes/empty").unwrap(),
        ExpectedOriginalEntry::file(
            "notes/opaque.bin",
            ExpectedBytes::literal(&[0, 1, 2, 255]).unwrap(),
        )
        .unwrap(),
    ])
    .unwrap();
    let projection = ExpectedProjection::json(r#"{"formatVersion":4,"distribution":{"Library":{"packageName":"pricing","dependencies":{},"def":{"modules":{}}}}}"#, ProjectionWorkLimits::new(1024*1024,1000).unwrap()).unwrap();
    let request = Request::parse(&packet["cases"][0]["input"]["request"].to_string()).unwrap();
    let session = SessionId::new(session).unwrap();
    let expected = ConnectedCaptureExpectation::new(
        &session,
        &request,
        &originals,
        ExpectedProjectionState::Available(&projection),
        completion,
    )
    .map_err(|e| e.to_string())?;
    let transcript = Transcript::parse(&value.to_string(), limits()).map_err(|e| e.to_string())?;
    let checked = transcript.verify(&expected).map_err(|e| e.to_string())?;
    assert_eq!(checked.originals().inventory().source_byte_length(), 120);
    assert_eq!(checked.projection().unwrap().byte_length(), 111);
    assert_eq!(checked.completion(), completion);
    Ok(())
}

#[test]
fn complete_raw_transcript_joins_independent_source_semantics_and_release() {
    check(&fixture(), "session-A", CaptureCompletion::ReleasedTwice).unwrap();
    let mut fixture = fixture();
    fixture["exchanges"].as_array_mut().unwrap().truncate(6);
    check(&fixture, "session-A", CaptureCompletion::Retained).unwrap();
    fixture["exchanges"]
        .as_array_mut()
        .unwrap()
        .push(super_release());
    check(&fixture, "session-A", CaptureCompletion::Released).unwrap();
}
fn super_release() -> Value {
    fixture()["exchanges"][6].clone()
}

#[test]
fn compact_replies_preserve_the_actual_bytes() {
    let mut fixture = fixture();
    for exchange in fixture["exchanges"].as_array_mut().unwrap() {
        let reply = exchange["reply"]["text"].as_str().unwrap().to_owned();
        let split = reply.find(',').unwrap();
        exchange["reply"] = json!({"kind":"segments","parts":[{"kind":"literal","text":&reply[..split]},{"kind":"repeat","text":",","count":1},{"kind":"literal","text":&reply[split+1..]}]});
    }
    check(&fixture, "session-A", CaptureCompletion::ReleasedTwice).unwrap();
}

#[test]
fn current_request_session_and_stream_order_are_not_taken_from_the_peer() {
    assert!(
        check(
            &fixture(),
            "other-session",
            CaptureCompletion::ReleasedTwice
        )
        .is_err()
    );
    for (left, right) in [(0, 1), (1, 3), (2, 3), (3, 5), (5, 6)] {
        let mut changed = fixture();
        changed["exchanges"]
            .as_array_mut()
            .unwrap()
            .swap(left, right);
        assert!(
            check(&changed, "session-A", CaptureCompletion::ReleasedTwice).is_err(),
            "{left}/{right}"
        );
    }
    let mut changed = fixture();
    let raw = changed["exchanges"][0]["request"]
        .as_str()
        .unwrap()
        .replace("workspace:orders", "workspace:other");
    changed["exchanges"][0]["request"] = json!(raw);
    assert!(check(&changed, "session-A", CaptureCompletion::ReleasedTwice).is_err());
}

#[test]
fn missing_extra_duplicate_and_substituted_evidence_are_refused() {
    for index in 0..8 {
        let mut changed = fixture();
        changed["exchanges"].as_array_mut().unwrap().remove(index);
        assert!(
            check(&changed, "session-A", CaptureCompletion::ReleasedTwice).is_err(),
            "missing{index}"
        );
    }
    for index in [0, 1, 3, 5, 6] {
        let mut changed = fixture();
        let extra = changed["exchanges"][index].clone();
        changed["exchanges"]
            .as_array_mut()
            .unwrap()
            .insert(index, extra);
        assert!(
            check(&changed, "session-A", CaptureCompletion::ReleasedTwice).is_err(),
            "duplicate{index}"
        );
    }
    let mut changed = fixture();
    changed["exchanges"][4] = changed["exchanges"][5].clone();
    assert!(check(&changed, "session-A", CaptureCompletion::ReleasedTwice).is_err());
}

#[test]
fn release_requires_exact_closed_reply_rpc_identity_capture_and_count() {
    for field in ["captureId", "status", "profile", "contractVersion"] {
        let mut changed = fixture();
        let mut reply: Value =
            serde_json::from_str(changed["exchanges"][6]["reply"]["text"].as_str().unwrap())
                .unwrap();
        reply["result"][field] = json!("wrong");
        changed["exchanges"][6]["reply"] = literal(reply.to_string());
        assert!(
            check(&changed, "session-A", CaptureCompletion::ReleasedTwice).is_err(),
            "{field}"
        );
    }
    for reply in [
        json!({"jsonrpc":"2.0","id":2,"result":{"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","captureId":"capture-A","status":"released"}}),
        json!({"jsonrpc":"2.0","id":1,"result":{"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","captureId":"capture-A","status":"released","extra":true}}),
    ] {
        let mut changed = fixture();
        changed["exchanges"][7]["reply"] = literal(reply.to_string());
        assert!(check(&changed, "session-A", CaptureCompletion::ReleasedTwice).is_err());
    }
    assert!(check(&fixture(), "session-A", CaptureCompletion::Released).is_err());
    assert!(check(&fixture(), "session-A", CaptureCompletion::Retained).is_err());
}

#[test]
fn all_transcript_resource_bounds_are_preflighted_at_exact_limits() {
    let fixture = fixture();
    let text = fixture.to_string();
    let bytes: usize = fixture["exchanges"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["request"].as_str().unwrap().len() + e["reply"]["text"].as_str().unwrap().len())
        .sum();
    Transcript::parse(&text, TranscriptLimits::new(text.len(), bytes, 8).unwrap()).unwrap();
    for (saved, expanded, count) in [
        (text.len() - 1, bytes, 8),
        (text.len(), bytes - 1, 8),
        (text.len(), bytes, 7),
    ] {
        assert!(
            Transcript::parse(
                &text,
                TranscriptLimits::new(saved, expanded, count).unwrap()
            )
            .is_err()
        );
    }
    for (saved, expanded, count) in [(0, 1, 1), (1, 0, 1), (1, 1, 0)] {
        assert!(TranscriptLimits::new(saved, expanded, count).is_err());
    }
}

#[test]
fn malformed_recipe_counts_shapes_and_expansion_overflow_cannot_be_laundered() {
    for part in [
        json!({"kind":"repeat","text":"","count":1}),
        json!({"kind":"repeat","text":"x","count":0}),
        json!({"kind":"repeat","text":"xx","count":u64::MAX}),
        json!({"kind":"repeat","text":"x","count":1.0}),
        json!({"kind":"repeat","text":"x","count":{"$serde_json::private::Number":"1"}}),
        json!({"kind":"literal","text":"x","extra":true}),
    ] {
        let mut changed = fixture();
        changed["exchanges"][0]["reply"] = json!({"kind":"segments","parts":[part]});
        assert!(Transcript::parse(&changed.to_string(), limits()).is_err());
    }
    for text in [
        r#"{"exchanges":[],"exchanges":[]}"#,
        r#"{"exchanges":[],"extra":true}"#,
    ] {
        assert!(Transcript::parse(text, limits()).is_err());
    }
}

#[test]
fn projection_expectation_and_capture_semantic_mode_form_a_closed_choice() {
    let request = Request::parse(&packet()["cases"][0]["input"]["request"].to_string()).unwrap();
    let source =
        ExpectedOriginals::new(vec![ExpectedOriginalEntry::directory("a").unwrap()]).unwrap();
    let session = SessionId::new("session-A").unwrap();
    assert!(
        ConnectedCaptureExpectation::new(
            &session,
            &request,
            &source,
            ExpectedProjectionState::NotRequested,
            CaptureCompletion::Retained
        )
        .is_err()
    );
    for reason in [ProjectionRefusal::InvalidModel, ProjectionRefusal::Capacity] {
        assert!(
            ConnectedCaptureExpectation::new(
                &session,
                &request,
                &source,
                ExpectedProjectionState::Unavailable(reason),
                CaptureCompletion::Retained
            )
            .is_ok()
        );
    }
}

#[test]
fn unavailable_projection_preserves_verified_originals_and_exact_refusal() {
    let packet = packet();
    let model = packet["cases"][0]["input"]["sourceFiles"][0]["content"]
        .as_str()
        .unwrap();
    let source = ExpectedOriginals::new(vec![
        ExpectedOriginalEntry::file(
            "morphir-ir.json",
            ExpectedBytes::literal(model.as_bytes()).unwrap(),
        )
        .unwrap(),
        ExpectedOriginalEntry::directory("notes").unwrap(),
        ExpectedOriginalEntry::directory("notes/empty").unwrap(),
        ExpectedOriginalEntry::file(
            "notes/opaque.bin",
            ExpectedBytes::literal(&[0, 1, 2, 255]).unwrap(),
        )
        .unwrap(),
    ])
    .unwrap();
    let session = SessionId::new("session-A").unwrap();
    for (semantic, status, expected_state) in [
        (
            "projection",
            json!({"status":"unavailable","reason":"capacity"}),
            ExpectedProjectionState::Unavailable(ProjectionRefusal::Capacity),
        ),
        (
            "projection",
            json!({"status":"unavailable","reason":"invalid_model"}),
            ExpectedProjectionState::Unavailable(ProjectionRefusal::InvalidModel),
        ),
        (
            "none",
            json!({"status":"not-requested"}),
            ExpectedProjectionState::NotRequested,
        ),
    ] {
        let mut fixture = fixture();
        fixture["exchanges"].as_array_mut().unwrap().remove(5);
        let mut request = packet["cases"][0]["input"]["request"].clone();
        request["params"]["semantic"] = json!(semantic);
        fixture["exchanges"][0]["request"] = json!(request.to_string());
        let request = Request::parse(&request.to_string()).unwrap();
        let mut ready: Value =
            serde_json::from_str(fixture["exchanges"][0]["reply"]["text"].as_str().unwrap())
                .unwrap();
        ready["result"]["projection"] = status;
        fixture["exchanges"][0]["reply"] = literal(ready.to_string());
        let transcript = Transcript::parse(&fixture.to_string(), limits()).unwrap();
        let expected = ConnectedCaptureExpectation::new(
            &session,
            &request,
            &source,
            expected_state,
            CaptureCompletion::ReleasedTwice,
        )
        .unwrap();
        let checked = transcript.verify(&expected).unwrap();
        assert_eq!(checked.originals().inventory().source_byte_length(), 120);
        assert!(checked.projection().is_none());
        if semantic == "projection" {
            let wrong = ConnectedCaptureExpectation::new(
                &session,
                &request,
                &source,
                ExpectedProjectionState::Unavailable(ProjectionRefusal::Timeout),
                CaptureCompletion::ReleasedTwice,
            )
            .unwrap();
            assert!(transcript.verify(&wrong).is_err());
        }
    }
}

#[test]
fn self_consistent_actual_projection_still_requires_independent_semantics() {
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    use sha2::{Digest, Sha256};
    let mut fixture = fixture();
    let mut actual: Value =
        serde_json::from_str(fixture["exchanges"][5]["reply"]["text"].as_str().unwrap()).unwrap();
    let actual_json = String::from_utf8(
        STANDARD
            .decode(actual["result"]["content"].as_str().unwrap())
            .unwrap(),
    )
    .unwrap()
    .replace("pricing", "pricinx");
    actual["result"]["content"] = json!(STANDARD.encode(&actual_json));
    fixture["exchanges"][5]["reply"] = literal(actual.to_string());
    let mut ready: Value =
        serde_json::from_str(fixture["exchanges"][0]["reply"]["text"].as_str().unwrap()).unwrap();
    ready["result"]["projection"]["sha256"] = json!(
        Sha256::digest(actual_json.as_bytes())
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>()
    );
    fixture["exchanges"][0]["reply"] = literal(ready.to_string());
    assert!(check(&fixture, "session-A", CaptureCompletion::ReleasedTwice).is_err());
}

#[test]
fn exact_request_and_reply_frame_bounds_count_actual_utf8_before_expansion() {
    let mut changed = fixture();
    let reply = changed["exchanges"][0]["reply"]["text"]
        .as_str()
        .unwrap()
        .to_owned();
    for count in [128 * 1024 - reply.len(), 128 * 1024 - reply.len() + 1] {
        changed["exchanges"][0]["reply"] = json!({"kind":"segments","parts":[{"kind":"literal","text":reply},{"kind":"repeat","text":" ","count":count}]});
        if count + reply.len() == 128 * 1024 {
            check(&changed, "session-A", CaptureCompletion::ReleasedTwice).unwrap();
        } else {
            assert!(Transcript::parse(&changed.to_string(), limits()).is_err());
        }
    }
    let mut changed = fixture();
    let raw = changed["exchanges"][0]["request"]
        .as_str()
        .unwrap()
        .to_owned();
    changed["exchanges"][0]["request"] =
        json!(format!("{raw}{}", " ".repeat(16 * 1024 - raw.len())));
    check(&changed, "session-A", CaptureCompletion::ReleasedTwice).unwrap();
    changed["exchanges"][0]["request"] = json!(format!(
        "{} ",
        changed["exchanges"][0]["request"].as_str().unwrap()
    ));
    assert!(Transcript::parse(&changed.to_string(), limits()).is_err());
    let mut changed = fixture();
    changed["exchanges"][0]["reply"] =
        json!({"kind":"segments","parts":[{"kind":"repeat","text":"é","count":65537}]});
    assert!(Transcript::parse(&changed.to_string(), limits()).is_err());
}

#[test]
fn full_transcripts_keep_their_closed_literal_json_vocabulary() {
    let mut changed = fixture();
    changed["extra"] = json!(true);
    assert!(Transcript::parse(&changed.to_string(), limits()).is_err());
    let text =
        fixture()
            .to_string()
            .replacen("\"exchanges\":", "\"exchanges\":[],\"exchanges\":", 1);
    assert!(Transcript::parse(&text, limits()).is_err());
    for key in [
        "$serde_json::private::Number",
        "$serde_json::private::RawValue",
    ] {
        let mut changed = fixture();
        changed["exchanges"][0]["request"] = json!({key:"1"});
        assert!(Transcript::parse(&changed.to_string(), limits()).is_err());
    }
}

#[test]
fn actual_64_mib_original_and_projection_have_lossless_saved_transcripts() {
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    use sha2::{Digest, Sha256};
    let packet = packet();
    let length = 67_108_864usize;
    let tail = packet["largeByteRecipes"][0]["tail"].as_str().unwrap();
    let digest = packet["largeByteRecipes"][0]["sha256"].as_str().unwrap();
    let mut inventory = Sha256::new();
    inventory.update(b"morphir/workbench/model-originals/0.1.0-draft.1\0");
    inventory.update(1u32.to_be_bytes());
    inventory.update([1]);
    inventory.update((b"morphir-ir.json".len() as u32).to_be_bytes());
    inventory.update(b"morphir-ir.json");
    inventory.update((length as u64).to_be_bytes());
    for pair in digest.as_bytes().as_chunks::<2>().0 {
        inventory.update([u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap()]);
    }
    let inventory = inventory
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    let mut summary = packet["cases"][0]["expected"]["summary"].clone();
    summary["coverage"] = json!({"kind":"primary"});
    summary["companions"] = json!([]);
    summary["projection"] = json!({"status":"available","codec":"morphir-json","byteLength":length,"sha256":digest,"formatVersion":"4.0.0"});
    summary["inventory"] = json!({"entryCount":1,"fileCount":1,"directoryCount":0,"sourceByteLength":length,"sha256":inventory});
    let mut capture = packet["cases"][0]["input"]["request"].clone();
    capture["params"]["scope"] = json!("primary");
    let request = Request::parse(&capture.to_string()).unwrap();
    let mut exchanges = vec![
        json!({"request":capture.to_string(),"reply":literal(json!({"jsonrpc":"2.0","id":1,"result":summary}).to_string())}),
    ];
    exchanges.push(exchange("inventory",json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","startIndex":0,"maxEntries":256}),json!({"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","binding":summary["binding"],"captureId":"capture-A","inventorySha256":inventory,"startIndex":0,"entries":[{"kind":"file","entryId":"entry-model","path":"morphir-ir.json","byteLength":length,"sha256":digest}],"next":{"kind":"complete"}})));
    let mut expanded = 0usize;
    for target in [
        json!({"kind":"original","entryId":"entry-model"}),
        json!({"kind":"semantic-projection"}),
    ] {
        for offset in (0..length).step_by(65536) {
            // Construct each independent actual peer chunk, then losslessly
            // encode its literal text. The checker sees neither this fixture
            // generator nor the source expectation when expanding a reply.
            let mut bytes = vec![b' '; 65536];
            if offset + 65536 == length {
                bytes[65536 - tail.len()..].copy_from_slice(tail.as_bytes());
            }
            let encoded = STANDARD.encode(bytes);
            let run = encoded
                .as_bytes()
                .as_chunks::<4>()
                .0
                .iter()
                .take_while(|part| *part == b"ICAg")
                .count();
            let chunk = json!({"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","binding":summary["binding"],"captureId":"capture-A","target":target,"offset":offset,"nextOffset":offset+65536,"content":encoded});
            let mut event = exchange(
                "read",
                json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":target,"offset":offset,"maxBytes":65536}),
                chunk,
            );
            let raw = event["reply"]["text"].as_str().unwrap().to_owned();
            expanded += raw.len() + event["request"].as_str().unwrap().len();
            let prefix = raw.find(&encoded).unwrap();
            event["reply"] = json!({"kind":"segments","parts":[{"kind":"literal","text":&raw[..prefix]},{"kind":"repeat","text":"ICAg","count":run},{"kind":"literal","text":&raw[prefix+run*4..]}]});
            exchanges.push(event);
        }
    }
    exchanges.push(super_release());
    assert_eq!(exchanges.len(), 2051);
    let saved = json!({"exchanges":exchanges}).to_string();
    assert!(saved.len() < 16 * 1024 * 1024);
    assert!(expanded > 128 * 1024 * 1024);
    let transcript = Transcript::parse(&saved, limits()).unwrap();
    let source = ExpectedOriginals::new(vec![
        ExpectedOriginalEntry::file(
            "morphir-ir.json",
            ExpectedBytes::prefix_tail(b' ', length, tail.as_bytes()).unwrap(),
        )
        .unwrap(),
    ])
    .unwrap();
    let projection = ExpectedProjection::json(
        tail,
        ProjectionWorkLimits::new(128 * 1024 * 1024, 1_000_000).unwrap(),
    )
    .unwrap();
    let session = SessionId::new("session-A").unwrap();
    let expected = ConnectedCaptureExpectation::new(
        &session,
        &request,
        &source,
        ExpectedProjectionState::Available(&projection),
        CaptureCompletion::Released,
    )
    .unwrap();
    let checked = transcript.verify(&expected).unwrap();
    assert_eq!(checked.originals().inventory().source_byte_length(), length);
    assert_eq!(checked.projection().unwrap().byte_length(), length);
    println!(
        "actual original={length} projection={length}; 1024 replies each; saved={} bytes; expanded read frames={expanded} bytes",
        saved.len()
    );
}
