//! The toolset recipe, an authenticated target such as
//! `toolchains/recipes/fsharp/1.0.0.json`.
//!
//! A recipe maps host offerings (implementation, release, deployment) to the
//! tool release metadata v1 tool ids or .NET tool packages that publish them,
//! and binds each required operation to built-in or independently released
//! providers by exact descriptor and artifact digests. It does not change the
//! extension descriptor format.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope;
use crate::ids::{
    CommandName, DeploymentId, ExtensionIdentity, ImplementationId, PackageId, PresetId,
    ProtocolVersion, Sha256, TargetDigest, WasmAbi,
};
use crate::model::{
    self, DELIVERY_CASES, DeliveryKind, ModelInput, Operation, Prerequisite, Protocol,
};
use crate::platform::{Os, PlatformId};
use crate::reader::{Node, Obj, inconsistent, index, join};
use morphir_distribution::ToolId;
use semver::Version;
use serde_json::Value;
use std::collections::BTreeMap;

/// Member paths a `0.1.0-draft.1` recipe reader understands.
pub const UNDERSTOOD_PATHS: &[&str] = &[
    "schemaVersion",
    "critical",
    "preset",
    "version",
    "operations",
    "hosts",
    "hosts.implementation",
    "hosts.version",
    "hosts.deployment",
    "hosts.execution",
    "hosts.source",
    "hosts.protocolVersions",
    "hosts.wasmAbis",
    "hosts.prerequisites",
    "hosts.builtIns",
    "hosts.platforms",
    "providers",
    "providers.operation",
    "providers.delivery",
    "providers.extensionId",
    "providers.version",
    "providers.abi",
    "providers.repositoryId",
    "providers.descriptorTarget",
    "providers.descriptorSha256",
    "providers.artifactTarget",
    "providers.artifactSha256",
    "providers.packageId",
    "providers.command",
    "providers.packageTarget",
    "providers.packageSha256",
    "providers.protocolVersion",
    "providers.modelTuple",
    "providers.modelInput",
    "providers.prerequisites",
    "providers.platforms",
];

/// How a host executes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Execution {
    /// Native compiled code without an installed .NET runtime.
    NativeAot,
    /// Managed code under a JIT, with a bundled or installed runtime.
    Jit,
}

/// Where a host offering is published.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HostSource {
    /// A tool release metadata v1 tool id; one id per separately published
    /// offering, so implementation and deployment are never inferred from an
    /// executable name.
    ToolRelease {
        /// The v1 tool id.
        tool_id: ToolId,
    },
    /// A .NET tool package. The package bytes are authenticated targets bound
    /// per platform like any other host artifact.
    DotnetTool {
        /// NuGet package id, such as `Morphir.Tool`.
        package_id: PackageId,
        /// Command the package exposes, such as `dotnet-morphir`.
        command: CommandName,
    },
}

/// A provider compiled into a host offering.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuiltIn {
    /// Operation it performs.
    pub operation: Operation,
    /// Registry identity, such as `morphir.fsharp`.
    pub extension_id: ExtensionIdentity,
    /// Exact version.
    pub version: Version,
    /// Model input.
    pub model_input: ModelInput,
}

/// One host offering: an implementation, release and deployment.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostOffering {
    /// Implementation.
    pub implementation: ImplementationId,
    /// Exact release.
    pub version: Version,
    /// Deployment offering.
    pub deployment: DeploymentId,
    /// Execution mode.
    pub execution: Execution,
    /// Publication source.
    pub source: HostSource,
    /// MEP versions the host speaks.
    pub protocol_versions: Vec<ProtocolVersion>,
    /// WASM ABIs the host's qualified engine supports.
    pub wasm_abis: Vec<WasmAbi>,
    /// Declared prerequisites.
    pub prerequisites: Vec<Prerequisite>,
    /// Built-in providers.
    pub built_ins: Vec<BuiltIn>,
    /// The authenticated artifact for each supported platform.
    pub platforms: BTreeMap<PlatformId, TargetDigest>,
}

