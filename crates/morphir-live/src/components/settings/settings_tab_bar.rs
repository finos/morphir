//! Settings tab bar component - switches between UI and TOML tabs.

use dioxus::prelude::*;

use crate::models::SettingsTab;

#[component]
pub fn SettingsTabBar(
    active_tab: SettingsTab,
    on_tab_change: EventHandler<SettingsTab>,
) -> Element {
    rsx! {
        div { class: "settings-tabs",
            button {
                class: if active_tab == SettingsTab::UI { "settings-tab active" } else { "settings-tab" },
                onclick: move |_| on_tab_change.call(SettingsTab::UI),
                "🎨 UI"
            }
            button {
                class: if active_tab == SettingsTab::Toml { "settings-tab active" } else { "settings-tab" },
                onclick: move |_| on_tab_change.call(SettingsTab::Toml),
                "📄 TOML"
            }
        }
    }
}
