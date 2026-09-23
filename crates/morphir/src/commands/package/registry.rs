//! Explicit local model-Library publication commands.

#[cfg(target_os = "macos")]
use std::fs;
use std::path::{Path, PathBuf};

use clap::{Args, Subcommand};
use miette::{IntoDiagnostic, WrapErr, miette};
#[cfg(target_os = "macos")]
use morphir_package::authoring::AuthoredLibrary;
use morphir_package::local_registry::publication::Draft;
#[cfg(target_os = "macos")]
use morphir_package::local_registry::publication::Registry;
#[cfg(target_os = "macos")]
use morphir_package::local_registry::publication::{Predecessor, Proposal};

use super::author::read_key;
#[cfg(target_os = "macos")]
use super::author::{read_bundle, stage_files};
use super::{emit, read_bounded};

#[derive(Clone, Debug, Subcommand)]
pub enum RegistryAction {
    /// Inspect the public Ed25519 key and TUF key ID for an explicit local seed
    KeyInfo(KeyInfoArgs),
    /// Sign a caller-authored TUF role with an explicit local key
    SignMetadata(SignMetadataArgs),
    /// Initialize absent publisher state from a caller-signed root and policy
    Init(RegistryInitArgs),
    /// Prepare an unsigned successor against the exact current view
    Prepare(RegistryPrepareArgs),
    /// Sign a prepared successor with explicit local operator keys
    SignProposal(SignProposalArgs),
}

#[derive(Clone, Debug, Args)]
pub struct KeyInfoArgs {
    /// Explicit Ed25519 seed file: 64 lowercase hex characters and optional final newline
    #[arg(long, value_name = "FILE")]
    key_file: PathBuf,
    /// Output the public key, TUF key and key ID as JSON
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Debug, Args)]
pub struct SignMetadataArgs {
    /// Unsigned top-level TUF role JSON
    #[arg(long, value_name = "FILE")]
    input: PathBuf,
    /// Explicit Ed25519 seed file used to sign this role
    #[arg(long, value_name = "FILE")]
    key_file: PathBuf,
    /// New signed role envelope file
    #[arg(long, value_name = "FILE")]
    output: PathBuf,
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Debug, Args)]
pub struct RegistryInitArgs {
    /// Trust policy pinning the caller-signed bootstrap root and publisher keys
    #[arg(long, value_name = "FILE")]
    policy: PathBuf,
    /// Caller-signed bootstrap TUF root envelope
    #[arg(long, value_name = "FILE")]
    root: PathBuf,
    /// New local registry directory
    #[arg(long, value_name = "DIR")]
    registry: PathBuf,
    /// New private publisher-state directory
    #[arg(long, value_name = "DIR")]
    publisher_state: PathBuf,
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Debug, Args)]
pub struct RegistryPrepareArgs {
    /// Verified Library bundle from package create
    #[arg(long, value_name = "DIR")]
    bundle: PathBuf,
    /// Signed Library release from package sign
    #[arg(long, value_name = "DIR")]
    release: PathBuf,
    /// Trust policy used when initializing the registry
    #[arg(long, value_name = "FILE")]
    policy: PathBuf,
    /// Existing local registry directory
    #[arg(long, value_name = "DIR")]
    registry: PathBuf,
    /// Existing private publisher-state directory
    #[arg(long, value_name = "DIR")]
    publisher_state: PathBuf,
    /// Expiry for newly signed metadata, as an RFC 3339 UTC timestamp
    #[arg(long, value_name = "TIMESTAMP")]
    expires: String,
    /// New directory for draft.json and predecessor.json
    #[arg(long, value_name = "DIR")]
    output: PathBuf,
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Debug, Args)]
pub struct SignProposalArgs {
    /// draft.json from package registry prepare
    #[arg(long, value_name = "FILE")]
    draft: PathBuf,
    /// Explicit Ed25519 key for the TUF targets role
    #[arg(long, value_name = "FILE")]
    targets_key_file: PathBuf,
    /// Explicit Ed25519 key for the TUF snapshot role
    #[arg(long, value_name = "FILE")]
    snapshot_key_file: PathBuf,
    /// Explicit Ed25519 key for the TUF timestamp role
    #[arg(long, value_name = "FILE")]
    timestamp_key_file: PathBuf,
    /// New file containing exact signed role bytes
    #[arg(long, value_name = "FILE")]
    output: PathBuf,
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Debug, Args)]
pub struct PublishArgs {
    /// Exact Library bundle passed to package registry prepare
    #[arg(long, value_name = "DIR")]
    bundle: PathBuf,
    /// Exact signed Library release passed to package registry prepare
    #[arg(long, value_name = "DIR")]
    release: PathBuf,
    /// predecessor.json from package registry prepare
    #[arg(long, value_name = "FILE")]
    predecessor: PathBuf,
    /// Caller-signed proposal from package registry sign-proposal
    #[arg(long, value_name = "FILE")]
    proposal: PathBuf,
    /// Trust policy used when initializing the registry
    #[arg(long, value_name = "FILE")]
    policy: PathBuf,
    /// Existing local registry directory
    #[arg(long, value_name = "DIR")]
    registry: PathBuf,
    /// Existing private publisher-state directory
    #[arg(long, value_name = "DIR")]
    publisher_state: PathBuf,
    #[arg(long)]
    json: bool,
}

