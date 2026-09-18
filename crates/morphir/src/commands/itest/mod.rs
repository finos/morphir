//! Notebook scenarios executed through real Morphir CLI child processes.
mod model;
mod runner;
#[cfg(windows)]
mod windows_job;
#[cfg(test)]
use runner::execute;
use runner::run;
#[cfg(test)]
mod tests;

use crate::notebook::Notebook;
use anyhow::{Context, Result, bail, ensure};
use model::{Metadata, Step};
use std::{
    fs,
    path::{Path, PathBuf},
};

#[derive(Debug)]
struct Scenario {
    pub id: String,
    pub notebook: Notebook,
    pub metadata: Metadata,
    pub steps: Vec<Step>,
}

fn included(entry: &walkdir::DirEntry) -> bool {
    !matches!(
        entry.file_name().to_str(),
        Some(".git" | ".morphir" | "node_modules" | "target" | "elm-stuff" | "out" | "dist")
    )
}

fn discover(root: &Path, filter: Option<&str>) -> Result<Vec<Scenario>> {
    if let Some(filter) = filter {
        model::relative_path(filter)?;
    }
    let mut scenarios = Vec::new();
    for entry in walkdir::WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(included)
    {
        let entry = entry?;
        if entry.file_name() != "scenario.ipynb" {
            continue;
        }
        ensure!(
            !entry.file_type().is_symlink(),
            "scenario cannot be a symlink: {}",
            entry.path().display()
        );
        if !entry.file_type().is_file() {
            continue;
        }
        let directory = entry
            .path()
            .parent()
            .context("scenario has no directory")?
            .to_owned();
        let relative = directory.strip_prefix(root)?;
        let id = if relative.as_os_str().is_empty() {
            "root".into()
        } else {
            relative.to_string_lossy().replace('\\', "/")
        };
        let notebook = Notebook::parse(&fs::read_to_string(entry.path())?)
            .with_context(|| format!("scenario {id}: {}", entry.path().display()))?;
        let (metadata, steps) = model::parse(&notebook)
            .with_context(|| format!("scenario {id}: {}", entry.path().display()))?;
        scenarios.push(Scenario {
            id,
            notebook,
            metadata,
            steps,
        });
    }
    scenarios.sort_by(|a, b| a.id.cmp(&b.id));
    ensure!(
        !scenarios.is_empty(),
        "no scenarios found under {}",
        root.display()
    );
    if let Some(filter) = filter {
        scenarios.retain(|s| s.id == filter || s.id.starts_with(&format!("{filter}/")));
        ensure!(!scenarios.is_empty(), "no scenarios match path {filter:?}");
    }
    Ok(scenarios)
}

fn select_tags<'a>(scenarios: &'a [Scenario], tags: &[String]) -> Result<Vec<&'a Scenario>> {
    let selected: Vec<_> = scenarios
        .iter()
        .filter(|s| tags.iter().all(|tag| s.metadata.tags.contains(tag)))
        .collect();
    if selected.is_empty() {
        bail!("no scenarios match tags {tags:?}");
    }
    Ok(selected)
}

#[derive(Clone, Debug, clap::Args)]
pub struct ItestArgs {
    /// Directory to search recursively for scenario.ipynb files
    #[arg(default_value = "examples")]
    pub root: PathBuf,
    /// Select one example path or category relative to the search root
    #[arg(long)]
    pub filter: Option<String>,
    /// Require this exact tag; repeat to require all supplied tags
    #[arg(long = "tag")]
    pub tags: Vec<String>,
    /// List matching scenarios and their purpose without executing commands
    #[arg(long)]
    pub list: bool,
    /// Retain isolated projects, homes and per-step logs for diagnosis
    #[arg(long)]
    pub keep_temp: bool,
}

pub fn run_itest(args: ItestArgs) -> starbase::AppResult<miette::Report> {
    run_suite(args).map_err(|error| miette::miette!("{error:#}"))?;
    Ok(None)
}

fn run_suite(args: ItestArgs) -> Result<()> {
    let scenarios = discover(&args.root, None)?;
    let mut selected = select_tags(&scenarios, &args.tags)?;
    if let Some(filter) = &args.filter {
        model::relative_path(filter)?;
        selected.retain(|s| s.id == *filter || s.id.starts_with(&format!("{filter}/")));
        ensure!(
            !selected.is_empty(),
            "no scenarios match path {filter:?} and tags {:?}",
            args.tags
        );
    }
    if !args.list {
        // The CLI has no portable system-config relocation switch. Refuse a
        // contaminated host rather than silently changing the tested behavior.
        ensure!(
            morphir_devkit::config::discover_system_config()?.is_none(),
            "itest requires a host without system Morphir configuration"
        );
        #[cfg(windows)]
        if let Some(config) = dirs::config_dir() {
            for name in ["morphir.toml", "morphir.yaml"] {
                ensure!(
                    !config.join("morphir").join(name).try_exists()?,
                    "itest cannot isolate Windows Known Folder Morphir configuration; use a clean test account"
                );
            }
        }
    }
    let binary = std::env::current_exe().context("locate the running Morphir CLI")?;
    let mut failed = 0;
    for scenario in &selected {
        if args.list {
            println!(
                "{}: {} [{}]\n  {}",
                scenario.id,
                scenario.metadata.title,
                scenario.metadata.tags.join(", "),
                scenario.metadata.description
            );
        } else {
            match run(scenario, &binary, args.keep_temp) {
                Ok(()) => println!(
                    "PASS {}: {} ({} steps)",
                    scenario.id,
                    scenario.metadata.title,
                    scenario.steps.len()
                ),
                Err(error) => {
                    failed += 1;
                    eprintln!("FAIL {}\n{error:#}", scenario.id);
                }
            }
        }
    }
    if !args.list {
        println!(
            "{} passed; {failed} failed; {} not selected",
            selected.len() - failed,
            scenarios.len() - selected.len()
        );
    }
    ensure!(failed == 0, "{failed} integration scenario(s) failed");
    Ok(())
}
