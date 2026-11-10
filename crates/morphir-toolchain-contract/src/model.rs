//! Operations, compatibility tuples, prerequisites and delivery cases shared by
//! recipes, locks, receipts and manager results.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::ids::{
    CommandName, ExtensionIdentity, LanguageId, ModelToken, PackageId, ProtocolVersion, Sha256,
    TargetDigest, TargetPath, WasmAbi, comparator, exact_version,
};
use crate::platform::PlatformId;
use crate::reader::{Node, Obj, inconsistent};
use semver::{Comparator, Version};

/// A required toolset operation. Compilation and generation are separate
/// operations with separate providers.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Operation {
    /// Compile supported source in `language` to Morphir IR.
    Compile {
        /// Source language.
        language: LanguageId,
    },
    /// Generate `target` source from Morphir IR.
    Generate {
        /// Generation target.
        target: LanguageId,
    },
}

impl Operation {
    /// The MEP model transport method for this operation.
    pub fn model_method(&self) -> &'static str {
        match self {
            Self::Compile { .. } => "morphir.frontend.compileModel",
            Self::Generate { .. } => "morphir.backend.generateModel",
        }
    }

    /// The capability kind a provider for this operation claims.
    pub fn capability_kind(&self) -> &'static str {
        match self {
            Self::Compile { .. } => "frontend",
            Self::Generate { .. } => "backend",
        }
    }
}

/// The delivery kind a provider uses. The public runtime name of a WASM
/// delivery stays `wasm`; its ABI is a separate member.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum DeliveryKind {
    /// Compiled into the host.
    BuiltIn,
    /// A native process speaking Content-Length framed MEP.
    Process,
    /// A WASM module for a named ABI.
    Wasm,
    /// A .NET tool package installed through the SDK.
    DotnetTool,
}

impl DeliveryKind {
    pub(crate) const CASES: &'static [(&'static str, Self)] = &[
        ("built-in", Self::BuiltIn),
        ("process", Self::Process),
        ("wasm", Self::Wasm),
        ("dotnet-tool", Self::DotnetTool),
    ];

    /// Return the tag spelling.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::BuiltIn => "built-in",
            Self::Process => "process",
            Self::Wasm => "wasm",
            Self::DotnetTool => "dotnet-tool",
        }
    }
}

/// The five exactly compared members of a MEP model transport tuple. Its
/// operation always agrees with the provider operation that carries it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelTuple {
    operation: Operation,
    profile: ModelToken,
    codec: ModelToken,
    envelope_version: Version,
    ir_version: Version,
}

impl ModelTuple {
    /// The operation the tuple admits.
    pub fn operation(&self) -> &Operation {
        &self.operation
    }
    /// The model profile.
    pub fn profile(&self) -> &ModelToken {
        &self.profile
    }
    /// The model codec.
    pub fn codec(&self) -> &ModelToken {
        &self.codec
    }
    /// The model envelope version.
    pub fn envelope_version(&self) -> &Version {
        &self.envelope_version
    }
    /// The semantic IR version.
    pub fn ir_version(&self) -> &Version {
        &self.ir_version
    }
}

/// The model input of a built-in or legacy provider.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelInput {
    /// Model profile.
    pub profile: ModelToken,
    /// Model codec.
    pub codec: ModelToken,
    /// Semantic IR version.
    pub ir_version: Version,
}

/// How an external provider negotiates with its host.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Protocol {
    /// MEP `0.1` with the legacy JSON shapes and a declared model input.
    Legacy(ModelInput),
    /// MEP `0.2.0-draft.1` with one exact model transport tuple.
    ModelTransport(ModelTuple),
}

impl Protocol {
    /// The MEP version this protocol case requires.
    pub fn version(&self) -> ProtocolVersion {
        match self {
            Self::Legacy(_) => ProtocolVersion::Legacy,
            Self::ModelTransport(_) => ProtocolVersion::ModelTransportDraft1,
        }
    }

    /// The semantic IR version the provider reads or writes.
    pub fn ir_version(&self) -> &Version {
        match self {
            Self::Legacy(input) => &input.ir_version,
            Self::ModelTransport(tuple) => &tuple.ir_version,
        }
    }
}

/// When an SDK prerequisite applies.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SdkPhase {
    /// Needed to install the delivery (for example `dotnet tool install`).
    Install,
    /// Needed whenever the delivery runs.
    Run,
}

