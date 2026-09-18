//! The Elm prelude a compile asks the Elm provider for, read from the
//! project's configuration.
//!
//! `morphir.toml` names it in a language-scoped table:
//!
//! ```toml
//! [elm]
//! prelude = "none"
//! ```
//!
//! or, for a prelude the project describes itself:
//!
//! ```toml
//! [elm.prelude]
//! id = "acme-std"
//!
//! [[elm.prelude.module_alias]]
//! source = "Core"
//! target = "Acme.Std.Core"
//! ```
//!
//! The table is not part of the typed configuration model, so it is read off
//! the merged configuration value every loader already carries
//! (`ConfigContext::effective`). That value is serialization independent, so
//! the same key works in `morphir.yaml`, in a user override, and through
//! `MORPHIR_ELM__PRELUDE`.
//!
//! The value travels to the provider untouched as the `elmPrelude` compile
//! option: a string names a built-in prelude, a table describes one with the
//! same field names its TOML form uses. The provider decides which names and
//! which tables it accepts, and says so itself; the CLI only insists that the
//! key is one of those two shapes.

use crate::error::CliError;
use serde_json::Value;

/// The configuration key that names the prelude.
pub const CONFIG_KEY: &str = "elm.prelude";

/// The compile option the Elm provider reads the prelude as.
pub const OPTION_KEY: &str = "elmPrelude";

/// [`CONFIG_KEY`] as a JSON pointer into a merged configuration value.
const CONFIG_POINTER: &str = "/elm/prelude";

/// The `elmPrelude` compile option a configuration asks for, or `None` when it
/// says nothing and the provider's own default applies.
pub fn from_config(effective: &Value) -> Result<Option<Value>, CliError> {
    match effective.pointer(CONFIG_POINTER) {
        None | Some(Value::Null) => Ok(None),
        Some(value @ (Value::String(_) | Value::Object(_))) => Ok(Some(value.clone())),
        Some(other) => Err(CliError::Config {
            error: anyhow::anyhow!(
                "{CONFIG_KEY} is {}, but it must name a built-in prelude \
                 (\"elm-core\" or \"none\") or be a table describing one",
                shape_of(other)
            ),
        }),
    }
}

/// How to name a value's shape in the error above.
fn shape_of(value: &Value) -> &'static str {
    match value {
        Value::Null => "empty",
        Value::Bool(_) => "a boolean",
        Value::Number(_) => "a number",
        Value::Array(_) => "an array",
        Value::String(_) => "a string",
        Value::Object(_) => "a table",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// A configuration that says nothing about the prelude sends no option, so
    /// the provider applies its own default rather than the CLI restating it.
    #[test]
    fn a_configuration_without_the_key_sends_no_option() {
        assert_eq!(from_config(&json!({})).unwrap(), None);
        assert_eq!(from_config(&json!({"elm": {}})).unwrap(), None);
    }

    #[test]
    fn the_empty_prelude_is_sent_by_name() {
        let option = from_config(&json!({"elm": {"prelude": "none"}})).unwrap();
        assert_eq!(option, Some(json!("none")));
    }

    #[test]
    fn the_default_prelude_is_sent_by_name() {
        let option = from_config(&json!({"elm": {"prelude": "elm-core"}})).unwrap();
        assert_eq!(option, Some(json!("elm-core")));
    }

    /// An inline prelude keeps the field names its TOML form uses, because the
    /// provider deserializes the option into the same type it reads a prelude
    /// file into.
    #[test]
    fn an_inline_prelude_travels_as_a_json_object() {
        let configured = toml::from_str::<toml::Value>(
            "[elm.prelude]\n\
             id = \"acme-std\"\n\
             \n\
             [[elm.prelude.implicit_import]]\n\
             module = \"Acme.Std.Basics\"\n\
             exposing = [\"Int\"]\n\
             \n\
             [[elm.prelude.module_alias]]\n\
             source = \"Core\"\n\
             target = \"Acme.Std.Core\"\n",
        )
        .expect("the configured table parses");
        let effective = serde_json::to_value(configured).expect("TOML converts to JSON");

        let option = from_config(&effective).unwrap();

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
            let failure = from_config(&json!({"elm": {"prelude": wrong}}))
                .expect_err("a prelude must be a name or a table");
            let CliError::Config { error } = failure else {
                panic!("a misconfigured prelude is a configuration error: {failure:?}");
            };
            let message = error.to_string();
            assert!(message.contains("elm.prelude"), "{message}");
            assert!(message.contains("elm-core"), "{message}");
            assert!(message.contains("none"), "{message}");
        }
    }
}
