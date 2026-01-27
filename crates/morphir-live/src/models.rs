//! Data models and filter enums for the Morphir Live application.

use serde::{Deserialize, Serialize};

// ============================================================================
// View State (deprecated - use Route instead)
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
// Search Result
// ============================================================================

/// A unified search result that can be a workspace, project, or model.
#[derive(Clone, Debug)]
pub enum SearchResult {
    Workspace(Workspace),
    Project(Project),
    Model(Model),
}

impl SearchResult {
    /// Check if this result matches a search query (case-insensitive).
    pub fn matches(&self, query: &str) -> bool {
        if query.is_empty() {
            return true;
        }
        let q = query.to_lowercase();
        match self {
            SearchResult::Workspace(w) => {
                w.name.to_lowercase().contains(&q) || w.description.to_lowercase().contains(&q)
            }
            SearchResult::Project(p) => {
                p.name.to_lowercase().contains(&q) || p.description.to_lowercase().contains(&q)
            }
            SearchResult::Model(m) => {
                m.name.to_lowercase().contains(&q) || m.description.to_lowercase().contains(&q)
            }
        }
    }

    /// Get the last accessed timestamp (only workspaces have this).
    pub fn last_accessed(&self) -> Option<u64> {
        match self {
            SearchResult::Workspace(w) => w.last_accessed,
            SearchResult::Project(_) => None,
            SearchResult::Model(_) => None,
        }
    }

    /// Check if this result is marked as favorite (only workspaces have this).
    pub fn is_favorite(&self) -> bool {
        match self {
            SearchResult::Workspace(w) => w.is_favorite,
            SearchResult::Project(_) => false,
            SearchResult::Model(_) => false,
        }
    }
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
// Content Filters
// ============================================================================

/// Entity type for filtering search results.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum EntityType {
    Workspace,
    Project,
    Model,
}

impl EntityType {
    pub fn label(&self) -> &'static str {
        match self {
            EntityType::Workspace => "Workspace",
            EntityType::Project => "Project",
            EntityType::Model => "Model",
        }
    }
}

/// Status filter options.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum StatusFilter {
    Active,
    Archived,
    Favorite,
}

impl StatusFilter {
    pub fn label(&self) -> &'static str {
        match self {
            StatusFilter::Active => "Active",
            StatusFilter::Archived => "Archived",
            StatusFilter::Favorite => "Favorite",
        }
    }
}

/// Types of filters that can be applied.
#[derive(Clone, PartialEq, Debug)]
pub enum FilterType {
    Type(EntityType),
    Location(String),
    Status(StatusFilter),
    Tags(Vec<String>),
}

/// An active filter applied by the user.
#[derive(Clone, PartialEq, Debug)]
pub struct ActiveFilter {
    pub filter_type: FilterType,
    pub label: String,
}

impl SearchResult {
    /// Check if this result matches an active filter.
    pub fn matches_filter(&self, filter: &ActiveFilter) -> bool {
        match &filter.filter_type {
            FilterType::Type(entity_type) => match (entity_type, self) {
                (EntityType::Workspace, SearchResult::Workspace(_)) => true,
                (EntityType::Project, SearchResult::Project(_)) => true,
                (EntityType::Model, SearchResult::Model(_)) => true,
                _ => false,
            },
            FilterType::Location(workspace_id) => match self {
                SearchResult::Workspace(w) => &w.id == workspace_id,
                SearchResult::Project(p) => &p.workspace_id == workspace_id,
                SearchResult::Model(_) => true, // Models don't have direct workspace ref
            },
            FilterType::Status(status) => match (status, self) {
                (StatusFilter::Active, SearchResult::Project(p)) => p.is_active,
                (StatusFilter::Archived, SearchResult::Project(p)) => !p.is_active,
                (StatusFilter::Favorite, SearchResult::Workspace(w)) => w.is_favorite,
                _ => false,
            },
            FilterType::Tags(_) => true, // Tags not implemented on entities yet
        }
    }
}

// ============================================================================
// Upload Types
// ============================================================================

/// Type of uploaded Morphir file.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum UploadFileType {
    /// morphir-ir.json - Morphir IR JSON file
    MorphirIr,
    /// morphir.json - Morphir project configuration
    MorphirJson,
    /// morphir.toml - Morphir TOML configuration
    MorphirToml,
    /// .tgz archive containing v4 model
    MorphirTgz,
}

impl UploadFileType {
    /// Detect file type from filename.
    pub fn from_filename(name: &str) -> Option<Self> {
        let lower = name.to_lowercase();
        if lower.ends_with("morphir-ir.json") {
            Some(UploadFileType::MorphirIr)
        } else if lower.ends_with("morphir.json") {
            Some(UploadFileType::MorphirJson)
        } else if lower.ends_with("morphir.toml") {
            Some(UploadFileType::MorphirToml)
        } else if lower.ends_with(".tgz") {
            Some(UploadFileType::MorphirTgz)
        } else {
            None
        }
    }
}

/// Uploaded file info (minimal for now, content types to be provided later).
#[derive(Clone, Debug)]
pub struct UploadedFile {
    pub name: String,
    pub file_type: UploadFileType,
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
