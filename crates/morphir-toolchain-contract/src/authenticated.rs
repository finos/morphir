//! Recipe bindings checked against authenticated TUF targets metadata.
//!
//! The TUF client authenticates the metadata: signatures, thresholds, expiry,
//! rollback and snapshot links. These checks then prove what an authenticated
//! recipe binds. A validly signed recipe can still name another platform's
//! artifact, another offering's artifact, a wrong digest or an unpublished
//! target, and each of those is refused here.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope::CONTRACT_VERSION;
use crate::ids::{PresetId, Sha256, TargetDigest, TargetPath};
use crate::model::{DeliveryKind, Operation};
use crate::platform::PlatformId;
use crate::reader::{index, join};
use crate::recipe::{HostSource, RecipeDelivery, RecipeProvider, ToolsetRecipe};
use morphir_distribution::{ArtifactRuntime, Channel, ReleaseBundleDescriptor, ToolReleaseRecord};
use semver::Version;
use serde_json::Value;
use std::collections::BTreeMap;

/// One authenticated target entry.
#[derive(Debug, Clone)]
pub struct AuthenticatedTarget {
    /// Declared length.
    pub length: u64,
    /// SHA-256 of the exact target bytes.
    pub sha256: Sha256,
    /// `custom.morphir`, when present.
    pub custom: Option<Value>,
}

/// The `targets` map of verified TUF targets metadata.
#[derive(Debug, Clone)]
pub struct AuthenticatedTargets {
    targets: BTreeMap<String, AuthenticatedTarget>,
}

/// A recipe target's `custom.morphir` metadata. Recipe targets are an
/// additive target kind: version 1 tool clients select only `tool-release`
/// targets and ignore them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecipeTargetState {
    /// Preset.
    pub preset: PresetId,
    /// Recipe release.
    pub version: Version,
    /// Current channel memberships.
    pub channels: Vec<Channel>,
    /// Current status: `active`, `yanked` or `revoked`.
    pub status: String,
}

impl AuthenticatedTargets {
    /// Read the `signed` object of targets metadata whose signatures, expiry
    /// and snapshot links the TUF client has already verified.
    pub fn from_targets_metadata(signed: &Value) -> std::result::Result<Self, String> {
        let entries = signed["targets"]
            .as_object()
            .ok_or("targets metadata has no targets map")?;
        let targets = entries
            .iter()
            .map(|(path, entry)| {
                let length = entry["length"]
                    .as_u64()
                    .ok_or_else(|| format!("{path} has no length"))?;
                let sha256 = entry["hashes"]["sha256"]
                    .as_str()
                    .ok_or_else(|| format!("{path} has no SHA-256 hash"))
                    .and_then(Sha256::parse)?;
                Ok((
                    path.clone(),
                    AuthenticatedTarget {
                        length,
                        sha256,
                        custom: entry["custom"].get("morphir").cloned(),
                    },
                ))
            })
            .collect::<std::result::Result<_, String>>()?;
        Ok(Self { targets })
    }

    /// Return the authenticated digest of a target.
    pub fn digest(&self, path: &str) -> Option<&Sha256> {
        self.targets.get(path).map(|target| &target.sha256)
    }

    /// Return a target's `custom.morphir` metadata.
    pub fn custom(&self, path: &str) -> Option<&Value> {
        self.targets
            .get(path)
            .and_then(|target| target.custom.as_ref())
    }

    /// Verify exact bytes against the authenticated length and digest.
    pub fn authenticate(&self, path: &str, bytes: &[u8]) -> Result<Sha256> {
        let target = self.targets.get(path).ok_or_else(|| {
            Diagnostic::new(
                Code::TargetNotAuthenticated,
                "",
                format!("{path} is not an authenticated target"),
            )
        })?;
        if target.length != bytes.len() as u64 {
            return Err(Diagnostic::new(
                Code::TargetLengthMismatch,
                "",
                format!(
                    "{path} is authenticated as {} bytes, not {}",
                    target.length,
                    bytes.len()
                ),
            ));
        }
        let actual = Sha256::of_bytes(bytes);
        if actual != target.sha256 {
            return Err(Diagnostic::new(
                Code::TargetDigestMismatch,
                "",
                format!(
                    "{path} is authenticated as {}, but the bytes hash to {actual}",
                    target.sha256
                ),
            ));
        }
        Ok(actual)
    }

    /// Return a recipe target's authenticated state.
    pub fn recipe_state(&self, path: &str) -> Option<RecipeTargetState> {
        let custom = self.custom(path)?;
        if custom["kind"] != "toolset-recipe" || custom["schemaVersion"] != CONTRACT_VERSION {
            return None;
        }
        Some(RecipeTargetState {
            preset: PresetId::parse(custom["preset"].as_str()?).ok()?,
            version: Version::parse(custom["version"].as_str()?).ok()?,
            channels: custom["channels"]
                .as_array()?
                .iter()
                .map(|channel| channel.as_str().and_then(|text| Channel::parse(text).ok()))
                .collect::<Option<Vec<_>>>()?,
            status: custom["status"].as_str()?.to_owned(),
        })
    }

