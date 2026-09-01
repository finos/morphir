//! Verified extension artifact management.

use crate::home::MorphirHome;
use crate::observability::OperationId;
use morphir_distribution::{
    Channel, ExtensionId, ExtensionInstaller, ExtensionRepositories, ExtensionRepository,
    InstalledCatalog, Platform, RepositoryEndpoint, RepositoryName, Selection, list_installed,
    uninstall_extension,
};
use semver::Version;
use starbase::AppResult;

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

fn repository_name(name: &str) -> miette::Result<RepositoryName> {
    RepositoryName::parse(name).map_err(|error| miette::miette!("Invalid repository name: {error}"))
}

fn install_selected(
    home: &MorphirHome,
    repository: &str,
    id: &ExtensionId,
    requested: Selection,
) -> miette::Result<morphir_distribution::InstalledExtension> {
    let repository = repository_name(repository)?;
    let selected = ExtensionRepositories::new(home)
        .resolve(&repository, id, requested, &Platform::current())
        .map_err(|error| {
            miette::miette!(
                "Failed to resolve extension '{id}' from repository '{repository}': {error}"
            )
        })?;
    ExtensionInstaller::new(home)
        .install(selected)
        .map_err(|error| miette::miette!("Failed to install extension '{id}': {error}"))
}

/// Resolve, verify, and install one extension from a configured repository.
pub fn run_extension_install(
    operation_id: &OperationId,
    name: String,
    repository: String,
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
    let entry = install_selected(&home, &repository, &id, requested.clone())?;
    tracing::info!(
        schema_version = 1,
        component = "cli",
        operation_id = %operation_id,
        event_name = "extension.install",
        extension = %entry.extension_id(),
        repository,
        version = %entry.version(),
        selection = %requested,
        "extension installed from configured repository"
    );
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
    operation_id: &OperationId,
    name: String,
    repository: String,
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
        &repository,
        &id,
        selection(channel.as_deref(), version.as_deref())?,
    )?;
    tracing::info!(
        schema_version = 1,
        component = "cli",
        operation_id = %operation_id,
        event_name = "extension.update",
        extension = %entry.extension_id(),
        repository,
        previous_version = %previous_version,
        version = %entry.version(),
        "extension updated from configured repository"
    );
    println!(
        "Updated {} from {} to {}",
        entry.extension_id(),
        previous_version,
        entry.version()
    );
    Ok(None)
}

fn repositories(home: &MorphirHome) -> ExtensionRepositories<'_> {
    ExtensionRepositories::new(home)
}

fn endpoint_display(repository: &ExtensionRepository) -> String {
    repository
        .endpoint()
        .local_directory_path()
        .map(|path| path.display().to_string())
        .unwrap_or_else(|| "<unsupported>".to_owned())
}

/// Add a named local-directory extension repository to Morphir Home.
pub fn run_extension_repository_add(
    operation_id: &OperationId,
    name: String,
    directory: std::path::PathBuf,
) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let name = repository_name(&name)?;
    let endpoint = RepositoryEndpoint::local_directory(&directory)
        .map_err(|error| miette::miette!("Failed to open extension repository: {error}"))?;
    let added = repositories(&home)
        .add(name, endpoint)
        .map_err(|error| miette::miette!("Failed to add extension repository: {error}"))?;
    tracing::info!(
        schema_version = 1,
        component = "cli",
        operation_id = %operation_id,
        event_name = "extension.repository.add",
        repository = %added.name(),
        endpoint_kind = added.endpoint().kind(),
        state = added.state().as_str(),
        "extension repository configured"
    );
    println!(
        "Added extension repository {} ({}) at {}",
        added.name(),
        added.endpoint().kind(),
        endpoint_display(&added)
    );
    Ok(None)
}

/// List configured extension repositories without contacting their endpoints.
pub fn run_extension_repository_list(operation_id: &OperationId) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let configured = repositories(&home)
        .list()
        .map_err(|error| miette::miette!("Failed to list extension repositories: {error}"))?;
    tracing::info!(
        schema_version = 1,
        component = "cli",
        operation_id = %operation_id,
        event_name = "extension.repository.list",
        repository_count = configured.len(),
        "extension repositories listed"
    );
    if configured.is_empty() {
        println!("No extension repositories configured.");
        return Ok(None);
    }
    println!(
        "{:<24} {:<10} {:<18} Endpoint",
        "Repository", "State", "Kind"
    );
    for repository in configured {
        println!(
            "{:<24} {:<10} {:<18} {}",
            repository.name(),
            repository.state().as_str(),
            repository.endpoint().kind(),
            endpoint_display(&repository)
        );
    }
    Ok(None)
}

