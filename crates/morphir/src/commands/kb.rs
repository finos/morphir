//! `morphir kb` — knowledge base management over OKF bundles.
//!
//! Ported from the morphir-scala `kb` CLI (`.claude/skills/kb/kb.scala`),
//! matching its command surface so playbooks carry over. Faults in that
//! reference are fixed here rather than reproduced for the sake of parity.
//! All the actual behaviour lives in the `morphir-kb` and `morphir-okf`
//! crates; this module owns argument parsing, kb-root resolution, the clock,
//! and the `error: <msg>` / exit-1 convention the Scala CLI follows.
//!
//! Two conventions, ported verbatim:
//!
//!   - every operational failure prints `error: <msg>` to stderr and exits 1 —
//!     never a stack trace, never a fancy report;
//!   - the command payload (text or JSON) goes to stdout, so it can be piped.

use std::path::{Path, PathBuf};

use chrono::{Local, NaiveDate, Utc};
use starbase::AppResult;

use morphir_kb::error::{Error, Result as KbResult};
use morphir_kb::scaffold::ScaffoldResult;
use morphir_kb::sync::SyncBundle;
use morphir_kb::{check, decision, index, intent, refresh, render, scaffold, sync};
use morphir_okf::model::{Bundle, Kb, Severity};
use morphir_okf::{paths, store};

// ------------------------------------------------------------------ options

/// The `--kb`/`--json` pair every kb command takes, mirroring the Scala
/// `CommonOpts`.
#[derive(Clone, Debug, clap::Args)]
pub struct KbCommonArgs {
    /// Path to the knowledge base root (the directory holding bundles/). Auto-detected when omitted.
    #[arg(long, value_name = "PATH")]
    pub kb: Option<String>,
    /// Emit JSON instead of text, for chaining and for agent consumption
    #[arg(long)]
    pub json: bool,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbListArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Show concepts within this bundle (name or group/name)
    #[arg(long)]
    pub bundle: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbShowArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Concept path — bundle-relative (/x.md) or a path suffix
    #[arg(long)]
    pub path: String,
    /// Bundle to resolve a bundle-relative path against
    #[arg(long)]
    pub bundle: Option<String>,
    /// Also include the document body
    #[arg(long)]
    pub body: bool,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbSearchArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Text to look for in titles, descriptions, tags and paths
    #[arg(long)]
    pub query: Option<String>,
    /// Also search document bodies
    #[arg(long)]
    pub body: bool,
    /// Filter by frontmatter type
    #[arg(long = "type")]
    pub type_filter: Option<String>,
    /// Filter by tag (repeatable)
    #[arg(long = "tag")]
    pub tag: Vec<String>,
    /// Filter by status
    #[arg(long)]
    pub status: Option<String>,
    /// Restrict to one bundle
    #[arg(long)]
    pub bundle: Option<String>,
    /// Use the SQLite index for full-text search — faster, and ranks by relevance
    #[arg(long)]
    pub index: bool,
    /// Row limit when using --index
    #[arg(long, default_value_t = 20)]
    pub limit: usize,
    /// Index database path (default: .dev/kb/index.db under the repository root)
    #[arg(long)]
    pub db: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbCheckArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Reference checkout root for provenance checks (default: .refs under the repository root)
    #[arg(long)]
    pub refs: Option<String>,
    /// Skip provenance checks against .refs/
    #[arg(long)]
    pub no_provenance: bool,
    /// Include info-level findings
    #[arg(long)]
    pub verbose: bool,
    /// Exit non-zero when warnings are present, not just errors
    #[arg(long)]
    pub strict: bool,
    /// Report dangling links as warnings — OKF's stance that they mark not-yet-written knowledge
    #[arg(long)]
    pub allow_dangling: bool,
    /// Write the report here instead of stdout (convention: under .dev/)
    #[arg(long)]
    pub out: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbIndexArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Database path (default: .dev/kb/index.db under the repository root)
    #[arg(long)]
    pub db: Option<String>,
    /// Report the index's freshness instead of rebuilding it
    #[arg(long)]
    pub status: bool,
}

/// `kb refresh` — everything. The `--no-*` flags narrow it; the
/// `refresh markdown` and `refresh db` subcommands do the same thing more
/// legibly.
#[derive(Clone, Debug, clap::Args)]
pub struct KbRefreshArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Report what would change without writing anything
    #[arg(long)]
    pub dry_run: bool,
    /// Rebuild the SQLite index even when it is already up to date
    #[arg(long)]
    pub force: bool,
    /// Append index entries for concepts no index links to
    #[arg(long)]
    pub add_missing: bool,
    /// Index section to append missing entries under
    #[arg(long, default_value = "Orientation")]
    pub section: String,
    /// Skip the markdown indexes — same as `kb refresh db`
    #[arg(long)]
    pub no_markdown: bool,
    /// Skip the SQLite index — same as `kb refresh markdown`
    #[arg(long)]
    pub no_db: bool,
    /// Database path (default: .dev/kb/index.db under the repository root)
    #[arg(long)]
    pub db: Option<String>,
}

/// `kb refresh markdown` — index bullets only.
#[derive(Clone, Debug, clap::Args)]
pub struct KbRefreshMarkdownArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Report what would change without writing anything
    #[arg(long)]
    pub dry_run: bool,
    /// Append index entries for concepts no index links to
    #[arg(long)]
    pub add_missing: bool,
    /// Index section to append missing entries under
    #[arg(long, default_value = "Orientation")]
    pub section: String,
}

