//! `morphir itest`: example scenarios run through real Morphir CLI child processes, on a
//! `morphir_bdd::Suite`.
//!
//! Discovery finds one scenario document per example directory under the search root: a
//! `scenarios.md` file (read by [`read_scenarios_md`]), or a `*.feature` or `*.feature.md` file
//! (read by `morphir_gherkin`). A scenario's id is `<directory id>#<section>`, where the section is
//! its `@section:` tag or else the id of its name. The suite then runs the selected scenarios one
//! at a time with the [`steps`] building blocks, and prints one `PASS` or `FAIL` line for each
//! scenario and a summary line.
//!
//! Scenarios run, and their lines print as they finish, in document order: documents in path
//! order, and each document's scenarios in the order they are written. (Before the suite, itest
//! ran them sorted by id.) `--list` still prints them sorted by id.
mod golden;
mod markdown;
mod model;
mod reader;
mod runner;
pub mod steps;
#[cfg(windows)]
mod windows_job;
mod workspace;

pub use reader::read_scenarios_md;
#[cfg(test)]
use runner::execute;
#[cfg(test)]
mod markdown_tests;
#[cfg(test)]
mod tests;

use anyhow::{Context, Result, anyhow, bail, ensure};
use morphir_bdd::{
    Console, Reader, ScenarioOutcome, Suite, standard_extensions, steps::cli::CustomCliRunner,
    tags::TagExpr,
};
use morphir_gherkin::{Description, Scenario as GherkinScenario};
use std::{
    collections::HashSet,
    ffi::OsStr,
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};
use steps::{ItestFence, ItestRoot, ItestRunner, KeepTemp, MaterializeExample};
use tempfile::TempDir;

#[cfg(test)]
use markdown::ParsedSection;
#[cfg(test)]
use model::{Metadata, Step};
#[cfg(test)]
use std::fs;

/// The Markdown scenario document that [`read_scenarios_md`] reads.
const SCENARIOS_MD: &str = "scenarios.md";

/// The notebook scenario document. `morphir itest` no longer runs it, and refuses a directory
/// that holds one.
const NOTEBOOK: &str = "scenario.ipynb";

/// The tag expression of a run with no `--tag`: it matches every scenario, so a run that selects
/// nothing is an empty run rather than a suite error.
const EVERY_SCENARIO: &str = "@nothing or not @nothing";

/// One `scenarios.md` section with its parsed model, loaded by the legacy [`discover`] that the
/// unit tests still use.
#[cfg(test)]
#[derive(Debug)]
struct Scenario {
    pub id: String,
    pub directory: PathBuf,
    pub section: ParsedSection,
    pub metadata: Metadata,
    pub steps: Vec<Step>,
}

/// The directory names discovery never enters: build outputs, dependencies and VCS data. The
/// suite's own file errors under them are not reported either.
const EXCLUDED_DIRS: [&str; 7] = [
    ".git",
    ".morphir",
    "node_modules",
    "target",
    "elm-stuff",
    "out",
    "dist",
];

fn included(entry: &walkdir::DirEntry) -> bool {
    entry
        .file_name()
        .to_str()
        .is_none_or(|name| !EXCLUDED_DIRS.contains(&name))
}

/// How a morphir-bdd discovery error ends its path: `the directory {dir} cannot be read: {e}`,
/// `an entry in {dir} cannot be read: {e}` and `{path} cannot be read: {e}`.
const CANNOT_BE_READ: &str = " cannot be read: ";

/// Whether the suite's error `message` names a path under one of the [`EXCLUDED_DIRS`] below
/// `root` (or one of those directories itself). It reads the path from each form the suite writes:
/// a file error, which starts with the file's path and puts a `:` after it, and the three
/// discovery errors, which may start with `the directory ` or `an entry in ` and end the path at
/// ` cannot be read: `.
fn under_excluded_dir(root: &Path, message: &str) -> bool {
    let text = message
        .strip_prefix("the directory ")
        .or_else(|| message.strip_prefix("an entry in "))
        .unwrap_or(message);
    let path = text.find(CANNOT_BE_READ).map_or(text, |end| &text[..end]);
    let Some(rest) = path.strip_prefix(&root.display().to_string()) else {
        return false;
    };
    rest.split(['/', '\\'])
        .take_while(|component| !component.contains(':'))
        .any(|component| EXCLUDED_DIRS.contains(&component))
}

