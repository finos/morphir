//! Upload button component for importing Morphir files.

use dioxus::prelude::*;

use crate::models::UploadedFile;

/// Upload button for importing Morphir files.
///
/// Supports: morphir-ir.json, morphir.json, morphir.toml, and .tgz files.
#[component]
pub fn UploadButton(on_upload: EventHandler<UploadedFile>) -> Element {
    let mut show_menu = use_signal(|| false);

    rsx! {
        div { class: "upload-button-container",
            button {
                class: "upload-btn",
                onclick: move |_| show_menu.toggle(),
                "↑ Upload"
            }
            if *show_menu.read() {
                div { class: "upload-menu dropdown-menu",
                    div { class: "upload-menu-header",
                        "Import Morphir files"
                    }
                    div { class: "upload-menu-hint",
                        "Supported formats:"
                    }
                    div { class: "upload-format-list",
                        div { class: "upload-format", "• morphir-ir.json" }
                        div { class: "upload-format", "• morphir.json" }
                        div { class: "upload-format", "• morphir.toml" }
                        div { class: "upload-format", "• .tgz (v4 model)" }
                    }
                    div { class: "upload-menu-actions",
                        button {
                            class: "btn-primary",
                            onclick: move |_| {
                                // TODO: Integrate with file picker when library types are provided
                                // For now, show a placeholder message
                                show_menu.set(false);
                            },
                            "Choose file..."
                        }
                    }
                    div { class: "upload-menu-note",
                        "File handling will be integrated with Morphir libraries"
                    }
                }
            }
        }
    }
}
