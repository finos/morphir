//! Monaco Editor component with JavaScript interop for TOML editing.
//! Falls back to a textarea on non-web platforms.

use dioxus::prelude::*;

#[cfg(target_arch = "wasm32")]
use crate::monaco;

/// Monaco Editor component that provides syntax highlighting for TOML.
/// On web, uses Monaco Editor with full syntax highlighting.
/// On desktop/mobile, falls back to a simple textarea.
#[component]
pub fn MonacoEditor(
    container_id: String,
    content: String,
    on_change: EventHandler<String>,
) -> Element {
    // Use conditional compilation for web vs desktop
    #[cfg(target_arch = "wasm32")]
    {
        monaco_editor_web(container_id, content, on_change)
    }

    #[cfg(not(target_arch = "wasm32"))]
    {
        monaco_editor_fallback(content, on_change)
    }
}

/// Fallback textarea editor for desktop/mobile platforms
#[cfg(not(target_arch = "wasm32"))]
fn monaco_editor_fallback(
    content: String,
    on_change: EventHandler<String>,
) -> Element {
    rsx! {
        textarea {
            class: "toml-editor",
            value: "{content}",
            spellcheck: false,
            oninput: move |e| on_change.call(e.value())
        }
    }
}

/// Monaco Editor for web platform with full syntax highlighting
#[cfg(target_arch = "wasm32")]
fn monaco_editor_web(
    container_id: String,
    content: String,
    on_change: EventHandler<String>,
) -> Element {
    let mut editor_initialized = use_signal(|| false);
    let mut pending_content = use_signal(|| content.clone());

    // Check global Monaco ready state
    let monaco_ready = monaco::use_monaco_ready();

    // Clone container_id for use in multiple closures and rsx
    let container_id_init = container_id.clone();
    let container_id_poll = container_id.clone();
    let container_id_render = container_id.clone();

    // Effect to initialize the editor instance when Monaco is ready
    use_effect(move || {
        // Only proceed if Monaco is globally ready and we haven't initialized this editor yet
        if !monaco_ready || *editor_initialized.read() {
            return;
        }

        let container_id = container_id_init.clone();
        let content = content.clone();

        spawn(async move {
            // Small delay to ensure the DOM element is rendered
            gloo_timers::future::TimeoutFuture::new(50).await;

            // Initialize the editor
            let init_script = format!(
                r#"
                (function() {{
                    const container = document.getElementById('{container_id}');
                    if (!container) {{
                        console.error('Monaco container not found:', '{container_id}');
                        return false;
                    }}

                    // Initialize the editor with content
                    const content = {content_json};
                    const editor = window.initMonacoEditor('{container_id}', content, 'toml');

                    if (editor) {{
                        return true;
                    }}
                    return false;
                }})()
                "#,
                container_id = container_id,
                content_json = serde_json::to_string(&content).unwrap_or_else(|_| "\"\"".to_string()),
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

        let container_id = container_id_poll.clone();
        let on_change = on_change.clone();
        let mut last_content = pending_content.read().clone();

        spawn(async move {
            loop {
                gloo_timers::future::TimeoutFuture::new(500).await;

                let get_content_script = format!(
                    r#"window.getMonacoContent('{}')"#,
                    container_id
                );

                let result = document::eval(&get_content_script);
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
            id: "{container_id_render}",
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
