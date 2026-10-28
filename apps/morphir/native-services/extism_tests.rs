//! Adapter qualification with real Extism instances. These small fault peers
//! exercise adapter/session boundaries; they do not replace Python acceptance.
use super::extism::{self, Operation};
use morphir_distribution::Sha256Digest;
use morphir_extension_sdk::{
    BackendCapability, ExtensionCapabilities, ExtensionInfo, ExtensionType, FrontendCapability,
    LanguageCapability, claims::CapabilityClaimSet,
};
use serde_json::{Value, json};
use std::{fs, path::Path};

fn info() -> ExtensionInfo {
    ExtensionInfo {
        id: "extism-fault-peer".into(),
        name: "Extism fault peer".into(),
        version: "1.0.0".into(),
        types: vec![ExtensionType::Frontend, ExtensionType::Backend],
        ..Default::default()
    }
}

fn capabilities() -> ExtensionCapabilities {
    ExtensionCapabilities {
        frontend: Some(FrontendCapability {
            languages: vec![LanguageCapability {
                id: "python".into(),
                file_extensions: vec![".py".into()],
            }],
            ir_versions: vec!["3".into(), "4".into()],
            compile: true,
            ..Default::default()
        }),
        backend: Some(BackendCapability {
            targets: vec!["python".into()],
            ir_versions: vec!["3".into(), "4".into()],
            generate: true,
        }),
        ..Default::default()
    }
}

fn claims() -> Value {
    let Value::Object(capabilities) = serde_json::to_value(capabilities()).unwrap() else {
        unreachable!()
    };
    serde_json::to_value(CapabilityClaimSet::from_session(
        vec!["0.1".into()],
        info(),
        capabilities,
    ))
    .unwrap()
}

fn response(id: u64, result: Value) -> Value {
    json!({"jsonrpc":"2.0","id":id,"result":result})
}

struct Responses {
    describe: String,
    initialize: String,
    operation: String,
    shutdown: String,
}

impl Responses {
    fn new(result: Value) -> Self {
        Self {
            describe: response(1, claims()).to_string(),
            initialize: response(
                1,
                json!({"protocolVersion":"0.1","extension":info(),"capabilities":capabilities()}),
            )
            .to_string(),
            operation: response(2, result).to_string(),
            shutdown: response(3, json!({})).to_string(),
        }
    }
}

fn output(text: &str) -> String {
    let writes = text
        .bytes()
        .enumerate()
        .map(|(offset, byte)| {
            format!(
                "(call $store (i64.add (local.get $output) (i64.const {offset})) (i32.const {byte}))"
            )
        })
        .collect::<String>();
    format!(
        "(local.set $output (call $alloc (i64.const {}))) {writes} (call $set (local.get $output) (i64.const {}))",
        text.len(),
        text.len()
    )
}

fn method_match(name: &str, method: &str) -> String {
    // Match the complete compact method member, not a method-prefix or text
    // embedded in a source document. The shared SDK owns request serialization.
    let pattern = format!("\"method\":\"{method}\"");
    let equal = pattern
        .bytes()
        .enumerate()
        .map(|(offset, byte)| {
            format!("(i32.eq (call $input (i64.add (local.get $offset) (i64.const {offset}))) (i32.const {byte}))")
        })
        .reduce(|left, right| format!("(i32.and {left} {right})"))
        .unwrap();
    format!(
        r#"(func ${name} (result i32)
            (local $offset i64)
            (loop $scan
                (if (i64.gt_u (i64.add (local.get $offset) (i64.const {length})) (call $length))
                    (then (return (i32.const 0))))
                (if {equal} (then (return (i32.const 1))))
                (local.set $offset (i64.add (local.get $offset) (i64.const 1)))
                (br $scan))
            (i32.const 0))"#,
        length = pattern.len()
    )
}

