//! Model detail view component.

use dioxus::prelude::*;

use crate::models::{Model, ModelType};

#[component]
pub fn ModelDetailView(model: Model) -> Element {
    let type_icon = match model.model_type {
        ModelType::TypeDefinition => "📐",
        ModelType::Function => "⚡",
    };

    let type_label = match model.model_type {
        ModelType::TypeDefinition => "Type Definition",
        ModelType::Function => "Function",
    };

    rsx! {
        div { class: "detail-view",
            // Header
            div { class: "detail-header",
                div { class: "detail-avatar", "{type_icon}" }
                div { class: "detail-info",
                    h1 { class: "detail-title", "{model.name}" }
                    p { class: "detail-subtitle", "{model.id}" }
                }
                div { class: "detail-header-actions",
                    span { class: "detail-badge model-type", "{type_label}" }
                }
            }

            // Description
            div { class: "detail-section",
                h3 { class: "detail-section-title", "Description" }
                p { class: "detail-description", "{model.description}" }
            }

            // Statistics
            div { class: "detail-section",
                h3 { class: "detail-section-title", "Statistics" }
                div { class: "detail-stats-grid",
                    div { class: "detail-stat-card",
                        span { class: "detail-stat-value", "{model.type_count}" }
                        span { class: "detail-stat-label", "Types" }
                    }
                    div { class: "detail-stat-card",
                        span { class: "detail-stat-value", "{model.function_count}" }
                        span { class: "detail-stat-label", "Functions" }
                    }
                }
            }

            // Model Definition placeholder
            div { class: "detail-section",
                h3 { class: "detail-section-title", "Definition" }
                div { class: "model-definition",
                    pre { class: "code-block",
                        code {
                            match model.model_type {
                                ModelType::TypeDefinition => rsx! {
                                    "type {model.name} = \n    {{ -- Type definition here }}"
                                },
                                ModelType::Function => rsx! {
                                    "{model.name} : Input -> Output\n{model.name} input =\n    -- Function body here"
                                },
                            }
                        }
                    }
                }
            }
        }
    }
}
