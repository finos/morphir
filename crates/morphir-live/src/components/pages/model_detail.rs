//! Model detail page.

use dioxus::prelude::*;

use crate::components::detail_views::ModelDetailView;
use crate::components::toolbar::Toolbar;
use crate::data::sample_models;
use crate::Route;

#[component]
pub fn ModelDetail(workspace_id: String, project_id: String, id: String) -> Element {
    let nav = navigator();

    let models = sample_models(&project_id);
    let model = models.iter().find(|m| m.id == id).cloned();

    if let Some(m) = model {
        let model_name = m.name.clone();
        let ws_id = workspace_id.clone();
        let proj_id = project_id.clone();

        rsx! {
            Toolbar {
                title: model_name,
                subtitle: Some("Model".to_string()),
                on_config: move |_| {},
                show_back: true,
                on_back: Some(EventHandler::new({
                    let ws_id = ws_id.clone();
                    let proj_id = proj_id.clone();
                    move |_| {
                        nav.push(Route::ModelList {
                            workspace_id: ws_id.clone(),
                            project_id: proj_id.clone(),
                        });
                    }
                }))
            }
            div { class: "content-body",
                ModelDetailView {
                    model: m.clone()
                }
            }
        }
    } else {
        rsx! {
            div { class: "not-found",
                h2 { "Model not found" }
                p { "The model with ID \"{id}\" does not exist." }
            }
        }
    }
}
