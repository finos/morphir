//! Fixed peer frames exercise the independent checker, not a production adapter.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir_mck::workbench::model_originals::{
    CaptureExpectation, Exchange, Parameters, Request, SessionId, TransferError,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

fn packet() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/wire49.json"
    ))
    .unwrap()
}
fn inventory_request(start: usize, maximum: usize, id: u64) -> Request {
    inventory_request_for("capture-A", start, maximum, id)
}
fn inventory_request_for(capture: &str, start: usize, maximum: usize, id: u64) -> Request {
    Request::parse(&json!({"jsonrpc":"2.0","id":id,"method":"morphir.model-originals.inventory","params":{
        "contractVersion":"0.1.0-draft.1","captureId":capture,"startIndex":start,"maxEntries":maximum
    }}).to_string()).unwrap()
}
fn read_request(target: Value, offset: usize, maximum: usize, id: u64) -> Request {
    Request::parse(&json!({"jsonrpc":"2.0","id":id,"method":"morphir.model-originals.read","params":{
        "contractVersion":"0.1.0-draft.1","captureId":"capture-A","target":target,"offset":offset,"maxBytes":maximum
    }}).to_string()).unwrap()
}
fn reply(id: u64, result: &Value) -> String {
    json!({"jsonrpc":"2.0","id":id,"result":result}).to_string()
}

#[test]
fn capture_expectation_rejects_companions_in_a_primary_only_summary() {
    let packet = packet();
    let mut summary = packet["cases"][0]["expected"]["summary"].clone();
    summary["coverage"] = json!({"kind":"primary"});
    assert!(CaptureExpectation::parse(&summary.to_string()).is_err());
}

#[test]
fn ready_summary_matches_the_capture_request_and_independent_session() {
    let packet = packet();
    let request = Request::parse(&packet["cases"][0]["input"]["request"].to_string()).unwrap();
    let session = SessionId::new("session-A").unwrap();
    let summary = &packet["cases"][0]["expected"]["summary"];
    assert!(
        CaptureExpectation::parse_for_request(&summary.to_string(), &request, &session).is_ok()
    );
    let other = SessionId::new("another-session").unwrap();
    assert!(matches!(
        CaptureExpectation::parse_for_request(&summary.to_string(), &request, &other),
        Err(TransferError::Binding)
    ));
    for pointer in [
        "/binding/source/providerId",
        "/binding/source/locator",
        "/binding/projectId",
    ] {
        let mut changed = summary.clone();
        *changed.pointer_mut(pointer).unwrap() = json!("different");
        assert!(matches!(
            CaptureExpectation::parse_for_request(&changed.to_string(), &request, &session),
            Err(TransferError::Binding)
        ));
    }
    let inventory = inventory_request(0, 2, 1);
    assert!(matches!(
        CaptureExpectation::parse_for_request(&summary.to_string(), &inventory, &session),
        Err(TransferError::Method)
    ));
}

#[test]
fn capture_scope_and_projection_request_are_distinct_from_available_bytes() {
    let packet = packet();
    let summary = &packet["cases"][0]["expected"]["summary"];
    let session = SessionId::new("session-A").unwrap();
    for (field, value) in [("scope", "primary"), ("semantic", "none")] {
        let mut raw = packet["cases"][0]["input"]["request"].clone();
        raw["params"][field] = json!(value);
        let request = Request::parse(&raw.to_string()).unwrap();
        assert!(
            CaptureExpectation::parse_for_request(&summary.to_string(), &request, &session)
                .is_err()
        );
    }
    let request = Request::parse(&packet["cases"][0]["input"]["request"].to_string()).unwrap();
    let mut changed = summary.clone();
    changed["projection"] = json!({"status":"not-requested"});
    assert!(
        CaptureExpectation::parse_for_request(&changed.to_string(), &request, &session).is_err()
    );
    let mut no_semantic = packet["cases"][0]["input"]["request"].clone();
    no_semantic["params"]["semantic"] = json!("none");
    let no_semantic = Request::parse(&no_semantic.to_string()).unwrap();
    assert!(
        CaptureExpectation::parse_for_request(&changed.to_string(), &no_semantic, &session).is_ok()
    );
    // Originals may remain ready when the independently requested projection
    // cannot be produced. An unavailable projection is a valid scoped outcome.
    changed["projection"] = json!({"status":"unavailable","reason":"invalid_model"});
    assert!(
        CaptureExpectation::parse_for_request(&changed.to_string(), &request, &session).is_ok()
    );
}