/// `kb refresh db` — the SQLite index only.
#[derive(Clone, Debug, clap::Args)]
pub struct KbRefreshDbArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Report what would change without writing anything
    #[arg(long)]
    pub dry_run: bool,
    /// Rebuild even when the index is already up to date
    #[arg(long)]
    pub force: bool,
    /// Database path (default: .dev/kb/index.db under the repository root)
    #[arg(long)]
    pub db: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbQueryArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// SQL to run. Read-only: SELECT, WITH, PRAGMA or EXPLAIN
    #[arg(long)]
    pub sql: String,
    /// Database path (default: .dev/kb/index.db under the repository root)
    #[arg(long)]
    pub db: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbNewBundleArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Bundle slug, e.g. morphir-ir-v5
    #[arg(long)]
    pub name: String,
    /// Grouping directory under bundles/, e.g. morphir
    #[arg(long)]
    pub group: Option<String>,
    /// Bundle title
    #[arg(long)]
    pub title: String,
    /// One-sentence bundle description
    #[arg(long)]
    pub description: String,
    /// OKF version to declare
    #[arg(long, default_value = "0.2")]
    pub okf_version: String,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbAddConceptArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Target bundle (name or group/name)
    #[arg(long)]
    pub bundle: String,
    /// Path within the bundle, e.g. naming.md or design/naming.md
    #[arg(long)]
    pub path: String,
    /// OKF type — the one required frontmatter field
    #[arg(long = "type")]
    pub concept_type: String,
    /// Concept title
    #[arg(long)]
    pub title: String,
    /// One-sentence description
    #[arg(long)]
    pub description: String,
    /// Tag (repeatable)
    #[arg(long = "tag")]
    pub tag: Vec<String>,
    /// Lifecycle status: draft, stable or deprecated
    #[arg(long)]
    pub status: Option<String>,
    /// Source URL (repeatable); use id=URL or id=URL=Title to name it
    #[arg(long = "source")]
    pub source: Vec<String>,
    /// Index section heading to file the entry under
    #[arg(long, default_value = "Orientation")]
    pub section: String,
    /// Actor for the generated.by frontmatter, e.g. process:kb-seed
    #[arg(long)]
    pub generated_by: Option<String>,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

// -------------------------------------------------------------- sync options

/// The flags every `kb sync` subcommand shares, mirroring `SyncCommonOpts`.
#[derive(Clone, Debug, clap::Args)]
pub struct KbSyncCommonArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Bundle to sync (defaults to the one whose index declares `sync: true`)
    #[arg(long)]
    pub bundle: Option<String>,
    /// Reference checkouts root (default: .refs under the repository root)
    #[arg(long)]
    pub refs: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbSyncStatusArgs {
    #[command(flatten)]
    pub sync: KbSyncCommonArgs,
    /// Do not consult the upstream checkout — compare the mirror against the lockfile only
    #[arg(long)]
    pub no_upstream: bool,
    /// List clean files too
    #[arg(long)]
    pub verbose: bool,
    /// Exit non-zero when anything has diverged
    #[arg(long)]
    pub strict: bool,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbSyncPullArgs {
    #[command(flatten)]
    pub sync: KbSyncCommonArgs,
    /// Report what would change without writing anything
    #[arg(long)]
    pub dry_run: bool,
    /// Take upstream's version of files that changed on both sides
    #[arg(long)]
    pub theirs: bool,
    /// Delete mirrored files that upstream has removed
    #[arg(long)]
    pub prune: bool,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbSyncPushArgs {
    #[command(flatten)]
    pub sync: KbSyncCommonArgs,
    /// Checkout to write the upstream form into (default: the reference checkout)
    #[arg(long)]
    pub to: Option<String>,
    /// Report what would be written without writing anything
    #[arg(long)]
    pub dry_run: bool,
    /// Also export files that changed upstream since the last import
    #[arg(long)]
    pub include_diverged: bool,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbSyncDiffArgs {
    #[command(flatten)]
    pub sync: KbSyncCommonArgs,
    /// Mirrored paths or globs, e.g. docs/spec/draft/types.md or 'docs/**'. Quote
    /// a glob: an unquoted one is expanded by the shell against the working
    /// directory before this ever sees it. No argument diffs every mirrored file;
    /// `-` reads the remaining patterns from stdin, one per line
    #[arg(value_name = "PATH")]
    pub path: Vec<String>,
    /// Mirrored path, e.g. docs/spec/draft/types.md
    #[arg(
        long = "path",
        value_name = "PATH",
        hide = true,
        conflicts_with = "path"
    )]
    pub path_flag: Option<String>,
    /// Print the patch alone — `git apply` takes it in the upstream checkout
    #[arg(long, conflicts_with = "json")]
    pub raw: bool,
    /// Split the patterns read from stdin on NUL rather than newline, pairing
    /// with `find -print0`. Only meaningful alongside `-`
    #[arg(short = 'z', long = "null")]
    pub null: bool,
}

// ------------------------------------------------------------ intent options

#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentInitArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Bundle name under bundles/
    #[arg(long, default_value = "intent")]
    pub name: String,
    /// Package URL identifying the system, e.g. pkg:maven/org.finos.morphir/morphir-core
    #[arg(long)]
    pub system: Option<String>,
    /// Bundle label holding capabilities, e.g. morphir/morphir-scala
    #[arg(long)]
    pub capability_bundle: Option<String>,
    /// Days before an active intent is reported stale
    #[arg(long, default_value_t = 60)]
    pub stale_after_days: i64,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentNewArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// What the work is
    #[arg(long)]
    pub title: String,
    /// One sentence — also the index entry
    #[arg(long)]
    pub description: String,
    /// feature, bug, performance, security, deprecation, removal, refactor, docs, test, build, spike
    #[arg(long)]
    pub kind: String,
    /// Marks a compatibility break — orthogonal to kind
    #[arg(long)]
    pub breaking: bool,
    /// GitHub issue number this came from
    #[arg(long)]
    pub issue: Option<String>,
    /// Tag (repeatable)
    #[arg(long = "tag")]
    pub tag: Vec<String>,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentListArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Filter by state
    #[arg(long)]
    pub state: Option<String>,
    /// Filter by kind
    #[arg(long)]
    pub kind: Option<String>,
    /// Only breaking intent
    #[arg(long)]
    pub breaking: bool,
    /// Only open intent — excludes Released, Cancelled, Superseded
    #[arg(long)]
    pub open: bool,
    /// Only user-visible kinds, as release notes would show
    #[arg(long)]
    pub user_visible: bool,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentShowArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Intent id or slug, e.g. 0007
    #[arg(value_name = "ID")]
    pub id: Option<String>,
    /// Intent id or slug, e.g. 0007
    #[arg(long = "id", value_name = "ID", hide = true, conflicts_with = "id")]
    pub id_flag: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentCheckArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Exit non-zero on warnings too
    #[arg(long)]
    pub strict: bool,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

/// Obligation-free transitions: refine, start, and the generic escape hatch.
/// One struct for all three, as in the Scala `IntentMoveOpts`.
#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentMoveArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Intent id or slug
    #[arg(value_name = "ID")]
    pub id: Option<String>,
    /// Intent id or slug
    #[arg(long = "id", value_name = "ID", hide = true, conflicts_with = "id")]
    pub id_flag: Option<String>,
    /// Target state (move only)
    #[arg(long)]
    pub state: Option<String>,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentReleaseArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Intent id or slug
    #[arg(value_name = "ID")]
    pub id: Option<String>,
    /// Intent id or slug
    #[arg(long = "id", value_name = "ID", hide = true, conflicts_with = "id")]
    pub id_flag: Option<String>,
    /// Capability this produced, as bundle-label:/path.md
    #[arg(long)]
    pub capability: Option<String>,
    /// Package URL of a shipped artifact (repeatable)
    #[arg(long = "artifact")]
    pub artifact: Vec<String>,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentCancelArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Intent id or slug
    #[arg(value_name = "ID")]
    pub id: Option<String>,
    /// Intent id or slug
    #[arg(long = "id", value_name = "ID", hide = true, conflicts_with = "id")]
    pub id_flag: Option<String>,
    /// Why the work is not being done
    #[arg(long)]
    pub reason: Option<String>,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbIntentSupersedeArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Intent id or slug
    #[arg(value_name = "ID")]
    pub id: Option<String>,
    /// Intent id or slug
    #[arg(long = "id", value_name = "ID", hide = true, conflicts_with = "id")]
    pub id_flag: Option<String>,
    /// Intent id that replaces it
    #[arg(long)]
    pub by: Option<String>,
    /// Override today's date (YYYY-MM-DD)
    #[arg(long)]
    pub date: Option<String>,
}

