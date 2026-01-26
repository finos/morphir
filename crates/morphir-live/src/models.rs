//! Data models and filter enums for the Morphir Live application.

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