#[test]
fn frozen_pages_and_separate_original_projection_chunks_verify() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, u64::MAX);
    let first_reply = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    let second_reply = reply(u64::MAX, &packet["cases"][1]["input"]["pages"][1]);
    let inventory = expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &first_reply,
            },
            Exchange {
                request: &second,
                reply: &second_reply,
            },
        ])
        .unwrap();
    assert_eq!(inventory.inventory().entries().len(), 4);
    for (case, target, expected_length) in [
        (11, json!({"kind":"original","entryId":"entry-model"}), 116),
        (12, json!({"kind":"semantic-projection"}), 111),
    ] {
        let request = read_request(target, 0, 65536, 1);
        let Parameters::Read { target, .. } = request.parameters() else {
            panic!()
        };
        let frame = reply(1, &packet["cases"][case]["expected"]["chunk"]);
        let stream = inventory
            .verify_stream(
                target,
                &[Exchange {
                    request: &request,
                    reply: &frame,
                }],
            )
            .unwrap();
        assert_eq!(stream.bytes().len(), expected_length);
        assert_eq!(stream.target(), target);
    }
}

#[test]
fn pages_reject_changed_binding_capture_digest_indices_and_incomplete_progress() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let request = inventory_request(0, 2, 1);
    for (pointer, value) in [
        ("/binding/sessionId", json!("other-session")),
        ("/binding/source/providerId", json!("other-provider")),
        ("/binding/source/locator", json!("other-source")),
        ("/binding/projectId", json!("other-project")),
        ("/captureId", json!("other-capture")),
        ("/inventorySha256", json!("0".repeat(64))),
        ("/startIndex", json!(1)),
        ("/next/startIndex", json!(3)),
    ] {
        let mut page = packet["cases"][1]["input"]["pages"][0].clone();
        *page.pointer_mut(pointer).unwrap() = value;
        let frame = reply(1, &page);
        assert!(
            expected
                .verify_inventory(&[Exchange {
                    request: &request,
                    reply: &frame
                }])
                .is_err(),
            "accepted {pointer}"
        );
    }
    let frame = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    assert!(
        expected
            .verify_inventory(&[Exchange {
                request: &request,
                reply: &frame
            }])
            .is_err()
    );
}

#[test]
fn page_must_be_maximal_for_the_requested_limit_and_terminal_page_is_empty() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, 2);
    let a = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    let b = reply(2, &packet["cases"][1]["input"]["pages"][1]);
    let inventory = expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &a,
            },
            Exchange {
                request: &second,
                reply: &b,
            },
        ])
        .unwrap();
    let oversized = inventory_request(0, 256, 1);
    assert!(
        inventory
            .check_page(&Exchange {
                request: &oversized,
                reply: &a
            })
            .is_err()
    );
    let terminal = inventory_request(4, 256, 7);
    let frame = reply(7, &packet["cases"][2]["expected"]["page"]);
    inventory
        .check_page(&Exchange {
            request: &terminal,
            reply: &frame,
        })
        .unwrap();
}

#[test]
fn raw_rpc_ids_duplicates_whitespace_and_non_ascii_escaping_are_checked() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, 2);
    let a = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    let b = reply(2, &packet["cases"][1]["input"]["pages"][1]);
    for token in ["1.0", "1e0", "-0", "18446744073709551616", "null", "\"1\""] {
        let raw = a.replacen("\"id\":1", &format!("\"id\":{token}"), 1);
        assert!(
            expected
                .verify_inventory(&[
                    Exchange {
                        request: &first,
                        reply: &raw
                    },
                    Exchange {
                        request: &second,
                        reply: &b
                    }
                ])
                .is_err(),
            "accepted ID {token}"
        );
    }
    for raw in [
        a.replacen("\"id\":1", "\"id\":1,\"id\":1", 1),
        format!(" {a}"),
        a.replacen("\"entries\":", "\"entries\": ", 1),
    ] {
        assert!(
            expected
                .verify_inventory(&[
                    Exchange {
                        request: &first,
                        reply: &raw
                    },
                    Exchange {
                        request: &second,
                        reply: &b
                    }
                ])
                .is_err()
        );
    }
}

