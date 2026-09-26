//! `morphir mck` — the Morphir Compatibility Kit command layer.
//!
//! This module owns argument shapes, terminal output and exit status only;
//! the kit grammar, loading, hashing, snapshots and status live in the
//! `morphir-mck` crate. The contract is `spec/mck/cli-contract.md`: stdout
//! carries the command's result, diagnostics go to stderr, 0 is success, 1 is
//! a failed check or an operational error, and 2 is a usage error.

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};

use clap::{Args, ValueEnum};
use morphir_bdd::{Console, Suite, SuiteResult};
use morphir_mck::ir::run::{RunState, report_of};
use morphir_mck::ir::{Run, RunOptions, RunVerdict, Testee, run_kit, verdict};
use morphir_mck::json::to_tab_json;
use morphir_mck::kit::embedded::{PROVENANCE, embedded_source};
use morphir_mck::kit::gherkin::convert::{convert, feature_description, feature_title};
use morphir_mck::kit::hash::ContentDigest;
use morphir_mck::kit::load::load_feature_kit;
use morphir_mck::kit::manifest::{CommitId, Lock, LockSource, UPSTREAM_REPOSITORY};
use morphir_mck::kit::snapshot::collect;
use morphir_mck::kit::status::{
    KitMode, KitStatus, MANIFEST_NAME, embedded_status, local_status, vendored_status,
};
use morphir_mck::kit::syntax::case::topic_of;
use morphir_mck::kit::vendor::{
    Change, Managed, UpdateOutcome, VendorOutcome, VendorSource, check_updatable,
    default_update_source, describe, open_managed, update, vendor,
};
use morphir_mck::kit::{KIT_PATH, Kit, KitCase, KitError, KitSource, load_kit};
use morphir_mck::provenance::{KitProvenance, KitSourceKind};
use morphir_mck::report::iso_timestamp;
use morphir_mck::steps::{KitRun, link};
use morphir_mck::transport::{Limits, Session, TransportError};
use serde_json::json;
use starbase::AppResult;

pub mod node_address;
pub mod package;
pub mod report;

#[derive(Args, Clone, Debug)]
pub struct MckSchemaCheckArgs {
    /// The kit directory or verified snapshot root; the embedded kit when omitted
    #[arg(long, value_name = "DIR")]
    pub kit: Option<PathBuf>,
    /// Repository root for a raw authoring kit
    #[arg(long, value_name = "DIR")]
    pub repo_root: Option<PathBuf>,
}

pub fn run_mck_schema_check(args: MckSchemaCheckArgs) -> AppResult<miette::Report> {
    let result = (|| {
        let kit = match &args.kit {
            None => load_kit(embedded_source()).map_err(|e| e.to_string())?,
            Some(dir) => load_directory(dir, args.repo_root.as_deref())?
                .kit()
                .clone(),
        };
        morphir_mck::schema::check(&kit).map_err(|e| e.to_string())
    })();
    finish(match result {
        Ok(report) => {
            print!("{report}");
            if report.is_success() {
                Outcome::Passed
            } else {
                Outcome::Failed
            }
        }
        Err(error) => Outcome::Error(error),
    })
}

#[derive(Args, Clone, Debug)]
pub struct MckCoverageArgs {
    /// A kit directory or vendored snapshot; the embedded kit when omitted
    #[arg(long, value_name = "DIR")]
    pub kit: Option<PathBuf>,

    /// Repository root holding spec/mck/vocabulary.json, inferred for spec/ir/mck
    #[arg(long, value_name = "DIR")]
    pub repo_root: Option<PathBuf>,
}

pub fn run_mck_coverage(args: MckCoverageArgs) -> AppResult<miette::Report> {
    use morphir_mck::ir::coverage::{Vocabulary, coverage_gaps};

    let loaded = match &args.kit {
        Some(dir) => load_directory(dir, args.repo_root.as_deref()),
        None => load_kit(embedded_source())
            .map(Loaded::Raw)
            .map_err(|error| format!("cannot read the embedded kit: {error}")),
    };
    let loaded = match loaded {
        Ok(loaded) => loaded,
        Err(message) => return finish(Outcome::Error(message)),
    };
    let kit = loaded.kit();
    if !kit.errors.is_empty() {
        for error in &kit.errors {
            eprintln!("{}:{}: {}", error.file, error.line, error.message);
        }
        return finish(Outcome::Failed);
    }
    let vocabulary = match Vocabulary::load(&kit.source) {
        Ok(vocabulary) => vocabulary,
        Err(error) => return finish(Outcome::Error(error.to_string())),
    };
    let gaps = coverage_gaps(&kit.cases, &vocabulary);
    if gaps.is_empty() {
        println!("coverage: every vocabulary entry has a case");
        finish(Outcome::Passed)
    } else {
        for gap in gaps {
            println!("{gap}");
        }
        finish(Outcome::Failed)
    }
}

#[derive(Args, Clone, Debug)]
pub struct MckCheckArgs {
    /// The kit directory to validate, for example spec/ir/mck, or a vendored
    /// snapshot's root
    pub dir: PathBuf,

    /// Repository root that `text` fences resolve against (inferred when the
    /// kit path ends in spec/ir/mck)
    #[arg(long, value_name = "DIR")]
    pub repo_root: Option<PathBuf>,

    /// Print the files, case ids and errors as JSON on stdout
    #[arg(long)]
    pub json: bool,
}

/// The options of `morphir mck convert`: the kit directory, and whether to check the
/// `.feature` twins instead of writing them.
#[derive(Args, Clone, Debug)]
pub struct MckConvertArgs {
    /// The kit directory whose Markdown case files to convert, for example spec/ir/mck
    #[arg(long, value_name = "DIR", default_value = "spec/ir/mck")]
    pub kit: PathBuf,

    /// Check that every committed `.feature` file matches its `.md` twin's conversion, writing
    /// nothing, instead of writing the files
    #[arg(long)]
    pub check: bool,
}

#[derive(Args, Clone, Debug)]
pub struct MckKitStatusArgs {
    /// A kit directory or a vendored snapshot's root; the kit embedded in
    /// this CLI when omitted
    #[arg(long, value_name = "DIR")]
    pub kit: Option<PathBuf>,

    /// Repository root that `text` fences resolve against (inferred when the
    /// kit path ends in spec/ir/mck)
    #[arg(long, value_name = "DIR")]
    pub repo_root: Option<PathBuf>,

    /// Print the status as JSON on stdout
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Clone, Debug)]
pub struct MckKitVendorArgs {
    /// Where the kit data comes from: `embedded` (this CLI's kit, offline),
    /// a local snapshot or finos/morphir checkout, or `github:finos/morphir`
    #[arg(long, value_name = "SOURCE")]
    pub source: String,

