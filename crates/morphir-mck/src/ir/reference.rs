//! Kit-owned reference conversion for admitted semantic Ion cases.
//!
//! This module reads the public Ion spelling directly. It does not call an
//! implementation's IR codec, so adapter output cannot define the expected
//! result. Unsupported node shapes fail as kit errors until admitted here.

use indexmap::IndexMap;
use ion_rs::{Element, Sequence, TextFormat};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

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
            serde_json::to_string(&value.canonical_ordered()).map_err(|error| error.to_string())
        }
        Profile::Yaml => {
            match &value {
                ValueReference::Integer(number) => {
                    Ok(format!("Literal:\n  IntegerLiteral: {number}\n"))
                }
                ValueReference::Boolean(value) => Ok(format!("Literal:\n  BoolLiteral: {value}\n")),
                // JSON flow syntax is valid YAML 1.2. Semantic checks need a
                // readable YAML document; spelling cases pin the YAML writer.
                // This also avoids serde_saphyr exposing serde_json's private
                // arbitrary-precision number wrapper in nested literals.
                ValueReference::Tuple(_)
                | ValueReference::List(_)
                | ValueReference::Apply(_, _)
                | ValueReference::IfThenElse(_, _, _)
                | ValueReference::Field(_, _)
                | ValueReference::Record(_)
                | ValueReference::UpdateRecord(_, _) => {
                    serde_json::to_string(&value.canonical_ordered())
                        .map_err(|error| error.to_string())
                }
                _ => serde_saphyr::to_string(&value.canonical_json())
                    .map_err(|error| error.to_string()),
            }
        }
    }
}

pub(super) fn to_ion(node: &str, profile: Profile, text: &str) -> Result<String, String> {
    if node != "Value" {
        return Err(format!("reference codec does not support {node}"));
    }
    let value: OrderedValue = match profile {
        Profile::Json => serde_json::from_str(text).map_err(|error| error.to_string())?,
        Profile::Yaml => serde_saphyr::from_str(text).map_err(|error| error.to_string())?,
        Profile::Ion => return canonical_ion(&read_ion(node, text)?),
    };
    canonical_ion(&read_ordered_profile_value(&value)?)
}

// Record fields are ordered in v4. Keep source member order here instead of
// enabling serde_json's preserve_order feature across unrelated MCK contracts.
#[derive(Debug, Deserialize, Serialize)]
#[serde(untagged)]
enum OrderedValue {
    Null,
    Bool(bool),
    Number(serde_json::Number),
    String(String),
    Array(Vec<OrderedValue>),
    Object(IndexMap<String, OrderedValue>),
}

impl From<Value> for OrderedValue {
    fn from(value: Value) -> Self {
        match value {
            Value::Null => Self::Null,
            Value::Bool(value) => Self::Bool(value),
            Value::Number(value) => Self::Number(value),
            Value::String(value) => Self::String(value),
            Value::Array(values) => Self::Array(values.into_iter().map(Self::from).collect()),
            Value::Object(fields) => Self::Object(
                fields
                    .into_iter()
                    .map(|(name, value)| (name, Self::from(value)))
                    .collect(),
            ),
        }
    }
}

fn ordered_object(fields: impl IntoIterator<Item = (String, OrderedValue)>) -> OrderedValue {
    OrderedValue::Object(fields.into_iter().collect())
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
    String(String),
    Tuple(Vec<ValueReference>),
    List(Vec<ValueReference>),
    Apply(Box<ValueReference>, Box<ValueReference>),
    IfThenElse(
        Box<ValueReference>,
        Box<ValueReference>,
        Box<ValueReference>,
    ),
    Field(Box<ValueReference>, String),
    Record(Vec<(String, ValueReference)>),
    UpdateRecord(Box<ValueReference>, Vec<(String, ValueReference)>),
}

