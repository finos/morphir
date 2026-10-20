//! Connected operations belong to a fresh exact draft, independent of local parity.
use super::Capabilities;
use serde_json::{Value, json};

fn capabilities(version: &str, operations: Value, formats: Value) -> Result<Capabilities, String> {
    Capabilities::parse(
        json!({
            "suite":"workbench", "contractVersion":version,
            "binding":"checker-infrastructure-only", "language":"rust-test",
            "operations":operations, "formats":formats
        }),
        version,
    )
}

#[test]
fn connected_server_and_client_use_their_fresh_exact_draft() {
    for operations in [
        json!(["model-originals-server"]),
        json!(["model-originals-client"]),
        json!(["model-originals-server", "model-originals-client"]),
    ] {
        assert!(capabilities("0.1.0-draft.30", operations.clone(), json!(["json"])).is_ok());
        for historical in ["0.1.0-draft.1", "0.1.0-draft.28", "0.1.0-draft.29"] {
            assert!(capabilities(historical, operations.clone(), json!(["json"])).is_err());
        }
        assert!(capabilities("0.1.0-draft.30", operations, json!(["ion-text"])).is_err());
    }
}

#[test]
fn connected_draft_does_not_broaden_historical_local_or_artifact_operations() {
    for operation in [
        "inspect-model",
        "export-model-original",
        "artifact-server",
        "artifact-client",
        "decode-value",
    ] {
        assert!(capabilities("0.1.0-draft.30", json!([operation]), json!(["json"])).is_err());
    }
    assert!(
        capabilities(
            "0.1.0-draft.29",
            json!(["inspect-model", "export-model-original"]),
            json!(["json"])
        )
        .is_ok()
    );
    for version in ["0.1.0-draft.31", "0.1.0-draft.30+extra", "v0.1.0-draft.30"] {
        assert!(capabilities(version, json!(["model-originals-server"]), json!(["json"])).is_err());
    }
}
