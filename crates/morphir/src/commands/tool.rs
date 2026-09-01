//! Tool command for managing Morphir tools, distributions, and extensions
//!
//! This module provides functionality for installing, updating, listing, and
//! uninstalling Morphir tools and extensions, similar to npm or dotnet tool.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use starbase::AppResult;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Default version to use when no version is specified
const DEFAULT_VERSION: &str = "latest";

/// Tool registry configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ToolRegistry {
    /// Installed tools with their versions
    tools: HashMap<String, ToolInfo>,
}

/// Information about an installed tool
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ToolInfo {
    /// Tool name
    name: String,
    /// Tool version
    version: Option<String>,
    /// Tool description
    description: Option<String>,
    /// Installation path
    install_path: Option<String>,
}

impl ToolRegistry {
    /// Create a new empty tool registry
    fn new() -> Self {
        Self {
            tools: HashMap::new(),
        }
    }

    /// Load tool registry from configuration file
    fn load() -> Result<Self> {
        let config_path = Self::config_path()?;
        if config_path.exists() {
            let content = fs::read_to_string(&config_path)
                .context("Failed to read tool registry configuration")?;
            let registry: ToolRegistry = serde_json::from_str(&content)
                .context("Failed to parse tool registry configuration")?;
            Ok(registry)
        } else {
            Ok(Self::new())
        }
    }

    /// Save tool registry to configuration file
    fn save(&self) -> Result<()> {
        let config_path = Self::config_path()?;
        if let Some(parent) = config_path.parent() {
            fs::create_dir_all(parent).context("Failed to create config directory")?;
        }
        let content =
            serde_json::to_string_pretty(self).context("Failed to serialize tool registry")?;
        fs::write(&config_path, content).context("Failed to write tool registry configuration")?;
        Ok(())
    }

    /// Get the path to the tool registry configuration file
    fn config_path() -> Result<PathBuf> {
        Ok(crate::home::MorphirHome::resolve()?.tools_file())
    }

    /// Add or update a tool in the registry
    fn add_tool(&mut self, tool: ToolInfo) {
        self.tools.insert(tool.name.clone(), tool);
    }

    /// Remove a tool from the registry
    fn remove_tool(&mut self, name: &str) -> Option<ToolInfo> {
        self.tools.remove(name)
    }

    /// Get a tool from the registry
    fn get_tool(&self, name: &str) -> Option<&ToolInfo> {
        self.tools.get(name)
    }

    /// List all tools in the registry
    fn list_tools(&self) -> Vec<&ToolInfo> {
        self.tools.values().collect()
    }
}

/// Run the tool install command
pub fn run_tool_install(name: String, version: Option<String>) -> AppResult<miette::Report> {
    println!("Installing Morphir tool: {}", name);

    let mut registry = ToolRegistry::load()
        .map_err(|error| miette::miette!("Failed to load tool registry: {error}"))?;

    // Check if tool is already installed
    if let Some(existing_tool) = registry.get_tool(&name) {
        let version_str = existing_tool.version.as_deref().unwrap_or(DEFAULT_VERSION);
        println!(
            "Tool '{}' is already installed (version: {})",
            name, version_str
        );
        println!("Use 'morphir tool update' to update to a newer version");
        return Ok(None);
    }

    // Create tool info
    let tool_version = version.or_else(|| Some(DEFAULT_VERSION.to_string()));
    let display_version = tool_version.as_deref().unwrap_or(DEFAULT_VERSION);
    let tool = ToolInfo {
        name: name.clone(),
        version: tool_version.clone(),
        description: Some(format!("Morphir tool: {}", name)),
        install_path: None,
    };

    // Add tool to registry
    registry.add_tool(tool);
    registry
        .save()
        .map_err(|error| miette::miette!("Failed to save tool registry: {error}"))?;

    println!(
        "✓ Successfully installed tool '{}' (version: {})",
        name, display_version
    );
    println!("  Run 'morphir tool list' to see all installed tools");

    Ok(None)
}

/// Run the tool list command
pub fn run_tool_list() -> AppResult<miette::Report> {
    println!("Listing installed Morphir tools...\n");

    let registry = ToolRegistry::load()
        .map_err(|error| miette::miette!("Failed to load tool registry: {error}"))?;

    let tools = registry.list_tools();

    if tools.is_empty() {
        println!("No tools installed.");
        println!("Use 'morphir tool install <name>' to install a tool");
    } else {
        println!("{:<20} {:<15} Description", "Tool Name", "Version");
        println!("{}", "-".repeat(70));
        for tool in &tools {
            let description = tool.description.as_deref().unwrap_or("No description");
            let version_str = tool.version.as_deref().unwrap_or(DEFAULT_VERSION);
            println!("{:<20} {:<15} {}", tool.name, version_str, description);
        }
        println!("\nTotal: {} tool(s) installed", tools.len());
    }

    Ok(None)
}

/// Run the tool update command
pub fn run_tool_update(name: String, version: Option<String>) -> AppResult<miette::Report> {
    println!("Updating Morphir tool: {}", name);

    let mut registry = ToolRegistry::load()
        .map_err(|error| miette::miette!("Failed to load tool registry: {error}"))?;

    // Check if tool exists
    let existing_tool = registry.get_tool(&name).cloned().ok_or_else(|| {
        miette::miette!(
            "Tool '{}' is not installed. Use 'morphir tool install' first",
            name
        )
    })?;

    let old_version = existing_tool
        .version
        .as_deref()
        .unwrap_or(DEFAULT_VERSION)
        .to_string();
    let new_version = version.or_else(|| Some(DEFAULT_VERSION.to_string()));
    let new_version_str = new_version.as_deref().unwrap_or(DEFAULT_VERSION);

    if old_version == new_version_str {
        println!("Tool '{}' is already at version {}", name, new_version_str);
        return Ok(None);
    }

    // Update tool
    let updated_tool = ToolInfo {
        name: name.clone(),
        version: new_version.clone(),
        description: existing_tool.description.clone(),
        install_path: existing_tool.install_path.clone(),
    };

    registry.add_tool(updated_tool);
    registry
        .save()
        .map_err(|error| miette::miette!("Failed to save tool registry: {error}"))?;

    println!(
        "✓ Successfully updated tool '{}' from {} to {}",
        name, old_version, new_version_str
    );

    Ok(None)
}

/// Run the tool uninstall command
pub fn run_tool_uninstall(name: String) -> AppResult<miette::Report> {
    println!("Uninstalling Morphir tool: {}", name);

    let mut registry = ToolRegistry::load()
        .map_err(|error| miette::miette!("Failed to load tool registry: {error}"))?;

    // Remove tool from registry
    let removed_tool = registry
        .remove_tool(&name)
        .ok_or_else(|| miette::miette!("Tool '{name}' is not installed"))?;

    registry
        .save()
        .map_err(|error| miette::miette!("Failed to save tool registry: {error}"))?;

    let version_str = removed_tool.version.as_deref().unwrap_or(DEFAULT_VERSION);
    println!(
        "✓ Successfully uninstalled tool '{}' (version: {})",
        removed_tool.name, version_str
    );

    Ok(None)
}