/// A recipe provider delivery and its exact identities.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecipeDelivery {
    /// A process guest with one artifact per platform.
    Process {
        /// Repository holding the descriptor and artifacts.
        repository_id: Sha256,
        /// Extension release descriptor.
        descriptor: TargetDigest,
        /// Negotiation contract.
        protocol: Protocol,
        /// Artifacts by platform.
        platforms: BTreeMap<PlatformId, TargetDigest>,
    },
    /// A portable WASM guest for one ABI.
    Wasm {
        /// Required host ABI.
        abi: WasmAbi,
        /// Repository holding the descriptor and artifact.
        repository_id: Sha256,
        /// Extension release descriptor.
        descriptor: TargetDigest,
        /// Portable artifact.
        artifact: TargetDigest,
        /// Negotiation contract.
        protocol: Protocol,
    },
    /// A framework-dependent .NET tool package.
    DotnetTool {
        /// Repository holding the package.
        repository_id: Sha256,
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

impl RecipeDelivery {
    /// Return the delivery kind.
    pub fn kind(&self) -> DeliveryKind {
        match self {
            Self::Process { .. } => DeliveryKind::Process,
            Self::Wasm { .. } => DeliveryKind::Wasm,
            Self::DotnetTool { .. } => DeliveryKind::DotnetTool,
        }
    }

    /// Return the negotiation contract.
    pub fn protocol(&self) -> &Protocol {
        match self {
            Self::Process { protocol, .. }
            | Self::Wasm { protocol, .. }
            | Self::DotnetTool { protocol, .. } => protocol,
        }
    }
}

/// An independently released provider a recipe may select.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecipeProvider {
    /// Operation it performs.
    pub operation: Operation,
    /// Registry and MEP identity.
    pub extension_id: ExtensionIdentity,
    /// Exact provider release.
    pub version: Version,
    /// Declared prerequisites.
    pub prerequisites: Vec<Prerequisite>,
    /// Delivery.
    pub delivery: RecipeDelivery,
}

/// A parsed toolset recipe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolsetRecipe {
    /// Preset name.
    pub preset: PresetId,
    /// Recipe release.
    pub version: Version,
    /// Required operations, in workflow order.
    pub operations: Vec<Operation>,
    /// Host offerings.
    pub hosts: Vec<HostOffering>,
    /// Providers, in preference order.
    pub providers: Vec<RecipeProvider>,
}

/// Read a recipe from its exact bytes.
pub fn read_recipe(bytes: &[u8]) -> Result<ToolsetRecipe> {
    let value: Value = serde_json::from_slice(bytes).map_err(|error| {
        Diagnostic::new(Code::InvalidDocument, "", format!("not JSON: {error}"))
    })?;
    envelope::check(&value, UNDERSTOOD_PATHS)?;
    let root = Node::root(&value).object()?;
    let recipe = ToolsetRecipe {
        preset: root.req("preset", model::token(PresetId::parse))?,
        version: root.req("version", model::version)?,
        operations: root.req("operations", |node| {
            node.array(|item| model::operation(&item.object()?))
        })?,
        hosts: root.req("hosts", |node| node.array(host_offering))?,
        providers: root.req("providers", |node| node.array(provider))?,
    };
    validate(&recipe)?;
    Ok(recipe)
}

fn platform_digests(
    object: &Obj<'_>,
    key: &str,
    target: &str,
    digest: &str,
) -> Result<BTreeMap<PlatformId, TargetDigest>> {
    object.req(key, |node| {
        let platforms = node.object()?;
        let entries = platforms.map(PlatformId::parse, |_, node| {
            model::digest_pair(&node.object()?, target, digest)
        })?;
        if entries.is_empty() {
            return Err(inconsistent(
                platforms.path(),
                "at least one platform is required",
            ));
        }
        Ok(entries.into_iter().collect())
    })
}

