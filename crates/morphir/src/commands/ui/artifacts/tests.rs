use super::*;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir_extension_sdk::Artifact;

fn artifact(path: &str, content: &str, binary: bool) -> Artifact {
    Artifact {
        path: path.into(),
        content: content.into(),
        binary,
    }
}

#[test]
fn producer_versions_have_portable_canonical_semver_components() {
    let fixture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../../../spec/workbench/artifacts/0.1.0-draft.1/fixtures/producer-version-boundaries.json"
    ))
    .unwrap();
    for case in fixture["cases"].as_array().unwrap() {
        let version = case["version"].as_str().unwrap();
        let result = Producer::parse("fixture", version);
        assert_eq!(
            result.is_ok(),
            case["accepted"].as_bool().unwrap(),
            "{version}"
        );
        if let Ok(producer) = result {
            assert_eq!(serde_json::to_value(producer).unwrap()["version"], version);
        }
    }
}

#[test]
fn sdk_bytes_preserve_binary_and_text_without_newline_or_bom_conversion() {
    let bytes: Vec<u8> = (0..=255).collect();
    let sdk = vec![
        artifact("all.bin", &STANDARD.encode(&bytes), true),
        artifact("original.txt", "\u{feff}a\r\n\0\n", false),
    ];
    let prepared = PreparedArtifacts::inspect(sdk).unwrap();
    assert_eq!(prepared.decoded_length(), 264);
    let set = prepared.decode().unwrap();
    assert_eq!(set.artifacts[0].content.bytes(), bytes);
    assert_eq!(
        set.artifacts[1].content.bytes(),
        "\u{feff}a\r\n\0\n".as_bytes()
    );
    assert_eq!(
        set.artifacts[0].digest.to_string(),
        "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880"
    );
}

#[test]
fn canonical_base64_is_required_before_decoded_allocation() {
    for content in ["Zg", "Zh==", "Zg===", "Zg==\n", "-w==", "ab=c"] {
        assert_eq!(
            PreparedArtifacts::inspect(vec![artifact("file.bin", content, true)]).unwrap_err(),
            ArtifactError::InvalidContent
        );
    }
    assert_eq!(
        PreparedArtifacts::inspect(vec![artifact("empty.bin", "", true)])
            .unwrap()
            .decode()
            .unwrap()
            .artifacts[0]
            .content
            .bytes(),
        b""
    );
}

#[test]
fn portable_inventory_rejects_unicode_collisions_and_prefixes() {
    assert_eq!(unicode_normalization::UNICODE_VERSION, (17, 0, 0));
    assert_eq!(unicode_casefold::UNICODE_VERSION, (9, 0, 0));
    // Unicode9 folding deliberately does not fold Georgian Mtavruli, added
    // later. Unicode17 NFKC deliberately does normalize these newer letters.
    assert_ne!(portable_path_key("Ა.txt"), portable_path_key("ა.txt"));
    assert_eq!(portable_path_key("𜳖.txt"), "a.txt");
    for paths in [
        ["Straße.txt", "STRASSE.txt"],
        ["K.txt", "K.txt"],
        ["é/a", "e\u{301}/b"],
        ["dir", "DIR/child"],
        ["a", "a"],
    ] {
        assert_eq!(
            PreparedArtifacts::inspect(
                paths
                    .into_iter()
                    .map(|path| artifact(path, "", false))
                    .collect()
            )
            .unwrap_err(),
            ArtifactError::InvalidPathSet
        );
    }
    for path in [
        "COM¹.txt",
        "a\u{7f}",
        "a\u{85}",
        "../escape",
        "/root",
        "a/",
        "trail.",
    ] {
        assert_eq!(
            PreparedArtifacts::inspect(vec![artifact(path, "", false)]).unwrap_err(),
            ArtifactError::InvalidPath
        );
    }
}

#[test]
fn complete_set_limits_are_checked_before_decoding() {
    assert_eq!(
        PreparedArtifacts::inspect(
            (0..257)
                .map(|n| artifact(&format!("{n}"), "", false))
                .collect()
        )
        .unwrap_err(),
        ArtifactError::FileCount
    );
    assert!(
        PreparedArtifacts::inspect(vec![artifact("exact", &"x".repeat(MAX_FILE_BYTES), false)])
            .is_ok()
    );
    assert_eq!(
        PreparedArtifacts::inspect(vec![artifact(
            "over",
            &"x".repeat(MAX_FILE_BYTES + 1),
            false
        )])
        .unwrap_err(),
        ArtifactError::FileSize
    );
    assert_eq!(
        PreparedArtifacts::inspect(
            (0..5)
                .map(|n| artifact(&format!("{n}"), &"x".repeat(MAX_FILE_BYTES), false))
                .collect()
        )
        .unwrap_err(),
        ArtifactError::SetSize
    );
}

