//! Launched authenticated CLI host, checked by the existing independent MCK.
//! No model semantic, Report, registration or whole-campaign qualification claim.
#[path = "support/model_originals_host/mod.rs"]
mod support;

use morphir_mck::workbench::model_originals::{
    CaptureEvidence, CaptureExpectation, EntryId, Exchange, ExpectedBytes, ExpectedOriginalEntry,
    ExpectedOriginals, ExpectedSource, ModelRelease, OriginalTransfer, ProjectionRefusal,
    ProjectionStatus, Request, Root, SessionId, SourceFormatVersion,
};
use serde_json::{Value, json};
use support::{Fixture, Format, Host, Layout, PROFILE, SIDECAR, VERSION, capture_params};

struct Recorded {
    request: Request,
    reply: String,
}
impl Recorded {
    fn new((request, reply): (String, String)) -> Self {
        Self {
            request: Request::parse(&request).unwrap(),
            reply,
        }
    }
    fn exchange(&self) -> Exchange<'_> {
        Exchange {
            request: &self.request,
            reply: &self.reply,
        }
    }
}

async fn capture_and_check(fixture: &Fixture, tree: bool) {
    capture_and_check_projection(fixture, tree, ProjectionCase::NotRequested).await;
}

#[derive(Clone, Copy)]
enum ProjectionCase {
    NotRequested,
    Unsupported,
}
impl ProjectionCase {
    fn status(self) -> ProjectionStatus {
        match self {
            Self::NotRequested => ProjectionStatus::NotRequested,
            Self::Unsupported => {
                ProjectionStatus::Unavailable(ProjectionRefusal::UnsupportedRepresentation)
            }
        }
    }
    fn wire(self) -> Value {
        match self {
            Self::NotRequested => json!({"status":"not-requested"}),
            Self::Unsupported => {
                json!({"status":"unavailable","reason":"unsupported_representation"})
            }
        }
    }
}

