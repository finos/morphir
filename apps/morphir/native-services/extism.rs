//! Explicit local WASM invocation. Distribution, MEP and engine rules stay shared.
use super::{Result, text};
use morphir_distribution::{ArtifactRuntime, ReleaseBundleDescriptor, Sha256Digest};
use morphir_extension_sdk::{
    CompileRequest, ExtensionCapabilities, GenerateRequest, protocol::PeerInfo,
};
use morphir_host::{ExpectedChecks, ExpectedExtension, HostConfig, JsonRpcConnection, Session};
use morphir_host_native::{
    CheckedConnection,
    extism::{ExtensionContainer, ExtismChannel, MorphirHostFunctions, RestrictedExtismPolicy},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{io::Read, path::Path, time::Duration};

#[derive(Deserialize, Clone, Copy)]
pub(super) enum Operation {
    #[serde(rename = "extism.describe")]
    Describe,
    #[serde(rename = "extism.compile")]
    Compile,
    #[serde(rename = "extism.generate")]
    Generate,
}

fn bytes(path: &Path, expected: &str, limit: u64) -> Result<Vec<u8>> {
    if !path.is_absolute() || !std::fs::symlink_metadata(path)?.is_file() {
        return Err("extension.invalid_pin: regular absolute file required".into());
    }
    // The helper has already materialized an immutable no-follow snapshot.
    // Rehash those bytes at the engine boundary; never reopen the original bundle.
    let mut value = Vec::new();
    std::fs::File::open(path)?
        .take(limit + 1)
        .read_to_end(&mut value)?;
    if value.len() as u64 > limit {
        return Err("extension.resource_limit: artifact bytes".into());
    }
    if Sha256Digest::of_bytes(&value).to_string() != expected {
        return Err("extension.integrity_mismatch: artifact digest".into());
    }
    Ok(value)
}

fn config() -> HostConfig {
    HostConfig::with_versions(
        PeerInfo {
            kind: Default::default(),
            name: "morphir-moonbit-cli".into(),
            version: "0.1.0".into(),
        },
        vec!["0.1".into()],
    )
}

async fn container(id: &str, wasm: Vec<u8>, work: &Path) -> Result<ExtensionContainer> {
    let policy = RestrictedExtismPolicy::new(
        256 * 1024 * 1024,
        1_000_000_000,
        Duration::from_secs(30),
        4 * 1024 * 1024,
        16 * 1024 * 1024,
    )?;
    Ok(ExtensionContainer::from_bytes_with_execution_policy_async(
        id.to_owned(),
        wasm,
        MorphirHostFunctions::for_restricted_generation(work.to_owned()),
        policy,
    )
    .await?)
}

fn ir_major(version: &str) -> Option<u8> {
    match version {
        "3" | "3.0.0" => Some(3),
        "4" | "4.0.0" => Some(4),
        _ => None,
    }
}

/// Legacy method scope is checked here as well as identity negotiation. The
/// shared session currently scopes workspace methods but not these operations.
fn validate_operation(
    capabilities: &ExtensionCapabilities,
    params: &Value,
    operation: Operation,
) -> Result<()> {
    match operation {
        Operation::Describe => Ok(()),
        Operation::Compile => {
            let request: CompileRequest = serde_json::from_value(params.clone())?;
            let frontend = capabilities
                .frontend
                .as_ref()
                .ok_or("extension.capability_mismatch: frontend missing")?;
            let version =
                ir_major(&request.options.ir_version).ok_or("extension.ir_version_mismatch")?;
            if !frontend.compile
                || !frontend
                    .languages
                    .iter()
                    .any(|language| language.id == request.language_id)
                || !frontend
                    .ir_versions
                    .iter()
                    .any(|offered| ir_major(offered) == Some(version))
                || request.sources.documents.is_empty()
                || request
                    .sources
                    .documents
                    .iter()
                    .any(|document| document.language_id != request.language_id)
                || (request.sources.documents.len() != 1 && !frontend.multi_document)
            {
                return Err(
                    "extension.capability_mismatch: compile language, IR or source count".into(),
                );
            }
            Ok(())
        }
        Operation::Generate => {
            let request: GenerateRequest = serde_json::from_value(params.clone())?;
            let backend = capabilities
                .backend
                .as_ref()
                .ok_or("extension.capability_mismatch: backend missing")?;
            let version = match request.ir.get("formatVersion") {
                Some(Value::String(value)) => ir_major(value),
                Some(Value::Number(value)) => ir_major(&value.to_string()),
                _ => None,
            }
            .ok_or("extension.ir_version_mismatch")?;
            if !backend.generate
                || !backend.targets.contains(&request.target)
                || !backend
                    .ir_versions
                    .iter()
                    .any(|offered| ir_major(offered) == Some(version))
            {
                return Err("extension.capability_mismatch: generate target or IR".into());
            }
            Ok(())
        }
    }
}

pub(super) async fn invoke(request: &Value, operation: Operation) -> Result<Value> {
    let artifact = &request["pin"]["artifact"];
    let id = text(artifact, "extensionId")?;
    let version = text(artifact, "version")?;
    let directory = Path::new(text(artifact, "directory")?);
    let descriptor_bytes = bytes(
        &directory.join("release.json"),
        text(artifact, "descriptorSha256")?,
        1024 * 1024,
    )?;
    let descriptor = ReleaseBundleDescriptor::parse_json(&descriptor_bytes)
        .map_err(|e| format!("extension.invalid_pin: {e}"))?;
    if descriptor.schema_version().to_string() != "2.0.0-draft.2"
        || descriptor.extension_id().as_str() != id
        || descriptor.version().to_string() != version
    {
        return Err("extension.identity_mismatch: descriptor".into());
    }
    let selected: Vec<_> = descriptor
        .artifacts()
        .iter()
        .filter(|a| {
            a.runtime() == ArtifactRuntime::Wasm
                && a.sha256().to_string() == text(artifact, "wasmSha256").unwrap_or("")
        })
        .collect();
    if selected.len() != 1 {
        return Err("extension.integrity_mismatch: one matching WASM required".into());
    }
    let selected = selected[0];
    let wasm = bytes(
        &directory.join(selected.filename().as_str()),
        text(artifact, "wasmSha256")?,
        128 * 1024 * 1024,
    )?;
    let work = Path::new(text(request, "workDirectory")?);
    let probe = container(id, wasm.clone(), work).await?;
    if probe.info().id != id || probe.info().version != version {
        return Err("extension.identity_mismatch: exported metadata".into());
    }
    let expected = ExpectedExtension::discovered(probe.info().clone());
    let description = morphir_host::describe(ExtismChannel::new(probe, expected), &config(), id)
        .await
        .map_err(|e| format!("extension.protocol_mismatch: {e}"))?;
    // A descriptor is a claim. Execute only after its exact live scope is checked.
    if serde_json::to_value(&description.claims)? != serde_json::to_value(selected.claims())? {
        return Err("extension.capability_mismatch: descriptor and live claims differ".into());
    }
    if description.claims.extension.version != version {
        return Err("extension.identity_mismatch: description".into());
    }
    if matches!(operation, Operation::Describe) {
        return Ok(
            json!({"extension":description.claims.extension,"result":description.claims,"shutdown":"not-applicable","containerDropped":true,"claimCheck":"runtime-verified","provenance":"asserted"}),
        );
    }
    let capabilities: ExtensionCapabilities =
        serde_json::from_value(Value::Object(description.claims.capabilities.clone()))?;
    validate_operation(&capabilities, &request["params"], operation)?;
    let expected = ExpectedExtension::discovered_with_capabilities(
        description.claims.extension.clone(),
        capabilities,
    );
    let active = container(id, wasm, work).await?;
    let channel = ExtismChannel::new(active, expected.clone());
    let connection = CheckedConnection::new(JsonRpcConnection::new(
        channel,
        ExpectedChecks::new(expected),
    ));
    let mut session = Session::open(connection, &config())
        .await
        .map_err(|e| format!("extension.capability_mismatch: {e}"))?;
    let protocol = session.negotiated().protocol_version().to_owned();
    let method = match operation {
        Operation::Compile => "morphir.frontend.compile",
        Operation::Generate => "morphir.backend.generate",
        Operation::Describe => unreachable!(),
    };
    let result: std::result::Result<Value, _> =
        session.call(method, request["params"].clone()).await;
    let close = session.close().await;
    // Session::close consumes the session, releasing the channel/container.
    let result = result.map_err(|e| format!("extension.invalid_result: {e}"))?;
    close.map_err(|e| format!("extension.incomplete_session: {e}"))?;
    Ok(
        json!({"extension":description.claims.extension,"negotiated":{"protocolVersion":protocol},"result":result,"shutdown":"acknowledged","containerDropped":true,"claimCheck":"runtime-verified","provenance":"asserted"}),
    )
}
