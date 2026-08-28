//! Verified extension artifact management.

use crate::home::MorphirHome;
use morphir_distribution::{
    Channel, ExtensionId, ExtensionInstaller, InstalledCatalog, LocalIndex, Platform, Selection,
    list_installed, uninstall_extension,
};
use semver::Version;
use starbase::AppResult;
use std::path::Path;

fn selection(channel: Option<&str>, version: Option<&str>) -> miette::Result<Selection> {
    match (channel, version) {
        (Some(_), Some(_)) => Err(miette::miette!(
            "--channel and --version are mutually exclusive"
        )),
        (_, Some(version)) => version
            .parse::<Version>()
            .map(Selection::Exact)
            .map_err(|error| {
                miette::miette!("Invalid exact extension version '{version}': {error}")
            }),
        (Some(channel), None) => Channel::parse(channel)
            .map(Selection::Channel)
            .map_err(|error| miette::miette!("Invalid extension channel '{channel}': {error}")),
        (None, None) => Ok(Selection::Channel(Channel::Stable)),
    }
}

fn extension_id(name: &str) -> miette::Result<ExtensionId> {
    ExtensionId::parse(name).map_err(|error| miette::miette!("Invalid extension id: {error}"))
}

fn install_selected(
    home: &MorphirHome,
    index_path: &Path,
    id: &ExtensionId,
    requested: Selection,
) -> miette::Result<morphir_distribution::InstalledExtension> {
    let index = LocalIndex::open(index_path)
        .map_err(|error| miette::miette!("Failed to open extension index: {error}"))?;
    let selected = index
        .resolve(id, requested, &Platform::current())
        .map_err(|error| miette::miette!("Failed to resolve extension '{id}': {error}"))?;
    ExtensionInstaller::new(home)
        .install(selected)
        .map_err(|error| miette::miette!("Failed to install extension '{id}': {error}"))
}

/// Resolve, verify, and install one extension from a controlled local index.
pub fn run_extension_install(
    name: String,
    index: std::path::PathBuf,
    channel: Option<String>,
    version: Option<String>,
) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let id = extension_id(&name)?;
    let catalog = InstalledCatalog::load(&home)
        .map_err(|error| miette::miette!("Failed to load installed extensions: {error}"))?;
    if let Some(installed) = catalog.get(&id) {
        return Err(miette::miette!(
            "Extension '{id}' is already installed at version {}; use 'morphir extension update'",
            installed.version()
        ));
    }
    let requested = selection(channel.as_deref(), version.as_deref())?;
    let entry = install_selected(&home, &index, &id, requested.clone())?;
    println!(
        "Installed {} {} ({})",
        entry.extension_id(),
        entry.version(),
        requested
    );
    Ok(None)
}

/// List exact active catalog entries and their locked request selection.
pub fn run_extension_list() -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let builtins = morphir_devkit::discover_builtin_extensions();
    let installed = list_installed(&home)
        .map_err(|error| miette::miette!("Failed to list installed extensions: {error}"))?;

    if !builtins.is_empty() {
        println!("Builtin Extensions:");
        println!("{:<24} {:<32} Capabilities", "Extension", "Name");
        for builtin in builtins {
            let capabilities = match (builtin.languages.is_empty(), builtin.targets.is_empty()) {
                (false, false) => format!(
                    "frontend: {}; backend: {}",
                    builtin.languages.join(", "),
                    builtin.targets.join(", ")
                ),
                (false, true) => format!("frontend: {}", builtin.languages.join(", ")),
                (true, false) => format!("backend: {}", builtin.targets.join(", ")),
                (true, true) => "none".to_owned(),
            };
            println!("{:<24} {:<32} {}", builtin.id, builtin.name, capabilities);
        }
        println!();
    }

    if installed.is_empty() {
        println!("No verified extensions installed.");
        return Ok(None);
    }

    println!("Verified Installed Extensions:");
    println!("{:<24} {:<16} Selection", "Extension", "Exact version");
    for snapshot in installed {
        let entry = snapshot.installed();
        println!(
            "{:<24} {:<16} {}",
            entry.extension_id(),
            entry.version(),
            snapshot.selection()
        );
    }
    Ok(None)
}

/// Re-resolve and replace an installed extension through the verified pipeline.
pub fn run_extension_update(
    name: String,
    index: std::path::PathBuf,
    channel: Option<String>,
    version: Option<String>,
) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let id = extension_id(&name)?;
    let catalog = InstalledCatalog::load(&home)
        .map_err(|error| miette::miette!("Failed to load installed extensions: {error}"))?;
    let previous = catalog.get(&id).ok_or_else(|| {
        miette::miette!("Extension '{id}' is not installed; use 'morphir extension install' first")
    })?;
    let previous_version = previous.version().clone();
    let entry = install_selected(
        &home,
        &index,
        &id,
        selection(channel.as_deref(), version.as_deref())?,
    )?;
    println!(
        "Updated {} from {} to {}",
        entry.extension_id(),
        previous_version,
        entry.version()
    );
    Ok(None)
}

/// Remove active catalog and lock state while retaining content-addressed bytes.
pub fn run_extension_uninstall(name: String) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let id = extension_id(&name)?;
    let removed = uninstall_extension(&home, &id)
        .map_err(|error| miette::miette!("Failed to uninstall extension '{id}': {error}"))?;
    println!(
        "Uninstalled {} {} (store bytes retained)",
        removed.extension_id(),
        removed.version()
    );
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selection_defaults_to_stable() {
        assert_eq!(
            selection(None, None).unwrap(),
            Selection::Channel(Channel::Stable)
        );
    }

    #[test]
    fn selection_accepts_an_exact_semantic_version() {
        assert_eq!(
            selection(None, Some("2.100.0")).unwrap(),
            Selection::Exact(Version::new(2, 100, 0))
        );
    }
}
