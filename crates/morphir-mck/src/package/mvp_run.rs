//! Public MVP case execution through the single MCK adapter session. This is
//! intentionally separate from the historical draft.1/draft.2 package kit.
use super::local_registry::AdmittedMvpInventory;
use crate::kit::hash::is_sha256_hex;
use crate::transport::{Limits, Session};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::ffi::{OsStr, OsString};

const PROFILE: &str = "local-library-mvp:0.1.0-draft.1";
const CONTRACT: &str = "0.1.0-draft.3";
const OPERATIONS: [&str; 2] = ["restore-local-library", "resolve-local-library"];

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MvpRun {
    profile: &'static str,
    scope: &'static str,
    kit_hash: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    testee: Option<MvpCapabilities>,
    pub records: Vec<MvpRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    adapter_error: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MvpRecord {
    case_id: String,
    result: MvpResult,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
enum MvpResult {
    Pass,
    Fail,
    KitError,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MvpCapabilities {
    suite: String,
    contract_version: String,
    implementation: String,
    implementation_version: String,
    profiles: Vec<String>,
    operations: Vec<String>,
}

impl MvpCapabilities {
    fn parse(body: Value) -> Result<Self, String> {
        let caps: Self = serde_json::from_value(body).map_err(|e| e.to_string())?;
        if caps.suite != "package"
            || caps.contract_version != CONTRACT
            || caps.implementation.is_empty()
            || caps.implementation_version.is_empty()
            || caps.profiles.len() > 1
            || caps.profiles.iter().any(|profile| profile != PROFILE)
            || caps.operations.len() > OPERATIONS.len()
            || caps
                .operations
                .iter()
                .any(|operation| !OPERATIONS.contains(&operation.as_str()))
            || caps
                .operations
                .iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len()
                != caps.operations.len()
        {
            return Err("invalid MVP adapter capabilities".into());
        }
        Ok(caps)
    }

    fn supports_mvp(&self) -> bool {
        self.profiles.len() == 1 && self.operations.len() == OPERATIONS.len()
    }
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
enum OutputState {
    Present,
    Absent,
    PreservedSentinel,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
enum RefusalCategory {
    MetadataAuthentication,
    PackageIntegrity,
    PublisherAuthorization,
    InvalidInput,
    TrustState,
    OutputConflict,
    UnsupportedPolicy,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
enum RefusalReason {
    TimestampSignatureThreshold,
    TimestampExpired,
    ContentDigestMismatch,
    PublisherSignatureInvalid,
    UnsafeAcquisitionPath,
    Uninitialized,
    DestinationExists,
    HistoricalAuthorizationUnsupported,
    MissingEstablishedDatabase,
    CorruptEstablishedDatabase,
    UnresolvedOperation,
    HistoricalEvidenceUnsupported,
    BundleInventoryMismatch,
    PublishedRootUnavailable,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct OutputFile {
    path: String,
    sha256: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Package {
    package_path: String,
    version: String,
    directory: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "outcome",
    rename_all = "lowercase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
enum Observation {
    Resolved {
        output: OutputState,
        output_files: Vec<OutputFile>,
        lock_unchanged: bool,
        registry_unchanged: bool,
    },
    Restored {
        packages: Vec<Package>,
        output: OutputState,
        output_files: Vec<OutputFile>,
        lock_unchanged: bool,
        registry_unchanged: bool,
    },
    Refused {
        category: RefusalCategory,
        reason: RefusalReason,
        output: OutputState,
        output_files: Vec<OutputFile>,
        lock_unchanged: bool,
        registry_unchanged: bool,
    },
}

impl Observation {
    fn parse(body: Value) -> Result<Self, String> {
        let mut observation: Self = serde_json::from_value(body).map_err(|e| e.to_string())?;
        match &mut observation {
            Self::Resolved {
                output,
                output_files,
                lock_unchanged,
                registry_unchanged,
            } => {
                if *output != OutputState::Present
                    || output_files.len() != 1
                    || output_files[0].path != "morphir.lock"
                    || !output_files[0]
                        .sha256
                        .strip_prefix("sha256:")
                        .is_some_and(is_sha256_hex)
                    || !*lock_unchanged
                    || !*registry_unchanged
                {
                    return Err("invalid MVP resolved observation".into());
                }
            }
            Self::Restored {
                packages,
                output,
                output_files,
                lock_unchanged,
                registry_unchanged,
            } => {
                if *output != OutputState::Present
                    || !*lock_unchanged
                    || !*registry_unchanged
                    || packages.is_empty()
                    || output_files.is_empty()
                {
                    return Err("invalid MVP restored observation".into());
                }
                packages.sort_by(|a, b| a.package_path.cmp(&b.package_path));
                if packages
                    .windows(2)
                    .any(|pair| pair[0].package_path == pair[1].package_path)
                {
                    return Err("duplicate MVP restored package".into());
                }
                output_files.sort_by(|a, b| a.path.cmp(&b.path));
                if output_files
                    .windows(2)
                    .any(|pair| pair[0].path == pair[1].path)
                    || output_files.iter().any(|file| {
                        file.path.is_empty()
                            || file.path.starts_with('/')
                            || file
                                .path
                                .split('/')
                                .any(|part| part.is_empty() || part == "." || part == "..")
                            || !file
                                .sha256
                                .strip_prefix("sha256:")
                                .is_some_and(is_sha256_hex)
                    })
                {
                    return Err("invalid MVP output inventory".into());
                }
            }
            Self::Refused {
                output,
                output_files,
                lock_unchanged,
                registry_unchanged,
                ..
            } => {
                let output_valid = match output {
                    OutputState::Absent => output_files.is_empty(),
                    OutputState::PreservedSentinel => {
                        output_files.len() == 1
                            && matches!(
                                output_files[0].path.as_str(),
                                "sentinel.txt" | "morphir.lock"
                            )
                            && output_files[0]
                                .sha256
                                .strip_prefix("sha256:")
                                .is_some_and(is_sha256_hex)
                    }
                    OutputState::Present => false,
                };
                if !output_valid || !*lock_unchanged || !*registry_unchanged {
                    return Err("invalid MVP refusal observation".into());
                }
            }
        }
        Ok(observation)
    }
}

impl MvpRun {
    fn new(inventory: &AdmittedMvpInventory) -> Self {
        Self {
            profile: PROFILE,
            scope: "fresh-local-library-workflow",
            kit_hash: inventory.content_hash().to_string(),
            testee: None,
            records: Vec::new(),
            adapter_error: None,
        }
    }

    fn fail_remaining(&mut self, inventory: &AdmittedMvpInventory, message: &str) {
        for case in inventory.cases().iter().skip(self.records.len()) {
            self.records.push(MvpRecord {
                case_id: case.id().into(),
                result: MvpResult::KitError,
                message: Some(message.into()),
            });
        }
    }

    pub fn exit_code(&self) -> i32 {
        if self.adapter_error.is_none()
            && !self.records.is_empty()
            && self
                .records
                .iter()
                .all(|record| record.result == MvpResult::Pass)
        {
            0
        } else {
            1
        }
    }

    pub fn summary_line(&self) -> String {
        let count = |result| {
            self.records
                .iter()
                .filter(|record| record.result == result)
                .count()
        };
        format!(
            "{} pass, {} fail, {} kit-error",
            count(MvpResult::Pass),
            count(MvpResult::Fail),
            count(MvpResult::KitError)
        )
    }

    pub fn failures(&self) -> impl Iterator<Item = (&str, &str)> {
        self.records.iter().filter_map(|record| {
            record
                .message
                .as_deref()
                .map(|message| (record.case_id.as_str(), message))
        })
    }
}

/// Every admitted required case is represented, including failures before or
/// during adapter exchange. No result can be classified as a skip.
pub fn run_mvp_process(
    inventory: &AdmittedMvpInventory,
    program: &OsStr,
    args: &[OsString],
    limits: Limits,
) -> MvpRun {
    let mut run = MvpRun::new(inventory);
    let mut session = match Session::spawn(&program.to_os_string(), args, limits) {
        Ok(session) => session,
        Err(error) => {
            run.fail_remaining(inventory, &error.to_string());
            return run;
        }
    };
    let capabilities = session
        .exchange_serializable(&crate::transport::protocol::Request::Capabilities)
        .map_err(|error| error.to_string())
        .and_then(|body| MvpCapabilities::parse(Value::Object(body)));
    match capabilities {
        Err(error) => run.fail_remaining(inventory, &error),
        Ok(caps) => {
            let supported = caps.supports_mvp();
            run.testee = Some(caps);
            if !supported {
                run.fail_remaining(inventory, "required MVP capability unsupported");
            } else {
                for case in inventory.cases() {
                    let result = session
                        .exchange_serializable(&case.request())
                        .map_err(|error| error.to_string())
                        .and_then(|body| Observation::parse(Value::Object(body)))
                        .and_then(|actual| {
                            let expected: Value = serde_json::from_slice(case.expected())
                                .map_err(|error| format!("invalid fixed MVP result: {error}"))?;
                            let expected = Observation::parse(expected)
                                .map_err(|error| format!("invalid fixed MVP result: {error}"))?;
                            Ok(actual == expected)
                        });
                    let (result, message) = match result {
                        Ok(true) => (MvpResult::Pass, None),
                        Ok(false) => (
                            MvpResult::Fail,
                            Some("MVP observation differs from fixed result".into()),
                        ),
                        Err(error) => (MvpResult::KitError, Some(error)),
                    };
                    let stop = result == MvpResult::KitError;
                    run.records.push(MvpRecord {
                        case_id: case.id().into(),
                        result,
                        message,
                    });
                    if stop {
                        run.fail_remaining(
                            inventory,
                            "adapter exchange stopped before required case",
                        );
                        break;
                    }
                }
            }
        }
    }
    if let Err(error) = session.close() {
        run.adapter_error = Some(error.to_string());
    }
    run
}

#[cfg(test)]
mod tests {
    use super::Observation;
    use crate::package::local_registry::{MvpRepositorySource, admit_mvp_inventory};

    #[test]
    fn all_frozen_restore_observations_are_structurally_admitted() {
        let source =
            MvpRepositorySource::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).unwrap();
        let inventory = admit_mvp_inventory(&source).unwrap();
        assert_eq!(inventory.cases().len(), 29);
        for case in inventory.cases() {
            let value = serde_json::from_slice(case.expected()).unwrap();
            Observation::parse(value).unwrap_or_else(|error| panic!("{}: {error}", case.id()));
        }
    }
}
