use config::{Config, ConfigError, File};
use dirs;
use serde_derive::Deserialize;
use starbase::diagnostics::Diagnostic;
use std::collections::HashMap;
use std::env;
use thiserror::Error;

#[derive(Error, Debug, Diagnostic)]
pub enum SettingsError {
    #[error(transparent)]
    #[diagnostic(code(app::config_error))]
    ConfigError(#[from] ConfigError),
    #[error("Deserialization error")]
    DeserializeError,
    #[error(transparent)]
    #[diagnostic(code(app::io_error))]
    IOError(#[from] std::io::Error),
}

#[derive(Debug, Deserialize)]
#[allow(unused)]
struct KnowledgeBase {
    default: Option<String>,
    sources: Option<HashMap<String, KnowledgeBaseSource>>,
}

#[derive(Debug, Deserialize)]
#[allow(unused)]
#[serde(untagged)]
enum KnowledgeBaseSource {
    PathSource(String),
}

#[derive(Debug, Deserialize)]
#[allow(unused)]
pub struct Settings {
    kb: Option<KnowledgeBase>,
}

impl Settings {
    pub fn new() -> Result<Self, SettingsError> {
        let run_mode = env::var("RUN_MODE").unwrap_or_else(|_| "development".into());
        println!("run_mode: {}", run_mode);
        let mut bldr = Config::builder()
            .add_source(File::from_str(
                include_str!("../config/morphir.default.toml"),
                config::FileFormat::Toml,
            ))
            .add_source(File::with_name(".morphir/config/morphir").required(false))
            .add_source(
                File::with_name(&format!(".morphir/config/morphir-{}", run_mode)).required(false),
            );

        if let Some(home_dir) = dirs::home_dir() {
            bldr = bldr.add_source(
                File::with_name(home_dir.join(".morphir/config/morphir").to_str().unwrap())
                    .required(false),
            );
        }

        let s = bldr.build()?;
        s.try_deserialize().map_err(|e| e.into())
    }
}
