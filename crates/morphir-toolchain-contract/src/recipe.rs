//! The toolset recipe, an authenticated target such as
//! `toolchains/recipes/fsharp/1.0.0.json`.
//!
//! A recipe maps host offerings (implementation, release, deployment) to the
//! tool release metadata v1 tool ids or .NET tool packages that publish them,
//! and binds each required operation to built-in or independently released
//! providers by exact digests. It does not change the extension descriptor
//! format.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope;
use crate::ids::{
    CommandName, DeploymentId, ExtensionIdentity, ImplementationId, PackageId, PresetId,
    ProtocolVersion, Sha256, TargetDigest, WasmAbi,
};
use crate::model::{self, DeliveryKind, ModelInput, Operation, Prerequisite, Protocol};
use crate::platform::{Os, PlatformId};
use crate::reader::{Node, Obj, inconsistent, index, join};
use morphir_distribution::ToolId;
use semver::Version;
use serde_json::Value;
use std::collections::BTreeMap;

/// Member paths a `0.1.0-draft.1` recipe reader understands. `*` names any
/// platform key.
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
    "hosts.platforms.*",
    "hosts.platforms.*.target",
    "hosts.platforms.*.sha256",
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
    "providers.platforms.*",
    "providers.platforms.*.artifactTarget",
    "providers.platforms.*.artifactSha256",
];

/// How a host executes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Execution {
    /// Native compiled code without an installed .NET runtime.
    NativeAot,
    /// Managed code under a JIT, with a bundled or installed runtime.
    Jit,
}

impl Execution {
    pub(crate) const CASES: &'static [(&'static str, Self)] =
        &[("native-aot", Self::NativeAot), ("jit", Self::Jit)];
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
    /// per platform like any other host artifact. A .NET tool package has no
    /// version 1 release status: revocation reaches it only through the recipe.
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
    operation: Operation,
    extension_id: ExtensionIdentity,
    version: Version,
    model_input: ModelInput,
}

impl BuiltIn {
    /// The operation it performs.
    pub fn operation(&self) -> &Operation {
        &self.operation
    }
    /// Its registry identity, such as `morphir.fsharp`.
    pub fn extension_id(&self) -> &ExtensionIdentity {
        &self.extension_id
    }
    /// Its exact version.
    pub fn version(&self) -> &Version {
        &self.version
    }
    /// Its model input.
    pub fn model_input(&self) -> &ModelInput {
        &self.model_input
    }
}

/// One host offering: an implementation, release and deployment.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostOffering {
    implementation: ImplementationId,
    version: Version,
    deployment: DeploymentId,
    execution: Execution,
    source: HostSource,
    protocol_versions: Vec<ProtocolVersion>,
    wasm_abis: Vec<WasmAbi>,
    prerequisites: Vec<Prerequisite>,
    built_ins: Vec<BuiltIn>,
    platforms: BTreeMap<PlatformId, TargetDigest>,
}

