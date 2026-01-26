//! Application layout component with sidebar and content area.

use dioxus::prelude::*;

use crate::components::nav_item::NavItem;
use crate::components::selected_item::SelectedItem;
use crate::components::sidebar::SidebarSection;
use crate::data::{sample_projects, sample_workspaces};
use crate::Route;

/// Main application layout with sidebar navigation.
/// Uses Outlet to render routed content.
#[component]
pub fn AppLayout() -> Element {
    let route: Route = use_route();
    let nav = navigator();

    // Determine current context from route
    let (current_workspace_id, current_project_id, is_settings) = match &route {
        Route::Home {} => (None, None, false),
        Route::WorkspaceDetail { id } => (Some(id.clone()), None, false),
        Route::WorkspaceSettings { id } => (Some(id.clone()), None, true),
        Route::ProjectList { workspace_id } => (Some(workspace_id.clone()), None, false),
        Route::ProjectDetail { workspace_id, id } => {
            (Some(workspace_id.clone()), Some(id.clone()), false)
        }
        Route::ProjectSettings { workspace_id, id } => {
            (Some(workspace_id.clone()), Some(id.clone()), true)
        }
        Route::ModelList {
            workspace_id,
            project_id,
        } => (Some(workspace_id.clone()), Some(project_id.clone()), false),
        Route::ModelDetail {
            workspace_id,
            project_id,
            ..
        } => (Some(workspace_id.clone()), Some(project_id.clone()), false),
        Route::NotFound { .. } => (None, None, false),
    };

    // Get workspace and project data
    let all_workspaces = sample_workspaces();
    let current_workspace = current_workspace_id
        .as_ref()
        .and_then(|id| all_workspaces.iter().find(|w| w.id == *id).cloned());

    let all_projects = current_workspace_id
        .as_ref()
        .map(|id| sample_projects(id))
        .unwrap_or_default();
    let current_project = current_project_id
        .as_ref()
        .and_then(|id| all_projects.iter().find(|p| p.id == *id).cloned());

    rsx! {
        div { class: "layout",
            // Sidebar (hidden in settings view for cleaner look)
            if !is_settings {
                aside { class: "sidebar",
                    // Workspaces Section (always visible)
                    SidebarSection { icon: Some("📁".to_string()), title: "Workspaces",
                        // Show selected workspace if any
                        if let Some(ws) = &current_workspace {
                            SelectedItem {
                                icon: "📁".to_string(),
                                name: ws.name.clone(),
                                on_click: {
                                    let ws_id = ws.id.clone();
                                    move |_| {
                                        nav.push(Route::WorkspaceDetail { id: ws_id.clone() });
                                    }
                                }
                            }
                        }

                        NavItem {
                            icon: "📁",
                            label: "All Workspaces",
                            active: matches!(route, Route::Home {}),
                            on_click: move |_| {
                                nav.push(Route::Home {});
                            }
                        }
                    }

                    // Projects Section (visible when workspace selected)
                    if current_workspace.is_some() {
                        SidebarSection { icon: Some("📑".to_string()), title: "Projects",
                            // Show selected project if any
                            if let Some(proj) = &current_project {
                                SelectedItem {
                                    icon: "📂".to_string(),
                                    name: proj.name.clone(),
                                    on_click: {
                                        let ws_id = current_workspace_id.clone().unwrap_or_default();
                                        let proj_id = proj.id.clone();
                                        move |_| {
                                            nav.push(Route::ProjectDetail {
                                                workspace_id: ws_id.clone(),
                                                id: proj_id.clone(),
                                            });
                                        }
                                    }
                                }
                            }

                            NavItem {
                                icon: "📂",
                                label: "All Projects",
                                active: matches!(route, Route::ProjectList { .. }),
                                on_click: {
                                    let ws_id = current_workspace_id.clone().unwrap_or_default();
                                    move |_| {
                                        nav.push(Route::ProjectList { workspace_id: ws_id.clone() });
                                    }
                                }
                            }
                        }
                    }

                    // Models Section (visible when project selected)
                    if current_project.is_some() {
                        SidebarSection { icon: Some("⊞".to_string()), title: "Models",
                            NavItem {
                                icon: "🧊",
                                label: "All Models",
                                active: matches!(route, Route::ModelList { .. }),
                                on_click: {
                                    let ws_id = current_workspace_id.clone().unwrap_or_default();
                                    let proj_id = current_project_id.clone().unwrap_or_default();
                                    move |_| {
                                        nav.push(Route::ModelList {
                                            workspace_id: ws_id.clone(),
                                            project_id: proj_id.clone(),
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Content Area
            main { class: if is_settings { "content-area content-area-full" } else { "content-area" },
                Outlet::<Route> {}
            }
        }
    }
}