    /// Select the greatest active recipe for a preset on a moving channel,
    /// with the tool release metadata v1 channel rules.
    pub fn select_recipe(&self, preset: &PresetId, channel: &Channel) -> Result<TargetPath> {
        self.targets
            .keys()
            .filter_map(|path| self.recipe_state(path).map(|state| (path, state)))
            .filter(|(_, state)| {
                &state.preset == preset
                    && state.status == "active"
                    && channel_matches(channel, &state.version, &state.channels)
            })
            .max_by(|(_, left), (_, right)| left.version.cmp(&right.version))
            .map(|(path, _)| TargetPath::parse(path).expect("authenticated paths are portable"))
            .ok_or_else(|| {
                Diagnostic::new(
                    Code::UnsupportedArtifact,
                    "toolset.preset",
                    format!("no active {preset} recipe is on the {channel} channel"),
                )
            })
    }

    /// Authenticate a recipe target, enforce its authenticated status, read
    /// it, and check every host and provider binding.
    pub fn check_recipe(
        &self,
        path: &str,
        bytes: &[u8],
        read: impl Fn(&str) -> Option<Vec<u8>>,
    ) -> Result<ToolsetRecipe> {
        self.authenticate(path, bytes)?;
        let state = self.recipe_state(path).ok_or_else(|| {
            Diagnostic::new(
                Code::ReleaseDescriptorMismatch,
                "",
                format!("{path} is not authenticated as a {CONTRACT_VERSION} toolset recipe"),
            )
        })?;
        if state.status == "revoked" {
            return Err(Diagnostic::new(
                Code::ReleaseRevoked,
                "",
                format!("{path} is revoked"),
            ));
        }
        let recipe = crate::recipe::read_recipe(bytes)?;
        if recipe.preset != state.preset || recipe.version != state.version {
            return Err(Diagnostic::new(
                Code::ReleaseDescriptorMismatch,
                "",
                format!("{path} disagrees with its authenticated preset and version"),
            ));
        }
        self.check_recipe_hosts(&recipe, &read)?;
        self.check_recipe_providers(&recipe, &read)?;
        Ok(recipe)
    }

    /// Check every provider binding of an authenticated recipe.
    ///
    /// The extension release descriptor is read with the existing version-2
    /// reader and is not rewritten. Its artifacts' claim-check status is left
    /// as published: authenticating the bytes says who published them, not
    /// whether the claims were probed.
    pub fn check_recipe_providers(
        &self,
        recipe: &ToolsetRecipe,
        read: impl Fn(&str) -> Option<Vec<u8>>,
    ) -> Result<()> {
        for (position, provider) in recipe.providers.iter().enumerate() {
            let path = index("providers", position);
            match &provider.delivery {
                RecipeDelivery::Process {
                    descriptor,
                    platforms,
                    ..
                } => {
                    let release = self.descriptor(&path, provider, descriptor, &read)?;
                    for (platform, binding) in platforms {
                        let binding_path = join(&join(&path, "platforms"), platform.as_str());
                        self.bound_target(&binding_path, "artifact", binding)?;
                        check_extension_artifact(
                            &release,
                            descriptor,
                            provider,
                            Some(*platform),
                            binding,
                            &path,
                            &binding_path,
                        )?;
                    }
                }
                RecipeDelivery::Wasm {
                    descriptor,
                    artifact,
                    ..
                } => {
                    let release = self.descriptor(&path, provider, descriptor, &read)?;
                    self.bound_target(&path, "artifact", artifact)?;
                    check_extension_artifact(
                        &release, descriptor, provider, None, artifact, &path, &path,
                    )?;
                }
                RecipeDelivery::DotnetTool { package, .. } => {
                    self.bound_target(&path, "package", package)?;
                }
            }
        }
        Ok(())
    }

    /// Check that `<prefix>Target` is authenticated with `<prefix>Sha256`.
    fn bound_target(&self, path: &str, prefix: &str, binding: &TargetDigest) -> Result<()> {
        let target = binding.target.as_str();
        let entry = self.targets.get(target).ok_or_else(|| {
            Diagnostic::new(
                Code::TargetNotAuthenticated,
                join(path, &format!("{prefix}Target")),
                format!("{target} is not an authenticated target"),
            )
        })?;
        if entry.sha256 != binding.sha256 {
            return Err(Diagnostic::new(
                Code::TargetDigestMismatch,
                join(path, &format!("{prefix}Sha256")),
                format!(
                    "the recipe binds {target} to {}, but it is authenticated as {}",
                    binding.sha256, entry.sha256
                ),
            ));
        }
        Ok(())
    }

