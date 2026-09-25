//! Early-access linked-metadata inspection and self-contained context export.

use clap::{Args, Subcommand, ValueEnum};
use morphir_common::ir_transport::metadata::{
    ContextExportRequest, ContextOutput, ContextResourceLimits, ContextStorage, export_contexts,
};
use morphir_common::ir_transport::{
    CodecOptions, FormatId, IonCodec, IrCodec, IrVersion, JsonCodec, Layout,
};
use morphir_core::ir::v4::expand_v4_single_file_graph;
use morphir_core::metadata::{Carrier, ContextResources, DocumentId, Fact, GraphIndex, ObjectTerm};
use morphir_core::node_address::{NodeIndex, NodeRoot, NodeUri};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::io::Cursor;
use std::path::{Path, PathBuf};

#[derive(Clone, Args)]
pub struct MetadataInput {
    /// A V4.1 single-file JSON, YAML, or Ion document
    #[arg(long)]
    ir: PathBuf,
    /// Optional local predicate closure for typed @json expansion
    #[arg(long)]
    schema_closure: Option<PathBuf>,
}

#[derive(Clone, Subcommand)]
pub enum MetadataAction {
    /// Parse metadata carriers and report the semantic-validation boundary
    Validate {
        #[command(flatten)]
        input: MetadataInput,
    },
    /// Query expanded facts and their assertion locations
    Query {
        #[command(flatten)]
        input: MetadataInput,
        #[arg(long)]
        subject: Option<String>,
        #[arg(long)]
        object: Option<String>,
        #[arg(long)]
        predicate: Option<String>,
    },
    /// Export JSON with inline contexts or an inventory-ready directory
    Export {
        #[command(flatten)]
        input: MetadataInput,
        #[arg(long)]
        output: PathBuf,
        #[arg(long, value_enum, default_value_t = ContextStorageArg::Auto)]
        context_storage: ContextStorageArg,
    },
}

#[derive(Clone, Copy, ValueEnum)]
pub enum ContextStorageArg {
    Auto,
    Inline,
    External,
}

impl From<ContextStorageArg> for ContextStorage {
    fn from(value: ContextStorageArg) -> Self {
        match value {
            ContextStorageArg::Auto => Self::Auto,
            ContextStorageArg::Inline => Self::Inline,
            ContextStorageArg::External => Self::External,
        }
    }
}

pub fn run(action: &MetadataAction) -> miette::Result<()> {
    match action {
        MetadataAction::Validate { input } => {
            let graph = load_graph(input)?;
            println!(
                "{}",
                json!({"status":"parsed","factCount":graph.facts().len(),
                "assertionCount":graph.assertions().len(),"semanticStatus":"unvalidated"})
            );
        }
        MetadataAction::Query {
            input,
            subject,
            object,
            predicate,
        } => {
            let graph = load_graph(input)?;
            let subject = parse_filter(subject)?;
            let object = parse_filter(object)?;
            let predicate = parse_filter(predicate)?;
            let facts = graph.facts().iter().filter(|fact| {
                subject.as_ref().is_none_or(|uri| fact.subject() == uri)
                    && predicate.as_ref().is_none_or(|uri| fact.predicate() == uri)
                    && object.as_ref().is_none_or(|uri| matches!(fact.object(), ObjectTerm::NodeRef(target) if target == uri))
            }).map(fact_wire).collect::<Vec<_>>();
            let assertions = graph
                .assertions()
                .iter()
                .filter(|assertion| {
                    facts
                        .iter()
                        .any(|fact| *fact == fact_wire(assertion.key().fact()))
                })
                .map(|assertion| {
                    let carrier = match assertion.key().carrier() {
                        Carrier::AttributesFacts(_) => "attributesFacts",
                        Carrier::AnnotationsFacts(_) => "annotationsFacts",
                        Carrier::DocumentGraph => "documentGraph",
                        Carrier::Sidecar { .. } => "sidecar",
                    };
                    json!({"owner":assertion.key().owner().as_str(),"carrier":carrier,
                    "fact":fact_wire(assertion.key().fact())})
                })
                .collect::<Vec<_>>();
            println!(
                "{}",
                json!({"facts":facts,"assertions":assertions,
                "semanticStatus":"unvalidated"})
            );
        }
        MetadataAction::Export {
            input,
            output,
            context_storage,
        } => {
            export(input, output, *context_storage)?;
            println!("Exported {}", output.display());
        }
    }
    Ok(())
}

