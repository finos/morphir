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
            // JSON flow syntax is valid YAML 1.2. Semantic checks need a
            // readable YAML document; spelling cases pin the YAML writer.
            // This also avoids serde_saphyr exposing serde_json's private
            // arbitrary-precision number wrapper in nested literals.
            ValueReference::Tuple(_) | ValueReference::List(_) => {
                serde_json::to_string(&value.canonical_json()).map_err(|error| error.to_string())
            }
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
    Constructor(String),
    Variable(String),
    FieldFunction(String),
    Unit,
    Integer(i64),
    Boolean(bool),
    Tuple(Vec<ValueReference>),
    List(Vec<ValueReference>),
}

impl ValueReference {
    fn canonical_json(&self) -> Value {
        match self {
            Self::Reference(name) => json!({"Reference": name}),
            Self::Constructor(name) => json!({"Constructor": name}),
            Self::Variable(name) => json!({"Variable": name}),
            Self::FieldFunction(name) => json!({"FieldFunction": name}),
            Self::Unit => json!({"Unit": {}}),
            Self::Integer(number) => json!({"Literal": {"IntegerLiteral": number}}),
            Self::Boolean(value) => json!({"Literal": {"BoolLiteral": value}}),
            Self::Tuple(items) => {
                json!({"Tuple": items.iter().map(Self::canonical_json).collect::<Vec<_>>()})
            }
            Self::List(items) => {
                json!({"List": items.iter().map(Self::canonical_json).collect::<Vec<_>>()})
            }
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
            Self::Constructor(name) => Element::from(
                Sequence::builder()
                    .push(Element::symbol("constructor"))
                    .push(Element::symbol(name))
                    .build_sexp(),
            ),
            Self::Variable(name) => Element::symbol(name),
            Self::FieldFunction(name) => Element::from(
                Sequence::builder()
                    .push(Element::symbol("fieldFunction"))
                    .push(Element::symbol(name))
                    .build_sexp(),
            ),
            Self::Unit => Element::from(Sequence::builder().build_sexp()),
            Self::Integer(number) => Element::from(ion_rs::Int::from(*number)),
            Self::Boolean(value) => Element::from(*value),
            Self::Tuple(items) => collection_element("tuple", items),
            Self::List(items) => collection_element("list", items),
        }
    }
}

fn collection_element(head: &str, items: &[ValueReference]) -> Element {
    Element::from(
        items
            .iter()
            .map(ValueReference::ion_element)
            .fold(
                Sequence::builder().push(Element::symbol(head)),
                |builder, item| builder.push(item),
            )
            .build_sexp(),
    )
}

fn read_profile_value(value: &Value) -> Result<ValueReference, String> {
    match value {
        Value::String(name) => variable(name),
        Value::Array(items) => read_items(items).map(ValueReference::List),
        Value::Number(number) => number
            .as_i64()
            .map(ValueReference::Integer)
            .ok_or("a Value integer fits i64".to_owned()),
        Value::Bool(value) => Ok(ValueReference::Boolean(*value)),
        Value::Object(fields) if fields.len() == 1 => {
            let (kind, payload) = fields.iter().next().expect("one member");
            match kind.as_str() {
                "Reference" => read_named(payload, "fqname")
                    .and_then(|name| fqname(&name).map(ValueReference::Reference)),
                "Constructor" => read_named(payload, "fqname")
                    .and_then(|name| fqname(&name).map(ValueReference::Constructor)),
                "Variable" => read_named(payload, "name").and_then(|name| variable(&name)),
                "FieldFunction" => read_named(payload, "name")
                    .and_then(|name| variable(&name).map(|_| ValueReference::FieldFunction(name))),
                "Unit" if empty_attributes(payload) => Ok(ValueReference::Unit),
                "Literal" => read_literal(payload),
                "Tuple" => read_collection(payload, "elements").map(ValueReference::Tuple),
                "List" => read_collection(payload, "items").map(ValueReference::List),
                _ => Err(format!("unsupported Value reference shape {kind}")),
            }
        }
        _ => Err("a Value reference has one supported shape".to_owned()),
    }
}

fn read_items(items: &[Value]) -> Result<Vec<ValueReference>, String> {
    items.iter().map(read_profile_value).collect()
}

fn read_collection(payload: &Value, member: &str) -> Result<Vec<ValueReference>, String> {
    match payload {
        Value::Array(items) => read_items(items),
        Value::Object(fields)
            if fields.len() == 1
                || (fields.len() == 2
                    && matches!(fields.get("attributes"), Some(Value::Object(attrs)) if attrs.is_empty())) =>
        {
            fields
                .get(member)
                .and_then(Value::as_array)
                .ok_or_else(|| format!("a Value {member} collection needs an array"))
                .and_then(|items| read_items(items))
        }
        _ => Err(format!(
            "a Value {member} collection has unsupported members"
        )),
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
    if canonical_name(name) {
        Ok(ValueReference::Variable(name.to_owned()))
    } else {
        Err(format!("a Value variable name is not canonical: {name}"))
    }
}

fn canonical_name(name: &str) -> bool {
    name.split('-').all(|segment| {
        !segment.is_empty()
            && (segment
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
                || segment
                    .bytes()
                    .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit()))
    })
}

