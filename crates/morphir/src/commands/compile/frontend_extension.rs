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
//!
//! A malformed key is a configuration error, unless `--extension` is given: the
//! flag already settles which provider the run uses, so a broken key it would
//! otherwise have overridden is reported as a warning instead, not a failure.

use super::frontend_settings::{language_setting, shape_of};
use crate::error::CliError;
use morphir_common::config::model::FrontendSection;
use morphir_distribution::ExtensionId;

/// The configuration key that names the provider, for a given language.
pub fn config_key(language: &str) -> String {
    format!("frontend.{language}.extension")
}

/// The extension id a configuration names for this language, or `None` when it
/// says nothing and the language's default provider applies.
///
/// The id's syntax is checked here so a malformed one names the key. Left to
/// the caller it would surface as a bare "Invalid extension id", which says
/// nothing about `morphir.toml` and leaves the reader hunting for where the id
/// came from.
pub fn from_config(
    frontend: Option<&FrontendSection>,
    language: &str,
) -> Result<Option<String>, CliError> {
    let Some(configured) = language_setting(frontend, language, "extension")? else {
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
    ExtensionId::parse(trimmed).map_err(|error| CliError::Config {
        error: anyhow::anyhow!("{key} is not a valid extension id: {error}"),
    })?;
    Ok(Some(trimmed.to_owned()))
}

/// What a run does with the configured provider for a language.
#[derive(Debug, PartialEq, Eq)]
pub struct Resolved<'a> {
    /// The provider a run uses: the flag when it names one, then the
    /// configuration, then nothing, which leaves the language's default
    /// provider.
    pub extension: Option<std::borrow::Cow<'a, str>>,
    /// Set only when `--extension` was given and the configured key was
    /// malformed: the flag's id is used regardless, but the key is unusable
    /// and a caller should tell the user so, on stderr.
    pub warning: Option<String>,
}

/// The provider a run uses: the flag when it names one, then the
/// configuration, then nothing, which leaves the language's default provider.
///
/// A malformed key is a configuration error when there is no flag to fall
/// back on: with nothing to override it, a broken `morphir.toml` must not
/// silently resolve to the language's default provider. But when `--extension`
/// names a provider, that flag already settles which provider the run uses,
/// so a malformed key no longer needs to fail the run — it is reported as a
/// warning instead, naming the key and reusing the same text the key would
/// have failed with on its own, so the two messages agree.
pub fn resolve<'a>(
    flag: Option<&'a str>,
    frontend: Option<&FrontendSection>,
    language: &str,
) -> Result<Resolved<'a>, CliError> {
    match flag {
        Some(id) => match from_config(frontend, language) {
            Ok(_) => Ok(Resolved {
                extension: Some(std::borrow::Cow::Borrowed(id)),
                warning: None,
            }),
            Err(CliError::Config { error }) => Ok(Resolved {
                extension: Some(std::borrow::Cow::Borrowed(id)),
                warning: Some(format!(
                    "{error}; ignored because --extension {id} was given"
                )),
            }),
            Err(other) => Err(other),
        },
        None => {
            let configured = from_config(frontend, language)?;
            Ok(Resolved {
                extension: configured.map(std::borrow::Cow::Owned),
                warning: None,
            })
        }
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
        let resolved = resolve(Some("morphir-elm"), Some(&section), "elm").unwrap();
        assert_eq!(resolved.extension.as_deref(), Some("morphir-elm"));
        assert_eq!(resolved.warning, None);

        let resolved = resolve(None, Some(&section), "elm").unwrap();
        assert_eq!(resolved.extension.as_deref(), Some("morphir-elm-native"));
        assert_eq!(resolved.warning, None);

        assert_eq!(resolve(None, None, "elm").unwrap().extension, None);
    }

    /// A well-formed key never produces a warning, flag or no flag: a warning
    /// is only for a key the flag had to ignore because it could not be used.
    #[test]
    fn a_well_formed_key_with_the_flag_is_silent() {
        let section = frontend(json!({"elm": {"extension": "morphir-elm-native"}}));
        let resolved = resolve(Some("morphir-elm"), Some(&section), "elm").unwrap();
        assert_eq!(resolved.extension.as_deref(), Some("morphir-elm"));
        assert_eq!(resolved.warning, None);
    }

    /// With the flag given, a malformed key no longer fails the run: the flag
    /// already settles which provider is used, so the key is ignored and
    /// reported as a warning that names the key and the flag's id, reusing
    /// the same text the key would have failed with on its own.
    #[test]
    fn a_misconfigured_key_is_a_warning_with_the_flag() {
        for wrong in [json!(3), json!(""), json!("Morphir Elm Native")] {
            let section = frontend(json!({"elm": {"extension": wrong}}));

            let resolved = resolve(Some("morphir-elm-native"), Some(&section), "elm")
                .expect("a malformed key no longer fails the run when the flag is given");

            assert_eq!(resolved.extension.as_deref(), Some("morphir-elm-native"));
            let warning = resolved.warning.expect("a malformed key warns");
            assert!(warning.contains("frontend.elm.extension"), "{warning}");
            assert!(warning.contains("morphir-elm-native"), "{warning}");
        }
    }

    /// Without the flag, a malformed key is still a configuration error: there
    /// is nothing to fall back on, so the run must not silently use the
    /// language's default provider in place of a broken key.
    #[test]
    fn a_misconfigured_key_is_still_an_error_without_the_flag() {
        for wrong in [json!(3), json!(""), json!("Morphir Elm Native")] {
            let section = frontend(json!({"elm": {"extension": wrong}}));

            let failure = resolve(None, Some(&section), "elm")
                .expect_err("a malformed key fails without a flag to fall back on");

            let CliError::Config { error } = failure else {
                panic!("a misconfigured provider is a configuration error: {failure:?}");
            };
            assert!(
                error.to_string().contains("frontend.elm.extension"),
                "{error}"
            );
        }
    }

    /// An id that is not a well-formed extension id names the key, rather than
    /// surfacing as a bare "Invalid extension id" from wherever it is parsed.
    #[test]
    fn a_malformed_id_names_the_key() {
        let section = frontend(json!({"elm": {"extension": "Morphir Elm Native"}}));

        let failure =
            from_config(Some(&section), "elm").expect_err("an id with spaces is not an id");

        let CliError::Config { error } = failure else {
            panic!("a misconfigured provider is a configuration error: {failure:?}");
        };
        let message = error.to_string();
        assert!(message.contains("frontend.elm.extension"), "{message}");
    }
}
