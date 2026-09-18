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

use crate::error::CliError;
use morphir_common::config::model::FrontendSection;

/// The value of `[frontend.<language>] <key>`, or `None` when the
/// configuration says nothing about it.
///
/// A language is matched exactly first and then without regard to case, so a
/// run that asks for `Elm` still finds the `[frontend.elm]` a project wrote in
/// the spelling the rest of the configuration uses. Two tables that differ
/// only in case are a configuration error rather than a coin toss: the
/// settings map has no order, so picking one would mean a project compiled
/// differently from run to run.
pub fn language_setting<'a>(
    frontend: Option<&'a FrontendSection>,
    language: &str,
    key: &str,
) -> Result<Option<&'a toml::Value>, CliError> {
    let Some(frontend) = frontend else {
        return Ok(None);
    };
    let settings = &frontend.settings;
    let table = match settings.get(language) {
        Some(exact) => exact,
        None => {
            let mut spellings: Vec<&String> = settings
                .keys()
                .filter(|name| name.eq_ignore_ascii_case(language))
                .collect();
            match spellings.len() {
                0 => return Ok(None),
                1 => &settings[spellings[0]],
                _ => {
                    spellings.sort();
                    let named = spellings
                        .iter()
                        .map(|name| format!("frontend.{name}"))
                        .collect::<Vec<_>>()
                        .join(" and ");
                    return Err(CliError::Config {
                        error: anyhow::anyhow!(
                            "{named} both configure the '{language}' frontend; \
                             keep one of them"
                        ),
                    });
                }
            }
        }
    };
    Ok(table.get(key))
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
        assert_eq!(language_setting(None, "elm", "extension").unwrap(), None);
        let section = frontend(json!({"language": "elm", "gleam": {"extension": "x"}}));
        assert_eq!(
            language_setting(Some(&section), "elm", "extension").unwrap(),
            None
        );
        assert_eq!(
            language_setting(Some(&section), "gleam", "prelude").unwrap(),
            None
        );
    }

    #[test]
    fn a_language_is_matched_without_regard_to_case() {
        let section = frontend(json!({"elm": {"extension": "morphir-elm-native"}}));
        assert_eq!(
            language_setting(Some(&section), "Elm", "extension")
                .unwrap()
                .and_then(|value| value.as_str()),
            Some("morphir-elm-native")
        );
    }

    /// An exact spelling answers even when another differs only in case, so
    /// the ambiguity below is only about tables none of which match exactly.
    #[test]
    fn an_exact_spelling_wins_over_one_that_differs_in_case() {
        let section = frontend(json!({
            "elm": {"extension": "morphir-elm-native"},
            "Elm": {"extension": "morphir-elm"},
        }));
        assert_eq!(
            language_setting(Some(&section), "elm", "extension")
                .unwrap()
                .and_then(|value| value.as_str()),
            Some("morphir-elm-native")
        );
    }

    /// Two tables that differ only in case, with no exact match, would be
    /// chosen between by the settings map's arbitrary order. That is refused,
    /// naming both spellings, rather than compiled differently from run to run.
    #[test]
    fn two_spellings_of_a_language_name_both_spellings() {
        let section = frontend(json!({
            "Elm": {"extension": "morphir-elm"},
            "ELM": {"extension": "morphir-elm-native"},
        }));

        let failure = language_setting(Some(&section), "elm", "extension")
            .expect_err("two spellings of one language are ambiguous");

        let CliError::Config { error } = failure else {
            panic!("an ambiguous frontend table is a configuration error: {failure:?}");
        };
        let message = error.to_string();
        assert!(message.contains("frontend.ELM"), "{message}");
        assert!(message.contains("frontend.Elm"), "{message}");
    }

    #[test]
    fn a_language_table_keeps_the_keys_beside_it() {
        let section = frontend(json!({
            "language": "elm",
            "elm": {"extension": "morphir-elm-native", "prelude": "none"},
        }));
        assert_eq!(section.language.as_deref(), Some("elm"));
        assert_eq!(
            language_setting(Some(&section), "elm", "prelude")
                .unwrap()
                .and_then(|value| value.as_str()),
            Some("none")
        );
    }
}
