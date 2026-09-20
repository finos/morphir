//! The Elm frontend's two compatibility modes, read from the project's
//! configuration, an environment variable, or the command line.
//!
//! The native Elm frontend can write a document either the way morphir-elm
//! would have written it or the way it would choose for itself, and it makes
//! that choice twice over: once for the text of a doc comment, once for the
//! order modules, types and constructors appear in. Neither choice belongs in
//! the code, so each is a key in the frontend's Elm table:
//!
//! ```toml
//! [frontend.elm]
//! doc_comments = "morphir-elm"
//! ordering = "source"
//! ```
//!
//! The defaults differ, and deliberately. `doc_comments` defaults to
//! `morphir-elm` because a doc's text is data a consumer may already be
//! matching on, so changing it silently would change documents that compare
//! equal today. `ordering` defaults to `source` because the order is not data
//! anyone matches on, and declaration order is the better answer: a reader
//! comparing a document with the Elm it came from finds things in the same
//! place, and a diff between two versions shows the edit rather than a
//! reshuffle. Both defaults live in the provider, not here — a run that
//! configures nothing sends no option at all.
//!
//! Three surfaces set each key, in this order of precedence:
//!
//! 1. `--elm-doc-comments` / `--elm-ordering` on the command line.
//! 2. `MORPHIR_FRONTEND__ELM__DOC_COMMENTS` / `MORPHIR_FRONTEND__ELM__ORDERING`.
//! 3. `[frontend.elm]` in `morphir.toml`, `morphir.yaml`, or a user override.
//!
//! Only the flag is handled here. The environment variable is already a
//! configuration layer that the loader merges over the files — `MORPHIR_`
//! variables become nested keys, and `__` separates levels — so by the time a
//! [`FrontendSection`] reaches this module an environment variable and a file
//! are the same thing, and the variable has already won. That is also why the
//! key is spelled `doc_comments` rather than `docComments`: the environment
//! mapping lower-cases a segment and keeps single underscores, so snake_case
//! is the one spelling all three surfaces share.
//!
//! A malformed value is a configuration error, unless the matching flag was
//! given: the flag already settles the mode, so a broken value it would have
//! overridden is reported as a warning on stderr instead of failing the run.
//! This is the rule `[frontend.<language>] extension` follows, and the keys
//! sit in the same table, so they behave the same way.

use super::frontend_settings::{language_setting, shape_of};
use crate::error::CliError;
use morphir_common::config::model::FrontendSection;

/// One `[frontend.elm]` key whose value names a mode.
pub struct Mode {
    /// The key's spelling in the configuration and, lower-cased and
    /// underscore-separated, in the environment variable.
    key: &'static str,
    /// The compile option the Elm provider reads the mode as.
    option: &'static str,
    /// The command-line flag that overrides the key.
    flag: &'static str,
    /// The modes the provider accepts, in the order the help text lists them.
    modes: &'static [&'static str],
}

/// How a `{-| ... -}` comment becomes the doc text the IR carries.
pub const DOC_COMMENTS: Mode = Mode {
    key: "doc_comments",
    option: "elmDocComments",
    flag: "--elm-doc-comments",
    modes: &["morphir-elm", "trimmed"],
};

/// The order modules, types and constructors are written in.
pub const ORDERING: Mode = Mode {
    key: "ordering",
    option: "elmOrdering",
    flag: "--elm-ordering",
    modes: &["source", "morphir-elm"],
};

/// Every mode key, for a caller that applies all of them.
pub const ALL: &[Mode] = &[DOC_COMMENTS, ORDERING];

/// What a run does with one mode key.
#[derive(Debug, PartialEq, Eq)]
pub struct Resolved {
    /// The mode a run sends, or `None` when nothing named one and the
    /// provider's own default applies.
    pub mode: Option<String>,
    /// Set only when the flag was given and the configured value was
    /// malformed: the flag's mode is used regardless, but the key is unusable
    /// and a caller should say so, on stderr.
    pub warning: Option<String>,
}

/// Why a configured mode was not returned to a caller.
///
/// The split lets [`Mode::resolve`] tell a malformed *value* apart from every
/// other reason the lookup can fail — today only an ambiguous
/// `[frontend.elm]` table — without matching on message text. Only the value
/// is the flag's business: a flag names a mode, so a broken value it overrides
/// no longer matters, but an ambiguous table is not about this key at all.
enum Unresolved {
    /// The key's value is not a mode this provider accepts. The message
    /// already names the key.
    MalformedValue(String),
    /// Any other reason the lookup itself failed, already a [`CliError`].
    Lookup(CliError),
}