/// The legacy loader: every section of every `scenarios.md` under `root`, sorted by id. The run
/// path no longer uses it; the unit tests of the scenario model still do.
#[cfg(test)]
fn discover(root: &Path, filter: Option<&str>) -> Result<Vec<Scenario>> {
    if let Some(filter) = filter {
        validate_filter(filter)?;
    }
    let mut scenarios = Vec::new();
    for entry in walkdir::WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(included)
    {
        let entry = entry?;
        if entry.file_name() != SCENARIOS_MD {
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
        let id = directory_id(root, &directory)?;
        let text = fs::read_to_string(entry.path())?;
        let sections = markdown::parse_sections(&text)
            .with_context(|| format!("scenario document {}", entry.path().display()))?
            .sections;
        for section in sections {
            let id = format!("{id}#{}", section.id);
            let (metadata, steps) = model::parse(&section)
                .with_context(|| format!("scenario {id}: {}", entry.path().display()))?;
            scenarios.push(Scenario {
                id,
                directory: directory.clone(),
                section,
                metadata,
                steps,
            });
        }
    }
    scenarios.sort_by(|a, b| a.id.cmp(&b.id));
    ensure!(
        !scenarios.is_empty(),
        "no scenarios found under {}",
        root.display()
    );
    if let Some(filter) = filter {
        scenarios.retain(|s| matches_filter(&s.id, filter));
        ensure!(!scenarios.is_empty(), "no scenarios match path {filter:?}");
    }
    Ok(scenarios)
}

/// The legacy tag selection over [`discover`]'s scenarios, kept for the unit tests.
#[cfg(test)]
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

/// A scenario directory's id: its path relative to the itest `root`, with `/` separators, or
/// `.` for the root itself.
fn directory_id(root: &Path, directory: &Path) -> Result<String> {
    let relative = directory.strip_prefix(root)?;
    if relative.as_os_str().is_empty() {
        return Ok(".".into());
    }
    let id = relative
        .components()
        .map(|component| {
            component
                .as_os_str()
                .to_str()
                .context("scenario directory name must be UTF-8")
        })
        .collect::<Result<Vec<_>>>()?
        .join("/");
    model::relative_path(&id)?;
    ensure!(
        !id.contains('#'),
        "scenario directory cannot contain reserved '#' separator"
    );
    Ok(id)
}

/// The directory that holds the scenario document at `document`: its parent, or `.` for a bare
/// file name.
fn document_dir(document: &Path) -> PathBuf {
    match document.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.to_owned(),
        _ => PathBuf::from("."),
    }
}

/// The itest id of the scenario named `name` in the document at `document` under `root`:
/// `<directory id>#<section>`. The section is `section` (the scenario's `@section:` tag) when
/// given, or else the section id of `name`. `root` and `document` must use the same path form.
fn scenario_id_of(
    root: &Path,
    document: &Path,
    name: &str,
    section: Option<&str>,
) -> Result<String> {
    let context = || format!("scenario document {}", document.display());
    let directory = directory_id(root, &document_dir(document)).with_context(context)?;
    let section = markdown::section_id(name, section.map(str::to_owned)).with_context(context)?;
    Ok(format!("{directory}#{section}"))
}

fn validate_filter(filter: &str) -> Result<()> {
    let (directory, section) = filter
        .split_once('#')
        .map_or((filter, None), |(directory, section)| {
            (directory, Some(section))
        });
    if directory != "." {
        model::relative_path(directory)?;
    }
    if let Some(section) = section {
        markdown::validate_id(section)?;
    }
    Ok(())
}

fn matches_filter(id: &str, filter: &str) -> bool {
    id == filter
        || (!filter.contains('#')
            && (id.starts_with(&format!("{filter}/")) || id.starts_with(&format!("{filter}#"))))
}

/// Whether `filter` can select a scenario of the directory whose id is `directory`. A document
/// that cannot be read has no scenario ids, so its directory stands in for them.
fn directory_matches_filter(directory: &str, filter: &str) -> bool {
    match filter.split_once('#') {
        Some((path, _)) => directory == path,
        None => directory == filter || directory.starts_with(&format!("{filter}/")),
    }
}

/// Whether a file named `name` is a scenario document.
fn is_scenario_document(name: &str) -> bool {
    name == SCENARIOS_MD
        || name == NOTEBOOK
        || name.ends_with(".feature")
        || name.ends_with(".feature.md")
}

