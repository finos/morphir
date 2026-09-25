//! Offline smoke for the downloaded CLI's single-file metadata preview.

use std::path::Path;
use std::process::Output;

use morphir_common::ir_transport::{
    CodecOptions, FormatId, IonCodec, IrCodec, IrVersion, JsonCodec, Layout,
};
use serde_json::{Value, json};

use super::{read_json, stderr, stdout};

const SUBJECT: &str = "morphir://ir/pkg/acme/orders?format=4.1.0#/module/api";
const PREDICATE: &str =
    "morphir://ir/pkg/acme/metadata?format=4.0.0#/module/lifecycle/value/deprecated";

pub(super) fn qualify(work: &Path, run: &impl Fn(&[&str]) -> Output, denied_probe: Option<&str>) {
    let document = json!({
        "formatVersion": "4.1.0",
        "$meta": {
            "@context": {"deprecated": PREDICATE},
            "@graph": [{"@id": SUBJECT, "deprecated": true}]
        },
        "distribution": {"Library": {
            "packageName": "acme/orders",
            "dependencies": {},
            "def": {"modules": {"api": {"Public": {"types": {}, "values": {}}}}}
        }}
    });
    let json_text = document.to_string();
    let json_path = work.join("metadata.json");
    let yaml_path = work.join("metadata.yaml");
    let ion_path = work.join("metadata.ion");
    std::fs::write(&json_path, &json_text).unwrap();
    let (file, _) = morphir_core::ir::json::read_ir_file(&json_text).unwrap();
    std::fs::write(&yaml_path, morphir_core::ir::yaml::write_ir_file(&file)).unwrap();
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
                &mut std::io::Cursor::new(json_text),
                &json_options,
                sink.as_mut(),
            )
            .unwrap();
    }
    std::fs::write(&ion_path, ion_bytes).unwrap();

    let mut fact_sets = Vec::new();
    for path in [&json_path, &yaml_path, &ion_path] {
        let output = run(&[
            "metadata",
            "query",
            "--ir",
            path.to_str().unwrap(),
            "--subject",
            SUBJECT,
        ]);
        assert!(
            output.status.success(),
            "{}: {}\n{}",
            path.display(),
            stdout(&output),
            stderr(&output)
        );
        let result: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(result["semanticStatus"], "unvalidated");
        assert_eq!(result["facts"].as_array().unwrap().len(), 1);
        assert_eq!(result["facts"][0]["predicate"], PREDICATE);
        assert_eq!(result["facts"][0]["object"], json!({"@value": true}));
        fact_sets.push(result["facts"].clone());
    }
    assert_eq!(fact_sets[0], fact_sets[1]);
    assert_eq!(fact_sets[0], fact_sets[2]);

    let export = work.join("metadata-export");
    let output = run(&[
        "metadata",
        "export",
        "--ir",
        json_path.to_str().unwrap(),
        "--output",
        export.to_str().unwrap(),
        "--context-storage",
        "external",
    ]);
    assert!(
        output.status.success(),
        "metadata export: {}\n{}",
        stdout(&output),
        stderr(&output)
    );
    let published = read_json(&export.join("ir.json"));
    let context = published["$meta"]["@context"].as_str().unwrap();
    assert!(export.join(context).is_file());
    let output = run(&[
        "metadata",
        "query",
        "--ir",
        export.join("ir.json").to_str().unwrap(),
        "--subject",
        SUBJECT,
    ]);
    assert!(
        output.status.success(),
        "metadata exported query: {}\n{}",
        stdout(&output),
        stderr(&output)
    );
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["facts"], fact_sets[0]);
    std::fs::write(
        work.join("metadata-preview.json"),
        serde_json::to_vec_pretty(&json!({
            "networkDenial": denied_probe,
            "profiles": ["json", "yaml", "ion"],
            "factCount": 1,
            "semanticStatus": "unvalidated",
            "externalContextReuse": true
        }))
        .unwrap(),
    )
    .unwrap();
}
