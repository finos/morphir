//! Main layout component with sidebar and content area.

use dioxus::prelude::*;

use crate::components::cards::{ModelCard, ProjectCard, WorkspaceCard};
use crate::components::nav_item::NavItem;
use crate::components::sidebar::SidebarSection;
use crate::data::{sample_models, sample_projects, sample_workspaces};
use crate::models::{
    Model, ModelFilter, ModelType, Project, ProjectFilter, Workspace, WorkspaceFilter,
};

#[component]
pub fn MainLayout() -> Element {
    // State management
    let mut selected_workspace = use_signal(|| None::<Workspace>);
    let mut selected_project = use_signal(|| None::<Project>);
    let mut workspace_filter = use_signal(WorkspaceFilter::default);
    let mut project_filter = use_signal(ProjectFilter::default);
    let mut model_filter = use_signal(ModelFilter::default);

    // Get filtered data based on current state
    let workspaces = sample_workspaces();
    let filtered_workspaces: Vec<Workspace> = workspaces
        .into_iter()
        .filter(|w| match *workspace_filter.read() {
            WorkspaceFilter::All => true,
            WorkspaceFilter::Recent => w.last_accessed.is_some(),
            WorkspaceFilter::Favorites => w.is_favorite,
        })
        .collect();

    let projects: Vec<Project> = selected_workspace
        .read()
        .as_ref()
        .map(|ws| sample_projects(&ws.id))
        .unwrap_or_default()
        .into_iter()
        .filter(|p| match *project_filter.read() {
            ProjectFilter::All => true,
            ProjectFilter::Active => p.is_active,
            ProjectFilter::Archived => !p.is_active,
        })
        .collect();

    let models: Vec<Model> = selected_project
        .read()
        .as_ref()
        .map(|proj| sample_models(&proj.id))
        .unwrap_or_default()
        .into_iter()
        .filter(|m| match *model_filter.read() {
            ModelFilter::All => true,
            ModelFilter::Types => matches!(m.model_type, ModelType::TypeDefinition),
            ModelFilter::Functions => matches!(m.model_type, ModelType::Function),
        })
        .collect();

    // Determine what content to show
    let content_view = if selected_project.read().is_some() {
        "models"
    } else if selected_workspace.read().is_some() {
        "projects"
    } else {
        "workspaces"
    };

    rsx! {
        div { class: "layout",
            // Sidebar
            aside { class: "sidebar",
                // Workspaces Section (always visible)
                SidebarSection { title: "Workspaces",
                    NavItem {
                        icon: "📁",
                        label: "All Workspaces",
                        active: matches!(*workspace_filter.read(), WorkspaceFilter::All),
                        on_click: move |_| {
                            workspace_filter.set(WorkspaceFilter::All);
                            selected_workspace.set(None);
                            selected_project.set(None);
                        }
                    }
                    NavItem {
                        icon: "🕐",
                        label: "Recent",
                        active: matches!(*workspace_filter.read(), WorkspaceFilter::Recent),
                        on_click: move |_| {
                            workspace_filter.set(WorkspaceFilter::Recent);
                            selected_workspace.set(None);
                            selected_project.set(None);
                        }
                    }
                    NavItem {
                        icon: "⭐",
                        label: "Favorites",
                        active: matches!(*workspace_filter.read(), WorkspaceFilter::Favorites),
                        on_click: move |_| {
                            workspace_filter.set(WorkspaceFilter::Favorites);
                            selected_workspace.set(None);
                            selected_project.set(None);
                        }
                    }
                }

                // Projects Section (visible when workspace selected)
                if selected_workspace.read().is_some() {
                    SidebarSection { title: "Projects",
                        NavItem {
                            icon: "📂",
                            label: "All Projects",
                            active: matches!(*project_filter.read(), ProjectFilter::All),
                            on_click: move |_| {
                                project_filter.set(ProjectFilter::All);
                                selected_project.set(None);
                            }
                        }
                        NavItem {
                            icon: "▶️",
                            label: "Active",
                            active: matches!(*project_filter.read(), ProjectFilter::Active),
                            on_click: move |_| {
                                project_filter.set(ProjectFilter::Active);
                                selected_project.set(None);
                            }
                        }
                        NavItem {
                            icon: "📦",
                            label: "Archived",
                            active: matches!(*project_filter.read(), ProjectFilter::Archived),
                            on_click: move |_| {
                                project_filter.set(ProjectFilter::Archived);
                                selected_project.set(None);
                            }
                        }
                    }
                }

                // Models Section (visible when project selected)
                if selected_project.read().is_some() {
                    SidebarSection { title: "Models",
                        NavItem {
                            icon: "🧊",
                            label: "All Models",
                            active: matches!(*model_filter.read(), ModelFilter::All),
                            on_click: move |_| model_filter.set(ModelFilter::All)
                        }
                        NavItem {
                            icon: "📐",
                            label: "Types",
                            active: matches!(*model_filter.read(), ModelFilter::Types),
                            on_click: move |_| model_filter.set(ModelFilter::Types)
                        }
                        NavItem {
                            icon: "⚡",
                            label: "Functions",
                            active: matches!(*model_filter.read(), ModelFilter::Functions),
                            on_click: move |_| model_filter.set(ModelFilter::Functions)
                        }
                    }
                }
            }

            // Content Area
            main { class: "content-area",
                match content_view {
                    "workspaces" => rsx! {
                        for workspace in filtered_workspaces {
                            WorkspaceCard {
                                key: "{workspace.id}",
                                workspace: workspace.clone(),
                                on_open: move |ws: Workspace| {
                                    selected_workspace.set(Some(ws));
                                    project_filter.set(ProjectFilter::default());
                                }
                            }
                        }
                    },
                    "projects" => rsx! {
                        for project in projects {
                            ProjectCard {
                                key: "{project.id}",
                                project: project.clone(),
                                on_open: move |proj: Project| {
                                    selected_project.set(Some(proj));
                                    model_filter.set(ModelFilter::default());
                                }
                            }
                        }
                    },
                    "models" => rsx! {
                        for model in models {
                            ModelCard {
                                key: "{model.id}",
                                model: model.clone()
                            }
                        }
                    },
                    _ => rsx! { div { "Unknown view" } }
                }
            }
        }
    }
}