fn parse_filter(value: &Option<String>) -> miette::Result<Option<NodeUri>> {
    value
        .as_ref()
        .map(|value| NodeUri::parse(value).map_err(|error| miette::miette!("{error}")))
        .transpose()
}

fn read_value(path: &Path) -> miette::Result<Value> {
    let bytes =
        std::fs::read(path).map_err(|error| miette::miette!("{}: {error}", path.display()))?;
    let text = std::str::from_utf8(&bytes)
        .map_err(|error| miette::miette!("{}: {error}", path.display()))?;
    match path.extension().and_then(|value| value.to_str()) {
        Some("json") => morphir_core::ir::json::read(text)
            .map_err(|error| miette::miette!("invalid JSON IR: {error:?}")),
        Some("yaml" | "yml") => {
            let (file, _) = morphir_core::ir::yaml::read_ir_file(text)
                .map_err(|error| miette::miette!("invalid YAML IR: {error}"))?;
            serde_json::to_value(file).map_err(|error| miette::miette!("{error}"))
        }
        Some("ion") => {
            let ion = CodecOptions::new(IrVersion::V4, Layout::SingleFile, FormatId::ion())
                .with_linked_metadata();
            let json_options =
                CodecOptions::new(IrVersion::V4, Layout::SingleFile, FormatId::json())
                    .with_linked_metadata();
            let mut json_bytes = Vec::new();
            let mut sink = JsonCodec::new()
                .encoder(&mut json_bytes, &json_options)
                .map_err(|error| miette::miette!("{error}"))?;
            IonCodec::new()
                .decode(&mut Cursor::new(bytes), &ion, sink.as_mut())
                .map_err(|error| miette::miette!("{error}"))?;
            drop(sink);
            morphir_core::ir::json::read(
                std::str::from_utf8(&json_bytes).expect("JSON codec emits UTF-8"),
            )
            .map_err(|error| miette::miette!("invalid normalized Ion IR: {error:?}"))
        }
        _ => Err(miette::miette!(
            "metadata input must end in .json, .yaml, .yml, or .ion"
        )),
    }
}

fn source_parts(path: &Path) -> miette::Result<(&Path, &str)> {
    let root = path
        .parent()
        .filter(|root| !root.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let file = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| miette::miette!("IR path must have a UTF-8 file name"))?;
    Ok((root, file))
}

fn inline_input(input: &MetadataInput) -> miette::Result<Value> {
    let authored = read_value(&input.ir)?;
    let (root, source_file) = source_parts(&input.ir)?;
    export_contexts(ContextExportRequest {
        source_root: root,
        document: &authored,
        source_file: Some(source_file),
        output_file: None,
        output: ContextOutput::Standalone,
        storage: ContextStorage::Inline,
        resolver: None,
        limits: ContextResourceLimits::default(),
    })
    .map(|export| export.document)
    .map_err(|error| miette::miette!("{error}"))
}

fn json_datatypes(path: Option<&Path>) -> miette::Result<HashMap<String, NodeUri>> {
    let Some(path) = path else {
        return Ok(HashMap::new());
    };
    let value = read_value(path)?;
    let declarations = value["predicates"]
        .as_array()
        .ok_or_else(|| miette::miette!("predicate closure has no predicates array"))?;
    declarations
        .iter()
        .filter(|item| item["object"]["kind"] == "json")
        .map(|item| {
            let key = item["uri"]
                .as_str()
                .ok_or_else(|| miette::miette!("predicate URI missing"))?;
            let datatype = item["object"]["type"]
                .as_str()
                .ok_or_else(|| miette::miette!("JSON datatype missing"))?;
            Ok((
                key.to_owned(),
                NodeUri::parse(datatype).map_err(|error| miette::miette!("{error}"))?,
            ))
        })
        .collect()
}