    /// The full 40-character commit to acquire; required with
    /// `github:finos/morphir` and refused with any other source
    #[arg(long, value_name = "COMMIT")]
    pub revision: Option<String>,

    /// Fail, writing nothing, unless the snapshot digest is exactly this
    #[arg(long, value_name = "DIGEST")]
    pub expect_digest: Option<String>,

    /// The directory to create; it must not exist, or be empty
    #[arg(long, value_name = "DIR")]
    pub dest: PathBuf,

    /// Print the outcome as JSON on stdout
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Clone, Debug)]
pub struct MckKitUpdateArgs {
    /// The root of the vendored snapshot to replace
    #[arg(long, value_name = "DIR")]
    pub kit: PathBuf,

    /// Where the new kit data comes from; defaults to the snapshot's own
    /// source when that needs no further input (`embedded`)
    #[arg(long, value_name = "SOURCE")]
    pub source: Option<String>,

    /// The full 40-character commit to acquire from github:finos/morphir.
    /// Without --source it updates a snapshot that came from GitHub; it is
    /// refused for any other source
    #[arg(long, value_name = "COMMIT")]
    pub revision: Option<String>,

    /// Fail, changing nothing, unless the new snapshot digest is exactly this
    #[arg(long, value_name = "DIGEST")]
    pub expect_digest: Option<String>,

    /// Print the outcome as JSON on stdout
    #[arg(long)]
    pub json: bool,
}

/// How a command ended, once its payload is printed.
enum Outcome {
    Passed,
    Failed,
    /// An operational failure: `error: <message>` on stderr, exit 1.
    Error(String),
    /// A usage error found after clap's parsing: message on stderr, exit 2,
    /// nothing done.
    Usage(String),
}

fn finish(outcome: Outcome) -> AppResult<miette::Report> {
    match outcome {
        Outcome::Passed => Ok(None),
        Outcome::Failed => Ok(Some(1)),
        Outcome::Error(message) => {
            eprintln!("error: {message}");
            Ok(Some(1))
        }
        Outcome::Usage(message) => {
            eprintln!("error: {message}");
            Ok(Some(2))
        }
    }
}

/// A kit given on the command line, after managed-snapshot verification.
enum Loaded {
    Raw(Kit),
    Managed(Box<Managed>),
}

impl Loaded {
    fn kit(&self) -> &Kit {
        match self {
            Self::Raw(kit) => kit,
            Self::Managed(managed) => &managed.kit,
        }
    }
}

/// Loads a kit directory. A snapshot root, or a kit directory whose
/// repository root holds `mck-kit.lock.json`, is a managed snapshot: it is
/// verified against its manifest before any case is read, and a failure is
/// an error, never a fallback to reading it raw.
fn load_directory(dir: &Path, repo_root: Option<&Path>) -> Result<Loaded, String> {
    let managed_root = if dir.join(MANIFEST_NAME).is_file() {
        Some(dir.to_path_buf())
    } else {
        let source = KitSource::directory(dir, repo_root);
        source
            .repo_root()
            .filter(|root| root.join(MANIFEST_NAME).exists())
            .map(Path::to_path_buf)
    };
    match managed_root {
        Some(root) => open_managed(&root)
            .map(|managed| Loaded::Managed(Box::new(managed)))
            .map_err(|error| error.to_string()),
        None => load_kit(KitSource::directory(dir, repo_root))
            .map(Loaded::Raw)
            .map_err(|error| format!("cannot read kit {}: {error}", dir.display())),
    }
}

/// The `.feature` file beside `md_file`: its repository-relative path with `.md` replaced by
/// `.feature`.
fn feature_sibling(md_file: &str) -> String {
    format!("{}.feature", md_file.strip_suffix(".md").unwrap_or(md_file))
}

/// The `.feature` text `md_file`'s current cases convert to (`feature_title`, `feature_description`
/// and `convert`), with its trailing newlines collapsed to exactly one, as the generated files
/// carry.
/// Whether `md_file` holds at least one kit case. A Markdown file with none,
/// such as the metadata suite's prose `metadata-contract-draft.md`, has no
/// `.feature` twin: `mck convert` skips it and the drift check does not ask for
/// one.
fn has_cases(kit: &Kit, md_file: &str) -> bool {
    let display = kit.source.display(md_file);
    kit.cases.iter().any(|c| c.file == display)
}

fn converted_feature_text(kit: &Kit, md_file: &str) -> Result<String, String> {
    let bytes = kit
        .source
        .read(md_file)
        .map_err(|error| format!("cannot read {md_file}: {error}"))?
        .ok_or_else(|| format!("{md_file} disappeared while converting the kit"))?;
    let markdown =
        std::str::from_utf8(&bytes).map_err(|_| format!("{md_file} is not valid UTF-8"))?;
    let display = kit.source.display(md_file);
    let cases: Vec<KitCase> = kit
        .cases
        .iter()
        .filter(|c| c.file == display)
        .cloned()
        .collect();
    let topic = topic_of(md_file);
    let mut text = convert(
        &feature_title(topic, markdown),
        &feature_description(markdown),
        &cases,
    );
    while text.ends_with('\n') {
        text.pop();
    }
    text.push('\n');
    Ok(text)
}

/// One `.feature` file that no longer matches converting its `.md` twin's current cases: its
/// committed text differs (`Changed`, carrying the `.feature` file's repository-relative path),
/// or it is not committed at all (`Missing`).
enum Drift {
    Changed(String),
    Missing,
}

/// The drift-check line for one `.feature` file, as both `mck check` and `mck convert --check`
/// print it.
fn drift_message(kit: &Kit, drift: &Drift, topic: &str) -> String {
    match drift {
        Drift::Changed(file) => {
            let target = kit.source.display(file);
            format!("{target}: out of date with {topic}.md; run morphir mck convert")
        }
        Drift::Missing => format!("{topic}.feature: missing; run morphir mck convert"),
    }
}

/// The `.md` files of `kit` whose `.feature` twin no longer matches converting their current
/// cases, as `(drift, topic)` pairs, in `kit.files` order. A `.feature` file that is not
/// committed yet is drift only when `feature_files_present` — the kit directory already carries
/// at least one other `.feature` file (`!FeatureKit.kit.files.is_empty()`); a Markdown-only kit,
/// with none at all, carries no twins yet during the parity window and is not drift, so ad hoc
/// `.md`-only fixture kits stay unaffected.
fn drifted_feature_files(
    kit: &Kit,
    feature_files_present: bool,
) -> Result<Vec<(Drift, String)>, String> {
    let mut drifted = Vec::new();
    for md_file in kit.files.iter().filter(|f| has_cases(kit, f)) {
        let feature_file = feature_sibling(md_file);
        let topic = topic_of(md_file).to_owned();
        let Some(committed) = kit
            .source
            .read(&feature_file)
            .map_err(|error| format!("cannot read {feature_file}: {error}"))?
        else {
            if feature_files_present {
                drifted.push((Drift::Missing, topic));
            }
            continue;
        };
        let expected = converted_feature_text(kit, md_file)?;
        if committed.as_ref() as &[u8] != expected.as_bytes() {
            drifted.push((Drift::Changed(feature_file), topic));
        }
    }
    Ok(drifted)
}

