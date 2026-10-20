// Frozen schema-authored setup corpus. Gzip bytes and full decoded JSON are hash/size bounded.
use super::*;
use std::io::Read;
#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Corpus {
    kind: String,
    cases: Vec<Case>,
}
#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Case {
    id: String,
    #[serde(rename = "typeName")]
    type_name: String,
    #[serde(rename = "sourceSchemaPointer")]
    source_pointer: String,
    #[serde(rename = "rawJson")]
    raw: String,
    #[serde(rename = "rawUTF8ByteLength")]
    raw_bytes: usize,
    #[serde(rename = "rawSHA256")]
    raw_sha256: String,
    accepts: bool,
    category: String,
    reason: String,
    #[serde(rename = "expectationScope")]
    scope: String,
}
fn decode_case(name: &str, raw: &str) -> Result<(), DecodeError> {
    let mut owner = Decoder::new(
        DecodeLimits::new(
            16_777_216,
            1_073_741_824,
            4_000_000,
            1_073_741_824,
            4_000_000,
        )
        .unwrap(),
    );
    match name {
        "AtomicBytes" => owner.decode::<input::AtomicBytes>(raw).map(|_| ()),
        "AtomicBytesHexHex" => owner.decode::<input::AtomicBytesHexHex>(raw).map(|_| ()),
        "Bytes" => owner.decode::<input::Bytes>(raw).map(|_| ()),
        "BytesHexHex" => owner.decode::<input::BytesHexHex>(raw).map(|_| ()),
        "ClientAction" => owner.decode::<input::ClientAction>(raw).map(|_| ()),
        "ClientActionStartImportVia" => owner
            .decode::<input::ClientActionStartImportVia>(raw)
            .map(|_| ()),
        "ClientActionStartConnectedScope" => owner
            .decode::<input::ClientActionStartConnectedScope>(raw)
            .map(|_| ()),
        "ClientActionStartConnectedSemantic" => owner
            .decode::<input::ClientActionStartConnectedSemantic>(raw)
            .map(|_| ()),
        "ClientActionReadRunEffectKind" => owner
            .decode::<input::ClientActionReadRunEffectKind>(raw)
            .map(|_| ()),
        "ClientActionReadRunExpectedRequest" => owner
            .decode::<input::ClientActionReadRunExpectedRequest>(raw)
            .map(|_| ()),
        "ClientActionReadRunExpectedRequestContractVersion" => owner
            .decode::<input::ClientActionReadRunExpectedRequestContractVersion>(raw)
            .map(|_| ()),
        "ClientActionReadRunExpectedRequestMethod" => owner
            .decode::<input::ClientActionReadRunExpectedRequestMethod>(raw)
            .map(|_| ()),
        "ClientActionReadRunWindow" => owner
            .decode::<input::ClientActionReadRunWindow>(raw)
            .map(|_| ()),
        "ClientActionMutateCallerReplacement" => owner
            .decode::<input::ClientActionMutateCallerReplacement>(raw)
            .map(|_| ()),
        "ClientActionDownloadOriginalTarget" => owner
            .decode::<input::ClientActionDownloadOriginalTarget>(raw)
            .map(|_| ()),
        "ClientActionSubmitExecutionExecutionMode" => owner
            .decode::<input::ClientActionSubmitExecutionExecutionMode>(raw)
            .map(|_| ()),
        "ClientActionBeginLocalEvaluationExecutionMode" => owner
            .decode::<input::ClientActionBeginLocalEvaluationExecutionMode>(raw)
            .map(|_| ()),
        "ClientActionAwaitNativeBoundaryBoundary" => owner
            .decode::<input::ClientActionAwaitNativeBoundaryBoundary>(raw)
            .map(|_| ()),
        "ClientActionBindNativeProjectProjectId" => owner
            .decode::<input::ClientActionBindNativeProjectProjectId>(raw)
            .map(|_| ()),
        "ClientActionBeginConnectedOpeningScope" => owner
            .decode::<input::ClientActionBeginConnectedOpeningScope>(raw)
            .map(|_| ()),
        "ClientActionBeginConnectedOpeningSemantic" => owner
            .decode::<input::ClientActionBeginConnectedOpeningSemantic>(raw)
            .map(|_| ()),
        "ClientActionAwaitConnectedBoundaryBoundary" => owner
            .decode::<input::ClientActionAwaitConnectedBoundaryBoundary>(raw)
            .map(|_| ()),
        "ClientFixture" => owner.decode::<input::ClientFixture>(raw).map(|_| ()),
        "ClientFixtureFilesItem" => owner
            .decode::<input::ClientFixtureFilesItem>(raw)
            .map(|_| ()),
        "ClientFixtureLiteralPeersItem" => owner
            .decode::<input::ClientFixtureLiteralPeersItem>(raw)
            .map(|_| ()),
        "ClientRuntime" => owner.decode::<input::ClientRuntime>(raw).map(|_| ()),
        "ClientRuntimeControlledModelOriginalsHttpV1Manifest" => owner
            .decode::<input::ClientRuntimeControlledModelOriginalsHttpV1Manifest>(raw)
            .map(|_| ()),
        "ClientRuntimeControlledModelOriginalsHttpV1ManifestPath" => owner
            .decode::<input::ClientRuntimeControlledModelOriginalsHttpV1ManifestPath>(raw)
            .map(|_| ()),
        "ClientRuntimeControlledNativeWorkspaceV1EntryUrl" => owner
            .decode::<input::ClientRuntimeControlledNativeWorkspaceV1EntryUrl>(raw)
            .map(|_| ()),
        "ClientRuntimeControlledNativeWorkspaceV1Mapping" => owner
            .decode::<input::ClientRuntimeControlledNativeWorkspaceV1Mapping>(raw)
            .map(|_| ()),
        "ConfigPolicy" => owner.decode::<input::ConfigPolicy>(raw).map(|_| ()),
        "ConnectedTransferLimits" => owner
            .decode::<input::ConnectedTransferLimits>(raw)
            .map(|_| ()),
        "Count" => owner.decode::<input::Count>(raw).map(|_| ()),
        "DeliveredReply" => owner.decode::<input::DeliveredReply>(raw).map(|_| ()),
        "DeliveredReplyTextOperation" => owner
            .decode::<input::DeliveredReplyTextOperation>(raw)
            .map(|_| ()),
        "DeliveredReplyVoidOperation" => owner
            .decode::<input::DeliveredReplyVoidOperation>(raw)
            .map(|_| ()),
        "EffectKind" => owner.decode::<input::EffectKind>(raw).map(|_| ()),
        "EffectRef" => owner.decode::<input::EffectRef>(raw).map(|_| ()),
        "Entry" => owner.decode::<input::Entry>(raw).map(|_| ()),
        "Frame" => owner.decode::<input::Frame>(raw).map(|_| ()),
        "FramePart" => owner.decode::<input::FramePart>(raw).map(|_| ()),
        "Guest" => owner.decode::<input::Guest>(raw).map(|_| ()),
        "GuestKind" => owner.decode::<input::GuestKind>(raw).map(|_| ()),
        "HostAction" => owner.decode::<input::HostAction>(raw).map(|_| ()),
        "HostActionAwaitBoundaryCaptureAt" => owner
            .decode::<input::HostActionAwaitBoundaryCaptureAt>(raw)
            .map(|_| ()),
        "HostActionAwaitBoundaryCaptureOwner" => owner
            .decode::<input::HostActionAwaitBoundaryCaptureOwner>(raw)
            .map(|_| ()),
        "HostActionAwaitBoundaryCaptureOwnerKind" => owner
            .decode::<input::HostActionAwaitBoundaryCaptureOwnerKind>(raw)
            .map(|_| ()),
        "HostActionAwaitBoundaryWriterAt" => owner
            .decode::<input::HostActionAwaitBoundaryWriterAt>(raw)
            .map(|_| ()),
        "HostActionAwaitBoundaryWriterOwner" => owner
            .decode::<input::HostActionAwaitBoundaryWriterOwner>(raw)
            .map(|_| ()),
        "HostActionAwaitBoundaryWriterOwnerKind" => owner
            .decode::<input::HostActionAwaitBoundaryWriterOwnerKind>(raw)
            .map(|_| ()),
        "HostActionAwaitBoundary" => owner
            .decode::<input::HostActionAwaitBoundary>(raw)
            .map(|_| ()),
        "HostActionConnectAuthentication" => owner
            .decode::<input::HostActionConnectAuthentication>(raw)
            .map(|_| ()),
        "HostActionCaptureSelectedScope" => owner
            .decode::<input::HostActionCaptureSelectedScope>(raw)
            .map(|_| ()),
        "HostActionCaptureSelectedSemantic" => owner
            .decode::<input::HostActionCaptureSelectedSemantic>(raw)
            .map(|_| ()),
        "HostActionReadSelectedTarget" => owner
            .decode::<input::HostActionReadSelectedTarget>(raw)
            .map(|_| ()),
        "HostActionBeginCaptureSelectedScope" => owner
            .decode::<input::HostActionBeginCaptureSelectedScope>(raw)
            .map(|_| ()),
        "HostActionBeginCaptureSelectedSemantic" => owner
            .decode::<input::HostActionBeginCaptureSelectedSemantic>(raw)
            .map(|_| ()),
        "HostActionHoldCooperatingCompileAt" => owner
            .decode::<input::HostActionHoldCooperatingCompileAt>(raw)
            .map(|_| ()),
        "HostActionProducerMessageBoundaryStage" => owner
            .decode::<input::HostActionProducerMessageBoundaryStage>(raw)
            .map(|_| ()),
        "HostBoundary" => owner.decode::<input::HostBoundary>(raw).map(|_| ()),
        "HostFixture" => owner.decode::<input::HostFixture>(raw).map(|_| ()),
        "HostFixtureGrantsItem" => owner
            .decode::<input::HostFixtureGrantsItem>(raw)
            .map(|_| ()),
        "HostFixtureRecordsItem" => owner
            .decode::<input::HostFixtureRecordsItem>(raw)
            .map(|_| ()),
        "HostFixtureStartup" => owner.decode::<input::HostFixtureStartup>(raw).map(|_| ()),
        "HostFixtureStartupOutputOverride" => owner
            .decode::<input::HostFixtureStartupOutputOverride>(raw)
            .map(|_| ()),
        "HostNode" => owner.decode::<input::HostNode>(raw).map(|_| ()),
        "HostNodeEntrySeriesEntry" => owner
            .decode::<input::HostNodeEntrySeriesEntry>(raw)
            .map(|_| ()),
        "JsonDeliveryOperation" => owner
            .decode::<input::JsonDeliveryOperation>(raw)
            .map(|_| ()),
        "Limits" => owner.decode::<input::Limits>(raw).map(|_| ()),
        "LimitsCorpusBytes" => owner.decode::<input::LimitsCorpusBytes>(raw).map(|_| ()),
        "LimitsEvents" => owner.decode::<input::LimitsEvents>(raw).map(|_| ()),
        "LimitsEvidenceBytes" => owner.decode::<input::LimitsEvidenceBytes>(raw).map(|_| ()),
        "LimitsInputBytes" => owner.decode::<input::LimitsInputBytes>(raw).map(|_| ()),
        "LimitsObservationsBytes" => owner
            .decode::<input::LimitsObservationsBytes>(raw)
            .map(|_| ()),
        "LimitsReportBytes" => owner.decode::<input::LimitsReportBytes>(raw).map(|_| ()),
        "ModelCodec" => owner.decode::<input::ModelCodec>(raw).map(|_| ()),
        "PacketRef" => owner.decode::<input::PacketRef>(raw).map(|_| ()),
        "PacketRefPacket" => owner.decode::<input::PacketRefPacket>(raw).map(|_| ()),
        "PickerSignal" => owner.decode::<input::PickerSignal>(raw).map(|_| ()),
        "ProjectBinding" => owner.decode::<input::ProjectBinding>(raw).map(|_| ()),
        "Provider" => owner.decode::<input::Provider>(raw).map(|_| ()),
        "RawJsonSource" => owner.decode::<input::RawJsonSource>(raw).map(|_| ()),
        "ReadRun" => owner.decode::<input::ReadRun>(raw).map(|_| ()),
        "ReadRunEffectKind" => owner.decode::<input::ReadRunEffectKind>(raw).map(|_| ()),
        "ReadRunExpectedRequest" => owner
            .decode::<input::ReadRunExpectedRequest>(raw)
            .map(|_| ()),
        "ReadRunExpectedRequestContractVersion" => owner
            .decode::<input::ReadRunExpectedRequestContractVersion>(raw)
            .map(|_| ()),
        "ReadRunExpectedRequestMethod" => owner
            .decode::<input::ReadRunExpectedRequestMethod>(raw)
            .map(|_| ()),
        "ReadRunKind" => owner.decode::<input::ReadRunKind>(raw).map(|_| ()),
        "ReadRunWindow" => owner.decode::<input::ReadRunWindow>(raw).map(|_| ()),
        "ReadRunPart" => owner.decode::<input::ReadRunPart>(raw).map(|_| ()),
        "ReadTarget" => owner.decode::<input::ReadTarget>(raw).map(|_| ()),
        "RejectedEffect" => owner.decode::<input::RejectedEffect>(raw).map(|_| ()),
        "RejectedEffectKind" => owner.decode::<input::RejectedEffectKind>(raw).map(|_| ()),
        "RejectedEffectName" => owner.decode::<input::RejectedEffectName>(raw).map(|_| ()),
        "Run" => owner.decode::<input::Run>(raw).map(|_| ()),
        "Scenario" => owner.decode::<input::Scenario>(raw).map(|_| ()),
        "SourceIdentity" => owner.decode::<input::SourceIdentity>(raw).map(|_| ()),
        "U8" => owner.decode::<input::U8>(raw).map(|_| ()),
        "@leaf/FixtureAlias" => owner.decode::<decode::FixtureAlias>(raw).map(|_| ()),
        "@leaf/RawJson" => owner.decode::<decode::RawJson>(raw).map(|_| ()),
        "@leaf/ContentSha256" => owner.decode::<decode::ContentSha256>(raw).map(|_| ()),
        "@leaf/SourcePath" => owner.decode::<decode::SourcePath>(raw).map(|_| ()),
        "@leaf/U64Token" => owner.decode::<decode::U64Token>(raw).map(|_| ()),
        _ => panic!("unmapped independently authored input type {name}"),
    }
}
#[test]
fn frozen_input_corpus_covers_types_variants_bounds_and_presence() {
    const ENCODED_SIZE: usize = 186861;
    const DECODED_SIZE: usize = 33444598;
    let encoded = include_bytes!("cases.json.gz");
    assert_eq!(encoded.len(), ENCODED_SIZE);
    assert_eq!(
        crate::kit::hash::sha256_hex(encoded),
        "4608d1bf86e28e8a0b7314cfce76d2c7892c4c5866478b9d4c0c5005beca912a"
    );
    let mut bytes = Vec::with_capacity(DECODED_SIZE);
    flate2::read::GzDecoder::new(encoded.as_slice())
        .take((DECODED_SIZE as u64) + 1)
        .read_to_end(&mut bytes)
        .unwrap();
    assert_eq!(bytes.len(), DECODED_SIZE);
    assert_eq!(
        crate::kit::hash::sha256_hex(&bytes),
        "3af681b4e2a6defde25cdba9248e205ec6ef744116a367233beebb2fb6c98439"
    );
    let corpus: Corpus = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(corpus.kind, "independent-input-v27-decoder-corpus");
    assert_eq!(corpus.cases.len(), 2106);
    let mut ordinary = 0;
    let mut nested = 0;
    let mut originals = 0;
    for case in corpus.cases {
        assert_eq!(case.raw.len(), case.raw_bytes);
        assert_eq!(
            crate::kit::hash::sha256_hex(case.raw.as_bytes()),
            case.raw_sha256
        );
        assert!(case.source_pointer.starts_with("#/"));
        assert!(!case.reason.is_empty());
        assert!(matches!(
            case.scope.as_str(),
            "schema" | "schema-and-description" | "description-role-validation"
        ));
        if case.category == "expanded-tagged-variant" {
            ordinary += 1;
        }
        if case.category == "expanded-nested-tagged-variant" {
            nested += 1;
        }
        if case.category == "original21-boundary" {
            originals += 1;
        }
        let result = decode_case(&case.type_name, &case.raw);
        if let Err(
            DecodeError::Limits
            | DecodeError::SavedBytes
            | DecodeError::Work(_)
            | DecodeError::Allocation
            | DecodeError::Literal(
                crate::json::strict::StrictReadError::Work(_)
                | crate::json::strict::StrictReadError::Limits,
            ),
        ) = &result
        {
            panic!(
                "case {} exhausted resources instead of its authored shape: {result:?}",
                case.id
            );
        }
        assert_eq!(
            result.is_ok(),
            case.accepts,
            "case {} type {} category {} result {result:?}",
            case.id,
            case.type_name,
            case.category
        );
    }
    assert_eq!(ordinary, 121);
    assert_eq!(nested, 2);
    assert_eq!(originals, 21);
}
