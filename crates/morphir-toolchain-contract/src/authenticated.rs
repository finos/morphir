//! Recipe bindings checked against an authenticated tool repository.
//!
//! [`AuthenticatedTargets`] is built only by loading a repository through the
//! TUF client from an out-of-band trusted root, so every target it lists has
//! passed signature, threshold, expiry, rollback and snapshot-link checks.
//! These checks then prove what an authenticated recipe binds: a validly
//! signed recipe can still name another platform's artifact, another
//! offering's artifact, a wrong digest, an unpublished target or an artifact
//! whose claims do not fit, and each of those is refused here.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope::CONTRACT_VERSION;
use crate::ids::{PresetId, Sha256, TargetDigest, TargetPath};
use crate::model::{Operation, Protocol};
use crate::platform::PlatformId;
use crate::reader::{index, join};
use crate::recipe::{HostSource, RecipeDelivery, RecipeProvider, ToolsetRecipe};
use futures_core::Stream;
use morphir_distribution::{ArtifactRuntime, Channel, ReleaseBundleDescriptor, ToolReleaseRecord};
use semver::Version;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;
use tough::{FilesystemTransport, Limits, RepositoryLoader, TargetName};

/// One authenticated target entry.
#[derive(Debug, Clone)]
struct AuthenticatedTarget {
    length: u64,
    sha256: Sha256,
    custom: Option<Value>,
}

/// The current authenticated status of a recipe target.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecipeStatus {
    /// Eligible for channel and exact selection.
    Active,
    /// Excluded from channels, still eligible by exact target.
    Yanked,
    /// Refused.
    Revoked,
}

/// A recipe target's `custom.morphir` metadata. Recipe targets are an
/// additive target kind, versioned by the recipe contract.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecipeTargetState {
    /// Preset.
    pub preset: PresetId,
    /// Recipe release.
    pub version: Version,
    /// Current channel memberships.
    pub channels: Vec<Channel>,
    /// Current status.
    pub status: RecipeStatus,
}

/// The authenticated targets of a loaded tool repository.
pub struct AuthenticatedTargets {
    repository: tough::Repository,
    repository_id: Sha256,
    targets: BTreeMap<String, AuthenticatedTarget>,
    targets_version: u64,
}

impl std::fmt::Debug for AuthenticatedTargets {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("AuthenticatedTargets")
            .field("targets", &self.targets.len())
            .field("targets_version", &self.targets_version)
            .finish()
    }
}

/// The stable code for a TUF client failure. `target` says whether the
/// failure happened while reading a target rather than metadata.
fn trust_code(error: &tough::error::Error, target: bool) -> Code {
    use tough::error::Error as E;
    let mut current: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(error) = current {
        if let Some(error) = error.downcast_ref::<E>() {
            let code = match error {
                E::ExpiredMetadata { .. } => Some(Code::MetadataExpired),
                E::VerifyMetadata { .. }
                | E::VerifyRoleMetadata { .. }
                | E::VerifyTrustedMetadata { .. } => Some(Code::MetadataSignatureInvalid),
                E::OlderMetadata { .. }
                | E::VersionMismatch { .. }
                | E::SnapshotRoleRollback { .. }
                | E::OlderSnapshotInTimestamp { .. } => Some(Code::MetadataRollback),
                E::MaxUpdatesExceeded { .. } => Some(Code::MetadataRootRotationInvalid),
                E::HashMismatch { .. } if target => Some(Code::TargetDigestMismatch),
                E::MaxSizeExceeded { .. } if target => Some(Code::TargetLengthMismatch),
                E::HashMismatch { .. } | E::MaxSizeExceeded { .. } => {
                    Some(Code::MetadataLinkMismatch)
                }
                _ => None,
            };
            if let Some(code) = code {
                return code;
            }
        }
        current = error.source();
    }
    Code::RepositoryUnavailable
}

