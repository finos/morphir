//! Early-access linked-metadata inspection and self-contained context export.

use clap::{Args, Subcommand, ValueEnum};
use morphir_common::ir_transport::metadata::{
    ContextExportRequest, ContextOutput, ContextResourceLimits, ContextStorage, export_contexts,
};
use morphir_common::ir_transport::{
    CodecOptions, FormatId, IonCodec, IrCodec, IrVersion, JsonCodec, Layout,
};
use morphir_core::data_value::DataValueValidator;
use morphir_core::ir::v4::expand_v4_single_file_graph;
use morphir_core::metadata::admission::{Admission, NodeTargetKind, PredicateClosure, SubjectRole};
use morphir_core::metadata::{Carrier, ContextResources, DocumentId, Fact, GraphIndex, ObjectTerm};
use morphir_core::node_address::{IndexedNodeKind, NodeIndex, NodeRoot, NodeUri};
use morphir_package::local_registry::mvp::{self, RestoreRequest};
use morphir_package::resolution::{PackagePath, ReleaseId, StableVersion};
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
    /// Validate with declarations from a freshly authenticated Library restore
    ValidateTrusted(TrustedValidationInput),
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

#[derive(Clone, Args)]
pub struct TrustedValidationInput {
    /// Consumer V4.1 single-file IR to validate
    #[arg(long)]
    ir: PathBuf,
    /// Exact provider Library release in the full lock
    #[arg(long, value_name = "PACKAGE@VERSION", value_parser = parse_release)]
    provider_release: ReleaseId,
    /// Explicit trusted-host policy file
    #[arg(long)]
    policy: PathBuf,
    /// Full package lock; replay never rewrites it
    #[arg(long)]
    lock: PathBuf,
    /// Caller-controlled local registry
    #[arg(long)]
    registry: PathBuf,
    /// Existing initialized trust-state directory
    #[arg(long)]
    state: PathBuf,
    /// Accept the local MVP's caller-controlled filesystem roots
    #[arg(long, value_enum)]
    assurance: super::package::Assurance,
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

pub async fn run(action: &MetadataAction) -> miette::Result<()> {
    match action {
        MetadataAction::Validate { input } => {
            let graph = load_graph(input)?;
            println!(
                "{}",
                json!({"status":"parsed","factCount":graph.facts().len(),
                "assertionCount":graph.assertions().len(),"semanticStatus":"unvalidated"})
            );
        }
        MetadataAction::ValidateTrusted(input) => validate_trusted(input).await?,
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

fn parse_release(input: &str) -> Result<ReleaseId, String> {
    let (package, version) = input
        .split_once('@')
        .ok_or_else(|| "expected PACKAGE@VERSION".to_owned())?;
    Ok(ReleaseId::new(
        PackagePath::parse(package).map_err(|error| error.to_string())?,
        StableVersion::parse(version).map_err(|error| error.to_string())?,
    ))
}

fn bounded_file(path: &Path, limit: u64) -> miette::Result<Vec<u8>> {
    let metadata =
        std::fs::metadata(path).map_err(|error| miette::miette!("{}: {error}", path.display()))?;
    if !metadata.is_file() || metadata.len() > limit {
        return Err(miette::miette!(
            "invalid or oversized input: {}",
            path.display()
        ));
    }
    std::fs::read(path).map_err(|error| miette::miette!("{}: {error}", path.display()))
}

fn loaded_file(path: &Path) -> miette::Result<morphir_core::ir::v4::IRFile> {
    let input = MetadataInput {
        ir: path.to_path_buf(),
        schema_closure: None,
    };
    let value = inline_input(&input)?;
    morphir_core::ir::json::read_ir_file(&value.to_string())
        .map(|(file, _)| file)
        .map_err(|error| miette::miette!("invalid V4 metadata document: {error}"))
}

fn subject_role(
    kind: IndexedNodeKind,
    uri: &NodeUri,
    distribution: &morphir_core::ir::v4::Distribution,
) -> Option<SubjectRole> {
    let specification = match distribution {
        morphir_core::ir::v4::Distribution::Specs(_) => true,
        morphir_core::ir::v4::Distribution::Library(_) => matches!(
            uri.root(),
            NodeRoot::Type { owner: morphir_core::node_address::NodeOwner::Dependency(_), .. }
                | NodeRoot::Value { owner: morphir_core::node_address::NodeOwner::Dependency(_), .. }
        ),
        morphir_core::ir::v4::Distribution::Application(_) => false,
    };
    match kind {
        IndexedNodeKind::Package => Some(SubjectRole::Package),
        IndexedNodeKind::Module => Some(SubjectRole::Module),
        IndexedNodeKind::TypeDefinition => Some(if specification {
            SubjectRole::TypeSpecification
        } else {
            SubjectRole::TypeDefinition
        }),
        IndexedNodeKind::ValueDefinition => Some(if specification {
            SubjectRole::ValueSpecification
        } else {
            SubjectRole::ValueDefinition
        }),
        IndexedNodeKind::TypeExpression => Some(SubjectRole::TypeExpression),
        IndexedNodeKind::ValueExpression => Some(SubjectRole::ValueExpression),
        IndexedNodeKind::Pattern => Some(SubjectRole::Pattern),
        _ => None,
    }
}

fn target_kind(kind: IndexedNodeKind) -> Option<NodeTargetKind> {
    match kind {
        IndexedNodeKind::Package => Some(NodeTargetKind::Package),
        IndexedNodeKind::Module => Some(NodeTargetKind::Module),
        IndexedNodeKind::TypeDefinition => Some(NodeTargetKind::Type),
        IndexedNodeKind::ValueDefinition => Some(NodeTargetKind::Value),
        _ => None,
    }
}

async fn validate_trusted(input: &TrustedValidationInput) -> miette::Result<()> {
    let super::package::Assurance::Portable = input.assurance;
    let policy = bounded_file(&input.policy, 1_048_576)?;
    let lock = bounded_file(&input.lock, 16 * 1_048_576)?;
    let temporary = tempfile::tempdir().map_err(|error| miette::miette!("{error}"))?;
    let output = temporary.path().join("libraries");
    let report = mvp::restore(RestoreRequest {
        policy: &policy,
        lock: &lock,
        registry: &input.registry,
        state: &input.state,
        output: &output,
    })
    .await
    .map_err(|error| miette::miette!("provider restore: {error}"))?;
    let package = report
        .packages
        .iter()
        .find(|package| package.release == input.provider_release)
        .ok_or_else(|| miette::miette!("provider release is absent from the verified lock"))?;
    let provider = loaded_file(&output.join(&package.directory).join("ir.json"))?;
    let closure = PredicateClosure::from_v4_provider(&provider, &ContextResources::new("contexts"))
        .map_err(|error| miette::miette!("provider declarations: {error}"))?;
    let validator = DataValueValidator::v4(&provider.distribution)
        .map_err(|error| miette::miette!("provider data types: {error}"))?;
    let provider_index =
        NodeIndex::v4_file(&provider).map_err(|error| miette::miette!("{error}"))?;
    let consumer = loaded_file(&input.ir)?;
    let consumer_index =
        NodeIndex::v4_file(&consumer).map_err(|error| miette::miette!("{error}"))?;
    let owner = consumer_index
        .address_for(&NodeRoot::Distribution, &[])
        .map_err(|error| miette::miette!("{error}"))?;
    let graph = expand_v4_single_file_graph(
        &consumer,
        &DocumentId::new(owner.to_string()).map_err(|error| miette::miette!("{error}"))?,
        &ContextResources::new("contexts"),
        |predicate| closure.json_datatype(predicate),
    )
    .map_err(|error| miette::miette!("consumer facts: {error}"))?;
    let mut validated = 0usize;
    let mut unvalidated = 0usize;
    for assertion in graph.assertions() {
        let fact = assertion.key().fact();
        let Some(role) = consumer_index
            .resolve(fact.subject())
            .ok()
            .and_then(|kind| subject_role(kind, fact.subject(), &consumer.distribution))
        else {
            unvalidated += 1;
            continue;
        };
        let target = match fact.object() {
            ObjectTerm::NodeRef(uri) => consumer_index
                .resolve(uri)
                .or_else(|_| provider_index.resolve(uri))
                .ok()
                .and_then(target_kind),
            ObjectTerm::Value(_) => None,
        };
        match closure
            .admit(
                fact,
                role,
                assertion.key().carrier(),
                &validator,
                &[],
                target,
            )
            .map_err(|error| miette::miette!("fact {}: {error}", fact.predicate()))?
        {
            Admission::Validated => validated += 1,
            Admission::PreservedUnvalidated(_) => unvalidated += 1,
        }
    }
    println!(
        "{}",
        json!({"status":"parsed","factCount":graph.facts().len(),
            "assertionCount":graph.assertions().len(),"validatedAssertionCount":validated,
            "unvalidatedAssertionCount":unvalidated,
            "semanticStatus": if validated > 0 && unvalidated == 0 {"validated"}
                else if validated > 0 {"partiallyValidated"} else {"unvalidated"}})
    );
    Ok(())
}

fn read_value(path: &Path) -> miette::Result<Value> {
    let bytes = bounded_file(path, 64 * 1_048_576)?;
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
