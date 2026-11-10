//! Pure resolution of one platform closure from a recipe and a request.
//!
//! Nothing here reads a network, a filesystem or a clock. Nothing is
//! substituted: a missing implementation, deployment, release, platform, ABI
//! or protocol is refused, and resolution never falls through from the
//! preferred provider to another one.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::lock::PlatformClosure;
use crate::model::{LockedDelivery, LockedProvider, Operation};
use crate::platform::PlatformId;
use crate::reader::index;
use crate::recipe::{
    BuiltIn, HostOffering, Misfit, RecipeDelivery, RecipeProvider, ToolsetRecipe, provider_fits,
};
use crate::request::{HostSelection, ProviderSelection, ToolchainRequest};

fn unsupported(path: impl Into<String>, message: impl Into<String>) -> Diagnostic {
    Diagnostic::new(Code::UnsupportedArtifact, path, message)
}

fn misfit(path: &str, provider: &RecipeProvider, reason: &Misfit) -> Diagnostic {
    let code = match reason {
        Misfit::Abi(_) => Code::AbiUnavailable,
        _ => Code::UnsupportedArtifact,
    };
    Diagnostic::new(code, path, reason.describe(provider))
}

pub(crate) fn built_in(built_in: &BuiltIn) -> LockedProvider {
    LockedProvider::new(
        built_in.operation().clone(),
        built_in.extension_id().clone(),
        built_in.version().clone(),
        LockedDelivery::BuiltIn {
            model: built_in.model().clone(),
        },
    )
}

/// The locked form of a provider on a platform it fits.
fn external(provider: &RecipeProvider, platform: PlatformId) -> Option<LockedProvider> {
    let delivery = match provider.delivery() {
        RecipeDelivery::Process {
            repository_id,
            descriptor,
            protocol,
            platforms,
        } => LockedDelivery::Process {
            repository_id: repository_id.clone(),
            descriptor: descriptor.clone(),
            artifact: platforms.get(&platform)?.clone(),
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
            descriptor,
            package_id,
            command,
            package,
            protocol,
        } => LockedDelivery::DotnetTool {
            repository_id: repository_id.clone(),
            descriptor: descriptor.clone(),
            package_id: package_id.clone(),
            command: command.clone(),
            package: package.clone(),
            protocol: protocol.clone(),
        },
    };
    Some(LockedProvider::new(
        provider.operation().clone(),
        provider.extension_id().clone(),
        provider.version().clone(),
        delivery,
    ))
}

/// Every provider a lock may record for an operation on a platform: the
/// offering's built-in and each recipe provider that fits there.
pub(crate) fn allowed(
    recipe: &ToolsetRecipe,
    host: &HostOffering,
    platform: PlatformId,
    operation: &Operation,
) -> Vec<LockedProvider> {
    host.built_ins()
        .iter()
        .filter(|candidate| candidate.operation() == operation)
        .map(built_in)
        .chain(
            recipe
                .providers()
                .iter()
                .filter(|provider| {
                    provider.operation() == operation
                        && provider_fits(provider, host, Some(platform)).is_ok()
                })
                .filter_map(|provider| external(provider, platform)),
        )
        .collect()
}

/// An explicit choice: the first built-in or recipe provider, in that order,
/// whose delivery, identity and ABI match it. It must then fit.
fn choose(
    recipe: &ToolsetRecipe,
    host: &HostOffering,
    platform: PlatformId,
    operation: &Operation,
    selection: &ProviderSelection,
    path: &str,
) -> Result<LockedProvider> {
    let identity_matches = |id: &crate::ids::ExtensionIdentity| {
        selection
            .extension_id
            .as_ref()
            .is_none_or(|wanted| wanted == id)
    };
    if selection.abi.is_none()
        && selection
            .delivery
            .is_none_or(|delivery| delivery == crate::model::DeliveryKind::BuiltIn)
        && let Some(candidate) = host.built_ins().iter().find(|candidate| {
            candidate.operation() == operation && identity_matches(candidate.extension_id())
        })
    {
        return Ok(built_in(candidate));
    }
    let provider = recipe
        .providers()
        .iter()
        .find(|provider| {
            provider.operation() == operation
                && identity_matches(provider.extension_id())
                && selection
                    .delivery
                    .is_none_or(|delivery| delivery == provider.delivery().kind())
                && selection.abi.as_ref().is_none_or(|abi| {
                    matches!(provider.delivery(), RecipeDelivery::Wasm { abi: offered, .. } if offered == abi)
                })
        })
        .ok_or_else(|| unsupported(path, "no built-in or recipe provider matches this selection"))?;
    provider_fits(provider, host, Some(platform))
        .map_err(|reason| misfit(path, provider, &reason))?;
    external(provider, platform).ok_or_else(|| unsupported(path, "no artifact for this platform"))
}

