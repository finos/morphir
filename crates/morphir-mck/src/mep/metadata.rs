//! Independent source metadata expectations for the fixed Boolean guest kit.
use ion_rs::{Element, IonData};
use serde_json::Value;
use std::collections::BTreeMap;

const OWNER: &str = "urn:finos:morphir-moonbit:node-metadata:v1";
const PREFIX: &str = "value:mck/bool:main#";

fn require(condition: bool, message: &str) -> Result<(), String> {
    if condition {
        Ok(())
    } else {
        Err(message.to_owned())
    }
}

fn member<'a>(value: &'a Element, name: &str) -> Result<&'a Element, String> {
    let fields = value
        .as_struct()
        .ok_or("metadata value must be an Ion struct")?;
    let mut found = fields.iter().filter(|(key, _)| key.text() == Some(name));
    let (_, value) = found
        .next()
        .ok_or_else(|| format!("missing metadata field {name}"))?;
    require(
        found.next().is_none(),
        &format!("duplicate metadata field {name}"),
    )?;
    Ok(value)
}

fn text(value: &Element) -> Result<&str, String> {
    value
        .as_string()
        .ok_or("metadata value must be an Ion string".into())
}

fn list(value: &Element) -> Result<Vec<&Element>, String> {
    value
        .as_list()
        .map(|values| values.iter().collect())
        .ok_or("metadata value must be an Ion list".into())
}

fn annotation(value: &Element, expected: &str) -> bool {
    value
        .annotations()
        .iter()
        .map(|symbol| symbol.text())
        .collect::<Vec<_>>()
        == [Some(expected)]
}

fn carrier(root: &Element) -> Result<&Element, String> {
    let mut carriers = Vec::new();
    for entry in list(member(root, "enrichments")?)? {
        if text(member(entry, "owner")?)? == OWNER {
            carriers.push(member(entry, "data")?);
        }
    }
    require(
        carriers.len() == 1,
        "exactly one source metadata carrier is required",
    )?;
    Ok(carriers[0])
}

fn keyed_nodes<'a>(
    values: &'a Element,
    key: &str,
) -> Result<BTreeMap<&'a str, &'a Element>, String> {
    let mut result = BTreeMap::new();
    for node in list(values)? {
        let id = text(member(node, key)?)?;
        require(
            result.insert(id, member(node, "data")?).is_none(),
            "duplicate source node identity",
        )?;
    }
    Ok(result)
}

fn annotated<'a>(values: &'a Element, expected: &str) -> Result<&'a Element, String> {
    let selected = list(values)?
        .into_iter()
        .filter(|value| annotation(value, expected))
        .collect::<Vec<_>>();
    require(
        selected.len() == 1,
        &format!("exactly one {expected} provenance entry is required"),
    )?;
    Ok(selected[0])
}

fn validate_origin(
    value: &Element,
    name: &str,
    line: i64,
    start: i64,
    end: i64,
) -> Result<(), String> {
    require(
        text(member(value, "name")?)? == name,
        "original source origin name changed",
    )?;
    require(
        text(member(value, "coordinate_profile")?)? == "moonbit-parser-position-v1",
        "source coordinate profile changed",
    )?;
    for (field, expected) in [
        ("start_line", line),
        ("end_line", line),
        ("start_column", start),
        ("end_column", end),
    ] {
        require(
            member(value, field)?.as_i64() == Some(expected),
            &format!("source origin coordinate changed: {name}.{field}"),
        )?;
    }
    Ok(())
}

