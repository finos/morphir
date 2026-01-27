//! Try mode page - interactive notebooks and explorations for building Morphir models.

use dioxus::prelude::*;

use crate::models::{Exploration, Notebook, NotebookCellType};

/// Which tab is active in Try mode sidebar.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum TryModeTab {
    #[default]
    Notebooks,
    Explorations,
}

/// Try mode sidebar with Notebooks and Explorations tabs.
#[component]
pub fn TryModeSidebar(
    notebooks: Vec<Notebook>,
    explorations: Vec<Exploration>,
    active_tab: TryModeTab,
    selected_notebook: Option<String>,
    selected_exploration: Option<String>,
    collapsed: bool,
    on_tab_change: EventHandler<TryModeTab>,
    on_select_notebook: EventHandler<String>,
    on_select_exploration: EventHandler<String>,
    on_new_notebook: EventHandler<()>,
    on_new_exploration: EventHandler<()>,
) -> Element {
    if collapsed {
        return rsx! {
            div { class: "try-sidebar collapsed",
                button {
                    class: if active_tab == TryModeTab::Notebooks { "sidebar-icon-btn active" } else { "sidebar-icon-btn" },
                    title: "Notebooks",
                    onclick: move |_| on_tab_change.call(TryModeTab::Notebooks),
                    "📓"
                }
                button {
                    class: if active_tab == TryModeTab::Explorations { "sidebar-icon-btn active" } else { "sidebar-icon-btn" },
                    title: "Explorations",
                    onclick: move |_| on_tab_change.call(TryModeTab::Explorations),
                    "🔬"
                }
                div { class: "sidebar-divider" }
                button {
                    class: "sidebar-icon-btn",
                    title: "New",
                    onclick: move |_| {
                        match active_tab {
                            TryModeTab::Notebooks => on_new_notebook.call(()),
                            TryModeTab::Explorations => on_new_exploration.call(()),
                        }
                    },
                    "+"
                }
            }
        };
    }

    rsx! {
        div { class: "try-sidebar",
            // Tab switcher
            div { class: "try-sidebar-tabs",
                button {
                    class: if active_tab == TryModeTab::Notebooks { "try-tab active" } else { "try-tab" },
                    onclick: move |_| on_tab_change.call(TryModeTab::Notebooks),
                    "📓 Notebooks"
                }
                button {
                    class: if active_tab == TryModeTab::Explorations { "try-tab active" } else { "try-tab" },
                    onclick: move |_| on_tab_change.call(TryModeTab::Explorations),
                    "🔬 Explorations"
                }
            }

            // Content based on active tab
            match active_tab {
                TryModeTab::Notebooks => {
                    rsx! {
                        div { class: "try-sidebar-header",
                            span { "Notebooks" }
                            button {
                                class: "new-item-btn",
                                onclick: move |_| on_new_notebook.call(()),
                                "+"
                            }
                        }
                        div { class: "try-sidebar-list",
                            for notebook in notebooks.iter() {
                                div {
                                    class: if selected_notebook.as_ref() == Some(&notebook.id) { "try-item selected" } else { "try-item" },
                                    onclick: {
                                        let id = notebook.id.clone();
                                        move |_| on_select_notebook.call(id.clone())
                                    },
                                    div { class: "try-item-name", "{notebook.name}" }
                                    div { class: "try-item-meta", "{notebook.updated_at}" }
                                }
                            }
                        }
                    }
                }
                TryModeTab::Explorations => {
                    rsx! {
                        div { class: "try-sidebar-header",
                            span { "Explorations" }
                            button {
                                class: "new-item-btn",
                                onclick: move |_| on_new_exploration.call(()),
                                "+"
                            }
                        }
                        div { class: "try-sidebar-list",
                            for exploration in explorations.iter() {
                                div {
                                    class: if selected_exploration.as_ref() == Some(&exploration.id) { "try-item selected" } else { "try-item" },
                                    onclick: {
                                        let id = exploration.id.clone();
                                        move |_| on_select_exploration.call(id.clone())
                                    },
                                    div { class: "try-item-name", "{exploration.name}" }
                                    div { class: "try-item-meta",
                                        span { class: "language-badge", "{exploration.language.label()}" }
                                        " · {exploration.updated_at}"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Try mode main content - shows either a notebook or exploration.
#[component]
pub fn TryModeContent(
    notebooks: Vec<Notebook>,
    explorations: Vec<Exploration>,
    active_tab: TryModeTab,
    selected_notebook: Option<String>,
    selected_exploration: Option<String>,
) -> Element {
    match active_tab {
        TryModeTab::Notebooks => {
            let selected = selected_notebook
                .as_ref()
                .and_then(|id| notebooks.iter().find(|n| n.id == *id));

            rsx! {
                div { class: "try-mode-content",
                    if let Some(notebook) = selected {
                        NotebookView { notebook: notebook.clone() }
                    } else {
                        EmptyState {
                            icon: "📓",
                            title: "Create a new notebook",
                            description: "Build Morphir models interactively with Jupyter-style notebooks",
                            button_text: "New Notebook",
                        }
                    }
                }
            }
        }
        TryModeTab::Explorations => {
            let selected = selected_exploration
                .as_ref()
                .and_then(|id| explorations.iter().find(|e| e.id == *id));

            rsx! {
                div { class: "try-mode-content",
                    if let Some(exploration) = selected {
                        ExplorationView { exploration: exploration.clone() }
                    } else {
                        EmptyState {
                            icon: "🔬",
                            title: "Create a new exploration",
                            description: "Write Morphir code and see the output in real-time",
                            button_text: "New Exploration",
                        }
                    }
                }
            }
        }
    }
}

/// Empty state component.
#[component]
fn EmptyState(icon: &'static str, title: &'static str, description: &'static str, button_text: &'static str) -> Element {
    rsx! {
        div { class: "empty-state",
            div { class: "empty-icon", "{icon}" }
            h2 { "{title}" }
            p { "{description}" }
            button { class: "btn-primary", "{button_text}" }
        }
    }
}

/// Notebook view - Jupyter-style notebook interface.
#[component]
fn NotebookView(notebook: Notebook) -> Element {
    rsx! {
        div { class: "notebook-container",
            div { class: "notebook-header",
                h1 { class: "notebook-title", "{notebook.name}" }
                p { class: "notebook-description", "{notebook.description}" }
            }
            div { class: "notebook-cells",
                for (idx, cell) in notebook.cells.iter().enumerate() {
                    NotebookCellView {
                        key: "{idx}",
                        cell_type: cell.cell_type,
                        content: cell.content.clone(),
                        output: cell.output.clone(),
                    }
                }
                div { class: "add-cell-container",
                    button { class: "add-cell-btn", "+ Add Cell" }
                }
            }
        }
    }
}

/// A single notebook cell.
#[component]
fn NotebookCellView(cell_type: NotebookCellType, content: String, output: Option<String>) -> Element {
    let cell_class = match cell_type {
        NotebookCellType::Code => "notebook-cell code-cell",
        NotebookCellType::Markdown => "notebook-cell markdown-cell",
    };

    rsx! {
        div { class: "{cell_class}",
            div { class: "cell-toolbar",
                span { class: "cell-type-indicator",
                    match cell_type {
                        NotebookCellType::Code => "Code",
                        NotebookCellType::Markdown => "Markdown",
                    }
                }
                div { class: "cell-actions",
                    button { class: "cell-action-btn", title: "Run cell", "▶" }
                    button { class: "cell-action-btn", title: "Delete cell", "×" }
                }
            }
            div { class: "cell-input",
                textarea {
                    class: "cell-editor",
                    value: "{content}",
                    placeholder: if cell_type == NotebookCellType::Code { "# Write Morphir code here..." } else { "Write documentation..." },
                }
            }
            if let Some(out) = output {
                div { class: "cell-output",
                    pre { "{out}" }
                }
            }
        }
    }
}

/// Exploration view - split-panel code editor with output.
#[component]
fn ExplorationView(exploration: Exploration) -> Element {
    rsx! {
        div { class: "exploration-container",
            // Header
            div { class: "exploration-header",
                div { class: "exploration-title-area",
                    h1 { class: "exploration-title", "{exploration.name}" }
                    span { class: "language-badge large", "{exploration.language.label()}" }
                }
                div { class: "exploration-actions",
                    button { class: "btn-run", "▶ Run" }
                }
            }

            // Split panel
            div { class: "exploration-split",
                // Left: Code editor
                div { class: "exploration-editor-panel",
                    div { class: "panel-header",
                        span { "Source Code" }
                        span { class: "file-ext", "{exploration.language.file_extension()}" }
                    }
                    div { class: "panel-content",
                        textarea {
                            class: "exploration-editor",
                            value: "{exploration.source_code}",
                            spellcheck: false,
                        }
                    }
                }

                // Resizer
                div { class: "exploration-resizer" }

                // Right: Output
                div { class: "exploration-output-panel",
                    div { class: "panel-header",
                        span { "Output" }
                    }
                    div { class: "panel-content",
                        if let Some(output) = &exploration.output {
                            pre { class: "exploration-output", "{output}" }
                        } else {
                            div { class: "output-placeholder",
                                "Run the code to see output"
                            }
                        }
                    }
                }
            }
        }
    }
}

