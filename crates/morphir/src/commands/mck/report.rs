//! Filesystem and CLI boundaries for the shared report reader, checker and renderer.
use std::io::Write;
use std::path::{Path, PathBuf};

use clap::{Args, ValueEnum};
use morphir_mck::ir::{Run, run::RunFailure};
use morphir_mck::kit::{embedded::embedded_source, load_kit};
use morphir_mck::provenance::{Driver, KitProvenance};
use morphir_mck::report::check::{AllowedFailures, check};
use morphir_mck::report::draft::{DraftReport, NegotiatedCapabilities, ReportError};
use serde_json::json;
use starbase::AppResult;

use super::{Outcome, finish, load_directory};

#[derive(Args, Clone, Debug)]
pub struct CheckArgs {
    /// Consolidated JSON report to check
    pub report: PathBuf,
    /// Binding-owned JSON file listing allowed failing case IDs
    pub allowed_failing: PathBuf,
    /// Independent kit, defaulting to the embedded kit
    #[arg(long)]
    pub kit: Option<PathBuf>,
    #[arg(long)]
    pub repo_root: Option<PathBuf>,
    /// Require this exact case filter; omission requires a full-kit report
    #[arg(long)]
    pub filter: Option<String>,
}

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum RenderFormat {
    Html,
}

#[derive(Args, Clone, Debug)]
pub struct RenderArgs {
    /// Consolidated JSON report to display
    pub report: PathBuf,
    /// Output representation; HTML opens offline without a server
    #[arg(long, value_enum, default_value = "html")]
    pub format: RenderFormat,
    /// Destination for the standalone report; cannot overwrite the JSON input
    #[arg(short, long)]
    pub output: PathBuf,
}

fn read(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))
}

pub fn run_check(args: CheckArgs) -> AppResult<miette::Report> {
    if let Some(pattern) = &args.filter
        && let Err(error) = regex::Regex::new(pattern)
    {
        return finish(Outcome::Usage(format!("invalid --filter regex: {error}")));
    }
    let result = (|| {
        let text = read(&args.report)?;
        let allowed = AllowedFailures::from_json(&read(&args.allowed_failing)?)?;
        let kit = match &args.kit {
            None => load_kit(embedded_source()).map_err(|e| e.to_string())?,
            Some(dir) => load_directory(dir, args.repo_root.as_deref())?
                .kit()
                .clone(),
        };
        let value: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        let (checked, summary) = if value["suite"] == "metadata" {
            let report = morphir_mck::metadata::report::MetadataReport::from_value(value)?;
            let checked = morphir_mck::metadata::report::check(
                &report,
                &kit,
                &allowed,
                args.filter.as_deref(),
            )?;
            (checked, report.summary_line())
        } else {
            let report = DraftReport::from_value(value).map_err(|e| e.to_string())?;
            let checked = check(&report, &kit, &allowed, args.filter.as_deref())?;
            (checked, report.summary_line())
        };
        println!("{}: {}", args.report.display(), summary);
        println!(
            "Verified inventory: {} cases, {} records ({})",
            checked.selected_cases,
            checked.records,
            if checked.filtered {
                "filtered selection; unselected baseline entries not checked"
            } else {
                "full kit"
            }
        );
        if checked.allowed_failures > 0 {
            println!(
                "Development baseline with {} allowed failing cases; not a compatibility certificate",
                checked.allowed_failures
            );
        }
        Ok::<_, String>(())
    })();
    finish(match result {
        Ok(()) => Outcome::Passed,
        Err(error) => Outcome::Error(error),
    })
}

pub fn run_render(args: RenderArgs) -> AppResult<miette::Report> {
    if args.output.exists() {
        match same_file::is_same_file(&args.report, &args.output) {
            Ok(true) => {
                return finish(Outcome::Usage(
                    "HTML output must not overwrite its JSON input".into(),
                ));
            }
            Ok(false) => {}
            Err(error) => {
                return finish(Outcome::Error(format!(
                    "cannot compare input and output: {error}"
                )));
            }
        }
    }
    let result = (|| {
        let text = read(&args.report)?;
        let value: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        let html = if value["suite"] == "metadata" {
            let report = morphir_mck::metadata::report::MetadataReport::from_value(value)?;
            match args.format {
                RenderFormat::Html => morphir_mck::metadata::report::render(&report),
            }
        } else {
            let report = DraftReport::from_value(value).map_err(|e| e.to_string())?;
            match args.format {
                RenderFormat::Html => morphir_mck::report::html::render(&report),
            }
        };
        write_atomic(&args.output, html.as_bytes())
            .map_err(|e| format!("cannot write {}: {e}", args.output.display()))?;
        println!("Wrote {}", args.output.display());
        Ok::<_, String>(())
    })();
    finish(match result {
        Ok(()) => Outcome::Passed,
        Err(error) => Outcome::Error(error),
    })
}

pub(super) fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent)?;
    let mut staged = tempfile::NamedTempFile::new_in(parent)?;
    staged.write_all(bytes)?;
    staged.as_file().sync_all()?;
    staged.persist(path).map_err(|error| error.error)?;
    Ok(())
}

pub(super) fn assemble(
    run: &Run,
    kit: KitProvenance,
    command: Vec<String>,
    filter: Option<&str>,
    strict: bool,
    spawn_error: Option<&str>,
    shutdown_error: Option<&str>,
) -> Result<DraftReport, ReportError> {
    let negotiation = match &run.capabilities {
        Some(caps) => {
            json!({"status":"succeeded","capabilities":NegotiatedCapabilities::from_capabilities(caps)?})
        }
        None => {
            let message = match &run.failure {
                Some(RunFailure::Capabilities(message)) => message.as_str(),
                _ => return Err(ReportError("missing capability failure context".into())),
            };
            json!({"status":"failed","message":message})
        }
    };
    let mut errors = Vec::new();
    match (spawn_error, &run.failure) {
        (Some(message), _) => errors.push(json!({"phase":"spawn","message":message})),
        (None, Some(RunFailure::Capabilities(message))) => {
            errors.push(json!({"phase":"capabilities","message":message}))
        }
        (None, Some(RunFailure::Exchange(message))) => {
            errors.push(json!({"phase":"exchange","message":message}))
        }
        (None, None) => {}
    }
    if let Some(message) = shutdown_error {
        errors.push(json!({"phase":"shutdown","message":message}));
    }
    let session = if errors.is_empty() {
        json!({"status":"finished"})
    } else {
        json!({"status":"failed","errors":errors})
    };
    let selection = match filter {
        Some(pattern) => json!({"kind":"filter","syntax":"rust-regex","pattern":pattern}),
        None => json!({"kind":"all"}),
    };
    let mut kit = serde_json::to_value(kit).map_err(|e| ReportError(e.to_string()))?;
    kit["version"] = json!(run.report.kit_version);
    DraftReport::from_value(json!({
        "contractVersion": morphir_mck::report::draft::CONTRACT_VERSION, "suite":"ir",
        "startedAt":run.report.started_at, "driver":Driver::current(), "kit":kit,
        "adapter":{"command":command,"negotiation":negotiation},
        "selection":selection,"execution":{"strict":strict,"session":session},"records":run.report.records
    }))
}