pub fn run_mck_check(args: MckCheckArgs) -> AppResult<miette::Report> {
    let outcome = match load_directory(&args.dir, args.repo_root.as_deref()) {
        Err(message) => Outcome::Error(message),
        Ok(loaded) => {
            let kit = loaded.kit();
            let feature = match load_feature_kit(kit.source.clone()) {
                Ok(feature) => feature,
                Err(error) => {
                    return finish(Outcome::Error(format!(
                        "cannot read kit {}: {error}",
                        args.dir.display()
                    )));
                }
            };
            let drifted = match drifted_feature_files(kit, !feature.kit.files.is_empty()) {
                Ok(drifted) => drifted,
                Err(message) => return finish(Outcome::Error(message)),
            };
            if args.json {
                let error_json =
                    |e: &KitError| json!({ "file": e.file, "line": e.line, "message": e.message });
                let errors: Vec<_> = kit
                    .errors
                    .iter()
                    .chain(&feature.kit.errors)
                    .map(error_json)
                    .collect();
                let cases: Vec<_> = kit.cases.iter().map(|c| c.id.as_str()).collect();
                let feature_cases: Vec<_> =
                    feature.kit.cases.iter().map(|c| c.id.as_str()).collect();
                let drifted_json: Vec<_> = drifted
                    .iter()
                    .map(|(drift, topic)| match drift {
                        Drift::Changed(file) => json!(file),
                        Drift::Missing => json!(format!("{topic}.feature")),
                    })
                    .collect();
                println!(
                    "{}",
                    to_tab_json(&json!({
                        "files": kit.files,
                        "cases": cases,
                        "metadataReferenceCases": kit.metadata_reference_cases,
                        "errors": errors,
                        "featureFiles": feature.kit.files,
                        "featureCases": feature_cases,
                        "drifted": drifted_json,
                    }))
                );
            } else {
                for error in kit.errors.iter().chain(&feature.kit.errors) {
                    eprintln!("{}:{}: {}", error.file, error.line, error.message);
                }
                for (drift, topic) in &drifted {
                    eprintln!("{}", drift_message(kit, drift, topic));
                }
                if kit.metadata_reference_cases > 0 {
                    print!(
                        "{} metadata reference case(s) admitted (separate metadata suite); ",
                        kit.metadata_reference_cases
                    );
                }
                println!(
                    "{} case(s) in {} file(s), {} error(s)",
                    kit.cases.len(),
                    kit.files.len(),
                    kit.errors.len() + feature.kit.errors.len() + drifted.len()
                );
            }
            if kit.errors.is_empty() && feature.kit.errors.is_empty() && drifted.is_empty() {
                Outcome::Passed
            } else {
                Outcome::Failed
            }
        }
    };
    finish(outcome)
}

/// `morphir mck convert`: write, or with `--check` verify, the `.feature` twin of every `.md`
/// case file under `args.kit`.
pub fn run_mck_convert(args: MckConvertArgs) -> AppResult<miette::Report> {
    let kit = match load_kit(KitSource::directory(&args.kit, None)) {
        Ok(kit) => kit,
        Err(error) => {
            return finish(Outcome::Error(format!(
                "cannot read kit {}: {error}",
                args.kit.display()
            )));
        }
    };
    if !kit.errors.is_empty() {
        for error in &kit.errors {
            eprintln!("{}:{}: {}", error.file, error.line, error.message);
        }
        return finish(Outcome::Error(format!(
            "kit {} has errors; run morphir mck check first",
            args.kit.display()
        )));
    }
    let outcome = if args.check {
        let feature = match load_feature_kit(kit.source.clone()) {
            Ok(feature) => feature,
            Err(error) => {
                return finish(Outcome::Error(format!(
                    "cannot read kit {}: {error}",
                    args.kit.display()
                )));
            }
        };
        match drifted_feature_files(&kit, !feature.kit.files.is_empty()) {
            Ok(drifted) if drifted.is_empty() => Outcome::Passed,
            Ok(drifted) => {
                for (drift, topic) in &drifted {
                    println!("{}", drift_message(&kit, drift, topic));
                }
                Outcome::Failed
            }
            Err(message) => Outcome::Error(message),
        }
    } else {
        let mut error = None;
        for md_file in kit.files.iter().filter(|f| has_cases(&kit, f)) {
            let text = match converted_feature_text(&kit, md_file) {
                Ok(text) => text,
                Err(message) => {
                    error = Some(message);
                    break;
                }
            };
            let target = kit.source.display(&feature_sibling(md_file));
            if let Err(write_error) = std::fs::write(&target, text.as_bytes()) {
                error = Some(format!("cannot write {target}: {write_error}"));
                break;
            }
            println!("wrote {target}");
        }
        match error {
            Some(message) => Outcome::Error(message),
            None => Outcome::Passed,
        }
    };
    finish(outcome)
}

fn print_status(status: &KitStatus) {
    let mode = match status.mode {
        KitMode::Embedded => "embedded",
        KitMode::Local => "local",
        KitMode::Vendored => "vendored",
    };
    println!("kit: {mode} ({})", status.label);
    if let Some(source) = status.source {
        println!("source: {source}");
    }
    println!("revision: {}", status.revision.as_deref().unwrap_or("none"));
    println!("modified: {}", status.modified);
    if let Some(digest) = &status.snapshot_digest {
        println!("snapshot digest: {digest}");
    }
    println!(
        "corpus hash: {} ({})",
        status
            .corpus_hash
            .as_deref()
            .unwrap_or("none; the kit has errors"),
        status.algorithm
    );
    println!(
        "{} case(s) in {} file(s), {} error(s)",
        status.cases, status.files, status.errors
    );
    println!("driver contract: {}", status.driver_contract);
}

pub fn run_mck_kit_status(args: MckKitStatusArgs) -> AppResult<miette::Report> {
    let status = match &args.kit {
        None => embedded_status().map_err(|error| format!("cannot read the embedded kit: {error}")),
        Some(dir) => load_directory(dir, args.repo_root.as_deref()).and_then(|loaded| {
            match &loaded {
                Loaded::Raw(kit) => local_status(kit),
                Loaded::Managed(managed) => vendored_status(managed),
            }
            .map_err(|error| format!("cannot hash kit {}: {error}", dir.display()))
        }),
    };
    finish(match status {
        Err(message) => Outcome::Error(message),
        Ok(status) => {
            if args.json {
                println!("{}", to_tab_json(&status));
            } else {
                print_status(&status);
            }
            if status.is_ok() {
                Outcome::Passed
            } else {
                Outcome::Failed
            }
        }
    })
}

