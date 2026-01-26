//! Workspace detail page.

use dioxus::prelude::*;

use crate::components::detail_views::WorkspaceDetailView;
use crate::components::toolbar::{BreadcrumbItem, Toolbar};
use crate::data::sample_workspaces;
use crate::Route;

#[component]
pub fn WorkspaceDetail(id: String) -> Element {
    let nav = navigator();

    let all_workspaces = sample_workspaces();
    let workspace = all_workspaces.iter().find(|w| w.id == id).cloned();

    if let Some(ws) = workspace {
        let ws_name = ws.name.clone();
        let ws_id = ws.id.clone();

        let breadcrumbs = vec![
            BreadcrumbItem::new("Workspaces", Route::Home {}),
            BreadcrumbItem::current(&ws_name),
        ];

        rsx! {
            Toolbar {
                title: ws_name,
                breadcrumbs,
                on_config: {
                    let ws_id = ws_id.clone();
                    move |_| {
                        nav.push(Route::WorkspaceSettings {
                            id: ws_id.clone(),
                        });
                    }
                },
                show_back: true,
                on_back: Some(
                    EventHandler::new(move |_| {
                        nav.push(Route::Home {});
                    }),
                ),
            }
            div { class: "content-body",
                WorkspaceDetailView {
                    workspace: ws.clone(),
                    on_open_projects: {
                        let ws_id = ws_id.clone();
                        move |_| {
                            nav.push(Route::ProjectList {
                                workspace_id: ws_id.clone(),
                            });
                        }
                    },
                    on_configure: {
                        let ws_id = ws_id.clone();
                        move |_| {
                            nav.push(Route::WorkspaceSettings {
                                id: ws_id.clone(),
                            });
                        }
                    },
                }
            }
        }
    } else {
        rsx! {
            div { class: "not-found",
                h2 { "Workspace not found" }
                p { "The workspace with ID \"{id}\" does not exist." }
            }
        }
    }
}