impl ValueReference {
    fn canonical_ordered(&self) -> OrderedValue {
        let node = |kind: &str, payload| ordered_object([(kind.to_owned(), payload)]);
        let members = |fields: Vec<(&str, OrderedValue)>| {
            ordered_object(
                fields
                    .into_iter()
                    .map(|(name, value)| (name.to_owned(), value)),
            )
        };
        let fields = |fields: &[(String, ValueReference)]| {
            ordered_object(
                fields
                    .iter()
                    .map(|(name, value)| (name.clone(), value.canonical_ordered())),
            )
        };
        match self {
            Self::Tuple(items) => node(
                "Tuple",
                OrderedValue::Array(items.iter().map(Self::canonical_ordered).collect()),
            ),
            Self::List(items) => node(
                "List",
                OrderedValue::Array(items.iter().map(Self::canonical_ordered).collect()),
            ),
            Self::Apply(function, argument) => node(
                "Apply",
                members(vec![
                    ("function", function.canonical_ordered()),
                    ("argument", argument.canonical_ordered()),
                ]),
            ),
            Self::IfThenElse(condition, then_branch, else_branch) => node(
                "IfThenElse",
                members(vec![
                    ("condition", condition.canonical_ordered()),
                    ("then", then_branch.canonical_ordered()),
                    ("else", else_branch.canonical_ordered()),
                ]),
            ),
            Self::Field(target, name) => node(
                "Field",
                members(vec![
                    ("target", target.canonical_ordered()),
                    ("name", OrderedValue::String(name.clone())),
                ]),
            ),
            Self::Record(entries) => node("Record", members(vec![("fields", fields(entries))])),
            Self::UpdateRecord(target, entries) => node(
                "UpdateRecord",
                members(vec![
                    ("target", target.canonical_ordered()),
                    ("fields", fields(entries)),
                ]),
            ),
            _ => self.canonical_json().into(),
        }
    }

    fn canonical_json(&self) -> Value {
        match self {
            Self::Reference(name) => json!({"Reference": name}),
            Self::Constructor(name) => json!({"Constructor": name}),
            Self::Variable(name) => json!({"Variable": name}),
            Self::FieldFunction(name) => json!({"FieldFunction": name}),
            Self::Unit => json!({"Unit": {}}),
            Self::Integer(number) => json!({"Literal": {"IntegerLiteral": number}}),
            Self::Boolean(value) => json!({"Literal": {"BoolLiteral": value}}),
            Self::String(value) => json!({"Literal": {"StringLiteral": value}}),
            Self::Tuple(items) => {
                json!({"Tuple": items.iter().map(Self::canonical_json).collect::<Vec<_>>()})
            }
            Self::List(items) => {
                json!({"List": items.iter().map(Self::canonical_json).collect::<Vec<_>>()})
            }
            Self::Apply(function, argument) => json!({"Apply": {
                "function": function.canonical_json(),
                "argument": argument.canonical_json(),
            }}),
            Self::IfThenElse(condition, then_branch, else_branch) => json!({"IfThenElse": {
                "condition": condition.canonical_json(),
                "then": then_branch.canonical_json(),
                "else": else_branch.canonical_json(),
            }}),
            Self::Field(target, name) => json!({"Field": {
                "target": target.canonical_json(),
                "name": name,
            }}),
            Self::Record(fields) => json!({"Record": {"fields": canonical_fields(fields)}}),
            Self::UpdateRecord(target, fields) => json!({"UpdateRecord": {
                "target": target.canonical_json(),
                "fields": canonical_fields(fields),
            }}),
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
            Self::String(value) => sexp_element("string", [Element::string(value.as_str())]),
            Self::Tuple(items) => collection_element("tuple", items),
            Self::List(items) => collection_element("list", items),
            Self::Apply(function, argument) => {
                sexp_element("apply", [function.ion_element(), argument.ion_element()])
            }
            Self::IfThenElse(condition, then_branch, else_branch) => sexp_element(
                "if",
                [
                    condition.ion_element(),
                    then_branch.ion_element(),
                    else_branch.ion_element(),
                ],
            ),
            Self::Field(target, name) => {
                sexp_element("field", [target.ion_element(), Element::symbol(name)])
            }
            Self::Record(fields) => sexp_element("record", ion_fields(fields)),
            Self::UpdateRecord(target, fields) => sexp_element(
                "update",
                std::iter::once(target.ion_element()).chain(ion_fields(fields)),
            ),
        }
    }
}