/// Whether `tag` is one the `scenarios.md` reader adds for the runner (`section:` and `steps:`),
/// not one the author wrote. `--list` leaves these out.
fn is_runner_tag(tag: &str) -> bool {
    tag.starts_with("section:") || tag.starts_with("steps:")
}

/// One scenario of a discovered document: what `--list` prints, and what `--tag` and `--filter`
/// select on.
#[derive(Debug)]
struct Listed {
    /// `<directory id>#<section>`.
    id: String,
    /// The scenario's name.
    title: String,
    /// The feature's, rule's and scenario's tags, without `@`, in that order.
    tags: Vec<String>,
    /// The scenario's own description, else its rule's, else its feature's, on one line.
    description: String,
    /// How many scenarios the suite finds for it: 1, or one for each row of an outline's examples.
    runs: usize,
    /// How many of those the suite runs when it is selected: `runs`, less the ones a `@wip` tag
    /// skips.
    will_run: usize,
}

impl Listed {
    fn selected(&self, tags: &[String], filter: Option<&str>) -> bool {
        tags.iter().all(|tag| self.tags.contains(tag))
            && filter.is_none_or(|filter| matches_filter(&self.id, filter))
    }

    fn list_entry(&self) -> String {
        let tags: Vec<&str> = self
            .tags
            .iter()
            .map(String::as_str)
            .filter(|tag| !is_runner_tag(tag))
            .collect();
        format!(
            "{}: {} [{}]\n  {}",
            self.id,
            self.title,
            tags.join(", "),
            self.description
        )
    }
}

/// A scenario document found under the itest root.
#[derive(Debug)]
struct Found {
    /// The document's path: the search root joined with its relative path.
    path: PathBuf,
    /// The id of the document's directory.
    directory: String,
    /// The document's scenarios, or why it cannot run.
    scenarios: std::result::Result<Vec<Listed>, String>,
}

impl Found {
    /// How many scenarios this document adds to the discovered count. A document that cannot
    /// be read counts as one.
    fn discovered(&self) -> usize {
        self.scenarios
            .as_ref()
            .map_or(1, |scenarios| scenarios.iter().map(|s| s.runs).sum())
    }

    /// Why this document cannot run, when `filter` selects its directory.
    fn refusal(&self, filter: Option<&str>) -> Option<&str> {
        match &self.scenarios {
            Err(reason)
                if filter
                    .is_none_or(|filter| directory_matches_filter(&self.directory, filter)) =>
            {
                Some(reason)
            }
            _ => None,
        }
    }
}

