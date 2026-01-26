//! Global Monaco Editor state management.
//! Handles async initialization on app startup and provides ready state.

#[cfg(target_arch = "wasm32")]
use dioxus::prelude::*;

/// Global signal tracking whether Monaco Editor is ready
#[cfg(target_arch = "wasm32")]
static MONACO_READY: GlobalSignal<bool> = Signal::global(|| false);

/// Check if Monaco is ready (always false on non-web platforms)
#[cfg(target_arch = "wasm32")]
pub fn is_monaco_ready() -> bool {
    *MONACO_READY.read()
}

#[cfg(not(target_arch = "wasm32"))]
pub fn is_monaco_ready() -> bool {
    false
}

/// Initialize Monaco Editor asynchronously on app startup.
/// This should be called once from the App component.
#[cfg(target_arch = "wasm32")]
pub fn init_monaco_on_startup() {
    spawn(async move {
        // Check if already initialized
        if *MONACO_READY.read() {
            return;
        }

        // Poll until Monaco is ready (max 10 seconds)
        // We check window.monacoReady which is set by our JS code after Monaco loads
        for i in 0..100 {
            // Use js_sys to check the global flag directly
            if check_monaco_ready_js() {
                *MONACO_READY.write() = true;
                let _ = document::eval("console.log('[Rust] Monaco Editor ready!')");
                return;
            }

            // Log progress every 2 seconds
            if i > 0 && i % 20 == 0 {
                let _ = document::eval(&format!(
                    "console.log('[Rust] Waiting for Monaco... {}s')",
                    i / 10
                ));
            }

            gloo_timers::future::TimeoutFuture::new(100).await;
        }

        let _ = document::eval("console.warn('[Rust] Monaco initialization timed out')");
    });
}

/// Check if Monaco is ready by reading window.monacoReady directly using js_sys
#[cfg(target_arch = "wasm32")]
fn check_monaco_ready_js() -> bool {
    use js_sys::Reflect;
    use wasm_bindgen::JsValue;

    // Get the window object
    let window = match web_sys::window() {
        Some(w) => w,
        None => return false,
    };

    // Get window.monacoReady
    let key = JsValue::from_str("monacoReady");
    match Reflect::get(&window, &key) {
        Ok(value) => value.as_bool().unwrap_or(false),
        Err(_) => false,
    }
}

/// No-op on non-web platforms
#[cfg(not(target_arch = "wasm32"))]
pub fn init_monaco_on_startup() {
    // Monaco is only available on web
}

/// Subscribe to Monaco ready state changes (web only)
#[cfg(target_arch = "wasm32")]
pub fn use_monaco_ready() -> bool {
    *MONACO_READY.read()
}

#[cfg(not(target_arch = "wasm32"))]
pub fn use_monaco_ready() -> bool {
    false
}