fn canonical_fields(fields: &[(String, ValueReference)]) -> Value {
    let mut map = Map::new();
    for (name, value) in fields {
        map.insert(name.clone(), value.canonical_json());
    }
    Value::Object(map)
}

fn ion_fields(fields: &[(String, ValueReference)]) -> impl Iterator<Item = Element> {
    fields.iter().map(|(name, value)| {
        Element::from(
            Sequence::builder()
                .push(Element::symbol(name))
                .push(value.ion_element())
                .build_sexp(),
        )
    })
}

fn collection_element(head: &str, items: &[ValueReference]) -> Element {
    sexp_element(head, items.iter().map(ValueReference::ion_element))
}

fn sexp_element(head: &str, rest: impl IntoIterator<Item = Element>) -> Element {
    Element::from(
        rest.into_iter()
            .fold(
                Sequence::builder().push(Element::symbol(head)),
                |builder, item| builder.push(item),
            )
            .build_sexp(),
    )
}

fn read_ordered_profile_value(raw: &OrderedValue) -> Result<ValueReference, String> {
    // Reuse the strict shape checks, then rebuild ordered fields from the
    // source tree. serde_json::Value otherwise sorts object keys.
    let generic = serde_json::to_value(raw).map_err(|error| error.to_string())?;
    let value = read_profile_value(&generic)?;
    restore_record_order(value, raw)
}

fn restore_record_order(
    value: ValueReference,
    raw: &OrderedValue,
) -> Result<ValueReference, String> {
    let payload = |kind: &str| match raw {
        OrderedValue::Object(node) => node.get(kind),
        _ => None,
    };
    let member = |kind: &str, name: &str| match payload(kind) {
        Some(OrderedValue::Object(fields)) => fields.get(name),
        _ => None,
    };
    let children = |items: &[OrderedValue]| {
        items
            .iter()
            .map(read_ordered_profile_value)
            .collect::<Result<Vec<_>, _>>()
    };
    match value {
        ValueReference::Record(_) => {
            let Some(OrderedValue::Object(node)) = payload("Record") else {
                return Err("a Record has an object payload".to_owned());
            };
            let fields = match node.get("fields") {
                Some(OrderedValue::Object(fields)) => fields,
                _ => node,
            };
            Ok(ValueReference::Record(ordered_fields(fields)?))
        }
        ValueReference::UpdateRecord(_, _) => {
            let Some(OrderedValue::Object(fields)) = payload("UpdateRecord") else {
                return Err("an UpdateRecord has an object payload".to_owned());
            };
            let target = fields.get("target").ok_or("an UpdateRecord has a target")?;
            let Some(OrderedValue::Object(entries)) = fields.get("fields") else {
                return Err("an UpdateRecord has fields".to_owned());
            };
            Ok(ValueReference::UpdateRecord(
                Box::new(read_ordered_profile_value(target)?),
                ordered_fields(entries)?,
            ))
        }
        ValueReference::Tuple(_) | ValueReference::List(_) => {
            let (kind, key) = if matches!(value, ValueReference::Tuple(_)) {
                ("Tuple", "elements")
            } else {
                ("List", "items")
            };
            let items = if let OrderedValue::Array(items) = raw {
                Some(items)
            } else {
                match payload(kind) {
                    Some(OrderedValue::Array(items)) => Some(items),
                    Some(OrderedValue::Object(fields)) => fields.get(key).and_then(|value| {
                        if let OrderedValue::Array(items) = value {
                            Some(items)
                        } else {
                            None
                        }
                    }),
                    _ => None,
                }
            }
            .ok_or("a collection has items")?;
            if kind == "Tuple" {
                children(items).map(ValueReference::Tuple)
            } else {
                children(items).map(ValueReference::List)
            }
        }
        ValueReference::Apply(_, _) => Ok(ValueReference::Apply(
            Box::new(read_ordered_profile_value(
                member("Apply", "function").ok_or("Apply function")?,
            )?),
            Box::new(read_ordered_profile_value(
                member("Apply", "argument").ok_or("Apply argument")?,
            )?),
        )),
        ValueReference::IfThenElse(_, _, _) => Ok(ValueReference::IfThenElse(
            Box::new(read_ordered_profile_value(
                member("IfThenElse", "condition").ok_or("If condition")?,
            )?),
            Box::new(read_ordered_profile_value(
                member("IfThenElse", "then").ok_or("If then")?,
            )?),
            Box::new(read_ordered_profile_value(
                member("IfThenElse", "else").ok_or("If else")?,
            )?),
        )),
        ValueReference::Field(_, name) => Ok(ValueReference::Field(
            Box::new(read_ordered_profile_value(
                member("Field", "target").ok_or("Field target")?,
            )?),
            name,
        )),
        other => Ok(other),
    }
}

