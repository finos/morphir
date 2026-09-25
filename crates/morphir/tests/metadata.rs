use morphir_common::ir_transport::{
    CodecOptions, FormatId, IonCodec, IrCodec, IrVersion, JsonCodec, Layout,
};
use serde_json::{Value, json};
use std::process::Command;

const SUBJECT: &str = "morphir://ir/pkg/acme/orders?format=4.1.0#/module/api";
const PREDICATE: &str =
    "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/deprecated";

fn fixture(root: &std::path::Path) -> std::path::PathBuf {
    std::fs::create_dir_all(root.join("contexts")).unwrap();
    std::fs::write(
        root.join("contexts/lifecycle.jsonld"),
        serde_json::to_vec(&json!({"@context":{"deprecated":PREDICATE}})).unwrap(),
    )
    .unwrap();
    let ir = root.join("library.json");
    std::fs::write(&ir, serde_json::to_vec(&json!({
        "formatVersion":"4.1.0",
        "$meta":{"@context":"contexts/lifecycle.jsonld","@graph":[{"@id":SUBJECT,"deprecated":true}]},
        "distribution":{"Library":{"packageName":"acme/orders","dependencies":{},
            "def":{"modules":{"api":{"Public":{"types":{},"values":{}}}}}}}
    })).unwrap()).unwrap();
    ir
}

fn run(args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .args(["--no-banner"])
        .args(args)
        .output()
        .unwrap()
}

#[test]
fn queries_authored_facts_and_exports_contexts_for_offline_reuse() {
    let temp = tempfile::tempdir().unwrap();
    let ir = fixture(temp.path());
    let ir_path = ir.to_str().unwrap();
    let queried = run(&["metadata", "query", "--ir", ir_path, "--subject", SUBJECT]);
    assert!(
        queried.status.success(),
        "{}",
        String::from_utf8_lossy(&queried.stderr)
    );
    let response: Value = serde_json::from_slice(&queried.stdout).unwrap();
    assert_eq!(response["facts"].as_array().unwrap().len(), 1);
    assert_eq!(response["facts"][0]["predicate"], PREDICATE);
    assert_eq!(response["facts"][0]["object"], json!({"@value":true}));
    assert_eq!(response["semanticStatus"], "unvalidated");

    let destination = temp.path().join("published");
    let exported = run(&[
        "metadata",
        "export",
        "--ir",
        ir_path,
        "--output",
        destination.to_str().unwrap(),
        "--context-storage",
        "external",
    ]);
    assert!(
        exported.status.success(),
        "{}",
        String::from_utf8_lossy(&exported.stderr)
    );
    let published: Value =
        serde_json::from_slice(&std::fs::read(destination.join("ir.json")).unwrap()).unwrap();
    let context_path = published["$meta"]["@context"].as_str().unwrap();
    assert!(destination.join(context_path).is_file());
    std::fs::remove_dir_all(temp.path().join("contexts")).unwrap();
    let reused = run(&[
        "metadata",
        "query",
        "--ir",
        destination.join("ir.json").to_str().unwrap(),
    ]);
    assert!(
        reused.status.success(),
        "{}",
        String::from_utf8_lossy(&reused.stderr)
    );
    let reused: Value = serde_json::from_slice(&reused.stdout).unwrap();
    assert_eq!(reused["facts"], response["facts"]);
}

#[test]
fn missing_context_fails_before_any_export_output_is_published() {
    let temp = tempfile::tempdir().unwrap();
    let ir = fixture(temp.path());
    std::fs::remove_dir_all(temp.path().join("contexts")).unwrap();
    let destination = temp.path().join("published");
    let output = run(&[
        "metadata",
        "export",
        "--ir",
        ir.to_str().unwrap(),
        "--output",
        destination.to_str().unwrap(),
        "--context-storage",
        "external",
    ]);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("context resource"));
    assert!(!destination.exists());
}

#[test]
fn query_reads_the_same_fact_from_json_yaml_and_ion() {
    let temp = tempfile::tempdir().unwrap();
    let ir = fixture(temp.path());
    let mut document: Value = serde_json::from_slice(&std::fs::read(&ir).unwrap()).unwrap();
    document["$meta"]["@context"] = json!({"deprecated":PREDICATE});
    std::fs::write(&ir, serde_json::to_vec(&document).unwrap()).unwrap();
    let (file, _) = morphir_core::ir::json::read_ir_file(&document.to_string()).unwrap();
    let yaml = temp.path().join("library.yaml");
    std::fs::write(&yaml, morphir_core::ir::yaml::write_ir_file(&file)).unwrap();

    let ion = temp.path().join("library.ion");
    let json_options = CodecOptions::new(IrVersion::V4, Layout::SingleFile, FormatId::json())
        .with_linked_metadata();
    let ion_options = CodecOptions::new(IrVersion::V4, Layout::SingleFile, FormatId::ion())
        .with_linked_metadata();
    let mut ion_bytes = Vec::new();
    {
        let mut sink = IonCodec::new()
            .encoder(&mut ion_bytes, &ion_options)
            .unwrap();
        JsonCodec::new()
            .decode(
                &mut std::io::Cursor::new(document.to_string()),
                &json_options,
                sink.as_mut(),
            )
            .unwrap();
    }
    std::fs::write(&ion, ion_bytes).unwrap();

    let outputs = [&ir, &yaml, &ion].map(|path| {
        let output = run(&["metadata", "query", "--ir", path.to_str().unwrap()]);
        assert!(
            output.status.success(),
            "{}: {}",
            path.display(),
            String::from_utf8_lossy(&output.stderr)
        );
        let result: Value = serde_json::from_slice(&output.stdout).unwrap();
        result["facts"].clone()
    });
    assert_eq!(outputs[0], outputs[1]);
    assert_eq!(outputs[0], outputs[2]);
}
