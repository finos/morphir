//! Project detail view component.

use dioxus::prelude::*;

use crate::models::Project;

#[component]
pub fn ProjectDetailView(
    project: Project,
    on_open_models: EventHandler<()>,
    on_configure: EventHandler<()>,
) -> Element {
    rsx! {
        div { class: "detail-view",
            // Header
            div { class: "detail-header",
                div { class: "detail-avatar", "📂" }
                div { class: "detail-info",
                    h1 { class: "detail-title", "{project.name}" }
                    p { class: "detail-subtitle", "{project.id}" }
                }
                div { class: "detail-header-actions",
                    if project.is_active {
                        span { class: "detail-badge active", "▶️ Active" }
                    } else {
                        span { class: "detail-badge archived", "📦 Archived" }
                    }
                }
            }

            // Description
            div { class: "detail-section",
                h3 { class: "detail-section-title", "Description" }
                p { class: "detail-description", "{project.description}" }
            }

            // Statistics
            div { class: "detail-section",
                h3 { class: "detail-section-title", "Statistics" }
                div { class: "detail-stats-grid",
                    div { class: "detail-stat-card",
                        span { class: "detail-stat-value", "{project.model_count}" }
                        span { class: "detail-stat-label", "Models" }
                    }
                }
            }

            // Actions
            div { class: "detail-actions",
                button {
                    class: "btn-primary btn-large",
                    onclick: move |_| on_open_models.call(()),
                    "🧊 Open Models"
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
