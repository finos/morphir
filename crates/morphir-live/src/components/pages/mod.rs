//! Page components for routing.

mod home;
mod model_detail;
mod model_list;
mod not_found;
mod project_detail;
mod project_list;
mod project_settings;
mod workspace_detail;
mod workspace_settings;

pub use home::Home;
pub use model_detail::ModelDetail;
pub use model_list::ModelList;
pub use not_found::NotFound;
pub use project_detail::ProjectDetail;
pub use project_list::ProjectList;
pub use project_settings::ProjectSettings;
pub use workspace_detail::WorkspaceDetail;
pub use workspace_settings::WorkspaceSettings;
