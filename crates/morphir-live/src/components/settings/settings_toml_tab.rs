//! TOML editor tab for direct configuration editing with Monaco Editor.

use dioxus::prelude::*;
use super::monaco_editor::MonacoEditor;

/// TOML editor using Monaco Editor for syntax highlighting
#[component]
pub fn SettingsTomlTab(
    content: String,
    on_change: EventHandler<String>,
) -> Element {
    rsx! {
        div { class: "settings-toml-tab",
            div { class: "toml-editor-header",
                span { class: "toml-editor-title", "morphir.toml" }
                span { class: "toml-editor-hint", "Edit configuration directly in TOML format" }
            }
            div { class: "toml-editor-wrapper",
                MonacoEditor {
                    container_id: "monaco-toml-editor".to_string(),
                    content: content,
                    on_change: on_change,
                }
            }
        }
    }
}
