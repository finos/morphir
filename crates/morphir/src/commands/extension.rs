//! Extension command for managing Morphir extensions
//!
//! This module provides functionality for installing, updating, listing, and
//! uninstalling Morphir extensions.

use anyhow::{Context, Result, anyhow};
use serde::{Deserialize, Serialize};
use starbase::AppResult;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Default version to use when no version is specified
const DEFAULT_VERSION: &str = "latest";

/// Extension registry configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExtensionRegistry {
    /// Installed extensions with their versions
    extensions: HashMap<String, ExtensionInfo>,
}

/// Information about an installed extension
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExtensionInfo {
    /// Extension name
    name: String,
    /// Extension version
    version: Option<String>,
    /// Extension description
    description: Option<String>,
    /// Installation path
    install_path: Option<String>,
}

impl ExtensionRegistry {
    /// Create a new empty extension registry
    fn new() -> Self {
        Self {
            extensions: HashMap::new(),
        }
    }

    /// Load extension registry from configuration file
    fn load() -> Result<Self> {
        let config_path = Self::config_path()?;
        if config_path.exists() {
            let content = fs::read_to_string(&config_path)
                .context("Failed to read extension registry configuration")?;
            let registry: ExtensionRegistry = serde_json::from_str(&content)
                .context("Failed to parse extension registry configuration")?;
            Ok(registry)
        } else {
            Ok(Self::new())
        }
    }

    /// Save extension registry to configuration file
    fn save(&self) -> Result<()> {
        let config_path = Self::config_path()?;
        if let Some(parent) = config_path.parent() {
            fs::create_dir_all(parent).context("Failed to create config directory")?;
        }
        let content =
            serde_json::to_string_pretty(self).context("Failed to serialize extension registry")?;
        fs::write(&config_path, content)
            .context("Failed to write extension registry configuration")?;
        Ok(())
    }

    /// Get the path to the extension registry configuration file
    fn config_path() -> Result<PathBuf> {
        let home = dirs::home_dir().ok_or_else(|| anyhow!("Could not determine home directory"))?;
        Ok(home.join(".morphir").join("extensions.json"))
    }

    /// Add or update an extension in the registry
    fn add_extension(&mut self, ext: ExtensionInfo) {
        self.extensions.insert(ext.name.clone(), ext);
    }

    /// Remove an extension from the registry
    fn remove_extension(&mut self, name: &str) -> Option<ExtensionInfo> {
        self.extensions.remove(name)
    }

    /// Get an extension from the registry
    fn get_extension(&self, name: &str) -> Option<&ExtensionInfo> {
        self.extensions.get(name)
    }

    /// List all extensions in the registry
    fn list_extensions(&self) -> Vec<&ExtensionInfo> {
        self.extensions.values().collect()
    }
}

/// Run the extension install command
pub fn run_extension_install(name: String, version: Option<String>) -> AppResult {
    println!("Installing Morphir extension: {}", name);

    let mut registry = match ExtensionRegistry::load() {
        Ok(reg) => reg,
        Err(e) => {
            eprintln!("Error: Failed to load extension registry: {}", e);
            return Ok(Some(1));
        }
    };

    // Check if extension is already installed
    if let Some(existing_ext) = registry.get_extension(&name) {
        let version_str = existing_ext.version.as_deref().unwrap_or(DEFAULT_VERSION);
        println!(
            "Extension '{}' is already installed (version: {})",
            name, version_str
        );
        println!("Use 'morphir extension update' to update to a newer version");
        return Ok(None);
    }

    // Create extension info
    let ext_version = version.or_else(|| Some(DEFAULT_VERSION.to_string()));
    let display_version = ext_version.as_deref().unwrap_or(DEFAULT_VERSION);
    let ext = ExtensionInfo {
        name: name.clone(),
        version: ext_version.clone(),
        description: Some(format!("Morphir extension: {}", name)),
        install_path: None,
    };

    // Add extension to registry
    registry.add_extension(ext);
    if let Err(e) = registry.save() {
        eprintln!("Error: Failed to save extension registry: {}", e);
        return Ok(Some(1));
    }

    println!(
        "✓ Successfully installed extension '{}' (version: {})",
        name, display_version
    );
    println!("  Run 'morphir extension list' to see all installed extensions");

    Ok(None)
}