fn ordered_fields(
    fields: &IndexMap<String, OrderedValue>,
) -> Result<Vec<(String, ValueReference)>, String> {
    fields
        .iter()
        .map(|(name, value)| Ok((name.clone(), read_ordered_profile_value(value)?)))
        .collect()
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
                "Apply" => {
                    let members = read_members(payload, &["function", "argument"])?;
                    Ok(ValueReference::Apply(
                        Box::new(read_profile_value(&members["function"])?),
                        Box::new(read_profile_value(&members["argument"])?),
                    ))
                }
                "IfThenElse" => {
                    let members = read_members(payload, &["condition", "then", "else"])?;
                    Ok(ValueReference::IfThenElse(
                        Box::new(read_profile_value(&members["condition"])?),
                        Box::new(read_profile_value(&members["then"])?),
                        Box::new(read_profile_value(&members["else"])?),
                    ))
                }
                "Field" => {
                    let members = read_members(payload, &["target", "name"])?;
                    let name = members["name"].as_str().ok_or("a Field name is a string")?;
                    if !canonical_name(name) {
                        return Err(format!("a Field name is not canonical: {name}"));
                    }
                    Ok(ValueReference::Field(
                        Box::new(read_profile_value(&members["target"])?),
                        name.to_owned(),
                    ))
                }
                "Record" => read_record_payload(payload).map(ValueReference::Record),
                "UpdateRecord" => {
                    let members = read_members(payload, &["target", "fields"])?;
                    Ok(ValueReference::UpdateRecord(
                        Box::new(read_profile_value(&members["target"])?),
                        read_profile_fields(&members["fields"])?,
                    ))
                }
                _ => Err(format!("unsupported Value reference shape {kind}")),
            }
        }
        _ => Err("a Value reference has one supported shape".to_owned()),
    }
}

fn read_record_payload(payload: &Value) -> Result<Vec<(String, ValueReference)>, String> {
    let Value::Object(members) = payload else {
        return Err("a Record has an object payload".to_owned());
    };
    if let Some(fields) = members.get("fields") {
        let allowed = members.len() == 1
            || (members.len() == 2
                && ["attributes", "attrs"].iter().any(|name| {
                    matches!(members.get(*name), Some(Value::Object(attrs)) if attrs.is_empty())
                }));
        if !allowed {
            return Err("a Record has fields and optional empty attributes".to_owned());
        }
        read_profile_fields(fields)
    } else {
        read_profile_fields(payload)
    }
}

fn read_profile_fields(value: &Value) -> Result<Vec<(String, ValueReference)>, String> {
    let Value::Object(fields) = value else {
        return Err("record fields are an object".to_owned());
    };
    fields
        .iter()
        .map(|(name, value)| {
            if !canonical_name(name) {
                return Err(format!("a Record field name is not canonical: {name}"));
            }
            Ok((name.clone(), read_profile_value(value)?))
        })
        .collect()
}

