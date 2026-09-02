//! Verified lifecycle commands for CLI-managed Morphir tools.

use crate::home::MorphirHome;
use miette::{IntoDiagnostic, Result, WrapErr, miette};
use morphir_distribution::{
    ArchiveFormat, LocalDeveloperToolPackage, Platform, RelativeArtifactPath, ToolId,
    ToolInstaller, ToolPackageStore, ToolProvenance, ToolRepairer, list_installed_tools,
    rollback_tool, uninstall_tool,
};
use semver::Version;
use serde::Serialize;
use starbase::AppResult;
use std::path::{Path, PathBuf};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ListedTool {
    id: String,
    name: String,
    version: String,
    channel: &'static str,
    trust_policy: &'static str,
    digest: String,
    platform: String,
    launch_path: String,
    rollback_versions: Vec<String>,
}

pub fn run_tool_install(
    name: String,
    version: Option<String>,
    source: Option<PathBuf>,
    channel: Option<String>,
) -> AppResult<miette::Report> {
    let installed = install_local(
        &name,
        version,
        source,
        channel,
        LocalInstallOperation::Install,
    )?;
    println!(
        "Installed '{}' {} from the unsigned developer channel.\nDigest: {}",
        installed.tool_name(),
        installed.version(),
        installed.digest()
    );
    Ok(None)
}

pub fn run_tool_list(json: bool) -> AppResult<miette::Report> {
    let home = resolve_home()?;
    let tools = list_installed_tools(&home).into_diagnostic()?;
    let listed = tools
        .iter()
        .map(|snapshot| {
            let active = snapshot.active();
            let (channel, trust_policy) = provenance_labels(active.provenance());
            ListedTool {
                id: active.tool_id().to_string(),
                name: active.tool_name().to_owned(),
                version: active.version().to_string(),
                channel,
                trust_policy,
                digest: active.digest().to_string(),
                platform: active.platform().to_string(),
                launch_path: active.store_path().to_string_lossy().into_owned(),
                rollback_versions: snapshot
                    .rollback()
                    .iter()
                    .map(|release| release.version().to_string())
                    .collect(),
            }
        })
        .collect::<Vec<_>>();
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&listed).into_diagnostic()?
        );
    } else if listed.is_empty() {
        println!("No tools installed.");
    } else {
        println!("{:<16} {:<12} {:<12} Trust", "Tool", "Version", "Channel");
        for tool in listed {
            println!(
                "{:<16} {:<12} {:<12} {}",
                tool.id, tool.version, tool.channel, tool.trust_policy
            );
        }
    }
    Ok(None)
}

pub fn run_tool_update(
    name: String,
    version: Option<String>,
    source: Option<PathBuf>,
    channel: Option<String>,
) -> AppResult<miette::Report> {
    let installed = install_local(
        &name,
        version,
        source,
        channel,
        LocalInstallOperation::Update,
    )?;
    println!(
        "Updated '{}' to {}.",
        installed.tool_name(),
        installed.version()
    );
    Ok(None)
}

pub fn run_tool_repair(name: String, source: PathBuf) -> AppResult<miette::Report> {
    require_desktop(&name)?;
    let home = resolve_home()?;
    let id = ToolId::parse(&name).into_diagnostic()?;
    let installed = list_installed_tools(&home)
        .into_diagnostic()?
        .into_iter()
        .find(|tool| tool.active().tool_id() == &id)
        .ok_or_else(|| miette!("Tool '{name}' is not installed"))?;
    let active = installed.active();
    let local = desktop_package(source, active.version().clone(), active.platform().clone())?;
    ToolRepairer::new(&home)
        .repair_local(&id, local)
        .into_diagnostic()
        .wrap_err("Failed to repair the exact local developer package")?;
    println!("Repaired '{}' {}.", active.tool_name(), active.version());
    Ok(None)
}

pub fn run_tool_rollback(name: String) -> AppResult<miette::Report> {
    let home = resolve_home()?;
    let id = ToolId::parse(&name).into_diagnostic()?;
    let restored = rollback_tool(&home, &id).into_diagnostic()?;
    println!(
        "Rolled back '{}' to {}.",
        restored.tool_name(),
        restored.version()
    );
    Ok(None)
}

pub fn run_tool_uninstall(name: String) -> AppResult<miette::Report> {
    let home = resolve_home()?;
    let id = ToolId::parse(&name).into_diagnostic()?;
    let removed = uninstall_tool(&home, &id).into_diagnostic()?;
    println!(
        "Uninstalled '{}' {}.",
        removed.tool_name(),
        removed.version()
    );
    Ok(None)
}

