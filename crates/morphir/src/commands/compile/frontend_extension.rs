//! The frontend provider a compile uses for a language, read from the
//! project's configuration.
//!
//! A provider belongs to a language, so the key that names one sits in the
//! frontend's language-specific table rather than beside `[frontend] language`:
//! `[[frontend.rules]]` may send different paths to different languages, and
//! each of those languages has its own provider.
//!
//! ```toml
//! [frontend]
//! language = "elm"
//!
//! [frontend.elm]
//! extension = "morphir-elm-native"
//! prelude = "elm-core"
//! ```
//!
//! The key is read through the same typed passthrough the prelude uses, so it
//! works in `morphir.yaml` and in a user override as well.
//!
//! `--extension` overrides it, and with neither the language's default provider
//! applies. A configured id is otherwise the flag's equal: it restricts the
//! registry the same way, which is what makes an opt-in built-in provider such
//! as `morphir-elm-native` reachable without the flag, and what makes an id
//! that provides some other language fail with the same message the flag gets.

use super::frontend_settings::{language_setting, shape_of};
use crate::error::CliError;
use morphir_common::config::model::FrontendSection;

/// The configuration key that names the provider, for a given language.
pub fn config_key(language: &str) -> String {
    format!("frontend.{language}.extension")
}

/// The extension id a configuration names for this language, or `None` when it
/// says nothing and the language's default provider applies.
pub fn from_config(
    frontend: Option<&FrontendSection>,
    language: &str,
) -> Result<Option<String>, CliError> {
    let Some(configured) = language_setting(frontend, language, "extension") else {
        return Ok(None);
    };
    let key = config_key(language);
    let Some(id) = configured.as_str() else {
        let shape = serde_json::to_value(configured)
            .map(|value| shape_of(&value))
            .unwrap_or("not a string");
        return Err(CliError::Config {
            error: anyhow::anyhow!(
                "{key} is {shape}, but it must name an extension id such as \
                 \"morphir-elm-native\""
            ),
        });
    };
    let trimmed = id.trim();
    if trimmed.is_empty() {
        return Err(CliError::Config {
            error: anyhow::anyhow!(
                "{key} is empty; name an extension id such as \
                 \"morphir-elm-native\" or remove the key"
            ),
        });
    }
    Ok(Some(trimmed.to_owned()))
}

/// The provider a run uses: the flag when it names one, then the
/// configuration, then nothing, which leaves the language's default provider.
///
/// The flag is validated by its own caller, which reports an empty
/// `--extension` as a flag error; this only settles which of the two answers.
pub fn resolve<'a>(
    flag: Option<&'a str>,
    frontend: Option<&FrontendSection>,
    language: &str,
) -> Result<Option<std::borrow::Cow<'a, str>>, CliError> {
    match flag {
        Some(id) => Ok(Some(std::borrow::Cow::Borrowed(id))),
        None => Ok(from_config(frontend, language)?.map(std::borrow::Cow::Owned)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn frontend(value: serde_json::Value) -> FrontendSection {
        serde_json::from_value(value).expect("the frontend section decodes")
    }

    /// Saying nothing leaves the language's default provider in place, rather
    /// than the CLI restating it as an explicit choice.
    #[test]
    fn a_configuration_without_the_key_names_no_provider() {
        assert_eq!(from_config(None, "elm").unwrap(), None);
        assert_eq!(
            from_config(Some(&frontend(json!({}))), "elm").unwrap(),
            None
        );
        assert_eq!(
            from_config(Some(&frontend(json!({"elm": {}}))), "elm").unwrap(),
            None
        );
    }

    #[test]
    fn a_configured_id_is_read_for_its_language() {
        let section = frontend(json!({"elm": {"extension": "morphir-elm-native"}}));
        assert_eq!(
            from_config(Some(&section), "elm").unwrap().as_deref(),
            Some("morphir-elm-native")
        );
    }

    /// The key is per language, so another language's table never answers for
    /// the language being compiled.
    #[test]
    fn another_languages_key_is_ignored() {
        let section = frontend(json!({
            "elm": {"extension": "morphir-elm-native"},
            "gleam": {"extension": "morphir-gleam-binding"},
        }));
        assert_eq!(
            from_config(Some(&section), "gleam").unwrap().as_deref(),
            Some("morphir-gleam-binding")
        );
        assert_eq!(from_config(Some(&section), "scala").unwrap(), None);
    }

    #[test]
    fn surrounding_whitespace_is_trimmed() {
        let section = frontend(json!({"elm": {"extension": "  morphir-elm-native  "}}));
        assert_eq!(
            from_config(Some(&section), "elm").unwrap().as_deref(),
            Some("morphir-elm-native")
        );
    }

    /// A blank value is a mistake, not a way of asking for the default: it is
    /// refused here, naming the key, rather than reaching the registry as an
    /// id that resolves nothing.
    #[test]
    fn a_blank_value_names_the_key() {
        for blank in ["", "   "] {
            let failure = from_config(Some(&frontend(json!({"elm": {"extension": blank}}))), "elm")
                .expect_err("a blank provider id is refused");
            let CliError::Config { error } = failure else {
                panic!("a misconfigured provider is a configuration error: {failure:?}");
            };
            let message = error.to_string();
            assert!(message.contains("frontend.elm.extension"), "{message}");
        }
    }

    #[test]
    fn a_value_of_the_wrong_type_names_the_key() {
        for wrong in [
            json!(3),
            json!(true),
            json!(["morphir-elm-native"]),
            json!({}),
        ] {
            let failure = from_config(Some(&frontend(json!({"elm": {"extension": wrong}}))), "elm")
                .expect_err("a provider id must be a string");
            let CliError::Config { error } = failure else {
                panic!("a misconfigured provider is a configuration error: {failure:?}");
            };
            let message = error.to_string();
            assert!(message.contains("frontend.elm.extension"), "{message}");
            assert!(message.contains("morphir-elm-native"), "{message}");
        }
    }

    #[test]
    fn the_flag_overrides_the_configured_id() {
        let section = frontend(json!({"elm": {"extension": "morphir-elm-native"}}));
        assert_eq!(
            resolve(Some("morphir-elm"), Some(&section), "elm")
                .unwrap()
                .as_deref(),
            Some("morphir-elm")
        );
        assert_eq!(
            resolve(None, Some(&section), "elm").unwrap().as_deref(),
            Some("morphir-elm-native")
        );
        assert_eq!(resolve(None, None, "elm").unwrap(), None);
    }

    /// The flag wins even when the configured value would have been refused:
    /// a run that names its provider is not stopped by a key it is not using.
    #[test]
    fn the_flag_wins_over_a_misconfigured_key() {
        let section = frontend(json!({"elm": {"extension": 3}}));
        assert_eq!(
            resolve(Some("morphir-elm"), Some(&section), "elm")
                .unwrap()
                .as_deref(),
            Some("morphir-elm")
        );
    }
}
