//! Model detail page.

use dioxus::prelude::*;

use crate::components::detail_views::ModelDetailView;
use crate::components::toolbar::{BreadcrumbItem, Toolbar};
use crate::data::{sample_models, sample_projects, sample_workspaces};
use crate::Route;

#[component]
pub fn ModelDetail(workspace_id: String, project_id: String, id: String) -> Element {
    let nav = navigator();

    let all_workspaces = sample_workspaces();
    let workspace = all_workspaces
        .iter()
        .find(|w| w.id == workspace_id)
        .cloned();
    let ws_name = workspace.as_ref().map(|w| w.name.clone()).unwrap_or_default();

    let projects = sample_projects(&workspace_id);
    let project = projects.iter().find(|p| p.id == project_id).cloned();
    let proj_name = project.as_ref().map(|p| p.name.clone()).unwrap_or_default();

    let models = sample_models(&project_id);
    let model = models.iter().find(|m| m.id == id).cloned();

    if let Some(m) = model {
        let model_name = m.name.clone();
        let ws_id = workspace_id.clone();
        let proj_id = project_id.clone();

        let breadcrumbs = vec![
            BreadcrumbItem::new("Workspaces", Route::WorkspaceList {}),
            BreadcrumbItem::new(&ws_name, Route::WorkspaceDetail { id: ws_id.clone() }),
            BreadcrumbItem::new(
                "Projects",
                Route::ProjectList {
                    workspace_id: ws_id.clone(),
                },
            ),
            BreadcrumbItem::new(
                &proj_name,
                Route::ProjectDetail {
                    workspace_id: ws_id.clone(),
                    id: proj_id.clone(),
                },
            ),
            BreadcrumbItem::new(
                "Models",
                Route::ModelList {
                    workspace_id: ws_id.clone(),
                    project_id: proj_id.clone(),
                },
            ),
            BreadcrumbItem::current(&model_name),
        ];

        rsx! {
            Toolbar {
                title: model_name,
                breadcrumbs,
                on_config: move |_| {},
                show_back: true,
                on_back: Some(
                    EventHandler::new({
                        let ws_id = ws_id.clone();
                        let proj_id = proj_id.clone();
                        move |_| {
                            nav.push(Route::ModelList {
                                workspace_id: ws_id.clone(),
                                project_id: proj_id.clone(),
                            });
                        }
                    }),
                ),
            }
            div { class: "content-body",
                ModelDetailView { model: m.clone() }
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
