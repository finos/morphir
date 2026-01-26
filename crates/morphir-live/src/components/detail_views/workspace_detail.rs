//! Workspace detail view component.

use dioxus::prelude::*;

use crate::models::Workspace;

#[component]
pub fn WorkspaceDetailView(
    workspace: Workspace,
    on_open_projects: EventHandler<()>,
    on_configure: EventHandler<()>,
) -> Element {
    rsx! {
        div { class: "detail-view",
            // Header
            div { class: "detail-header",
                div { class: "detail-avatar", "📁" }
                div { class: "detail-info",
                    h1 { class: "detail-title", "{workspace.name}" }
                    p { class: "detail-subtitle", "{workspace.id}" }
                }
                div { class: "detail-header-actions",
                    if workspace.is_favorite {
                        span { class: "detail-badge favorite", "⭐ Favorite" }
                    }
                }
            }

            // Description
            div { class: "detail-section",
                h3 { class: "detail-section-title", "Description" }
                p { class: "detail-description", "{workspace.description}" }
            }

            // Statistics
            div { class: "detail-section",
                h3 { class: "detail-section-title", "Statistics" }
                div { class: "detail-stats-grid",
                    div { class: "detail-stat-card",
                        span { class: "detail-stat-value", "{workspace.project_count}" }
                        span { class: "detail-stat-label", "Projects" }
                    }
                    if let Some(last_accessed) = workspace.last_accessed {
                        div { class: "detail-stat-card",
                            span { class: "detail-stat-value", "{last_accessed}" }
                            span { class: "detail-stat-label", "Last Accessed" }
                        }
                    }
                }
            }

            // Actions
            div { class: "detail-actions",
                button {
                    class: "btn-primary btn-large",
                    onclick: move |_| on_open_projects.call(()),
                    "📂 Open Projects"
                }
                button {
                    class: "btn-secondary btn-large",
                    onclick: move |_| on_configure.call(()),
                    "⚙️ Configure"
                }
            }
        }
    }
}
