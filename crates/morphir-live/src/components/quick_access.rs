//! Quick access tabs component.

use dioxus::prelude::*;

/// Tab options for quick access filtering.
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub enum QuickAccessTab {
    #[default]
    Recent,
    Favorites,
}

/// Tab bar for switching between Recent and Favorites views.
#[component]
pub fn QuickAccessTabs(
    active_tab: QuickAccessTab,
    on_tab_change: EventHandler<QuickAccessTab>,
) -> Element {
    rsx! {
        div { class: "quick-access-tabs",
            button {
                class: if active_tab == QuickAccessTab::Recent { "quick-access-tab active" } else { "quick-access-tab" },
                onclick: move |_| on_tab_change.call(QuickAccessTab::Recent),
                "Recent"
            }
            button {
                class: if active_tab == QuickAccessTab::Favorites { "quick-access-tab active" } else { "quick-access-tab" },
                onclick: move |_| on_tab_change.call(QuickAccessTab::Favorites),
                "Favorites"
            }
        }
    }
}