#[test]
fn chunks_reject_role_confusion_short_progress_and_noncanonical_base64() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, 2);
    let a = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    let b = reply(2, &packet["cases"][1]["input"]["pages"][1]);
    let inventory = expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &a,
            },
            Exchange {
                request: &second,
                reply: &b,
            },
        ])
        .unwrap();
    let request = read_request(
        json!({"kind":"original","entryId":"entry-model"}),
        0,
        65536,
        1,
    );
    let Parameters::Read { target, .. } = request.parameters() else {
        panic!()
    };
    for (pointer, value) in [
        ("/target", json!({"kind":"semantic-projection"})),
        ("/offset", json!(1)),
        ("/nextOffset", json!(115)),
        ("/content", json!("AB==")),
        ("/content", json!("AA")),
        ("/content", json!("AA-_")),
    ] {
        let mut chunk = packet["cases"][11]["expected"]["chunk"].clone();
        *chunk.pointer_mut(pointer).unwrap() = value;
        let frame = reply(1, &chunk);
        assert!(
            inventory
                .verify_stream(
                    target,
                    &[Exchange {
                        request: &request,
                        reply: &frame
                    }]
                )
                .is_err(),
            "accepted {pointer}"
        );
    }
}

#[test]
fn nonpage_reply_byte_boundary_retains_the_original_exact_padding_control() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, 2);
    let a = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    let b = reply(2, &packet["cases"][1]["input"]["pages"][1]);
    let inventory = expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &a,
            },
            Exchange {
                request: &second,
                reply: &b,
            },
        ])
        .unwrap();
    let request = read_request(
        json!({"kind":"original","entryId":"entry-model"}),
        0,
        65536,
        1,
    );
    let Parameters::Read { target, .. } = request.parameters() else {
        panic!()
    };
    let frame = reply(1, &packet["cases"][11]["expected"]["chunk"]);
    let exact = format!("{frame}{}", " ".repeat(131072 - frame.len()));
    assert_eq!(exact.len(), 131072);
    inventory
        .verify_stream(
            target,
            &[Exchange {
                request: &request,
                reply: &exact,
            }],
        )
        .unwrap();
    let one_over = format!("{exact} ");
    assert!(
        inventory
            .verify_stream(
                target,
                &[Exchange {
                    request: &request,
                    reply: &one_over
                }]
            )
            .is_err()
    );
}

#[test]
fn multiple_chunks_and_explicit_eof_preserve_exact_opaque_bytes() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, 2);
    let a = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    let b = reply(2, &packet["cases"][1]["input"]["pages"][1]);
    let inventory = expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &a,
            },
            Exchange {
                request: &second,
                reply: &b,
            },
        ])
        .unwrap();
    let target = json!({"kind":"original","entryId":"entry-opaque"});
    let bytes = [0, 1, 2, 255];
    let requests = (0..=4)
        .map(|offset| read_request(target.clone(), offset, 1, offset as u64))
        .collect::<Vec<_>>();
    let frames = (0..=4)
        .map(|offset| {
            let mut chunk = packet["cases"][11]["expected"]["chunk"].clone();
            chunk["target"] = target.clone();
            chunk["offset"] = json!(offset);
            chunk["nextOffset"] = json!((offset + 1).min(4));
            chunk["content"] = json!(STANDARD.encode(&bytes[offset..(offset + 1).min(4)]));
            reply(offset as u64, &chunk)
        })
        .collect::<Vec<_>>();
    let exchanges = requests
        .iter()
        .zip(&frames)
        .map(|(request, reply)| Exchange { request, reply })
        .collect::<Vec<_>>();
    let Parameters::Read { target, .. } = requests[0].parameters() else {
        panic!()
    };
    assert_eq!(
        inventory.verify_stream(target, &exchanges).unwrap().bytes(),
        bytes
    );
    let mut changed = frames.clone();
    let mut frame: Value = serde_json::from_str(&changed[0]).unwrap();
    frame["result"]["content"] = json!("AQ==");
    changed[0] = frame.to_string();
    let exchanges = requests
        .iter()
        .zip(&changed)
        .map(|(request, reply)| Exchange { request, reply })
        .collect::<Vec<_>>();
    assert!(inventory.verify_stream(target, &exchanges).is_err());
}

