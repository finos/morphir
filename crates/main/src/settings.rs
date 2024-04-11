use anyhow::Error as AnyError;
use config::{Config, ConfigError, File};
use dirs;
use std::collections::HashMap;
use std::env;
use serde_derive::Deserialize;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum SettingsError {
    #[error("Configuration error: {0}")]
    ConfigError(#[from] ConfigError),
    #[error("Deserialization error: {0}")]
    DeserializeError(#[from] AnyError),
    #[error("IO error: {0}")]
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
    pub fn new()  -> Result<Self, SettingsError> {
        let run_mode = env::var("RUN_MODE").unwrap_or_else(|_| "development".into());      
        println!("run_mode: {}", run_mode);  
        let mut bldr = Config::builder()        
            .add_source(File::from_str(include_str!("../config/morphir.default.toml"), config::FileFormat::Toml))
            .add_source(File::with_name(".morphir/config/morphir").required(false))
            .add_source(File::with_name(&format!(".morphir/config/morphir-{}", run_mode)).required(false));

        if let Some(home_dir) = dirs::home_dir() {
            bldr = bldr.add_source(File::with_name(home_dir.join(".morphir/config/morphir").to_str().unwrap()).required(false));
        }

        let s = bldr.build()?;            
        s.try_deserialize().map_err(|e| e.into())
    }
}
