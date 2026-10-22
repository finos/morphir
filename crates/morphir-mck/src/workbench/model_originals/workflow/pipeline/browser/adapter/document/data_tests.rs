//! Literal DATA projection controls. No browser, factual owner or runtime proof.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::policy::Policy;

fn decoder() -> Decoder {
    let policy = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
    ));
    Policy::from_document(&Document::parse_unsigned_counts(policy.as_bytes()).unwrap())
        .unwrap()
        .owners()
        .decode
}
fn projected(
    payload: &[u8],
    kind: u8,
    sequence: u64,
) -> Result<BrowserDocumentFrameData, BrowserDocumentError> {
    let mut decode = decoder();
    let raw = decode.raw_literal(payload)?;
    decode_frame_data(&mut decode, kind, sequence, payload, raw)
}
fn token<'a>(payload: &'a [u8], span: &BrowserJsonStringSpan) -> &'a [u8] {
    &payload[span.range()]
}

#[test]
fn browser_document_data_01_original_payload_spans_preserve_nested_utf16_tokens_and_whitespace() {
    let payload = br#"{"kind":"project-selected","sequence":1,"actual":{"workspace":"w\ud800","opening":0,"attempt":"a\udfff","openingOrdinal":1},"sessionId":"s\u0000","providerId":"p\\q","locator":"x\u0061","projectId":"\ud800\udc00"} "#;
    // Actual leading whitespace, not an escaped JSON string prefix.
    let mut bytes = b" \r\n ".to_vec();
    bytes.extend_from_slice(payload);
    let frame = projected(&bytes, 1, 1).unwrap();
    assert_eq!(frame.sequence().get(), 1);
    let BrowserDocumentContent::Fact(BrowserDocumentFactData::ProjectSelected {
        actual,
        selection,
    }) = frame.content()
    else {
        panic!("closed project selection")
    };
    assert_eq!(actual.visit().opening().get(), 0);
    assert_eq!(actual.opening_ordinal().get(), 1);
    for (span, expected) in [
        (actual.visit().workspace(), br#""w\ud800""#.as_slice()),
        (actual.attempt(), br#""a\udfff""#),
        (selection.source().session_id(), br#""s\u0000""#),
        (selection.source().provider_id(), br#""p\\q""#),
        (selection.source().locator(), br#""x\u0061""#),
        (selection.project_id(), br#""\ud800\udc00""#),
    ] {
        assert_eq!(token(&bytes, span), expected);
    }
    // Offsets remain DATA after the raw payload moves into a framed journal.
    let mut journal = vec![0; 29];
    journal.extend_from_slice(&bytes);
    assert_eq!(
        token(&journal[29..], selection.project_id()),
        br#""\ud800\udc00""#
    );
}

#[test]
fn browser_document_data_02_all_thirteen_closed_fact_tags_project_their_actual_owner_shape() {
    let visit = r#""workspace":"w","opening":0"#;
    let opening = format!(r#"{visit},"attempt":"a","openingOrdinal":1"#);
    let inventory = format!(r#"{opening},"inventoryRevision":"r""#);
    let archive = format!(r#"{inventory},"operationOrdinal":2"#);
    let ready = format!(r#"{archive},"readyOrdinal":3"#);
    for (tag, owner, tail) in [
        ("opening-stored", opening.as_str(), ""),
        (
            "source-selected",
            opening.as_str(),
            r#", "sessionId":"s","providerId":"p","locator":"l""#,
        ),
        (
            "project-selected",
            opening.as_str(),
            r#", "sessionId":"s","providerId":"p","locator":"l","projectId":"j""#,
        ),
        (
            "transfer-verified",
            opening.as_str(),
            r#", "sessionId":"s","providerId":"p","locator":"l","projectId":"j""#,
        ),
        ("inventory-adopted", inventory.as_str(), ""),
        ("archive-stored", archive.as_str(), ""),
        ("archive-retirement-requested", archive.as_str(), ""),
        ("archive-settled-retired", archive.as_str(), ""),
        ("archive-ready", ready.as_str(), ""),
        ("download-will-request", ready.as_str(), ""),
        (
            "download-result",
            ready.as_str(),
            r#", "outcome":{"kind":"returned","result":"download-requested"}"#,
        ),
        ("model-closed", visit, ""),
        ("workspace-closed", visit, ""),
    ] {
        let bytes =
            format!(r#"{{"kind":"{tag}","sequence":1,"actual":{{{owner}}}{tail}}}"#).into_bytes();
        let frame = projected(&bytes, 1, 1).unwrap();
        let BrowserDocumentContent::Fact(fact) = frame.content() else {
            panic!("FACT required")
        };
        let actual_tag = match fact {
            BrowserDocumentFactData::OpeningStored(_) => "opening-stored",
            BrowserDocumentFactData::SourceSelected { .. } => "source-selected",
            BrowserDocumentFactData::ProjectSelected { .. } => "project-selected",
            BrowserDocumentFactData::TransferVerified { .. } => "transfer-verified",
            BrowserDocumentFactData::InventoryAdopted(_) => "inventory-adopted",
            BrowserDocumentFactData::ArchiveStored(_) => "archive-stored",
            BrowserDocumentFactData::ArchiveRetirementRequested(_) => {
                "archive-retirement-requested"
            }
            BrowserDocumentFactData::ArchiveSettledRetired(_) => "archive-settled-retired",
            BrowserDocumentFactData::ArchiveReady(_) => "archive-ready",
            BrowserDocumentFactData::DownloadWillRequest(_) => "download-will-request",
            BrowserDocumentFactData::DownloadResult { .. } => "download-result",
            BrowserDocumentFactData::ModelClosed(_) => "model-closed",
            BrowserDocumentFactData::WorkspaceClosed(_) => "workspace-closed",
        };
        assert_eq!(actual_tag, tag);
    }
}

#[test]
fn browser_document_data_03_closed_end_and_download_outcomes_keep_semantic_distinctions() {
    let end = projected(br#"{"lastSequence":0,"observer":{"kind":"closed"}}"#, 2, 1).unwrap();
    assert!(
        matches!(end.content(), BrowserDocumentContent::End { last_sequence } if last_sequence.get()==0)
    );
    for (json, expected) in [
        (r#"{"kind":"raised"}"#, BrowserDownloadOutcomeData::Raised),
        (
            r#"{"kind":"returned","result":"download-requested"}"#,
            BrowserDownloadOutcomeData::Returned(BrowserDownloadResultData::DownloadRequested),
        ),
        (
            r#"{"kind":"returned","result":"retired"}"#,
            BrowserDownloadOutcomeData::Returned(BrowserDownloadResultData::Retired),
        ),
        (
            r#"{"kind":"returned","result":"failed"}"#,
            BrowserDownloadOutcomeData::Returned(BrowserDownloadResultData::Failed),
        ),
    ] {
        let bytes = format!(r#"{{"kind":"download-result","sequence":1,"actual":{{"workspace":"w","opening":0,"attempt":"a","openingOrdinal":1,"inventoryRevision":"r","operationOrdinal":2,"readyOrdinal":3}},"outcome":{json}}}"#).into_bytes();
        let frame = projected(&bytes, 1, 1).unwrap();
        assert!(
            matches!(frame.content(), BrowserDocumentContent::Fact(BrowserDocumentFactData::DownloadResult { outcome, .. }) if *outcome==expected)
        );
    }
}

#[test]
fn browser_document_data_04_invalid_shape_sequence_and_incomplete_end_never_mint_projection() {
    for (payload, kind, sequence, expected) in [
        (br#"{"kind":"model-closed","sequence":2,"actual":{"workspace":"w","opening":0}}"#.as_slice(),1,1,BrowserDocumentErrorKind::Order),
        (br#"{"kind":"opening-stored","sequence":1,"actual":{"workspace":"w","opening":0,"attempt":"a","openingOrdinal":0}}"#,1,1,BrowserDocumentErrorKind::Shape),
        (br#"{"kind":"model-closed","sequence":1,"actual":{"workspace":"w","opening":0,"extra":0}}"#,1,1,BrowserDocumentErrorKind::Shape),
        (br#"{"kind":"model-closed","sequence":1,"actual":{"workspace":"w","opening":0,"workspace":"different"}}"#,1,1,BrowserDocumentErrorKind::Json),
        (br#"{"lastSequence":0,"observer":{"kind":"active"}}"#,2,1,BrowserDocumentErrorKind::ProducerIncomplete),
    ] { assert_eq!(projected(payload,kind,sequence).unwrap_err().kind(),expected); }
}