/// Resolve the closure a request selects on one platform.
///
/// The offering is the one whose implementation and deployment equal the
/// request's, with an equal release for an exact request. For each operation,
/// an explicit request choice wins; otherwise the offering's built-in;
/// otherwise the recipe's first provider for the operation. A provider that
/// does not fit is refused: `abi_unavailable` names a missing WASM ABI, and
/// `unsupported_artifact` any other misfit. No other provider is substituted.
pub fn resolve_closure(
    recipe: &ToolsetRecipe,
    request: &ToolchainRequest,
    platform: PlatformId,
) -> Result<PlatformClosure> {
    if request.preset() != recipe.preset() {
        return Err(unsupported(
            "toolset.preset",
            format!(
                "the recipe is for {}, not {}",
                recipe.preset(),
                request.preset()
            ),
        ));
    }
    let wanted = request.host();
    let host = recipe
        .hosts()
        .iter()
        .find(|host| {
            host.implementation() == &wanted.implementation
                && host.deployment() == &wanted.deployment
        })
        .ok_or_else(|| {
            unsupported(
                "host",
                format!(
                    "{} {} is not offered; available: {}",
                    wanted.implementation,
                    wanted.deployment,
                    recipe
                        .hosts()
                        .iter()
                        .map(|host| format!("{} {}", host.implementation(), host.deployment()))
                        .collect::<Vec<_>>()
                        .join(", ")
                ),
            )
        })?;
    if let HostSelection::Exact(version) = &wanted.selection
        && version != host.version()
    {
        return Err(unsupported(
            "host.version",
            format!(
                "the recipe offers {} {}, not {version}",
                host.deployment(),
                host.version()
            ),
        ));
    }
    let host_artifact = host.platforms().get(&platform).ok_or_else(|| {
        unsupported(
            "platforms",
            format!(
                "{} {} has no {platform} artifact; available: {}",
                host.implementation(),
                host.deployment(),
                host.platforms()
                    .keys()
                    .map(PlatformId::as_str)
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        )
    })?;

    let mut providers = Vec::with_capacity(recipe.operations().len());
    for operation in recipe.operations() {
        let explicit = request
            .providers()
            .iter()
            .position(|selection| &selection.operation == operation);
        let selected = match explicit {
            Some(position) => choose(
                recipe,
                host,
                platform,
                operation,
                &request.providers()[position],
                &index("toolset.providers", position),
            )?,
            None => match host
                .built_ins()
                .iter()
                .find(|candidate| candidate.operation() == operation)
            {
                Some(candidate) => built_in(candidate),
                None => {
                    let preferred = recipe
                        .providers()
                        .iter()
                        .find(|provider| provider.operation() == operation)
                        .ok_or_else(|| {
                            unsupported("toolset", format!("no provider performs {operation:?}"))
                        })?;
                    provider_fits(preferred, host, Some(platform))
                        .map_err(|reason| misfit("toolset", preferred, &reason))?;
                    external(preferred, platform)
                        .ok_or_else(|| unsupported("toolset", "no artifact for this platform"))?
                }
            },
        };
        providers.push(selected);
    }
    Ok(PlatformClosure::new(host_artifact.clone(), providers))
}
