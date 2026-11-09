//! Recipe bindings checked against authenticated TUF targets metadata.
//!
//! The TUF client authenticates the metadata: signatures, thresholds, expiry,
//! rollback and snapshot links. These checks then prove what an authenticated
//! recipe binds. A validly signed recipe can still name another platform's
//! artifact, another offering's artifact, a wrong digest or an unpublished
//! target, and each of those is refused here.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope::CONTRACT_VERSION;
use crate::ids::{PresetId, Sha256, TargetPath};
use crate::platform::PlatformId;
use crate::reader::{index, join};
use crate::recipe::{HostSource, ToolsetRecipe};
use morphir_distribution::{Channel, ToolReleaseRecord};
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

fn channel_matches(requested: &Channel, version: &Version, channels: &[Channel]) -> bool {
    match requested {
        Channel::Stable => version.pre.is_empty() && channels.contains(&Channel::Stable),
        Channel::Preview(None) | Channel::Insiders => channels
            .iter()
            .any(|channel| matches!(channel, Channel::Preview(_) | Channel::Insiders)),
        Channel::Preview(Some(_)) => channels.contains(requested),
    }
}
