//! Author a native process release bundle from explicit immutable input bytes.
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use cap_fs_ext::{FollowSymlinks, OpenOptionsFollowExt, OpenOptionsSyncExt};
use cap_std::{
    ambient_authority,
    fs::{Dir, OpenOptions},
};
use clap::Args;
use miette::{IntoDiagnostic, WrapErr, miette};
use morphir_distribution::{ArtifactFilename, ReleaseBundleDescriptor, Sha256Digest};
use morphir_extension_sdk::claims::CapabilityClaimSet;
use morphir_host::DescriptionSource;
use morphir_host_native::process::{ProcessChannel, ProcessLaunch};
use semver::Version;
use serde_json::json;
use starbase::AppResult;

use crate::commands::staging::move_directory_no_replace;
use crate::observability::OperationId;

#[derive(Clone, Debug, Args)]
pub struct BundleArgs {
    /// Already-built native executable; the command runs its describe probe
    #[arg(long, value_name = "FILE")]
    executable: PathBuf,
    /// Expected extension identity, independent of the source language
    #[arg(long)]
    extension_id: String,
    /// Portable identifier used by the extension release inventory
    #[arg(long)]
    short_id: String,
    /// Exact extension SemVer; must match the executable's description
    #[arg(long)]
    version: Version,
    /// Native target triple; must match the CLI build target for this probe
    #[arg(long, value_name = "TRIPLE")]
    platform: String,
    /// New bundle directory; its parent must exist and existing paths are refused
    #[arg(long, value_name = "DIR")]
    output: PathBuf,
}

/// Probe exact artifact bytes and atomically create a local release bundle.
/// Publication, installation and their independent probes remain explicit steps.
pub async fn run_extension_bundle(
    operation_id: &OperationId,
    args: &BundleArgs,
) -> AppResult<miette::Report> {
    let id = super::extension_id(&args.extension_id)?;
    if args.platform != env!("MORPHIR_BUILD_TARGET") {
        return Err(miette!(
            "Bundle platform '{}' differs from this CLI's native target '{}'; probe each artifact on its declared target",
            args.platform,
            env!("MORPHIR_BUILD_TARGET")
        ));
    }
    // A dangling symlink is an existing destination too. Final publication uses
    // an atomic no-replace move, so this early check is not the race protection.
    match fs::symlink_metadata(&args.output) {
        Ok(_) => {
            return Err(miette!(
                "Bundle output already exists: {}",
                args.output.display()
            ));
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => {
            return Err(error)
                .into_diagnostic()
                .wrap_err("inspect bundle output");
        }
    }
    let filename = args
        .executable
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| miette!("Executable must have a portable UTF-8 filename"))?;
    let filename = ArtifactFilename::parse(filename)
        .map_err(|error| miette!("Invalid executable filename: {error}"))?;
    if filename.as_str().eq_ignore_ascii_case("release.json") {
        return Err(miette!("Executable filename conflicts with release.json"));
    }
    let checksum_name = ArtifactFilename::parse(format!("{}.sha256", filename.as_str()))
        .map_err(|error| miette!("Invalid derived checksum filename: {error}"))?;
    let bytes = read_executable(&args.executable)?;
    let parent = args
        .output
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let leaf = args
        .output
        .file_name()
        .ok_or_else(|| miette!("Bundle output must name a new directory"))?;
    let staged = tempfile::Builder::new()
        .prefix(".morphir-bundle-")
        .tempdir_in(parent)
        .into_diagnostic()
        .wrap_err("prepare bundle directory")?;
    let claims = describe_bytes(id.as_str(), &filename, &bytes).await?;
    if claims.extension.version != args.version.to_string() {
        return Err(miette!(
            "Guest version '{}' differs from expected version '{}'",
            claims.extension.version,
            args.version
        ));
    }
    let digest = Sha256Digest::of_bytes(&bytes);
    let descriptor = json!({
        "schemaVersion": "2.0.0-draft.2",
        "extensionId": id, "shortId": args.short_id, "version": args.version,
        "platformDifferences": "none",
        "artifacts": [{
            "runtime": "process", "platform": args.platform, "filename": filename,
            "sha256": digest, "claims": claims, "claimCheck": "unchecked",
        }],
    });
    let mut descriptor_bytes = serde_json::to_vec_pretty(&descriptor).into_diagnostic()?;
    descriptor_bytes.push(b'\n');
    // The shared reader owns descriptor validation and forward-compatibility.
    ReleaseBundleDescriptor::parse_json(&descriptor_bytes)
        .map_err(|error| miette!("Invalid release bundle: {error}"))?;
    let artifact = staged.path().join(filename.as_str());
    fs::write(&artifact, &bytes)
        .into_diagnostic()
        .wrap_err("write bundle executable")?;
    make_executable(&artifact)?;
    fs::write(
        staged.path().join(checksum_name.as_str()),
        format!("{digest}  {}\n", filename.as_str()),
    )
    .into_diagnostic()
    .wrap_err("write bundle checksum")?;
    fs::write(staged.path().join("release.json"), descriptor_bytes)
        .into_diagnostic()
        .wrap_err("write release descriptor")?;
    move_directory_no_replace(parent, staged.path(), leaf)
        .into_diagnostic()
        .wrap_err_with(|| {
            format!(
                "create bundle at {} without replacing existing output",
                args.output.display()
            )
        })?;
    tracing::info!(schema_version = 1, component = "cli", operation_id = %operation_id,
        event_name = "extension.bundle", extension = %id, version = %args.version,
        platform = %args.platform, sha256 = %digest, output = %args.output.display(),
        "native extension bundle created from described bytes");
    println!(
        "Bundled {id} {} ({}) at {}",
        args.version,
        args.platform,
        args.output.display()
    );
    Ok(None)
}