#[test]
fn frozen_escaped_unicode_pagination_uses_the_maximum_u64_id() {
    let packet = packet();
    let case = packet["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["id"] == "largest-page-prefix-counts-full-escaped-UTF8-binding")
        .unwrap();
    let input = &case["input"];
    let recipe = &input["entryRecipe"];
    let directory = recipe["directory"].as_str().unwrap();
    let prefix = recipe["filenamePrefix"].as_str().unwrap();
    // This is the original independent author's recipe, including the fixed
    // directory ID and underscore separating each filename and decimal index.
    let mut entries = vec![json!({"kind":"directory","entryId":"directory-long","path":directory})];
    for index in 0..256 {
        entries.push(json!({"kind":"file","entryId":format!("file-{index:03}"),"path":format!("{directory}/{prefix}_{index:03}"),"byteLength":0,"sha256":recipe["sha256"]}));
    }
    let mut summary = packet["cases"][0]["expected"]["summary"].clone();
    summary["captureId"] = json!("capture-escaped-binding");
    summary["binding"] = input["binding"].clone();
    summary["primary"] = json!({"kind":"directory","path":directory});
    summary["companions"] = json!([]);
    summary["inventory"] = json!({"entryCount":257,"fileCount":256,"directoryCount":1,"sourceByteLength":0,"sha256":input["inventorySha256"]});
    let page = |summary: &Value, start: usize, count: usize| json!({"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","binding":summary["binding"],"captureId":summary["captureId"],"inventorySha256":summary["inventory"]["sha256"],"startIndex":start,"entries":&entries[start..start+count],"next":if start+count==257 {json!({"kind":"complete"})} else {json!({"kind":"more","startIndex":start+count})}});
    assert_eq!(reply(u64::MAX, &page(&summary, 0, 228)).len(), 131015);
    assert_eq!(reply(u64::MAX, &page(&summary, 0, 229)).len(), 131558);
    for id in [1, u64::MAX] {
        let expected = CaptureExpectation::parse(&summary.to_string()).unwrap();
        let first = inventory_request_for("capture-escaped-binding", 0, 256, id);
        let second = inventory_request_for("capture-escaped-binding", 228, 256, 2);
        let a = reply(id, &page(&summary, 0, 228));
        let b = reply(2, &page(&summary, 228, 29));
        expected
            .verify_inventory(&[
                Exchange {
                    request: &first,
                    reply: &a,
                },
                Exchange {
                    request: &second,
                    reply: &b,
                },
            ])
            .unwrap();
    }
    // Make n+1 fit the *actual short ID* but exceed the max-u64 measurement by
    // one byte. This distinguishes pessimistic sizing from an actual-ID gate.
    let encoded_project = serde_json::to_string(&summary["binding"]["projectId"])
        .unwrap()
        .len();
    summary["binding"]["projectId"] = json!("x".repeat(encoded_project - 2 - 485));
    assert_eq!(reply(u64::MAX, &page(&summary, 0, 229)).len(), 131073);
    let expected = CaptureExpectation::parse(&summary.to_string()).unwrap();
    let first = inventory_request_for("capture-escaped-binding", 0, 256, 1);
    let second = inventory_request_for("capture-escaped-binding", 228, 256, 2);
    let a = reply(1, &page(&summary, 0, 228));
    let b = reply(2, &page(&summary, 228, 29));
    let inventory = expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &a,
            },
            Exchange {
                request: &second,
                reply: &b,
            },
        ])
        .unwrap();
    let too_many = reply(1, &page(&summary, 0, 229));
    assert!(too_many.len() < 131072);
    assert!(
        inventory
            .check_page(&Exchange {
                request: &first,
                reply: &too_many
            })
            .is_err()
    );
}