impl From<Unresolved> for CliError {
    fn from(unresolved: Unresolved) -> Self {
        match unresolved {
            Unresolved::MalformedValue(message) => CliError::Config {
                error: anyhow::anyhow!(message),
            },
            Unresolved::Lookup(error) => error,
        }
    }
}

impl Mode {
    /// The configuration key, as a reader would write it in `morphir.toml`.
    pub fn config_key(&self) -> String {
        format!("frontend.elm.{}", self.key)
    }

    /// The compile option the Elm provider reads this mode as.
    pub fn option_key(&self) -> &'static str {
        self.option
    }

    /// The modes this key accepts, quoted, as an error message lists them.
    fn accepted(&self) -> String {
        self.modes
            .iter()
            .map(|mode| format!("\"{mode}\""))
            .collect::<Vec<_>>()
            .join(" or ")
    }

    /// [`Mode::configured`]'s work, keeping a malformed value distinct from
    /// every other reason the lookup can fail — see [`Unresolved`].
    fn configured_typed(
        &self,
        frontend: Option<&FrontendSection>,
    ) -> Result<Option<String>, Unresolved> {
        let Some(configured) =
            language_setting(frontend, "elm", self.key).map_err(Unresolved::Lookup)?
        else {
            return Ok(None);
        };
        let key = self.config_key();
        let Some(named) = configured.as_str() else {
            let shape = serde_json::to_value(configured)
                .map(|value| shape_of(&value))
                .unwrap_or("not a string");
            return Err(Unresolved::MalformedValue(format!(
                "{key} is {shape}, but it must name a mode: {}",
                self.accepted()
            )));
        };
        let trimmed = named.trim();
        if trimmed.is_empty() {
            return Err(Unresolved::MalformedValue(format!(
                "{key} is empty; name a mode ({}) or remove the key",
                self.accepted()
            )));
        }
        if !self.modes.contains(&trimmed) {
            return Err(Unresolved::MalformedValue(format!(
                "{key} is \"{trimmed}\", which is not a mode this frontend \
                 knows; it must be {}",
                self.accepted()
            )));
        }
        Ok(Some(trimmed.to_owned()))
    }

    /// The mode a configuration names, or `None` when it says nothing and the
    /// provider's own default applies.
    ///
    /// The value is checked here so a bad one names the key. Left to the
    /// provider it would come back as a protocol error about an option the
    /// reader never wrote, saying nothing about where the value came from.
    pub fn configured(
        &self,
        frontend: Option<&FrontendSection>,
    ) -> Result<Option<String>, CliError> {
        self.configured_typed(frontend).map_err(CliError::from)
    }

    /// The mode a run uses: the flag when it names one, then the
    /// configuration — which the environment has already been merged into —
    /// then nothing, which leaves the provider's default.
    pub fn resolve(
        &self,
        flag: Option<&str>,
        frontend: Option<&FrontendSection>,
    ) -> Result<Resolved, CliError> {
        let Some(named) = flag else {
            return Ok(Resolved {
                mode: self.configured(frontend)?,
                warning: None,
            });
        };
        match self.configured_typed(frontend) {
            Ok(_) => Ok(Resolved {
                mode: Some(named.to_owned()),
                warning: None,
            }),
            Err(Unresolved::MalformedValue(message)) => Ok(Resolved {
                mode: Some(named.to_owned()),
                warning: Some(format!(
                    "{message}; ignored because {} {named} was given",
                    self.flag
                )),
            }),
            Err(Unresolved::Lookup(error)) => Err(error),
        }
    }
}

/// The flags that override the Elm modes for one run.
#[derive(Debug, Default, Clone)]
pub struct Flags {
    /// `--elm-doc-comments`.
    pub doc_comments: Option<String>,
    /// `--elm-ordering`.
    pub ordering: Option<String>,
}

impl Flags {
    /// The flag that overrides `mode`, if this run gave it.
    fn for_mode(&self, mode: &Mode) -> Option<&str> {
        let named = if mode.key == DOC_COMMENTS.key {
            &self.doc_comments
        } else {
            &self.ordering
        };
        named.as_deref()
    }
}