fn guest(exported: &ExtensionInfo, responses: &Responses) -> Vec<u8> {
    let methods = [
        (
            "describe",
            "morphir.extension.describe",
            &responses.describe,
        ),
        ("initialize", "morphir.initialize", &responses.initialize),
        ("compile", "morphir.frontend.compile", &responses.operation),
        ("generate", "morphir.backend.generate", &responses.operation),
        ("shutdown", "morphir.shutdown", &responses.shutdown),
    ];
    let matching = methods
        .iter()
        .map(|(name, method, _)| method_match(name, method))
        .collect::<String>();
    let dispatch = methods
        .iter()
        .map(|(name, _, reply)| {
            format!(
                "(if (call ${name}) (then {} (return (i32.const 0))))",
                output(reply)
            )
        })
        .collect::<String>();
    wat::parse_str(format!(
        r#"(module
            (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
            (import "extism:host/env" "store_u8" (func $store (param i64 i32)))
            (import "extism:host/env" "output_set" (func $set (param i64 i64)))
            (import "extism:host/env" "input_load_u8" (func $input (param i64) (result i32)))
            (import "extism:host/env" "input_length" (func $length (result i64)))
            {matching}
            (func (export "morphir_extension_info") (result i32)
                (local $output i64) {metadata} (i32.const 0))
            (func (export "handle") (result i32)
                (local $output i64) {dispatch} (i32.const 1)))"#,
        metadata = output(&serde_json::to_string(exported).unwrap()),
    ))
    .unwrap()
}

struct Bundle {
    _root: tempfile::TempDir,
    request: Value,
    descriptor: Value,
}

impl Bundle {
    fn new(wasm: &[u8], claim_set: Value) -> Self {
        let root = tempfile::tempdir().unwrap();
        fs::create_dir(root.path().join("work")).unwrap();
        fs::write(root.path().join("guest.wasm"), wasm).unwrap();
        let digest = Sha256Digest::of_bytes(wasm).to_string();
        let descriptor = json!({
            "schemaVersion":"2.0.0-draft.2","shortId":"fault","extensionId":info().id,"version":info().version,
            "artifacts":[{"runtime":"wasm","filename":"guest.wasm","sha256":digest,"claims":claim_set}]
        });
        let bytes = serde_json::to_vec(&descriptor).unwrap();
        fs::write(root.path().join("release.json"), &bytes).unwrap();
        let request = json!({
            "operation":"extism.generate","timeout":10000,"workDirectory":root.path().join("work"),
            "pin":{"artifact":{"directory":root.path(),"descriptorSha256":Sha256Digest::of_bytes(&bytes).to_string(),"wasmSha256":digest,"extensionId":info().id,"version":info().version}},
            "params":{"ir":{"formatVersion":4,"distribution":{}},"target":"python","options":{}}
        });
        Self {
            _root: root,
            request,
            descriptor,
        }
    }

    fn update_descriptor(&mut self) {
        let bytes = serde_json::to_vec(&self.descriptor).unwrap();
        fs::write(self._root.path().join("release.json"), &bytes).unwrap();
        self.request["pin"]["artifact"]["descriptorSha256"] =
            json!(Sha256Digest::of_bytes(&bytes).to_string());
    }

    async fn error(&self, operation: Operation) -> String {
        extism::invoke(&self.request, operation)
            .await
            .expect_err("fault guest must refuse")
            .to_string()
    }
}

fn generated() -> Value {
    json!({"success":true,"artifacts":[{"path":"models.py","content":"answer = 42\n","binary":false}],"diagnostics":[]})
}

#[tokio::test]
async fn checked_extism_probe_and_fresh_session_generate() {
    let bundle = Bundle::new(&guest(&info(), &Responses::new(generated())), claims());
    let described = extism::invoke(&bundle.request, Operation::Describe)
        .await
        .unwrap();
    assert_eq!(described["extension"]["id"], info().id);
    assert_eq!(described["provenance"], "asserted");
    assert_eq!(described["containerDropped"], true);
    let result = extism::invoke(&bundle.request, Operation::Generate)
        .await
        .unwrap();
    assert_eq!(result["negotiated"]["protocolVersion"], "0.1");
    assert_eq!(result["result"], generated());
    assert_eq!(result["shutdown"], "acknowledged");
    assert_eq!(result["containerDropped"], true);
    assert_eq!(
        fs::read_dir(bundle._root.path().join("work"))
            .unwrap()
            .count(),
        0
    );
}

