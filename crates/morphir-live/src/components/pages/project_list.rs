//! Project list page.

use dioxus::prelude::*;

use crate::components::cards::ProjectCard;
use crate::components::toolbar::Toolbar;
use crate::data::{sample_projects, sample_workspaces};
use crate::models::{Project, ProjectFilter};
use crate::Route;

#[component]
pub fn ProjectList(workspace_id: String) -> Element {
    let nav = navigator();
    let project_filter = use_signal(ProjectFilter::default);

    let all_workspaces = sample_workspaces();
    let workspace = all_workspaces.iter().find(|w| w.id == workspace_id).cloned();
    let ws_name = workspace.as_ref().map(|w| w.name.clone()).unwrap_or_default();

    let projects: Vec<Project> = sample_projects(&workspace_id)
        .into_iter()
        .filter(|p| match *project_filter.read() {
            ProjectFilter::All => true,
            ProjectFilter::Active => p.is_active,
            ProjectFilter::Archived => !p.is_active,
        })
        .collect();

    let ws_id = workspace_id.clone();

    rsx! {
        Toolbar {
            title: "Projects".to_string(),
            subtitle: Some(ws_name),
            on_config: {
                let ws_id = ws_id.clone();
                move |_| {
                    nav.push(Route::WorkspaceSettings { id: ws_id.clone() });
                }
            },
            show_back: true,
            on_back: Some(EventHandler::new({
                let ws_id = ws_id.clone();
                move |_| {
                    nav.push(Route::WorkspaceDetail { id: ws_id.clone() });
                }
            }))
        }
        div { class: "content-body",
            for project in projects {
                ProjectCard {
                    key: "{project.id}",
                    project: project.clone(),
                    on_open: {
                        let proj_id = project.id.clone();
                        let ws_id = ws_id.clone();
                        move |_: Project| {
                            nav.push(Route::ProjectDetail {
                                workspace_id: ws_id.clone(),
                                id: proj_id.clone(),
                            });
                        }
                    }
                }
            }
        }
    }
}