/// Inspect one configured extension repository without contacting its endpoint.
pub fn run_extension_repository_inspect(
    operation_id: &OperationId,
    name: String,
) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let name = repository_name(&name)?;
    let repository = repositories(&home)
        .get(&name)
        .map_err(|error| miette::miette!("Failed to inspect extension repository: {error}"))?;
    tracing::info!(
        schema_version = 1,
        component = "cli",
        operation_id = %operation_id,
        event_name = "extension.repository.inspect",
        repository = %repository.name(),
        endpoint_kind = repository.endpoint().kind(),
        state = repository.state().as_str(),
        "extension repository inspected"
    );
    println!("Repository: {}", repository.name());
    println!("State: {}", repository.state().as_str());
    println!("Kind: {}", repository.endpoint().kind());
    println!("Endpoint: {}", endpoint_display(&repository));
    Ok(None)
}

fn run_extension_repository_state(
    operation_id: &OperationId,
    name: String,
    enabled: bool,
) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let name = repository_name(&name)?;
    let repository = if enabled {
        repositories(&home).enable(&name)
    } else {
        repositories(&home).disable(&name)
    }
    .map_err(|error| miette::miette!("Failed to change extension repository state: {error}"))?;
    tracing::info!(
        schema_version = 1,
        component = "cli",
        operation_id = %operation_id,
        event_name = "extension.repository.state_change",
        repository = %repository.name(),
        endpoint_kind = repository.endpoint().kind(),
        state = repository.state().as_str(),
        "extension repository state changed"
    );
    println!(
        "{} extension repository {}",
        if enabled { "Enabled" } else { "Disabled" },
        repository.name()
    );
    Ok(None)
}

/// Enable one configured extension repository.
pub fn run_extension_repository_enable(
    operation_id: &OperationId,
    name: String,
) -> AppResult<miette::Report> {
    run_extension_repository_state(operation_id, name, true)
}

/// Disable one configured extension repository.
pub fn run_extension_repository_disable(
    operation_id: &OperationId,
    name: String,
) -> AppResult<miette::Report> {
    run_extension_repository_state(operation_id, name, false)
}

/// Remove repository configuration without touching endpoint content.
pub fn run_extension_repository_remove(
    operation_id: &OperationId,
    name: String,
) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let name = repository_name(&name)?;
    let removed = repositories(&home)
        .remove(&name)
        .map_err(|error| miette::miette!("Failed to remove extension repository: {error}"))?;
    tracing::info!(
        schema_version = 1,
        component = "cli",
        operation_id = %operation_id,
        event_name = "extension.repository.remove",
        repository = %removed.name(),
        endpoint_kind = removed.endpoint().kind(),
        "extension repository configuration removed"
    );
    println!("Removed extension repository {}", removed.name());
    Ok(None)
}

/// Validate repository metadata without installing extension bytes.
pub fn run_extension_repository_verify(
    operation_id: &OperationId,
    name: String,
) -> AppResult<miette::Report> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette::miette!("Failed to resolve Morphir home: {error}"))?;
    let name = repository_name(&name)?;
    let report = repositories(&home)
        .verify(&name)
        .map_err(|error| miette::miette!("Failed to verify extension repository: {error}"))?;
    tracing::info!(
        schema_version = 1,
        component = "cli",
        operation_id = %operation_id,
        event_name = "extension.repository.verify",
        repository = %name,
        histories = report.history_count(),
        releases = report.release_count(),
        "extension repository metadata verified"
    );
    let history_label = if report.history_count() == 1 {
        "history"
    } else {
        "histories"
    };
    let release_label = if report.release_count() == 1 {
        "release"
    } else {
        "releases"
    };
    println!(
        "Verified extension repository {name}: {} {history_label}, {} {release_label}",
        report.history_count(),
        report.release_count()
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