/// The frontend section an environment-only configuration describes, or `None`
/// when the environment says nothing about the frontend.
///
/// A standalone single-file compile — one given neither `--config` nor
/// `--project` — loads no configuration file, so the layered loader never runs
/// and `MORPHIR_FRONTEND__ELM__*` would go unseen on exactly the runs that are
/// most likely to use it. The modes advertise an environment surface on every
/// compile, so that one layer is read directly here.
///
/// Only this layer: no file is consulted, so a standalone compile still cannot
/// be reconfigured by a `morphir.toml` it never selected. `prelude` and
/// `extension` are unaffected — a file is the only surface either of them
/// documents — which is why the caller decides where this section applies
/// rather than it being merged in for everything.
pub fn environment_frontend() -> Option<FrontendSection> {
    frontend_from_environment(&morphir_common::config::env::process_env_config_value(
        morphir_common::config::env::DEFAULT_ENV_PREFIX,
    ))
}

/// [`environment_frontend`]'s work, over an already-mapped environment, so it
/// can be tested without touching the process environment.
fn frontend_from_environment(environment: &serde_json::Value) -> Option<FrontendSection> {
    // An environment that describes no frontend, or describes one this model
    // cannot read, is treated as absent rather than fatal: nothing here is
    // what the run was asked to do, and a compile that never mentions a mode
    // must not fail over a variable it does not use. A value that *is* read
    // and is not a mode still fails, in `configured`, naming the key.
    serde_json::from_value(environment.get("frontend")?.clone()).ok()
}

