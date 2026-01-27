//! Workspace list page - shows all available workspaces.

use dioxus::prelude::*;

use crate::components::cards::WorkspaceCard;
use crate::components::toolbar::{BreadcrumbItem, Toolbar};
use crate::data::sample_workspaces;
use crate::models::Workspace;
use crate::Route;

#[component]
pub fn WorkspaceList() -> Element {
    let nav = navigator();

    let workspaces: Vec<Workspace> = sample_workspaces();

    let breadcrumbs = vec![BreadcrumbItem::current("Workspaces")];

    rsx! {
        Toolbar {
            title: "Workspaces".to_string(),
            breadcrumbs,
            on_config: move |_| {},
            show_back: false,
            on_back: None,
        }
        div { class: "content-body",
            for workspace in workspaces {
                WorkspaceCard {
                    key: "{workspace.id}",
                    workspace: workspace.clone(),
                    on_open: {
                        let ws_id = workspace.id.clone();
                        move |_: Workspace| {
                            nav.push(Route::WorkspaceDetail {
                                id: ws_id.clone(),
                            });
                        }
                    },
                }
            }
        }
    }
}
