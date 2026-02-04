//! Card components for displaying workspaces, projects, and models.

use dioxus::prelude::*;

use crate::models::{Model, ModelType, Project, Workspace};

#[component]
pub fn WorkspaceCard(workspace: Workspace, on_open: EventHandler<Workspace>) -> Element {
    let ws = workspace.clone();
    let icon = if workspace.is_favorite { "⭐" } else { "📁" };

    rsx! {
        div { class: "item-card",
            div { class: "card-header",
                div { class: "card-avatar", "{icon}" }
                div { class: "card-info",
                    div { class: "card-title-row",
                        div {
                            h3 { class: "card-name", "{workspace.name}" }
                            div { class: "card-subtitle", "workspace" }
                        }
                        button {
                            class: "btn-primary",
                            onclick: move |_| on_open.call(ws.clone()),
                            "Open"
                        }
                    }
                    p { class: "card-description", "{workspace.description}" }
                    div { class: "card-stats",
                        span {
                            span { class: "stat-value", "{workspace.project_count}" }
                            span { class: "stat-label", "Projects" }
                        }
                    }
                }
            }
        }
    }
}

#[component]
pub fn ProjectCard(project: Project, on_open: EventHandler<Project>) -> Element {
    let proj = project.clone();
    let icon = if project.is_active { "📂" } else { "📦" };
    let status = if project.is_active {
        "active"
    } else {
        "archived"
    };

    rsx! {
        div { class: "item-card",
            div { class: "card-header",
                div { class: "card-avatar", "{icon}" }
                div { class: "card-info",
                    div { class: "card-title-row",
                        div {
                            h3 { class: "card-name", "{project.name}" }
                            div { class: "card-subtitle", "{status}" }
                        }
                        button {
                            class: "btn-primary",
                            onclick: move |_| on_open.call(proj.clone()),
                            "Open"
                        }
                    }
                    p { class: "card-description", "{project.description}" }
                    div { class: "card-stats",
                        span {
                            span { class: "stat-value", "{project.model_count}" }
                            span { class: "stat-label", "Models" }
                        }
                    }
                }
            }
        }
    }
}

#[component]
pub fn ModelCard(model: Model, on_open: EventHandler<Model>) -> Element {
    let m = model.clone();
    let icon = match model.model_type {
        ModelType::TypeDefinition => "📐",
        ModelType::Function => "⚡",
    };
    let type_label = match model.model_type {
        ModelType::TypeDefinition => "type",
        ModelType::Function => "function",
    };

    rsx! {
        div { class: "item-card",
            div { class: "card-header",
                div { class: "card-avatar", "{icon}" }
                div { class: "card-info",
                    div { class: "card-title-row",
                        div {
                            h3 { class: "card-name", "{model.name}" }
                            div { class: "card-subtitle", "{type_label}" }
                        }
                        button {
                            class: "btn-primary",
                            onclick: move |_| on_open.call(m.clone()),
                            "View"
                        }
                    }
                    p { class: "card-description", "{model.description}" }
                    div { class: "card-stats",
                        if model.type_count > 0 {
                            span {
                                span { class: "stat-value", "{model.type_count}" }
                                span { class: "stat-label", "Types" }
                            }
                        }
                        if model.function_count > 0 {
                            span {
                                span { class: "stat-value", "{model.function_count}" }
                                span { class: "stat-label", "Functions" }
                            }
                        }
                    }
                }
            }
        }
    }
}