impl HostOffering {
    /// The implementation.
    pub fn implementation(&self) -> &ImplementationId {
        &self.implementation
    }
    /// The exact release.
    pub fn version(&self) -> &Version {
        &self.version
    }
    /// The deployment offering.
    pub fn deployment(&self) -> &DeploymentId {
        &self.deployment
    }
    /// The execution mode.
    pub fn execution(&self) -> Execution {
        self.execution
    }
    /// The publication source.
    pub fn source(&self) -> &HostSource {
        &self.source
    }
    /// The MEP versions the host speaks.
    pub fn protocol_versions(&self) -> &[ProtocolVersion] {
        &self.protocol_versions
    }
    /// The WASM ABIs the host's qualified engine supports.
    pub fn wasm_abis(&self) -> &[WasmAbi] {
        &self.wasm_abis
    }
    /// The declared prerequisites.
    pub fn prerequisites(&self) -> &[Prerequisite] {
        &self.prerequisites
    }
    /// The built-in providers.
    pub fn built_ins(&self) -> &[BuiltIn] {
        &self.built_ins
    }
    /// The authenticated artifact for each supported platform.
    pub fn platforms(&self) -> &BTreeMap<PlatformId, TargetDigest> {
        &self.platforms
    }
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
    /// A framework-dependent .NET tool package. The version-2 extension
    /// descriptor has no runtime for .NET tool packages, so the provider binds
    /// the release's descriptor, whose claims describe the guest.
    DotnetTool {
        /// Repository holding the package and descriptor.
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

    /// Return the repository holding the descriptor and artifacts.
    pub fn repository_id(&self) -> &Sha256 {
        match self {
            Self::Process { repository_id, .. }
            | Self::Wasm { repository_id, .. }
            | Self::DotnetTool { repository_id, .. } => repository_id,
        }
    }

    /// Return the extension release descriptor.
    pub fn descriptor(&self) -> &TargetDigest {
        match self {
            Self::Process { descriptor, .. }
            | Self::Wasm { descriptor, .. }
            | Self::DotnetTool { descriptor, .. } => descriptor,
        }
    }
}

/// An independently released provider a recipe may select.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecipeProvider {
    operation: Operation,
    extension_id: ExtensionIdentity,
    version: Version,
    prerequisites: Vec<Prerequisite>,
    delivery: RecipeDelivery,
}

impl RecipeProvider {
    /// The operation it performs.
    pub fn operation(&self) -> &Operation {
        &self.operation
    }
    /// Its registry and MEP identity.
    pub fn extension_id(&self) -> &ExtensionIdentity {
        &self.extension_id
    }
    /// Its exact release.
    pub fn version(&self) -> &Version {
        &self.version
    }
    /// Its declared prerequisites.
    pub fn prerequisites(&self) -> &[Prerequisite] {
        &self.prerequisites
    }
    /// Its delivery.
    pub fn delivery(&self) -> &RecipeDelivery {
        &self.delivery
    }
}

/// A parsed toolset recipe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolsetRecipe {
    preset: PresetId,
    version: Version,
    operations: Vec<Operation>,
    hosts: Vec<HostOffering>,
    providers: Vec<RecipeProvider>,
}