fn load_graph(input: &MetadataInput) -> miette::Result<GraphIndex> {
    let value = inline_input(input)?;
    let (file, _) = morphir_core::ir::json::read_ir_file(&value.to_string())
        .map_err(|error| miette::miette!("invalid V4 metadata document: {error}"))?;
    let index = NodeIndex::v4_file(&file).map_err(|error| miette::miette!("{error}"))?;
    let owner = index
        .address_for(&NodeRoot::Distribution, &[])
        .map_err(|error| miette::miette!("{error}"))?;
    let datatypes = json_datatypes(input.schema_closure.as_deref())?;
    expand_v4_single_file_graph(
        &file,
        &DocumentId::new(owner.to_string()).map_err(|error| miette::miette!("{error}"))?,
        &ContextResources::new("contexts"),
        |predicate| datatypes.get(&predicate.to_string()).cloned(),
    )
    .map_err(|error| miette::miette!("{error}"))
}

fn fact_wire(fact: &Fact) -> Value {
    let object = match fact.object() {
        ObjectTerm::NodeRef(uri) => json!({"@id":uri.to_string()}),
        ObjectTerm::Value(value) => match value.datatype() {
            Some(_) => json!({"@value":value.value(),"@type":"@json"}),
            None => json!({"@value":value.value()}),
        },
    };
    json!({"subject":fact.subject().to_string(),"predicate":fact.predicate().to_string(),
        "object":object,"graph":"default"})
}

fn export(input: &MetadataInput, output: &Path, choice: ContextStorageArg) -> miette::Result<()> {
    let authored = read_value(&input.ir)?;
    let (root, source_file) = source_parts(&input.ir)?;
    let external = matches!(choice, ContextStorageArg::External)
        || matches!(choice, ContextStorageArg::Auto) && output.extension().is_none();
    let parent = output
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    if output.exists() {
        return Err(miette::miette!(
            "output already exists: {}",
            output.display()
        ));
    }
    std::fs::create_dir_all(parent)
        .map_err(|error| miette::miette!("{}: {error}", parent.display()))?;
    let result = export_contexts(ContextExportRequest {
        source_root: root,
        document: &authored,
        source_file: Some(source_file),
        output_file: external.then_some("ir.json"),
        output: if external {
            ContextOutput::Archive
        } else {
            ContextOutput::Standalone
        },
        storage: if external {
            ContextStorage::External
        } else {
            ContextStorage::Inline
        },
        resolver: None,
        limits: ContextResourceLimits::default(),
    })
    .map_err(|error| miette::miette!("{error}"))?;
    let bytes =
        serde_json::to_vec_pretty(&result.document).map_err(|error| miette::miette!("{error}"))?;
    if external {
        let stage = tempfile::tempdir_in(parent).map_err(|error| miette::miette!("{error}"))?;
        std::fs::write(stage.path().join("ir.json"), bytes)
            .map_err(|error| miette::miette!("{error}"))?;
        for resource in result.resources {
            let path = stage.path().join(resource.path);
            std::fs::create_dir_all(path.parent().expect("resource has parent"))
                .map_err(|error| miette::miette!("{error}"))?;
            std::fs::write(path, resource.bytes).map_err(|error| miette::miette!("{error}"))?;
        }
        std::fs::rename(stage.path(), output).map_err(|error| miette::miette!("{error}"))?;
    } else {
        let mut stage =
            tempfile::NamedTempFile::new_in(parent).map_err(|error| miette::miette!("{error}"))?;
        std::io::Write::write_all(&mut stage, &bytes)
            .map_err(|error| miette::miette!("{error}"))?;
        stage
            .persist_noclobber(output)
            .map_err(|error| miette::miette!("{error}"))?;
    }
    Ok(())
}