// ---------------------------------------------------------- decision options

#[derive(Clone, Debug, clap::Args)]
pub struct KbDecisionListArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Filter by state
    #[arg(long)]
    pub state: Option<String>,
    /// Only decisions that still govern — excludes Superseded and Withdrawn
    #[arg(long)]
    pub in_force: bool,
    /// Restrict to one bundle
    #[arg(long)]
    pub bundle: Option<String>,
}

#[derive(Clone, Debug, clap::Args)]
pub struct KbDecisionShowArgs {
    #[command(flatten)]
    pub common: KbCommonArgs,
    /// Decision id or slug, e.g. 0004
    #[arg(value_name = "ID")]
    pub id: Option<String>,
    /// Decision id or slug, e.g. 0004
    #[arg(long = "id", value_name = "ID", hide = true, conflicts_with = "id")]
    pub id_flag: Option<String>,
    /// Bundle to look in — required when an id means a record in more than one
    #[arg(long)]
    pub bundle: Option<String>,
    /// Also include the document body
    #[arg(long)]
    pub body: bool,
}

// ------------------------------------------------------------------- shared

/// Maps the kb error convention onto the CLI's handler convention: payload was
/// already printed, so success is `Ok(None)`, a nonzero exit is `Ok(Some(code))`,
/// and an operational failure prints `error: <msg>` and exits 1.
fn finish(result: KbResult<u8>) -> AppResult<miette::Report> {
    match result {
        Ok(0) => Ok(None),
        Ok(code) => Ok(Some(code)),
        Err(e) => {
            eprintln!("error: {e}");
            Ok(Some(1))
        }
    }
}

