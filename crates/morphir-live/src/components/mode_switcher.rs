//! Mode switcher component for toggling between Spaces and Try modes.

use dioxus::prelude::*;

/// The application mode.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum AppMode {
    /// Spaces mode - browse workspaces, projects, and models
    #[default]
    Spaces,
    /// Try mode - interactive notebook for building Morphir models
    Try,
}

impl AppMode {
    /// Get the display label for this mode.
    #[allow(dead_code)]
    pub fn label(&self) -> &'static str {
        match self {
            AppMode::Spaces => "Spaces",
            AppMode::Try => "Try",
        }
    }
}

/// Mode switcher toggle component.
#[component]
pub fn ModeSwitcher(current_mode: AppMode, on_change: EventHandler<AppMode>) -> Element {
    rsx! {
        div { class: "mode-switcher",
            button {
                class: if current_mode == AppMode::Spaces { "mode-btn active" } else { "mode-btn" },
                onclick: move |_| on_change.call(AppMode::Spaces),
                "Spaces"
            }
            button {
                class: if current_mode == AppMode::Try { "mode-btn active" } else { "mode-btn" },
                onclick: move |_| on_change.call(AppMode::Try),
                "Try"
            }
        }
    }
}
