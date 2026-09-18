//! Reading a language-scoped setting out of the frontend section.
//!
//! `FrontendSection` collects every key it does not name itself into
//! `settings`, so a per-language table arrives in the typed configuration model
//! without the model having to know about any particular language:
//!
//! ```toml
//! [frontend.elm]
//! prelude = "elm-core"
//! extension = "morphir-elm-native"
//! ```
//!
//! Both of those keys are found the same way, so the lookup lives here rather
//! than once per key. The model is serialization independent, so the same
//! tables work in `morphir.yaml` and in a user override as well.

use morphir_common::config::model::FrontendSection;

/// The value of `[frontend.<language>] <key>`, or `None` when the
/// configuration says nothing about it.
///
/// A language is matched exactly first and then without regard to case, so a
/// run that asks for `Elm` still finds the `[frontend.elm]` a project wrote in
/// the spelling the rest of the configuration uses.
pub fn language_setting<'a>(
    frontend: Option<&'a FrontendSection>,
    language: &str,
    key: &str,
) -> Option<&'a toml::Value> {
    let settings = &frontend?.settings;
    let table = settings.get(language).or_else(|| {
        settings
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case(language))
            .map(|(_, value)| value)
    })?;
    table.get(key)
}

/// How to name a value's shape when a setting is refused for its type.
pub fn shape_of(value: &serde_json::Value) -> &'static str {
    match value {
        serde_json::Value::Null => "empty",
        serde_json::Value::Bool(_) => "a boolean",
        serde_json::Value::Number(_) => "a number",
        serde_json::Value::Array(_) => "an array",
        serde_json::Value::String(_) => "a string",
        serde_json::Value::Object(_) => "a table",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn frontend(value: serde_json::Value) -> FrontendSection {
        serde_json::from_value(value).expect("the frontend section decodes")
    }

    #[test]
    fn a_missing_section_table_or_key_is_absent() {
        assert_eq!(language_setting(None, "elm", "extension"), None);
        let section = frontend(json!({"language": "elm", "gleam": {"extension": "x"}}));
        assert_eq!(language_setting(Some(&section), "elm", "extension"), None);
        assert_eq!(language_setting(Some(&section), "gleam", "prelude"), None);
    }

    #[test]
    fn a_language_is_matched_without_regard_to_case() {
        let section = frontend(json!({"elm": {"extension": "morphir-elm-native"}}));
        assert_eq!(
            language_setting(Some(&section), "Elm", "extension").and_then(|value| value.as_str()),
            Some("morphir-elm-native")
        );
    }

    #[test]
    fn a_language_table_keeps_the_keys_beside_it() {
        let section = frontend(json!({
            "language": "elm",
            "elm": {"extension": "morphir-elm-native", "prelude": "none"},
        }));
        assert_eq!(section.language.as_deref(), Some("elm"));
        assert_eq!(
            language_setting(Some(&section), "elm", "prelude").and_then(|value| value.as_str()),
            Some("none")
        );
    }
}