fn cwd() -> PathBuf {
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

/// Resolves a user-supplied path: absolute as given, relative against the
/// working directory (the Scala `KbCli.at`).
fn at(p: &str) -> PathBuf {
    let pb = PathBuf::from(p);
    if pb.is_absolute() { pb } else { cwd().join(pb) }
}

/// Walks up from the working directory looking for a directory holding
/// `kb/bundles`; the resolved root is `<that>/kb`.
fn resolve_kb(explicit: Option<&str>) -> KbResult<PathBuf> {
    if let Some(p) = explicit {
        return Ok(at(p));
    }
    let mut dir = cwd();
    loop {
        if dir.join("kb").join("bundles").is_dir() {
            return Ok(dir.join("kb"));
        }
        if !dir.pop() {
            return Err(Error::msg("could not locate a kb/ directory — pass --kb"));
        }
    }
}

/// The index is derived state, so it lives under `.dev/` with the rest of the
/// tooling output: `<repo>/.dev/kb/index.db` beside the kb root.
fn default_db(kb_root: &Path) -> PathBuf {
    match kb_root.parent() {
        Some(p) => p.join(".dev").join("kb").join("index.db"),
        None => PathBuf::from(".dev/kb/index.db"),
    }
}

fn db_path(explicit: Option<&str>, kb_root: &Path) -> PathBuf {
    explicit.map(at).unwrap_or_else(|| default_db(kb_root))
}

/// `.refs/` sits beside `kb/`, the convention `kb check` follows for provenance.
fn refs_root(explicit: Option<&str>, kb_root: &Path) -> PathBuf {
    explicit
        .map(at)
        .unwrap_or_else(|| check::default_refs_root(kb_root))
}

/// The library takes `today` as a parameter; the CLI reads the clock, and
/// every `--date` flag overrides it.
fn today(explicit: Option<&str>) -> KbResult<NaiveDate> {
    match explicit {
        None => Ok(Local::now().date_naive()),
        Some(s) => NaiveDate::parse_from_str(s.trim(), "%Y-%m-%d")
            .map_err(|_| Error::msg(format!("invalid date `{s}` — expected YYYY-MM-DD"))),
    }
}

fn require_bundle<'a>(kb: &'a Kb, label: &str) -> KbResult<&'a Bundle> {
    kb.bundle(label).ok_or_else(|| {
        Error::msg(format!(
            "no bundle `{label}`; known: {}",
            kb.bundles
                .iter()
                .map(|b| b.label())
                .collect::<Vec<_>>()
                .join(", ")
        ))
    })
}

/// Record ids read better as positionals (`kb intent start 0007`); the flag
/// form stays accepted for compatibility.
fn record_id(flag: Option<&str>, positional: Option<&str>) -> Option<String> {
    flag.or(positional)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// The patterns `-` stands for: everything on stdin, split on newlines or, under
/// `-z`, on NUL. Read whole rather than line-by-line because the delimiter is a
/// parameter and `BufRead::lines` only knows one of them.
fn stdin_patterns(nul_delimited: bool) -> KbResult<Vec<String>> {
    use std::io::Read;
    let mut buf = String::new();
    std::io::stdin()
        .read_to_string(&mut buf)
        .map_err(|e| Error::msg(format!("could not read patterns from stdin: {e}")))?;
    let separator = if nul_delimited { '\0' } else { '\n' };
    Ok(buf
        .split(separator)
        // A newline-delimited list written on Windows carries the carriage
        // return with it; a NUL-delimited one from `find -print0` does not, and
        // there a trailing `\r` would be part of the filename.
        .map(|s| {
            if nul_delimited {
                s.to_string()
            } else {
                s.trim_end_matches('\r').to_string()
            }
        })
        .collect())
}

/// The pattern list `sync diff` actually acts on: the arguments as given, with
/// `-` replaced by what stdin holds.
///
/// `-` may sit anywhere among literal patterns and the result is their union;
/// stdin can only be drained once, so a second `-` contributes nothing and is
/// dropped rather than refused. Empty elements go last of all: a trailing
/// delimiter yields one, the crate's containment check refuses an empty path,
/// and an empty element carries no intent worth refusing over.
fn diff_selection(args: &KbSyncDiffArgs) -> KbResult<Vec<String>> {
    // Trimmed, as `record_id` trimmed the single path this replaced: an argument
    // carrying surrounding whitespace came from a quoting slip, never from a
    // filename. What stdin brings is left exactly as it arrived — there the
    // whitespace may be the name.
    let given: Vec<String> = match args.path_flag.as_deref() {
        Some(p) => vec![p.trim().to_string()],
        None => args.path.iter().map(|p| p.trim().to_string()).collect(),
    };
    let from_stdin = given.iter().any(|p| p == "-");
    if args.null && !from_stdin {
        return Err(Error::msg(
            "-z/--null says how to split what stdin holds, and nothing is being read from stdin — \
             pass `-` as a path to read patterns from stdin, or drop -z",
        ));
    }
    let mut out: Vec<String> = Vec::with_capacity(given.len());
    let mut drained = false;
    for pattern in given {
        if pattern == "-" {
            if !drained {
                drained = true;
                out.extend(stdin_patterns(args.null)?);
            }
        } else {
            out.push(pattern);
        }
    }
    out.retain(|p| !p.is_empty());
    Ok(out)
}

fn json_str(s: &str) -> String {
    serde_json::to_string(s).expect("a string always serializes")
}

fn count(findings: &[morphir_okf::model::Finding], severity: Severity) -> usize {
    findings.iter().filter(|f| f.severity == severity).count()
}

/// Loads the kb and locates the intent bundle, failing with guidance when
/// there is none.
fn with_intent<T>(
    kb_opt: Option<&str>,
    f: impl FnOnce(&Kb, &Bundle) -> KbResult<T>,
) -> KbResult<T> {
    let root = resolve_kb(kb_opt)?;
    let kb = store::load(&root)?;
    let b = intent::find_bundle(&kb).ok_or_else(|| {
        Error::msg(
            "no intent bundle — no bundle index declares `intent: true`. Run `kb intent init` to scaffold one.",
        )
    })?;
    f(&kb, b)
}

/// Loads the kb and the sync bundle's manifest and lockfile, failing with
/// guidance when either is missing.
fn with_sync<T>(
    kb_opt: Option<&str>,
    bundle: Option<&str>,
    f: impl FnOnce(&Path, &Kb, &SyncBundle) -> KbResult<T>,
) -> KbResult<T> {
    let root = resolve_kb(kb_opt)?;
    let kb = store::load(&root)?;
    let b = sync::find_bundle(&kb, bundle).ok_or_else(|| {
        Error::msg("no sync bundle — no bundle index declares `sync: true`. Pass --bundle, or add a sync.yaml.")
    })?;
    let sb = sync::load(b)?;
    f(&root, &kb, &sb)
}

/// The upstream checkout a sync bundle reads from, failing with guidance when
/// it is absent.
fn require_upstream(refs: &Path, sb: &SyncBundle) -> KbResult<PathBuf> {
    sync::upstream_root(refs, sb).ok_or_else(|| {
        Error::msg(format!(
            "no reference checkout for {} under {} — add one with `/squire reference repo add https://github.com/{}`",
            sb.manifest.repo,
            paths::render(refs),
            sb.manifest.repo
        ))
    })
}

// ----------------------------------------------------------------- commands

pub fn run_kb_list(args: KbListArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let kb = store::load(&root)?;
        let text = match &args.bundle {
            None => render::list_bundles(&kb, args.common.json),
            Some(b) => render::list_concepts(&kb, require_bundle(&kb, b)?, args.common.json),
        };
        print!("{text}");
        Ok(0)
    })())
}