fn read_executable(path: &Path) -> miette::Result<Vec<u8>> {
    let parent = path
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let filename = path
        .file_name()
        .ok_or_else(|| miette!("Executable must name a file"))?;
    let directory = Dir::open_ambient_dir(parent, ambient_authority())
        .into_diagnostic()
        .wrap_err("open executable directory")?;
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No).nonblock(true);
    let mut file = directory
        .open_with(filename, &options)
        .into_diagnostic()
        .wrap_err("open executable without following symlinks")?;
    if !file.metadata().into_diagnostic()?.is_file() {
        return Err(miette!("Executable must be a regular file"));
    }
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes)
        .into_diagnostic()
        .wrap_err("read executable bytes")?;
    Ok(bytes)
}

fn make_executable(path: &Path) -> miette::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))
            .into_diagnostic()
            .wrap_err("set executable permissions")?;
    }
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}

async fn describe_bytes(
    id: &str,
    filename: &ArtifactFilename,
    bytes: &[u8],
) -> miette::Result<CapabilityClaimSet> {
    // Probe in a separate private workspace. Guest-created files are never
    // added to the release bundle, which is written from the original snapshot.
    let probe = tempfile::Builder::new()
        .prefix("morphir-bundle-probe-")
        .tempdir()
        .into_diagnostic()?;
    let executable = probe.path().join(filename.as_str());
    fs::write(&executable, bytes).into_diagnostic()?;
    make_executable(&executable)?;
    let channel = ProcessChannel::spawn(ProcessLaunch::new(id, executable, probe.path()))
        .await
        .map_err(|error| miette!("Failed to start bundle describe probe: {error}"))?;
    let description = morphir_host::describe(channel, &super::host_config(), id)
        .await
        .map_err(|error| miette!("Failed to describe bundle executable: {error}"))?;
    if description.source != DescriptionSource::Describe {
        return Err(miette!(
            "Bundle authoring requires morphir.extension.describe; a session fallback cannot supply the guest's full claim set"
        ));
    }
    Ok(description.claims)
}