/// Run the extension list command
pub fn run_extension_list() -> AppResult {
    println!("Listing Morphir extensions...\n");

    // Discover builtin extensions
    let builtins = morphir_design::discover_builtin_extensions();

    // Load registry extensions
    let registry = match ExtensionRegistry::load() {
        Ok(reg) => reg,
        Err(e) => {
            eprintln!("Error: Failed to load extension registry: {}", e);
            return Ok(Some(1));
        }
    };

    let registry_extensions = registry.list_extensions();

    // Display builtin extensions
    if !builtins.is_empty() {
        println!("Builtin Extensions:");
        println!(
            "{:<20} {:<15} {:<30} Description",
            "Extension", "Version", "Capabilities"
        );
        println!("{}", "-".repeat(85));
        for builtin in &builtins {
            let languages = builtin.languages.join(", ");
            let targets = builtin.targets.join(", ");
            let capabilities = if !languages.is_empty() && !targets.is_empty() {
                format!("Frontend: {} | Backend: {}", languages, targets)
            } else if !languages.is_empty() {
                format!("Frontend: {}", languages)
            } else if !targets.is_empty() {
                format!("Backend: {}", targets)
            } else {
                "N/A".to_string()
            };
            println!(
                "{:<20} {:<15} {:<30} {}",
                builtin.id, "builtin", capabilities, builtin.name
            );
        }
        println!();
    }

    // Display registry extensions
    if registry_extensions.is_empty() && builtins.is_empty() {
        println!("No extensions available.");
        println!("Use 'morphir extension install <name>' to install an extension");
    } else if !registry_extensions.is_empty() {
        println!("Installed Extensions (from registry):");
        println!("{:<20} {:<15} Description", "Extension", "Version");
        println!("{}", "-".repeat(70));
        for ext in &registry_extensions {
            let description = ext.description.as_deref().unwrap_or("No description");
            let version_str = ext.version.as_deref().unwrap_or(DEFAULT_VERSION);
            println!("{:<20} {:<15} {}", ext.name, version_str, description);
        }
        println!();
    }

    let total = builtins.len() + registry_extensions.len();
    if total > 0 {
        println!(
            "Total: {} extension(s) available ({} builtin, {} installed)",
            total,
            builtins.len(),
            registry_extensions.len()
        );
    }

    Ok(None)
}

/// Run the extension update command
pub fn run_extension_update(name: String, version: Option<String>) -> AppResult {
    println!("Updating Morphir extension: {}", name);

    let mut registry = match ExtensionRegistry::load() {
        Ok(reg) => reg,
        Err(e) => {
            eprintln!("Error: Failed to load extension registry: {}", e);
            return Ok(Some(1));
        }
    };

    // Check if extension exists
    let existing_ext = match registry.get_extension(&name) {
        Some(ext) => ext.clone(),
        None => {
            eprintln!(
                "Error: Extension '{}' is not installed. Use 'morphir extension install' first",
                name
            );
            return Ok(Some(1));
        }
    };

    let old_version = existing_ext
        .version
        .as_deref()
        .unwrap_or(DEFAULT_VERSION)
        .to_string();
    let new_version = version.or_else(|| Some(DEFAULT_VERSION.to_string()));
    let new_version_str = new_version.as_deref().unwrap_or(DEFAULT_VERSION);

    if old_version == new_version_str {
        println!(
            "Extension '{}' is already at version {}",
            name, new_version_str
        );
        return Ok(None);
    }

    // Update extension
    let updated_ext = ExtensionInfo {
        name: name.clone(),
        version: new_version.clone(),
        description: existing_ext.description.clone(),
        install_path: existing_ext.install_path.clone(),
    };

    registry.add_extension(updated_ext);
    if let Err(e) = registry.save() {
        eprintln!("Error: Failed to save extension registry: {}", e);
        return Ok(Some(1));
    }

    println!(
        "✓ Successfully updated extension '{}' from {} to {}",
        name, old_version, new_version_str
    );

    Ok(None)
}

/// Run the extension uninstall command
pub fn run_extension_uninstall(name: String) -> AppResult {
    println!("Uninstalling Morphir extension: {}", name);

    let mut registry = match ExtensionRegistry::load() {
        Ok(reg) => reg,
        Err(e) => {
            eprintln!("Error: Failed to load extension registry: {}", e);
            return Ok(Some(1));
        }
    };

    // Remove extension from registry
    let removed_ext = match registry.remove_extension(&name) {
        Some(ext) => ext,
        None => {
            eprintln!("Error: Extension '{}' is not installed", name);
            return Ok(Some(1));
        }
    };

    if let Err(e) = registry.save() {
        eprintln!("Error: Failed to save extension registry: {}", e);
        return Ok(Some(1));
    }

    let version_str = removed_ext.version.as_deref().unwrap_or(DEFAULT_VERSION);
    println!(
        "✓ Successfully uninstalled extension '{}' (version: {})",
        removed_ext.name, version_str
    );

    Ok(None)
}