fn host_offering(node: Node<'_>) -> Result<HostOffering> {
    let host = node.object()?;
    let source = host.req("source", |node| {
        let source = node.object()?;
        match source.tag("kind", &["tool-release", "dotnet-tool"])? {
            "tool-release" => Ok(HostSource::ToolRelease {
                tool_id: source.req("toolId", |node| {
                    node.parse(Code::InvalidValue, |text| {
                        ToolId::parse(text).map_err(|error| error.to_string())
                    })
                })?,
            }),
            _ => Ok(HostSource::DotnetTool {
                package_id: source.req("packageId", model::token(PackageId::parse))?,
                command: source.req("command", model::token(CommandName::parse))?,
            }),
        }
    })?;
    let platforms = platform_digests(&host, "platforms", "target", "sha256")?;
    if matches!(source, HostSource::ToolRelease { .. })
        && let Some(musl) = platforms
            .keys()
            .find(|platform| platform.os() == Os::LinuxMusl)
    {
        return Err(inconsistent(
            join(&host.member_path("platforms"), musl.as_str()),
            "tool release metadata v1 platforms do not state a C library, so a v1 artifact binds only glibc Linux",
        ));
    }
    Ok(HostOffering {
        implementation: host.req("implementation", model::token(ImplementationId::parse))?,
        version: host.req("version", model::version)?,
        deployment: host.req("deployment", model::token(DeploymentId::parse))?,
        execution: match host.tag("execution", &["native-aot", "jit"])? {
            "native-aot" => Execution::NativeAot,
            _ => Execution::Jit,
        },
        source,
        protocol_versions: host.req("protocolVersions", |node| {
            node.array(|item| item.parse(Code::UnsupportedCase, ProtocolVersion::parse))
        })?,
        wasm_abis: host
            .opt("wasmAbis", |node| node.array(model::token(WasmAbi::parse)))?
            .unwrap_or_default(),
        prerequisites: model::prerequisites(&host)?,
        built_ins: host
            .opt("builtIns", |node| {
                node.array(|item| {
                    let built_in = item.object()?;
                    Ok(BuiltIn {
                        operation: model::operation(&built_in)?,
                        extension_id: built_in.req("extensionId", model::extension_id)?,
                        version: built_in.req("version", model::version)?,
                        model_input: built_in.req("modelInput", model::model_input)?,
                    })
                })
            })?
            .unwrap_or_default(),
        platforms,
    })
}

fn provider(node: Node<'_>) -> Result<RecipeProvider> {
    let object = node.object()?;
    let operation = model::operation(&object)?;
    let kind = DeliveryKind::from_tag(object.tag("delivery", DELIVERY_CASES)?);
    let extension_id = object.req("extensionId", model::extension_id)?;
    let version = object.req("version", model::version)?;
    let delivery = match kind {
        DeliveryKind::BuiltIn => {
            return Err(inconsistent(
                object.member_path("delivery"),
                "built-in providers belong to a host offering's builtIns",
            ));
        }
        DeliveryKind::Process => RecipeDelivery::Process {
            repository_id: object.req("repositoryId", model::sha256)?,
            descriptor: model::digest_pair(&object, "descriptorTarget", "descriptorSha256")?,
            protocol: model::protocol(&object, &operation)?,
            platforms: platform_digests(&object, "platforms", "artifactTarget", "artifactSha256")?,
        },
        DeliveryKind::Wasm => RecipeDelivery::Wasm {
            abi: object.req("abi", model::token(WasmAbi::parse))?,
            repository_id: object.req("repositoryId", model::sha256)?,
            descriptor: model::digest_pair(&object, "descriptorTarget", "descriptorSha256")?,
            artifact: model::digest_pair(&object, "artifactTarget", "artifactSha256")?,
            protocol: model::protocol(&object, &operation)?,
        },
        DeliveryKind::DotnetTool => RecipeDelivery::DotnetTool {
            repository_id: object.req("repositoryId", model::sha256)?,
            package_id: object.req("packageId", model::token(PackageId::parse))?,
            command: object.req("command", model::token(CommandName::parse))?,
            package: model::digest_pair(&object, "packageTarget", "packageSha256")?,
            protocol: model::protocol(&object, &operation)?,
        },
    };
    Ok(RecipeProvider {
        operation,
        extension_id,
        version,
        prerequisites: model::prerequisites(&object)?,
        delivery,
    })
}