fn invalid_metadata(path: &str, message: impl Into<String>) -> Diagnostic {
    Diagnostic::new(Code::RepositoryUnavailable, path, message)
}

impl AuthenticatedTargets {
    /// Load and authenticate a filesystem repository from an out-of-band
    /// trusted root. Expiry is enforced against the current time.
    pub async fn load_filesystem(
        trusted_root: &[u8],
        metadata_directory: &Path,
        targets_directory: &Path,
        datastore: &Path,
    ) -> Result<Self> {
        std::fs::create_dir_all(datastore).map_err(|error| {
            invalid_metadata(
                "",
                format!("cannot create {}: {error}", datastore.display()),
            )
        })?;
        let url = |path: &Path| {
            url::Url::from_directory_path(path).map_err(|()| {
                invalid_metadata("", format!("{} is not a directory URL", path.display()))
            })
        };
        let repository = RepositoryLoader::new(
            &trusted_root,
            url(metadata_directory)?,
            url(targets_directory)?,
        )
        .transport(FilesystemTransport)
        .limits(Limits {
            max_root_updates: 32,
            ..Limits::default()
        })
        .datastore(datastore)
        .load()
        .await
        .map_err(|error| Diagnostic::new(trust_code(&error, false), "", error.to_string()))?;
        let mut targets = BTreeMap::new();
        for (name, target) in repository.all_targets() {
            // Publication refuses non-NFC target paths, because canonical
            // encoding would sign them under their NFC spelling. A server
            // that serves non-canonical metadata could still list one, and
            // the client would then disagree with every canonical encoder.
            if !unicode_normalization::is_nfc(name.raw()) {
                return Err(Diagnostic::new(
                    Code::NonPortablePath,
                    "",
                    format!(
                        "the targets metadata lists {}, which is not NFC",
                        name.raw()
                    ),
                ));
            }
            let digest: [u8; 32] = target.hashes.sha256.as_ref().try_into().map_err(|_| {
                invalid_metadata("", format!("{} has no SHA-256 digest", name.raw()))
            })?;
            targets.insert(
                name.raw().to_owned(),
                AuthenticatedTarget {
                    length: target.length,
                    sha256: Sha256::of_digest(morphir_distribution::Sha256Digest::from_bytes(
                        digest,
                    )),
                    custom: target.custom.get("morphir").cloned(),
                },
            );
        }
        let targets_version = repository.targets().signed.version.get();
        // The repository identity of tool release metadata v1: the SHA-256 of
        // the canonical JSON of the out-of-band trusted root's `signed`
        // object. Root rotation does not change it.
        let root: Value = serde_json::from_slice(trusted_root).map_err(|error| {
            invalid_metadata("", format!("the trusted root is not JSON: {error}"))
        })?;
        let repository_id = crate::result::canonical_sha256(&root["signed"])
            .map_err(|message| invalid_metadata("", message))?;
        Ok(Self {
            repository,
            repository_id,
            targets,
            targets_version,
        })
    }

    /// The repository identity: the SHA-256 of the canonical JSON of the
    /// trusted root's `signed` object, as tool release metadata v1 defines it.
    pub fn repository_id(&self) -> &Sha256 {
        &self.repository_id
    }

    /// The authenticated targets metadata version.
    pub fn targets_version(&self) -> u64 {
        self.targets_version
    }

    /// The authenticated digest of a target.
    pub fn digest(&self, path: &str) -> Option<&Sha256> {
        self.targets.get(path).map(|target| &target.sha256)
    }

    /// A target's `custom.morphir` metadata.
    pub fn custom(&self, path: &str) -> Option<&Value> {
        self.targets
            .get(path)
            .and_then(|target| target.custom.as_ref())
    }

    /// Verify bytes from elsewhere, such as a local store, against the
    /// authenticated length and digest. Refusals concern the target itself
    /// and have the empty path.
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