pub fn run_kb_show(args: KbShowArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let kb = store::load(&root)?;
        print!(
            "{}",
            render::show(
                &kb,
                &args.path,
                args.bundle.as_deref(),
                args.body,
                args.common.json,
            )
        );
        Ok(0)
    })())
}

pub fn run_kb_search(args: KbSearchArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        if args.index {
            let Some(q) = args.query.as_deref() else {
                return Err(Error::msg("--index needs --query"));
            };
            // The facets the scanning branch below already applies. Passing them
            // here too is the whole point of the pair: `--index --bundle x` used
            // to return every bundle, which is a wrong answer rather than a slow
            // one.
            let filters = index::SearchFilters {
                doc_type: args.type_filter.as_deref(),
                tags: &args.tag,
                status: args.status.as_deref(),
                bundle: args.bundle.as_deref(),
            };
            let rows = index::search(&db_path(args.db.as_deref(), &root), q, args.limit, &filters)?;
            print!("{}", index::render_rows(&rows, args.common.json));
        } else {
            let kb = store::load(&root)?;
            print!(
                "{}",
                render::search(
                    &kb,
                    args.query.as_deref(),
                    args.body,
                    args.type_filter.as_deref(),
                    &args.tag,
                    args.status.as_deref(),
                    args.bundle.as_deref(),
                    args.common.json,
                )
            );
        }
        Ok(0)
    })())
}

pub fn run_kb_check(args: KbCheckArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let kb = store::load(&root)?;
        let opts = check::CheckOpts {
            refs: args.refs.as_deref().map(at),
            no_provenance: args.no_provenance,
            verbose: args.verbose,
            strict: args.strict,
            allow_dangling: args.allow_dangling,
            out: args.out.as_deref().map(at),
        };
        let report = check::run_full(&kb, &opts, today(None)?)?;
        let text = if args.common.json {
            check::render_json(&report.findings)
        } else {
            check::render_text(&report.findings, args.verbose)
        };
        match &opts.out {
            None => print!("{text}"),
            Some(out) => println!("{}", check::write_report(&text, out)?),
        }
        Ok(if report.should_fail(args.strict) {
            1
        } else {
            0
        })
    })())
}

pub fn run_kb_index(args: KbIndexArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let kb = store::load(&root)?;
        let db = db_path(args.db.as_deref(), &root);
        if args.status {
            let st = index::status(&db, &kb)?;
            print!("{}", index::render_status(&st, &db, args.common.json));
        } else {
            let stats = index::build(&kb, &db, Utc::now())?;
            print!("{}", index::render_stats(&stats, &db, args.common.json));
        }
        Ok(0)
    })())
}

/// The one refresh implementation. `kb refresh`, `kb refresh markdown` and
/// `kb refresh db` differ only in which halves they enable, so they all land
/// here — mirroring the Scala `KbCli.runRefresh` (the reload between the
/// markdown and DB passes happens inside `refresh::refresh`).
#[allow(clippy::too_many_arguments)]
fn run_refresh(
    kb_opt: Option<&str>,
    json: bool,
    markdown: bool,
    database: bool,
    dry_run: bool,
    force: bool,
    add_missing: bool,
    section: &str,
    db_opt: Option<&str>,
) -> KbResult<u8> {
    let root = resolve_kb(kb_opt)?;
    let db = db_path(db_opt, &root);
    let actions = refresh::refresh(
        &root,
        markdown,
        database,
        dry_run,
        force,
        add_missing,
        section,
        &db,
        today(None)?,
        Utc::now(),
    )?;
    print!("{}", refresh::render(&actions, dry_run, json));
    Ok(0)
}

pub fn run_kb_refresh(args: KbRefreshArgs) -> AppResult<miette::Report> {
    finish(run_refresh(
        args.common.kb.as_deref(),
        args.common.json,
        !args.no_markdown,
        !args.no_db,
        args.dry_run,
        args.force,
        args.add_missing,
        &args.section,
        args.db.as_deref(),
    ))
}

