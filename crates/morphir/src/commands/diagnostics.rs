//! Commands for locating local troubleshooting data.

use serde::Serialize;
use starbase::AppResult;
use std::path::PathBuf;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DiagnosticPaths {
    morphir_home: PathBuf,
    logs: PathBuf,
    cli_logs: PathBuf,
    desktop_logs: PathBuf,
}

impl DiagnosticPaths {
    fn resolve() -> miette::Result<Self> {
        let home = crate::home::MorphirHome::resolve()
            .map_err(|error| miette::miette!("Failed to resolve Morphir Home: {error}"))?;

        Ok(Self {
            morphir_home: home.root().to_path_buf(),
            logs: home.logs_dir(),
            cli_logs: home.cli_logs_dir(),
            desktop_logs: home.desktop_logs_dir(),
        })
    }
}

/// Print the stable locations for Morphir's local logs.
pub fn run_diagnostics_path(json: bool) -> AppResult<miette::Report> {
    let paths = DiagnosticPaths::resolve()?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&paths)
                .map_err(|error| miette::miette!("Failed to serialize log paths: {error}"))?
        );
    } else {
        println!("Morphir Home: {}", paths.morphir_home.display());
        println!("Logs: {}", paths.logs.display());
        println!("CLI logs: {}", paths.cli_logs.display());
        println!("Desktop logs: {}", paths.desktop_logs.display());
    }

    Ok(None)
}