/// One declared prerequisite. Runtime, SDK and native prerequisites are
/// distinct cases so a plan can report each separately.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Prerequisite {
    /// A shared runtime such as `Microsoft.NETCore.App`.
    Runtime {
        /// Runtime name.
        name: String,
        /// Single comparators, all of which must hold.
        versions: Vec<Comparator>,
    },
    /// A language SDK.
    Sdk {
        /// SDK name.
        name: String,
        /// Single comparators, all of which must hold.
        versions: Vec<Comparator>,
        /// Install-time or run-time requirement.
        phase: SdkPhase,
    },
    /// A native library or operating-system component. Its version is
    /// written as SemVer (glibc 2.28 is `2.28.0`).
    Native {
        /// Library name, such as `glibc`.
        name: String,
        /// Single comparators, when the library has a version.
        versions: Vec<Comparator>,
        /// Platforms the prerequisite applies to; all platforms when empty.
        platforms: Vec<PlatformId>,
    },
}

/// The provider identity recorded by a lock and repeated by a receipt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LockedProvider {
    operation: Operation,
    extension_id: ExtensionIdentity,
    version: Version,
    delivery: LockedDelivery,
}

impl LockedProvider {
    pub(crate) fn new(
        operation: Operation,
        extension_id: ExtensionIdentity,
        version: Version,
        delivery: LockedDelivery,
    ) -> Self {
        Self {
            operation,
            extension_id,
            version,
            delivery,
        }
    }
    /// The operation this provider performs.
    pub fn operation(&self) -> &Operation {
        &self.operation
    }
    /// The registry and MEP identity.
    pub fn extension_id(&self) -> &ExtensionIdentity {
        &self.extension_id
    }
    /// The exact provider release.
    pub fn version(&self) -> &Version {
        &self.version
    }
    /// The delivery and its exact artifact identities.
    pub fn delivery(&self) -> &LockedDelivery {
        &self.delivery
    }
}

/// A locked delivery with the exact identities it needs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LockedDelivery {
    /// A provider compiled into the locked host; it has no artifact.
    BuiltIn {
        /// Model input the built-in reads or writes.
        model_input: ModelInput,
    },
    /// A process guest from an extension release descriptor.
    Process {
        /// Repository identity holding the descriptor and artifact.
        repository_id: Sha256,
        /// Extension release descriptor.
        descriptor: TargetDigest,
        /// The platform artifact.
        artifact: TargetDigest,
        /// Negotiation contract.
        protocol: Protocol,
    },
    /// A portable WASM guest for one named ABI.
    Wasm {
        /// Required host ABI.
        abi: WasmAbi,
        /// Repository identity holding the descriptor and artifact.
        repository_id: Sha256,
        /// Extension release descriptor.
        descriptor: TargetDigest,
        /// The portable artifact.
        artifact: TargetDigest,
        /// Negotiation contract.
        protocol: Protocol,
    },
    /// A .NET tool package installed into an isolated tool path. The
    /// extension release descriptor of the same release states its claims.
    DotnetTool {
        /// Repository identity holding the package and descriptor.
        repository_id: Sha256,
        /// Extension release descriptor of the same release.
        descriptor: TargetDigest,
        /// NuGet package id.
        package_id: PackageId,
        /// Command the package exposes.
        command: CommandName,
        /// Exact package bytes.
        package: TargetDigest,
        /// Negotiation contract.
        protocol: Protocol,
    },
}

impl LockedDelivery {
    /// Return the delivery kind.
    pub fn kind(&self) -> DeliveryKind {
        match self {
            Self::BuiltIn { .. } => DeliveryKind::BuiltIn,
            Self::Process { .. } => DeliveryKind::Process,
            Self::Wasm { .. } => DeliveryKind::Wasm,
            Self::DotnetTool { .. } => DeliveryKind::DotnetTool,
        }
    }
}

/// An authenticated recipe target.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecipeRef {
    /// Repository identity: SHA-256 of the canonical initial root `signed` object.
    pub repository_id: Sha256,
    /// Recipe target path.
    pub target: TargetPath,
    /// SHA-256 of the exact recipe bytes.
    pub sha256: Sha256,
}

// ----- readers -------------------------------------------------------------

pub(crate) fn sha256(node: Node<'_>) -> Result<Sha256> {
    node.parse(Code::InvalidValue, Sha256::parse)
}

pub(crate) fn target_path(node: Node<'_>) -> Result<TargetPath> {
    node.parse(Code::NonPortablePath, TargetPath::parse)
}

