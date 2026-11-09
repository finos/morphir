//! Pure resolution of one platform closure from a recipe and a request.
//!
//! Nothing here reads a network, a filesystem or a clock. Nothing is
//! substituted: a missing implementation, deployment, release, platform, ABI
//! or protocol is `unsupported_artifact`.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::lock::PlatformClosure;
use crate::model::{DeliveryKind, LockedDelivery, LockedProvider, Operation};
use crate::platform::PlatformId;
use crate::reader::index;
use crate::recipe::{
    BuiltIn, HostOffering, RecipeDelivery, RecipeProvider, ToolsetRecipe, provider_fits,
};
use crate::request::{HostSelection, ProviderSelection, ToolchainRequest};

fn unsupported(path: impl Into<String>, message: impl Into<String>) -> Diagnostic {
    Diagnostic::new(Code::UnsupportedArtifact, path, message)
}

fn built_in(built_in: &BuiltIn) -> LockedProvider {
    LockedProvider {
        operation: built_in.operation.clone(),
        extension_id: built_in.extension_id.clone(),
        version: built_in.version.clone(),
        delivery: LockedDelivery::BuiltIn {
            model_input: built_in.model_input.clone(),
        },
    }
}

fn external(provider: &RecipeProvider, platform: PlatformId) -> LockedProvider {
    let delivery = match &provider.delivery {
        RecipeDelivery::Process {
            repository_id,
            descriptor,
            protocol,
            platforms,
        } => LockedDelivery::Process {
            repository_id: repository_id.clone(),
            descriptor: descriptor.clone(),
            artifact: platforms[&platform].clone(),
            protocol: protocol.clone(),
        },
        RecipeDelivery::Wasm {
            abi,
            repository_id,
            descriptor,
            artifact,
            protocol,
        } => LockedDelivery::Wasm {
            abi: abi.clone(),
            repository_id: repository_id.clone(),
            descriptor: descriptor.clone(),
            artifact: artifact.clone(),
            protocol: protocol.clone(),
        },
        RecipeDelivery::DotnetTool {
            repository_id,
            package_id,
            command,
            package,
            protocol,
        } => LockedDelivery::DotnetTool {
            repository_id: repository_id.clone(),
            package_id: package_id.clone(),
            command: command.clone(),
            package: package.clone(),
            protocol: protocol.clone(),
        },
    };
    LockedProvider {
        operation: provider.operation.clone(),
        extension_id: provider.extension_id.clone(),
        version: provider.version.clone(),
        delivery,
    }
}

fn candidates(
    recipe: &ToolsetRecipe,
    host: &HostOffering,
    platform: PlatformId,
    operation: &Operation,
) -> (Vec<LockedProvider>, Vec<String>) {
    let mut fitting = host
        .built_ins
        .iter()
        .filter(|candidate| &candidate.operation == operation)
        .map(built_in)
        .collect::<Vec<_>>();
    let mut refused = Vec::new();
    for provider in recipe
        .providers
        .iter()
        .filter(|provider| &provider.operation == operation)
    {
        match provider_fits(provider, host, Some(platform)) {
            Ok(()) => fitting.push(external(provider, platform)),
            Err(reason) => refused.push(reason),
        }
    }
    (fitting, refused)
}

fn chosen(selection: &ProviderSelection, candidate: &LockedProvider) -> bool {
    selection
        .delivery
        .is_none_or(|delivery| delivery == candidate.delivery.kind())
        && selection
            .extension_id
            .as_ref()
            .is_none_or(|id| id == &candidate.extension_id)
}

/// Resolve the closure a request selects on one platform.
///
/// The offering is the one whose implementation and deployment equal the
/// request's, with an equal release for an exact request. For each operation
/// an explicit request choice wins; otherwise a built-in wins; otherwise the
/// first provider, in recipe order, that fits the host and platform.
pub fn resolve_closure(
    recipe: &ToolsetRecipe,
    request: &ToolchainRequest,
    platform: PlatformId,
) -> Result<PlatformClosure> {
    if request.preset != recipe.preset {
        return Err(unsupported(
            "toolset.preset",
            format!(
                "the recipe is for {}, not {}",
                recipe.preset, request.preset
            ),
        ));
    }
    let wanted = &request.host;
    let host = recipe
        .hosts
        .iter()
        .find(|host| {
            host.implementation == wanted.implementation && host.deployment == wanted.deployment
        })
        .ok_or_else(|| {
            unsupported(
                "host",
                format!(
                    "{} {} is not offered; available: {}",
                    wanted.implementation,
                    wanted.deployment,
                    recipe
                        .hosts
                        .iter()
                        .map(|host| format!("{} {}", host.implementation, host.deployment))
                        .collect::<Vec<_>>()
                        .join(", ")
                ),
            )
        })?;
    if let HostSelection::Exact(version) = &wanted.selection
        && version != &host.version
    {
        return Err(unsupported(
            "host.version",
            format!(
                "the recipe offers {} {}, not {version}",
                host.deployment, host.version
            ),
        ));
    }
    let host_artifact = host.platforms.get(&platform).ok_or_else(|| {
        unsupported(
            "platforms",
            format!(
                "{} {} has no {platform} artifact; available: {}",
                host.implementation,
                host.deployment,
                host.platforms
                    .keys()
                    .map(PlatformId::as_str)
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        )
    })?;

    let mut providers = Vec::with_capacity(recipe.operations.len());
    for operation in &recipe.operations {
        let (fitting, refused) = candidates(recipe, host, platform, operation);
        let explicit = request
            .providers
            .iter()
            .position(|selection| &selection.operation == operation);
        let selected = match explicit {
            Some(position) => fitting
                .into_iter()
                .find(|candidate| chosen(&request.providers[position], candidate))
                .ok_or_else(|| {
                    unsupported(
                        index("toolset.providers", position),
                        format!(
                            "no compatible provider matches this selection; {}",
                            refused.join("; ")
                        ),
                    )
                })?,
            None => {
                let built_in = fitting
                    .iter()
                    .position(|candidate| candidate.delivery.kind() == DeliveryKind::BuiltIn);
                let mut fitting = fitting;
                match built_in {
                    Some(position) => fitting.swap_remove(position),
                    None if !fitting.is_empty() => fitting.remove(0),
                    None => {
                        return Err(unsupported(
                            "toolset",
                            format!(
                                "no built-in or compatible provider performs {operation:?} on {platform}; {}",
                                refused.join("; ")
                            ),
                        ));
                    }
                }
            }
        };
        providers.push(selected);
    }
    Ok(PlatformClosure {
        host: host_artifact.clone(),
        providers,
    })
}