mod acquire;

/// A source as given on the command line: ready to read, or a commit to fetch.
enum Requested {
    Ready(VendorSource),
    Github(CommitId),
}

/// Parses `--source`, `--revision` and `--expect-digest`. Any mismatch is a
/// usage error, reported before anything is read, fetched or written.
fn parse_source(
    source: &str,
    revision: Option<&str>,
    expect_digest: Option<&str>,
) -> Result<(Requested, Option<ContentDigest>), String> {
    let expected = expect_digest
        .map(ContentDigest::parse)
        .transpose()
        .map_err(|why| format!("--expect-digest: {why}"))?;
    if let Some(repository) = source.strip_prefix("github:") {
        if repository != UPSTREAM_REPOSITORY {
            return Err(format!(
                "--source github:{repository}: only github:{UPSTREAM_REPOSITORY} is supported"
            ));
        }
        let Some(revision) = revision else {
            return Err(format!(
                "--source github:{UPSTREAM_REPOSITORY} needs --revision <full 40-character commit>"
            ));
        };
        let revision = CommitId::parse(revision).map_err(|why| {
            format!("--revision: {why}; branches, tags and short ids are not accepted")
        })?;
        return Ok((Requested::Github(revision), expected));
    }
    if revision.is_some() {
        return Err(format!(
            "--revision applies only to --source github:{UPSTREAM_REPOSITORY}"
        ));
    }
    let source = if source == "embedded" {
        VendorSource::Embedded
    } else {
        VendorSource::Local(PathBuf::from(source))
    };
    Ok((Requested::Ready(source), expected))
}

/// Resolves a requested source, downloading a GitHub archive when asked. The
/// returned file handle keeps the download alive until the caller is done.
async fn resolve(
    requested: Requested,
) -> Result<(VendorSource, Option<tempfile::NamedTempFile>), String> {
    match requested {
        Requested::Ready(source) => Ok((source, None)),
        Requested::Github(revision) => {
            let archive = acquire::download(&revision).await?;
            let source = VendorSource::GithubArchive {
                archive: archive.path().to_path_buf(),
                revision,
            };
            Ok((source, Some(archive)))
        }
    }
}

fn lock_json(lock: &Lock) -> serde_json::Value {
    json!({
        "source": lock.source.kind(),
        "revision": lock.source.revision().map(CommitId::as_str),
        "snapshotDigest": lock.snapshot_digest.as_str(),
        "corpusHash": lock.corpus_hash.as_str(),
        "files": lock.files.len(),
    })
}

fn print_lock(lock: &Lock) {
    println!("source: {}", lock.source.kind());
    println!(
        "revision: {}",
        lock.source.revision().map_or("none", CommitId::as_str)
    );
    println!("snapshot digest: {}", lock.snapshot_digest);
    println!("corpus hash: {}", lock.corpus_hash);
    println!("{} file(s)", lock.files.len());
}

pub async fn run_mck_kit_vendor(args: MckKitVendorArgs) -> AppResult<miette::Report> {
    let (requested, expected) = match parse_source(
        &args.source,
        args.revision.as_deref(),
        args.expect_digest.as_deref(),
    ) {
        Ok(parsed) => parsed,
        Err(message) => return finish(Outcome::Usage(message)),
    };
    let remote = matches!(requested, Requested::Github(_));
    let (source, _download) = match resolve(requested).await {
        Ok(resolved) => resolved,
        Err(message) => return finish(Outcome::Error(message)),
    };
    let outcome = match vendor(&source, &args.dest, expected.as_ref()) {
        Err(error) => Outcome::Error(error.to_string()),
        Ok(outcome) => {
            let (created, lock) = match &outcome {
                VendorOutcome::Created(lock) => (true, lock),
                VendorOutcome::Unchanged(lock) => (false, lock),
            };
            if args.json {
                let mut payload = lock_json(lock);
                payload["outcome"] = json!(if created { "created" } else { "unchanged" });
                payload["dest"] = json!(args.dest.display().to_string());
                println!("{}", to_tab_json(&payload));
            } else {
                let verb = if created {
                    "vendored"
                } else {
                    "already vendored"
                };
                println!("{verb} {} into {}", describe(&source), args.dest.display());
                print_lock(lock);
            }
            if remote {
                eprintln!("{}", acquire::TRUST_NOTE);
            }
            if created {
                eprintln!(
                    "note: commit {} with its {MANIFEST_NAME}, and keep its bytes exact, for example with `{}/** -text` in .gitattributes",
                    args.dest.display(),
                    args.dest.display().to_string().replace('\\', "/")
                );
            }
            Outcome::Passed
        }
    };
    finish(outcome)
}