    /// Read a target's bytes through the TUF client, which verifies their
    /// length and digest. Refusals have the empty path.
    ///
    /// As in [`Self::authenticate`], the length is decided first: bytes that
    /// are longer or shorter than the authenticated length are
    /// `target_length_mismatch`, and bytes of the right length that hash to
    /// another digest are `target_digest_mismatch`.
    pub async fn read(&self, path: &str) -> Result<Vec<u8>> {
        let Some(authenticated) = self.targets.get(path) else {
            return Err(Diagnostic::new(
                Code::TargetNotAuthenticated,
                "",
                format!("{path} is not an authenticated target"),
            ));
        };
        let name = TargetName::new(path)
            .map_err(|error| Diagnostic::new(Code::NonPortablePath, "", error.to_string()))?;
        let stream = self
            .repository
            .read_target(&name)
            .await
            .map_err(|error| Diagnostic::new(trust_code(&error, true), "", error.to_string()))?
            .ok_or_else(|| {
                Diagnostic::new(
                    Code::TargetNotAuthenticated,
                    "",
                    format!("{path} is not available"),
                )
            })?;
        let mut stream = std::pin::pin!(stream);
        let mut bytes = Vec::new();
        while let Some(chunk) =
            std::future::poll_fn(|context| stream.as_mut().poll_next(context)).await
        {
            match chunk {
                Ok(chunk) => bytes.extend_from_slice(&chunk),
                Err(error) => {
                    let code = match trust_code(&error, true) {
                        Code::TargetDigestMismatch
                            if bytes.len() as u64 != authenticated.length =>
                        {
                            Code::TargetLengthMismatch
                        }
                        code => code,
                    };
                    return Err(Diagnostic::new(code, "", error.to_string()));
                }
            }
        }
        Ok(bytes)
    }

    /// Read a target that a recipe binding names. A refusal concerns the
    /// binding, so it is reported at `member`, the binding member that named
    /// the target, rather than at the empty path.
    async fn read_bound(&self, path: &str, member: &str) -> Result<Vec<u8>> {
        self.read(path).await.map_err(|mut refusal| {
            refusal.path = member.to_owned();
            refusal
        })
    }

    /// A recipe target's authenticated state, or a refusal when the target is
    /// not a `0.1.0-draft.1` toolset recipe. Refusals have the empty path.
    pub fn recipe_state(&self, path: &str) -> Result<RecipeTargetState> {
        let not_a_recipe = || {
            Diagnostic::new(
                Code::ReleaseDescriptorMismatch,
                "",
                format!("{path} is not authenticated as a {CONTRACT_VERSION} toolset recipe"),
            )
        };
        let custom = self.custom(path).ok_or_else(not_a_recipe)?;
        if custom["kind"] != "toolset-recipe" || custom["schemaVersion"] != CONTRACT_VERSION {
            return Err(not_a_recipe());
        }
        let status = match custom["status"].as_str() {
            Some("active") => RecipeStatus::Active,
            Some("yanked") => RecipeStatus::Yanked,
            Some("revoked") => RecipeStatus::Revoked,
            _ => return Err(not_a_recipe()),
        };
        let channels = custom["channels"]
            .as_array()
            .ok_or_else(not_a_recipe)?
            .iter()
            .map(|channel| channel.as_str().and_then(|text| Channel::parse(text).ok()))
            .collect::<Option<Vec<_>>>()
            .ok_or_else(not_a_recipe)?;
        Ok(RecipeTargetState {
            preset: custom["preset"]
                .as_str()
                .and_then(|text| PresetId::parse(text).ok())
                .ok_or_else(not_a_recipe)?,
            version: custom["version"]
                .as_str()
                .and_then(|text| Version::parse(text).ok())
                .ok_or_else(not_a_recipe)?,
            channels,
            status,
        })
    }