pub fn run_kb_refresh_markdown(args: KbRefreshMarkdownArgs) -> AppResult<miette::Report> {
    finish(run_refresh(
        args.common.kb.as_deref(),
        args.common.json,
        true,
        false,
        args.dry_run,
        false,
        args.add_missing,
        &args.section,
        None,
    ))
}

pub fn run_kb_refresh_db(args: KbRefreshDbArgs) -> AppResult<miette::Report> {
    finish(run_refresh(
        args.common.kb.as_deref(),
        args.common.json,
        false,
        true,
        args.dry_run,
        args.force,
        false,
        "Orientation",
        args.db.as_deref(),
    ))
}

pub fn run_kb_query(args: KbQueryArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let rows = index::query(&db_path(args.db.as_deref(), &root), &args.sql)?;
        print!("{}", index::render_rows(&rows, args.common.json));
        Ok(0)
    })())
}

pub fn run_kb_new_bundle(args: KbNewBundleArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let r = scaffold::new_bundle(
            &root,
            &args.name,
            args.group.as_deref(),
            &args.title,
            &args.description,
            &args.okf_version,
            today(args.date.as_deref())?,
        )?;
        print!("{}", render::scaffold(&r, args.common.json));
        Ok(0)
    })())
}

pub fn run_kb_add_concept(args: KbAddConceptArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let kb = store::load(&root)?;
        let bundle = require_bundle(&kb, &args.bundle)?;
        let sources: Vec<_> = args
            .source
            .iter()
            .map(|s| scaffold::parse_source(s))
            .collect();
        let r = scaffold::add_concept(
            bundle,
            &args.path,
            &args.concept_type,
            &args.title,
            &args.description,
            &args.tag,
            args.status.as_deref(),
            &sources,
            &args.section,
            args.generated_by.as_deref(),
            today(args.date.as_deref())?,
        )?;
        print!("{}", render::scaffold(&r, args.common.json));
        Ok(0)
    })())
}

// --------------------------------------------------------------------- sync

pub fn run_kb_sync_status(args: KbSyncStatusArgs) -> AppResult<miette::Report> {
    finish(with_sync(
        args.sync.common.kb.as_deref(),
        args.sync.bundle.as_deref(),
        |root, _kb, sb| {
            let refs = refs_root(args.sync.refs.as_deref(), root);
            let up = if args.no_upstream {
                None
            } else {
                sync::upstream_root(&refs, sb)
            };
            let rows = sync::status(sb, up.as_deref())?;
            print!(
                "{}",
                sync::render_status(&rows, args.sync.common.json, args.verbose)
            );
            Ok(if args.strict && sync::strict_violations(&rows) > 0 {
                1
            } else {
                0
            })
        },
    ))
}

pub fn run_kb_sync_pull(args: KbSyncPullArgs) -> AppResult<miette::Report> {
    finish(with_sync(
        args.sync.common.kb.as_deref(),
        args.sync.bundle.as_deref(),
        |root, _kb, sb| {
            let refs = refs_root(args.sync.refs.as_deref(), root);
            let day = today(args.date.as_deref())?;
            let up = require_upstream(&refs, sb)?;
            let head = sync::git_head(&up).unwrap_or_else(|| sb.lock.base_commit.clone());
            let result = sync::pull(sb, &up, &head, day, args.dry_run, args.theirs, args.prune)?;
            if !args.dry_run {
                let written = sync::write_lock(sb, &result.lock)?;
                // Reload before generating the index: the bullets have to carry
                // the descriptions of the concepts that were just written, and
                // the in-memory bundle predates them.
                let reloaded = store::load(root)?;
                if let Some(b) = sync::find_bundle(&reloaded, args.sync.bundle.as_deref()) {
                    let regen = SyncBundle {
                        bundle: b.clone(),
                        manifest: sb.manifest.clone(),
                        lock: sb.lock.clone(),
                    };
                    sync::generate_index(&regen, &written, day)?;
                }
            }
            print!(
                "{}",
                sync::render_actions(
                    &result.actions,
                    &result.refused,
                    args.dry_run,
                    args.sync.common.json,
                )
            );
            // Non-zero when anything was held back, matching `sync push`: a
            // caller that only checks the exit code must not report a clean
            // import over files that were never imported.
            Ok(if result.refused.is_empty() { 0 } else { 1 })
        },
    ))
}

pub fn run_kb_sync_push(args: KbSyncPushArgs) -> AppResult<miette::Report> {
    finish(with_sync(
        args.sync.common.kb.as_deref(),
        args.sync.bundle.as_deref(),
        |root, _kb, sb| {
            let refs = refs_root(args.sync.refs.as_deref(), root);
            let target = match args.to.as_deref() {
                Some(p) => at(p),
                None => require_upstream(&refs, sb)?,
            };
            // Consult the checkout even when exporting elsewhere: it is the
            // only way to know whether a change here would be overwriting a
            // change there.
            let up = sync::upstream_root(&refs, sb);
            let out = sync::push(
                sb,
                &target,
                up.as_deref(),
                args.dry_run,
                args.include_diverged,
            )?;
            print!(
                "{}",
                sync::render_actions(
                    &out.actions,
                    &out.refused,
                    args.dry_run,
                    args.sync.common.json,
                )
            );
            Ok(if out.refused.is_empty() { 0 } else { 1 })
        },
    ))
}

