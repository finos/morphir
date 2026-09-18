//! The Elm prelude a compile asks the Elm provider for, read from the
//! project's configuration.
//!
//! `morphir.toml` names it in the frontend's language-specific table, the
//! shape `docs/design/draft/daemon/morphir-toml.md` specifies for per-language
//! settings:
//!
//! ```toml
//! [frontend.elm]
//! prelude = "none"
//! ```
//!
//! or, for a prelude the project describes itself:
//!
//! ```toml
//! [frontend.elm.prelude]
//! id = "acme-std"
//!
//! [[frontend.elm.prelude.module_alias]]
//! source = "Core"
//! target = "Acme.Std.Core"
//! ```
//!
//! `FrontendSection` collects every key it does not name itself into
//! `settings`, so `[frontend.elm]` arrives in the typed configuration model
//! without the model having to know about Elm. The model is
//! serialization independent, so the same key works in `morphir.yaml` and in a
//! user override as well.
//!
//! The value travels to the provider untouched as the `elmPrelude` compile
//! option: a string names a built-in prelude, a table describes one with the
//! same field names its TOML form uses. The provider decides which names and
//! which tables it accepts, and says so itself; the CLI only insists that the
//! key is one of those two shapes.

use super::frontend_settings::{language_setting, shape_of};
use crate::error::CliError;
use morphir_common::config::model::FrontendSection;
use serde_json::Value;

/// The configuration key that names the prelude.
pub const CONFIG_KEY: &str = "frontend.elm.prelude";

/// The compile option the Elm provider reads the prelude as.
pub const OPTION_KEY: &str = "elmPrelude";

/// The `elmPrelude` compile option a configuration asks for, or `None` when it
/// says nothing and the provider's own default applies.
pub fn from_config(frontend: Option<&FrontendSection>) -> Result<Option<Value>, CliError> {
    let Some(configured) = language_setting(frontend, "elm", "prelude") else {
        return Ok(None);
    };
    let value = serde_json::to_value(configured).map_err(|error| CliError::Config {
        error: anyhow::anyhow!("{CONFIG_KEY} could not be read: {error}"),
    })?;
    match value {
        Value::String(_) | Value::Object(_) => Ok(Some(value)),
        other => Err(CliError::Config {
            error: anyhow::anyhow!(
                "{CONFIG_KEY} is {}, but it must name a built-in prelude \
                 (\"elm-core\" or \"none\") or be a table describing one",
                shape_of(&other)
            ),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// The frontend section a `morphir.toml` decodes to, built the way the
    /// loader builds it: from the merged, serialization-independent value.
    fn frontend(value: serde_json::Value) -> FrontendSection {
        serde_json::from_value(value).expect("the frontend section decodes")
    }

    /// A configuration that says nothing about the prelude sends no option, so
    /// the provider applies its own default rather than the CLI restating it.
    #[test]
    fn a_configuration_without_the_key_sends_no_option() {
        assert_eq!(from_config(None).unwrap(), None);
        assert_eq!(from_config(Some(&frontend(json!({})))).unwrap(), None);
        assert_eq!(
            from_config(Some(&frontend(json!({"elm": {}})))).unwrap(),
            None
        );
    }

    #[test]
    fn the_empty_prelude_is_sent_by_name() {
        let option = from_config(Some(&frontend(json!({"elm": {"prelude": "none"}})))).unwrap();
        assert_eq!(option, Some(json!("none")));
    }

    #[test]
    fn the_default_prelude_is_sent_by_name() {
        let option = from_config(Some(&frontend(json!({"elm": {"prelude": "elm-core"}})))).unwrap();
        assert_eq!(option, Some(json!("elm-core")));
    }

    /// The prelude sits beside the keys the frontend section names itself, and
    /// reading it leaves them alone.
    #[test]
    fn the_prelude_shares_the_section_with_the_language() {
        let section = frontend(json!({"language": "elm", "elm": {"prelude": "none"}}));
        assert_eq!(section.language.as_deref(), Some("elm"));
        assert_eq!(from_config(Some(&section)).unwrap(), Some(json!("none")));
    }

    /// An inline prelude keeps the field names its TOML form uses, because the
    /// provider deserializes the option into the same type it reads a prelude
    /// file into.
    #[test]
    fn an_inline_prelude_travels_as_a_json_object() {
        let configured = toml::from_str::<toml::Value>(
            "[frontend.elm.prelude]\n\
             id = \"acme-std\"\n\
             \n\
             [[frontend.elm.prelude.implicit_import]]\n\
             module = \"Acme.Std.Basics\"\n\
             exposing = [\"Int\"]\n\
             \n\
             [[frontend.elm.prelude.module_alias]]\n\
             source = \"Core\"\n\
             target = \"Acme.Std.Core\"\n",
        )
        .expect("the configured table parses");
        let effective = serde_json::to_value(configured).expect("TOML converts to JSON");

        let option = from_config(Some(&frontend(effective["frontend"].clone()))).unwrap();

        assert_eq!(
            option,
            Some(json!({
                "id": "acme-std",
                "implicit_import": [{"module": "Acme.Std.Basics", "exposing": ["Int"]}],
                "module_alias": [{"source": "Core", "target": "Acme.Std.Core"}],
            }))
        );
    }

    /// A value that is neither a name nor a table is refused here, naming the
    /// key, rather than travelling to the provider to come back as a protocol
    /// error that says nothing about `morphir.toml`.
    #[test]
    fn a_value_of_the_wrong_type_names_the_key() {
        for wrong in [json!(3), json!(true), json!(["elm-core"])] {
            let failure = from_config(Some(&frontend(json!({"elm": {"prelude": wrong}}))))
                .expect_err("a prelude must be a name or a table");
            let CliError::Config { error } = failure else {
                panic!("a misconfigured prelude is a configuration error: {failure:?}");
            };
            let message = error.to_string();
            assert!(message.contains("frontend.elm.prelude"), "{message}");
            assert!(message.contains("elm-core"), "{message}");
            assert!(message.contains("none"), "{message}");
        }
    }
}
