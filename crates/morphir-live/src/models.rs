//! Data models and filter enums for the Morphir Live application.

use serde::{Deserialize, Serialize};

// ============================================================================
// View State
// ============================================================================

/// Represents the current view state of the application
#[derive(Clone, PartialEq, Debug, Default)]
pub enum ViewState {
    /// List of all workspaces
    #[default]
    WorkspaceList,
    /// Detail view for a specific workspace
    WorkspaceDetail(String),
    /// List of projects in the selected workspace
    ProjectList,
    /// Detail view for a specific project
    ProjectDetail(String),
    /// List of models in the selected project
    ModelList,
    /// Detail view for a specific model
    ModelDetail(String),
    /// Settings view for a workspace or project
    Settings(SettingsContext),
}

/// Context for the settings view - what entity is being configured
#[derive(Clone, PartialEq, Debug)]
pub enum SettingsContext {
    Workspace(String),
    Project(String),
}

/// Which tab is active in the settings view
#[derive(Clone, PartialEq, Debug, Default)]
pub enum SettingsTab {
    #[default]
    UI,
    Toml,
}

// ============================================================================
// Data Models
// ============================================================================

#[derive(Clone, PartialEq, Debug)]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub description: String,
    pub project_count: usize,
    pub is_favorite: bool,
    pub last_accessed: Option<u64>,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub description: String,
    pub workspace_id: String,
    pub model_count: usize,
    pub is_active: bool,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Model {
    pub id: String,
    pub name: String,
    pub description: String,
    pub project_id: String,
    pub model_type: ModelType,
    pub type_count: usize,
    pub function_count: usize,
}

#[derive(Clone, PartialEq, Debug)]
pub enum ModelType {
    TypeDefinition,
    Function,
}

// ============================================================================
// Filter Enums
// ============================================================================

#[derive(Clone, PartialEq, Debug, Default)]
pub enum WorkspaceFilter {
    #[default]
    All,
    Recent,
    Favorites,
}

#[derive(Clone, PartialEq, Debug, Default)]
pub enum ProjectFilter {
    #[default]
    All,
    Active,
    Archived,
}

#[derive(Clone, PartialEq, Debug, Default)]
pub enum ModelFilter {
    #[default]
    All,
    Types,
    Functions,
}

// ============================================================================
// Configuration Models (morphir.toml)
// ============================================================================

/// Root configuration structure matching morphir.toml
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct MorphirConfig {
    pub project: ProjectConfig,
    pub workspace: WorkspaceConfig,
    pub codegen: CodegenConfig,
    pub ir: IrConfig,
    pub cache: CacheConfig,
    pub logging: LoggingConfig,
    pub ui: UiConfig,
}

/// Project configuration section
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ProjectConfig {
    pub name: String,
    pub version: String,
    pub source_directory: String,
    #[serde(default)]
    pub exposed_modules: Vec<String>,
}

/// Workspace configuration section
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct WorkspaceConfig {
    pub root: String,
    pub output_dir: String,
    #[serde(default)]
    pub members: Vec<String>,
    #[serde(default)]
    pub exclude: Vec<String>,
}

/// Code generation configuration section
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct CodegenConfig {
    #[serde(default)]
    pub targets: Vec<String>,
    pub output_format: OutputFormat,
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    #[default]
    Pretty,
    Compact,
    Minified,
}

/// IR configuration section
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct IrConfig {
    pub format_version: u32,
    pub strict_mode: bool,
}

impl Default for IrConfig {
    fn default() -> Self {
        Self {
            format_version: 3,
            strict_mode: false,
        }
    }
}

/// Cache configuration section
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct CacheConfig {
    pub enabled: bool,
    pub dir: String,
    pub max_size: u64,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            dir: String::new(),
            max_size: 0,
        }
    }
}

/// Logging configuration section
#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct LoggingConfig {
    pub level: LogLevel,
    pub format: LogFormat,
    pub file: String,
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Debug,
    #[default]
    Info,
    Warn,
    Error,
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogFormat {
    #[default]
    Text,
    Json,
}

/// UI configuration section
#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct UiConfig {
    pub color: bool,
    pub interactive: bool,
    pub theme: UiTheme,
}

impl Default for UiConfig {
    fn default() -> Self {
        Self {
            color: true,
            interactive: true,
            theme: UiTheme::default(),
        }
    }
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum UiTheme {
    #[default]
    Default,
    Light,
    Dark,
}

impl MorphirConfig {
    /// Serialize config to TOML string
    pub fn to_toml(&self) -> Result<String, toml::ser::Error> {
        toml::to_string_pretty(self)
    }

    /// Parse config from TOML string
    pub fn from_toml(s: &str) -> Result<Self, toml::de::Error> {
        toml::from_str(s)
    }
}
