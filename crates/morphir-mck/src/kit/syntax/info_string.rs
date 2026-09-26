//! Grammar of a data fence's info string: `<language> <role> [key=value ...]`.
//! Every token is validated; an unknown word is an error rather than ignored,
//! so a typo in a role cannot silently turn a case into prose.

use std::collections::BTreeMap;
use std::fmt;

use super::text::js_tokens;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Language {
    Yaml,
    Json,
    Text,
}

impl Language {
    fn parse(word: &str) -> Option<Self> {
        match word {
            "yaml" => Some(Self::Yaml),
            "json" => Some(Self::Json),
            "text" => Some(Self::Text),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Yaml => "yaml",
            Self::Json => "json",
            Self::Text => "text",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Role {
    Canonical,
    Accepted,
    Rejected,
    File,
}

impl Role {
    fn parse(word: &str) -> Option<Self> {
        match word {
            "canonical" => Some(Self::Canonical),
            "accepted" => Some(Self::Accepted),
            "rejected" => Some(Self::Rejected),
            "file" => Some(Self::File),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Canonical => "canonical",
            Self::Accepted => "accepted",
            Self::Rejected => "rejected",
            Self::File => "file",
        }
    }

    fn allowed_keys(self) -> &'static [&'static str] {
        match self {
            Self::Canonical => &[],
            // warning=<code>: the reader must accept the spelling and report
            // exactly that warning (decision 0006's compatibility window).
            Self::Accepted => &["warning"],
            Self::Rejected => &["diagnostic", "expect"],
            // mode=read: the set holds input a canonical writer never
            // reproduces, so only the read half of the tree comparison runs.
            // It is all-or-nothing per set, which the case parser enforces.
            Self::File => &["path", "set", "mode"],
        }
    }
}

impl fmt::Display for Role {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FenceInfo {
    pub language: Language,
    pub role: Role,
    keys: BTreeMap<String, String>,
}

impl FenceInfo {
    /// A fence info built from its parts, for a fence read from another format
    /// than Markdown (the `.feature` lowering). The caller keeps the role's key
    /// rules; nothing here checks them.
    pub(crate) fn from_parts<K: Into<String>, V: Into<String>>(
        language: Language,
        role: Role,
        keys: impl IntoIterator<Item = (K, V)>,
    ) -> Self {
        Self {
            language,
            role,
            keys: keys
                .into_iter()
                .map(|(key, value)| (key.into(), value.into()))
                .collect(),
        }
    }

    /// Every key and its value, in key order.
    pub fn keys(&self) -> impl Iterator<Item = (&str, &str)> {
        self.keys.iter().map(|(k, v)| (k.as_str(), v.as_str()))
    }

    pub fn key(&self, name: &str) -> Option<&str> {
        self.keys.get(name).map(String::as_str)
    }

    /// The set a `file` fence belongs to; fences that name none share the anonymous set.
    pub fn set(&self) -> &str {
        self.key("set").unwrap_or("")
    }
}

/// How a set is named in a message. The anonymous set has no name to show, and
/// the parser and the runner have to render it the same way or the same set
/// reads as two in a report.
pub fn set_label(name: &str) -> &str {
    if name.is_empty() { "(unnamed)" } else { name }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InfoError {
    /// Fewer than two words: an illustration, not kit data.
    NotADataFence(String),
    Invalid(String),
}

impl fmt::Display for InfoError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotADataFence(info) => write!(f, "not a data fence: \"{info}\""),
            Self::Invalid(message) => f.write_str(message),
        }
    }
}

pub fn parse_info_string(info: &str) -> Result<FenceInfo, InfoError> {
    let invalid = |message: String| Err(InfoError::Invalid(message));
    let mut tokens = js_tokens(info);
    let (Some(language), Some(role)) = (tokens.next(), tokens.next()) else {
        return Err(InfoError::NotADataFence(info.to_owned()));
    };
    let Some(language) = Language::parse(language) else {
        return invalid(format!("unknown language \"{language}\""));
    };
    let Some(role) = Role::parse(role) else {
        return invalid(format!("unknown role \"{role}\""));
    };

    let mut keys = BTreeMap::new();
    for token in tokens {
        let Some((key, value)) = token.split_once('=').filter(|(key, _)| !key.is_empty()) else {
            return invalid(format!("malformed key \"{token}\", expected key=value"));
        };
        if !role.allowed_keys().contains(&key) {
            return invalid(format!("unknown key \"{key}\" for role {role}"));
        }
        if keys.insert(key.to_owned(), value.to_owned()).is_some() {
            return invalid(format!("duplicate key \"{key}\""));
        }
    }

    match role {
        Role::Rejected if keys.len() != 1 => {
            return invalid("rejected needs exactly one of diagnostic or expect".to_owned());
        }
        Role::File if !keys.contains_key("path") => return invalid("file needs path".to_owned()),
        Role::File if keys.get("mode").is_some_and(|mode| mode != "read") => {
            return invalid("mode must be read".to_owned());
        }
        _ => {}
    }

    Ok(FenceInfo {
        language,
        role,
        keys,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(info: &str) -> String {
        parse_info_string(info).unwrap_err().to_string()
    }

    #[test]
    fn parses_language_role_and_keys() {
        let info = parse_info_string("yaml file path=pkg/a/module set=s mode=read").unwrap();
        assert_eq!((info.language, info.role), (Language::Yaml, Role::File));
        assert_eq!(info.key("path"), Some("pkg/a/module"));
        assert_eq!(info.set(), "s");
        assert_eq!(parse_info_string("json canonical").unwrap().set(), "");
    }

    #[test]
    fn fewer_than_two_words_is_not_a_data_fence() {
        assert_eq!(
            parse_info_string("ts"),
            Err(InfoError::NotADataFence("ts".into()))
        );
        assert_eq!(message(""), "not a data fence: \"\"");
    }

    #[test]
    fn every_token_is_validated() {
        assert_eq!(message("toml canonical"), "unknown language \"toml\"");
        assert_eq!(message("yaml canonicl"), "unknown role \"canonicl\"");
        assert_eq!(
            message("yaml accepted warning"),
            "malformed key \"warning\", expected key=value"
        );
        assert_eq!(
            message("yaml accepted =x"),
            "malformed key \"=x\", expected key=value"
        );
        assert_eq!(
            message("yaml canonical warning=x"),
            "unknown key \"warning\" for role canonical"
        );
        assert_eq!(
            message("yaml accepted warning=a warning=b"),
            "duplicate key \"warning\""
        );
    }

    #[test]
    fn role_specific_rules() {
        assert_eq!(
            message("yaml rejected"),
            "rejected needs exactly one of diagnostic or expect"
        );
        assert_eq!(
            message("yaml rejected diagnostic=a expect=B"),
            "rejected needs exactly one of diagnostic or expect"
        );
        assert!(parse_info_string("json rejected expect=Kind").is_ok());
        assert_eq!(message("yaml file set=s"), "file needs path");
        assert_eq!(message("yaml file path=a mode=write"), "mode must be read");
        assert!(parse_info_string("yaml file path=").is_ok());
    }

    #[test]
    fn set_label_names_the_anonymous_set() {
        assert_eq!(set_label(""), "(unnamed)");
        assert_eq!(set_label("meta"), "meta");
    }
}
