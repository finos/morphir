//! Project detail page.

use dioxus::prelude::*;

use crate::Route;
use crate::components::detail_views::ProjectDetailView;
use crate::components::toolbar::Toolbar;
use crate::data::sample_projects;

#[component]
pub fn ProjectDetail(workspace_id: String, id: String) -> Element {
    let nav = navigator();

    let projects = sample_projects(&workspace_id);
    let project = projects.iter().find(|p| p.id == id).cloned();

    if let Some(proj) = project {
        let proj_name = proj.name.clone();
        let proj_id = proj.id.clone();
        let ws_id = workspace_id.clone();

        rsx! {
            Toolbar {
                title: proj_name,
                subtitle: Some("Project".to_string()),
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
                    move |_| {
                        nav.push(Route::ProjectList { workspace_id: ws_id.clone() });
                    }
                }))
            }
            div { class: "content-body",
                ProjectDetailView {
                    project: proj.clone(),
                    on_open_models: {
                        let ws_id = ws_id.clone();
                        let proj_id = proj_id.clone();
                        move |_| {
                            nav.push(Route::ModelList {
                                workspace_id: ws_id.clone(),
                                project_id: proj_id.clone(),
                            });
                        }
                    },
                    on_configure: {
                        let ws_id = ws_id.clone();
                        let proj_id = proj_id.clone();
                        move |_| {
                            nav.push(Route::ProjectSettings {
                                workspace_id: ws_id.clone(),
                                id: proj_id.clone(),
                            });
                        }
                    }
                }
            }
        }
    } else {
        rsx! {
            div { class: "not-found",
                h2 { "Project not found" }
                p { "The project with ID \"{id}\" does not exist." }
            }
        }
    }
}
