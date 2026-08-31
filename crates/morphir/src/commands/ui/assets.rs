//! Exact static assets served by the loopback host.

pub struct EmbeddedAsset {
    pub bytes: &'static [u8],
    pub content_type: &'static str,
    pub immutable: bool,
}

include!("assets/embedded.rs");

pub fn asset(path: &str) -> Option<EmbeddedAsset> {
    generated_asset(if path.is_empty() { "index.html" } else { path })
}