#[test]
fn page_strings_use_direct_unicode_while_object_member_order_remains_free() {
    let packet = packet();
    let mut summary = packet["cases"][0]["expected"]["summary"].clone();
    summary["binding"]["sessionId"] = json!("session-é");
    let expected = CaptureExpectation::parse(&summary.to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, 2);
    let mut a = packet["cases"][1]["input"]["pages"][0].clone();
    a["binding"] = summary["binding"].clone();
    let mut b = packet["cases"][1]["input"]["pages"][1].clone();
    b["binding"] = summary["binding"].clone();
    let first_frame = format!("{{\"result\":{a},\"jsonrpc\":\"2.0\",\"id\":1}}");
    let second_frame = reply(2, &b);
    expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &first_frame,
            },
            Exchange {
                request: &second,
                reply: &second_frame,
            },
        ])
        .unwrap();
    let escaped = first_frame.replace('é', "\\u00e9");
    assert!(matches!(
        expected.verify_inventory(&[
            Exchange {
                request: &first,
                reply: &escaped
            },
            Exchange {
                request: &second,
                reply: &second_frame
            }
        ]),
        Err(TransferError::Encoding)
    ));
    let exact_count = second_frame.replacen("\"startIndex\":2", "\"startIndex\":2.000e0", 1);
    expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &first_frame,
            },
            Exchange {
                request: &second,
                reply: &exact_count,
            },
        ])
        .unwrap();
}

#[test]
fn malformed_numeric_members_in_pages_and_chunks_return_refusals_without_schema_panics() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, 2);
    let a = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    let b = reply(2, &packet["cases"][1]["input"]["pages"][1]);
    let inventory = expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &a,
            },
            Exchange {
                request: &second,
                reply: &b,
            },
        ])
        .unwrap();
    let huge: Value = serde_json::from_str("1e100000").unwrap();
    let mut page = packet["cases"][1]["input"]["pages"][1].clone();
    page["next"]["startIndex"] = huge.clone();
    assert!(
        inventory
            .check_page(&Exchange {
                request: &second,
                reply: &reply(2, &page)
            })
            .is_err()
    );
    let mut page = packet["cases"][1]["input"]["pages"][0].clone();
    page["entries"][1]["byteLength"] = huge.clone();
    assert!(
        inventory
            .check_page(&Exchange {
                request: &first,
                reply: &reply(1, &page)
            })
            .is_err()
    );
    let request = read_request(
        json!({"kind":"original","entryId":"entry-model"}),
        0,
        65536,
        1,
    );
    let Parameters::Read { target, .. } = request.parameters() else {
        panic!()
    };
    for member in ["offset", "nextOffset"] {
        let mut chunk = packet["cases"][11]["expected"]["chunk"].clone();
        chunk[member] = huge.clone();
        assert!(
            inventory
                .verify_stream(
                    target,
                    &[Exchange {
                        request: &request,
                        reply: &reply(1, &chunk)
                    }]
                )
                .is_err()
        );
    }
}