pub(super) fn run(action: &RegistryAction) -> miette::Result<()> {
    match action {
        RegistryAction::KeyInfo(args) => key_info(args),
        RegistryAction::SignMetadata(args) => sign_metadata(args),
        RegistryAction::Init(args) => initialize(args),
        RegistryAction::Prepare(args) => prepare(args),
        RegistryAction::SignProposal(args) => sign_proposal(args),
    }
}

fn key_info(args: &KeyInfoArgs) -> miette::Result<()> {
    let key = read_key(&args.key_file)?;
    let result = serde_json::json!({
        "publicKey": key.public_key_hex(),
        "tufKey": key.tuf_public_key(),
        "keyId": key.tuf_key_id().map_err(|error| miette!("{error}"))?
    });
    emit(args.json, &result, || result.to_string())
}

fn sign_metadata(args: &SignMetadataArgs) -> miette::Result<()> {
    let bytes = read_bounded(&args.input, 1024 * 1024)?;
    let value = morphir_package::strict_json::parse(
        std::str::from_utf8(&bytes)
            .into_diagnostic()
            .wrap_err("unsigned metadata must be UTF-8 JSON")?,
    )
    .map_err(|_| miette!("invalid unsigned metadata JSON"))?;
    let key = read_key(&args.key_file)?;
    let signed = key.sign_tuf(&value).map_err(|error| miette!("{error}"))?;
    write_new_file(&args.output, &signed)?;
    emit(args.json, &serde_json::json!({"signed":true}), || {
        format!("Wrote signed TUF metadata to {}", args.output.display())
    })
}

#[cfg(target_os = "macos")]
fn initialize(args: &RegistryInitArgs) -> miette::Result<()> {
    let policy = read_bounded(&args.policy, 1024 * 1024)?;
    let root = read_bounded(&args.root, 1024 * 1024)?;
    Registry::initialize(&args.registry, &args.publisher_state, &policy, &root)
        .map_err(|error| miette!("{error}"))?;
    emit(args.json, &serde_json::json!({"initialized":true}), || {
        format!(
            "Initialized local Library registry at {}",
            args.registry.display()
        )
    })
}

#[cfg(not(target_os = "macos"))]
fn initialize(_args: &RegistryInitArgs) -> miette::Result<()> {
    Err(miette!(
        "local Library publication is currently qualified only on macOS"
    ))
}

#[cfg(target_os = "macos")]
fn prepare(args: &RegistryPrepareArgs) -> miette::Result<()> {
    let (manifest, ir) = read_bundle(&args.bundle)?;
    let library =
        AuthoredLibrary::from_bundle(&manifest, &ir).map_err(|error| miette!("{error}"))?;
    let (record, envelope) = read_release(&args.release)?;
    let policy = read_bounded(&args.policy, 1024 * 1024)?;
    let registry = Registry::open(&args.registry, &args.publisher_state, &policy)
        .map_err(|error| miette!("{error}"))?;
    let draft = registry
        .prepare(&library, &record, &envelope, &args.expires)
        .map_err(|error| miette!("{error}"))?;
    let predecessor = serde_json::to_vec(draft.predecessor()).into_diagnostic()?;
    let draft_bytes = serde_json::to_vec(&draft).into_diagnostic()?;
    drop(registry);
    stage_files(
        &args.output,
        &[
            ("draft.json", &draft_bytes),
            ("predecessor.json", &predecessor),
        ],
    )?;
    emit(args.json, &draft, || {
        format!(
            "Prepared local Library successor at {}",
            args.output.display()
        )
    })
}

