//! Machine output: tab-indented JSON, the form every MCK report and `--json`
//! payload has used since the first driver.

use serde::Serialize;
use serde_json::ser::{PrettyFormatter, Serializer};

pub fn to_tab_json(value: &impl Serialize) -> String {
    let mut out = Vec::new();
    let mut serializer = Serializer::with_formatter(&mut out, PrettyFormatter::with_indent(b"\t"));
    value
        .serialize(&mut serializer)
        .expect("serializing to memory cannot fail for string-keyed data");
    String::from_utf8(out).expect("serde_json writes UTF-8")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn indents_with_tabs() {
        assert_eq!(
            to_tab_json(&serde_json::json!({ "a": [1] })),
            "{\n\t\"a\": [\n\t\t1\n\t]\n}"
        );
    }
}
