use serde::Serialize;
use starbase::AppResult;

/// Version information for the Morphir CLI
#[derive(Serialize)]
pub struct VersionInfo {
    pub name: &'static str,
    pub version: &'static str,
    pub build_date: &'static str,
    pub build_time: &'static str,
}

impl VersionInfo {
    pub fn new() -> Self {
        Self {
            name: env!("CARGO_PKG_NAME"),
            version: env!("CARGO_PKG_VERSION"),
            build_date: env!("BUILD_DATE"),
            build_time: env!("BUILD_TIME"),
        }
    }
}

impl Default for VersionInfo {
    fn default() -> Self {
        Self::new()
    }
}

pub fn run_version(json: bool) -> AppResult {
    let info = VersionInfo::new();

    if json {
        match serde_json::to_string_pretty(&info) {
            Ok(json_str) => println!("{}", json_str),
            Err(e) => {
                eprintln!("Failed to serialize version info: {}", e);
                return Ok(Some(1));
            }
        }
    } else {
        println!(
            "{} {} (built {} {})",
            info.name, info.version, info.build_date, info.build_time
        );
    }

    Ok(None)
}