pub(crate) fn validate_model(source: &Value, root: &Element) -> Result<(), String> {
    validate_bounds(root)?;
    require(
        annotation(root, "morphir_model"),
        "model annotation missing",
    )?;
    let data = carrier(root)?;
    let uri = source
        .pointer("/sources/documents/0/uri")
        .and_then(Value::as_str)
        .ok_or("kit source URI missing")?;
    require(
        text(member(data, "sourceUnitId")?)? == uri,
        "source unit identity changed",
    )?;
    let annotations = Element::read_one("[morphir_pipeline]").map_err(|e| e.to_string())?;
    require(
        member(data, "sourceAnnotations")? == &annotations,
        "source annotations changed",
    )?;
    let nodes = keyed_nodes(member(data, "nodes")?, "nodeId")?;
    let expected = [
        format!("{PREFIX}always"),
        format!("{PREFIX}always/body"),
        format!("{PREFIX}is-ready"),
        format!("{PREFIX}is-ready/body"),
    ];
    require(
        nodes.keys().copied().collect::<Vec<_>>()
            == expected.iter().map(String::as_str).collect::<Vec<_>>(),
        "source node inventory differs",
    )?;
    for (identity, original) in [("is-ready", "isReady"), ("always", "always")] {
        let declaration = nodes[format!("{PREFIX}{identity}").as_str()];
        let (line, end, body_start, body_end) = if identity == "is-ready" {
            (1, 14, 44, 54)
        } else {
            (2, 13, 26, 30)
        };
        validate_origin(member(declaration, "declaration")?, original, line, 7, end)?;
        require(
            text(member(member(declaration, "declaration")?, "name")?)? == original,
            "original declaration name changed",
        )?;
        let naming = member(declaration, "naming")?;
        require(
            text(member(naming, "original")?)? == original
                && text(member(naming, "identity")?)? == identity,
            "declaration naming metadata changed",
        )?;
        let parameters = list(member(declaration, "parameters")?)?;
        if identity == "is-ready" {
            require(parameters.len() == 1, "source parameter missing")?;
            validate_origin(parameters[0], "flag_value", 1, 15, 25)?;
            require(
                text(member(parameters[0], "name")?)? == "flag_value"
                    && text(member(parameters[0], "identity")?)? == "flag-value",
                "original parameter metadata changed",
            )?;
        } else {
            require(parameters.is_empty(), "unexpected source parameters")?;
        }
        let body = nodes[format!("{PREFIX}{identity}/body").as_str()];
        validate_origin(member(body, "body")?, original, line, body_start, body_end)?;
        require(
            text(member(member(body, "body")?, "name")?)? == original,
            "source body origin changed",
        )?;
        list(member(body, "nodes")?)?;
    }
    let provenance = member(root, "provenance")?;
    let frontend = annotated(provenance, "morphir_moonbit_frontend")?;
    require(
        text(member(frontend, "unit_id")?)? == uri,
        "frontend source identity changed",
    )?;
    require(
        text(member(frontend, "language")?)? == "moonbit",
        "frontend source language changed",
    )?;
    require(
        text(member(frontend, "profile")?)? == super::PROFILE,
        "frontend source profile changed",
    )?;
    let compilation = annotated(provenance, "morphir_moonbit_compilation")?;
    let version = source
        .pointer("/sources/documents/0/version")
        .and_then(Value::as_u64)
        .ok_or("kit source version missing")?
        .to_string();
    let expected = serde_json::json!({"sourceUri":uri,"sourceVersion":version,"sourceRoot":source["sources"]["root"],"packageName":source["package"]["name"],"exposedModules":source["package"]["exposedModules"],"options":source["options"],"contextDigest":source["contextDigest"]});
    for (name, value) in expected.as_object().unwrap() {
        let expected = Element::read_one(value.to_string()).map_err(|e| e.to_string())?;
        require(
            member(compilation, name)? == &expected,
            &format!("compilation provenance changed: {name}"),
        )?;
    }
    Ok(())
}