fn fqname(name: &str) -> Result<String, String> {
    let valid = name
        .split_once(':')
        .and_then(|(package, tail)| {
            tail.split_once('#')
                .map(|(module, local)| (package, module, local))
        })
        .is_some_and(|(package, module, local)| {
            [package, module]
                .into_iter()
                .all(|path| !path.is_empty() && path.split('/').all(canonical_name))
                && canonical_name(local)
        });
    if valid {
        Ok(name.to_owned())
    } else {
        Err(format!("a Value FQName is not canonical: {name}"))
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
    let value = read_element(&element)?;
    let canonical = canonical_ion(&value)?;
    if normalize_canonical(text) != normalize_canonical(&canonical) {
        return Err(format!(
            "the Ion reference is not canonically spelled; expected {canonical:?}"
        ));
    }
    Ok(value)
}

fn read_element(element: &Element) -> Result<ValueReference, String> {
    Ok(
        if let Some(name) = element.as_symbol().and_then(|symbol| symbol.text()) {
            variable(name)?
        } else if let Some(number) = element.as_i64() {
            ValueReference::Integer(number)
        } else if let Some(value) = element.as_bool() {
            ValueReference::Boolean(value)
        } else {
            read_sexp(element)?
        },
    )
}

fn read_sexp(element: &Element) -> Result<ValueReference, String> {
    let sexp = element
        .as_sexp()
        .ok_or("a Value reference is an Ion S-expression or atom")?;
    let parts = sexp.iter().collect::<Vec<_>>();
    if parts.is_empty() {
        return Ok(ValueReference::Unit);
    }
    let (head, rest) = parts.split_first().expect("nonempty");
    let head = head
        .as_symbol()
        .and_then(|symbol| symbol.text())
        .ok_or("a Value reference head is a symbol")?;
    match head {
        "ref" | "constructor" | "fieldFunction" => {
            let [argument] = rest else {
                return Err(format!("a Value {head} reference has one argument"));
            };
            let name = argument
                .as_symbol()
                .and_then(|symbol| symbol.text())
                .ok_or("a named Value reference names a symbol")?;
            match head {
                "ref" => fqname(name).map(ValueReference::Reference),
                "constructor" => fqname(name).map(ValueReference::Constructor),
                _ => variable(name).map(|_| ValueReference::FieldFunction(name.to_owned())),
            }
        }
        "tuple" | "list" => {
            let items = rest
                .iter()
                .map(|item| read_element(item))
                .collect::<Result<Vec<_>, _>>()?;
            if head == "tuple" {
                Ok(ValueReference::Tuple(items))
            } else {
                Ok(ValueReference::List(items))
            }
        }
        _ => Err(format!("unsupported Value reference head {head}")),
    }
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

    #[test]
    fn named_and_collection_values_convert_between_profiles() {
        for (ion, json) in [
            (
                "(\n  constructor\n  'morphir/SDK:maybe#just'\n)\n",
                r#"{"Constructor":"morphir/SDK:maybe#just"}"#,
            ),
            (
                "(\n  fieldFunction\n  name\n)\n",
                r#"{"FieldFunction":"name"}"#,
            ),
            (
                "(\n  tuple\n  x\n  1\n)\n",
                r#"{"Tuple":[{"Variable":"x"},{"Literal":{"IntegerLiteral":1}}]}"#,
            ),
            (
                "(\n  list\n  1\n  2\n  3\n)\n",
                r#"{"List":[{"Literal":{"IntegerLiteral":1}},{"Literal":{"IntegerLiteral":2}},{"Literal":{"IntegerLiteral":3}}]}"#,
            ),
        ] {
            assert_eq!(to_profile("Value", ion, Profile::Json).unwrap(), json);
            assert_eq!(to_ion("Value", Profile::Json, json).unwrap(), ion);
            let yaml = to_profile("Value", ion, Profile::Yaml).unwrap();
            assert_eq!(to_ion("Value", Profile::Yaml, &yaml).unwrap(), ion);
        }
    }

    #[test]
    fn named_and_collection_reader_aliases_and_invalid_shapes() {
        for (ion, json) in [
            (
                "(\n  constructor\n  'morphir/SDK:maybe#just'\n)\n",
                r#"{"Constructor":{"attributes":{},"fqname":"morphir/SDK:maybe#just"}}"#,
            ),
            (
                "(\n  fieldFunction\n  name\n)\n",
                r#"{"FieldFunction":{"attributes":{},"name":"name"}}"#,
            ),
            (
                "(\n  tuple\n  x\n  1\n)\n",
                r#"{"Tuple":{"attributes":{},"elements":[{"Variable":"x"},{"Literal":{"IntegerLiteral":1}}]}}"#,
            ),
            (
                "(\n  list\n  1\n  2\n  3\n)\n",
                r#"{"List":{"items":[1,2,3]}}"#,
            ),
            ("(\n  list\n  1\n  2\n  3\n)\n", "[1,2,3]"),
        ] {
            assert_eq!(to_ion("Value", Profile::Json, json).unwrap(), ion);
        }
        for bad in [
            r#"{"FieldFunction":"Usd"}"#,
            r#"{"Tuple":{"attributes":{"x":1},"elements":[]}}"#,
            r#"{"List":{"items":[],"unexpected":1}}"#,
        ] {
            assert!(to_ion("Value", Profile::Json, bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn named_references_follow_the_v4_fqname_grammar() {
        for valid in [
            "morphir/SDK:maybe#just",
            "my-org/finance:pricing/models#value-in-USD",
        ] {
            for kind in ["Reference", "Constructor"] {
                let json = format!(r#"{{"{kind}":"{valid}"}}"#);
                assert!(to_ion("Value", Profile::Json, &json).is_ok());
            }
        }
        for invalid in [
            "bad_name:mod#x",
            "pkg:Mod#x",
            "pkg:mod#x_y",
            "pkg/mod#x",
            "pkg:mod#",
        ] {
            for kind in ["Reference", "Constructor"] {
                let json = format!(r#"{{"{kind}":"{invalid}"}}"#);
                assert!(to_ion("Value", Profile::Json, &json).is_err());
            }
        }
    }
}