/// Whether a provider can run on a host offering and platform. Nothing is
/// substituted: a missing platform artifact, ABI or protocol is incompatible.
pub(crate) fn provider_fits(
    provider: &RecipeProvider,
    host: &HostOffering,
    platform: Option<PlatformId>,
) -> std::result::Result<(), String> {
    let protocol = provider.delivery.protocol().version();
    if !host.protocol_versions.contains(&protocol) {
        return Err(format!(
            "the host does not speak MEP {} required by {}",
            protocol.as_str(),
            provider.extension_id
        ));
    }
    match &provider.delivery {
        RecipeDelivery::Process { platforms, .. } => match platform {
            Some(platform) if !platforms.contains_key(&platform) => Err(format!(
                "{} has no process artifact for {platform}",
                provider.extension_id
            )),
            None if !platforms
                .keys()
                .any(|platform| host.platforms.contains_key(platform)) =>
            {
                Err(format!(
                    "{} shares no platform with the host",
                    provider.extension_id
                ))
            }
            _ => Ok(()),
        },
        RecipeDelivery::Wasm { abi, .. } if !host.wasm_abis.contains(abi) => Err(format!(
            "the host does not support the WASM ABI {abi} required by {}",
            provider.extension_id
        )),
        RecipeDelivery::Wasm { .. } | RecipeDelivery::DotnetTool { .. } => Ok(()),
    }
}

fn validate(recipe: &ToolsetRecipe) -> Result<()> {
    for (position, operation) in recipe.operations.iter().enumerate() {
        if recipe.operations[..position].contains(operation) {
            return Err(inconsistent(
                index("operations", position),
                "duplicate operation",
            ));
        }
    }
    for (position, host) in recipe.hosts.iter().enumerate() {
        let path = index("hosts", position);
        if recipe.hosts[..position].iter().any(|other| {
            other.implementation == host.implementation && other.deployment == host.deployment
        }) {
            return Err(inconsistent(
                path,
                format!(
                    "a second offering for {} {}",
                    host.implementation, host.deployment
                ),
            ));
        }
        model::unique_operations(
            &join(&path, "builtIns"),
            host.built_ins.iter().map(|built_in| &built_in.operation),
        )?;
    }
    for (position, provider) in recipe.providers.iter().enumerate() {
        let path = index("providers", position);
        if recipe.providers[..position].iter().any(|other| {
            other.operation == provider.operation
                && other.extension_id == provider.extension_id
                && other.delivery.kind() == provider.delivery.kind()
                && other.version == provider.version
        }) {
            return Err(inconsistent(path, "a duplicate provider delivery"));
        }
        if recipe.hosts.iter().any(|host| {
            host.built_ins
                .iter()
                .any(|built_in| built_in.extension_id == provider.extension_id)
        }) {
            return Err(inconsistent(
                join(&path, "extensionId"),
                format!(
                    "{} is a built-in identity; an external delivery has its own identity",
                    provider.extension_id
                ),
            ));
        }
    }
    for (position, operation) in recipe.operations.iter().enumerate() {
        for host in &recipe.hosts {
            let built_in = host
                .built_ins
                .iter()
                .any(|built_in| &built_in.operation == operation);
            let external = recipe.providers.iter().any(|provider| {
                &provider.operation == operation && provider_fits(provider, host, None).is_ok()
            });
            if !built_in && !external {
                return Err(inconsistent(
                    index("operations", position),
                    format!(
                        "no built-in or compatible provider performs this operation on {} {}",
                        host.implementation, host.deployment
                    ),
                ));
            }
        }
    }
    Ok(())
}
