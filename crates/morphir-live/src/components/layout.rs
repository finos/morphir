//! Main layout component with sidebar and content area.

use dioxus::prelude::*;

use crate::components::cards::{ModelCard, ProjectCard, WorkspaceCard};
use crate::components::detail_views::{ModelDetailView, ProjectDetailView, WorkspaceDetailView};
use crate::components::nav_item::NavItem;
use crate::components::selected_item::SelectedItem;
use crate::components::settings::SettingsView;
use crate::components::sidebar::SidebarSection;
use crate::components::toolbar::Toolbar;
use crate::data::{sample_models, sample_projects, sample_workspaces};
use crate::models::{
    Model, ModelFilter, ModelType, MorphirConfig, Project, ProjectFilter, SettingsContext,
    ViewState, Workspace, WorkspaceFilter,
};

#[component]
pub fn MainLayout() -> Element {
    // View state management
    let mut view_state = use_signal(ViewState::default);

    // Selection state
    let mut selected_workspace = use_signal(|| None::<Workspace>);
    let mut selected_project = use_signal(|| None::<Project>);
    let mut selected_model = use_signal(|| None::<Model>);

    // Filter state
    let mut workspace_filter = use_signal(WorkspaceFilter::default);
    let mut project_filter = use_signal(ProjectFilter::default);
    let mut model_filter = use_signal(ModelFilter::default);

    // Get all data
    let all_workspaces = sample_workspaces();

    // Get filtered workspaces
    let filtered_workspaces: Vec<Workspace> = all_workspaces
        .clone()
        .into_iter()
        .filter(|w| match *workspace_filter.read() {
            WorkspaceFilter::All => true,
            WorkspaceFilter::Recent => w.last_accessed.is_some(),
            WorkspaceFilter::Favorites => w.is_favorite,
        })
        .collect();

    // Get filtered projects for selected workspace
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

    // Get filtered models for selected project
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

    // Helper to find workspace by id
    let find_workspace = |id: &str| -> Option<Workspace> {
        all_workspaces.iter().find(|w| w.id == id).cloned()
    };

    // Check if we're in settings view
    let is_settings_view = matches!(*view_state.read(), ViewState::Settings(_));

    rsx! {
        div { class: "layout",
            // Sidebar (hidden in settings view for cleaner look)
            if !is_settings_view {
                aside { class: "sidebar",
                    // Workspaces Section (always visible)
                    SidebarSection { title: "Workspaces",
                        // Show selected workspace if any
                        if let Some(ws) = selected_workspace.read().as_ref() {
                            SelectedItem {
                                icon: "📁".to_string(),
                                name: ws.name.clone(),
                                on_click: {
                                    let ws_id = ws.id.clone();
                                    move |_| {
                                        view_state.set(ViewState::WorkspaceDetail(ws_id.clone()));
                                    }
                                }
                            }
                        }

                        NavItem {
                            icon: "📁",
                            label: "All Workspaces",
                            active: matches!(*view_state.read(), ViewState::WorkspaceList) && matches!(*workspace_filter.read(), WorkspaceFilter::All),
                            on_click: move |_| {
                                workspace_filter.set(WorkspaceFilter::All);
                                selected_workspace.set(None);
                                selected_project.set(None);
                                selected_model.set(None);
                                view_state.set(ViewState::WorkspaceList);
                            }
                        }
                        NavItem {
                            icon: "🕐",
                            label: "Recent",
                            active: matches!(*view_state.read(), ViewState::WorkspaceList) && matches!(*workspace_filter.read(), WorkspaceFilter::Recent),
                            on_click: move |_| {
                                workspace_filter.set(WorkspaceFilter::Recent);
                                selected_workspace.set(None);
                                selected_project.set(None);
                                selected_model.set(None);
                                view_state.set(ViewState::WorkspaceList);
                            }
                        }
                        NavItem {
                            icon: "⭐",
                            label: "Favorites",
                            active: matches!(*view_state.read(), ViewState::WorkspaceList) && matches!(*workspace_filter.read(), WorkspaceFilter::Favorites),
                            on_click: move |_| {
                                workspace_filter.set(WorkspaceFilter::Favorites);
                                selected_workspace.set(None);
                                selected_project.set(None);
                                selected_model.set(None);
                                view_state.set(ViewState::WorkspaceList);
                            }
                        }
                    }

                    // Projects Section (visible when workspace selected)
                    if selected_workspace.read().is_some() {
                        SidebarSection { title: "Projects",
                            // Show selected project if any
                            if let Some(proj) = selected_project.read().as_ref() {
                                SelectedItem {
                                    icon: "📂".to_string(),
                                    name: proj.name.clone(),
                                    on_click: {
                                        let proj_id = proj.id.clone();
                                        move |_| {
                                            view_state.set(ViewState::ProjectDetail(proj_id.clone()));
                                        }
                                    }
                                }
                            }

                            NavItem {
                                icon: "📂",
                                label: "All Projects",
                                active: matches!(*view_state.read(), ViewState::ProjectList) && matches!(*project_filter.read(), ProjectFilter::All),
                                on_click: move |_| {
                                    project_filter.set(ProjectFilter::All);
                                    selected_project.set(None);
                                    selected_model.set(None);
                                    view_state.set(ViewState::ProjectList);
                                }
                            }
                            NavItem {
                                icon: "▶️",
                                label: "Active",
                                active: matches!(*view_state.read(), ViewState::ProjectList) && matches!(*project_filter.read(), ProjectFilter::Active),
                                on_click: move |_| {
                                    project_filter.set(ProjectFilter::Active);
                                    selected_project.set(None);
                                    selected_model.set(None);
                                    view_state.set(ViewState::ProjectList);
                                }
                            }
                            NavItem {
                                icon: "📦",
                                label: "Archived",
                                active: matches!(*view_state.read(), ViewState::ProjectList) && matches!(*project_filter.read(), ProjectFilter::Archived),
                                on_click: move |_| {
                                    project_filter.set(ProjectFilter::Archived);
                                    selected_project.set(None);
                                    selected_model.set(None);
                                    view_state.set(ViewState::ProjectList);
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
                                active: matches!(*view_state.read(), ViewState::ModelList) && matches!(*model_filter.read(), ModelFilter::All),
                                on_click: move |_| {
                                    model_filter.set(ModelFilter::All);
                                    selected_model.set(None);
                                    view_state.set(ViewState::ModelList);
                                }
                            }
                            NavItem {
                                icon: "📐",
                                label: "Types",
                                active: matches!(*view_state.read(), ViewState::ModelList) && matches!(*model_filter.read(), ModelFilter::Types),
                                on_click: move |_| {
                                    model_filter.set(ModelFilter::Types);
                                    selected_model.set(None);
                                    view_state.set(ViewState::ModelList);
                                }
                            }
                            NavItem {
                                icon: "⚡",
                                label: "Functions",
                                active: matches!(*view_state.read(), ViewState::ModelList) && matches!(*model_filter.read(), ModelFilter::Functions),
                                on_click: move |_| {
                                    model_filter.set(ModelFilter::Functions);
                                    selected_model.set(None);
                                    view_state.set(ViewState::ModelList);
                                }
                            }
                        }
                    }
                }
            }

            // Content Area
            main { class: if is_settings_view { "content-area content-area-full" } else { "content-area" },
                match view_state.read().clone() {
                    ViewState::WorkspaceList => rsx! {
                        Toolbar {
                            title: "Workspaces".to_string(),
                            subtitle: None,
                            on_config: move |_| {}
                        }
                        div { class: "content-body",
                            for workspace in filtered_workspaces {
                                WorkspaceCard {
                                    key: "{workspace.id}",
                                    workspace: workspace.clone(),
                                    on_open: {
                                        let ws = workspace.clone();
                                        move |_: Workspace| {
                                            selected_workspace.set(Some(ws.clone()));
                                            view_state.set(ViewState::WorkspaceDetail(ws.id.clone()));
                                        }
                                    }
                                }
                            }
                        }
                    },

                    ViewState::WorkspaceDetail(ws_id) => {
                        if let Some(ws) = find_workspace(&ws_id) {
                            rsx! {
                                Toolbar {
                                    title: ws.name.clone(),
                                    subtitle: Some("Workspace".to_string()),
                                    on_config: {
                                        let ws_id = ws_id.clone();
                                        move |_| {
                                            view_state.set(ViewState::Settings(SettingsContext::Workspace(ws_id.clone())));
                                        }
                                    }
                                }
                                div { class: "content-body",
                                    WorkspaceDetailView {
                                        workspace: ws.clone(),
                                        on_open_projects: {
                                            let ws = ws.clone();
                                            move |_| {
                                                selected_workspace.set(Some(ws.clone()));
                                                project_filter.set(ProjectFilter::default());
                                                view_state.set(ViewState::ProjectList);
                                            }
                                        },
                                        on_configure: {
                                            let ws_id = ws_id.clone();
                                            move |_| {
                                                view_state.set(ViewState::Settings(SettingsContext::Workspace(ws_id.clone())));
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            rsx! { div { "Workspace not found" } }
                        }
                    },

                    ViewState::ProjectList => {
                        let ws_name = selected_workspace.read().as_ref().map(|w| w.name.clone()).unwrap_or_default();
                        rsx! {
                            Toolbar {
                                title: "Projects".to_string(),
                                subtitle: Some(ws_name),
                                on_config: {
                                    let ws_id = selected_workspace.read().as_ref().map(|w| w.id.clone());
                                    move |_| {
                                        if let Some(id) = ws_id.clone() {
                                            view_state.set(ViewState::Settings(SettingsContext::Workspace(id)));
                                        }
                                    }
                                }
                            }
                            div { class: "content-body",
                                for project in projects.clone() {
                                    ProjectCard {
                                        key: "{project.id}",
                                        project: project.clone(),
                                        on_open: {
                                            let proj = project.clone();
                                            move |_: Project| {
                                                selected_project.set(Some(proj.clone()));
                                                view_state.set(ViewState::ProjectDetail(proj.id.clone()));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    },

                    ViewState::ProjectDetail(proj_id) => {
                        let proj = projects.iter().find(|p| p.id == proj_id).cloned();
                        if let Some(proj) = proj {
                            rsx! {
                                Toolbar {
                                    title: proj.name.clone(),
                                    subtitle: Some("Project".to_string()),
                                    on_config: {
                                        let proj_id = proj_id.clone();
                                        move |_| {
                                            view_state.set(ViewState::Settings(SettingsContext::Project(proj_id.clone())));
                                        }
                                    }
                                }
                                div { class: "content-body",
                                    ProjectDetailView {
                                        project: proj.clone(),
                                        on_open_models: {
                                            let proj = proj.clone();
                                            move |_| {
                                                selected_project.set(Some(proj.clone()));
                                                model_filter.set(ModelFilter::default());
                                                view_state.set(ViewState::ModelList);
                                            }
                                        },
                                        on_configure: {
                                            let proj_id = proj_id.clone();
                                            move |_| {
                                                view_state.set(ViewState::Settings(SettingsContext::Project(proj_id.clone())));
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            rsx! { div { "Project not found" } }
                        }
                    },

                    ViewState::ModelList => {
                        let proj_name = selected_project.read().as_ref().map(|p| p.name.clone()).unwrap_or_default();
                        rsx! {
                            Toolbar {
                                title: "Models".to_string(),
                                subtitle: Some(proj_name),
                                on_config: {
                                    let proj_id = selected_project.read().as_ref().map(|p| p.id.clone());
                                    move |_| {
                                        if let Some(id) = proj_id.clone() {
                                            view_state.set(ViewState::Settings(SettingsContext::Project(id)));
                                        }
                                    }
                                }
                            }
                            div { class: "content-body",
                                for model in models.clone() {
                                    ModelCard {
                                        key: "{model.id}",
                                        model: model.clone(),
                                        on_open: {
                                            let m = model.clone();
                                            move |_: Model| {
                                                selected_model.set(Some(m.clone()));
                                                view_state.set(ViewState::ModelDetail(m.id.clone()));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    },

                    ViewState::ModelDetail(model_id) => {
                        let model = models.iter().find(|m| m.id == model_id).cloned();
                        if let Some(model) = model {
                            rsx! {
                                Toolbar {
                                    title: model.name.clone(),
                                    subtitle: Some("Model".to_string()),
                                    on_config: move |_| {}
                                }
                                div { class: "content-body",
                                    ModelDetailView {
                                        model: model.clone()
                                    }
                                }
                            }
                        } else {
                            rsx! { div { "Model not found" } }
                        }
                    },

                    ViewState::Settings(context) => {
                        let prev_view = match &context {
                            SettingsContext::Workspace(id) => ViewState::WorkspaceDetail(id.clone()),
                            SettingsContext::Project(id) => ViewState::ProjectDetail(id.clone()),
                        };
                        rsx! {
                            SettingsView {
                                context: context.clone(),
                                on_close: {
                                    let prev_view = prev_view.clone();
                                    move |_| {
                                        view_state.set(prev_view.clone());
                                    }
                                },
                                on_save: {
                                    let prev_view = prev_view.clone();
                                    move |_config: MorphirConfig| {
                                        // TODO: Actually save the config
                                        view_state.set(prev_view.clone());
                                    }
                                }
                            }
                        }
                    },
                }
            }
        }
    }
}