/// Every scenario document under `root`, sorted by directory id. A directory holds at most one
/// document. A document that cannot be read, and a [`NOTEBOOK`], is kept with the reason, so the
/// run can report it; a symlinked document, a directory id that is not portable, and a root
/// without documents are errors.
fn find_documents(root: &Path) -> Result<Vec<Found>> {
    let mut found = Vec::new();
    let mut directories = HashSet::new();
    for entry in walkdir::WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(included)
    {
        let entry = entry?;
        let Some(name) = entry.file_name().to_str() else {
            continue;
        };
        if !is_scenario_document(name) {
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
        ensure!(
            directories.insert(directory.clone()),
            "multiple scenario documents in {}; keep one scenarios.md, *.feature or *.feature.md",
            directory.display()
        );
        let directory = directory_id(root, &directory)?;
        let scenarios = if name == NOTEBOOK {
            Err(format!(
                "notebook scenarios are no longer supported; convert {} to scenarios.feature.md",
                entry.path().display()
            ))
        } else {
            read_listed(entry.path(), &directory)
        };
        found.push(Found {
            path: entry.path().to_owned(),
            directory,
            scenarios,
        });
    }
    ensure!(
        !found.is_empty(),
        "no scenarios found under {}",
        root.display()
    );
    found.sort_by(|a, b| a.directory.cmp(&b.directory));
    Ok(found)
}

/// The scenarios of the document at `path`, in the directory whose id is `directory`, or why the
/// document cannot be read. The reason has the same text the suite gives for the same file.
fn read_listed(path: &Path, directory: &str) -> std::result::Result<Vec<Listed>, String> {
    let document = if path.file_name() == Some(OsStr::new(SCENARIOS_MD)) {
        read_scenarios_md(path).map_err(|message| format!("{}: {message}", path.display()))?
    } else {
        morphir_gherkin::read_document(path)
            .map(|(document, _)| document)
            .map_err(|error| error.to_string())?
    };
    let feature = document
        .feature
        .as_ref()
        .ok_or_else(|| format!("{}: no Feature heading", path.display()))?;
    let scenarios = feature
        .scenarios
        .iter()
        .map(|scenario| (None, scenario))
        .chain(feature.rules.iter().flat_map(|rule| {
            rule.scenarios
                .iter()
                .map(move |scenario| (Some(rule), scenario))
        }));
    let mut ids = HashSet::new();
    let mut listed = Vec::new();
    for (rule, scenario) in scenarios {
        let section = scenario.tags.iter().find_map(|tag| match tag.namespaced() {
            Some(("section", id)) => Some(id.to_owned()),
            _ => None,
        });
        let section = markdown::section_id(&scenario.name, section)
            .map_err(|error| format!("{}: {error:#}", path.display()))?;
        let id = format!("{directory}#{section}");
        if !ids.insert(id.clone()) {
            return Err(format!(
                "{}: more than one scenario has the id {id}",
                path.display()
            ));
        }
        let tags = feature
            .tags
            .iter()
            .chain(rule.into_iter().flat_map(|rule| &rule.tags))
            .chain(&scenario.tags)
            .map(|tag| tag.name.clone())
            .collect();
        let description = [
            Some(&scenario.description),
            rule.map(|rule| &rule.description),
            Some(&feature.description),
        ]
        .into_iter()
        .flatten()
        .map(one_line)
        .find(|text| !text.is_empty())
        .unwrap_or_default();
        let wip = |tags: &[morphir_gherkin::Tag]| tags.iter().any(|tag| tag.name == "wip");
        let will_run = if wip(&feature.tags)
            || rule.is_some_and(|rule| wip(&rule.tags))
            || wip(&scenario.tags)
        {
            0
        } else {
            runs(scenario, |examples| !wip(&examples.tags))
        };
        listed.push(Listed {
            id,
            title: scenario.name.clone(),
            tags,
            description,
            runs: runs(scenario, |_| true),
            will_run,
        });
    }
    Ok(listed)
}

/// The prose of `description` on one line: its lines trimmed and joined with spaces.
fn one_line(description: &Description) -> String {
    description
        .prose()
        .flat_map(|block| block.markdown.lines())
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

/// How many scenarios the suite makes of `scenario`: 1, or one for each data row of an outline's
/// examples blocks that `counted` accepts.
fn runs(scenario: &GherkinScenario, counted: impl Fn(&morphir_gherkin::Examples) -> bool) -> usize {
    if scenario.examples.is_empty() {
        return 1;
    }
    scenario
        .examples
        .iter()
        .filter(|examples| counted(examples))
        .filter_map(|examples| examples.table.as_ref())
        .map(|table| table.rows.len().saturating_sub(1))
        .sum()
}

/// The tag expression for `--tag`: every tag required (`@a and @b`), or [`EVERY_SCENARIO`] when
/// none is given.
fn tag_expression(tags: &[String]) -> Result<String> {
    if tags.is_empty() {
        return Ok(EVERY_SCENARIO.to_owned());
    }
    for tag in tags {
        ensure!(
            !tag.is_empty()
                && !tag.starts_with('@')
                && !tag.contains(|c: char| c.is_whitespace() || c == '(' || c == ')'),
            "invalid tag {tag:?}: give one tag name without `@`, spaces or parentheses"
        );
    }
    let expression = tags
        .iter()
        .map(|tag| format!("@{tag}"))
        .collect::<Vec<_>>()
        .join(" and ");
    TagExpr::parse(&expression).map_err(|message| anyhow!(message))?;
    Ok(expression)
}

/// The arguments of `morphir itest`.
#[derive(Clone, Debug, clap::Args)]
pub struct ItestArgs {
    /// Directory to search recursively for scenarios.md, .feature and .feature.md files
    #[arg(default_value = "examples")]
    pub root: PathBuf,
    /// Select an example path, category or Markdown path#scenario relative to the search root
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

/// Runs `morphir itest`: lists or runs the selected example scenarios, and fails when a scenario
/// fails, a document cannot run, or the host cannot give the scenarios a clean configuration.
pub fn run_itest(args: ItestArgs) -> starbase::AppResult<miette::Report> {
    run_suite(args).map_err(|error| miette::miette!("{error:#}"))?;
    Ok(None)
}

/// The passed and failed scenario counts of a run, with the `PASS` and `FAIL` lines they print.
#[derive(Debug, Default)]
struct Tally {
    passed: usize,
    failed: usize,
}

impl Tally {
    fn fail(&mut self, id: &str, reason: &str) {
        self.fail_runs(id, reason, 1);
    }

    /// Prints one `FAIL` line for `id` and counts `runs` failed scenarios: an outline's rows all
    /// fail with it.
    fn fail_runs(&mut self, id: &str, reason: &str, runs: usize) {
        self.failed += runs;
        eprintln!("FAIL {id}\n{reason}");
    }
}

fn run_suite(args: ItestArgs) -> Result<()> {
    let filter = args.filter.as_deref();
    if let Some(filter) = filter {
        validate_filter(filter)?;
    }
    // Validated up front, like `filter`, so an invalid `--tag` (such as one already carrying
    // `@`) is reported as that, not folded into an "empty selection" below.
    let expression = tag_expression(&args.tags)?;
    let documents = find_documents(&args.root)?;
    let mut selected: Vec<&Listed> = documents
        .iter()
        .filter_map(|document| document.scenarios.as_ref().ok())
        .flatten()
        .filter(|scenario| scenario.selected(&args.tags, filter))
        .collect();
    selected.sort_by(|a, b| a.id.cmp(&b.id));
    let refused: Vec<(&Found, &str)> = documents
        .iter()
        .filter_map(|document| Some((document, document.refusal(filter)?)))
        .collect();
    // An empty selection is an error, as it always was, not a silently empty run: `--tag` or
    // `--filter` (or both) selecting nothing fails with the same text legacy itest gave. A
    // document `refused` still has something to report (its own `FAIL` line, below or in
    // `--list`'s own error), so these checks fire only when there is truly nothing to run or
    // list: no selected scenario and no refused document either.
    if !args.tags.is_empty() {
        let matches_tags = documents
            .iter()
            .filter_map(|document| document.scenarios.as_ref().ok())
            .flatten()
            .any(|scenario| scenario.selected(&args.tags, None));
        ensure!(
            matches_tags || !refused.is_empty(),
            "no scenarios match tags {:?}",
            args.tags
        );
    }
    if let Some(filter) = filter {
        ensure!(
            !selected.is_empty() || !refused.is_empty(),
            "no scenarios match path {filter:?} and tags {:?}",
            args.tags
        );
    }
    if args.list {
        for scenario in &selected {
            println!("{}", scenario.list_entry());
        }
        if refused.is_empty() {
            return Ok(());
        }
        bail!(
            "{}",
            refused
                .iter()
                .map(|(_, reason)| *reason)
                .collect::<Vec<_>>()
                .join("\n")
        );
    }
    check_host()?;
    let discovered: usize = documents.iter().map(Found::discovered).sum();
    let mut tally = Tally::default();
    let mut missing = 0;
    if let Err(error) = check_temporary_ancestors() {
        // Every scenario's temporary root shares these ancestors, so none of them can run.
        let reason = format!("{error:#}");
        for scenario in selected.iter().filter(|scenario| scenario.will_run > 0) {
            tally.fail_runs(&scenario.id, &reason, scenario.will_run);
        }
        for (document, reason) in &refused {
            tally.fail(&document.directory, reason);
        }
    } else {
        let runnable = documents
            .iter()
            .filter(|document| document.scenarios.is_ok())
            .map(|document| document.path.clone())
            .collect();
        let run = run_scenarios(&args, runnable, expression)?;
        tally.passed += run.passed;
        tally.failed += run.failed;
        let explained =
            report_documents_that_did_not_run(&args.root, &documents, &refused, &run, &mut tally);
        let expected = expected_runs(&documents, &args.tags, filter, &explained);
        let ran = run.passed + run.failed;
        if ran < expected {
            missing = expected - ran;
            eprintln!(
                "error: {missing} selected scenario(s) did not run, and no error says why; \
                 see the suite report in {}",
                run.reports.display()
            );
        }
    }
    println!(
        "{} passed; {} failed; {} not selected",
        tally.passed,
        tally.failed,
        discovered.saturating_sub(tally.passed + tally.failed)
    );
    ensure!(
        tally.failed == 0,
        "{} integration scenario(s) failed",
        tally.failed
    );
    ensure!(
        missing == 0,
        "{missing} selected integration scenario(s) did not run"
    );
    Ok(())
}

/// How many scenarios the suite should run: the `will_run` of every selected scenario of a
/// readable document, except the documents in `explained`, whose file errors were reported.
fn expected_runs(
    documents: &[Found],
    tags: &[String],
    filter: Option<&str>,
    explained: &HashSet<PathBuf>,
) -> usize {
    documents
        .iter()
        .filter(|document| !explained.contains(&document.path))
        .filter_map(|document| document.scenarios.as_ref().ok())
        .flatten()
        .filter(|scenario| scenario.selected(tags, filter))
        .map(|scenario| scenario.will_run)
        .sum()
}

/// Refuses a host whose system Morphir configuration the scenarios would read.
fn check_host() -> Result<()> {
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
    Ok(())
}

/// Refuses a temporary directory with Morphir configuration in it or above it. Every scenario's
/// temporary root is a new directory directly in the system temporary directory, so they all share
/// these ancestors, and this check runs once, before any scenario.
fn check_temporary_ancestors() -> Result<()> {
    // Project and enclosing-workspace discovery both walk ancestors. A local
    // .morphir directory only bounds outputs, not configuration discovery.
    let parent = std::env::temp_dir()
        .canonicalize()
        .context("itest cannot isolate temporary ancestor configuration")?;
    for ancestor in parent.ancestors() {
        let config = morphir_devkit::config::discover_config_at(ancestor)
            .context("itest cannot isolate temporary ancestor configuration")?;
        ensure!(
            config.is_none(),
            "itest cannot isolate temporary ancestor configuration at {}; choose a clean TMPDIR/TEMP",
            config.unwrap_or_default().display()
        );
    }
    Ok(())
}

/// What the suite reports back: the scenarios it passed and failed, and the errors that kept a
/// whole file from running.
#[derive(Debug)]
struct SuiteRun {
    passed: usize,
    failed: usize,
    error_messages: Vec<String>,
    /// Where the suite wrote its JSON report.
    reports: PathBuf,
}

/// The name of the thread the suite runs on.
const SUITE_THREAD: &str = "morphir-itest-suite";

/// Runs the scenarios of the `runnable` documents that `expression` and `--filter` select, one at
/// a time, and prints a `PASS` or `FAIL` line as each one finishes.
fn run_scenarios(
    args: &ItestArgs,
    runnable: HashSet<PathBuf>,
    expression: String,
) -> Result<SuiteRun> {
    steps::link();
    let binary = std::env::current_exe().context("locate the running Morphir CLI")?;
    let (reports, _reports) = report_dir()?;
    let root = args.root.clone();
    let filter = args.filter.clone();
    let keep = KeepTemp(args.keep_temp);
    let passed = Arc::new(AtomicUsize::new(0));
    let failed = Arc::new(AtomicUsize::new(0));
    let counts = (passed.clone(), failed.clone());
    // `Suite::run` drives cucumber-rs, whose event stream is not `Send`, so the suite runs to
    // completion on a thread of its own, under a runtime of its own.
    let result = std::thread::Builder::new()
        .name(SUITE_THREAD.to_owned())
        .spawn(move || -> Result<morphir_bdd::SuiteResult> {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .context("create a runtime for the itest suite")?;
            let reader: Reader = Arc::new(read_scenarios_md);
            let filter_root = root.clone();
            let outcome_root = root.clone();
            let suite = Suite::new("itest")
                .features(&root)
                .reader(SCENARIOS_MD, reader)
                .extensions(
                    standard_extensions()
                        .with_fences(ItestFence)
                        .with_processor(MaterializeExample),
                )
                .cli(&binary)
                .with_component(CustomCliRunner(Arc::new(ItestRunner)))
                .with_component(ItestRoot(root.clone()))
                .with_component(keep)
                .tags(expression)
                .filter(move |feature, _rule, scenario| {
                    let Some(path) = feature.path.as_deref() else {
                        return false;
                    };
                    if !runnable.contains(path) {
                        return false;
                    }
                    let Some(filter) = &filter else {
                        return true;
                    };
                    let section = scenario
                        .tags
                        .iter()
                        .find_map(|tag| tag.strip_prefix("section:"));
                    scenario_id_of(&filter_root, path, &scenario.name, section)
                        .is_ok_and(|id| matches_filter(&id, filter))
                })
                .max_concurrent_scenarios(1)
                .console(Console::Off)
                .out_dir(&reports)
                .on_scenario_finished(move |outcome| {
                    report_outcome(&outcome_root, outcome, &counts.0, &counts.1);
                });
            Ok(runtime.block_on(suite.run()))
        })
        .context("start the itest suite thread")?
        .join()
        .map_err(|_| anyhow!("the itest suite thread panicked"))??;
    Ok(SuiteRun {
        passed: passed.load(Ordering::SeqCst),
        failed: failed.load(Ordering::SeqCst),
        error_messages: result.error_messages,
        reports: result.json,
    })
}

/// Prints the `PASS` or `FAIL` line of one finished scenario and counts it. The step count is the
/// scenario's `@steps:` tag when the `scenarios.md` reader wrote one, else the steps it ran.
fn report_outcome(
    root: &Path,
    outcome: &ScenarioOutcome,
    passed: &AtomicUsize,
    failed: &AtomicUsize,
) {
    let section = outcome
        .tags
        .iter()
        .find_map(|tag| tag.strip_prefix("section:"));
    let id = scenario_id_of(root, &outcome.feature, &outcome.name, section)
        .unwrap_or_else(|_| format!("{}: {}", outcome.feature.display(), outcome.name));
    match &outcome.failure {
        None => {
            let steps = outcome
                .tags
                .iter()
                .find_map(|tag| tag.strip_prefix("steps:")?.parse().ok())
                .unwrap_or(outcome.steps);
            println!("PASS {id}: {} ({steps} steps)", outcome.name);
            passed.fetch_add(1, Ordering::SeqCst);
        }
        Some(failure) => {
            // A step's panic message is the reason; cucumber's own prefix adds nothing.
            let failure = failure
                .strip_prefix("Step panicked. Captured output: ")
                .unwrap_or(failure);
            eprintln!("FAIL {id}\n{failure}");
            failed.fetch_add(1, Ordering::SeqCst);
        }
    }
}

/// Prints a `FAIL` line for each document the suite could not run: one for each of the suite's
/// file errors (under the id of the directory it names), and one for each selected document the
/// suite does not read, such as a [`NOTEBOOK`]. A file error for a document `--filter` leaves
/// out, or for a file under one of the [`EXCLUDED_DIRS`], is not reported. Returns the paths of
/// the documents whose file errors were reported.
fn report_documents_that_did_not_run(
    root: &Path,
    documents: &[Found],
    refused: &[(&Found, &str)],
    run: &SuiteRun,
    tally: &mut Tally,
) -> HashSet<PathBuf> {
    let mut reported = HashSet::new();
    for message in &run.error_messages {
        if under_excluded_dir(root, message) {
            continue;
        }
        let named = documents
            .iter()
            .filter(|document| message.starts_with(&document.path.display().to_string()))
            .max_by_key(|document| document.path.as_os_str().len());
        match named {
            Some(document) => {
                let selected = document.scenarios.is_ok()
                    || refused
                        .iter()
                        .any(|(refused, _)| refused.path == document.path);
                if selected {
                    reported.insert(document.path.clone());
                    tally.fail(&document.directory, message);
                }
            }
            None => tally.fail(&root.display().to_string(), message),
        }
    }
    for (document, reason) in refused {
        if !reported.contains(&document.path) {
            tally.fail(&document.directory, reason);
        }
    }
    reported
}

/// Where the suite writes its JSON and JUnit reports: `MORPHIR_BDD_OUT` when set, else
/// `.dev/out/bdd` under the repository root (the nearest ancestor of the working directory with a
/// `Cargo.lock`). Outside a repository they go to a temporary directory that is removed after the
/// run, so an installed CLI leaves no files behind.
fn report_dir() -> Result<(PathBuf, Option<TempDir>)> {
    if let Some(dir) = std::env::var_os("MORPHIR_BDD_OUT") {
        return Ok((PathBuf::from(dir), None));
    }
    let cwd = std::env::current_dir().context("read the working directory")?;
    if let Some(repository) = cwd.ancestors().find(|dir| dir.join("Cargo.lock").is_file()) {
        return Ok((repository.join(".dev/out/bdd"), None));
    }
    let temp = tempfile::Builder::new()
        .prefix("morphir-itest-reports-")
        .tempdir()
        .context("create a directory for the itest reports")?;
    Ok((temp.path().to_owned(), Some(temp)))
}
