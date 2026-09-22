//! Keep released process and WASM frontends on their existing compile envelope.
use morphir_daemon::InvocationMode;
use morphir_extension_sdk::{
    CompileBaseline, CompileDependency, CompileOptions, CompilePackage, CompileRequest,
    SourceDocument,
};
use serde::Serialize;

pub(crate) fn compile_wire_request(
    request: &CompileRequest,
    mode: InvocationMode,
) -> impl Serialize + Sync + '_ {
    match mode {
        InvocationMode::NativeDirect | InvocationMode::NativeMep => CompileWire::Current(request),
        InvocationMode::ProcessMep | InvocationMode::WasmMep => {
            CompileWire::Legacy(LegacyCompileRequest {
                language_id: &request.language_id,
                documents: &request.sources.documents,
                package: &request.package,
                dependencies: &request.dependencies,
                options: LegacyCompileOptions {
                    options: &request.options,
                    source_root_uri: request.sources.root.as_deref(),
                },
                baseline: request.baseline.as_ref(),
            })
        }
    }
}

#[derive(Serialize)]
#[serde(untagged)]
enum CompileWire<'a> {
    Current(&'a CompileRequest),
    Legacy(LegacyCompileRequest<'a>),
}

// Released external providers precede SourceSet. New SDK providers also accept
// this envelope, so retain it until an explicit protocol transition replaces it.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyCompileRequest<'a> {
    language_id: &'a str,
    documents: &'a [SourceDocument],
    package: &'a CompilePackage,
    dependencies: &'a [CompileDependency],
    options: LegacyCompileOptions<'a>,
    #[serde(skip_serializing_if = "Option::is_none")]
    baseline: Option<&'a CompileBaseline>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LegacyCompileOptions<'a> {
    #[serde(flatten)]
    options: &'a CompileOptions,
    #[serde(skip_serializing_if = "Option::is_none")]
    source_root_uri: Option<&'a str>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_extension_sdk::{CompileOptions, CompilePackage, SourceDocument, SourceSet};
    use serde_json::json;

    #[test]
    fn external_compile_envelope_preserves_released_provider_documents_and_root() {
        let request = CompileRequest {
            language_id: "gleam".into(),
            sources: SourceSet {
                root: Some("file:///project/src".into()),
                documents: vec![SourceDocument {
                    uri: "file:///project/src/nested/main.gleam".into(),
                    language_id: "gleam".into(),
                    version: 1,
                    text: "pub fn answer() { 42 }".into(),
                }],
            },
            package: CompilePackage {
                name: "example/main".into(),
                exposed_modules: None,
            },
            options: CompileOptions {
                types_only: false,
                ir_version: "4.0.0".into(),
                extra: [("emitParseStage".into(), json!(false))].into(),
            },
            ..Default::default()
        };
        for mode in [InvocationMode::ProcessMep, InvocationMode::WasmMep] {
            let wire = serde_json::to_value(compile_wire_request(&request, mode)).unwrap();
            assert!(
                wire.get("sources").is_none(),
                "legacy provider received {wire}"
            );
            assert_eq!(
                wire["documents"][0]["uri"],
                request.sources.documents[0].uri
            );
            assert_eq!(wire["options"]["sourceRootUri"], "file:///project/src");
            assert_eq!(wire["options"]["emitParseStage"], false);
            // The newer SDK's compatibility decoder must preserve the same request.
            assert_eq!(
                serde_json::from_value::<CompileRequest>(wire).unwrap(),
                request
            );
        }
        let wire = serde_json::to_value(compile_wire_request(&request, InvocationMode::NativeMep))
            .unwrap();
        assert!(wire.get("documents").is_none());
        assert_eq!(wire["sources"]["root"], "file:///project/src");
        assert!(wire["options"].get("sourceRootUri").is_none());
    }
}
