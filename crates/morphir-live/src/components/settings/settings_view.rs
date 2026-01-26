//! Main settings view component that contains tabs and handles save/cancel.

use dioxus::prelude::*;

use crate::models::{MorphirConfig, SettingsContext, SettingsTab};

use super::settings_tab_bar::SettingsTabBar;
use super::settings_toml_tab::SettingsTomlTab;
use super::settings_ui_tab::SettingsUITab;

#[component]
pub fn SettingsView(
    context: SettingsContext,
    on_close: EventHandler<()>,
    on_save: EventHandler<MorphirConfig>,
) -> Element {
    // State for the active tab
    let mut active_tab = use_signal(SettingsTab::default);

    // State for the configuration (would be loaded from actual config in real app)
    let mut config = use_signal(MorphirConfig::default);

    // State for TOML content (synced with config)
    let mut toml_content = use_signal(|| {
        config
            .read()
            .to_toml()
            .unwrap_or_else(|_| "# Error generating TOML".to_string())
    });

    // Track if there are unsaved changes
    let mut has_changes = use_signal(|| false);

    // Determine the title based on context
    let title = match &context {
        SettingsContext::Workspace(id) => format!("Workspace Settings: {}", id),
        SettingsContext::Project(id) => format!("Project Settings: {}", id),
    };

    // Handle config change from UI tab
    let handle_config_change = move |new_config: MorphirConfig| {
        config.set(new_config.clone());
        // Sync TOML content
        if let Ok(toml) = new_config.to_toml() {
            toml_content.set(toml);
        }
        has_changes.set(true);
    };

    // Handle TOML content change
    let handle_toml_change = move |new_toml: String| {
        toml_content.set(new_toml.clone());
        // Try to parse and sync config
        if let Ok(new_config) = MorphirConfig::from_toml(&new_toml) {
            config.set(new_config);
        }
        has_changes.set(true);
    };

    // Handle save
    let handle_save = move |_| {
        on_save.call(config.read().clone());
    };

    rsx! {
        div { class: "settings-view",
            // Header
            div { class: "settings-header",
                div { class: "settings-header-left",
                    button {
                        class: "settings-back-btn",
                        onclick: move |_| on_close.call(()),
                        "← Back"
                    }
                    h2 { class: "settings-title", "{title}" }
                }
                div { class: "settings-header-right",
                    if *has_changes.read() {
                        span { class: "settings-unsaved-indicator", "• Unsaved changes" }
                    }
                    button {
                        class: "btn-secondary",
                        onclick: move |_| on_close.call(()),
                        "Cancel"
                    }
                    button {
                        class: "btn-primary",
                        onclick: handle_save,
                        "Save"
                    }
                }
            }

            // Tab bar
            SettingsTabBar {
                active_tab: active_tab.read().clone(),
                on_tab_change: move |tab| active_tab.set(tab)
            }

            // Tab content
            div { class: "settings-content",
                match *active_tab.read() {
                    SettingsTab::UI => rsx! {
                        SettingsUITab {
                            config: config.read().clone(),
                            on_change: handle_config_change
                        }
                    },
                    SettingsTab::Toml => rsx! {
                        SettingsTomlTab {
                            content: toml_content.read().clone(),
                            on_change: handle_toml_change
                        }
                    },
                }
            }
        }
    }
}