impl ToolsetRecipe {
    /// The preset name.
    pub fn preset(&self) -> &PresetId {
        &self.preset
    }
    /// The recipe release.
    pub fn version(&self) -> &Version {
        &self.version
    }
    /// The required operations, in workflow order. Never empty.
    pub fn operations(&self) -> &[Operation] {
        &self.operations
    }
    /// The host offerings. Never empty.
    pub fn hosts(&self) -> &[HostOffering] {
        &self.hosts
    }
    /// The providers, in preference order.
    pub fn providers(&self) -> &[RecipeProvider] {
        &self.providers
    }
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

#[derive(Clone, Copy)]
enum SourceTag {
    ToolRelease,
    DotnetTool,
}

fn host_offering(node: Node<'_>) -> Result<HostOffering> {
    let host = node.object()?;
    let source = host.req("source", |node| {
        let source = node.object()?;
        match source.case(
            "kind",
            &[
                ("tool-release", SourceTag::ToolRelease),
                ("dotnet-tool", SourceTag::DotnetTool),
            ],
        )? {
            SourceTag::ToolRelease => Ok(HostSource::ToolRelease {
                tool_id: source.req("toolId", |node| {
                    node.parse(Code::InvalidValue, |text| {
                        ToolId::parse(text).map_err(|error| error.to_string())
                    })
                })?,
            }),
            SourceTag::DotnetTool => Ok(HostSource::DotnetTool {
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
        execution: host.case("execution", Execution::CASES)?,
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
    let kind = model::delivery(&object)?;
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
            descriptor: model::digest_pair(&object, "descriptorTarget", "descriptorSha256")?,
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

/// Why a provider cannot run on a host offering and platform.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Misfit {
    /// The host does not speak the provider's MEP version.
    Protocol(ProtocolVersion),
    /// The provider has no process artifact for the platform.
    Platform(PlatformId),
    /// The provider shares no platform with the host.
    NoSharedPlatform,
    /// The host does not support the provider's WASM ABI.
    Abi(WasmAbi),
}

impl Misfit {
    pub(crate) fn describe(&self, provider: &RecipeProvider) -> String {
        match self {
            Self::Protocol(version) => format!(
                "the host does not speak MEP {} required by {}",
                version.as_str(),
                provider.extension_id
            ),
            Self::Platform(platform) => format!(
                "{} has no process artifact for {platform}",
                provider.extension_id
            ),
            Self::NoSharedPlatform => {
                format!("{} shares no platform with the host", provider.extension_id)
            }
            Self::Abi(abi) => format!(
                "the host does not support the WASM ABI {abi} required by {}",
                provider.extension_id
            ),
        }
    }
}

/// Whether a provider can run on a host offering and platform. Nothing is
/// substituted: a missing platform artifact, ABI or protocol is a misfit.
pub(crate) fn provider_fits(
    provider: &RecipeProvider,
    host: &HostOffering,
    platform: Option<PlatformId>,
) -> std::result::Result<(), Misfit> {
    let protocol = provider.delivery.protocol().version();
    if !host.protocol_versions.contains(&protocol) {
        return Err(Misfit::Protocol(protocol));
    }
    match &provider.delivery {
        RecipeDelivery::Process { platforms, .. } => match platform {
            Some(platform) if !platforms.contains_key(&platform) => Err(Misfit::Platform(platform)),
            None if !platforms
                .keys()
                .any(|platform| host.platforms.contains_key(platform)) =>
            {
                Err(Misfit::NoSharedPlatform)
            }
            _ => Ok(()),
        },
        RecipeDelivery::Wasm { abi, .. } if !host.wasm_abis.contains(abi) => {
            Err(Misfit::Abi(abi.clone()))
        }
        RecipeDelivery::Wasm { .. } | RecipeDelivery::DotnetTool { .. } => Ok(()),
    }
}

fn validate(recipe: &ToolsetRecipe) -> Result<()> {
    if recipe.operations.is_empty() {
        return Err(inconsistent(
            "operations",
            "a recipe requires at least one operation",
        ));
    }
    if recipe.hosts.is_empty() {
        return Err(inconsistent("hosts", "a recipe offers at least one host"));
    }
    for (position, operation) in recipe.operations.iter().enumerate() {
        if recipe.operations[..position].contains(operation) {
            return Err(inconsistent(
                index("operations", position),
                "duplicate operation",
            ));
        }
    }
    // Each rule is checked over its whole array before the next rule, in the
    // order of the consistency table on the toolset recipe page.
    for (position, host) in recipe.hosts.iter().enumerate() {
        if recipe.hosts[..position].iter().any(|other| {
            other.implementation == host.implementation && other.deployment == host.deployment
        }) {
            return Err(inconsistent(
                index("hosts", position),
                format!(
                    "a second offering for {} {}",
                    host.implementation, host.deployment
                ),
            ));
        }
    }
    for (position, host) in recipe.hosts.iter().enumerate() {
        model::unique_operations(
            &join(&index("hosts", position), "builtIns"),
            host.built_ins.iter().map(|built_in| &built_in.operation),
        )?;
    }
    for (position, provider) in recipe.providers.iter().enumerate() {
        if recipe.providers[..position].iter().any(|other| {
            other.operation == provider.operation
                && other.extension_id == provider.extension_id
                && other.delivery.kind() == provider.delivery.kind()
                && other.version == provider.version
        }) {
            return Err(inconsistent(
                index("providers", position),
                "a duplicate provider delivery",
            ));
        }
    }
    for (position, provider) in recipe.providers.iter().enumerate() {
        let path = index("providers", position);
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