pub async fn run_mck_kit_update(args: MckKitUpdateArgs) -> AppResult<miette::Report> {
    // Everything decidable from the arguments alone is a usage error first.
    let explicit = match &args.source {
        Some(source) => match parse_source(
            source,
            args.revision.as_deref(),
            args.expect_digest.as_deref(),
        ) {
            Ok(parsed) => Some(parsed),
            Err(message) => return finish(Outcome::Usage(message)),
        },
        None => None,
    };
    let expected = match args
        .expect_digest
        .as_deref()
        .map(ContentDigest::parse)
        .transpose()
    {
        Ok(expected) => expected,
        Err(why) => return finish(Outcome::Usage(format!("--expect-digest: {why}"))),
    };
    let revision = match args.revision.as_deref().map(CommitId::parse).transpose() {
        Ok(revision) => revision,
        Err(why) => {
            return finish(Outcome::Usage(format!(
                "--revision: {why}; branches, tags and short ids are not accepted"
            )));
        }
    };

    // The existing snapshot is verified before anything is fetched, so one
    // that will be refused costs no download.
    let lock = match check_updatable(&args.kit) {
        Ok(lock) => lock,
        Err(error) => return finish(Outcome::Error(error.to_string())),
    };
    let (requested, expected) = match explicit {
        Some(parsed) => parsed,
        None => match (&lock.source, revision) {
            (LockSource::Github { .. }, Some(revision)) => (Requested::Github(revision), expected),
            (_, Some(_)) => {
                return finish(Outcome::Usage(format!(
                    "--revision applies only to a snapshot from github:{UPSTREAM_REPOSITORY}, or with --source github:{UPSTREAM_REPOSITORY}"
                )));
            }
            (_, None) => match default_update_source(&lock) {
                Ok(source) => (Requested::Ready(source), expected),
                Err(error) => return finish(Outcome::Error(error.to_string())),
            },
        },
    };
    let remote = matches!(requested, Requested::Github(_));
    let (source, _download) = match resolve(requested).await {
        Ok(resolved) => resolved,
        Err(message) => return finish(Outcome::Error(message)),
    };
    if remote {
        eprintln!("{}", acquire::TRUST_NOTE);
    }
    let outcome = match update(&args.kit, &source, expected.as_ref()) {
        Err(error) => Outcome::Error(error.to_string()),
        Ok(UpdateOutcome::Unchanged(lock)) => {
            if args.json {
                let mut payload = lock_json(&lock);
                payload["outcome"] = json!("unchanged");
                println!("{}", to_tab_json(&payload));
            } else {
                println!(
                    "{} is already the snapshot {} would produce",
                    args.kit.display(),
                    describe(&source)
                );
                print_lock(&lock);
            }
            Outcome::Passed
        }
        Ok(UpdateOutcome::Updated(report)) => {
            let sign = |change: Change| match change {
                Change::Added => "+",
                Change::Removed => "-",
                Change::Changed => "~",
            };
            if args.json {
                let changes: Vec<_> = report
                    .changes
                    .iter()
                    .map(|(path, change)| json!({ "path": path, "change": format!("{change:?}").to_lowercase() }))
                    .collect();
                println!(
                    "{}",
                    to_tab_json(
                        &json!({ "outcome": "updated", "old": lock_json(&report.old), "new": lock_json(&report.new), "changes": changes })
                    )
                );
            } else {
                println!("updated {} from {}", args.kit.display(), describe(&source));
                println!(
                    "revision: {} -> {}",
                    report
                        .old
                        .source
                        .revision()
                        .map_or("none", CommitId::as_str),
                    report
                        .new
                        .source
                        .revision()
                        .map_or("none", CommitId::as_str)
                );
                println!(
                    "snapshot digest: {} -> {}",
                    report.old.snapshot_digest, report.new.snapshot_digest
                );
                for (path, change) in &report.changes {
                    println!("  {} {path}", sign(*change));
                }
            }
            eprintln!("note: review and commit the change; nothing was committed");
            if let Some(leftover) = &report.leftover {
                eprintln!(
                    "warning: could not delete the previous snapshot at {}; delete it by hand",
                    leftover.display()
                );
            }
            Outcome::Passed
        }
    };
    finish(outcome)
}

/// Which engine `mck run` runs the kit through. Both give the same report,
/// terminal output and exit code for the same inputs; `legacy` is the
/// default.
#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
pub enum Engine {
    /// The kit's Markdown case files, through the legacy per-fence run loop
    Legacy,
    /// The kit's `.feature` case files, through a `morphir_bdd::Suite`
    Gherkin,
}

#[derive(Args, Clone, Debug)]
pub struct MckRunArgs {
    /// Compatibility suite to execute
    #[arg(long, value_enum, default_value_t = MckSuite::Ir)]
    pub suite: MckSuite,
    /// The implementation's adapter executable. Required: there is no
    /// built-in binding and no discovery
    #[arg(long, value_name = "EXE", required = true)]
    pub adapter: OsString,

    /// An argument for the adapter; repeat for more
    #[arg(long = "adapter-arg", value_name = "ARG", allow_hyphen_values = true)]
    pub adapter_args: Vec<OsString>,

    /// A kit directory or vendored snapshot; the kit embedded in this CLI
    /// when omitted
    #[arg(long, value_name = "DIR")]
    pub kit: Option<PathBuf>,

    /// Repository root that `text` fences resolve against (inferred when the
    /// kit path ends in spec/ir/mck)
    #[arg(long, value_name = "DIR")]
    pub repo_root: Option<PathBuf>,

    /// Write the version 1 report here, and its provenance beside it
    #[arg(long, value_name = "FILE")]
    pub report: Option<PathBuf>,

    /// Fail when any fence is skipped, not only when one fails
    #[arg(long)]
    pub strict: bool,

    /// Run only the cases whose id matches this Rust regular expression,
    /// unanchored
    #[arg(long, alias = "only", value_name = "REGEX")]
    pub filter: Option<String>,

    /// How long one request may wait for its answer, in milliseconds
    #[arg(long, value_name = "MS", default_value_t = 30_000, value_parser = clap::value_parser!(u64).range(1..))]
    pub timeout: u64,

    /// How long the whole adapter session may last, in milliseconds
    #[arg(long, value_name = "MS", default_value_t = 1_800_000, value_parser = clap::value_parser!(u64).range(1..))]
    pub session_timeout: u64,

    /// Which engine runs the kit: `legacy` runs its Markdown case files
    /// through the per-fence run loop; `gherkin` runs its `.feature` case
    /// files through a `morphir_bdd::Suite`. Both give the same report,
    /// terminal output and exit code for the same inputs
    #[arg(long, value_enum, default_value = "legacy")]
    pub engine: Engine,
}

#[derive(clap::ValueEnum, Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MckSuite {
    #[default]
    Ir,
    Metadata,
}

/// An adapter that never started: every exchange reports why.
struct Unstarted(String);

impl Testee for Unstarted {
    fn exchange(
        &mut self,
        _: &morphir_mck::transport::protocol::Request,
    ) -> Result<serde_json::Map<String, serde_json::Value>, String> {
        Err(self.0.clone())
    }
}

impl morphir_mck::metadata::run::MetadataTestee for Unstarted {
    fn exchange(
        &mut self,
        _: &serde_json::Value,
    ) -> Result<serde_json::Map<String, serde_json::Value>, String> {
        Err(self.0.clone())
    }
}

/// A `Testee` that exchanges through a `Session` kept behind a shared lock.
/// `KitRun` owns its testee as a `Box<dyn Testee + Send>`, which erases
/// `Session`'s concrete type; wrapping it this way keeps a second handle to
/// the same session outside the `KitRun`, so the gherkin engine can reclaim
/// it once the `Suite` that runs the kit has finished with it, and close it
/// exactly as the legacy engine does.
struct SharedSession(Arc<Mutex<Session>>);

impl Testee for SharedSession {
    fn exchange(
        &mut self,
        request: &morphir_mck::transport::protocol::Request,
    ) -> Result<serde_json::Map<String, serde_json::Value>, String> {
        self.0
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .exchange(request)
            .map_err(|error| error.to_string())
    }
}

/// The text of a `.feature` scenario's name before its first space: `<id>
/// <title>` gives `<id>`, the case id the legacy engine's `--filter` matches.
fn case_id_of(name: &str) -> &str {
    name.split(' ').next().unwrap_or(name)
}

