//! TOML editor tab for direct configuration editing.
//! Uses Monaco Editor on web, syntect-based highlighting on desktop.

use super::editor::TomlEditor;
use dioxus::prelude::*;

/// TOML editor tab with platform-specific syntax highlighting.
/// - Web: Monaco Editor with full IDE features
/// - Desktop: Syntect-based highlighting with live preview
#[component]
pub fn SettingsTomlTab(content: String, on_change: EventHandler<String>) -> Element {
    rsx! {
        div { class: "settings-toml-tab",
            div { class: "toml-editor-header",
                span { class: "toml-editor-title", "morphir.toml" }
                span { class: "toml-editor-hint", "Edit configuration directly in TOML format" }
            }
            div { class: "toml-editor-wrapper",
                TomlEditor { content, on_change }
            }
        }
    }
}
