//! Kit-owned reference conversion for admitted semantic Ion cases.
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
    read_ion(node, ion).map(|_| ())
}

pub(super) fn to_profile(node: &str, ion: &str, profile: Profile) -> Result<String, String> {
    let value = read_ion(node, ion)?;
    match profile {
        Profile::Ion => canonical_ion(&value),
        Profile::Json => {
            serde_json::to_string(&value.canonical_json()).map_err(|error| error.to_string())
        }
        Profile::Yaml => match &value {
            ValueReference::Integer(number) => {
                Ok(format!("Literal:\n  IntegerLiteral: {number}\n"))
            }
            ValueReference::Boolean(value) => Ok(format!("Literal:\n  BoolLiteral: {value}\n")),
            _ => {
                serde_saphyr::to_string(&value.canonical_json()).map_err(|error| error.to_string())
            }
        },
    }
}

pub(super) fn to_ion(node: &str, profile: Profile, text: &str) -> Result<String, String> {
    if node != "Value" {
        return Err(format!("reference codec does not support {node}"));
    }
    let value: Value = match profile {
        Profile::Json => serde_json::from_str(text).map_err(|error| error.to_string())?,
        Profile::Yaml => serde_saphyr::from_str(text).map_err(|error| error.to_string())?,
        Profile::Ion => return canonical_ion(&read_ion(node, text)?),
    };
    canonical_ion(&read_profile_value(&value)?)
}

#[derive(Debug, PartialEq, Eq)]
enum ValueReference {
    Reference(String),
    Variable(String),
    Unit,
    Integer(i64),
    Boolean(bool),
}

impl ValueReference {
    fn canonical_json(&self) -> Value {
        match self {
            Self::Reference(name) => json!({"Reference": name}),
            Self::Variable(name) => json!({"Variable": name}),
            Self::Unit => json!({"Unit": {}}),
            Self::Integer(number) => json!({"Literal": {"IntegerLiteral": number}}),
            Self::Boolean(value) => json!({"Literal": {"BoolLiteral": value}}),
        }
    }

    fn ion_element(&self) -> Element {
        match self {
            Self::Reference(name) => Element::from(
                Sequence::builder()
                    .push(Element::symbol("ref"))
                    .push(Element::symbol(name))
                    .build_sexp(),
            ),
            Self::Variable(name) => Element::symbol(name),
            Self::Unit => Element::from(Sequence::builder().build_sexp()),
            Self::Integer(number) => Element::from(ion_rs::Int::from(*number)),
            Self::Boolean(value) => Element::from(*value),
        }
    }
}

fn read_profile_value(value: &Value) -> Result<ValueReference, String> {
    match value {
        Value::String(name) => variable(name),
        Value::Number(number) => number
            .as_i64()
            .map(ValueReference::Integer)
            .ok_or("a Value integer fits i64".to_owned()),
        Value::Bool(value) => Ok(ValueReference::Boolean(*value)),
        Value::Object(fields) if fields.len() == 1 => {
            let (kind, payload) = fields.iter().next().expect("one member");
            match kind.as_str() {
                "Reference" => read_named(payload, "fqname").map(ValueReference::Reference),
                "Variable" => read_named(payload, "name").and_then(|name| variable(&name)),
                "Unit" if empty_attributes(payload) => Ok(ValueReference::Unit),
                "Literal" => read_literal(payload),
                _ => Err(format!("unsupported Value reference shape {kind}")),
            }
        }
        _ => Err("a Value reference has one supported shape".to_owned()),
    }
}

fn empty_attributes(value: &Value) -> bool {
    matches!(value, Value::Object(fields) if fields.is_empty()
        || (fields.len() == 1 && matches!(fields.get("attributes"), Some(Value::Object(attrs)) if attrs.is_empty())))
}

fn read_named(value: &Value, member: &str) -> Result<String, String> {
    match value {
        Value::String(name) => Ok(name.clone()),
        Value::Object(fields)
            if fields.len() == 2
                && matches!(fields.get("attributes"), Some(Value::Object(attrs)) if attrs.is_empty()) =>
        {
            fields
                .get(member)
                .and_then(Value::as_str)
                .map(str::to_owned)
                .ok_or_else(|| format!("an expanded Value reference needs a {member} string"))
        }
        _ => Err(format!(
            "a Value reference needs a string or an expanded {member}"
        )),
    }
}

fn variable(name: &str) -> Result<ValueReference, String> {
    let canonical = name.split('-').all(|segment| {
        !segment.is_empty()
            && (segment
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
                || segment
                    .bytes()
                    .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit()))
    });
    if canonical {
        Ok(ValueReference::Variable(name.to_owned()))
    } else {
        Err(format!("a Value variable name is not canonical: {name}"))
    }
}

fn read_literal(value: &Value) -> Result<ValueReference, String> {
    let literal = match value {
        Value::Object(fields)
            if fields.len() == 2
                && matches!(fields.get("attributes"), Some(Value::Object(attrs)) if attrs.is_empty()) =>
        {
            fields
                .get("literal")
                .ok_or("a Literal needs a literal member")?
        }
        other => other,
    };
    match literal {
        Value::Number(number) => number
            .as_i64()
            .map(ValueReference::Integer)
            .ok_or("an IntegerLiteral fits i64".to_owned()),
        Value::Object(fields) if fields.len() == 1 => {
            let (kind, payload) = fields.iter().next().expect("one member");
            match kind.as_str() {
                "IntegerLiteral" | "WholeNumberLiteral" => {
                    let number = match payload {
                        Value::Object(inner) if inner.len() == 1 => inner.get("value"),
                        other => Some(other),
                    };
                    number
                        .and_then(Value::as_i64)
                        .map(ValueReference::Integer)
                        .ok_or("an IntegerLiteral needs an integer".to_owned())
                }
                "BoolLiteral" => payload
                    .as_bool()
                    .map(ValueReference::Boolean)
                    .ok_or("a BoolLiteral needs a boolean".to_owned()),
                _ => Err(format!("unsupported Literal reference shape {kind}")),
            }
        }
        _ => Err("a Literal reference has a supported payload".to_owned()),
    }
}

