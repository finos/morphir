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

/// Reads the connected protocol version that the vendored client pins in the
/// minified bundle.
///
/// The bundle declares several unrelated protocol versions — the WASM engine's
/// discovery request and the workspace snapshot each carry one — so a bare
/// search for `protocolVersion` would read the wrong number. Each occurrence is
/// instead anchored on the field that follows it in the object literal, which
/// is what makes the match specific to the connected session protocol.
#[cfg(test)]
fn pinned_protocol_version(source: &str, following_field: &str) -> Option<u32> {
    const NEEDLE: &str = "protocolVersion:";
    source
        .match_indices(NEEDLE)
        .filter_map(|(index, _)| {
            let tail = &source[index + NEEDLE.len()..];
            // A schema literal reads `protocolVersion:<helper>(1)`; a value the
            // client sends reads `protocolVersion:1`. The helper's name is
            // chosen by the minifier and differs between builds, so match any
            // identifier rather than one build's spelling.
            let helper = tail
                .find('(')
                .filter(|open| {
                    tail[..*open]
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '$')
                })
                .filter(|open| *open > 0);
            let (digits, tail) = match helper {
                Some(open) => {
                    let inner = &tail[open + 1..];
                    let end = inner.find(')')?;
                    (&inner[..end], &inner[end + 1..])
                }
                None => {
                    let end = tail.find(|character: char| !character.is_ascii_digit())?;
                    (&tail[..end], &tail[end..])
                }
            };
            if !tail.strip_prefix(',')?.starts_with(following_field) {
                return None;
            }
            digits.parse().ok()
        })
        .next()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::ui::protocol::CONNECTED_PROTOCOL_VERSION;

    fn entry_bundle() -> String {
        let index = asset("index.html").expect("the vendored bundle must serve index.html");
        let html = std::str::from_utf8(index.bytes).expect("index.html must be UTF-8");
        let (_, tail) = html
            .split_once("src=\"/")
            .expect("index.html must load the entry script from a rooted path");
        let (path, _) = tail
            .split_once('"')
            .expect("the entry script src must be quoted");
        let bundle = asset(path)
            .unwrap_or_else(|| panic!("index.html loads {path}, which the host does not serve"));
        String::from_utf8(bundle.bytes.to_vec()).expect("the entry bundle must be UTF-8")
    }

    /// The CLI serves a checked-in, pre-built client. Nothing in the build
    /// forces that bundle to agree with the server, so a protocol bump made
    /// without vendoring a matching bundle silently breaks every session: the
    /// client rejects the manifest and the window never connects. This test is
    /// the only thing that ties the two together.
    #[test]
    fn the_vendored_bundle_pins_the_served_protocol_version() {
        let bundle = entry_bundle();

        let manifest_version = pinned_protocol_version(&bundle, "webSocketPath").expect(
            "no session-manifest protocolVersion found in the vendored bundle; the minified \
             shape changed and this guard must be reworked, not deleted",
        );
        let initialize_version = pinned_protocol_version(&bundle, "sessionId").expect(
            "no session.initialize protocolVersion found in the vendored bundle; the minified \
             shape changed and this guard must be reworked, not deleted",
        );

        assert_eq!(
            manifest_version, CONNECTED_PROTOCOL_VERSION,
            "the vendored bundle validates the session manifest against protocol version \
             {manifest_version}, but the host serves {CONNECTED_PROTOCOL_VERSION}; bump the \
             constant only in the change that vendors a matching bundle"
        );
        assert_eq!(
            initialize_version, CONNECTED_PROTOCOL_VERSION,
            "the vendored bundle sends protocol version {initialize_version} in \
             morphir.session.initialize, but the host accepts only \
             {CONNECTED_PROTOCOL_VERSION}"
        );
    }

    #[test]
    fn a_pinned_version_is_read_from_the_matching_field_only() {
        let source = "a=L({protocolVersion:F(7),developmentRoot:x}),b=L({protocolVersion:F(3),\
                      webSocketPath:y}),c={protocolVersion:4,sessionId:z}";

        assert_eq!(pinned_protocol_version(source, "webSocketPath"), Some(3));
        assert_eq!(pinned_protocol_version(source, "sessionId"), Some(4));
        assert_eq!(pinned_protocol_version(source, "nothingLikeThis"), None);
    }
}
