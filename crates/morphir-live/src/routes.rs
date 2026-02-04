//! Application routes for URL-based navigation.

use dioxus::prelude::*;

// Import page components for the router
use crate::components::pages::{
    Home, ModelDetail, ModelList, NotFound, ProjectDetail, ProjectList, ProjectSettings,
    WorkspaceDetail, WorkspaceSettings,
};

/// Application routes for URL-based navigation
#[derive(Clone, Routable, Debug, PartialEq)]
#[rustfmt::skip]
pub enum Route {
    /// Main layout wrapper
    #[layout(crate::components::AppLayout)]
        /// Home page - list of all workspaces
        #[route("/")]
        Home {},
        /// Workspace detail view
        #[route("/workspace/:id")]
        WorkspaceDetail { id: String },
        /// Workspace settings
        #[route("/workspace/:id/settings")]
        WorkspaceSettings { id: String },
        /// Projects list for a workspace
        #[route("/workspace/:workspace_id/projects")]
        ProjectList { workspace_id: String },
        /// Project detail view
        #[route("/workspace/:workspace_id/project/:id")]
        ProjectDetail { workspace_id: String, id: String },
        /// Project settings
        #[route("/workspace/:workspace_id/project/:id/settings")]
        ProjectSettings { workspace_id: String, id: String },
        /// Models list for a project
        #[route("/workspace/:workspace_id/project/:project_id/models")]
        ModelList { workspace_id: String, project_id: String },
        /// Model detail view
        #[route("/workspace/:workspace_id/project/:project_id/model/:id")]
        ModelDetail { workspace_id: String, project_id: String, id: String },
    #[end_layout]
    /// 404 page
    #[route("/:..route")]
    NotFound { route: Vec<String> },
}