    fn descriptor(
        &self,
        path: &str,
        provider: &RecipeProvider,
        descriptor: &TargetDigest,
        read: &impl Fn(&str) -> Option<Vec<u8>>,
    ) -> Result<ReleaseBundleDescriptor> {
        self.bound_target(path, "descriptor", descriptor)?;
        let target = descriptor.target.as_str();
        let bytes = read(target).ok_or_else(|| {
            Diagnostic::new(
                Code::TargetNotAuthenticated,
                join(path, "descriptorTarget"),
                format!("{target} is not available"),
            )
        })?;
        self.authenticate(target, &bytes)?;
        let release = ReleaseBundleDescriptor::parse_json(&bytes).map_err(|error| {
            Diagnostic::new(
                Code::ReleaseDescriptorMismatch,
                join(path, "descriptorTarget"),
                format!("{target} is not an extension release descriptor: {error}"),
            )
        })?;
        if release.version() != &provider.version {
            return Err(Diagnostic::new(
                Code::ReleaseDescriptorMismatch,
                join(path, "version"),
                format!(
                    "{target} describes release {}, not {}",
                    release.version(),
                    provider.version
                ),
            ));
        }
        Ok(release)
    }

    /// Check every host binding of an authenticated recipe.
    ///
    /// `read` returns the bytes of an authenticated target, such as a tool
    /// release descriptor; they are authenticated again before use.
    pub fn check_recipe_hosts(
        &self,
        recipe: &ToolsetRecipe,
        read: impl Fn(&str) -> Option<Vec<u8>>,
    ) -> Result<()> {
        for (position, host) in recipe.hosts.iter().enumerate() {
            let host_path = index("hosts", position);
            let release = match &host.source {
                HostSource::ToolRelease { tool_id } => {
                    let path = format!("releases/{tool_id}/{}.json", host.version);
                    let custom = self.custom(&path).filter(|custom| {
                        custom["kind"] == "tool-release"
                            && custom["toolId"] == tool_id.as_str()
                            && custom["version"] == host.version.to_string()
                    });
                    let Some(custom) = custom else {
                        return Err(Diagnostic::new(
                            Code::TargetNotAuthenticated,
                            join(&host_path, "source"),
                            format!("{path} is not an authenticated tool release"),
                        ));
                    };
                    if custom["status"] == "revoked" {
                        return Err(Diagnostic::new(
                            Code::ReleaseRevoked,
                            join(&host_path, "version"),
                            format!("{tool_id} {} is revoked", host.version),
                        ));
                    }
                    let bytes = read(&path).ok_or_else(|| {
                        Diagnostic::new(
                            Code::TargetNotAuthenticated,
                            join(&host_path, "source"),
                            format!("{path} is not available"),
                        )
                    })?;
                    self.authenticate(&path, &bytes)?;
                    let record: ToolReleaseRecord =
                        serde_json::from_slice(&bytes).map_err(|error| {
                            Diagnostic::new(
                                Code::ReleaseDescriptorMismatch,
                                join(&host_path, "source"),
                                format!("{path} is not a v1 tool release: {error}"),
                            )
                        })?;
                    Some(record)
                }
                HostSource::DotnetTool { .. } => None,
            };
            for (platform, binding) in &host.platforms {
                let path = join(&join(&host_path, "platforms"), platform.as_str());
                let target = binding.target.as_str();
                let Some(entry) = self.targets.get(target) else {
                    return Err(Diagnostic::new(
                        Code::TargetNotAuthenticated,
                        join(&path, "target"),
                        format!("{target} is not an authenticated target"),
                    ));
                };
                if entry.sha256 != binding.sha256 {
                    return Err(Diagnostic::new(
                        Code::TargetDigestMismatch,
                        join(&path, "sha256"),
                        format!(
                            "the recipe binds {target} to {}, but it is authenticated as {}",
                            binding.sha256, entry.sha256
                        ),
                    ));
                }
                if let Some(record) = &release {
                    check_release_artifact(record, *platform, target, entry, &path)?;
                }
            }
        }
        Ok(())
    }
}

