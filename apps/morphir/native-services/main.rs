//! Versioned adapter to shared Morphir libraries. This is not a product CLI or checker.
use morphir_distribution::Sha256Digest;
use morphir_extension_sdk::protocol::{InitializeParams, PeerInfo};
use morphir_host::{HostConfig, JsonRpcConnection, Session};
use morphir_host_native::{
    CheckedConnection,
    process::{ProcessChannel, ProcessLaunch},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    error::Error,
    io::{self, Read},
    path::Path,
    time::Duration,
};
mod catalog;
mod diagnostics;
mod extism;
#[cfg(test)]
mod extism_tests;

type Result<T> = std::result::Result<T, Box<dyn Error + Send + Sync>>;
const REVISION: &str = "fc9f723a2cf0adae1299892c6cc4bee5ebcf4560";

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum NativeOperation {
    Describe,
    Compile,
    Generate,
}
#[derive(Deserialize)]
#[serde(untagged)]
enum Operation {
    Native(NativeOperation),
    Extism(extism::Operation),
    Catalog(catalog::Action),
}

fn text<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v[key]
        .as_str()
        .filter(|s| !s.is_empty() && !s.contains('\0'))
        .ok_or_else(|| format!("invalid {key}").into())
}
fn host() -> HostConfig {
    HostConfig::new(PeerInfo {
        kind: Default::default(),
        name: "morphir-moonbit-cli".into(),
        version: "0.1.0".into(),
    })
}
fn verified(v: &Value) -> Result<Vec<u8>> {
    let path = Path::new(text(v, "executable")?);
    if !path.is_absolute() || !std::fs::symlink_metadata(path)?.is_file() {
        return Err("native executable must be an absolute regular file".into());
    }
    let file = std::fs::File::open(path)?;
    if !file.metadata()?.is_file() {
        return Err("native executable must be a regular file".into());
    }
    let mut bytes = Vec::new();
    file.take(128 * 1024 * 1024 + 1).read_to_end(&mut bytes)?;
    if bytes.len() > 128 * 1024 * 1024
        || Sha256Digest::of_bytes(&bytes).to_string() != text(v, "sha256")?
    {
        return Err("extension.identity_mismatch".into());
    }
    Ok(bytes)
}
async fn invoke(v: &Value, operation: NativeOperation) -> Result<Value> {
    let pin = &v["pin"];
    let id = text(&pin["artifact"], "extensionId")?;
    let bytes = verified(&pin["artifact"])?;
    let work = Path::new(text(v, "workDirectory")?);
    let timeout = Duration::from_millis(
        v["timeout"]
            .as_u64()
            .filter(|n| *n > 0 && *n <= 594000)
            .ok_or("invalid timeout")?,
    );
    let args: Vec<String> = pin["artifact"]
        .get("args")
        .cloned()
        .map(serde_json::from_value)
        .transpose()?
        .unwrap_or_default();
    if args.len() > 64 || args.iter().any(|a| a.len() > 4096 || a.contains('\0')) {
        return Err("invalid native arguments".into());
    }
    // Shared staging requires discovered metadata. Describe from an immutable
    // private copy first, then hold initialization to the returned full identity.
    let staged = tempfile::tempdir()?;
    let program = staged.path().join("guest");
    std::fs::write(&program, &bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o500))?;
    }
    let launch = args.iter().fold(
        ProcessLaunch::new(id, &program, work).request_timeout(timeout),
        |launch, arg| launch.arg(arg),
    );
    let channel = ProcessChannel::spawn(launch).await?;
    let description =
        morphir_host::describe(diagnostics::Diagnostics::new(channel), &host(), id).await?;
    if description.claims.extension.version != text(&pin["artifact"], "version")? {
        return Err("extension.version_mismatch".into());
    }
    if matches!(operation, NativeOperation::Describe) {
        return Ok(
            json!({"extension":description.claims.extension,"result":description.claims,"shutdown":"not-applicable"}),
        );
    }
    let initialize: InitializeParams = serde_json::from_value(v["initialize"].clone())?;
    let config = HostConfig::with_versions(initialize.host, initialize.protocol_versions)
        .with_model_transport(
            initialize
                .model_transport
                .ok_or("model transport required")?,
        );
    let capabilities =
        serde_json::from_value(Value::Object(description.claims.capabilities.clone()))?;
    let launch = args.iter().fold(
        ProcessLaunch::from_verified_bytes_with_capabilities(
            description.claims.extension.clone(),
            capabilities,
            std::ffi::OsStr::new("guest"),
            &bytes,
            work,
        )
        .request_timeout(timeout),
        |launch, arg| launch.arg(arg),
    );
    let channel = ProcessChannel::spawn(launch).await?;
    let checks = morphir_host::ExpectedChecks::new(channel.expectation());
    let connection = CheckedConnection::new(JsonRpcConnection::new(
        diagnostics::Diagnostics::new(channel),
        checks,
    ));
    let mut session = Session::open(connection, &config).await?;
    let negotiated = json!({"protocolVersion":session.negotiated().protocol_version(),
        "modelTransport":session.negotiated().model_transport().map(|m| m.support())});
    let method = match operation {
        NativeOperation::Compile => "morphir.frontend.compileModel",
        NativeOperation::Generate => "morphir.backend.generateModel",
        NativeOperation::Describe => unreachable!(),
    };
    let result: std::result::Result<Value, _> = session.call(method, v["params"].clone()).await;
    let close = session.close().await;
    let result = result?;
    close?;
    Ok(
        json!({"extension":description.claims.extension,"negotiated":negotiated,"result":result,"shutdown":"acknowledged"}),
    )
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let mut bytes = Vec::new();
    let result = match io::stdin().take(4194305).read_to_end(&mut bytes) {
        Ok(_) if bytes.len() <= 4194304 => match serde_json::from_slice::<Value>(&bytes) {
            Ok(request) => {
                match serde_json::from_value::<Operation>(request["operation"].clone()) {
                    Ok(Operation::Native(operation)) => invoke(&request, operation).await,
                    Ok(Operation::Extism(operation)) => extism::invoke(&request, operation).await,
                    Ok(Operation::Catalog(operation)) => catalog::run(&request, operation).await,
                    Err(error) => Err(error.into()),
                }
            }
            Err(error) => Err(error.into()),
        },
        _ => Err("native request limit".into()),
    };
    let report = match result {
        Ok(result) => {
            json!({"profile":"morphir/native-services","contractVersion":"0.1.0","sourceRevision":REVISION,"state":"succeeded","result":result})
        }
        Err(error) => {
            let message = error.to_string();
            let code = message
                .split(':')
                .next()
                .filter(|code| code.starts_with("extension."))
                .unwrap_or("native.operation_failed");
            json!({"profile":"morphir/native-services","contractVersion":"0.1.0","sourceRevision":REVISION,"state":"failed","error":{"code":code,"message":message}})
        }
    };
    println!("{report}");
}