#[test]
fn malformed_error_objects_never_become_valid_remote_refusals() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let request = inventory_request(0, 2, 1);
    let refusal = json!({"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"No capture capacity","data":{"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","code":"model_originals.capacity"}}});
    assert!(matches!(
        expected.verify_inventory(&[Exchange {
            request: &request,
            reply: &refusal.to_string()
        }]),
        Err(TransferError::Refused(_))
    ));
    for (pointer, value) in [
        (
            "/error/code",
            serde_json::from_str::<Value>("1e100000").unwrap(),
        ),
        ("/error/data/code", json!("model_originals.unknown")),
        ("/error/data/profile", json!("morphir/workbench/artifacts")),
        ("/error/message", json!("😀".repeat(257))),
    ] {
        let mut malformed = refusal.clone();
        *malformed.pointer_mut(pointer).unwrap() = value;
        assert!(
            !matches!(
                expected.verify_inventory(&[Exchange {
                    request: &request,
                    reply: &malformed.to_string()
                }]),
                Err(TransferError::Refused(_))
            ),
            "laundered {pointer}"
        );
    }
}

fn fixture_inventory(summary: &Value) -> morphir_mck::workbench::model_originals::CaptureInventory {
    let packet = packet();
    let expected = CaptureExpectation::parse(&summary.to_string()).unwrap();
    let first = inventory_request(0, 2, 1);
    let second = inventory_request(2, 2, 2);
    let a = reply(1, &packet["cases"][1]["input"]["pages"][0]);
    let b = reply(2, &packet["cases"][1]["input"]["pages"][1]);
    expected
        .verify_inventory(&[
            Exchange {
                request: &first,
                reply: &a,
            },
            Exchange {
                request: &second,
                reply: &b,
            },
        ])
        .unwrap()
}

#[test]
fn unused_base64_pad_bits_are_rejected_even_when_decoded_bytes_would_match() {
    let packet = packet();
    let inventory = fixture_inventory(&packet["cases"][0]["expected"]["summary"]);
    let request = read_request(
        json!({"kind":"original","entryId":"entry-model"}),
        0,
        65536,
        1,
    );
    let Parameters::Read { target, .. } = request.parameters() else {
        panic!()
    };
    let mut chunk = packet["cases"][11]["expected"]["chunk"].clone();
    let original = chunk["content"].as_str().unwrap();
    assert!(original.ends_with("DQo="));
    // DQr= changes only unused pad bits, leaving both decoded bytes and the
    // complete content digest unchanged in a permissive decoder.
    chunk["content"] = json!(original.replacen("DQo=", "DQr=", 1));
    assert!(matches!(
        inventory.verify_stream(
            target,
            &[Exchange {
                request: &request,
                reply: &reply(1, &chunk)
            }]
        ),
        Err(TransferError::Encoding)
    ));
}

#[test]
fn typed_refusal_preserves_the_exact_utf16_message_limit_and_classification() {
    let packet = packet();
    let expected =
        CaptureExpectation::parse(&packet["cases"][0]["expected"]["summary"].to_string()).unwrap();
    let request = inventory_request(0, 2, 1);
    let refusal = json!({"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"😀".repeat(256),"data":{"profile":"morphir/workbench/model-originals","contractVersion":"0.1.0-draft.1","code":"model_originals.capacity"}}});
    match expected.verify_inventory(&[Exchange {
        request: &request,
        reply: &refusal.to_string(),
    }]) {
        Err(TransferError::Refused(failure)) => {
            assert_eq!(
                failure.code(),
                morphir_mck::workbench::model_originals::FailureCode::Capacity
            );
            assert_eq!(
                failure.rpc_kind(),
                morphir_mck::workbench::model_originals::RpcFailureKind::ServerError
            );
            assert_eq!(failure.message().encode_utf16().count(), 512);
        }
        other => panic!("wrong exact-bound refusal: {other:?}"),
    }
}

#[test]
fn full_sized_projection_chunk_obeys_the_decoded_byte_bound() {
    let packet = packet();
    let original = STANDARD
        .decode(
            packet["cases"][12]["expected"]["chunk"]["content"]
                .as_str()
                .unwrap(),
        )
        .unwrap();
    let mut bytes = vec![b' '; 65536 - original.len()];
    bytes.extend_from_slice(&original);
    let digest = Sha256::digest(&bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    let mut summary = packet["cases"][0]["expected"]["summary"].clone();
    summary["projection"]["byteLength"] = json!(65536);
    summary["projection"]["sha256"] = json!(digest);
    let inventory = fixture_inventory(&summary);
    let request = read_request(json!({"kind":"semantic-projection"}), 0, 65536, 7);
    let Parameters::Read { target, .. } = request.parameters() else {
        panic!()
    };
    let mut chunk = packet["cases"][12]["expected"]["chunk"].clone();
    chunk["nextOffset"] = json!(65536);
    chunk["content"] = json!(STANDARD.encode(&bytes));
    assert_eq!(chunk["content"].as_str().unwrap().len(), 87384);
    let frame = reply(7, &chunk);
    assert_eq!(
        inventory
            .verify_stream(
                target,
                &[Exchange {
                    request: &request,
                    reply: &frame
                }]
            )
            .unwrap()
            .bytes(),
        bytes
    );
    bytes.push(b' ');
    chunk["content"] = json!(STANDARD.encode(&bytes));
    assert_eq!(chunk["content"].as_str().unwrap().len(), 87384);
    let frame = reply(7, &chunk);
    assert!(matches!(
        inventory.verify_stream(
            target,
            &[Exchange {
                request: &request,
                reply: &frame
            }]
        ),
        Err(TransferError::Progress)
    ));
}