pub(crate) fn validate_symbols(
    source: &Value,
    symbols: &Element,
    source_root: Option<&Element>,
) -> Result<(), String> {
    validate_bounds(symbols)?;
    require(
        annotation(symbols, "morphir_moonbit_symbols"),
        "symbol metadata annotation missing",
    )?;
    require(
        text(member(symbols, "profile")?)? == "morphir-moonbit-symbols-2026-10-17",
        "symbol metadata profile changed",
    )?;
    require(
        text(member(symbols, "naming_policy")?)? == "moonbit-readable-targets-v1",
        "symbol naming policy changed",
    )?;
    let ir = crate::json::strict::parse_exact(text(member(symbols, "source_ir_json")?)?)?;
    require(ir.is_object(), "symbol source IR must be a JSON object")?;
    let retained = keyed_nodes(member(symbols, "metadata")?, "node_id")?;
    let expected_names = if let Some(root) = source_root {
        validate_model(source, root)?;
        let data = carrier(root)?;
        let original = keyed_nodes(member(data, "nodes")?, "nodeId")?;
        require(
            original.len() == retained.len()
                && original.iter().all(|(id, data)| {
                    retained
                        .get(id)
                        .is_some_and(|value| IonData::eq(*data, *value))
                }),
            "source metadata was dropped or changed in symbols",
        )?;
        require(
            IonData::eq(
                member(symbols, "source_annotations")?,
                member(data, "sourceAnnotations")?,
            ),
            "source annotations were changed in symbols",
        )?;
        require(
            IonData::eq(
                member(symbols, "source_provenance")?,
                member(root, "provenance")?,
            ),
            "source provenance was changed in symbols",
        )?;
        require(
            member(symbols, "unit_id")? == member(data, "sourceUnitId")?,
            "source unit identity was changed in symbols",
        )?;
        vec![("always", "always"), ("is-ready", "isReady")]
    } else {
        require(retained.is_empty(), "plain IR invented source metadata")?;
        require(
            list(member(symbols, "source_annotations")?)?.is_empty()
                && list(member(symbols, "source_provenance")?)?.is_empty(),
            "plain IR invented source provenance or annotations",
        )?;
        require(
            text(member(symbols, "unit_id")?)? == "mep",
            "plain IR source identity changed",
        )?;
        vec![("always", "always")]
    };
    let mut mappings = BTreeMap::new();
    for symbol in list(member(symbols, "symbols")?)? {
        require(
            mappings
                .insert(text(member(symbol, "fqname")?)?, symbol)
                .is_none(),
            "duplicate generated symbol identity",
        )?;
    }
    require(
        mappings.len() == expected_names.len(),
        "generated symbol inventory changed",
    )?;
    for (identity, generated) in expected_names {
        let fqname = format!("mck/bool:main#{identity}");
        let symbol = mappings
            .get(fqname.as_str())
            .ok_or("expected generated symbol missing")?;
        require(
            text(member(symbol, "generated_name")?)? == generated,
            "generated symbol name changed",
        )?;
        require(
            member(symbol, "public")?.as_bool() == Some(true),
            "public source symbol lost visibility",
        )?;
        let node = format!("{PREFIX}{identity}");
        require(
            text(member(symbol, "source_node")?)? == node
                && text(member(symbol, "generated_node")?)? == format!("moonbit:fn:{generated}"),
            "generated symbol node identity changed",
        )?;
        let origins = list(member(symbol, "origins")?)?
            .into_iter()
            .map(text)
            .collect::<Result<Vec<_>, _>>()?;
        require(
            origins == [node.as_str(), format!("{node}/body").as_str()],
            "source/body symbol origins changed",
        )?;
    }
    Ok(())
}

/// Inspect every Ion value, including opaque metadata and provenance.
/// An explicit stack avoids recursive validation of untrusted nesting.
pub(crate) fn validate_bounds(root: &Element) -> Result<(), String> {
    let mut pending = vec![(root, 1_usize)];
    let mut nodes = 0;
    while let Some((value, depth)) = pending.pop() {
        nodes += 1;
        require(
            depth <= 128 && nodes <= 100000,
            "Ion document exceeds negotiated depth or node limit",
        )?;
        if let Some(fields) = value.as_struct() {
            pending.extend(fields.iter().map(|(_, value)| (value, depth + 1)));
        } else if let Some(values) = value.as_sequence() {
            pending.extend(values.iter().map(|value| (value, depth + 1)));
        }
    }
    Ok(())
}

