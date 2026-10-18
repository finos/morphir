//! A real SDK backend registered only by explicit qualification executables.
//! Byte recipes are inputs, never expected observations or manifest digests.
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir::commands::ui::provider::playground::NativePlaygroundProvider;
use morphir_extension_sdk::{
    Artifact, Backend, BackendCapability, Extension, ExtensionCapabilities, ExtensionInfo,
    GenerateRequest, GenerateResult, NativeExtension,
};
use morphir_host::Registry;
use morphir_host_native::NativeSource;

pub const TARGET: &str = "qualified-artifact-fixture";
pub const PRODUCER: &str = "morphir-artifact-qualification-fixture";

pub struct FixtureBackend {
    invocations: Arc<AtomicUsize>,
}
impl FixtureBackend {
    pub fn new(invocations: Arc<AtomicUsize>) -> Self {
        Self { invocations }
    }
}
impl Extension for FixtureBackend {
    fn info() -> ExtensionInfo {
        ExtensionInfo {
            id: PRODUCER.into(),
            name: "Artifact qualification fixture".into(),
            version: "0.1.0".into(),
            ..Default::default()
        }
    }
    fn capabilities() -> ExtensionCapabilities {
        ExtensionCapabilities {
            backend: Some(BackendCapability {
                targets: vec![TARGET.into()],
                ir_versions: vec!["4.0.0".into()],
                generate: true,
            }),
            ..Default::default()
        }
    }
}
impl Backend for FixtureBackend {
    fn target_languages() -> Vec<String> {
        vec![TARGET.into()]
    }
    fn generate(&self, request: GenerateRequest) -> morphir_extension_sdk::Result<GenerateResult> {
        self.invocations.fetch_add(1, Ordering::SeqCst);
        // This fixture emits fixed bytes for an explicitly selected IR4 input.
        // It does not claim to lower a production language or execute that IR.
        if request.target != TARGET
            || request
                .ir
                .get("formatVersion")
                .and_then(serde_json::Value::as_u64)
                != Some(4)
        {
            return Ok(GenerateResult {
                success: false,
                artifacts: vec![],
                diagnostics: vec![],
            });
        }
        let binary: Vec<u8> = (0..1_048_833)
            .map(|i| (i % 256) as u8 ^ ((i / 65536) % 256) as u8)
            .collect();
        Ok(GenerateResult {
            success: true,
            artifacts: vec![
                Artifact {
                    path: "indexed.bin".into(),
                    content: STANDARD.encode(binary),
                    binary: true,
                },
                Artifact {
                    path: "original.txt".into(),
                    content: "\u{feff}Original\r\nline two\r\n".into(),
                    binary: false,
                },
                Artifact {
                    path: "empty.bin".into(),
                    content: "".into(),
                    binary: true,
                },
            ],
            diagnostics: vec![],
        })
    }
}

pub fn provider() -> (NativePlaygroundProvider, Arc<AtomicUsize>) {
    let invocations = Arc::new(AtomicUsize::new(0));
    let mut registry = Registry::new();
    registry
        .register(Arc::new(NativeSource::new(
            NativeExtension::backend_only(FixtureBackend::new(invocations.clone()))
                .expect("well-formed fixture backend"),
        )))
        .expect("fixture registry");
    (
        NativePlaygroundProvider::from_registry(
            registry,
            std::env::current_dir().expect("fixture working directory"),
        ),
        invocations,
    )
}