    /// Select the greatest active recipe for a preset on a moving channel,
    /// with the tool release metadata v1 channel rules.
    pub fn select_recipe(&self, preset: &PresetId, channel: &Channel) -> Result<TargetPath> {
        let mut best: Option<(&String, Version)> = None;
        for path in self.targets.keys() {
            let Ok(state) = self.recipe_state(path) else {
                continue;
            };
            if &state.preset == preset
                && state.status == RecipeStatus::Active
                && channel_matches(channel, &state.version, &state.channels)
                && best
                    .as_ref()
                    .is_none_or(|(_, version)| state.version > *version)
            {
                best = Some((path, state.version));
            }
        }
        let (path, _) = best.ok_or_else(|| {
            Diagnostic::new(
                Code::UnsupportedArtifact,
                "toolset.preset",
                format!("no active {preset} recipe is on the {channel} channel"),
            )
        })?;
        TargetPath::parse(path)
            .map_err(|message| Diagnostic::new(Code::NonPortablePath, "", message))
    }

    /// Read an authenticated recipe target, enforce its authenticated state,
    /// and check every host and provider binding. Refusals about the recipe
    /// target itself have the empty path.
    pub async fn check_recipe(&self, path: &str) -> Result<ToolsetRecipe> {
        TargetPath::parse(path)
            .map_err(|message| Diagnostic::new(Code::NonPortablePath, "", message))?;
        let bytes = self.read(path).await?;
        let state = self.recipe_state(path)?;
        if state.status == RecipeStatus::Revoked {
            return Err(Diagnostic::new(
                Code::ReleaseRevoked,
                "",
                format!("{path} is revoked"),
            ));
        }
        let recipe = crate::recipe::read_recipe(&bytes)?;
        if recipe.preset() != &state.preset || recipe.version() != &state.version {
            return Err(Diagnostic::new(
                Code::ReleaseDescriptorMismatch,
                "",
                format!("{path} disagrees with its authenticated preset and version"),
            ));
        }
        self.check_recipe_bindings(&recipe).await?;
        Ok(recipe)
    }

    /// Check that a locked generation may still be launched or rolled back to,
    /// against the learned state of this repository. A provider has no
    /// version 1 status, so revoking the recipe that binds it is how it is
    /// revoked: a learned recipe revocation refuses every generation bound to
    /// that recipe. A learned revocation of the host release refuses it too.
    /// Paths name the lock's members.
    pub async fn check_locked_generation(&self, lock: &crate::lock::ToolchainLock) -> Result<()> {
        let recipe = lock.recipe();
        if recipe.repository_id != self.repository_id {
            return Err(Diagnostic::new(
                Code::RepositoryMismatch,
                "recipe.repositoryId",
                format!(
                    "the lock names repository {}, but this is repository {}",
                    recipe.repository_id, self.repository_id
                ),
            ));
        }
        let at_target = |mut refusal: Diagnostic| {
            refusal.path = "recipe.target".to_owned();
            refusal
        };
        let state = self
            .recipe_state(recipe.target.as_str())
            .map_err(at_target)?;
        if state.status == RecipeStatus::Revoked {
            return Err(Diagnostic::new(
                Code::ReleaseRevoked,
                "recipe.target",
                format!("{} is revoked", recipe.target),
            ));
        }
        let bytes = self
            .read_bound(recipe.target.as_str(), "recipe.target")
            .await?;
        if Sha256::of_bytes(&bytes) != recipe.sha256 {
            return Err(Diagnostic::new(
                Code::TargetDigestMismatch,
                "recipe.sha256",
                "the lock binds other recipe bytes than the authenticated recipe target",
            ));
        }
        let document = crate::recipe::read_recipe(&bytes).map_err(at_target)?;
        let locked = lock.host();
        let host = document.hosts().iter().find(|host| {
            host.implementation() == &locked.implementation
                && host.deployment() == &locked.deployment
                && host.version() == &locked.version
        });
        if let Some(HostSource::ToolRelease { tool_id }) = host.map(|host| host.source()) {
            let path = format!("releases/{tool_id}/{}.json", locked.version);
            if self
                .custom(&path)
                .is_some_and(|custom| custom["status"] == "revoked")
            {
                return Err(Diagnostic::new(
                    Code::ReleaseRevoked,
                    "host.version",
                    format!("{tool_id} {} is revoked", locked.version),
                ));
            }
        }
        Ok(())
    }