pub fn run_kb_sync_diff(args: KbSyncDiffArgs) -> AppResult<miette::Report> {
    finish((|| {
        // Resolved before the knowledge base is loaded so that a bad flag pairing
        // is reported as such, rather than behind "no sync bundle".
        let select = diff_selection(&args)?;
        with_sync(
            args.sync.common.kb.as_deref(),
            args.sync.bundle.as_deref(),
            |root, _kb, sb| {
                let refs = refs_root(args.sync.refs.as_deref(), root);
                let up = require_upstream(&refs, sb)?;
                // The crate decides single from many by the shape of `select`, and
                // one literal path is still the single-file case it has always
                // been — down to the bytes it prints. Routing everything through
                // the multi-file path would quietly reframe that output.
                let sel = sync::diff_selected(sb, &up, &select)?;
                let text = if args.raw {
                    sync::render_diffs_raw(&sel)
                } else if args.sync.common.json {
                    sync::render_diffs_json(&sel)
                } else {
                    sync::render_diffs_text(&sel)
                };
                print!("{text}");
                Ok(0)
            },
        )
    })())
}

// ------------------------------------------------------------------- intent

pub fn run_kb_intent_init(args: KbIntentInitArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let files = intent::init_bundle(
            &root,
            &args.name,
            args.system.as_deref(),
            args.capability_bundle.as_deref(),
            args.stale_after_days,
            today(args.date.as_deref())?,
        )?;
        let r = ScaffoldResult {
            created: files,
            updated: Vec::new(),
            notes: vec![format!(
                "add the bundle to the Bundles table in {}",
                paths::render(&root.join("README.md"))
            )],
        };
        print!("{}", render::scaffold(&r, args.common.json));
        Ok(0)
    })())
}

pub fn run_kb_intent_new(args: KbIntentNewArgs) -> AppResult<miette::Report> {
    finish(with_intent(args.common.kb.as_deref(), |kb, b| {
        let kind = intent::IntentKind::parse(&args.kind).ok_or_else(|| {
            Error::msg(format!(
                "unknown kind `{}` — one of {}",
                args.kind,
                intent::IntentKind::names()
            ))
        })?;
        let file = intent::create(
            b,
            &args.title,
            &args.description,
            kind,
            args.breaking,
            args.issue.as_deref(),
            &args.tag,
            today(args.date.as_deref())?,
        )?;
        if args.common.json {
            print!("{{\n  \"file\": {}\n}}\n", json_str(&paths::render(&file)));
        } else {
            println!("created {}", kb.rel(&file));
            println!("  write the Problem section, then `kb refresh`");
        }
        Ok(0)
    }))
}

pub fn run_kb_intent_list(args: KbIntentListArgs) -> AppResult<miette::Report> {
    finish(with_intent(args.common.kb.as_deref(), |_kb, b| {
        // An unparseable --state or --kind filters nothing, as in the Scala
        // CLI (`wanted.forall`).
        let wanted = args.state.as_deref().and_then(intent::IntentState::parse);
        let wanted_kind = args.kind.as_deref().and_then(intent::IntentKind::parse);
        let items: Vec<intent::Intent<'_>> = intent::intents(b)
            .into_iter()
            .filter(|i| {
                wanted.is_none_or(|s| i.state() == Some(s))
                    && wanted_kind.is_none_or(|k| i.kind() == Some(k))
                    && (!args.breaking || i.breaking())
                    && (!args.open || i.state().is_none_or(|s| !s.is_terminal()))
                    && (!args.user_visible || i.kind().is_some_and(|k| k.user_visible()))
            })
            .collect();
        print!("{}", intent::render_list(b, &items, args.common.json));
        Ok(0)
    }))
}

pub fn run_kb_intent_show(args: KbIntentShowArgs) -> AppResult<miette::Report> {
    finish((|| {
        let Some(id) = record_id(args.id_flag.as_deref(), args.id.as_deref()) else {
            return Err(Error::msg("give an intent id, e.g. `kb intent show 0007`"));
        };
        with_intent(args.common.kb.as_deref(), |kb, b| {
            let i = intent::find(b, &id)
                .ok_or_else(|| Error::msg(format!("no intent `{id}` in {}", b.label())))?;
            print!("{}", intent::render_show(kb, &i, args.common.json));
            Ok(0)
        })
    })())
}

pub fn run_kb_intent_check(args: KbIntentCheckArgs) -> AppResult<miette::Report> {
    finish(with_intent(args.common.kb.as_deref(), |kb, b| {
        let findings = intent::check(kb, b, today(args.date.as_deref())?);
        let text = if args.common.json {
            check::render_json(&findings)
        } else {
            check::render_text(&findings, true)
        };
        print!("{text}");
        let errs = count(&findings, Severity::Error);
        let warns = count(&findings, Severity::Warn);
        Ok(if errs > 0 || (args.strict && warns > 0) {
            1
        } else {
            0
        })
    }))
}

