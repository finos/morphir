//! Project settings page.

use dioxus::prelude::*;

use crate::components::settings::SettingsView;
use crate::models::{MorphirConfig, SettingsContext};
use crate::Route;

#[component]
pub fn ProjectSettings(workspace_id: String, id: String) -> Element {
    let nav = navigator();
    let ws_id = workspace_id.clone();
    let proj_id = id.clone();

    rsx! {
        SettingsView {
            context: SettingsContext::Project(id.clone()),
            on_close: {
                let ws_id = ws_id.clone();
                let proj_id = proj_id.clone();
                move |_| {
                    nav.push(Route::ProjectDetail {
                        workspace_id: ws_id.clone(),
                        id: proj_id.clone(),
                    });
                }
            },
            on_save: {
                let ws_id = ws_id.clone();
                let proj_id = proj_id.clone();
                move |_config: MorphirConfig| {
                    // TODO: Actually save the config
                    nav.push(Route::ProjectDetail {
                        workspace_id: ws_id.clone(),
                        id: proj_id.clone(),
                    });
                }
            }
        }
    }
}
