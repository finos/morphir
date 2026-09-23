//! Thin command layer for local Library authoring.

use std::fs;
use std::path::{Path, PathBuf};

use clap::Args;
use miette::{IntoDiagnostic, WrapErr, miette};
use morphir_package::authoring::{AuthoredLibrary, LocalSigningKey};

use super::{emit, read_bounded};

#[derive(Clone, Debug, Args)]
pub struct CreateArgs {
    /// Already compiled classic JSON V4 Library IR
    #[arg(long, value_name = "FILE")]
    ir: PathBuf,
    /// Authoring fields: packagePath, version, dependencies and exports
    #[arg(long, value_name = "FILE")]
    manifest_input: PathBuf,
    /// New bundle directory; existing paths are never replaced
    #[arg(long, value_name = "DIR")]
    output: PathBuf,
    /// Output the created Library identity as JSON
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Debug, Args)]
pub struct SignArgs {
    /// Verified bundle directory containing only manifest.json and ir.json
    #[arg(long, value_name = "DIR")]
    bundle: PathBuf,
    /// Explicit Ed25519 seed file: 64 lowercase hex characters and optional final newline
    #[arg(long, value_name = "FILE")]
    key_file: PathBuf,
    /// New directory for public release record and signature envelope
    #[arg(long, value_name = "DIR")]
    output: PathBuf,
    /// Output the signer public key as JSON
    #[arg(long)]
    json: bool,
}

pub(super) fn create(args: &CreateArgs) -> miette::Result<()> {
    let input = read_bounded(&args.manifest_input, 1024 * 1024)?;
    let ir = read_bounded(&args.ir, 64 * 1024 * 1024)?;
    let library = AuthoredLibrary::create(&input, &ir).map_err(|error| miette!("{error}"))?;
    stage_files(
        &args.output,
        &[
            ("manifest.json", library.manifest_bytes()),
            ("ir.json", library.ir_bytes()),
        ],
    )?;
    emit(args.json, library.metadata().value(), || {
        format!("Created Library bundle at {}", args.output.display())
    })
}

pub(super) fn sign(args: &SignArgs) -> miette::Result<()> {
    let (manifest, ir) = read_bundle(&args.bundle)?;
    let library =
        AuthoredLibrary::from_bundle(&manifest, &ir).map_err(|error| miette!("{error}"))?;
    let key = read_key(&args.key_file)?;
    let signed = library.sign(&key).map_err(|error| miette!("{error}"))?;
    stage_files(
        &args.output,
        &[
            ("record.json", signed.record_bytes()),
            ("envelope.json", signed.envelope_bytes()),
        ],
    )?;
    emit(
        args.json,
        &serde_json::json!({"publicKey": key.public_key_hex()}),
        || format!("Wrote signed Library release to {}", args.output.display()),
    )
}

pub(super) fn read_bundle(bundle: &Path) -> miette::Result<(Vec<u8>, Vec<u8>)> {
    if !fs::symlink_metadata(bundle)
        .into_diagnostic()?
        .file_type()
        .is_dir()
    {
        return Err(miette!("bundle must be a directory, not a link"));
    }
    let mut entries = fs::read_dir(bundle)
        .into_diagnostic()?
        .map(|entry| entry.map(|entry| entry.file_name()).into_diagnostic())
        .collect::<miette::Result<Vec<_>>>()?;
    entries.sort();
    if entries != ["ir.json", "manifest.json"] {
        return Err(miette!(
            "bundle must contain only manifest.json and ir.json"
        ));
    }
    for file in ["manifest.json", "ir.json"] {
        if !fs::symlink_metadata(bundle.join(file))
            .into_diagnostic()?
            .file_type()
            .is_file()
        {
            return Err(miette!("bundle files must be regular files"));
        }
    }
    Ok((
        read_bounded(&bundle.join("manifest.json"), 1024 * 1024)?,
        read_bounded(&bundle.join("ir.json"), 64 * 1024 * 1024)?,
    ))
}

pub(super) fn read_key(path: &Path) -> miette::Result<LocalSigningKey> {
    if !fs::symlink_metadata(path)
        .into_diagnostic()?
        .file_type()
        .is_file()
    {
        return Err(miette!("invalid Ed25519 key file"));
    }
    let bytes = read_bounded(path, 65)?;
    let raw = bytes.strip_suffix(b"\n").unwrap_or(&bytes);
    if raw.len() != 64
        || !raw
            .iter()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(byte))
    {
        return Err(miette!("invalid Ed25519 key file"));
    }
    let mut seed = [0_u8; 32];
    for (index, pair) in raw.as_chunks::<2>().0.iter().enumerate() {
        let high = char::from(pair[0]).to_digit(16).expect("validated hex");
        let low = char::from(pair[1]).to_digit(16).expect("validated hex");
        seed[index] = ((high << 4) | low) as u8;
    }
    Ok(LocalSigningKey::from_seed(seed))
}

pub(super) fn stage_files(output: &Path, files: &[(&str, &[u8])]) -> miette::Result<()> {
    let parent = output
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let leaf = output
        .file_name()
        .ok_or_else(|| miette!("output must name a new directory"))?;
    let staged = tempfile::Builder::new()
        .prefix(".morphir-library-")
        .tempdir_in(parent)
        .into_diagnostic()
        .wrap_err("create staged Library directory")?;
    for (name, bytes) in files {
        fs::write(staged.path().join(name), bytes)
            .into_diagnostic()
            .wrap_err_with(|| format!("write staged {name}"))?;
    }
    move_directory_no_replace(parent, staged.path(), leaf)
        .into_diagnostic()
        .wrap_err_with(|| format!("publish Library bundle to {}", output.display()))?;
    Ok(())
}

#[cfg(unix)]
fn move_directory_no_replace(
    parent: &Path,
    staged: &Path,
    leaf: &std::ffi::OsStr,
) -> std::io::Result<()> {
    use cap_std::ambient_authority;
    use cap_std::fs::Dir;
    let parent_dir = Dir::open_ambient_dir(parent, ambient_authority())?;
    let staged_leaf = staged.file_name().ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "missing staged directory name",
        )
    })?;
    rustix::fs::renameat_with(
        &parent_dir,
        staged_leaf,
        &parent_dir,
        leaf,
        rustix::fs::RenameFlags::NOREPLACE,
    )
    .map_err(Into::into)
}

#[cfg(windows)]
fn move_directory_no_replace(
    parent: &Path,
    staged: &Path,
    leaf: &std::ffi::OsStr,
) -> std::io::Result<()> {
    // Windows directory rename fails if the destination already exists.
    fs::rename(staged, parent.join(leaf))
}
