//! Model list page.

use dioxus::prelude::*;

use crate::Route;
use crate::components::cards::ModelCard;
use crate::components::toolbar::Toolbar;
use crate::data::{sample_models, sample_projects};
use crate::models::{Model, ModelFilter, ModelType};

#[component]
pub fn ModelList(workspace_id: String, project_id: String) -> Element {
    let nav = navigator();
    let model_filter = use_signal(ModelFilter::default);

    let projects = sample_projects(&workspace_id);
    let project = projects.iter().find(|p| p.id == project_id).cloned();
    let proj_name = project.as_ref().map(|p| p.name.clone()).unwrap_or_default();

    let models: Vec<Model> = sample_models(&project_id)
        .into_iter()
        .filter(|m| match *model_filter.read() {
            ModelFilter::All => true,
            ModelFilter::Types => matches!(m.model_type, ModelType::TypeDefinition),
            ModelFilter::Functions => matches!(m.model_type, ModelType::Function),
        })
        .collect();

    let ws_id = workspace_id.clone();
    let proj_id = project_id.clone();

    rsx! {
        Toolbar {
            title: "Models".to_string(),
            subtitle: Some(proj_name),
            on_config: {
                let ws_id = ws_id.clone();
                let proj_id = proj_id.clone();
                move |_| {
                    nav.push(Route::ProjectSettings {
                        workspace_id: ws_id.clone(),
                        id: proj_id.clone(),
                    });
                }
            },
            show_back: true,
            on_back: Some(EventHandler::new({
                let ws_id = ws_id.clone();
                let proj_id = proj_id.clone();
                move |_| {
                    nav.push(Route::ProjectDetail {
                        workspace_id: ws_id.clone(),
                        id: proj_id.clone(),
                    });
                }
            }))
        }
        div { class: "content-body",
            for model in models {
                ModelCard {
                    key: "{model.id}",
                    model: model.clone(),
                    on_open: {
                        let model_id = model.id.clone();
                        let ws_id = ws_id.clone();
                        let proj_id = proj_id.clone();
                        move |_: Model| {
                            nav.push(Route::ModelDetail {
                                workspace_id: ws_id.clone(),
                                project_id: proj_id.clone(),
                                id: model_id.clone(),
                            });
                        }
                    }
                }
            }
        }
    }
}