async fn capture_and_check_projection(fixture: &Fixture, tree: bool, projection: ProjectionCase) {
    let host = Host::launch(fixture).await;
    host.prove_authentication().await;
    let source = &host.manifest["initialSources"][0];
    let provider = host.manifest["providers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == source["providerId"])
        .unwrap();
    assert!(
        provider["capabilities"]
            .as_array()
            .unwrap()
            .iter()
            .any(|c| c["name"] == PROFILE && c["version"] == VERSION),
        "actual host must advertise its exact available contract"
    );
    let mut socket = host.connect().await;
    let workspace = socket
        .call("morphir.workspace.open", json!({"source":source}))
        .await;
    assert!(workspace["error"].is_null(), "{workspace}");
    let project = workspace["result"]["snapshot"]["projects"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["relativePath"] == ".")
        .unwrap()["id"]
        .as_str()
        .unwrap();

    // A client-authored path is never output-directory authority.
    let refused = socket
        .call(
            "morphir.model-originals.capture",
            capture_params(source, "../../outside"),
        )
        .await;
    assert!(
        refused.get("error").is_some(),
        "unknown project must refuse whole capture: {refused}"
    );
    assert!(
        refused.get("result").is_none(),
        "no partial inventory on refusal"
    );

    let mut params = capture_params(source, project);
    if matches!(projection, ProjectionCase::Unsupported) {
        params["semantic"] = json!("projection");
    }
    let capture = Recorded::new(
        socket
            .raw_call("morphir.model-originals.capture", params)
            .await,
    );
    let ready: Value = serde_json::from_str(&capture.reply).unwrap();
    assert_eq!(ready["result"]["status"], "ready", "{ready}");
    assert_eq!(ready["result"]["projection"], projection.wire());
    let id = ready["result"]["captureId"].as_str().unwrap();
    let session = SessionId::new(host.manifest["sessionId"].as_str().unwrap()).unwrap();
    let expectation = CaptureExpectation::from_exchange(&capture.exchange(), &session).unwrap();

    // Capture is connection-owned, even for another correctly authenticated socket.
    let mut foreign = host.connect().await;
    let denied = foreign
        .call(
            "morphir.model-originals.inventory",
            json!({"contractVersion":VERSION,"captureId":id,"startIndex":0,"maxEntries":1}),
        )
        .await;
    assert!(denied.get("error").is_some());
    assert!(denied.get("result").is_none());
    foreign.close().await;

    let mut pages = Vec::new();
    let mut start = 0;
    loop {
        let page = Recorded::new(socket.raw_call("morphir.model-originals.inventory", json!({"contractVersion":VERSION,"captureId":id,"startIndex":start,"maxEntries":1})).await);
        let value: Value = serde_json::from_str(&page.reply).unwrap();
        assert!(value["error"].is_null(), "{value}");
        let next = value["result"]["next"].clone();
        pages.push(page);
        match next["kind"].as_str().unwrap() {
            "complete" => break,
            "more" => {
                let next = next["startIndex"].as_u64().unwrap();
                assert!(next > start);
                start = next;
            }
            other => panic!("invalid page progress {other}"),
        }
    }
    let page_exchanges = pages.iter().map(Recorded::exchange).collect::<Vec<_>>();
    let inventory = expectation.verify_inventory(&page_exchanges).unwrap();
    let mut streams: Vec<(EntryId, Vec<Recorded>)> = Vec::new();
    for entry in inventory.inventory().entries() {
        if entry.kind() != morphir_mck::workbench::model_originals::RootKind::File {
            continue;
        }
        let expected = fixture
            .originals
            .iter()
            .find(|(path, _)| path == entry.path())
            .unwrap()
            .1
            .as_ref()
            .unwrap();
        let mut records = Vec::new();
        let mut offset = 0;
        loop {
            let read = Recorded::new(socket.raw_call("morphir.model-originals.read", json!({"contractVersion":VERSION,"captureId":id,"target":{"kind":"original","entryId":entry.id().as_str()},"offset":offset,"maxBytes":3})).await);
            let value: Value = serde_json::from_str(&read.reply).unwrap();
            assert!(value["error"].is_null(), "{value}");
            let next = value["result"]["nextOffset"].as_u64().unwrap() as usize;
            records.push(read);
            if next == expected.len() {
                break;
            }
            assert!(next > offset);
            offset = next;
        }
        streams.push((entry.id().clone(), records));
    }
    let stream_exchanges = streams
        .iter()
        .map(|(_, records)| records.iter().map(Recorded::exchange).collect::<Vec<_>>())
        .collect::<Vec<_>>();
    let originals = streams
        .iter()
        .zip(&stream_exchanges)
        .map(|((entry, _), exchanges)| OriginalTransfer { entry, exchanges })
        .collect::<Vec<_>>();
    let expected_entries = fixture
        .originals
        .iter()
        .map(|(path, bytes)| match bytes {
            Some(bytes) => {
                ExpectedOriginalEntry::file(path, ExpectedBytes::literal(bytes).unwrap()).unwrap()
            }
            None => ExpectedOriginalEntry::directory(path).unwrap(),
        })
        .collect();
    let primary = if tree {
        Root::directory(&fixture.primary)
    } else {
        Root::file(&fixture.primary)
    }
    .unwrap();
    let expected_source =
        ExpectedSource::new(primary, vec![], fixture.expected_version.clone()).unwrap();
    let expected = ExpectedOriginals::new(expected_entries, expected_source).unwrap();
    let checked = expected
        .verify(
            &session,
            CaptureEvidence {
                capture: capture.exchange(),
                pages: &page_exchanges,
                originals: &originals,
            },
        )
        .unwrap();
    assert_eq!(checked.projection_status(), projection.status());
    if tree {
        assert!(
            fixture
                .originals
                .iter()
                .any(|(p, b)| p == "morphir-ir/opaque.bin" && b.as_deref() == Some(SIDECAR))
        );
        assert!(
            fixture
                .originals
                .iter()
                .any(|(p, b)| p == "morphir-ir/zero.bin" && b.as_deref() == Some(&[]))
        );
        assert!(
            fixture
                .originals
                .iter()
                .any(|(p, b)| p == "morphir-ir/empty" && b.is_none())
        );
    }
    for _ in 0..2 {
        let release = Recorded::new(
            socket
                .raw_call(
                    "morphir.model-originals.release",
                    json!({"contractVersion":VERSION,"captureId":id}),
                )
                .await,
        );
        expectation.verify_release(&release.exchange()).unwrap();
    }
    let retired = socket
        .call(
            "morphir.model-originals.inventory",
            json!({"contractVersion":VERSION,"captureId":id,"startIndex":0,"maxEntries":1}),
        )
        .await;
    assert!(retired.get("error").is_some());
    assert!(retired.get("result").is_none());
    socket.close().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_yaml_capture_inventory_bytes_and_release_match_independent_checker() {
    let fixture = Fixture::compile(Layout::File);
    capture_and_check(&fixture, false).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_tree_retains_fixed_sidecar_zero_file_and_empty_directory() {
    let fixture = Fixture::compile(Layout::Tree);
    capture_and_check(&fixture, true).await;
}

#[cfg(unix)]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_outside_symlink_refuses_the_whole_capture() {
    let fixture = Fixture::compile(Layout::Tree);
    let host = Host::launch(&fixture).await;
    let source = &host.manifest["initialSources"][0];
    let mut socket = host.connect().await;
    let workspace = socket
        .call("morphir.workspace.open", json!({"source":source}))
        .await;
    assert!(workspace["error"].is_null(), "{workspace}");
    let project = workspace["result"]["snapshot"]["projects"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["relativePath"] == ".")
        .unwrap()["id"]
        .as_str()
        .unwrap();
    // Resolve the genuine current project before introducing the capture poison.
    // This keeps the assertion at capture, rather than an earlier discovery step.
    let outside = fixture.root().join("outside.bin");
    std::fs::write(&outside, b"outside must not enter the capture\r\n\0").unwrap();
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(fixture.root().join(".morphir/out/compile.lock"))
        .unwrap();
    fs2::FileExt::lock_exclusive(&lock).unwrap();
    std::os::unix::fs::symlink(
        &outside,
        fixture
            .root()
            .join(".morphir/out/compile.dest/morphir-ir/outside.bin"),
    )
    .unwrap();
    fs2::FileExt::unlock(&lock).unwrap();
    let refused = socket
        .call(
            "morphir.model-originals.capture",
            capture_params(source, project),
        )
        .await;
    assert!(refused.get("error").is_some(), "{refused}");
    assert!(
        refused.get("result").is_none(),
        "an invalid descendant must refuse the whole capture, not publish a prefix"
    );
    assert_eq!(
        std::fs::read(outside).unwrap(),
        b"outside must not enter the capture\r\n\0"
    );
    // No-read is enforced by the confined production walker; unchanged content
    // and absent inventory alone do not measure whether the target was opened.
    socket.close().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_json_single_and_tree_source_headers_and_bytes() {
    for layout in [Layout::File, Layout::Tree] {
        let fixture = Fixture::compile_format(layout, Format::Json);
        capture_and_check(&fixture, matches!(layout, Layout::Tree)).await;
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_ion_single_and_tree_bytes_with_explicit_unreported_header() {
    for layout in [Layout::File, Layout::Tree] {
        let fixture = Fixture::compile_format(layout, Format::Ion);
        capture_and_check(&fixture, matches!(layout, Layout::Tree)).await;
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_json_bom_and_crlf_are_retained_with_explicit_unreported_header() {
    let mut fixture = Fixture::compile_format(Layout::File, Format::Json);
    let original = fixture.originals[0].1.as_ref().unwrap();
    assert!(!original.contains(&b'\r'));
    assert!(original.contains(&b'\n'));
    let mut rewritten = vec![0xef, 0xbb, 0xbf];
    for &byte in original {
        if byte == b'\n' {
            rewritten.push(b'\r');
        }
        rewritten.push(byte);
    }
    // Original wire49 explicitly permits unavailable physical BOM recognition.
    // Preserve every byte; never substitute the compile descriptor's release.
    fixture.replace_primary(&rewritten, SourceFormatVersion::NotReported);
    capture_and_check(&fixture, false).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_unsupported_source_releases_remain_original_evidence() {
    // Genuine compile records remain owned by the compiler. A cooperating writer
    // changes only the selected source bytes under its real compile lock.
    for (format, bytes, release) in [
        (
            Format::Json,
            br#"{"formatVersion":2,"opaque":"retained"}"#.as_slice(),
            "2.0.0",
        ),
        (
            Format::Yaml,
            b"formatVersion: 99\nopaque: retained\n".as_slice(),
            "99.0.0",
        ),
    ] {
        let mut fixture = Fixture::compile_format(Layout::File, format);
        fixture.replace_primary(
            bytes,
            SourceFormatVersion::Reported(ModelRelease::parse(release).unwrap()),
        );
        capture_and_check(&fixture, false).await;
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_unavailable_projection_preserves_ready_originals_and_full_transfer() {
    let fixture = Fixture::compile_format(Layout::File, Format::Json);
    capture_and_check_projection(&fixture, false, ProjectionCase::Unsupported).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_fixed_binary_ion_primary_is_retained_and_fully_transferred() {
    // Published independent draft29 model source, not a host/codec output
    // generated by this test and not an opaque companion relabeled as primary.
    const BINARY_MODEL: &[u8] = include_bytes!("support/model_originals_host/model-primary.ionb");
    assert_eq!(BINARY_MODEL.len(), 499);
    assert_eq!(&BINARY_MODEL[..4], &[0xe0, 0x01, 0x00, 0xea]);
    assert_eq!(
        morphir_distribution::Sha256Digest::of_bytes(BINARY_MODEL).to_string(),
        "49f87687c033a8ec39a7f42b93bb1c54b4856ceab0b05246d81ea0a8b27e10b1"
    );
    let mut fixture = Fixture::compile_format(Layout::File, Format::Ion);
    fixture.replace_primary(BINARY_MODEL, SourceFormatVersion::NotReported);
    assert_eq!(fixture.primary, "morphir-ir.ion");
    assert_eq!(
        fixture.originals,
        vec![("morphir-ir.ion".to_owned(), Some(BINARY_MODEL.to_vec()))]
    );
    capture_and_check(&fixture, false).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_source_limit_one_over_refuses_without_handle_and_recovers() {
    let mut fixture = Fixture::compile_format(Layout::File, Format::Json);
    let original = fixture.originals[0].1.as_ref().unwrap().clone();
    let host = Host::launch(&fixture).await;
    let source = &host.manifest["initialSources"][0];
    let session = SessionId::new(host.manifest["sessionId"].as_str().unwrap()).unwrap();
    let mut socket = host.connect().await;
    let workspace = socket
        .call("morphir.workspace.open", json!({"source":source}))
        .await;
    assert!(workspace["error"].is_null(), "{workspace}");
    let project = workspace["result"]["snapshot"]["projects"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["relativePath"] == ".")
        .unwrap()["id"]
        .as_str()
        .unwrap();
    // Exactly64MiB+1 is a real sparse/lengthened primary; no record/path rewrite.
    fixture.resize_primary_for_refusal(67_108_865);
    let (sent, reply) = socket
        .raw_call(
            "morphir.model-originals.capture",
            capture_params(source, project),
        )
        .await;
    let rejected = Request::parse(&sent).unwrap();
    closed_profile_failure(
        &reply,
        json!(rejected.id().get()),
        "model_originals.source_limit",
    );

    // Repair via the same trusted cooperating writer, then prove actual
    // same-socket recovery and all returned bytes using the existing checker.
    fixture.replace_primary(
        &original,
        SourceFormatVersion::Reported(ModelRelease::parse("4.0.0").unwrap()),
    );
    let capture = Recorded::new(
        socket
            .raw_call(
                "morphir.model-originals.capture",
                capture_params(source, project),
            )
            .await,
    );
    let expectation = CaptureExpectation::from_exchange(&capture.exchange(), &session).unwrap();
    let ready: Value = serde_json::from_str(&capture.reply).unwrap();
    let capture_id = ready["result"]["captureId"].as_str().unwrap();
    let page = Recorded::new(socket.raw_call("morphir.model-originals.inventory", json!({"contractVersion":VERSION,"captureId":capture_id,"startIndex":0,"maxEntries":256})).await);
    let page_exchanges = [page.exchange()];
    let inventory = expectation.verify_inventory(&page_exchanges).unwrap();
    assert_eq!(inventory.inventory().entries().len(), 1);
    let entry = inventory.inventory().entries()[0].id();
    let mut reads = Vec::new();
    let mut offset = 0;
    loop {
        let read = Recorded::new(socket.raw_call("morphir.model-originals.read", json!({"contractVersion":VERSION,"captureId":capture_id,"target":{"kind":"original","entryId":entry.as_str()},"offset":offset,"maxBytes":65536})).await);
        let value: Value = serde_json::from_str(&read.reply).unwrap();
        let next = value["result"]["nextOffset"].as_u64().unwrap() as usize;
        reads.push(read);
        if next == original.len() {
            break;
        }
        assert!(next > offset);
        offset = next;
    }
    let read_exchanges = reads.iter().map(Recorded::exchange).collect::<Vec<_>>();
    let originals = [OriginalTransfer {
        entry,
        exchanges: &read_exchanges,
    }];
    let expected = ExpectedOriginals::new(
        vec![
            ExpectedOriginalEntry::file(
                &fixture.primary,
                ExpectedBytes::literal(&original).unwrap(),
            )
            .unwrap(),
        ],
        ExpectedSource::new(
            Root::file(&fixture.primary).unwrap(),
            vec![],
            fixture.expected_version.clone(),
        )
        .unwrap(),
    )
    .unwrap();
    expected
        .verify(
            &session,
            CaptureEvidence {
                capture: capture.exchange(),
                pages: &page_exchanges,
                originals: &originals,
            },
        )
        .unwrap();
    let release = Recorded::new(
        socket
            .raw_call(
                "morphir.model-originals.release",
                json!({"contractVersion":VERSION,"captureId":capture_id}),
            )
            .await,
    );
    expectation.verify_release(&release.exchange()).unwrap();
    socket.close().await;
}

fn closed_profile_failure(raw: &str, id: Value, expected: &str) {
    let reply: Value = serde_json::from_str(raw).unwrap();
    assert_eq!(reply.as_object().unwrap().len(), 3, "{reply}");
    assert_eq!(reply["jsonrpc"], "2.0");
    assert_eq!(reply["id"], id);
    assert!(reply.get("result").is_none());
    let error = &reply["error"];
    assert_eq!(error.as_object().unwrap().len(), 3);
    assert_eq!(error["code"], -32602);
    assert!(error["message"].as_str().unwrap().encode_utf16().count() <= 512);
    assert_eq!(
        error["data"],
        json!({"profile":PROFILE,"contractVersion":VERSION,"code":expected})
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_cli_raw_selected_frames_refuse_without_publishing_and_exact_limit_accepts() {
    let fixture = Fixture::compile_format(Layout::File, Format::Json);
    let host = Host::launch(&fixture).await;
    let source = &host.manifest["initialSources"][0];
    let mut discovery = host.connect().await;
    let workspace = discovery
        .call("morphir.workspace.open", json!({"source":source}))
        .await;
    assert!(workspace["error"].is_null(), "{workspace}");
    let project = workspace["result"]["snapshot"]["projects"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["relativePath"] == ".")
        .unwrap()["id"]
        .as_str()
        .unwrap();
    discovery.close().await;
    let base = json!({"jsonrpc":"2.0","id":999,"method":"morphir.model-originals.capture","params":capture_params(source, project)}).to_string();
    assert_eq!(base.matches("\"id\":999").count(), 1);
    assert_eq!(base.matches("\"scope\":\"complete\"").count(), 1);
    let read = |offset: &str| {
        format!(
            r#"{{"jsonrpc":"2.0","id":999,"method":"morphir.model-originals.read","params":{{"contractVersion":"0.1.0-draft.1","captureId":"never-created","target":{{"kind":"original","entryId":"never-created"}},"offset":{offset},"maxBytes":1}}}}"#
        )
    };
    let mut oversized = base.clone();
    oversized.push_str(&" ".repeat(16 * 1024 + 1 - base.len()));
    assert_eq!(oversized.len(), 16 * 1024 + 1);
    let controls = [
        (
            "duplicate-scope",
            base.replace(
                "\"scope\":\"complete\"",
                "\"scope\":\"complete\",\"scope\":\"primary\"",
            ),
            Value::Null,
            "model_originals.invalid_request",
        ),
        (
            "negative-zero-id",
            base.replace("\"id\":999", "\"id\":-0"),
            Value::Null,
            "model_originals.invalid_request",
        ),
        (
            "fractional-token-id",
            base.replace("\"id\":999", "\"id\":1.0"),
            Value::Null,
            "model_originals.invalid_request",
        ),
        (
            "u64-id-one-over",
            base.replace("\"id\":999", "\"id\":18446744073709551616"),
            Value::Null,
            "model_originals.invalid_request",
        ),
        (
            "exponent-max",
            read("1e2147483647"),
            json!(999),
            "model_originals.invalid_range",
        ),
        (
            "underflow-noninteger",
            read("1e-2147483647"),
            json!(999),
            "model_originals.invalid_range",
        ),
        (
            "request-byte-limit-one-over",
            oversized,
            Value::Null,
            "model_originals.invalid_request",
        ),
    ];
    let session = SessionId::new(host.manifest["sessionId"].as_str().unwrap()).unwrap();
    for (name, raw, id, expected) in controls {
        let mut socket = host.connect().await;
        let reply = socket.literal(&raw).await;
        closed_profile_failure(&reply, id, expected);
        // A genuine successful next capture establishes the malformed request
        // did not leave this socket with a published/active capture owner.
        let capture = Recorded::new(
            socket
                .raw_call(
                    "morphir.model-originals.capture",
                    capture_params(source, project),
                )
                .await,
        );
        let expectation = CaptureExpectation::from_exchange(&capture.exchange(), &session)
            .unwrap_or_else(|error| panic!("after {name}: {error}: {}", capture.reply));
        let value: Value = serde_json::from_str(&capture.reply).unwrap();
        let id = value["result"]["captureId"].as_str().unwrap();
        let release = Recorded::new(
            socket
                .raw_call(
                    "morphir.model-originals.release",
                    json!({"contractVersion":VERSION,"captureId":id}),
                )
                .await,
        );
        expectation.verify_release(&release.exchange()).unwrap();
        socket.close().await;
    }
    // Exact inclusive byte limit, canonical full-u64 ID, actual request/reply
    // correlation and full capture are distinct from the refusal cases above.
    let mut exact = base.replace("\"id\":999", "\"id\":18446744073709551615");
    exact.push_str(&" ".repeat(16 * 1024 - exact.len()));
    assert_eq!(exact.len(), 16 * 1024);
    let mut socket = host.connect().await;
    let capture = Recorded::new((exact.clone(), socket.literal(&exact).await));
    let expectation = CaptureExpectation::from_exchange(&capture.exchange(), &session).unwrap();
    let value: Value = serde_json::from_str(&capture.reply).unwrap();
    assert_eq!(value["id"].as_u64(), Some(u64::MAX));
    let release = Recorded::new(
        socket
            .raw_call(
                "morphir.model-originals.release",
                json!({"contractVersion":VERSION,"captureId":value["result"]["captureId"]}),
            )
            .await,
    );
    expectation.verify_release(&release.exchange()).unwrap();
    socket.close().await;
}
