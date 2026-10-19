//! Lazy bounds checks precede materializing untrusted binary Ion documents.
use ion_rs::{Decoder, Element, LazyValue, Reader, ValueRef};

pub(super) fn read(bytes: &[u8]) -> Result<Element, String> {
    read_counted(bytes, 100000).map(|(element, _)| element)
}

pub(super) fn read_counted(bytes: &[u8], max_nodes: usize) -> Result<(Element, usize), String> {
    super::require(
        bytes.len() <= 16 * 1024 * 1024,
        "Ion document exceeds frame limit",
    )?;
    super::require(
        bytes.starts_with(&[0xe0, 1, 0, 0xea]),
        "Ion 1.0 binary marker missing",
    )?;
    let mut reader = Reader::new(ion_rs::v1_0::Binary, bytes).map_err(|e| e.to_string())?;
    let value = reader
        .next()
        .map_err(|e| e.to_string())?
        .ok_or("Ion document missing")?;
    let mut nodes = 0;
    visit(&value, 1, &mut nodes, max_nodes)?;
    super::require(
        reader.next().map_err(|e| e.to_string())?.is_none(),
        "multiple Ion documents",
    )?;
    Element::read_one(bytes)
        .map(|element| (element, nodes))
        .map_err(|e| e.to_string())
}

fn visit<D: Decoder>(
    value: &LazyValue<'_, D>,
    depth: usize,
    nodes: &mut usize,
    max_nodes: usize,
) -> Result<(), String> {
    *nodes += 1;
    super::require(
        depth <= 128 && *nodes <= max_nodes,
        "Ion structural limit exceeded",
    )?;
    for annotation in value.annotations() {
        super::require(
            annotation.map_err(|e| e.to_string())?.text().is_some(),
            "unresolved Ion annotation",
        )?;
    }
    match value.read().map_err(|e| e.to_string())? {
        ValueRef::Struct(fields) => {
            for field in fields.iter() {
                let field = field.map_err(|e| e.to_string())?;
                super::require(
                    field.name().map_err(|e| e.to_string())?.text().is_some(),
                    "unresolved Ion field name",
                )?;
                visit(&field.value(), depth + 1, nodes, max_nodes)?;
            }
        }
        ValueRef::List(values) => {
            for child in values.iter() {
                visit(
                    &child.map_err(|e| e.to_string())?,
                    depth + 1,
                    nodes,
                    max_nodes,
                )?;
            }
        }
        ValueRef::SExp(values) => {
            for child in values.iter() {
                visit(
                    &child.map_err(|e| e.to_string())?,
                    depth + 1,
                    nodes,
                    max_nodes,
                )?;
            }
        }
        ValueRef::Symbol(symbol) => {
            super::require(symbol.text().is_some(), "unresolved Ion symbol")?
        }
        _ => {}
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn deep_and_wide_documents_are_refused_before_materialization() {
        let mut deep = Element::from(true);
        for _ in 0..128 {
            deep = Element::from(ion_rs::Sequence::builder().push(deep).build_list());
        }
        assert!(read(&deep.encode_as(ion_rs::v1_0::Binary).unwrap()).is_err());
        let wide = Element::from(
            ion_rs::Sequence::builder()
                .push_all((0..100000).map(|_| true))
                .build_list(),
        );
        assert!(read(&wide.encode_as(ion_rs::v1_0::Binary).unwrap()).is_err());
        assert!(read(&[0xe0, 1, 0, 0xea, 0x11, 0x11]).is_err());
        assert!(read(&[0xe0, 1, 0, 0xea, 0xbe]).is_err());
        let okay = Element::read_one("unknown::{known:[true,123.4500]}").unwrap();
        assert!(read(&okay.encode_as(ion_rs::v1_0::Binary).unwrap()).is_ok());
    }
}
