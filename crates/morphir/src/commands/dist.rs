//! Distribution command for managing Morphir distributions
//!
//! This module provides functionality for installing, updating, listing, and
//! uninstalling Morphir distributions.

use anyhow::{Context, Result, anyhow};
use serde::{Deserialize, Serialize};
use starbase::AppResult;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Default version to use when no version is specified
const DEFAULT_VERSION: &str = "latest";

/// Distribution registry configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
struct DistRegistry {
    /// Installed distributions with their versions
    distributions: HashMap<String, DistInfo>,
}

/// Information about an installed distribution
#[derive(Debug, Clone, Serialize, Deserialize)]
struct DistInfo {
    /// Distribution name
    name: String,
    /// Distribution version
    version: Option<String>,
    /// Distribution description
    description: Option<String>,
    /// Installation path
    install_path: Option<String>,
}

impl DistRegistry {
    /// Create a new empty distribution registry
    fn new() -> Self {
        Self {
            distributions: HashMap::new(),
        }
    }

    /// Load distribution registry from configuration file
    fn load() -> Result<Self> {
        let config_path = Self::config_path()?;
        if config_path.exists() {
            let content = fs::read_to_string(&config_path)
                .context("Failed to read distribution registry configuration")?;
            let registry: DistRegistry = serde_json::from_str(&content)
                .context("Failed to parse distribution registry configuration")?;
            Ok(registry)
        } else {
            Ok(Self::new())
        }
    }

    /// Save distribution registry to configuration file
    fn save(&self) -> Result<()> {
        let config_path = Self::config_path()?;
        if let Some(parent) = config_path.parent() {
            fs::create_dir_all(parent).context("Failed to create config directory")?;
        }
        let content = serde_json::to_string_pretty(self)
            .context("Failed to serialize distribution registry")?;
        fs::write(&config_path, content)
            .context("Failed to write distribution registry configuration")?;
        Ok(())
    }

    /// Get the path to the distribution registry configuration file
    fn config_path() -> Result<PathBuf> {
        let home = dirs::home_dir().ok_or_else(|| anyhow!("Could not determine home directory"))?;
        Ok(home.join(".morphir").join("distributions.json"))
    }

    /// Add or update a distribution in the registry
    fn add_distribution(&mut self, dist: DistInfo) {
        self.distributions.insert(dist.name.clone(), dist);
    }

    /// Remove a distribution from the registry
    fn remove_distribution(&mut self, name: &str) -> Option<DistInfo> {
        self.distributions.remove(name)
    }

    /// Get a distribution from the registry
    fn get_distribution(&self, name: &str) -> Option<&DistInfo> {
        self.distributions.get(name)
    }

    /// List all distributions in the registry
    fn list_distributions(&self) -> Vec<&DistInfo> {
        self.distributions.values().collect()
    }
}

/// Run the dist install command
pub fn run_dist_install(name: String, version: Option<String>) -> AppResult {
    println!("Installing Morphir distribution: {}", name);

    let mut registry = match DistRegistry::load() {
        Ok(reg) => reg,
        Err(e) => {
            eprintln!("Error: Failed to load distribution registry: {}", e);
            return Ok(Some(1));
        }
    };

    // Check if distribution is already installed
    if let Some(existing_dist) = registry.get_distribution(&name) {
        let version_str = existing_dist.version.as_deref().unwrap_or(DEFAULT_VERSION);
        println!(
            "Distribution '{}' is already installed (version: {})",
            name, version_str
        );
        println!("Use 'morphir dist update' to update to a newer version");
        return Ok(None);
    }

    // Create distribution info
    let dist_version = version.or_else(|| Some(DEFAULT_VERSION.to_string()));
    let display_version = dist_version.as_deref().unwrap_or(DEFAULT_VERSION);
    let dist = DistInfo {
        name: name.clone(),
        version: dist_version.clone(),
        description: Some(format!("Morphir distribution: {}", name)),
        install_path: None,
    };

    // Add distribution to registry
    registry.add_distribution(dist);
    if let Err(e) = registry.save() {
        eprintln!("Error: Failed to save distribution registry: {}", e);
        return Ok(Some(1));
    }

    println!(
        "✓ Successfully installed distribution '{}' (version: {})",
        name, display_version
    );
    println!("  Run 'morphir dist list' to see all installed distributions");

    Ok(None)
}