#[test]
fn validated_id_and_read_bounds_do_not_expose_unchecked_primitives() {
    assert!(GenerationId::parse("").is_err());
    assert!(GenerationId::parse("x\n").is_err());
    assert!(GenerationId::parse(&"x".repeat(129)).is_err());
    assert!(ChunkLimit::new(0).is_err());
    assert!(ChunkLimit::new(65537).is_err());
    assert!(ChunkLimit::new(65536).is_ok());
    assert!(ByteOffset::new(MAX_FILE_BYTES + 1).is_err());
}

fn context() -> GenerationContext {
    GenerationContext::new(
        SessionId::parse("session-7").unwrap(),
        ProviderId::parse("playground").unwrap(),
        GenerationTarget::parse("fixture").unwrap(),
        GenerationIrVersion::parse("4").unwrap(),
        Producer::parse("fixture-producer", "0.1.0").unwrap(),
    )
}

#[test]
fn retained_generation_is_connection_owned_and_releases_capacity_exactly_once() {
    let capacity = HostArtifactCapacity::default();
    let mut first = ArtifactSession::default();
    let mut second = ArtifactSession::default();
    first.begin(&capacity).unwrap();
    let manifest = first
        .retain(
            PreparedArtifacts::inspect(vec![artifact("f.bin", "AAEC", true)]).unwrap(),
            context(),
            ArtifactDiagnostics::default(),
            &capacity,
        )
        .unwrap();
    assert_eq!(capacity.reserved_bytes(), 3);
    let generation = manifest.generation_id().clone();
    let file = manifest.artifacts()[0].id().clone();
    assert_eq!(
        second
            .read(
                &generation,
                &file,
                ByteOffset::new(0).unwrap(),
                ChunkLimit::new(2).unwrap()
            )
            .unwrap_err(),
        ArtifactError::UnknownHandle
    );
    assert_eq!(
        first.begin(&capacity).unwrap_err(),
        ArtifactError::ActiveGeneration
    );
    let chunk = first
        .read(
            &generation,
            &file,
            ByteOffset::new(1).unwrap(),
            ChunkLimit::new(65536).unwrap(),
        )
        .unwrap();
    assert_eq!(chunk.content(), "AQI=");
    assert_eq!(chunk.next_offset().get(), 3);
    assert_eq!(
        first
            .read(
                &generation,
                &file,
                ByteOffset::new(1).unwrap(),
                ChunkLimit::new(65536).unwrap()
            )
            .unwrap(),
        chunk
    );
    first.release(&generation).unwrap();
    first.release(&generation).unwrap();
    assert_eq!(capacity.reserved_bytes(), 0);
    assert_eq!(
        first
            .read(
                &generation,
                &file,
                ByteOffset::new(0).unwrap(),
                ChunkLimit::new(1).unwrap()
            )
            .unwrap_err(),
        ArtifactError::UnknownHandle
    );
    second.begin(&capacity).unwrap();
    second
        .retain(
            PreparedArtifacts::inspect(vec![artifact("f", "bytes", false)]).unwrap(),
            context(),
            ArtifactDiagnostics::default(),
            &capacity,
        )
        .unwrap();
    assert_eq!(capacity.reserved_bytes(), 5);
    drop(second);
    assert_eq!(capacity.reserved_bytes(), 0);
}

#[test]
fn oversized_encoded_manifest_never_becomes_ready_and_releases_reservation() {
    let paths = (0..256)
        .map(|n| {
            artifact(
                &format!(
                    "{n}/{}",
                    [
                        "a".repeat(250),
                        "b".repeat(250),
                        "c".repeat(250),
                        "d".repeat(250)
                    ]
                    .join("/")
                ),
                "",
                false,
            )
        })
        .collect();
    let capacity = HostArtifactCapacity::default();
    let invocation = capacity.reserve_invocation().unwrap();
    let mut session = ArtifactSession::default();
    session.begin(&capacity).unwrap();
    assert_eq!(
        session
            .retain(
                PreparedArtifacts::inspect(paths).unwrap(),
                context(),
                ArtifactDiagnostics::default(),
                &capacity
            )
            .unwrap_err(),
        ArtifactError::ReplyLimit
    );
    assert_eq!(capacity.reserved_bytes(), 0);
    assert_eq!(capacity.observer().snapshot().active_invocations(), 1);
    drop(invocation);
    assert_eq!(capacity.observer().snapshot().active_invocations(), 0);
    // A failed generation leaves the connection reusable.
    session.begin(&capacity).unwrap();
}