pub(crate) fn version(node: Node<'_>) -> Result<Version> {
    node.parse(Code::InvalidValue, exact_version)
}

pub(crate) fn token<T>(
    parse: fn(&str) -> std::result::Result<T, String>,
) -> impl Fn(Node<'_>) -> Result<T> {
    move |node| node.parse(Code::InvalidValue, parse)
}

pub(crate) fn extension_id(node: Node<'_>) -> Result<ExtensionIdentity> {
    node.parse(Code::InvalidValue, ExtensionIdentity::parse)
}

pub(crate) fn platform(node: Node<'_>) -> Result<PlatformId> {
    node.parse(Code::InvalidValue, PlatformId::parse)
}

pub(crate) fn comparators(node: Node<'_>) -> Result<Vec<Comparator>> {
    node.array(|item| item.parse(Code::InvalidValue, comparator))
}

pub(crate) fn non_empty_string(node: Node<'_>) -> Result<String> {
    let text = node.str()?;
    if text.trim().is_empty() {
        Err(Diagnostic::new(
            Code::InvalidValue,
            node.path(),
            "expected a non-blank string",
        ))
    } else {
        Ok(text.to_owned())
    }
}

#[derive(Clone, Copy)]
enum OperationTag {
    Compile,
    Generate,
}

/// Read the operation members of an object tagged by `operation`.
pub(crate) fn operation(object: &Obj<'_>) -> Result<Operation> {
    match object.case(
        "operation",
        &[
            ("compile", OperationTag::Compile),
            ("generate", OperationTag::Generate),
        ],
    )? {
        OperationTag::Compile => Ok(Operation::Compile {
            language: object.req("language", token(LanguageId::parse))?,
        }),
        OperationTag::Generate => Ok(Operation::Generate {
            target: object.req("target", token(LanguageId::parse))?,
        }),
    }
}

pub(crate) fn delivery(object: &Obj<'_>) -> Result<DeliveryKind> {
    object.case("delivery", DeliveryKind::CASES)
}

pub(crate) fn recipe_ref(node: Node<'_>) -> Result<RecipeRef> {
    let object = node.object()?;
    Ok(RecipeRef {
        repository_id: object.req("repositoryId", sha256)?,
        target: object.req("target", target_path)?,
        sha256: object.req("sha256", sha256)?,
    })
}

pub(crate) fn model_input(node: Node<'_>) -> Result<ModelInput> {
    let object = node.object()?;
    Ok(ModelInput {
        profile: object.req("profile", token(ModelToken::parse))?,
        codec: object.req("codec", token(ModelToken::parse))?,
        ir_version: object.req("irVersion", version)?,
    })
}

fn model_tuple(node: Node<'_>, provider: &Operation) -> Result<ModelTuple> {
    let object = node.object()?;
    let method_path = object.member_path("operation");
    let method = object.case(
        "operation",
        &[
            (
                "morphir.frontend.compileModel",
                "morphir.frontend.compileModel",
            ),
            (
                "morphir.backend.generateModel",
                "morphir.backend.generateModel",
            ),
        ],
    )?;
    if method != provider.model_method() {
        return Err(inconsistent(
            method_path,
            format!(
                "tuple operation {method} does not perform the provider operation; expected {}",
                provider.model_method()
            ),
        ));
    }
    Ok(ModelTuple {
        operation: provider.clone(),
        profile: object.req("profile", token(ModelToken::parse))?,
        codec: object.req("codec", token(ModelToken::parse))?,
        envelope_version: object.req("envelopeVersion", version)?,
        ir_version: object.req("irVersion", version)?,
    })
}

/// Read `protocolVersion` with exactly the compatibility member it requires.
pub(crate) fn protocol(object: &Obj<'_>, provider: &Operation) -> Result<Protocol> {
    let protocol_version = object.req("protocolVersion", |node| {
        node.parse(Code::UnsupportedCase, ProtocolVersion::parse)
    })?;
    match protocol_version {
        ProtocolVersion::Legacy => {
            if object.has("modelTuple") {
                return Err(inconsistent(
                    object.member_path("modelTuple"),
                    "MEP 0.1 never enables model transport; declare modelInput instead",
                ));
            }
            Ok(Protocol::Legacy(object.req("modelInput", model_input)?))
        }
        ProtocolVersion::ModelTransportDraft1 => {
            if object.has("modelInput") {
                return Err(inconsistent(
                    object.member_path("modelInput"),
                    "MEP 0.2.0-draft.1 providers declare one modelTuple",
                ));
            }
            Ok(Protocol::ModelTransport(
                object.req("modelTuple", |node| model_tuple(node, provider))?,
            ))
        }
    }
}