fn read_members<'a>(payload: &'a Value, names: &[&str]) -> Result<&'a Map<String, Value>, String> {
    let Value::Object(members) = payload else {
        return Err("a Value node has an object payload".to_owned());
    };
    let attributes = match members.get("attributes") {
        None => 0,
        Some(Value::Object(attrs)) if attrs.is_empty() => 1,
        _ => return Err("a Value node has empty attributes".to_owned()),
    };
    if members.len() != names.len() + attributes
        || names.iter().any(|name| !members.contains_key(*name))
    {
        return Err(format!(
            "a Value node has exactly {} required members",
            names.len()
        ));
    }
    Ok(members)
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
                "StringLiteral" => payload
                    .as_str()
                    .map(|text| ValueReference::String(text.to_owned()))
                    .ok_or("a StringLiteral needs a string".to_owned()),
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
        "apply" => {
            let [function, argument] = rest else {
                return Err("an Apply has a function and argument".to_owned());
            };
            Ok(ValueReference::Apply(
                Box::new(read_element(function)?),
                Box::new(read_element(argument)?),
            ))
        }
        "if" => {
            let [condition, then_branch, else_branch] = rest else {
                return Err("an IfThenElse has a condition and two branches".to_owned());
            };
            Ok(ValueReference::IfThenElse(
                Box::new(read_element(condition)?),
                Box::new(read_element(then_branch)?),
                Box::new(read_element(else_branch)?),
            ))
        }
        "field" => {
            let [target, name] = rest else {
                return Err("a Field has a target and name".to_owned());
            };
            let name = name
                .as_symbol()
                .and_then(|symbol| symbol.text())
                .ok_or("a Field name is a symbol")?;
            if !canonical_name(name) {
                return Err(format!("a Field name is not canonical: {name}"));
            }
            Ok(ValueReference::Field(
                Box::new(read_element(target)?),
                name.to_owned(),
            ))
        }
        "string" => {
            let [text] = rest else {
                return Err("a StringLiteral has one argument".to_owned());
            };
            text.as_string()
                .map(|text| ValueReference::String(text.to_owned()))
                .ok_or("a StringLiteral has a string argument".to_owned())
        }
        "record" => read_ion_fields(rest).map(ValueReference::Record),
        "update" => {
            let Some((target, fields)) = rest.split_first() else {
                return Err("an UpdateRecord has a target".to_owned());
            };
            Ok(ValueReference::UpdateRecord(
                Box::new(read_element(target)?),
                read_ion_fields(fields)?,
            ))
        }
        _ => Err(format!("unsupported Value reference head {head}")),
    }
}