    /// Check every host and provider binding of a recipe document.
    pub async fn check_recipe_bindings(&self, recipe: &ToolsetRecipe) -> Result<()> {
        self.check_hosts(recipe).await?;
        self.check_providers(recipe).await
    }

    async fn check_hosts(&self, recipe: &ToolsetRecipe) -> Result<()> {
        for (position, host) in recipe.hosts().iter().enumerate() {
            let host_path = index("hosts", position);
            let release = match host.source() {
                HostSource::ToolRelease { tool_id } => {
                    let path = format!("releases/{tool_id}/{}.json", host.version());
                    let custom = self.custom(&path).filter(|custom| {
                        custom["kind"] == "tool-release"
                            && custom["toolId"] == tool_id.as_str()
                            && custom["version"] == host.version().to_string()
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
                            format!("{tool_id} {} is revoked", host.version()),
                        ));
                    }
                    let bytes = self.read_bound(&path, &join(&host_path, "source")).await?;
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
            for (platform, binding) in host.platforms() {
                let path = join(&join(&host_path, "platforms"), platform.as_str());
                let entry = self.bound(&path, "target", "sha256", binding)?;
                if let Some(record) = &release {
                    check_release_artifact(
                        record,
                        *platform,
                        binding.target.as_str(),
                        entry,
                        &path,
                    )?;
                }
            }
        }
        Ok(())
    }

    /// Check that a bound target is authenticated with the bound digest.
    fn bound(
        &self,
        path: &str,
        target_member: &str,
        digest_member: &str,
        binding: &TargetDigest,
    ) -> Result<&AuthenticatedTarget> {
        let target = binding.target.as_str();
        let entry = self.targets.get(target).ok_or_else(|| {
            Diagnostic::new(
                Code::TargetNotAuthenticated,
                join(path, target_member),
                format!("{target} is not an authenticated target"),
            )
        })?;
        if entry.sha256 != binding.sha256 {
            return Err(Diagnostic::new(
                Code::TargetDigestMismatch,
                join(path, digest_member),
                format!(
                    "the recipe binds {target} to {}, but it is authenticated as {}",
                    binding.sha256, entry.sha256
                ),
            ));
        }
        Ok(entry)
    }

    async fn check_providers(&self, recipe: &ToolsetRecipe) -> Result<()> {
        for (position, provider) in recipe.providers().iter().enumerate() {
            let path = index("providers", position);
            // One repository per binding check: the provider's descriptor
            // and artifacts are authenticated by this repository only.
            let named = provider.delivery().repository_id();
            if named != &self.repository_id {
                return Err(Diagnostic::new(
                    Code::RepositoryMismatch,
                    join(&path, "repositoryId"),
                    format!(
                        "the provider names repository {named}, but the binding is checked against repository {}",
                        self.repository_id
                    ),
                ));
            }
            let descriptor = provider.delivery().descriptor();
            self.bound(&path, "descriptorTarget", "descriptorSha256", descriptor)?;
            let bytes = self
                .read_bound(descriptor.target.as_str(), &join(&path, "descriptorTarget"))
                .await?;
            let release = read_descriptor(&bytes, &path)?;
            check_release_identity(&release, provider, &path)?;
            match provider.delivery() {
                RecipeDelivery::Process { platforms, .. } => {
                    for (platform, binding) in platforms {
                        let binding_path = join(&join(&path, "platforms"), platform.as_str());
                        self.bound(&binding_path, "artifactTarget", "artifactSha256", binding)?;
                        let artifact = listed_artifact(
                            &release,
                            descriptor,
                            binding,
                            ArtifactRuntime::Process,
                            &binding_path,
                        )?;
                        if artifact.platform() != Some(platform.target_triple()) {
                            return Err(Diagnostic::new(
                                Code::ArtifactPlatformMismatch,
                                join(&binding_path, "artifactTarget"),
                                format!(
                                    "{} is the {} artifact, not the {} artifact",
                                    binding.target,
                                    artifact.platform().unwrap_or("portable"),
                                    platform.target_triple()
                                ),
                            ));
                        }
                        check_capabilities(artifact, provider, &path)?;
                    }
                }
                RecipeDelivery::Wasm { artifact, .. } => {
                    self.bound(&path, "artifactTarget", "artifactSha256", artifact)?;
                    let listed = listed_artifact(
                        &release,
                        descriptor,
                        artifact,
                        ArtifactRuntime::Wasm,
                        &path,
                    )?;
                    check_capabilities(listed, provider, &path)?;
                }
                RecipeDelivery::DotnetTool { package, .. } => {
                    self.bound(&path, "packageTarget", "packageSha256", package)?;
                    for artifact in release.artifacts() {
                        check_capabilities(artifact, provider, &path)?;
                    }
                }
            }
        }
        Ok(())
    }
}

fn read_descriptor(bytes: &[u8], path: &str) -> Result<ReleaseBundleDescriptor> {
    ReleaseBundleDescriptor::parse_json(bytes).map_err(|error| {
        Diagnostic::new(
            Code::ReleaseDescriptorMismatch,
            join(path, "descriptorTarget"),
            format!("not an extension release descriptor: {error}"),
        )
    })
}

/// The descriptor's own identity, and every artifact's claimed identity, are
/// the provider's. This is the existing publication rule: claims name the
/// descriptor's `extensionId` and `version`.
fn check_release_identity(
    release: &ReleaseBundleDescriptor,
    provider: &RecipeProvider,
    path: &str,
) -> Result<()> {
    let mismatch = |member: &str, message: String| {
        Diagnostic::new(Code::ReleaseDescriptorMismatch, join(path, member), message)
    };
    if release.extension_id().as_str() != provider.extension_id().as_str() {
        return Err(mismatch(
            "extensionId",
            format!(
                "the descriptor is for {}, not {}",
                release.extension_id(),
                provider.extension_id()
            ),
        ));
    }
    if release.version() != provider.version() {
        return Err(mismatch(
            "version",
            format!(
                "the descriptor describes {}, not {}",
                release.version(),
                provider.version()
            ),
        ));
    }
    for artifact in release.artifacts() {
        let claims = artifact.claims();
        if claims.extension.id != release.extension_id().as_str()
            || claims.extension.version != release.version().to_string()
        {
            return Err(mismatch(
                "descriptorTarget",
                format!(
                    "{} claims {} {}, not the descriptor's {} {}",
                    artifact.filename().as_str(),
                    claims.extension.id,
                    claims.extension.version,
                    release.extension_id(),
                    release.version()
                ),
            ));
        }
    }
    Ok(())
}

/// The descriptor entry that lists a bound artifact in its own directory,
/// with the delivery's runtime and the same digest.
fn listed_artifact<'a>(
    release: &'a ReleaseBundleDescriptor,
    descriptor: &TargetDigest,
    binding: &TargetDigest,
    runtime: ArtifactRuntime,
    binding_path: &str,
) -> Result<&'a morphir_distribution::BundleArtifactDescriptor> {
    let target_path = join(binding_path, "artifactTarget");
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
            Diagnostic::new(
                Code::ReleaseDescriptorMismatch,
                &target_path,
                format!("{} does not list {}", descriptor.target, binding.target),
            )
        })?;
    if artifact.runtime() != runtime {
        return Err(Diagnostic::new(
            Code::ReleaseDescriptorMismatch,
            &target_path,
            format!("{} is not a {runtime:?} artifact", binding.target),
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
    Ok(artifact)
}

/// The artifact's claims support the provider's operation, language or
/// target, MEP version, and model tuple or IR version.
fn check_capabilities(
    artifact: &morphir_distribution::BundleArtifactDescriptor,
    provider: &RecipeProvider,
    path: &str,
) -> Result<()> {
    let mismatch = |member: &str, message: String| {
        Diagnostic::new(Code::ReleaseDescriptorMismatch, join(path, member), message)
    };
    let claims = artifact.claims();
    let kind = provider.operation().capability_kind();
    let types = serde_json::to_value(&claims.extension.types).unwrap_or_default();
    if !types
        .as_array()
        .is_some_and(|types| types.iter().any(|item| item == kind))
    {
        return Err(mismatch(
            "operation",
            format!("the artifact does not claim the {kind} capability kind"),
        ));
    }
    let protocol = provider.delivery().protocol();
    if !claims
        .protocol_versions
        .iter()
        .any(|version| version == protocol.version().as_str())
    {
        return Err(mismatch(
            "protocolVersion",
            format!(
                "the artifact does not claim MEP {}",
                protocol.version().as_str()
            ),
        ));
    }
    let capability = claims.capabilities.get(kind).cloned().unwrap_or_default();
    let (member, supported) = match provider.operation() {
        Operation::Compile { language } => (
            "language",
            capability["compile"] == true
                && capability["languages"].as_array().is_some_and(|languages| {
                    languages
                        .iter()
                        .any(|entry| entry["id"] == language.as_str())
                }),
        ),
        Operation::Generate { target } => (
            "target",
            capability["generate"] == true
                && capability["targets"]
                    .as_array()
                    .is_some_and(|targets| targets.iter().any(|entry| entry == target.as_str())),
        ),
    };
    if !supported {
        return Err(mismatch(
            member,
            format!("the artifact's {kind} claims do not include this {member}"),
        ));
    }
    match protocol {
        Protocol::ModelTransport(tuple) => {
            let wanted = serde_json::json!({
                "operation": tuple.operation().model_method(),
                "profile": tuple.profile().as_str(),
                "codec": tuple.codec().as_str(),
                "envelopeVersion": tuple.envelope_version().to_string(),
                "irVersion": tuple.ir_version().to_string()
            });
            let claimed = claims
                .capabilities
                .get("modelTransport")
                .and_then(|transport| transport["tuples"].as_array().cloned())
                .unwrap_or_default();
            if !claimed.contains(&wanted) {
                return Err(mismatch(
                    "modelTuple",
                    "the artifact does not claim this exact model tuple".into(),
                ));
            }
        }
        Protocol::Legacy(input) => {
            let full = input.ir_version.to_string();
            let major = input.ir_version.major.to_string();
            let claimed = capability["irVersions"].as_array().is_some_and(|versions| {
                versions
                    .iter()
                    .any(|version| version == &full || version == &major)
            });
            if !claimed {
                return Err(mismatch(
                    "modelInput.irVersion",
                    format!("the artifact does not claim IR {full}"),
                ));
            }
        }
    }
    Ok(())
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
    let Some(expected) = platform.tool_platform() else {
        return Err(Diagnostic::new(
            Code::ArtifactPlatformMismatch,
            &target_path,
            format!("a version 1 artifact cannot be bound to {platform}"),
        ));
    };
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
    let agrees = entry.custom.as_ref().is_some_and(|custom| {
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

fn channel_matches(requested: &Channel, version: &Version, channels: &[Channel]) -> bool {
    match requested {
        Channel::Stable => version.pre.is_empty() && channels.contains(&Channel::Stable),
        Channel::Preview(None) | Channel::Insiders => channels
            .iter()
            .any(|channel| matches!(channel, Channel::Preview(_) | Channel::Insiders)),
        Channel::Preview(Some(_)) => channels.contains(requested),
    }
}
