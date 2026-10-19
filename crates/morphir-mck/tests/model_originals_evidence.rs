//! Fixed peers qualify the checker, never a production capture or model owner.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir_mck::workbench::model_originals::{
    CaptureEvidence, EvidenceError, Exchange, ExpectedBytes, ExpectedOriginalEntry,
    ExpectedOriginals, ExpectedProjection, FixtureByteLimits, FixtureBytes, OriginalTransfer,
    Parameters, ProjectionWorkLimits, Request, SessionId,
};
use serde_json::{Value, json};

fn packet() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/wire49.json"
    ))
    .unwrap()
}
fn request(method: &str, params: Value) -> Request {
    Request::parse(&json!({"jsonrpc":"2.0","id":1,"method":format!("morphir.model-originals.{method}"),"params":params}).to_string()).unwrap()
}
fn reply(result: &Value) -> String {
    json!({"jsonrpc":"2.0","id":1,"result":result}).to_string()
}
fn expected<'a>(model: &'a [u8], opaque: &'a [u8]) -> ExpectedOriginals<'a> {
    ExpectedOriginals::new(vec![
        ExpectedOriginalEntry::file("notes/opaque.bin", ExpectedBytes::literal(opaque).unwrap())
            .unwrap(),
        ExpectedOriginalEntry::directory("notes/empty").unwrap(),
        ExpectedOriginalEntry::directory("notes").unwrap(),
        ExpectedOriginalEntry::file("morphir-ir.json", ExpectedBytes::literal(model).unwrap())
            .unwrap(),
    ])
    .unwrap()
}
fn run(
    expected: &ExpectedOriginals<'_>,
    capture_reply: &str,
    include_opaque: bool,
    duplicate_model: bool,
) -> Result<(), EvidenceError> {
    let packet = packet();
    let capture = Request::parse(&packet["cases"][0]["input"]["request"].to_string()).unwrap();
    let page_requests=[0,2].map(|start| request("inventory",json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","startIndex":start,"maxEntries":2})));
    let page_replies = [0, 1].map(|i| reply(&packet["cases"][1]["input"]["pages"][i]));
    let pages = [0, 1].map(|i| Exchange {
        request: &page_requests[i],
        reply: &page_replies[i],
    });
    let read_requests=["entry-model","entry-opaque"].map(|id| request("read",json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":{"kind":"original","entryId":id},"offset":0,"maxBytes":65536})));
    let mut opaque = packet["cases"][11]["expected"]["chunk"].clone();
    opaque["target"]["entryId"] = json!("entry-opaque");
    opaque["content"] = json!("AAEC/w==");
    opaque["nextOffset"] = json!(4);
    let read_replies = [
        reply(&packet["cases"][11]["expected"]["chunk"]),
        reply(&opaque),
    ];
    let reads = [0, 1].map(|i| {
        [Exchange {
            request: &read_requests[i],
            reply: &read_replies[i],
        }]
    });
    let Parameters::Read {
        target: morphir_mck::workbench::model_originals::ReadTarget::Original { entry: model },
        ..
    } = read_requests[0].parameters()
    else {
        panic!()
    };
    let Parameters::Read {
        target: morphir_mck::workbench::model_originals::ReadTarget::Original { entry: opaque },
        ..
    } = read_requests[1].parameters()
    else {
        panic!()
    };
    let mut originals = vec![OriginalTransfer {
        entry: model,
        exchanges: &reads[0],
    }];
    if include_opaque {
        originals.push(OriginalTransfer {
            entry: opaque,
            exchanges: &reads[1],
        });
    }
    if duplicate_model {
        originals.push(OriginalTransfer {
            entry: model,
            exchanges: &reads[0],
        });
    }
    let checked = expected.verify(
        &SessionId::new("session-A").unwrap(),
        CaptureEvidence {
            capture: Exchange {
                request: &capture,
                reply: capture_reply,
            },
            pages: &pages,
            originals: &originals,
        },
    )?;
    assert_eq!(checked.inventory().source_byte_length(), 120);
    assert_eq!(checked.inventory().entries().len(), 4);
    Ok(())
}
fn model_bytes(packet: &Value) -> Vec<u8> {
    STANDARD
        .decode(
            packet["cases"][11]["expected"]["chunk"]["content"]
                .as_str()
                .unwrap(),
        )
        .unwrap()
}

#[test]
fn complete_capture_matches_independently_authored_files_and_empty_directories() {
    let packet = packet();
    let model = model_bytes(&packet);
    let expected = expected(&model, &[0, 1, 2, 255]);
    run(
        &expected,
        &reply(&packet["cases"][0]["expected"]["summary"]),
        true,
        false,
    )
    .unwrap();
}

#[test]
fn flat_fixture_bytes_feed_the_actual_source_correspondence_check() {
    let packet = packet();
    let model = model_bytes(&packet);
    let opaque = FixtureBytes::parse(
        r#"{"kind":"concat","parts":[{"kind":"cycle-u8","seed":0,"length":3},{"kind":"hex","hex":"ff"}]}"#,
        FixtureByteLimits::new(1024, 4, 2).unwrap(),
    ).unwrap();
    let originals = ExpectedOriginals::new(vec![
        ExpectedOriginalEntry::file("morphir-ir.json", ExpectedBytes::literal(&model).unwrap())
            .unwrap(),
        ExpectedOriginalEntry::directory("notes").unwrap(),
        ExpectedOriginalEntry::directory("notes/empty").unwrap(),
        ExpectedOriginalEntry::file("notes/opaque.bin", opaque.expected().unwrap()).unwrap(),
    ])
    .unwrap();
    run(
        &originals,
        &reply(&packet["cases"][0]["expected"]["summary"]),
        true,
        false,
    )
    .unwrap();
}

#[test]
fn self_consistent_peer_bytes_do_not_replace_independent_expected_originals() {
    let packet = packet();
    let mut model = model_bytes(&packet);
    model[0] = b'x';
    let expected = expected(&model, &[0, 1, 2, 255]);
    assert!(matches!(
        run(
            &expected,
            &reply(&packet["cases"][0]["expected"]["summary"]),
            true,
            false
        ),
        Err(EvidenceError::Bytes)
    ));
}

#[test]
fn every_original_is_required_once() {
    let packet = packet();
    let model = model_bytes(&packet);
    let expected = expected(&model, &[0, 1, 2, 255]);
    let capture = reply(&packet["cases"][0]["expected"]["summary"]);
    for (opaque, duplicate) in [(false, false), (true, true)] {
        assert!(matches!(
            run(&expected, &capture, opaque, duplicate),
            Err(EvidenceError::OriginalSet)
        ));
    }
}

#[test]
fn directories_and_original_projection_roles_cannot_be_omitted_or_confused() {
    let packet = packet();
    let model = model_bytes(&packet);
    for entries in [
        vec![
            ExpectedOriginalEntry::file("morphir-ir.json", ExpectedBytes::literal(&model).unwrap())
                .unwrap(),
        ],
        vec![
            ExpectedOriginalEntry::directory("morphir-ir.json").unwrap(),
            ExpectedOriginalEntry::directory("notes").unwrap(),
            ExpectedOriginalEntry::directory("notes/empty").unwrap(),
            ExpectedOriginalEntry::file(
                "notes/opaque.bin",
                ExpectedBytes::literal(&[0, 1, 2, 255]).unwrap(),
            )
            .unwrap(),
        ],
    ] {
        let expected = ExpectedOriginals::new(entries).unwrap();
        assert!(matches!(
            run(
                &expected,
                &reply(&packet["cases"][0]["expected"]["summary"]),
                true,
                false
            ),
            Err(EvidenceError::EntrySet)
        ));
    }
    let projection = STANDARD
        .decode(
            packet["cases"][12]["expected"]["chunk"]["content"]
                .as_str()
                .unwrap(),
        )
        .unwrap();
    let expected = expected(&projection, &[0, 1, 2, 255]);
    assert!(matches!(
        run(
            &expected,
            &reply(&packet["cases"][0]["expected"]["summary"]),
            true,
            false
        ),
        Err(EvidenceError::Bytes)
    ));
}

#[test]
fn capture_envelope_identity_and_session_are_checked_before_transfer() {
    let packet = packet();
    let model = model_bytes(&packet);
    let expected = expected(&model, &[0, 1, 2, 255]);
    let summary = &packet["cases"][0]["expected"]["summary"];
    let raw = reply(summary);
    for changed in [
        raw.replacen("\"id\":1,", "\"id\":2,", 1),
        raw.replacen("\"id\":1,", "\"id\":1.0,", 1),
        raw.replacen("session-A", "session-B", 1),
        raw.replacen(
            "\"jsonrpc\":\"2.0\"",
            "\"jsonrpc\":\"2.0\",\"jsonrpc\":\"2.0\"",
            1,
        ),
        json!({"jsonrpc":"2.0","id":1,"result":summary,"extra":0}).to_string(),
    ] {
        assert!(
            run(&expected, &changed, true, false).is_err(),
            "accepted {changed}"
        );
    }
}

#[test]
fn compact_byte_recipes_keep_the_source_boundary_without_expansion() {
    let maximum = 64 * 1024 * 1024;
    for bytes in [
        ExpectedBytes::repeat(255, maximum).unwrap(),
        ExpectedBytes::cycle(7, maximum).unwrap(),
        ExpectedBytes::chunk_indexed(11, maximum).unwrap(),
    ] {
        ExpectedOriginals::new(vec![ExpectedOriginalEntry::file("source", bytes).unwrap()])
            .unwrap();
    }
    assert!(ExpectedBytes::repeat(0, maximum + 1).is_err());
    assert!(
        ExpectedOriginals::new(vec![
            ExpectedOriginalEntry::file("a", ExpectedBytes::repeat(0, maximum).unwrap()).unwrap(),
            ExpectedOriginalEntry::file("b", ExpectedBytes::repeat(0, 1).unwrap()).unwrap()
        ])
        .is_err()
    );
    assert!(
        ExpectedOriginals::new(vec![
            ExpectedOriginalEntry::directory("a").unwrap(),
            ExpectedOriginalEntry::directory("a").unwrap()
        ])
        .is_err()
    );
    for path in ["../escape", "/absolute", "a//b", "a/CON"] {
        assert!(ExpectedOriginalEntry::directory(path).is_err());
    }
    assert!(ExpectedBytes::prefix_tail(b' ', 2, b"tail").is_err());
}

#[test]
fn unavailable_projection_still_allows_complete_original_byte_evidence() {
    let packet = packet();
    let model = model_bytes(&packet);
    let expected = expected(&model, &[0, 1, 2, 255]);
    let mut summary = packet["cases"][0]["expected"]["summary"].clone();
    summary["projection"] = json!({"status":"unavailable","reason":"invalid_model"});
    run(&expected, &reply(&summary), true, false).unwrap();
}

#[test]
fn compact_recipes_compare_actual_bytes_and_refuse_changes() {
    let packet = packet();
    let model = model_bytes(&packet);
    // The existing four-byte opaque file distinguishes wrapping-cycle,
    // repeated-byte, chunk-indexed and literal-tail expectations.
    for (index, bytes) in [
        ExpectedBytes::cycle(0, 4).unwrap(),
        ExpectedBytes::repeat(0, 4).unwrap(),
        ExpectedBytes::chunk_indexed(0, 4).unwrap(),
        ExpectedBytes::prefix_tail(0, 4, &[1, 2, 255]).unwrap(),
    ]
    .into_iter()
    .enumerate()
    {
        let expected = ExpectedOriginals::new(vec![
            ExpectedOriginalEntry::file("morphir-ir.json", ExpectedBytes::literal(&model).unwrap())
                .unwrap(),
            ExpectedOriginalEntry::directory("notes").unwrap(),
            ExpectedOriginalEntry::directory("notes/empty").unwrap(),
            ExpectedOriginalEntry::file("notes/opaque.bin", bytes).unwrap(),
        ])
        .unwrap();
        let result = run(
            &expected,
            &reply(&packet["cases"][0]["expected"]["summary"]),
            true,
            false,
        );
        // Only the source-authored prefix plus tail is the actual 00 01 02 ff.
        if index == 3 {
            result.unwrap();
        } else {
            assert!(matches!(result, Err(EvidenceError::Bytes)));
        }
    }
}

#[test]
fn actual_64_mib_original_verifies_against_the_frozen_compact_recipe() {
    use sha2::{Digest, Sha256};
    let packet = packet();
    let recipe = &packet["largeByteRecipes"][0];
    let length = 67_108_864usize;
    let tail = recipe["tail"].as_str().unwrap().as_bytes();
    let source_digest = recipe["sha256"].as_str().unwrap();
    // Independently encode the public inventory preimage, not a checker helper.
    let mut inventory_hash = Sha256::new();
    inventory_hash.update(b"morphir/workbench/model-originals/0.1.0-draft.1\0");
    inventory_hash.update(1u32.to_be_bytes());
    inventory_hash.update([1]);
    inventory_hash.update(
        u32::try_from(b"morphir-ir.json".len())
            .unwrap()
            .to_be_bytes(),
    );
    inventory_hash.update(b"morphir-ir.json");
    inventory_hash.update((length as u64).to_be_bytes());
    for pair in source_digest.as_bytes().as_chunks::<2>().0 {
        inventory_hash
            .update([u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap()]);
    }
    let inventory_digest = inventory_hash
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    let mut summary = packet["cases"][0]["expected"]["summary"].clone();
    summary["coverage"] = json!({"kind":"primary"});
    summary["companions"] = json!([]);
    summary["projection"] = json!({"status":"available","codec":"morphir-json","byteLength":length,"sha256":source_digest,"formatVersion":"4.0.0"});
    summary["inventory"] = json!({"entryCount":1,"fileCount":1,"directoryCount":0,"sourceByteLength":length,"sha256":inventory_digest});
    let mut capture = packet["cases"][0]["input"]["request"].clone();
    capture["params"]["scope"] = json!("primary");
    capture["params"]["semantic"] = json!("projection");
    let capture = Request::parse(&capture.to_string()).unwrap();
    let capture_reply = reply(&summary);
    let page = request(
        "inventory",
        json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","startIndex":0,"maxEntries":256}),
    );
    let page_reply = reply(
        &json!({"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","binding":summary["binding"],"captureId":"capture-A","inventorySha256":inventory_digest,"startIndex":0,"entries":[{"kind":"file","entryId":"entry-model","path":"morphir-ir.json","byteLength":length,"sha256":source_digest}],"next":{"kind":"complete"}}),
    );
    let mut requests = Vec::new();
    let mut replies = Vec::new();
    for offset in (0..length).step_by(65536) {
        requests.push(request("read",json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":{"kind":"original","entryId":"entry-model"},"offset":offset,"maxBytes":65536})));
        let mut bytes = vec![b' '; 65536];
        if offset + 65536 == length {
            bytes[65536 - tail.len()..].copy_from_slice(tail);
        }
        replies.push(reply(&json!({"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","binding":summary["binding"],"captureId":"capture-A","target":{"kind":"original","entryId":"entry-model"},"offset":offset,"nextOffset":offset+65536,"content":STANDARD.encode(bytes)})));
    }
    let reads = requests
        .iter()
        .zip(&replies)
        .map(|(request, reply)| Exchange { request, reply })
        .collect::<Vec<_>>();
    let Parameters::Read {
        target: morphir_mck::workbench::model_originals::ReadTarget::Original { entry },
        ..
    } = requests[0].parameters()
    else {
        panic!()
    };
    let expected = ExpectedOriginals::new(vec![
        ExpectedOriginalEntry::file(
            "morphir-ir.json",
            ExpectedBytes::prefix_tail(b' ', length, tail).unwrap(),
        )
        .unwrap(),
    ])
    .unwrap();
    let checked = expected
        .verify(
            &SessionId::new("session-A").unwrap(),
            CaptureEvidence {
                capture: Exchange {
                    request: &capture,
                    reply: &capture_reply,
                },
                pages: &[Exchange {
                    request: &page,
                    reply: &page_reply,
                }],
                originals: &[OriginalTransfer {
                    entry,
                    exchanges: &reads,
                }],
            },
        )
        .unwrap();
    assert_eq!(checked.inventory().source_byte_length(), length);
    assert_eq!(reads.len(), 1024);
    drop(reads);
    drop(replies);
    drop(requests);
    // A second real64MiB transfer uses the independent projection role. This
    // verifies both byte streams, not a host retained-pool or allocator ledger.
    let mut requests = Vec::new();
    let mut replies = Vec::new();
    for offset in (0..length).step_by(65536) {
        requests.push(request("read",json!({"contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":{"kind":"semantic-projection"},"offset":offset,"maxBytes":65536})));
        let mut bytes = vec![b' '; 65536];
        if offset + 65536 == length {
            bytes[65536 - tail.len()..].copy_from_slice(tail);
        }
        replies.push(reply(&json!({"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","binding":summary["binding"],"captureId":"capture-A","target":{"kind":"semantic-projection"},"offset":offset,"nextOffset":offset+65536,"content":STANDARD.encode(bytes)})));
    }
    let reads = requests
        .iter()
        .zip(&replies)
        .map(|(request, reply)| Exchange { request, reply })
        .collect::<Vec<_>>();
    let expectation = ExpectedProjection::json(
        std::str::from_utf8(tail).unwrap(),
        ProjectionWorkLimits::new(128 * 1024 * 1024, 1_000_000).unwrap(),
    )
    .unwrap();
    let projection = checked.verify_projection(&expectation, &reads).unwrap();
    assert_eq!(projection.byte_length(), length);
    assert_eq!(projection.format_version().as_str(), "4.0.0");
    assert_eq!(reads.len(), 1024);
}