#[tokio::test]
async fn descriptor_digest_and_exported_identity_are_checked() {
    let wasm = guest(&info(), &Responses::new(generated()));
    let mut descriptor_digest = Bundle::new(&wasm, claims());
    descriptor_digest.request["pin"]["artifact"]["descriptorSha256"] = json!("0".repeat(64));
    assert!(
        descriptor_digest
            .error(Operation::Describe)
            .await
            .contains("extension.integrity_mismatch")
    );
    let wasm_digest = Bundle::new(&wasm, claims());
    fs::write(wasm_digest._root.path().join("guest.wasm"), b"replacement").unwrap();
    assert!(
        wasm_digest
            .error(Operation::Describe)
            .await
            .contains("extension.integrity_mismatch")
    );
    let mut exported = info();
    exported.version = "9.0.0".into();
    let metadata = Bundle::new(&guest(&exported, &Responses::new(generated())), claims());
    assert!(
        metadata
            .error(Operation::Describe)
            .await
            .contains("extension.identity_mismatch")
    );
    let mut traversal = Bundle::new(&wasm, claims());
    traversal.descriptor["artifacts"][0]["filename"] = json!("../outside.wasm");
    traversal.update_descriptor();
    assert!(
        traversal
            .error(Operation::Describe)
            .await
            .contains("extension.invalid_pin")
    );
}

#[tokio::test]
async fn descriptor_live_claims_and_initialized_capabilities_cannot_drift() {
    let mut bundle = Bundle::new(&guest(&info(), &Responses::new(generated())), claims());
    bundle.descriptor["artifacts"][0]["claims"]["capabilities"]["backend"]["targets"] =
        json!(["other"]);
    bundle.update_descriptor();
    assert!(
        bundle
            .error(Operation::Describe)
            .await
            .contains("extension.capability_mismatch")
    );
    let mut responses = Responses::new(generated());
    let mut changed = serde_json::to_value(capabilities()).unwrap();
    changed["backend"]["targets"] = json!(["other"]);
    responses.initialize = response(
        1,
        json!({"protocolVersion":"0.1","extension":info(),"capabilities":changed}),
    )
    .to_string();
    let drift = Bundle::new(&guest(&info(), &responses), claims());
    assert!(
        drift
            .error(Operation::Generate)
            .await
            .contains("extension.capability_mismatch")
    );
}

fn scope_bundle(capabilities: Value, params: Value) -> Bundle {
    let mut declared = claims();
    declared["capabilities"] = capabilities.clone();
    let mut responses = Responses::new(generated());
    responses.describe = response(1, declared.clone()).to_string();
    responses.initialize = response(
        1,
        json!({"protocolVersion":"0.1","extension":info(),"capabilities":capabilities}),
    )
    .to_string();
    // If a scope check accidentally dispatches, the invalid operation reply
    // fails as invalid_result, rather than the expected capability refusal.
    responses.operation = "operation must not have been dispatched".into();
    let mut bundle = Bundle::new(&guest(&info(), &responses), declared);
    bundle.request["params"] = params;
    bundle
}

#[tokio::test]
async fn matching_claims_still_require_operation_language_ir_count_and_target_scope() {
    let caps = serde_json::to_value(capabilities()).unwrap();
    let mut compile_disabled = caps.clone();
    compile_disabled["frontend"]["compile"] = json!(false);
    let mut language = caps.clone();
    language["frontend"]["languages"][0]["id"] = json!("other");
    let mut compile_ir = caps.clone();
    compile_ir["frontend"]["irVersions"] = json!(["3"]);
    let mut documents = compile_params();
    let mut second = documents["sources"]["documents"][0].clone();
    second["uri"] = json!("rules.py");
    documents["sources"]["documents"]
        .as_array_mut()
        .unwrap()
        .push(second);
    let mut document_language = compile_params();
    document_language["sources"]["documents"][0]["languageId"] = json!("other");
    for (label, capabilities, params) in [
        ("compile flag", compile_disabled, compile_params()),
        ("language", language, compile_params()),
        ("compile IR", compile_ir, compile_params()),
        ("source count", caps.clone(), documents),
        ("document language", caps.clone(), document_language),
    ] {
        let bundle = scope_bundle(capabilities, params);
        let error = bundle.error(Operation::Compile).await;
        assert!(
            error.contains("extension.capability_mismatch"),
            "{label}: {error}"
        );
    }
    let mut generate_disabled = caps.clone();
    generate_disabled["backend"]["generate"] = json!(false);
    let mut target = caps.clone();
    target["backend"]["targets"] = json!(["other"]);
    let mut generate_ir = caps.clone();
    generate_ir["backend"]["irVersions"] = json!(["3"]);
    let params = json!({"ir":{"formatVersion":4,"distribution":{}},"target":"python","options":{}});
    for (label, capabilities) in [
        ("generate flag", generate_disabled),
        ("target", target),
        ("generate IR", generate_ir),
    ] {
        let bundle = scope_bundle(capabilities, params.clone());
        let error = bundle.error(Operation::Generate).await;
        assert!(
            error.contains("extension.capability_mismatch"),
            "{label}: {error}"
        );
    }
}

