//! Kit-owned reference conversion for the first semantic Ion cases.
//!
//! This module reads the public Ion spelling directly. It does not call an
//! implementation's IR codec, so adapter output cannot define the expected
//! result. Unsupported node shapes fail as kit errors until admitted here.

use ion_rs::{Element, Sequence, TextFormat};
use serde_json::{Value, json};

use super::compare::normalize_canonical;
use crate::transport::protocol::Profile;

/// Check an Ion expectation while the kit is loaded, before baseline rules
/// can adjudicate any execution record as an allowed failure.
pub(crate) fn validate(node: &str, ion: &str) -> Result<(), String> {
    reference_name(node, ion).map(|_| ())
}

pub(super) fn to_profile(node: &str, ion: &str, profile: Profile) -> Result<String, String> {
    let name = reference_name(node, ion)?;
    match profile {
        Profile::Ion => Ok(canonical_reference(&name)?),
        Profile::Json => {
            serde_json::to_string(&json!({"Reference": name})).map_err(|error| error.to_string())
        }
        Profile::Yaml => {
            serde_saphyr::to_string(&json!({"Reference": name})).map_err(|error| error.to_string())
        }
    }
}

pub(super) fn to_ion(node: &str, profile: Profile, text: &str) -> Result<String, String> {
    if node != "Value" {
        return Err(format!("reference codec does not support {node}"));
    }
    let value: Value = match profile {
        Profile::Json => serde_json::from_str(text).map_err(|error| error.to_string())?,
        Profile::Yaml => serde_saphyr::from_str(text).map_err(|error| error.to_string())?,
        Profile::Ion => return canonical_reference(&reference_name(node, text)?),
    };
    let Value::Object(fields) = value else {
        return Err("a Value reference is an object".to_owned());
    };
    if fields.len() != 1 {
        return Err("a Value reference has only Reference".to_owned());
    }
    let name = match fields.get("Reference") {
        Some(Value::String(name)) => name.as_str(),
        Some(Value::Object(reference)) => {
            if reference.len() != 2
                || !matches!(reference.get("attributes"), Some(Value::Object(attrs)) if attrs.is_empty())
            {
                return Err(
                    "an expanded Value reference has empty attributes and a fqname".to_owned(),
                );
            }
            reference
                .get("fqname")
                .and_then(Value::as_str)
                .ok_or("an expanded Value reference needs a fqname string")?
        }
        _ => return Err("a Value reference needs a Reference string or object".to_owned()),
    };
    canonical_reference(name)
}

fn reference_name(node: &str, text: &str) -> Result<String, String> {
    if node != "Value" {
        return Err(format!("reference codec does not support {node}"));
    }
    let element = Element::read_one(text.as_bytes()).map_err(|error| error.to_string())?;
    let sexp = element
        .as_sexp()
        .ok_or("a Value reference is an Ion S-expression")?;
    let parts = sexp.iter().collect::<Vec<_>>();
    let [head, argument] = parts.as_slice() else {
        return Err("a Value reference has one argument".to_owned());
    };
    if head.as_symbol().and_then(|symbol| symbol.text()) != Some("ref") {
        return Err("a Value reference starts with ref".to_owned());
    }
    let name = argument
        .as_symbol()
        .and_then(|symbol| symbol.text())
        .ok_or("a Value reference names a symbol")?;
    let canonical = canonical_reference(name)?;
    if normalize_canonical(text) != normalize_canonical(&canonical) {
        return Err(format!(
            "the Ion reference is not canonically spelled; expected {canonical:?}"
        ));
    }
    Ok(name.to_owned())
}

fn canonical_reference(name: &str) -> Result<String, String> {
    let sexp = Element::from(
        Sequence::builder()
            .push(Element::symbol("ref"))
            .push(Element::symbol(name))
            .build_sexp(),
    );
    let sequence = Sequence::builder().push(sexp).build();
    let mut text = sequence
        .encode_as(ion_rs::v1_0::Text.with_format(TextFormat::Pretty))
        .map_err(|error| error.to_string())?;
    if !text.ends_with('\n') {
        text.push('\n');
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ION: &str = "(\n  ref\n  'morphir/SDK:basics#add'\n)\n";

    #[test]
    fn reference_converts_between_ion_json_and_yaml() {
        let json = to_profile("Value", ION, Profile::Json).unwrap();
        let yaml = to_profile("Value", ION, Profile::Yaml).unwrap();
        assert_eq!(to_ion("Value", Profile::Json, &json).unwrap(), ION);
        assert_eq!(to_ion("Value", Profile::Yaml, &yaml).unwrap(), ION);
        assert_eq!(
            to_ion(
                "Value",
                Profile::Json,
                r##"{"Reference":{"attributes":{},"fqname":"morphir/SDK:basics#add"}}"##,
            )
            .unwrap(),
            ION
        );
        assert_eq!(to_profile("Value", ION, Profile::Ion).unwrap(), ION);
    }

    #[test]
    fn malformed_reference_never_becomes_an_expectation() {
        assert!(to_profile("Value", "(ref 42)", Profile::Json).is_err());
        assert!(to_profile("Value", "(ref 'x' 'y')", Profile::Json).is_err());
        assert!(to_profile("Value", "(ref 'x') 42", Profile::Json).is_err());
        assert!(to_profile("Type", ION, Profile::Json).is_err());
        assert!(to_ion("Value", Profile::Json, "{}").is_err());
        assert!(
            to_ion(
                "Value",
                Profile::Json,
                r##"{"Reference":{"attributes":{"x":1},"fqname":"morphir/SDK:basics#add"}}"##,
            )
            .is_err()
        );
    }
}