fn check_release_artifact(
    record: &ToolReleaseRecord,
    platform: PlatformId,
    target: &str,
    entry: &AuthenticatedTarget,
    path: &str,
) -> Result<()> {
    let target_path = join(path, "target");
    let artifact = record
        .artifacts()
        .iter()
        .find(|artifact| artifact.target_path().as_str() == target)
        .ok_or_else(|| {
            Diagnostic::new(
                Code::ReleaseDescriptorMismatch,
                &target_path,
                format!(
                    "{} {} does not publish {target}",
                    record.tool_id(),
                    record.version()
                ),
            )
        })?;
    let expected = platform
        .tool_platform()
        .expect("recipe validation keeps musl platforms off v1 offerings");
    if artifact.platform() != &expected {
        return Err(Diagnostic::new(
            Code::ArtifactPlatformMismatch,
            &target_path,
            format!(
                "{target} is the {} artifact, not the {platform} artifact",
                artifact.platform()
            ),
        ));
    }
    let custom = entry.custom.as_ref();
    let agrees = custom.is_some_and(|custom| {
        custom["kind"] == "tool-artifact"
            && custom["toolId"] == record.tool_id().as_str()
            && custom["version"] == record.version().to_string()
            && custom["platform"]["os"] == expected.os()
            && custom["platform"]["arch"] == expected.arch()
    });
    if agrees {
        Ok(())
    } else {
        Err(Diagnostic::new(
            Code::ReleaseDescriptorMismatch,
            &target_path,
            format!("the authenticated artifact metadata of {target} disagrees with its release"),
        ))
    }
}

/// Check one bound artifact against the descriptor entry that lists it.
fn check_extension_artifact(
    release: &ReleaseBundleDescriptor,
    descriptor: &TargetDigest,
    provider: &RecipeProvider,
    platform: Option<PlatformId>,
    binding: &TargetDigest,
    provider_path: &str,
    binding_path: &str,
) -> Result<()> {
    let target_path = join(binding_path, "artifactTarget");
    let mismatch = |path: &str, message: String| {
        Diagnostic::new(Code::ReleaseDescriptorMismatch, path, message)
    };
    let directory = descriptor
        .target
        .as_str()
        .rsplit_once('/')
        .map_or("", |(directory, _)| directory);
    let artifact = release
        .artifacts()
        .iter()
        .find(|artifact| {
            format!("{directory}/{}", artifact.filename().as_str()) == binding.target.as_str()
        })
        .ok_or_else(|| {
            mismatch(
                &target_path,
                format!("{} does not list {}", descriptor.target, binding.target),
            )
        })?;
    let runtime = match provider.delivery.kind() {
        DeliveryKind::Wasm => ArtifactRuntime::Wasm,
        _ => ArtifactRuntime::Process,
    };
    if artifact.runtime() != runtime {
        return Err(mismatch(
            &target_path,
            format!(
                "{} is not a {} artifact",
                binding.target,
                provider.delivery.kind().as_str()
            ),
        ));
    }
    if let Some(platform) = platform
        && artifact.platform() != Some(platform.target_triple())
    {
        return Err(Diagnostic::new(
            Code::ArtifactPlatformMismatch,
            &target_path,
            format!(
                "{} is the {} artifact, not the {} artifact",
                binding.target,
                artifact.platform().unwrap_or("portable"),
                platform.target_triple()
            ),
        ));
    }
    if artifact.sha256() != binding.sha256.digest() {
        return Err(Diagnostic::new(
            Code::TargetDigestMismatch,
            join(binding_path, "artifactSha256"),
            format!(
                "{} lists {} with another digest",
                descriptor.target, binding.target
            ),
        ));
    }
    let claims = artifact.claims();
    if claims.extension.id != provider.extension_id.as_str()
        || claims.extension.version != provider.version.to_string()
    {
        return Err(mismatch(
            &join(provider_path, "extensionId"),
            format!(
                "the artifact claims {} {}, not {} {}",
                claims.extension.id,
                claims.extension.version,
                provider.extension_id,
                provider.version
            ),
        ));
    }
    let kind = match provider.operation {
        Operation::Compile { .. } => "frontend",
        Operation::Generate { .. } => "backend",
    };
    let types = serde_json::to_value(&claims.extension.types).unwrap_or_default();
    if !types
        .as_array()
        .is_some_and(|types| types.iter().any(|item| item == kind))
    {
        return Err(mismatch(
            &join(provider_path, "operation"),
            format!("the artifact does not claim the {kind} capability kind"),
        ));
    }
    let protocol = provider.delivery.protocol().version();
    if !claims
        .protocol_versions
        .iter()
        .any(|version| version == protocol.as_str())
    {
        return Err(mismatch(
            &join(provider_path, "protocolVersion"),
            format!("the artifact does not claim MEP {}", protocol.as_str()),
        ));
    }
    Ok(())
}

fn channel_matches(requested: &Channel, version: &Version, channels: &[Channel]) -> bool {
    match requested {
        Channel::Stable => version.pre.is_empty() && channels.contains(&Channel::Stable),
        Channel::Preview(None) | Channel::Insiders => channels
            .iter()
            .any(|channel| matches!(channel, Channel::Preview(_) | Channel::Insiders)),
        Channel::Preview(Some(_)) => channels.contains(requested),
    }
}