fn read_ion_fields(parts: &[&Element]) -> Result<Vec<(String, ValueReference)>, String> {
    let mut fields = Vec::new();
    for part in parts {
        let pair = part
            .as_sexp()
            .ok_or("a Record field is a pair")?
            .iter()
            .collect::<Vec<_>>();
        let [name, value] = pair.as_slice() else {
            return Err("a Record field has a name and value".to_owned());
        };
        let name = name
            .as_symbol()
            .and_then(|symbol| symbol.text())
            .ok_or("a Record field name is a symbol")?;
        if !canonical_name(name) || fields.iter().any(|(existing, _)| existing == name) {
            return Err(format!(
                "a Record field name is invalid or repeated: {name}"
            ));
        }
        fields.push((name.to_owned(), read_element(value)?));
    }
    Ok(fields)
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
            assert_eq!(
                serde_json::from_str::<Value>(&to_profile("Value", ion, Profile::Json).unwrap())
                    .unwrap(),
                serde_json::from_str::<Value>(json).unwrap(),
            );
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

    #[test]
    fn control_values_convert_between_profiles() {
        for (ion, json) in [
            (
                "(\n  apply\n  (\n    ref\n    'morphir/SDK:basics#negate'\n  )\n  1\n)\n",
                r#"{"Apply":{"function":{"Reference":"morphir/SDK:basics#negate"},"argument":{"Literal":{"IntegerLiteral":1}}}}"#,
            ),
            (
                "(\n  if\n  true\n  1\n  2\n)\n",
                r#"{"IfThenElse":{"condition":{"Literal":{"BoolLiteral":true}},"then":{"Literal":{"IntegerLiteral":1}},"else":{"Literal":{"IntegerLiteral":2}}}}"#,
            ),
            (
                "(\n  field\n  record\n  'field-name'\n)\n",
                r#"{"Field":{"target":{"Variable":"record"},"name":"field-name"}}"#,
            ),
        ] {
            assert_eq!(
                serde_json::from_str::<Value>(&to_profile("Value", ion, Profile::Json).unwrap())
                    .unwrap(),
                serde_json::from_str::<Value>(json).unwrap(),
            );
            assert_eq!(to_ion("Value", Profile::Json, json).unwrap(), ion);
            let yaml = to_profile("Value", ion, Profile::Yaml).unwrap();
            assert_eq!(to_ion("Value", Profile::Yaml, &yaml).unwrap(), ion);
        }
    }

    #[test]
    fn control_values_reject_bad_members_and_names() {
        for json in [
            r#"{"Apply":{"function":{"Variable":"f"}}}"#,
            r#"{"IfThenElse":{"condition":true,"then":1,"else":2,"extra":0}}"#,
            r#"{"Field":{"target":{"Variable":"record"},"name":"bad_name"}}"#,
            r#"{"Field":{"attributes":{"x":1},"target":{"Variable":"record"},"name":"field-name"}}"#,
        ] {
            assert!(to_ion("Value", Profile::Json, json).is_err(), "{json}");
        }
    }

    #[test]
    fn record_values_preserve_field_order_across_profiles() {
        for (ion, json) in [
            (
                "(\n  record\n  (\n    name\n    x\n  )\n  (\n    age\n    25\n  )\n)\n",
                r#"{"Record":{"fields":{"name":{"Variable":"x"},"age":{"Literal":{"IntegerLiteral":25}}}}}"#,
            ),
            (
                "(\n  update\n  record\n  (\n    name\n    (\n      string\n      \"new\"\n    )\n  )\n)\n",
                r#"{"UpdateRecord":{"target":{"Variable":"record"},"fields":{"name":{"Literal":{"StringLiteral":"new"}}}}}"#,
            ),
        ] {
            assert_eq!(to_ion("Value", Profile::Json, json).unwrap(), ion);
            let canonical_json = to_profile("Value", ion, Profile::Json).unwrap();
            assert_eq!(
                to_ion("Value", Profile::Json, &canonical_json).unwrap(),
                ion
            );
            let yaml = to_profile("Value", ion, Profile::Yaml).unwrap();
            assert_eq!(to_ion("Value", Profile::Yaml, &yaml).unwrap(), ion);
        }
    }

    #[test]
    fn record_values_reject_duplicate_or_invalid_fields() {
        for ion in [
            "(record (name x) (name y))",
            "(record (bad_name x))",
            "(update record (name x y))",
        ] {
            assert!(to_profile("Value", ion, Profile::Json).is_err(), "{ion}");
        }
        for json in [
            r#"{"Record":{"fields":{"bad_name":{"Variable":"x"}}}}"#,
            r#"{"Record":{"fields":{},"unexpected":1}}"#,
            r#"{"UpdateRecord":{"target":{"Variable":"record"},"fields":{"name":{"Variable":"x"}},"extra":0}}"#,
        ] {
            assert!(to_ion("Value", Profile::Json, json).is_err(), "{json}");
        }
    }

    #[test]
    fn nested_records_keep_order_when_transcoded() {
        let json = r#"{"Apply":{"function":{"Variable":"f"},"argument":{"Record":{"fields":{"name":{"Variable":"x"},"age":{"Literal":{"IntegerLiteral":25}}}}}}}"#;
        let ion = to_ion("Value", Profile::Json, json).unwrap();
        assert!(ion.find("name").unwrap() < ion.find("age").unwrap());
        for profile in [Profile::Json, Profile::Yaml] {
            let encoded = to_profile("Value", &ion, profile).unwrap();
            assert_eq!(to_ion("Value", profile, &encoded).unwrap(), ion);
        }
    }
}