/// Writes `source`'s top-level `.feature` case files into `dir`, flat, so a
/// `morphir_bdd::Suite` can discover them without a real kit directory on
/// disk. Used only for a `KitSource::Map` (the embedded kit): a
/// `KitSource::Directory` is already a real directory a `Suite` can scan
/// directly.
fn write_feature_files(source: &KitSource, dir: &Path) -> Result<(), String> {
    let prefix = format!("{KIT_PATH}/");
    for path in source.list().map_err(|error| error.to_string())? {
        let Some(name) = path.strip_prefix(&prefix) else {
            continue;
        };
        if name.contains('/') || !name.ends_with(".feature") {
            continue;
        }
        let bytes = source
            .read(&path)
            .map_err(|error| error.to_string())?
            .ok_or_else(|| format!("{path} disappeared while materializing the kit"))?;
        let target = dir.join(name);
        std::fs::write(&target, &bytes)
            .map_err(|error| format!("cannot write {}: {error}", target.display()))?;
    }
    Ok(())
}

/// `git rev-parse HEAD` in a raw checkout, which is what the first driver
/// reported as `kitVersion`. Git is optional: without it, or outside a
/// repository, the answer is `unknown`.
fn checkout_revision(dir: &Path) -> String {
    let mut command = std::process::Command::new("git");
    command
        .arg("-C")
        .arg(dir)
        .args(["rev-parse", "HEAD"])
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt as _;
        command.creation_flags(0x0800_0000);
    }
    command
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
        .filter(|revision| revision.len() == 40)
        .unwrap_or_else(|| "unknown".to_owned())
}

/// The kit to run, what the report calls its version, and its provenance.
fn kit_for_run(args: &MckRunArgs) -> Result<(Kit, String, KitProvenance), String> {
    let digest = |kit: &Kit, source: morphir_mck::kit::manifest::LockSource| {
        collect(kit)
            .ok()
            .map(|snapshot| snapshot.lock(source).snapshot_digest.as_str().to_owned())
    };
    let corpus = |kit: &Kit| {
        kit.corpus_hash()
            .ok()
            .flatten()
            .map(|h| h.as_str().to_owned())
    };
    match &args.kit {
        None => {
            let kit = load_kit(embedded_source())
                .map_err(|error| format!("cannot read the embedded kit: {error}"))?;
            let revision = PROVENANCE.revision.map(str::to_owned);
            let snapshot = digest(
                &kit,
                morphir_mck::kit::manifest::LockSource::Local { revision: None },
            );
            let provenance = KitProvenance {
                source: KitSourceKind::Embedded,
                revision: revision.clone().filter(|_| !PROVENANCE.dirty),
                snapshot_digest: snapshot,
                corpus_hash: corpus(&kit),
                modified: PROVENANCE.dirty,
            };
            Ok((
                kit,
                revision.unwrap_or_else(|| "unknown".to_owned()),
                provenance,
            ))
        }
        Some(dir) => match load_directory(dir, args.repo_root.as_deref())? {
            Loaded::Managed(managed) => {
                let revision = managed
                    .lock
                    .source
                    .revision()
                    .map(|r| r.as_str().to_owned());
                let provenance = KitProvenance {
                    source: KitSourceKind::Vendored,
                    revision: revision.clone(),
                    snapshot_digest: Some(managed.lock.snapshot_digest.as_str().to_owned()),
                    corpus_hash: Some(managed.lock.corpus_hash.as_str().to_owned()),
                    modified: false,
                };
                Ok((
                    managed.kit,
                    revision.unwrap_or_else(|| "unknown".to_owned()),
                    provenance,
                ))
            }
            Loaded::Raw(kit) => {
                let modified = local_status(&kit).map(|s| s.modified).unwrap_or(true);
                let provenance = KitProvenance {
                    source: KitSourceKind::Local,
                    revision: None,
                    snapshot_digest: digest(
                        &kit,
                        morphir_mck::kit::manifest::LockSource::Local { revision: None },
                    ),
                    corpus_hash: corpus(&kit),
                    modified,
                };
                Ok((kit, checkout_revision(dir), provenance))
            }
        },
    }
}

pub async fn run_mck_run(args: MckRunArgs) -> AppResult<miette::Report> {
    // Usage first: nothing starts until the arguments are known to be good.
    let filter = match args.filter.as_deref().map(regex::Regex::new).transpose() {
        Ok(filter) => filter,
        Err(error) => return finish(Outcome::Usage(format!("invalid --filter regex: {error}"))),
    };
    if args.suite == MckSuite::Metadata {
        if args.engine == Engine::Gherkin {
            return finish(Outcome::Usage(
                "--engine gherkin runs the IR suite only; drop --engine or use --suite ir"
                    .to_owned(),
            ));
        }
        return run_mck_metadata(args, filter).await;
    }
    let (kit, kit_version, kit_provenance) = match kit_for_run(&args) {
        Ok(found) => found,
        Err(message) => return finish(Outcome::Error(message)),
    };
    let limits = Limits {
        request_timeout: std::time::Duration::from_millis(args.timeout),
        session_timeout: std::time::Duration::from_millis(args.session_timeout),
        ..Limits::DEFAULT
    };
    let command: Vec<String> = std::iter::once(&args.adapter)
        .chain(&args.adapter_args)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();

    let started_at = iso_timestamp(std::time::SystemTime::now());
    let origin = std::time::Instant::now();

    // `RunOptions` carries a bare `&dyn Fn`, so it is not `Sync`, and a reference to it cannot
    // be held across an await. It stays scoped to the legacy arm below, which awaits nothing;
    // the gherkin arm (`run_gherkin`, which does await) takes owned copies of the three fields
    // it needs instead of a `RunOptions`.
    let (run, shutdown, spawn_error) = match args.engine {
        Engine::Legacy => {
            let clock = move || origin.elapsed().as_secs_f64() * 1000.0;
            let options = RunOptions {
                filter: filter.as_ref(),
                driver_version: env!("CARGO_PKG_VERSION").to_owned(),
                kit_version,
                started_at,
                clock: &clock,
            };
            match Session::spawn(&args.adapter, &args.adapter_args, limits) {
                Err(error) => (
                    run_kit(&kit, &mut Unstarted(error.to_string()), &options),
                    Ok(()),
                    Some(error.to_string()),
                ),
                Ok(mut session) => {
                    // Ctrl-C takes the adapter's whole tree down with the CLI.
                    let terminator = session.terminator();
                    let interrupt = tokio::spawn(async move {
                        if tokio::signal::ctrl_c().await.is_ok() {
                            terminator.kill();
                            eprintln!("error: interrupted; the adapter was terminated");
                            std::process::exit(130);
                        }
                    });
                    let run = tokio::task::block_in_place(|| run_kit(&kit, &mut session, &options));
                    let shutdown = tokio::task::block_in_place(|| session.close());
                    interrupt.abort();
                    (run, shutdown, None)
                }
            }
        }
        Engine::Gherkin => {
            let meta = ReportMeta {
                driver_version: env!("CARGO_PKG_VERSION").to_owned(),
                kit_version,
                started_at,
            };
            match run_gherkin(&args, &kit, limits, meta, origin, filter.as_ref()).await {
                Ok(triple) => triple,
                Err(outcome) => return finish(outcome),
            }
        }
    };

    if let Some(header) = &run.header {
        eprintln!("{header}");
    }
    if let Some(file) = &args.report {
        let draft = match report::assemble(
            &run,
            kit_provenance,
            command,
            args.filter.as_deref(),
            args.strict,
            spawn_error.as_deref(),
            shutdown.as_ref().err().map(ToString::to_string).as_deref(),
        ) {
            Ok(draft) => draft,
            Err(error) => {
                return finish(Outcome::Error(format!("cannot construct report: {error}")));
            }
        };
        if let Err(error) = report::write_atomic(file, draft.to_json().as_bytes()) {
            return finish(Outcome::Error(format!(
                "cannot write the report {}: {error}",
                file.display()
            )));
        }
    }
    println!("{}", run.report.summary_line());
    for record in run
        .report
        .records
        .iter()
        .filter(|r| r.result != morphir_mck::report::Outcome::Pass)
    {
        let path = record.path.map_or_else(String::new, |p| format!(" [{p}]"));
        println!(
            "{} {} fence {}{path}: {}",
            record.result.as_str(),
            record.case_id,
            record.fence_index,
            record.message.as_deref().unwrap_or("")
        );
    }
    if let Err(error) = shutdown {
        return finish(Outcome::Error(error.to_string()));
    }
    match verdict(&run.report, args.strict) {
        RunVerdict::Passed => finish(Outcome::Passed),
        RunVerdict::Failed => finish(Outcome::Failed),
        RunVerdict::NothingSelected => finish(Outcome::Error("no cases selected".to_owned())),
    }
}

