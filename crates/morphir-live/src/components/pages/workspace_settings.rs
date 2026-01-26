//! Workspace settings page.

use dioxus::prelude::*;

use crate::components::settings::SettingsView;
use crate::models::{MorphirConfig, SettingsContext};
use crate::Route;

#[component]
pub fn WorkspaceSettings(id: String) -> Element {
    let nav = navigator();
    let ws_id = id.clone();

    rsx! {
        SettingsView {
            context: SettingsContext::Workspace(id.clone()),
            on_close: {
                let ws_id = ws_id.clone();
                move |_| {
                    nav.push(Route::WorkspaceDetail { id: ws_id.clone() });
                }
            },
            on_save: {
                let ws_id = ws_id.clone();
                move |_config: MorphirConfig| {
                    // TODO: Actually save the config
                    nav.push(Route::WorkspaceDetail { id: ws_id.clone() });
                }
            }
        }
    }
}
