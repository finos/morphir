//! `morphir mck` — the Morphir Compatibility Kit command layer.
//!
//! This module owns argument shapes, terminal output and exit status only;
//! the kit grammar, loading, hashing, snapshots and status live in the
//! `morphir-mck` crate. The contract is `spec/mck/cli-contract.md`: stdout
//! carries the command's result, diagnostics go to stderr, 0 is success, 1 is
//! a failed check or an operational error, and 2 is a usage error.

use std::path::{Path, PathBuf};

use clap::Args;
use morphir_mck::json::to_tab_json;
use morphir_mck::kit::hash::ContentDigest;
use morphir_mck::kit::manifest::{CommitId, Lock, UPSTREAM_REPOSITORY};
use morphir_mck::kit::status::{
    KitMode, KitStatus, MANIFEST_NAME, embedded_status, local_status, vendored_status,
};
use morphir_mck::kit::vendor::{
    Change, Managed, UpdateOutcome, VendorOutcome, VendorSource, default_update_source, describe,
    open_managed, read_lock, update, vendor,
};
use morphir_mck::kit::{Kit, KitSource, load_kit};
use serde_json::json;
use starbase::AppResult;

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

    /// The full 40-character commit to acquire; required with
    /// `github:finos/morphir` and refused with any other source
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
    let parsed = match &args.source {
        Some(source) => parse_source(
            source,
            args.revision.as_deref(),
            args.expect_digest.as_deref(),
        ),
        None if args.revision.is_some() => Err(format!(
            "--revision needs --source github:{UPSTREAM_REPOSITORY}"
        )),
        None => match args
            .expect_digest
            .as_deref()
            .map(ContentDigest::parse)
            .transpose()
        {
            Err(why) => Err(format!("--expect-digest: {why}")),
            Ok(expected) => {
                match read_lock(&args.kit).and_then(|lock| default_update_source(&lock)) {
                    Ok(source) => Ok((Requested::Ready(source), expected)),
                    Err(error) => return finish(Outcome::Error(error.to_string())),
                }
            }
        },
    };
    let (requested, expected) = match parsed {
        Ok(parsed) => parsed,
        Err(message) => return finish(Outcome::Usage(message)),
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
