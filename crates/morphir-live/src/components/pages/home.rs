//! Home page - search interface with quick access to workspaces, projects, and models.

use dioxus::prelude::*;

use crate::components::cards::{ModelCard, ProjectCard, WorkspaceCard};
use crate::components::{ContentFilters, QuickAccessTab, QuickAccessTabs, SearchInput, UploadButton};
use crate::data::{all_projects, all_search_results};
use crate::models::{ActiveFilter, EntityType, SearchResult};
use crate::Route;

#[component]
pub fn Home() -> Element {
    let nav = navigator();
    let mut search_query = use_signal(String::new);
    let mut active_tab = use_signal(QuickAccessTab::default);
    let mut show_all = use_signal(|| true);
    let mut type_filter = use_signal(|| None::<EntityType>);
    let mut active_filters = use_signal(Vec::<ActiveFilter>::new);
    let mut show_filter_panel = use_signal(|| false);

    // Get all search results
    let all_results = all_search_results();

    // Filter results based on all criteria
    let filtered_results: Vec<SearchResult> = all_results
        .into_iter()
        .filter(|result| {
            // First filter by search query
            if !result.matches(&search_query.read()) {
                return false;
            }

            // Filter by active tab
            match *active_tab.read() {
                QuickAccessTab::Recent => {
                    if result.last_accessed().is_none() {
                        return false;
                    }
                }
                QuickAccessTab::Favorites => {
                    if !result.is_favorite() {
                        return false;
                    }
                }
            }

            // If "All" is not selected, apply type filter
            if !*show_all.read() {
                if let Some(entity_type) = *type_filter.read() {
                    let matches_type = match (entity_type, result) {
                        (EntityType::Workspace, SearchResult::Workspace(_)) => true,
                        (EntityType::Project, SearchResult::Project(_)) => true,
                        (EntityType::Model, SearchResult::Model(_)) => true,
                        _ => false,
                    };
                    if !matches_type {
                        return false;
                    }
                }
            }

            // Apply active filters (AND logic)
            for filter in active_filters.read().iter() {
                if !result.matches_filter(filter) {
                    return false;
                }
            }

            true
        })
        .collect();

    rsx! {
        div { class: "home-search-page",
            // Search header
            div { class: "search-header",
                h1 { class: "search-title", "What can I help you find?" }
                SearchInput {
                    query: search_query.read().clone(),
                    placeholder: "Search workspaces, projects, models...".to_string(),
                    on_change: move |q| search_query.set(q),
                }
            }

            // Quick access section
            div { class: "quick-access-section",
                // Header with title and upload button
                div { class: "quick-access-header",
                    h2 { class: "quick-access-title", "Quick access" }
                    UploadButton {
                        on_upload: move |_file| {
                            // TODO: Handle uploaded file when library types are integrated
                        },
                    }
                }

                // Tabs
                QuickAccessTabs {
                    active_tab: *active_tab.read(),
                    on_tab_change: move |tab| active_tab.set(tab),
                }

                // Content filters
                ContentFilters {
                    show_all: *show_all.read(),
                    type_filter: *type_filter.read(),
                    active_filters: active_filters.read().clone(),
                    show_filter_panel: *show_filter_panel.read(),
                    on_toggle_all: move |_| {
                        let current = *show_all.read();
                        show_all.set(!current);
                        if !current {
                            // When enabling "All", clear type filter
                            type_filter.set(None);
                        }
                    },
                    on_type_change: move |t| {
                        type_filter.set(t);
                        if t.is_some() {
                            show_all.set(false);
                        }
                    },
                    on_add_filter: move |filter| {
                        active_filters.write().push(filter);
                        show_filter_panel.set(false);
                    },
                    on_remove_filter: move |idx| {
                        active_filters.write().remove(idx);
                    },
                    on_toggle_panel: move |_| {
                        let current = *show_filter_panel.read();
                        show_filter_panel.set(!current);
                    },
                }
            }

            // Results
            div { class: "search-results",
                if filtered_results.is_empty() {
                    div { class: "no-results",
                        p { "No items found. Try a different search or filter." }
                    }
                } else {
                    for result in filtered_results {
                        match result {
                            SearchResult::Workspace(workspace) => {
                                {
                                    let ws_id = workspace.id.clone();
                                    rsx! {
                                        WorkspaceCard {
                                            key: "{workspace.id}",
                                            workspace: workspace.clone(),
                                            on_open: move |_| {
                                                nav.push(Route::WorkspaceDetail { id: ws_id.clone() });
                                            },
                                        }
                                    }
                                }
                            }
                            SearchResult::Project(project) => {
                                {
                                    let ws_id = project.workspace_id.clone();
                                    let proj_id = project.id.clone();
                                    rsx! {
                                        ProjectCard {
                                            key: "{project.id}",
                                            project: project.clone(),
                                            on_open: move |_| {
                                                nav.push(Route::ProjectDetail {
                                                    workspace_id: ws_id.clone(),
                                                    id: proj_id.clone(),
                                                });
                                            },
                                        }
                                    }
                                }
                            }
                            SearchResult::Model(model) => {
                                {
                                    // Find the project to get workspace_id
                                    let projects = all_projects();
                                    let project = projects.iter().find(|p| p.id == model.project_id);
                                    let ws_id = project.map(|p| p.workspace_id.clone()).unwrap_or_default();
                                    let proj_id = model.project_id.clone();
                                    let model_id = model.id.clone();
                                    rsx! {
                                        ModelCard {
                                            key: "{model.id}",
                                            model: model.clone(),
                                            on_open: move |_| {
                                                nav.push(Route::ModelDetail {
                                                    workspace_id: ws_id.clone(),
                                                    project_id: proj_id.clone(),
                                                    id: model_id.clone(),
                                                });
                                            },
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
