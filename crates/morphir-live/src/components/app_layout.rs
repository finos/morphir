//! Application layout component with sidebar and content area.

use dioxus::prelude::*;

use crate::components::mode_switcher::{AppMode, ModeSwitcher};
use crate::components::nav_item::NavItem;
use crate::components::pages::{TryModeContent, TryModeTab, TryModeSidebar};
use crate::components::selected_item::SelectedItem;
use crate::components::sidebar::SidebarSection;
use crate::data::{sample_explorations, sample_notebooks, sample_projects, sample_workspaces};
use crate::Route;

/// Main application layout with sidebar navigation.
/// Uses Outlet to render routed content.
#[component]
pub fn AppLayout() -> Element {
    let route: Route = use_route();
    let nav = navigator();

    // App mode state (Spaces or Try)
    let mut app_mode = use_signal(AppMode::default);
    // Sidebar collapsed state
    let mut sidebar_collapsed = use_signal(|| false);
    // Try mode state
    let mut try_mode_tab = use_signal(TryModeTab::default);
    let mut selected_notebook = use_signal(|| None::<String>);
    let mut selected_exploration = use_signal(|| None::<String>);

    // Determine current context from route
    let (current_workspace_id, current_project_id, is_settings) = match &route {
        Route::Home {} => (None, None, false),
        Route::WorkspaceList {} => (None, None, false),
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

    // Get notebooks and explorations for Try mode
    let notebooks = sample_notebooks();
    let explorations = sample_explorations();

    let collapsed = *sidebar_collapsed.read();
    let layout_class = if collapsed {
        "layout sidebar-collapsed"
    } else {
        "layout"
    };

    rsx! {
        div { class: "{layout_class}",
            // Sidebar
            if !is_settings {
                aside { class: if collapsed { "sidebar collapsed" } else { "sidebar" },
                    // Sidebar header with app title, collapse button, and mode switcher
                    div { class: "sidebar-header",
                        // Row 1: App title and collapse button
                        div { class: "sidebar-header-row",
                            if !collapsed {
                                span { class: "app-title", "Morphir" }
                            }
                            button {
                                class: "sidebar-collapse-btn",
                                onclick: move |_| sidebar_collapsed.toggle(),
                                title: if collapsed { "Expand sidebar" } else { "Collapse sidebar" },
                                // Sidebar panel icon
                                svg {
                                    class: "collapse-icon",
                                    width: "18",
                                    height: "18",
                                    view_box: "0 0 24 24",
                                    fill: "none",
                                    xmlns: "http://www.w3.org/2000/svg",
                                    // Outer rounded rectangle
                                    rect {
                                        x: "2",
                                        y: "3",
                                        width: "20",
                                        height: "18",
                                        rx: "3",
                                        stroke: "currentColor",
                                        stroke_width: "2",
                                        fill: "none",
                                    }
                                    // Vertical divider line
                                    line {
                                        x1: "9",
                                        y1: "3",
                                        x2: "9",
                                        y2: "21",
                                        stroke: "currentColor",
                                        stroke_width: "2",
                                    }
                                    // Horizontal lines in sidebar area
                                    line {
                                        x1: "4",
                                        y1: "8",
                                        x2: "7",
                                        y2: "8",
                                        stroke: "currentColor",
                                        stroke_width: "2",
                                        stroke_linecap: "round",
                                    }
                                    line {
                                        x1: "4",
                                        y1: "12",
                                        x2: "7",
                                        y2: "12",
                                        stroke: "currentColor",
                                        stroke_width: "2",
                                        stroke_linecap: "round",
                                    }
                                    line {
                                        x1: "4",
                                        y1: "16",
                                        x2: "7",
                                        y2: "16",
                                        stroke: "currentColor",
                                        stroke_width: "2",
                                        stroke_linecap: "round",
                                    }
                                }
                            }
                        }
                        // Row 2: Mode switcher
                        if !collapsed {
                            ModeSwitcher {
                                current_mode: *app_mode.read(),
                                on_change: move |mode| app_mode.set(mode),
                            }
                        }
                    }

                    // Mode-specific sidebar content
                    match *app_mode.read() {
                        AppMode::Spaces => {
                            rsx! {
                                // Spaces mode sidebar
                                if collapsed {
                                    // Collapsed: show only icons
                                    div { class: "sidebar-icons",
                                        button {
                                            class: if matches!(route, Route::Home {}) { "sidebar-icon-btn active" } else { "sidebar-icon-btn" },
                                            title: "Search",
                                            onclick: move |_| { nav.push(Route::Home {}); },
                                            "🔍"
                                        }
                                        button {
                                            class: if matches!(route, Route::WorkspaceList {}) { "sidebar-icon-btn active" } else { "sidebar-icon-btn" },
                                            title: "Workspaces",
                                            onclick: move |_| { nav.push(Route::WorkspaceList {}); },
                                            "📁"
                                        }
                                        if current_workspace.is_some() {
                                            button {
                                                class: if matches!(route, Route::ProjectList { .. }) { "sidebar-icon-btn active" } else { "sidebar-icon-btn" },
                                                title: "Projects",
                                                onclick: {
                                                    let ws_id = current_workspace_id.clone().unwrap_or_default();
                                                    move |_| { nav.push(Route::ProjectList { workspace_id: ws_id.clone() }); }
                                                },
                                                "📂"
                                            }
                                        }
                                        if current_project.is_some() {
                                            button {
                                                class: if matches!(route, Route::ModelList { .. }) { "sidebar-icon-btn active" } else { "sidebar-icon-btn" },
                                                title: "Models",
                                                onclick: {
                                                    let ws_id = current_workspace_id.clone().unwrap_or_default();
                                                    let proj_id = current_project_id.clone().unwrap_or_default();
                                                    move |_| { nav.push(Route::ModelList { workspace_id: ws_id.clone(), project_id: proj_id.clone() }); }
                                                },
                                                "🧊"
                                            }
                                        }
                                    }
                                } else {
                                    // Expanded: show full sidebar
                                    NavItem {
                                        icon: "🔍",
                                        label: "Search",
                                        active: matches!(route, Route::Home {}),
                                        on_click: move |_| { nav.push(Route::Home {}); },
                                    }

                                    SidebarSection { icon: Some("📁".to_string()), title: "Workspaces",
                                        if let Some(ws) = &current_workspace {
                                            SelectedItem {
                                                icon: "📁".to_string(),
                                                name: ws.name.clone(),
                                                on_click: {
                                                    let ws_id = ws.id.clone();
                                                    move |_| { nav.push(Route::WorkspaceDetail { id: ws_id.clone() }); }
                                                },
                                            }
                                        }

                                        NavItem {
                                            icon: "📁",
                                            label: "All Workspaces",
                                            active: matches!(route, Route::WorkspaceList {}),
                                            on_click: move |_| { nav.push(Route::WorkspaceList {}); },
                                        }
                                    }

                                    if current_workspace.is_some() {
                                        SidebarSection { icon: Some("📑".to_string()), title: "Projects",
                                            if let Some(proj) = &current_project {
                                                SelectedItem {
                                                    icon: "📂".to_string(),
                                                    name: proj.name.clone(),
                                                    on_click: {
                                                        let ws_id = current_workspace_id.clone().unwrap_or_default();
                                                        let proj_id = proj.id.clone();
                                                        move |_| { nav.push(Route::ProjectDetail { workspace_id: ws_id.clone(), id: proj_id.clone() }); }
                                                    },
                                                }
                                            }

                                            NavItem {
                                                icon: "📂",
                                                label: "All Projects",
                                                active: matches!(route, Route::ProjectList { .. }),
                                                on_click: {
                                                    let ws_id = current_workspace_id.clone().unwrap_or_default();
                                                    move |_| { nav.push(Route::ProjectList { workspace_id: ws_id.clone() }); }
                                                },
                                            }
                                        }
                                    }

                                    if current_project.is_some() {
                                        SidebarSection { icon: Some("⊞".to_string()), title: "Models",
                                            NavItem {
                                                icon: "🧊",
                                                label: "All Models",
                                                active: matches!(route, Route::ModelList { .. }),
                                                on_click: {
                                                    let ws_id = current_workspace_id.clone().unwrap_or_default();
                                                    let proj_id = current_project_id.clone().unwrap_or_default();
                                                    move |_| { nav.push(Route::ModelList { workspace_id: ws_id.clone(), project_id: proj_id.clone() }); }
                                                },
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        AppMode::Try => {
                            rsx! {
                                // Try mode sidebar - Notebooks and Explorations
                                TryModeSidebar {
                                    notebooks: notebooks.clone(),
                                    explorations: explorations.clone(),
                                    active_tab: *try_mode_tab.read(),
                                    selected_notebook: selected_notebook.read().clone(),
                                    selected_exploration: selected_exploration.read().clone(),
                                    collapsed,
                                    on_tab_change: move |tab| try_mode_tab.set(tab),
                                    on_select_notebook: move |id| selected_notebook.set(Some(id)),
                                    on_select_exploration: move |id| selected_exploration.set(Some(id)),
                                    on_new_notebook: move |_| {
                                        // TODO: Create new notebook
                                    },
                                    on_new_exploration: move |_| {
                                        // TODO: Create new exploration
                                    },
                                }
                            }
                        }
                    }
                }
            }

            // Content Area
            main { class: if is_settings { "content-area content-area-full" } else { "content-area" },
                match *app_mode.read() {
                    AppMode::Spaces => {
                        rsx! { Outlet::<Route> {} }
                    }
                    AppMode::Try => {
                        rsx! {
                            TryModeContent {
                                notebooks: notebooks.clone(),
                                explorations: explorations.clone(),
                                active_tab: *try_mode_tab.read(),
                                selected_notebook: selected_notebook.read().clone(),
                                selected_exploration: selected_exploration.read().clone(),
                            }
                        }
                    }
                }
            }
        }
    }
}