fn read_ion(node: &str, text: &str) -> Result<ValueReference, String> {
    if node != "Value" {
        return Err(format!("reference codec does not support {node}"));
    }
    let element = Element::read_one(text.as_bytes()).map_err(|error| error.to_string())?;
    let value = if let Some(name) = element.as_symbol().and_then(|symbol| symbol.text()) {
        variable(name)?
    } else if let Some(number) = element.as_i64() {
        ValueReference::Integer(number)
    } else if let Some(value) = element.as_bool() {
        ValueReference::Boolean(value)
    } else {
        read_sexp(&element)?
    };
    let canonical = canonical_ion(&value)?;
    if normalize_canonical(text) != normalize_canonical(&canonical) {
        return Err(format!(
            "the Ion reference is not canonically spelled; expected {canonical:?}"
        ));
    }
    Ok(value)
}

fn read_sexp(element: &Element) -> Result<ValueReference, String> {
    let sexp = element
        .as_sexp()
        .ok_or("a Value reference is an Ion S-expression or atom")?;
    let parts = sexp.iter().collect::<Vec<_>>();
    if parts.is_empty() {
        return Ok(ValueReference::Unit);
    }
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
    Ok(ValueReference::Reference(name.to_owned()))
}

fn canonical_ion(value: &ValueReference) -> Result<String, String> {
    let sequence = Sequence::builder().push(value.ion_element()).build();
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

    #[test]
    fn value_atoms_convert_independently_between_profiles() {
        for (ion, json) in [
            ("x\n", r#"{"Variable":"x"}"#),
            ("(\n)\n", r#"{"Unit":{}}"#),
            ("42\n", r#"{"Literal":{"IntegerLiteral":42}}"#),
            ("true\n", r#"{"Literal":{"BoolLiteral":true}}"#),
        ] {
            assert_eq!(to_profile("Value", ion, Profile::Json).unwrap(), json);
            assert_eq!(to_ion("Value", Profile::Json, json).unwrap(), ion);
            let yaml = to_profile("Value", ion, Profile::Yaml).unwrap();
            if ion == "42\n" {
                assert_eq!(yaml, "Literal:\n  IntegerLiteral: 42\n");
            }
            if ion == "true\n" {
                assert_eq!(yaml, "Literal:\n  BoolLiteral: true\n");
            }
            assert_eq!(to_ion("Value", Profile::Yaml, &yaml).unwrap(), ion);
            assert_eq!(to_profile("Value", ion, Profile::Ion).unwrap(), ion);
        }
    }

    #[test]
    fn value_atom_reader_aliases_and_malformed_shapes() {
        for (ion, json) in [
            ("x\n", r#""x""#),
            ("x\n", r#"{"Variable":{"attributes":{},"name":"x"}}"#),
            ("(\n)\n", r#"{"Unit":{"attributes":{}}}"#),
            ("42\n", "42"),
            ("42\n", r#"{"Literal":42}"#),
            ("42\n", r#"{"Literal":{"IntegerLiteral":{"value":42}}}"#),
            ("42\n", r#"{"Literal":{"WholeNumberLiteral":42}}"#),
            (
                "42\n",
                r#"{"Literal":{"attributes":{},"literal":{"IntegerLiteral":42}}}"#,
            ),
            ("true\n", "true"),
        ] {
            assert_eq!(to_ion("Value", Profile::Json, json).unwrap(), ion);
        }
        for bad in [
            r#"{"Variable":{"attributes":{"x":1},"name":"x"}}"#,
            r#"{"Unit":{"unexpected":1}}"#,
            r#"{"Literal":{"IntegerLiteral":"42"}}"#,
            r#"{"Literal":{"BoolLiteral":1}}"#,
        ] {
            assert!(to_ion("Value", Profile::Json, bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn variable_names_follow_the_v4_canonical_name_grammar() {
        for valid in ["x", "value-in-USD", "IO-error", "123"] {
            let ion = canonical_ion(&ValueReference::Variable(valid.to_owned())).unwrap();
            assert!(to_profile("Value", &ion, Profile::Json).is_ok());
            assert!(
                to_ion(
                    "Value",
                    Profile::Json,
                    &format!(r#"{{"Variable":"{valid}"}}"#)
                )
                .is_ok()
            );
        }
        for invalid in ["foo_bar", "Usd", "mixedCase", "a--b", "-a", "a-", "café"] {
            let ion = canonical_ion(&ValueReference::Variable(invalid.to_owned())).unwrap();
            assert!(to_profile("Value", &ion, Profile::Json).is_err());
            assert!(
                to_ion(
                    "Value",
                    Profile::Json,
                    &format!(r#"{{"Variable":"{invalid}"}}"#)
                )
                .is_err()
            );
        }
    }
}
