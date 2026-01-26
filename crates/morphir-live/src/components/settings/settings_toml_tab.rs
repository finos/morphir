//! TOML editor tab for direct configuration editing.

use dioxus::prelude::*;

/// TOML editor using a textarea (Monaco can be integrated later)
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
            div { class: "toml-editor-container",
                textarea {
                    class: "toml-editor",
                    value: "{content}",
                    spellcheck: false,
                    oninput: move |e| on_change.call(e.value())
                }
            }
        }
    }
}