#[cfg(not(target_os = "macos"))]
fn prepare(_args: &RegistryPrepareArgs) -> miette::Result<()> {
    Err(miette!(
        "local Library publication is currently qualified only on macOS"
    ))
}

fn sign_proposal(args: &SignProposalArgs) -> miette::Result<()> {
    let bytes = read_bounded(&args.draft, 16 * 1024 * 1024)?;
    let draft: Draft = serde_json::from_slice(&bytes)
        .into_diagnostic()
        .wrap_err("decode publication draft")?;
    let targets = read_key(&args.targets_key_file)?;
    let snapshot = read_key(&args.snapshot_key_file)?;
    let timestamp = read_key(&args.timestamp_key_file)?;
    let proposal = draft
        .sign(&targets, &snapshot, &timestamp)
        .map_err(|error| miette!("{error}"))?;
    let proposal_bytes = serde_json::to_vec(&proposal).into_diagnostic()?;
    write_new_file(&args.output, &proposal_bytes)?;
    emit(args.json, &serde_json::json!({"signed":true}), || {
        format!(
            "Wrote signed publication proposal to {}",
            args.output.display()
        )
    })
}

#[cfg(target_os = "macos")]
pub(super) fn publish(args: &PublishArgs) -> miette::Result<()> {
    let (manifest, ir) = read_bundle(&args.bundle)?;
    let library =
        AuthoredLibrary::from_bundle(&manifest, &ir).map_err(|error| miette!("{error}"))?;
    let (record, envelope) = read_release(&args.release)?;
    let predecessor: Predecessor = serde_json::from_slice(&read_bounded(&args.predecessor, 4096)?)
        .into_diagnostic()
        .wrap_err("decode exact publication predecessor")?;
    let proposal: Proposal =
        serde_json::from_slice(&read_bounded(&args.proposal, 16 * 1024 * 1024)?)
            .into_diagnostic()
            .wrap_err("decode signed publication proposal")?;
    let policy = read_bounded(&args.policy, 1024 * 1024)?;
    let registry = Registry::open(&args.registry, &args.publisher_state, &policy)
        .map_err(|error| miette!("{error}"))?;
    let result = registry
        .publish(&library, &record, &envelope, &predecessor, &proposal)
        .map_err(|error| miette!("{error}"))?;
    emit(args.json, &result, || {
        format!(
            "Published local Library release to {}",
            args.registry.display()
        )
    })
}

#[cfg(not(target_os = "macos"))]
pub(super) fn publish(_args: &PublishArgs) -> miette::Result<()> {
    Err(miette!(
        "local Library publication is currently qualified only on macOS"
    ))
}

#[cfg(target_os = "macos")]
fn read_release(directory: &Path) -> miette::Result<(Vec<u8>, Vec<u8>)> {
    if !fs::symlink_metadata(directory)
        .into_diagnostic()?
        .file_type()
        .is_dir()
    {
        return Err(miette!("signed release must be a directory, not a link"));
    }
    let mut entries = fs::read_dir(directory)
        .into_diagnostic()?
        .map(|entry| entry.map(|entry| entry.file_name()).into_diagnostic())
        .collect::<miette::Result<Vec<_>>>()?;
    entries.sort();
    if entries != ["envelope.json", "record.json"] {
        return Err(miette!(
            "signed release must contain only envelope.json and record.json"
        ));
    }
    for file in ["record.json", "envelope.json"] {
        if !fs::symlink_metadata(directory.join(file))
            .into_diagnostic()?
            .file_type()
            .is_file()
        {
            return Err(miette!("signed release files must be regular files"));
        }
    }
    Ok((
        read_bounded(&directory.join("record.json"), 1024 * 1024)?,
        read_bounded(&directory.join("envelope.json"), 1024 * 1024)?,
    ))
}

fn write_new_file(path: &Path, bytes: &[u8]) -> miette::Result<()> {
    use std::io::Write;
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let mut staged = tempfile::NamedTempFile::new_in(parent)
        .into_diagnostic()
        .wrap_err("stage signed proposal")?;
    staged.write_all(bytes).into_diagnostic()?;
    staged
        .persist_noclobber(path)
        .map_err(|error| error.error)
        .into_diagnostic()?;
    Ok(())
}