/// Applies a transition, printing the Scala CLI's confirmation lines (or the
/// `{id, state, file}` JSON) and refusing with the guard's message otherwise.
fn run_transition(
    kb_opt: Option<&str>,
    json: bool,
    id: &str,
    date: Option<&str>,
    build: impl FnOnce(&intent::Intent<'_>) -> intent::Transition,
) -> KbResult<u8> {
    with_intent(kb_opt, |kb, b| {
        let i = intent::find(b, id)
            .ok_or_else(|| Error::msg(format!("no intent `{id}` in {}", b.label())))?;
        let t = build(&i);
        let file = intent::transition(kb, b, &i, &t, today(date)?)?;
        if json {
            print!(
                "{{\n  \"id\": {},\n  \"state\": {},\n  \"file\": {}\n}}\n",
                json_str(&i.id()),
                json_str(t.to.as_str()),
                json_str(&paths::render(&file)),
            );
        } else {
            println!("intent {} → {}", i.id(), t.to);
            println!("  {}", kb.rel(&file));
            println!("  run `kb refresh` to regenerate the intent index");
        }
        Ok(0)
    })
}

pub fn run_kb_intent_refine(args: KbIntentMoveArgs) -> AppResult<miette::Report> {
    finish((|| {
        let Some(id) = record_id(args.id_flag.as_deref(), args.id.as_deref()) else {
            return Err(Error::msg("give an intent id"));
        };
        run_transition(
            args.common.kb.as_deref(),
            args.common.json,
            &id,
            args.date.as_deref(),
            |_| intent::Transition::to(intent::IntentState::Refinement),
        )
    })())
}

pub fn run_kb_intent_start(args: KbIntentMoveArgs) -> AppResult<miette::Report> {
    finish((|| {
        let Some(id) = record_id(args.id_flag.as_deref(), args.id.as_deref()) else {
            return Err(Error::msg("give an intent id"));
        };
        run_transition(
            args.common.kb.as_deref(),
            args.common.json,
            &id,
            args.date.as_deref(),
            |_| intent::Transition::to(intent::IntentState::InProgress),
        )
    })())
}

pub fn run_kb_intent_move(args: KbIntentMoveArgs) -> AppResult<miette::Report> {
    finish((|| {
        let Some(id) = record_id(args.id_flag.as_deref(), args.id.as_deref()) else {
            return Err(Error::msg("give an intent id"));
        };
        let Some(target) = args.state.as_deref().and_then(intent::IntentState::parse) else {
            return Err(Error::msg(format!(
                "--state must be one of {}",
                intent::IntentState::names()
            )));
        };
        run_transition(
            args.common.kb.as_deref(),
            args.common.json,
            &id,
            args.date.as_deref(),
            |_| intent::Transition::to(target),
        )
    })())
}

pub fn run_kb_intent_release(args: KbIntentReleaseArgs) -> AppResult<miette::Report> {
    finish((|| {
        let Some(id) = record_id(args.id_flag.as_deref(), args.id.as_deref()) else {
            return Err(Error::msg("give an intent id"));
        };
        run_transition(
            args.common.kb.as_deref(),
            args.common.json,
            &id,
            args.date.as_deref(),
            |_| intent::Transition {
                to: intent::IntentState::Released,
                capability: args.capability.clone(),
                artifacts: args.artifact.clone(),
                reason: None,
                superseded_by: None,
            },
        )
    })())
}

pub fn run_kb_intent_cancel(args: KbIntentCancelArgs) -> AppResult<miette::Report> {
    finish((|| {
        let Some(id) = record_id(args.id_flag.as_deref(), args.id.as_deref()) else {
            return Err(Error::msg("give an intent id"));
        };
        run_transition(
            args.common.kb.as_deref(),
            args.common.json,
            &id,
            args.date.as_deref(),
            |_| intent::Transition {
                to: intent::IntentState::Cancelled,
                capability: None,
                artifacts: Vec::new(),
                reason: args.reason.clone(),
                superseded_by: None,
            },
        )
    })())
}

pub fn run_kb_intent_supersede(args: KbIntentSupersedeArgs) -> AppResult<miette::Report> {
    finish((|| {
        let Some(id) = record_id(args.id_flag.as_deref(), args.id.as_deref()) else {
            return Err(Error::msg("give an intent id"));
        };
        run_transition(
            args.common.kb.as_deref(),
            args.common.json,
            &id,
            args.date.as_deref(),
            |_| intent::Transition {
                to: intent::IntentState::Superseded,
                capability: None,
                artifacts: Vec::new(),
                reason: None,
                superseded_by: args.by.clone(),
            },
        )
    })())
}

// ----------------------------------------------------------------- decision

pub fn run_kb_decision_list(args: KbDecisionListArgs) -> AppResult<miette::Report> {
    finish((|| {
        let root = resolve_kb(args.common.kb.as_deref())?;
        let kb = store::load(&root)?;
        let wanted = args
            .state
            .as_deref()
            .and_then(decision::DecisionState::parse);
        let items: Vec<decision::Decision<'_>> = decision::decisions(&kb)
            .into_iter()
            .filter(|d| {
                wanted.is_none_or(|s| d.state() == Some(s))
                    && args
                        .bundle
                        .as_deref()
                        .is_none_or(|b| d.bundle == b || d.bundle.ends_with(&format!("/{b}")))
                    && (!args.in_force || d.state().is_none_or(|s| !s.is_retired()))
            })
            .collect();
        print!("{}", decision::render_list(&items, args.common.json));
        Ok(0)
    })())
}

pub fn run_kb_decision_show(args: KbDecisionShowArgs) -> AppResult<miette::Report> {
    finish((|| {
        let Some(id) = record_id(args.id_flag.as_deref(), args.id.as_deref()) else {
            return Err(Error::msg(
                "give a decision id, e.g. `kb decision show 0004`",
            ));
        };
        let root = resolve_kb(args.common.kb.as_deref())?;
        let kb = store::load(&root)?;
        let matches = decision::find_all(&kb, &id, args.bundle.as_deref());
        match matches.as_slice() {
            [] => Err(Error::msg(format!("no decision record `{id}`"))),
            [d] => {
                print!("{}", decision::render_show(d, args.body, args.common.json));
                Ok(0)
            }
            // Ids are unique per bundle, so the same number can name a
            // different decision in each. Picking one would be silent and
            // wrong; say which bundles have it and let the caller name one.
            many => Err(Error::msg(decision::ambiguous_message(&id, many))),
        }
    })())
}