async fn run_mck_metadata(
    args: MckRunArgs,
    filter: Option<regex::Regex>,
) -> AppResult<miette::Report> {
    let (kit, kit_version, kit_provenance) = match kit_for_run(&args) {
        Ok(found) => found,
        Err(message) => return finish(Outcome::Error(message)),
    };
    let limits = Limits {
        request_timeout: std::time::Duration::from_millis(args.timeout),
        session_timeout: std::time::Duration::from_millis(args.session_timeout),
        ..Limits::DEFAULT
    };
    let command: Vec<String> = std::iter::once(&args.adapter)
        .chain(&args.adapter_args)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    let started_at = iso_timestamp(std::time::SystemTime::now());
    let (run, shutdown, spawn_error) =
        match Session::spawn(&args.adapter, &args.adapter_args, limits) {
            Err(error) => (
                morphir_mck::metadata::run::run_kit(
                    &kit,
                    &mut Unstarted(error.to_string()),
                    filter.as_ref(),
                ),
                Ok(()),
                Some(error.to_string()),
            ),
            Ok(mut session) => {
                let terminator = session.terminator();
                let interrupt = tokio::spawn(async move {
                    if tokio::signal::ctrl_c().await.is_ok() {
                        terminator.kill();
                        eprintln!("error: interrupted; the adapter was terminated");
                        std::process::exit(130);
                    }
                });
                let run = tokio::task::block_in_place(|| {
                    morphir_mck::metadata::run::run_kit(&kit, &mut session, filter.as_ref())
                });
                let shutdown = tokio::task::block_in_place(|| session.close());
                interrupt.abort();
                (run, shutdown, None)
            }
        };
    if let Some(file) = &args.report {
        let mut provenance = match serde_json::to_value(kit_provenance) {
            Ok(value) => value,
            Err(error) => return finish(Outcome::Error(error.to_string())),
        };
        provenance["version"] = serde_json::json!(kit_version);
        let report = match morphir_mck::metadata::report::assemble(
            &run,
            provenance,
            command,
            args.filter.as_deref(),
            args.strict,
            &started_at,
            (
                spawn_error.as_deref(),
                shutdown.as_ref().err().map(ToString::to_string).as_deref(),
            ),
        ) {
            Ok(report) => report,
            Err(error) => {
                return finish(Outcome::Error(format!(
                    "cannot construct metadata report: {error}"
                )));
            }
        };
        if let Err(error) = report::write_atomic(file, report.to_json().as_bytes()) {
            return finish(Outcome::Error(format!(
                "cannot write report {}: {error}",
                file.display()
            )));
        }
    }
    let count = |kind: &str| run.records.iter().filter(|r| r.result == kind).count();
    println!(
        "{} pass, {} fail, {} kit-error, {} skipped",
        count("pass"),
        count("fail"),
        count("kit-error"),
        count("skipped")
    );
    for record in run.records.iter().filter(|r| r.result != "pass") {
        println!(
            "{} {}: {}",
            record.result,
            record.case_id,
            record.message.as_deref().unwrap_or("")
        );
    }
    if let Err(error) = shutdown {
        return finish(Outcome::Error(error.to_string()));
    }
    if let Some(error) = run.failure {
        return finish(Outcome::Error(error));
    }
    if run.records.is_empty() {
        return finish(Outcome::Error("no cases selected".into()));
    }
    if count("fail") > 0 || count("kit-error") > 0 || (args.strict && count("skipped") > 0) {
        finish(Outcome::Failed)
    } else {
        finish(Outcome::Passed)
    }
}

/// The report fields `run_gherkin` needs from `RunOptions`. It cannot take a
/// borrowed `RunOptions` itself: that type carries a bare `&dyn Fn`, so it is
/// not `Sync`, and a reference to it cannot be held across `run_gherkin`'s
/// internal await.
struct ReportMeta {
    driver_version: String,
    kit_version: String,
    started_at: String,
}