/// Run the dist list command
pub fn run_dist_list() -> AppResult {
    println!("Listing installed Morphir distributions...\n");

    let registry = match DistRegistry::load() {
        Ok(reg) => reg,
        Err(e) => {
            eprintln!("Error: Failed to load distribution registry: {}", e);
            return Ok(Some(1));
        }
    };

    let distributions = registry.list_distributions();

    if distributions.is_empty() {
        println!("No distributions installed.");
        println!("Use 'morphir dist install <name>' to install a distribution");
    } else {
        println!("{:<20} {:<15} Description", "Distribution", "Version");
        println!("{}", "-".repeat(70));
        for dist in &distributions {
            let description = dist.description.as_deref().unwrap_or("No description");
            let version_str = dist.version.as_deref().unwrap_or(DEFAULT_VERSION);
            println!("{:<20} {:<15} {}", dist.name, version_str, description);
        }
        println!("\nTotal: {} distribution(s) installed", distributions.len());
    }

    Ok(None)
}

/// Run the dist update command
pub fn run_dist_update(name: String, version: Option<String>) -> AppResult {
    println!("Updating Morphir distribution: {}", name);

    let mut registry = match DistRegistry::load() {
        Ok(reg) => reg,
        Err(e) => {
            eprintln!("Error: Failed to load distribution registry: {}", e);
            return Ok(Some(1));
        }
    };

    // Check if distribution exists
    let existing_dist = match registry.get_distribution(&name) {
        Some(dist) => dist.clone(),
        None => {
            eprintln!(
                "Error: Distribution '{}' is not installed. Use 'morphir dist install' first",
                name
            );
            return Ok(Some(1));
        }
    };

    let old_version = existing_dist
        .version
        .as_deref()
        .unwrap_or(DEFAULT_VERSION)
        .to_string();
    let new_version = version.or_else(|| Some(DEFAULT_VERSION.to_string()));
    let new_version_str = new_version.as_deref().unwrap_or(DEFAULT_VERSION);

    if old_version == new_version_str {
        println!(
            "Distribution '{}' is already at version {}",
            name, new_version_str
        );
        return Ok(None);
    }

    // Update distribution
    let updated_dist = DistInfo {
        name: name.clone(),
        version: new_version.clone(),
        description: existing_dist.description.clone(),
        install_path: existing_dist.install_path.clone(),
    };

    registry.add_distribution(updated_dist);
    if let Err(e) = registry.save() {
        eprintln!("Error: Failed to save distribution registry: {}", e);
        return Ok(Some(1));
    }

    println!(
        "✓ Successfully updated distribution '{}' from {} to {}",
        name, old_version, new_version_str
    );

    Ok(None)
}

/// Run the dist uninstall command
pub fn run_dist_uninstall(name: String) -> AppResult {
    println!("Uninstalling Morphir distribution: {}", name);

    let mut registry = match DistRegistry::load() {
        Ok(reg) => reg,
        Err(e) => {
            eprintln!("Error: Failed to load distribution registry: {}", e);
            return Ok(Some(1));
        }
    };

    // Remove distribution from registry
    let removed_dist = match registry.remove_distribution(&name) {
        Some(dist) => dist,
        None => {
            eprintln!("Error: Distribution '{}' is not installed", name);
            return Ok(Some(1));
        }
    };

    if let Err(e) = registry.save() {
        eprintln!("Error: Failed to save distribution registry: {}", e);
        return Ok(Some(1));
    }

    let version_str = removed_dist.version.as_deref().unwrap_or(DEFAULT_VERSION);
    println!(
        "✓ Successfully uninstalled distribution '{}' (version: {})",
        removed_dist.name, version_str
    );

    Ok(None)
}
