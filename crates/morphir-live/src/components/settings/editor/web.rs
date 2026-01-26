//! Monaco Editor component for web platform with TOML syntax highlighting.

use crate::monaco;
use dioxus::prelude::*;
use wasm_bindgen::JsValue;

/// Check if the TOML editor has been initialized via JS global flag.
fn is_editor_initialized_js() -> bool {
    let window = web_sys::window().expect("no global window");
    let value = js_sys::Reflect::get(&window, &JsValue::from_str("__tomlEditorInitialized"))
        .unwrap_or(JsValue::FALSE);
    value.as_bool().unwrap_or(false)
}

/// Monaco-based TOML editor for web platform.
/// Provides full syntax highlighting, line numbers, and code editing features.
#[component]
pub fn TomlEditor(content: String, on_change: EventHandler<String>) -> Element {
    let mut editor_initialized = use_signal(|| false);
    let mut polling_started = use_signal(|| false);
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

            // Initialize the editor and set a global flag for reliable detection
            let init_script = format!(
                r#"
                (function() {{
                    const container = document.getElementById('toml-editor-container');
                    if (!container) {{
                        console.error('Monaco container not found: toml-editor-container');
                        window.__tomlEditorInitialized = false;
                        return;
                    }}

                    // Initialize the editor with content
                    const content = {content_json};
                    const editor = window.initMonacoEditor('toml-editor-container', content, 'toml');

                    // Set global flag for Rust to check via web_sys
                    window.__tomlEditorInitialized = !!editor;
                }})()
                "#,
                content_json =
                    serde_json::to_string(&content).unwrap_or_else(|_| "\"\"".to_string()),
            );

            // Execute the init script (don't rely on return value)
            let _ = document::eval(&init_script).await;

            // Check the global flag via web_sys instead of eval return value
            if is_editor_initialized_js() {
                editor_initialized.set(true);
            }
        });
    });

    // Set up change polling when editor is initialized
    use_effect(move || {
        // Only start polling once, and only after editor is initialized
        if !*editor_initialized.read() || *polling_started.read() {
            return;
        }

        // Mark polling as started to prevent duplicate loops
        polling_started.set(true);

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
        div { id: "{container_id}", class: "monaco-editor-container",
            // Show loading state while Monaco is initializing
            if !monaco_ready {
                div { class: "monaco-loading", "Loading editor..." }
            }
        }
    }
}
