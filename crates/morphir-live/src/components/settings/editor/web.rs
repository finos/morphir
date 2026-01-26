//! Monaco Editor component for web platform with TOML syntax highlighting.

use crate::monaco;
use dioxus::prelude::*;

/// Monaco-based TOML editor for web platform.
/// Provides full syntax highlighting, line numbers, and code editing features.
#[component]
pub fn TomlEditor(content: String, on_change: EventHandler<String>) -> Element {
    let mut editor_initialized = use_signal(|| false);
    let mut pending_content = use_signal(|| content.clone());

    // Check global Monaco ready state
    let monaco_ready = monaco::use_monaco_ready();

    // Use a fixed container ID for the TOML editor
    let container_id = "toml-editor-container";

    // Effect to initialize the editor instance when Monaco is ready
    use_effect(move || {
        // Only proceed if Monaco is globally ready and we haven't initialized this editor yet
        if !monaco_ready || *editor_initialized.read() {
            return;
        }

        let content = content.clone();

        spawn(async move {
            // Small delay to ensure the DOM element is rendered
            gloo_timers::future::TimeoutFuture::new(50).await;

            // Initialize the editor
            let init_script = format!(
                r#"
                (function() {{
                    const container = document.getElementById('toml-editor-container');
                    if (!container) {{
                        console.error('Monaco container not found: toml-editor-container');
                        return false;
                    }}

                    // Initialize the editor with content
                    const content = {content_json};
                    const editor = window.initMonacoEditor('toml-editor-container', content, 'toml');

                    if (editor) {{
                        return true;
                    }}
                    return false;
                }})()
                "#,
                content_json =
                    serde_json::to_string(&content).unwrap_or_else(|_| "\"\"".to_string()),
            );

            let result = document::eval(&init_script);
            if let Ok(value) = result.await {
                if let Some(success) = value.as_bool() {
                    if success {
                        editor_initialized.set(true);
                    }
                }
            }
        });
    });

    // Set up change polling when editor is initialized
    use_effect(move || {
        if !*editor_initialized.read() {
            return;
        }

        let on_change = on_change.clone();
        let mut last_content = pending_content.read().clone();

        spawn(async move {
            loop {
                gloo_timers::future::TimeoutFuture::new(500).await;

                let get_content_script = "window.getMonacoContent('toml-editor-container')";

                let result = document::eval(get_content_script);
                if let Ok(value) = result.await {
                    if let Some(new_content) = value.as_str() {
                        if new_content != last_content {
                            last_content = new_content.to_string();
                            pending_content.set(new_content.to_string());
                            on_change.call(new_content.to_string());
                        }
                    }
                }
            }
        });
    });

    rsx! {
        div {
            id: "{container_id}",
            class: "monaco-editor-container",
            // Show loading state while Monaco is initializing
            if !monaco_ready {
                div { class: "monaco-loading",
                    "Loading editor..."
                }
            }
        }
    }
}