fn install_local(
    name: &str,
    version: Option<String>,
    source: Option<PathBuf>,
    channel: Option<String>,
    operation: LocalInstallOperation,
) -> Result<morphir_distribution::InstalledTool> {
    require_desktop(name)?;
    let source = source
        .ok_or_else(|| miette!("Local developer installation requires --source <package>"))?;
    if channel.as_deref() != Some("developer") {
        return Err(miette!(
            "Local unsigned packages require the explicit --channel developer policy"
        ));
    }
    let version = version
        .ok_or_else(|| miette!("Local developer installation requires --version <semver>"))?
        .parse::<Version>()
        .into_diagnostic()
        .wrap_err("Invalid local Desktop version")?;
    let home = resolve_home()?;
    let local = desktop_package(source, version, Platform::current())?;
    let prepared = ToolPackageStore::new(&home)
        .prepare_local(local)
        .into_diagnostic()
        .wrap_err("Failed to verify the local Desktop package")?;
    let installer = ToolInstaller::new(&home);
    operation
        .activate(&installer, prepared)
        .into_diagnostic()
        .wrap_err("Failed to activate the local Desktop package")
}

#[derive(Debug, Clone, Copy)]
enum LocalInstallOperation {
    Install,
    Update,
}

impl LocalInstallOperation {
    fn activate(
        self,
        installer: &ToolInstaller<'_>,
        package: morphir_distribution::VerifiedToolPackage,
    ) -> morphir_distribution::Result<morphir_distribution::InstalledTool> {
        match self {
            Self::Install => installer.install_new(package),
            Self::Update => installer.update(package),
        }
    }
}

fn desktop_package(
    source: PathBuf,
    version: Version,
    platform: Platform,
) -> Result<LocalDeveloperToolPackage> {
    let (format, entry_point) = desktop_archive_contract(&source, platform.os())?;
    LocalDeveloperToolPackage::new(
        source,
        ToolId::parse("desktop").into_diagnostic()?,
        "Morphir Desktop",
        version,
        platform,
        format,
        RelativeArtifactPath::parse(entry_point).into_diagnostic()?,
        Vec::new(),
    )
    .into_diagnostic()
}

fn desktop_archive_contract(source: &Path, os: &str) -> Result<(ArchiveFormat, String)> {
    let filename = source
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| miette!("Desktop package source must have a UTF-8 filename"))?;
    let lowercase = filename.to_ascii_lowercase();
    match os {
        "windows" if lowercase.ends_with(".zip") => {
            Ok((ArchiveFormat::Zip, "morphir-desktop.exe".to_owned()))
        }
        "windows" if matches!(filename, "morphir-desktop.exe" | "Morphir Desktop.exe") => {
            Ok((ArchiveFormat::Raw, filename.to_owned()))
        }
        "macos" if lowercase.ends_with(".zip") => Ok((
            ArchiveFormat::Zip,
            "Morphir Desktop.app/Contents/MacOS/morphir-desktop".to_owned(),
        )),
        "linux" if lowercase.ends_with(".tar.gz") => {
            Ok((ArchiveFormat::TarGzip, "morphir-desktop".to_owned()))
        }
        "linux" if lowercase.ends_with(".appimage") => {
            Ok((ArchiveFormat::Appimage, filename.to_owned()))
        }
        "linux" if filename == "morphir-desktop" => Ok((ArchiveFormat::Raw, filename.to_owned())),
        _ => Err(miette!(
            "Unsupported Desktop package '{}' for host platform {}-{}",
            source.display(),
            os,
            std::env::consts::ARCH
        )),
    }
}

fn require_desktop(name: &str) -> Result<()> {
    if name == "desktop" {
        Ok(())
    } else {
        Err(miette!(
            "Local developer tool installation currently supports only 'desktop'"
        ))
    }
}

fn resolve_home() -> Result<MorphirHome> {
    MorphirHome::resolve().map_err(|error| miette!("Failed to resolve Morphir Home: {error}"))
}

fn provenance_labels(provenance: &ToolProvenance) -> (&'static str, &'static str) {
    match provenance {
        ToolProvenance::LocalDeveloper => ("developer", "local-unsigned"),
        ToolProvenance::AuthenticatedRepository { .. } => ("repository", "tuf-authenticated"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_archives_use_the_release_contract_entry_points() {
        assert_eq!(
            desktop_archive_contract(Path::new("desktop.zip"), "windows").unwrap(),
            (ArchiveFormat::Zip, "morphir-desktop.exe".to_owned())
        );
        assert_eq!(
            desktop_archive_contract(Path::new("desktop.zip"), "macos").unwrap(),
            (
                ArchiveFormat::Zip,
                "Morphir Desktop.app/Contents/MacOS/morphir-desktop".to_owned(),
            )
        );
    }

    #[test]
    fn versioned_linux_appimage_uses_its_own_filename_as_the_entry_point() {
        let filename = "morphir-desktop-0.1.0-linux-arm64.AppImage";
        assert_eq!(
            desktop_archive_contract(Path::new(filename), "linux").unwrap(),
            (ArchiveFormat::Appimage, filename.to_owned())
        );
    }

    #[test]
    fn windows_raw_packages_accept_the_release_name_and_legacy_fixture_name() {
        for filename in ["morphir-desktop.exe", "Morphir Desktop.exe"] {
            assert_eq!(
                desktop_archive_contract(Path::new(filename), "windows").unwrap(),
                (ArchiveFormat::Raw, filename.to_owned())
            );
        }
        assert!(desktop_archive_contract(Path::new("unrelated.exe"), "windows").is_err());
    }
}