/// Adds every Elm mode option a run asks for to `extra`, returning the
/// warnings a caller should print on stderr.
///
/// A key nothing names is left out entirely, so the provider applies its own
/// default rather than the CLI restating it.
pub fn apply(
    extra: &mut std::collections::HashMap<String, serde_json::Value>,
    flags: &Flags,
    frontend: Option<&FrontendSection>,
) -> Result<Vec<String>, CliError> {
    let mut warnings = Vec::new();
    for mode in ALL {
        let resolved = mode.resolve(flags.for_mode(mode), frontend)?;
        if let Some(named) = resolved.mode {
            extra.insert(mode.option_key().to_owned(), serde_json::json!(named));
        }
        warnings.extend(resolved.warning);
    }
    Ok(warnings)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::collections::HashMap;

    /// The frontend section a `morphir.toml` decodes to, built the way the
    /// loader builds it: from the merged, serialization-independent value.
    fn frontend(value: serde_json::Value) -> FrontendSection {
        serde_json::from_value(value).expect("the frontend section decodes")
    }

    #[test]
    fn a_key_names_itself_the_same_way_on_every_surface() {
        assert_eq!(DOC_COMMENTS.config_key(), "frontend.elm.doc_comments");
        assert_eq!(DOC_COMMENTS.option_key(), "elmDocComments");
        assert_eq!(ORDERING.config_key(), "frontend.elm.ordering");
        assert_eq!(ORDERING.option_key(), "elmOrdering");
    }

    /// The environment variable is not read here — it is a configuration layer
    /// the loader merges over the files — so what needs pinning is that the
    /// mapping lands on the same key a file would have set. This maps an
    /// explicit variable list the way the loader maps the process environment,
    /// which is also what makes `doc_comments` the right spelling: the mapping
    /// lower-cases a segment and keeps single underscores, so `docComments`
    /// would be unreachable from the environment.
    #[test]
    fn an_environment_variable_reaches_the_key_a_file_would_have_set() {
        let value = morphir_common::config::env::env_config_value(
            "MORPHIR",
            [
                ("MORPHIR_FRONTEND__ELM__DOC_COMMENTS", "trimmed"),
                ("MORPHIR_FRONTEND__ELM__ORDERING", "morphir-elm"),
            ],
        );

        let section = frontend(value["frontend"].clone());

        assert_eq!(
            DOC_COMMENTS.configured(Some(&section)).unwrap(),
            Some("trimmed".to_owned())
        );
        assert_eq!(
            ORDERING.configured(Some(&section)).unwrap(),
            Some("morphir-elm".to_owned())
        );
    }

    /// A configuration that says nothing sends no option, so the provider
    /// applies its own default rather than the CLI restating it. That is what
    /// keeps the two defaults — compatible docs, source order — in one place.
    #[test]
    fn a_configuration_without_the_key_sends_no_option() {
        for mode in ALL {
            assert_eq!(mode.configured(None).unwrap(), None);
            assert_eq!(mode.configured(Some(&frontend(json!({})))).unwrap(), None);
            assert_eq!(
                mode.configured(Some(&frontend(json!({"elm": {}}))))
                    .unwrap(),
                None
            );
        }
    }

    #[test]
    fn a_configured_mode_is_sent_by_name() {
        let section =
            frontend(json!({"elm": {"doc_comments": "trimmed", "ordering": "morphir-elm"}}));
        assert_eq!(
            DOC_COMMENTS.configured(Some(&section)).unwrap(),
            Some("trimmed".to_owned())
        );
        assert_eq!(
            ORDERING.configured(Some(&section)).unwrap(),
            Some("morphir-elm".to_owned())
        );
    }

    /// The provider owns the defaults, but the CLI still refuses a mode the
    /// provider would reject, so the message names `morphir.toml` rather than
    /// coming back as a protocol error that says nothing about where the value
    /// came from.
    #[test]
    fn an_unknown_mode_names_the_key_and_the_modes_it_accepts() {
        let failure = ORDERING
            .configured(Some(&frontend(
                json!({"elm": {"ordering": "alphabetical"}}),
            )))
            .expect_err("an unknown order is refused");

        let CliError::Config { error } = failure else {
            panic!("an unknown mode is a configuration error: {failure:?}");
        };
        let message = error.to_string();
        assert!(message.contains("frontend.elm.ordering"), "{message}");
        assert!(message.contains("alphabetical"), "{message}");
        assert!(message.contains("source"), "{message}");
        assert!(message.contains("morphir-elm"), "{message}");
    }

    #[test]
    fn a_value_of_the_wrong_type_names_the_key() {
        for wrong in [json!(3), json!(true), json!(["trimmed"])] {
            let failure = DOC_COMMENTS
                .configured(Some(&frontend(json!({"elm": {"doc_comments": wrong}}))))
                .expect_err("a mode must be a string");

            let CliError::Config { error } = failure else {
                panic!("a misconfigured mode is a configuration error: {failure:?}");
            };
            let message = error.to_string();
            assert!(message.contains("frontend.elm.doc_comments"), "{message}");
            assert!(message.contains("trimmed"), "{message}");
        }
    }

    /// An empty value is its own message: "" is not a near-miss spelling of a
    /// mode, so listing the modes as if it were would not help.
    #[test]
    fn an_empty_mode_says_to_name_one_or_remove_the_key() {
        let failure = ORDERING
            .configured(Some(&frontend(json!({"elm": {"ordering": "  "}}))))
            .expect_err("an empty order is refused");

        let CliError::Config { error } = failure else {
            panic!("an empty mode is a configuration error: {failure:?}");
        };
        let message = error.to_string();
        assert!(message.contains("frontend.elm.ordering"), "{message}");
        assert!(message.contains("remove the key"), "{message}");
    }

    /// Surrounding whitespace is the kind of thing an editor leaves behind,
    /// and it does not change which mode was named.
    #[test]
    fn a_mode_is_read_without_its_surrounding_whitespace() {
        let section = frontend(json!({"elm": {"ordering": " source "}}));
        assert_eq!(
            ORDERING.configured(Some(&section)).unwrap(),
            Some("source".to_owned())
        );
    }

    #[test]
    fn the_flag_wins_over_the_configuration() {
        let section = frontend(json!({"elm": {"ordering": "source"}}));
        let resolved = ORDERING
            .resolve(Some("morphir-elm"), Some(&section))
            .unwrap();
        assert_eq!(
            resolved,
            Resolved {
                mode: Some("morphir-elm".to_owned()),
                warning: None
            }
        );
    }

    #[test]
    fn the_configuration_applies_without_a_flag() {
        let section = frontend(json!({"elm": {"ordering": "morphir-elm"}}));
        let resolved = ORDERING.resolve(None, Some(&section)).unwrap();
        assert_eq!(
            resolved,
            Resolved {
                mode: Some("morphir-elm".to_owned()),
                warning: None
            }
        );
    }

    #[test]
    fn neither_surface_sends_no_option() {
        let resolved = ORDERING.resolve(None, None).unwrap();
        assert_eq!(
            resolved,
            Resolved {
                mode: None,
                warning: None
            }
        );
    }

    /// The flag settles the mode, so a broken value it overrides is a warning
    /// rather than a failed run — the rule `extension` follows, in the same
    /// table.
    #[test]
    fn a_malformed_value_the_flag_overrides_is_a_warning() {
        let section = frontend(json!({"elm": {"ordering": "alphabetical"}}));
        let resolved = ORDERING
            .resolve(Some("source"), Some(&section))
            .expect("the flag settles the mode");

        assert_eq!(resolved.mode, Some("source".to_owned()));
        let warning = resolved.warning.expect("the unusable key is reported");
        assert!(warning.contains("frontend.elm.ordering"), "{warning}");
        assert!(warning.contains("--elm-ordering source"), "{warning}");
    }

    /// An ambiguous `[frontend.elm]` table is not about these keys at all, so
    /// a flag does not excuse it.
    #[test]
    fn an_ambiguous_table_fails_even_with_the_flag() {
        let section = frontend(json!({
            "Elm": {"ordering": "source"},
            "ELM": {"ordering": "morphir-elm"},
        }));
        let failure = ORDERING
            .resolve(Some("source"), Some(&section))
            .expect_err("an ambiguous table is an error whatever the flag says");
        assert!(matches!(failure, CliError::Config { .. }), "{failure:?}");
    }

    /// A standalone single-file compile loads no configuration file, so the
    /// environment is the only layer there is. Without this the flag would
    /// work on such a run and the variable would be silently ignored.
    #[test]
    fn the_environment_alone_describes_a_frontend_section() {
        let environment = morphir_common::config::env::env_config_value(
            "MORPHIR",
            [
                ("MORPHIR_FRONTEND__ELM__ORDERING", "morphir-elm"),
                ("PATH", "/usr/bin"),
            ],
        );

        let section = frontend_from_environment(&environment)
            .expect("the environment describes a frontend section");

        assert_eq!(
            ORDERING.configured(Some(&section)).unwrap(),
            Some("morphir-elm".to_owned())
        );
    }

    /// An environment that says nothing about the frontend describes no
    /// section, so a caller falls back to sending no option at all rather than
    /// to an empty table that means the same thing but costs a parse.
    #[test]
    fn an_environment_without_a_frontend_describes_no_section() {
        for environment in [
            morphir_common::config::env::env_config_value("MORPHIR", [("PATH", "/usr/bin")]),
            morphir_common::config::env::env_config_value(
                "MORPHIR",
                [("MORPHIR_IR__STRICT_MODE", "true")],
            ),
        ] {
            assert!(frontend_from_environment(&environment).is_none());
        }
    }

    /// A `[frontend]` the environment describes badly must not take down a
    /// compile that never asked for a mode: the section is simply not there.
    #[test]
    fn an_unreadable_frontend_section_is_absent_rather_than_fatal() {
        let environment = morphir_common::config::env::env_config_value(
            "MORPHIR",
            [("MORPHIR_FRONTEND", "not-a-table")],
        );

        assert!(frontend_from_environment(&environment).is_none());
    }

    #[test]
    fn apply_adds_only_the_keys_a_run_names() {
        let mut extra = HashMap::new();
        let section = frontend(json!({"elm": {"ordering": "morphir-elm"}}));

        let warnings = apply(&mut extra, &Flags::default(), Some(&section)).unwrap();

        assert_eq!(warnings, Vec::<String>::new());
        assert_eq!(
            extra,
            HashMap::from([("elmOrdering".to_owned(), json!("morphir-elm"))])
        );
    }

    #[test]
    fn apply_sends_both_keys_when_both_are_named() {
        let mut extra = HashMap::new();
        let flags = Flags {
            doc_comments: Some("trimmed".to_owned()),
            ordering: None,
        };
        let section = frontend(json!({"elm": {"ordering": "morphir-elm"}}));

        apply(&mut extra, &flags, Some(&section)).unwrap();

        assert_eq!(
            extra,
            HashMap::from([
                ("elmDocComments".to_owned(), json!("trimmed")),
                ("elmOrdering".to_owned(), json!("morphir-elm")),
            ])
        );
    }

    #[test]
    fn apply_leaves_the_options_alone_when_nothing_names_a_mode() {
        let mut extra = HashMap::from([("outputDir".to_owned(), json!("/out"))]);

        apply(&mut extra, &Flags::default(), None).unwrap();

        assert_eq!(
            extra,
            HashMap::from([("outputDir".to_owned(), json!("/out"))])
        );
    }

    #[test]
    fn apply_collects_a_warning_per_overridden_key() {
        let mut extra = HashMap::new();
        let flags = Flags {
            doc_comments: Some("trimmed".to_owned()),
            ordering: Some("source".to_owned()),
        };
        let section = frontend(json!({"elm": {"doc_comments": 3, "ordering": "alphabetical"}}));

        let warnings = apply(&mut extra, &flags, Some(&section)).unwrap();

        assert_eq!(warnings.len(), 2, "{warnings:?}");
        assert!(
            warnings
                .iter()
                .any(|w| w.contains("frontend.elm.doc_comments")),
            "{warnings:?}"
        );
        assert!(
            warnings.iter().any(|w| w.contains("frontend.elm.ordering")),
            "{warnings:?}"
        );
        assert_eq!(
            extra,
            HashMap::from([
                ("elmDocComments".to_owned(), json!("trimmed")),
                ("elmOrdering".to_owned(), json!("source")),
            ])
        );
    }
}
