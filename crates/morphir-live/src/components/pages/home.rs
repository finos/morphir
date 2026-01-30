//! Home page - displays the list of workspaces.

use dioxus::prelude::*;

use crate::Route;
use crate::components::cards::WorkspaceCard;
use crate::components::toolbar::Toolbar;
use crate::data::sample_workspaces;
use crate::models::{Workspace, WorkspaceFilter};

#[component]
pub fn Home() -> Element {
    let nav = navigator();
    let workspace_filter = use_signal(WorkspaceFilter::default);

    let all_workspaces = sample_workspaces();

    let filtered_workspaces: Vec<Workspace> = all_workspaces
        .into_iter()
        .filter(|w| match *workspace_filter.read() {
            WorkspaceFilter::All => true,
            WorkspaceFilter::Recent => w.last_accessed.is_some(),
            WorkspaceFilter::Favorites => w.is_favorite,
        })
        .collect();

    rsx! {
        Toolbar {
            title: "Workspaces".to_string(),
            subtitle: None,
            on_config: move |_| {},
            show_back: false,
            on_back: None
        }
        div { class: "content-body",
            for workspace in filtered_workspaces {
                WorkspaceCard {
                    key: "{workspace.id}",
                    workspace: workspace.clone(),
                    on_open: {
                        let ws_id = workspace.id.clone();
                        move |_: Workspace| {
                            nav.push(Route::WorkspaceDetail { id: ws_id.clone() });
                        }
                    }
                }
            }
        }
    }
}
