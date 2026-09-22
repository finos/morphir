use serde_json::Value;
use std::{
    cmp::Ordering,
    collections::{BTreeMap, BTreeSet},
};
pub(super) fn text(value: &Value) -> Result<&str, String> {
    value.as_str().ok_or_else(|| "expected string".into())
}
pub(super) fn list(value: &Value) -> Result<&[Value], String> {
    value
        .as_array()
        .map(Vec::as_slice)
        .ok_or_else(|| "expected array".into())
}
pub(super) fn equal(actual: &Value, expected: &Value, label: &str) -> Result<(), String> {
    if !deep_equal(actual, expected) {
        Err(format!("{label} mismatch"))
    } else {
        Ok(())
    }
}
// Assertions inherit JSON's number values, not serde's integer/float storage
// variants. Preserve the reference's signed-zero distinction in deep equality.
fn deep_equal(actual: &Value, expected: &Value) -> bool {
    match (actual, expected) {
        (Value::Number(a), Value::Number(b)) => {
            a.as_f64().map(f64::to_bits) == b.as_f64().map(f64::to_bits)
        }
        (Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(a, b)| deep_equal(a, b))
        }
        (Value::Object(a), Value::Object(b)) => {
            a.len() == b.len()
                && a.iter()
                    .all(|(key, a)| b.get(key).is_some_and(|b| deep_equal(a, b)))
        }
        _ => actual == expected,
    }
}
pub(super) fn canonical(value: &Value) -> String {
    match value {
        Value::Number(number) => {
            let number = number.as_f64().expect("finite JSON number");
            if number == 0.0 {
                "0".into()
            } else if (1e-6..1e21).contains(&number.abs()) {
                number.to_string()
            } else {
                let scientific = format!("{number:e}");
                let (mantissa, exponent) = scientific.split_once('e').expect("scientific number");
                format!(
                    "{mantissa}e{}{exponent}",
                    if exponent.starts_with('-') { "" } else { "+" }
                )
            }
        }
        Value::Array(items) => format!(
            "[{}]",
            items.iter().map(canonical).collect::<Vec<_>>().join(",")
        ),
        Value::Object(object) => {
            let mut keys = object.keys().collect::<Vec<_>>();
            keys.sort_by(|a, b| a.encode_utf16().cmp(b.encode_utf16()));
            format!(
                "{{{}}}",
                keys.into_iter()
                    .map(|key| format!(
                        "{}:{}",
                        serde_json::to_string(key).expect("string"),
                        canonical(&object[key])
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        }
        _ => value.to_string(),
    }
}
pub(super) fn unique<'a>(
    values: impl IntoIterator<Item = &'a Value>,
    label: &str,
) -> Result<(), String> {
    let mut keys = BTreeSet::new();
    for value in values {
        if !keys.insert(canonical(value)) {
            return Err(format!("duplicate {label}"));
        }
    }
    Ok(())
}
pub(super) fn sorted(values: &[Value], label: &str) -> Result<(), String> {
    sorted_by(values, label, |a, b| a.cmp(b))
}
pub(super) fn sorted_by(
    values: &[Value],
    label: &str,
    compare: impl Fn(&str, &str) -> Ordering,
) -> Result<(), String> {
    unique(values, label)?;
    let keys = values
        .iter()
        .map(|v| {
            v.as_str()
                .map(str::to_owned)
                .unwrap_or_else(|| canonical(v))
        })
        .collect::<Vec<_>>();
    if keys
        .windows(2)
        .any(|w| compare(&w[0], &w[1]) != Ordering::Less)
    {
        return Err(format!("noncanonical {label} ordering"));
    }
    Ok(())
}
/// Decimal comparisons avoid narrowing the arbitrary-length specification integers.
pub(super) fn decimal_cmp(a: &str, b: &str) -> Ordering {
    a.len().cmp(&b.len()).then_with(|| a.cmp(b))
}
pub(super) fn decimal(value: &Value) -> Result<&str, String> {
    let s = text(value)?;
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) || (s.len() > 1 && s.starts_with('0'))
    {
        return Err("expected canonical decimal".into());
    }
    Ok(s)
}
pub(super) fn successor(value: &str) -> String {
    let mut digits = value.as_bytes().to_vec();
    for d in digits.iter_mut().rev() {
        if *d != b'9' {
            *d += 1;
            return String::from_utf8(digits).expect("digits");
        }
        *d = b'0';
    }
    digits.insert(0, b'1');
    String::from_utf8(digits).expect("digits")
}
pub(super) fn calendar(value: &Value) -> Result<(), String> {
    fn visit(value: &Value, key: &str) -> Result<(), String> {
        if let Some(time) = value.as_str() {
            if ["at", "boundary", "time", "observedAt"].contains(&key)
                && !["before", "after"].contains(&time)
                && !valid_time(time)
            {
                return Err(format!("invalid calendar time {time}"));
            }
        } else {
            match value {
                Value::Array(items) => {
                    for (i, item) in items.iter().enumerate() {
                        visit(item, &i.to_string())?;
                    }
                }
                Value::Object(object) => {
                    for (key, item) in object {
                        if key != "assertions" && key != "equals" {
                            visit(item, key)?;
                        }
                    }
                }
                _ => {}
            }
        }
        Ok(())
    }
    visit(value, "")
}
fn valid_time(time: &str) -> bool {
    let b = time.as_bytes();
    if b.len() != 20
        || b[4] != b'-'
        || b[7] != b'-'
        || b[10] != b'T'
        || b[13] != b':'
        || b[16] != b':'
        || b[19] != b'Z'
    {
        return false;
    }
    let number = |a: usize, z: usize| -> Option<u32> {
        b[a..z].iter().try_fold(0, |n, d| {
            d.is_ascii_digit().then(|| n * 10 + u32::from(*d - b'0'))
        })
    };
    let (Some(y), Some(m), Some(d), Some(h), Some(min), Some(s)) = (
        number(0, 4),
        number(5, 7),
        number(8, 10),
        number(11, 13),
        number(14, 16),
        number(17, 19),
    ) else {
        return false;
    };
    let days = match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) {
                29
            } else {
                28
            }
        }
        _ => 0,
    };
    d > 0 && d <= days && h < 24 && min < 60 && s < 60
}
pub(super) fn tree(value: &Value) -> Result<(), String> {
    let entries = list(&value["entries"])?;
    unique(entries.iter().map(|e| &e["path"]), "tree entry path")?;
    let paths = entries
        .iter()
        .map(|e| Ok((text(&e["path"])?, e)))
        .collect::<Result<BTreeMap<_, _>, String>>()?;
    for entry in entries {
        let path = text(&entry["path"])?;
        for (i, _) in path.match_indices('/') {
            let parent = &path[..i];
            if paths.get(parent).is_none_or(|e| e["kind"] != "directory") {
                return Err(format!("missing tree parent {parent}"));
            }
        }
        if entry["kind"] == "hardlink"
            && paths
                .get(text(&entry["target"])?)
                .is_none_or(|e| e["kind"] != "file")
        {
            return Err(format!(
                "hardlink target must be a fixed regular file {}",
                entry["target"]
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn assertions_use_json_number_values_and_canonical_duplicate_identity() {
        let integer = crate::json::strict::parse("1").unwrap();
        let decimal = crate::json::strict::parse("1.0").unwrap();
        assert!(equal(&integer, &decimal, "JSON numeric assertion").is_ok());
        assert!(unique([&integer, &decimal], "number").is_err());
        assert!(
            equal(
                &crate::json::strict::parse("-0").unwrap(),
                &serde_json::json!(0),
                "signed zero"
            )
            .is_err()
        );
    }
}