#[derive(Clone, Copy)]
enum PrerequisiteTag {
    Runtime,
    Sdk,
    Native,
}

pub(crate) fn prerequisite(node: Node<'_>) -> Result<Prerequisite> {
    let object = node.object()?;
    let kind = object.case(
        "kind",
        &[
            ("runtime", PrerequisiteTag::Runtime),
            ("sdk", PrerequisiteTag::Sdk),
            ("native", PrerequisiteTag::Native),
        ],
    )?;
    let name = object.req("name", non_empty_string)?;
    match kind {
        PrerequisiteTag::Runtime => Ok(Prerequisite::Runtime {
            name,
            versions: object.req("versions", comparators)?,
        }),
        PrerequisiteTag::Sdk => Ok(Prerequisite::Sdk {
            name,
            versions: object.req("versions", comparators)?,
            phase: object.case(
                "phase",
                &[("install", SdkPhase::Install), ("run", SdkPhase::Run)],
            )?,
        }),
        PrerequisiteTag::Native => Ok(Prerequisite::Native {
            name,
            versions: object.opt("versions", comparators)?.unwrap_or_default(),
            platforms: object
                .opt("platforms", |node| node.array(platform))?
                .unwrap_or_default(),
        }),
    }
}

pub(crate) fn prerequisites(object: &Obj<'_>) -> Result<Vec<Prerequisite>> {
    Ok(object
        .opt("prerequisites", |node| node.array(prerequisite))?
        .unwrap_or_default())
}

pub(crate) fn digest_pair(object: &Obj<'_>, target: &str, digest: &str) -> Result<TargetDigest> {
    Ok(TargetDigest {
        target: object.req(target, target_path)?,
        sha256: object.req(digest, sha256)?,
    })
}

/// Read a lock provider entry. Recipe providers reuse the delivery members.
pub(crate) fn locked_provider(node: Node<'_>) -> Result<LockedProvider> {
    let object = node.object()?;
    let operation = operation(&object)?;
    let kind = delivery(&object)?;
    let extension_id = object.req("extensionId", extension_id)?;
    let version = object.req("version", version)?;
    let delivery = match kind {
        DeliveryKind::BuiltIn => LockedDelivery::BuiltIn {
            model_input: object.req("modelInput", model_input)?,
        },
        DeliveryKind::Process => LockedDelivery::Process {
            repository_id: object.req("repositoryId", sha256)?,
            descriptor: digest_pair(&object, "descriptorTarget", "descriptorSha256")?,
            artifact: digest_pair(&object, "artifactTarget", "artifactSha256")?,
            protocol: protocol(&object, &operation)?,
        },
        DeliveryKind::Wasm => LockedDelivery::Wasm {
            abi: object.req("abi", token(WasmAbi::parse))?,
            repository_id: object.req("repositoryId", sha256)?,
            descriptor: digest_pair(&object, "descriptorTarget", "descriptorSha256")?,
            artifact: digest_pair(&object, "artifactTarget", "artifactSha256")?,
            protocol: protocol(&object, &operation)?,
        },
        DeliveryKind::DotnetTool => LockedDelivery::DotnetTool {
            repository_id: object.req("repositoryId", sha256)?,
            descriptor: digest_pair(&object, "descriptorTarget", "descriptorSha256")?,
            package_id: object.req("packageId", token(PackageId::parse))?,
            command: object.req("command", token(CommandName::parse))?,
            package: digest_pair(&object, "packageTarget", "packageSha256")?,
            protocol: protocol(&object, &operation)?,
        },
    };
    Ok(LockedProvider {
        operation,
        extension_id,
        version,
        delivery,
    })
}

/// Refuse a second entry for the same operation.
pub(crate) fn unique_operations<'a>(
    path: &str,
    operations: impl Iterator<Item = &'a Operation>,
) -> Result<()> {
    let mut seen = Vec::new();
    for (position, operation) in operations.enumerate() {
        if seen.contains(&operation) {
            return Err(inconsistent(
                crate::reader::index(path, position),
                "a second entry for the same operation",
            ));
        }
        seen.push(operation);
    }
    Ok(())
}