#[cfg(test)]
pub(super) fn synthetic_model(ir: &Value) -> Element {
    Element::read_one(tests::model_text().replacen("ir:{}", &format!("ir:{ir}"), 1)).unwrap()
}

#[cfg(test)]
pub(super) fn synthetic_symbols(root: &Element, ir: &Value) -> Element {
    let encoded = serde_json::to_string(&ir.to_string()).unwrap();
    Element::read_one(tests::symbols_text(root).replacen(
        "source_ir_json:\"{}\"",
        &format!("source_ir_json:{encoded}"),
        1,
    ))
    .unwrap()
}

#[cfg(test)]
pub(super) fn synthetic_plain_symbols(ir: &Value) -> Element {
    let encoded = serde_json::to_string(&ir.to_string()).unwrap();
    Element::read_one(format!(r#"morphir_moonbit_symbols::{{profile:"morphir-moonbit-symbols-2026-10-17",naming_policy:"moonbit-readable-targets-v1",unit_id:"mep",source_ir_json:{encoded},metadata:[],source_annotations:[],source_provenance:[],symbols:[
      {{fqname:"mck/bool:main#always",generated_name:"always",public:true,source_node:"value:mck/bool:main#always",generated_node:"moonbit:fn:always",origins:["value:mck/bool:main#always","value:mck/bool:main#always/body"]}}
    ]}}"#)).unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn source() -> Value {
        serde_json::from_str::<Value>(include_str!(
            "../../../../spec/mep/mck/guest-moonbit-bool.json"
        ))
        .unwrap()["source"]
            .clone()
    }
    pub(super) fn model_text() -> String {
        r#"morphir_model::{ir:{},enrichments:[{
          owner:"urn:finos:morphir-moonbit:node-metadata:v1",
          data:{sourceUnitId:"file:///mck/source/main.mbt",sourceAnnotations:[morphir_pipeline],nodes:[
            {nodeId:"value:mck/bool:main#is-ready",data:{declaration:{name:"isReady",coordinate_profile:"moonbit-parser-position-v1",start_line:1,start_column:7,end_line:1,end_column:14},naming:{original:"isReady",identity:"is-ready"},parameters:[{name:"flag_value",identity:"flag-value",coordinate_profile:"moonbit-parser-position-v1",start_line:1,start_column:15,end_line:1,end_column:25}]}},
            {nodeId:"value:mck/bool:main#is-ready/body",data:{body:{name:"isReady",coordinate_profile:"moonbit-parser-position-v1",start_line:1,start_column:44,end_line:1,end_column:54},nodes:[]}},
            {nodeId:"value:mck/bool:main#always",data:{declaration:{name:"always",coordinate_profile:"moonbit-parser-position-v1",start_line:2,start_column:7,end_line:2,end_column:13},naming:{original:"always",identity:"always"},parameters:[]}},
            {nodeId:"value:mck/bool:main#always/body",data:{body:{name:"always",coordinate_profile:"moonbit-parser-position-v1",start_line:2,start_column:26,end_line:2,end_column:30},nodes:[]}}
          ]}
        }],provenance:[
          morphir_moonbit_frontend::{unit_id:"file:///mck/source/main.mbt",language:"moonbit",profile:"moonbit-model-stable-v1",parser_version:"0.4.5",naming_policy:"moonbit-readable-names-v1"},
          morphir_moonbit_compilation::{sourceUri:"file:///mck/source/main.mbt",sourceVersion:"19",sourceRoot:"file:///mck/source",packageName:"mck/bool",exposedModules:["main"],options:{typesOnly:false,irVersion:"4.0.0",profile:"moonbit-model-stable-v1"},contextDigest:"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}
        ]}"#.to_owned()
    }
    #[test]
    fn source_context_and_original_names_are_required() {
        let text = model_text();
        let model = Element::read_one(&text).unwrap();
        validate_model(&source(), &model).unwrap();
        for changed in [
            text.replace("sourceVersion:\"19\"", "sourceVersion:\"20\""),
            text.replace("\"isReady\"", "\"changed\""),
            text.replace("name:\"flag_value\"", "name:\"wrong\""),
            text.replace(
                "sourceAnnotations:[morphir_pipeline]",
                "sourceAnnotations:[]",
            ),
        ] {
            assert!(validate_model(&source(), &Element::read_one(changed).unwrap()).is_err());
        }
    }

    pub(super) fn symbols_text(root: &Element) -> String {
        let data = carrier(root).unwrap();
        let metadata = keyed_nodes(member(data, "nodes").unwrap(), "nodeId")
            .unwrap()
            .iter()
            .map(|(id, value)| {
                format!(
                    "{{node_id:{},data:{value}}}",
                    serde_json::to_string(id).unwrap()
                )
            })
            .collect::<Vec<_>>()
            .join(",");
        format!(
            r#"morphir_moonbit_symbols::{{profile:"morphir-moonbit-symbols-2026-10-17",naming_policy:"moonbit-readable-targets-v1",unit_id:"file:///mck/source/main.mbt",source_ir_json:"{{}}",metadata:[{metadata}],source_annotations:{},source_provenance:{},symbols:[
          {{fqname:"mck/bool:main#is-ready",generated_name:"isReady",public:true,source_node:"value:mck/bool:main#is-ready",generated_node:"moonbit:fn:isReady",origins:["value:mck/bool:main#is-ready","value:mck/bool:main#is-ready/body"]}},
          {{fqname:"mck/bool:main#always",generated_name:"always",public:true,source_node:"value:mck/bool:main#always",generated_node:"moonbit:fn:always",origins:["value:mck/bool:main#always","value:mck/bool:main#always/body"]}}
        ]}}"#,
            member(data, "sourceAnnotations").unwrap(),
            member(root, "provenance").unwrap()
        )
    }

    #[test]
    fn symbols_preserve_metadata_as_ion_and_source_spelling() {
        let root = Element::read_one(model_text()).unwrap();
        let text = symbols_text(&root);
        validate_symbols(&source(), &Element::read_one(&text).unwrap(), Some(&root)).unwrap();
        for changed in [
            text.replace("original: \"isReady\"", "original: \"changed\""),
            text.replace("generated_name:\"isReady\"", "generated_name:\"is_ready\""),
            text.replace(
                "source_annotations:[morphir_pipeline]",
                "source_annotations:[]",
            ),
            text.replace("\"19\"", "\"20\""),
        ] {
            assert_ne!(changed, text, "mutation must change the fixture");
            assert!(
                validate_symbols(&source(), &Element::read_one(changed).unwrap(), Some(&root))
                    .is_err()
            );
        }
    }

    #[test]
    fn symbol_retention_includes_decimal_scale_and_annotation_order() {
        let root = Element::read_one(model_text().replace(
            "identity:\"is-ready\"",
            "identity:\"is-ready\",opaque:first::second::1.00",
        ))
        .unwrap();
        let text = symbols_text(&root);
        validate_symbols(&source(), &Element::read_one(&text).unwrap(), Some(&root)).unwrap();
        for changed in [
            text.replace("1.00", "1.0"),
            text.replace("first::second", "second::first"),
        ] {
            assert_ne!(changed, text);
            assert!(
                validate_symbols(&source(), &Element::read_one(changed).unwrap(), Some(&root))
                    .is_err(),
                "Ion representation was changed"
            );
        }
    }

    #[test]
    fn fixed_source_coordinates_are_verified_independently() {
        let text = model_text();
        validate_model(&source(), &Element::read_one(&text).unwrap()).unwrap();
        for changed in [
            text.replacen("start_column:7", "start_column:8", 1),
            text.replace("end_column:25", "end_column:26"),
            text.replace("end_column:54", "end_column:53"),
            text.replace("moonbit-parser-position-v1", "wrong-profile"),
        ] {
            assert_ne!(changed, text);
            assert!(validate_model(&source(), &Element::read_one(changed).unwrap()).is_err());
        }
    }

    #[test]
    fn plain_symbols_have_no_original_source_metadata() {
        let symbols = synthetic_plain_symbols(&serde_json::json!({}));
        validate_symbols(&source(), &symbols, None).unwrap();
        let changed = symbols
            .to_string()
            .replace("metadata: []", "metadata: [{node_id:\"fake\",data:{}}]");
        assert_ne!(changed, symbols.to_string());
        assert!(validate_symbols(&source(), &Element::read_one(changed).unwrap(), None).is_err());
        let root = synthetic_model(&serde_json::json!({}));
        let rich = synthetic_symbols(&root, &serde_json::json!({}));
        validate_symbols(&source(), &rich, Some(&root)).unwrap();
    }

    #[test]
    fn whole_document_limits_cover_opaque_fields() {
        let too_deep = format!("{}0{}", "[".repeat(129), "]".repeat(129));
        let wide = format!("[{}]", vec!["0"; 100001].join(","));
        for opaque in [too_deep, wide] {
            let model = Element::read_one(model_text().replacen(
                "ir:{}",
                &format!("ir:{{}},opaque:{opaque}"),
                1,
            ))
            .unwrap();
            assert!(validate_model(&source(), &model).is_err());
        }
        let allowed = Element::read_one(model_text().replacen(
            "ir:{}",
            "ir:{},opaque:first::second::{n:123456789012345678901234567890,scaled:1.00}",
            1,
        ))
        .unwrap();
        validate_model(&source(), &allowed).unwrap();
    }

    #[test]
    fn missing_or_duplicate_source_metadata_is_refused() {
        let text = model_text();
        for changed in [
            text.replace(OWNER, "urn:mck:unknown"),
            text.replace(
                "nodeId:\"value:mck/bool:main#always/body\"",
                "nodeId:\"value:mck/bool:main#always\"",
            ),
        ] {
            assert_ne!(changed, text);
            assert!(validate_model(&source(), &Element::read_one(changed).unwrap()).is_err());
        }
        let root = synthetic_model(&serde_json::json!({}));
        let symbols = symbols_text(&root);
        for changed in [
            symbols.replace("metadata:[", "dropped_metadata:["),
            symbols.replace("source_provenance:", "dropped_provenance:"),
        ] {
            assert_ne!(changed, symbols);
            assert!(
                validate_symbols(&source(), &Element::read_one(changed).unwrap(), Some(&root))
                    .is_err()
            );
        }
    }

    #[test]
    fn optional_unknown_ion_content_stays_opaque_and_is_retained() {
        let text = model_text().replace("enrichments:[{", "enrichments:[{owner:\"urn:mck:unknown\",data:first::second::{large:123456789012345678901234567890,scale:1.00}},{").replace("provenance:[", "provenance:[future::second::{scale:1.00},");
        let root = Element::read_one(text).unwrap();
        validate_model(&source(), &root).unwrap();
        let symbols = synthetic_symbols(&root, &serde_json::json!({}));
        validate_symbols(&source(), &symbols, Some(&root)).unwrap();
        let changed = symbols
            .to_string()
            .replace("future::second", "second::future");
        assert_ne!(changed, symbols.to_string());
        assert!(
            validate_symbols(&source(), &Element::read_one(changed).unwrap(), Some(&root)).is_err()
        );
    }
}