#[test]
fn sdk_diagnostics_are_bounded_before_copying_into_retained_domain() {
    let diagnostic = morphir_extension_sdk::Diagnostic {
        severity: morphir_extension_sdk::DiagnosticSeverity::Error,
        code: None,
        message: "x".repeat(MAX_REPLY_BYTES + 1),
        location: None,
        related: vec![],
    };
    assert_eq!(
        ArtifactDiagnostics::from_sdk(&[diagnostic]).unwrap_err(),
        ArtifactError::ReplyLimit
    );
}

#[test]
fn raw_requests_reject_duplicate_and_rounded_numeric_evidence() {
    let make = |offset: &str| {
        format!(
            r#"{{"contractVersion":"0.1.0-draft.1","generationId":"g","artifactId":"a","offset":{offset},"maxBytes":1}}"#
        )
    };
    for offset in ["0", "-0", "1.0", "1e0", "100e-2"] {
        assert!(decode_read(&make(offset)).is_ok(), "{offset}");
    }
    for offset in [
        "0.1",
        "1e-9999",
        "0.999999999999999999999",
        "16777217",
        "-1",
    ] {
        assert_eq!(
            decode_read(&make(offset)).unwrap_err(),
            ArtifactError::InvalidRange,
            "{offset}"
        );
    }
    let duplicate = make("0").replace("\"offset\":0", "\"offset\":0,\"offset\":1");
    assert_eq!(
        decode_read(&duplicate).unwrap_err(),
        ArtifactError::InvalidRequest
    );
    assert_eq!(
        decode_read(&make("0").replace("\"g\"", r#""\ud800""#)).unwrap_err(),
        ArtifactError::InvalidRequest
    );
}

#[test]
fn literal_generation_inputs_remain_objects_even_with_serde_private_marker_keys() {
    let raw = r#"{"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":{"$serde_json::private::Number":"1"},"irVersion":"4","target":"fixture","options":{"$serde_json::private::RawValue":"{\"x\":1,\"x\":2}"}}}"#;
    let request = decode_generate(raw).unwrap().generation.into_playground();
    assert!(request.ir.is_object());
    assert_eq!(request.ir["$serde_json::private::Number"], "1");
    assert!(request.options.is_object());
    assert_eq!(
        request.options["$serde_json::private::RawValue"],
        r#"{"x":1,"x":2}"#
    );
}

#[test]
fn empty_and_inflight_generations_cannot_bypass_host_descriptor_capacity() {
    let capacity = HostArtifactCapacity::default();
    let mut sessions: Vec<_> = (0..64)
        .map(|_| {
            let mut session = ArtifactSession::default();
            session.begin(&capacity).unwrap();
            session
        })
        .collect();
    assert_eq!(capacity.reserved_generations(), 64);
    let mut excess = ArtifactSession::default();
    assert_eq!(excess.begin(&capacity), Err(ArtifactError::Capacity));
    sessions[0].fail();
    excess.begin(&capacity).unwrap();
    drop(sessions);
    assert_eq!(capacity.reserved_generations(), 1);
    drop(excess);
    assert_eq!(capacity.reserved_generations(), 0);
}

#[test]
fn exact_aggregate_capacity_is_reserved_before_decoding_and_rolled_back() {
    let capacity = HostArtifactCapacity::default();
    let mut first = ArtifactSession::default();
    first.begin(&capacity).unwrap();
    let full = PreparedArtifacts::inspect(
        (0..4)
            .map(|n| artifact(&format!("{n}"), &"x".repeat(MAX_FILE_BYTES), false))
            .collect(),
    )
    .unwrap();
    first
        .retain(full, context(), ArtifactDiagnostics::default(), &capacity)
        .unwrap();
    assert_eq!(capacity.reserved_bytes(), MAX_SET_BYTES);
    let mut second = ArtifactSession::default();
    second.begin(&capacity).unwrap();
    assert_eq!(
        second.retain(
            PreparedArtifacts::inspect(vec![artifact("a", "x", false)]).unwrap(),
            context(),
            ArtifactDiagnostics::default(),
            &capacity
        ),
        Err(ArtifactError::Capacity)
    );
    assert_eq!(capacity.reserved_generations(), 1);
    drop(first);
    assert_eq!(capacity.reserved_bytes(), 0);
}