#[tokio::test]
async fn missing_exports_malformed_envelopes_and_response_ids_fail_closed() {
    let missing = Bundle::new(&wat::parse_str("(module)").unwrap(), claims());
    assert!(
        missing
            .error(Operation::Describe)
            .await
            .contains("morphir_extension_info")
    );
    for output in ["not JSON".to_owned(), response(999, generated()).to_string(),
        json!({"jsonrpc":"2.0","id":2,"result":generated(),"error":{"code":-32603,"message":"both branches"}}).to_string()] {
        let mut responses = Responses::new(generated());
        responses.operation = output;
        let bundle = Bundle::new(&guest(&info(), &responses), claims());
        assert!(bundle.error(Operation::Generate).await.contains("extension.invalid_result"));
    }
    let mut responses = Responses::new(generated());
    responses.describe = response(9, claims()).to_string();
    let wrong_probe_id = Bundle::new(&guest(&info(), &responses), claims());
    assert!(
        wrong_probe_id
            .error(Operation::Describe)
            .await
            .contains("extension.protocol_mismatch")
    );
}

#[tokio::test]
async fn rich_only_peers_and_failed_shutdown_do_not_produce_success() {
    let mut rich_claims = claims();
    rich_claims["protocolVersions"] = json!(["0.2.0-draft.1"]);
    let mut rich = Responses::new(generated());
    rich.describe = response(1, rich_claims.clone()).to_string();
    let bundle = Bundle::new(&guest(&info(), &rich), rich_claims);
    assert!(
        bundle
            .error(Operation::Generate)
            .await
            .contains("extension.protocol_mismatch")
    );
    let mut shutdown = Responses::new(generated());
    shutdown.shutdown =
        json!({"jsonrpc":"2.0","id":3,"error":{"code":-32603,"message":"shutdown refused"}})
            .to_string();
    let bundle = Bundle::new(&guest(&info(), &shutdown), claims());
    assert!(
        bundle
            .error(Operation::Generate)
            .await
            .contains("extension.incomplete_session")
    );
}

#[tokio::test]
async fn unsafe_colliding_and_bad_binary_artifacts_are_rejected_by_shared_checks() {
    for artifacts in [
        json!([{"path":"../escape.py","content":"bad"}]),
        json!([{"path":"Models.py","content":"first"},{"path":"models.py","content":"second"}]),
        json!([{"path":"payload.bin","content":"not base64!","binary":true}]),
    ] {
        let result = json!({"success":true,"artifacts":artifacts,"diagnostics":[]});
        let bundle = Bundle::new(&guest(&info(), &Responses::new(result)), claims());
        assert!(
            bundle
                .error(Operation::Generate)
                .await
                .contains("extension.invalid_result")
        );
    }
}

fn compile_params() -> Value {
    json!({"languageId":"python","sources":{"documents":[{"uri":"models.py","languageId":"python","version":1,"text":"def identity(value: int) -> int:\n    return value\n"}]},"package":{"name":"acme/example"},"dependencies":[],"options":{"typesOnly":false,"irVersion":"4"}})
}

