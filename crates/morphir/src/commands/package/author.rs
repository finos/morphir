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
    /// Root of an exported document tree containing contexts/*.jsonld
    #[arg(long, value_name = "DIR")]
    context_root: Option<PathBuf>,
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
    /// Verified bundle directory containing manifest.json, ir.json, and declared contexts
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
    let library = if let Some(root) = &args.context_root {
        AuthoredLibrary::create_with_contexts(&input, &ir, read_context_tree(root)?)
    } else {
        AuthoredLibrary::create(&input, &ir)
    }
    .map_err(|error| miette!("{error}"))?;
    let mut files = vec![
        ("manifest.json", library.manifest_bytes()),
        ("ir.json", library.ir_bytes()),
    ];
    files.extend(library.context_files());
    stage_files(&args.output, &files)?;
    emit(args.json, library.metadata().value(), || {
        format!("Created Library bundle at {}", args.output.display())
    })
}

pub(super) fn sign(args: &SignArgs) -> miette::Result<()> {
    let library = verified_bundle(&args.bundle)?;
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

pub(super) fn verified_bundle(bundle: &Path) -> miette::Result<AuthoredLibrary> {
    let mut files = read_tree_files(bundle)?;
    let manifest = files
        .remove("manifest.json")
        .ok_or_else(|| miette!("bundle is missing manifest.json"))?;
    let ir = files
        .remove("ir.json")
        .ok_or_else(|| miette!("bundle is missing ir.json"))?;
    if files.keys().any(|path| !path.starts_with("contexts/")) {
        return Err(miette!(
            "bundle contains an undeclared file outside contexts/"
        ));
    }
    AuthoredLibrary::from_bundle_with_contexts(&manifest, &ir, files.into_iter().collect())
        .map_err(|error| miette!("{error}"))
}

fn read_context_tree(root: &Path) -> miette::Result<Vec<(String, Vec<u8>)>> {
    if !fs::symlink_metadata(root)
        .into_diagnostic()?
        .file_type()
        .is_dir()
    {
        return Err(miette!("context root must be a directory, not a link"));
    }
    let files = read_tree_files_from(root, &root.join("contexts"))?;
    if files.is_empty() {
        return Err(miette!("context root has no contexts/*.jsonld files"));
    }
    if files.keys().any(|path| !path.ends_with(".jsonld")) {
        return Err(miette!("context root contains a non-JSON-LD resource"));
    }
    Ok(files.into_iter().collect())
}

fn read_tree_files(root: &Path) -> miette::Result<std::collections::BTreeMap<String, Vec<u8>>> {
    read_tree_files_from(root, root)
}

fn read_tree_files_from(
    root: &Path,
    start: &Path,
) -> miette::Result<std::collections::BTreeMap<String, Vec<u8>>> {
    use std::path::Component;

    let mut files = std::collections::BTreeMap::new();
    let mut context_bytes = 0usize;
    let mut pending = vec![start.to_path_buf()];
    while let Some(directory) = pending.pop() {
        if !fs::symlink_metadata(&directory)
            .into_diagnostic()?
            .file_type()
            .is_dir()
        {
            return Err(miette!("bundle resource directory must not be a link"));
        }
        for entry in fs::read_dir(&directory).into_diagnostic()? {
            let entry = entry.into_diagnostic()?;
            let path = entry.path();
            let kind = entry.file_type().into_diagnostic()?;
            if kind.is_dir() {
                pending.push(path);
                continue;
            }
            if !kind.is_file() {
                return Err(miette!("bundle resources must be regular files"));
            }
            let relative = path
                .strip_prefix(root)
                .into_diagnostic()?
                .components()
                .map(|component| match component {
                    Component::Normal(name) => name
                        .to_str()
                        .map(str::to_owned)
                        .ok_or_else(|| miette!("bundle resource path must be UTF-8")),
                    _ => Err(miette!("invalid bundle resource path")),
                })
                .collect::<miette::Result<Vec<_>>>()?
                .join("/");
            let limit = match relative.as_str() {
                "manifest.json" => 1024 * 1024,
                "ir.json" => 64 * 1024 * 1024,
                _ => 1024 * 1024,
            };
            let bytes = read_bounded(&path, limit)?;
            if relative.starts_with("contexts/") {
                context_bytes = context_bytes
                    .checked_add(bytes.len())
                    .ok_or_else(|| miette!("context resources exceed 8 MiB"))?;
                if context_bytes > 8 * 1024 * 1024 {
                    return Err(miette!("context resources exceed 8 MiB"));
                }
            }
            if files.insert(relative, bytes).is_some() {
                return Err(miette!("duplicate bundle resource path"));
            }
            if files.len() > 130 {
                return Err(miette!("bundle resource count exceeds 130"));
            }
        }
    }
    Ok(files)
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
        let relative = Path::new(name);
        if !relative
            .components()
            .all(|component| matches!(component, std::path::Component::Normal(_)))
        {
            return Err(miette!("invalid staged Library path {name}"));
        }
        let destination = staged.path().join(relative);
        fs::create_dir_all(destination.parent().expect("staged file has a parent"))
            .into_diagnostic()?;
        fs::write(destination, bytes)
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