/// Runs `kit`'s `.feature` files through a `morphir_bdd::Suite`, one scenario
/// at a time, over the same adapter session the legacy engine would build
/// (same spawn, same timeouts, same shutdown). Returns exactly what
/// `run_mck_run`'s legacy match arm returns, so the rest of that function
/// treats both engines alike; the only new failure mode, which the legacy
/// arm cannot hit, is reported as an `Err(Outcome)` the caller turns into a
/// finished command instead of a triple.
async fn run_gherkin(
    args: &MckRunArgs,
    kit: &Kit,
    limits: Limits,
    meta: ReportMeta,
    origin: std::time::Instant,
    filter: Option<&regex::Regex>,
) -> Result<(Run, Result<(), TransportError>, Option<String>), Outcome> {
    let feature_kit = load_feature_kit(kit.source.clone()).map_err(|error| {
        Outcome::Error(format!("cannot read the kit's .feature files: {error}"))
    })?;
    if feature_kit.kit.files.is_empty() {
        return Err(Outcome::Usage(
            "the kit has no .feature files; run morphir mck convert, or use --engine legacy"
                .to_owned(),
        ));
    }

    // A directory-backed kit source is already a real directory the `Suite` can scan; the
    // embedded kit (a `KitSource::Map`) has no filesystem home, so its top-level `.feature`
    // files are written flat into a temp dir kept alive until the `Suite` has run.
    let mut features_temp = None;
    let features_dir: PathBuf = match &kit.source {
        KitSource::Directory { kit_root, .. } => kit_root.clone(),
        KitSource::Map { .. } => {
            let dir = tempfile::tempdir().map_err(|error| {
                Outcome::Error(format!("cannot create a temporary directory: {error}"))
            })?;
            write_feature_files(&kit.source, dir.path()).map_err(Outcome::Error)?;
            let path = dir.path().to_path_buf();
            features_temp = Some(dir);
            path
        }
    };

    // cucumber-rs collects steps through link-time registration: a step defined in
    // `morphir_mck::steps` reaches this binary only if it is asked for explicitly.
    link();

    let (kit_run, session, spawn_error) =
        match Session::spawn(&args.adapter, &args.adapter_args, limits) {
            Err(error) => {
                let kit_run = KitRun::new(
                    feature_kit,
                    Box::new(Unstarted(error.to_string())),
                    Box::new(move || origin.elapsed().as_secs_f64() * 1000.0),
                );
                (kit_run, None, Some(error.to_string()))
            }
            Ok(session) => {
                let session = Arc::new(Mutex::new(session));
                let kit_run = KitRun::new(
                    feature_kit,
                    Box::new(SharedSession(session.clone())),
                    Box::new(move || origin.elapsed().as_secs_f64() * 1000.0),
                );
                (kit_run, Some(session), None)
            }
        };

    // Ctrl-C takes the adapter's whole tree down with the CLI, as the legacy engine does.
    let interrupt = session.as_ref().map(|session| {
        let terminator = session
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .terminator();
        tokio::spawn(async move {
            if tokio::signal::ctrl_c().await.is_ok() {
                terminator.kill();
                eprintln!("error: interrupted; the adapter was terminated");
                std::process::exit(130);
            }
        })
    });

    // `Suite::run` drives cucumber-rs, whose own event stream is not `Send`; awaiting it in
    // place would make this whole function's future non-`Send`, which the CLI's boxed command
    // future cannot accept. So it runs to completion on a plain OS thread, under a runtime of
    // its own, and hands its `SuiteResult` back over a channel a `Send` future can await.
    let filter = filter.cloned();
    let out_dir = tempfile::tempdir()
        .map_err(|error| Outcome::Error(format!("cannot create a temporary directory: {error}")))?;
    let suite_kit_run = kit_run.clone();
    let (result_tx, result_rx) = tokio::sync::oneshot::channel::<Result<SuiteResult, String>>();
    let suite_thread = std::thread::Builder::new()
        .name("mck-gherkin-suite".to_owned())
        .spawn(move || {
            let runtime = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime,
                Err(error) => {
                    let _ = result_tx.send(Err(format!(
                        "cannot create a runtime for the kit suite: {error}"
                    )));
                    return;
                }
            };
            let result = runtime.block_on(
                Suite::new("mck")
                    .features(&features_dir)
                    .tags("@nothing or not @nothing")
                    .filter(move |_, _, scenario| {
                        filter
                            .as_ref()
                            .is_none_or(|re| re.is_match(case_id_of(&scenario.name)))
                    })
                    .max_concurrent_scenarios(1)
                    .with_component(suite_kit_run)
                    .console(Console::Off)
                    .out_dir(out_dir.path())
                    .run(),
            );
            let _ = result_tx.send(Ok(result));
        });
    let suite_thread = match suite_thread {
        Ok(handle) => handle,
        Err(error) => {
            return Err(Outcome::Error(format!(
                "cannot start the kit suite thread: {error}"
            )));
        }
    };
    let suite_result = match result_rx.await {
        Ok(Ok(result)) => result,
        Ok(Err(message)) => {
            let _ = suite_thread.join();
            return Err(Outcome::Error(message));
        }
        Err(_) => {
            let _ = suite_thread.join();
            return Err(Outcome::Error(
                "the kit suite thread ended without a result".to_owned(),
            ));
        }
    };
    if suite_thread.join().is_err() {
        return Err(Outcome::Error("the kit suite thread panicked".to_owned()));
    }
    drop(features_temp);

    if let Some(interrupt) = interrupt {
        interrupt.abort();
    }
    // Parse-level errors that `mck check` should already have caught; a kit error inside a
    // case's own fences still reaches the report as a kit-error record, as the legacy engine
    // does. The verdict comes from the report, not from this count.
    for message in &suite_result.error_messages {
        eprintln!("{message}");
    }

    let records = kit_run.report_records();
    let (header, capabilities, failure) = {
        let locked = kit_run.0.lock().unwrap_or_else(PoisonError::into_inner);
        (
            locked.state.header(),
            locked.state.caps.clone(),
            locked.state.failure(),
        )
    };
    drop(kit_run);

    // `report_of` reads only `driver_version`, `kit_version` and `started_at`; the filter and
    // clock are irrelevant here, so this `RunOptions` is built fresh from owned strings instead
    // of borrowing the caller's, which is not `Sync` (its clock is a bare `dyn Fn`) and so
    // cannot be held across this function's earlier await.
    let no_clock: &dyn Fn() -> f64 = &|| 0.0;
    let report = report_of(
        &RunState {
            caps: capabilities.clone(),
            dead: None,
        },
        &RunOptions {
            filter: None,
            driver_version: meta.driver_version,
            kit_version: meta.kit_version,
            started_at: meta.started_at,
            clock: no_clock,
        },
        records,
    );
    let run = Run {
        report,
        header,
        capabilities,
        failure,
    };

    let shutdown = match session {
        None => Ok(()),
        Some(session) => match Arc::try_unwrap(session) {
            Ok(mutex) => mutex
                .into_inner()
                .unwrap_or_else(PoisonError::into_inner)
                .close(),
            Err(_) => {
                return Err(Outcome::Error(
                    "internal error: the adapter session was still shared after the suite \
                     finished"
                        .to_owned(),
                ));
            }
        },
    };
    Ok((run, shutdown, spawn_error))
}