#[tokio::test]
async fn structured_guest_diagnostics_survive_failed_compile_without_transport_failure() {
    for code in ["PY001", "PY005", "PY006"] {
        let location = json!({"uri":"models.py","range":{"start":{"line":1,"character":2},"end":{"line":1,"character":5}}});
        let diagnostics = json!([{"severity":if code == "PY006" { "warning" } else { "error" },"code":code,"message":"kept verbatim","location":location,"related":[{"location":location,"message":"kept related information"}]}]);
        let failed = json!({"success":false,"modules":[],"diagnostics":diagnostics});
        let mut bundle = Bundle::new(&guest(&info(), &Responses::new(failed)), claims());
        bundle.request["params"] = compile_params();
        let result = extism::invoke(&bundle.request, Operation::Compile)
            .await
            .unwrap();
        assert_eq!(result["result"]["success"], false);
        assert_eq!(result["result"]["diagnostics"], diagnostics);
        assert_eq!(result["shutdown"], "acknowledged");
    }
}

fn real_python_request() -> Value {
    let bundle = std::env::var("MORPHIR_EXTISM_TEST_BUNDLE")
        .expect("set MORPHIR_EXTISM_TEST_BUNDLE to a verified real Python release bundle");
    let directory = Path::new(&bundle).canonicalize().unwrap();
    let bytes = fs::read(directory.join("release.json")).unwrap();
    let descriptor: Value = serde_json::from_slice(&bytes).unwrap();
    let selected = descriptor["artifacts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["runtime"] == "wasm")
        .unwrap();
    json!({"operation":"extism.compile","timeout":30000,"pin":{"artifact":{"directory":directory,"descriptorSha256":Sha256Digest::of_bytes(&bytes).to_string(),"wasmSha256":selected["sha256"],"extensionId":descriptor["extensionId"],"version":descriptor["version"]}},"params":compile_params()})
}

#[tokio::test]
#[ignore = "requires a real pinned Python release in MORPHIR_EXTISM_TEST_BUNDLE"]
async fn real_python_parse_stage_warning_and_unknown_option_are_preserved() {
    let work = tempfile::tempdir().unwrap();
    let mut request = real_python_request();
    request["workDirectory"] = json!(work.path());
    let description = extism::invoke(&request, Operation::Describe).await.unwrap();
    let mut multiple = request.clone();
    let mut second = multiple["params"]["sources"]["documents"][0].clone();
    second["uri"] = json!("rules.py");
    multiple["params"]["sources"]["documents"]
        .as_array_mut()
        .unwrap()
        .push(second);
    if description["result"]["capabilities"]["frontend"]["multiDocument"] != true {
        // The real 0.4.1 release omits multiDocument. Actual multi-module
        // behavior cannot grant authority that its live claim did not offer.
        let error = extism::invoke(&multiple, Operation::Compile)
            .await
            .unwrap_err()
            .to_string();
        assert!(error.contains("extension.capability_mismatch"), "{error}");
    } else {
        let result = extism::invoke(&multiple, Operation::Compile).await.unwrap();
        assert_eq!(result["result"]["success"], true);
    }
    request["params"]["options"]["emitParseStage"] = json!(true);
    let result = extism::invoke(&request, Operation::Compile).await.unwrap();
    assert_eq!(result["result"]["success"], true);
    assert!(
        result["result"]["diagnostics"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["code"] == "PY006" && d["severity"] == "warning")
    );
    request["params"]["options"] = json!({"typesOnly":false,"irVersion":"4","unknownOption":true});
    let result = extism::invoke(&request, Operation::Compile).await.unwrap();
    assert_eq!(result["result"]["success"], false);
    assert!(
        result["result"]["diagnostics"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["code"] == "PY001")
    );
}

#[tokio::test]
#[ignore = "requires a real pinned Python release in MORPHIR_EXTISM_TEST_BUNDLE"]
async fn real_python_invalid_ir_diagnostic_is_preserved() {
    let work = tempfile::tempdir().unwrap();
    let mut request = real_python_request();
    request["workDirectory"] = json!(work.path());
    request["params"] =
        json!({"ir":{"formatVersion":4,"distribution":"invalid"},"target":"python","options":{}});
    let result = extism::invoke(&request, Operation::Generate).await.unwrap();
    assert_eq!(result["result"]["success"], false);
    assert!(
        result["result"]["diagnostics"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["code"] == "PY005")
    );
}
