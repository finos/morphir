//! Versioned adapter to shared Morphir libraries. This is not a product CLI or checker.
//! It serves the local repository and installation commands only. The extension
//! commands run on the CLI's worker host, so the adapter has no describe, compile,
//! generate or Extism operation.
use morphir_distribution::Sha256Digest;
use morphir_extension_sdk::protocol::PeerInfo;
use morphir_host::HostConfig;
use serde_json::{Value, json};
use std::{
    error::Error,
    io::{self, Read},
    path::Path,
};
mod catalog;
mod diagnostics;

type Result<T> = std::result::Result<T, Box<dyn Error + Send + Sync>>;
const REVISION: &str = "64eb9b3315322b396ae4b2cbbc41eab2808277f5";

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

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let mut bytes = Vec::new();
    let result = match io::stdin().take(4194305).read_to_end(&mut bytes) {
        Ok(_) if bytes.len() <= 4194304 => match serde_json::from_slice::<Value>(&bytes) {
            Ok(request) => {
                match serde_json::from_value::<catalog::Action>(request["operation"].clone()) {
                    Ok(action) => catalog::run(&request, action).await,
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
