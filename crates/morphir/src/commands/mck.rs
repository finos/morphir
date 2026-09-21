//! `morphir mck` — the Morphir Compatibility Kit command layer.
//!
//! This module owns argument shapes, terminal output and exit status only;
//! the kit grammar, loading, hashing, snapshots and status live in the
//! `morphir-mck` crate. The contract is `spec/mck/cli-contract.md`: stdout
//! carries the command's result, diagnostics go to stderr, 0 is success, 1 is
//! a failed check or an operational error, and 2 is a usage error.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use clap::Args;
use morphir_mck::ir::{RunOptions, RunVerdict, Testee, run_kit, verdict};
use morphir_mck::json::to_tab_json;
use morphir_mck::kit::embedded::{PROVENANCE, embedded_source};
use morphir_mck::kit::hash::ContentDigest;
use morphir_mck::kit::manifest::{CommitId, Lock, LockSource, UPSTREAM_REPOSITORY};
use morphir_mck::kit::snapshot::collect;
use morphir_mck::kit::status::{
    KitMode, KitStatus, MANIFEST_NAME, embedded_status, local_status, vendored_status,
};
use morphir_mck::kit::vendor::{
    Change, Managed, UpdateOutcome, VendorOutcome, VendorSource, check_updatable,
    default_update_source, describe, open_managed, update, vendor,
};
use morphir_mck::kit::{Kit, KitSource, load_kit};
use morphir_mck::provenance::{KitProvenance, KitSourceKind};
use morphir_mck::report::iso_timestamp;
use morphir_mck::transport::{Limits, Session};
use serde_json::json;
use starbase::AppResult;

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

pub fn run_mck_check(args: MckCheckArgs) -> AppResult<miette::Report> {
    let outcome = match load_directory(&args.dir, args.repo_root.as_deref()) {
        Err(message) => Outcome::Error(message),
        Ok(loaded) => {
            let kit = loaded.kit();
            if args.json {
                let errors: Vec<_> = kit
                    .errors
                    .iter()
                    .map(|e| json!({ "file": e.file, "line": e.line, "message": e.message }))
                    .collect();
                let cases: Vec<_> = kit.cases.iter().map(|c| c.id.as_str()).collect();
                println!(
                    "{}",
                    to_tab_json(&json!({ "files": kit.files, "cases": cases, "errors": errors }))
                );
            } else {
                for error in &kit.errors {
                    eprintln!("{}:{}: {}", error.file, error.line, error.message);
                }
                println!(
                    "{} case(s) in {} file(s), {} error(s)",
                    kit.cases.len(),
                    kit.files.len(),
                    kit.errors.len()
                );
            }
            if kit.errors.is_empty() {
                Outcome::Passed
            } else {
                Outcome::Failed
            }
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

#[derive(Args, Clone, Debug)]
pub struct MckRunArgs {
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
    let clock = move || origin.elapsed().as_secs_f64() * 1000.0;
    let options = RunOptions {
        filter: filter.as_ref(),
        driver_version: env!("CARGO_PKG_VERSION").to_owned(),
        kit_version,
        started_at,
        clock: &clock,
    };

    let (run, shutdown, spawn_error) =
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
