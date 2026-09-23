//! Public MVP case execution through the single MCK adapter session. This is
//! intentionally separate from the historical draft.1/draft.2 package kit.
use super::local_registry::AdmittedMvpInventory;
use crate::kit::hash::is_sha256_hex;
use crate::transport::{Limits, Session};
use semver::Version;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::ffi::{OsStr, OsString};
use std::time::SystemTime;

mod report;

const PROFILE: &str = "local-library-mvp:0.1.0-draft.1";
const CONTRACT: &str = "0.1.0-draft.3";
const REPORT_VERSION: &str = "0.1.0-draft.1";
const OPERATIONS: [&str; 4] = [
    "restore-local-library",
    "resolve-local-library",
    "refresh-local-library",
    "update-local-library",
];

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct MvpRun {
    contract_version: Version,
    suite: String,
    started_at: String,
    driver: MvpDriver,
    adapter: MvpAdapter,
    selection: MvpSelection,
    profile: String,
    scope: String,
    kit_hash: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    testee: Option<MvpCapabilities>,
    pub records: Vec<MvpRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    adapter_error: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MvpDriver {
    name: String,
    version: String,
    commit: Option<String>,
    dirty: bool,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MvpAdapter {
    command: Vec<String>,
    request_timeout_ms: u64,
    session_timeout_ms: u64,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct MvpSelection {
    kind: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct MvpRecord {
    case_id: String,
    result: MvpResult,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
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
    Resolution,
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
    InvalidUpdateTargets,
    InvalidOldLock,
    OldRecordAcquisitionMismatch,
    UpdateScopeConflict,
    UnsatisfiableRequirements,
    RevocationTransitionUnsupported,
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
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RefreshReceipt {
    profile: String,
    profile_version: String,
    registry: String,
    timestamp_digest: String,
    snapshot_digest: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "outcome",
    rename_all = "lowercase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
enum Observation {
    Refreshed {
        receipt: RefreshReceipt,
        output: OutputState,
        output_files: Vec<OutputFile>,
        lock_unchanged: bool,
        registry_unchanged: bool,
    },
    Resolved {
        output: OutputState,
        output_files: Vec<OutputFile>,
        lock_unchanged: bool,
        registry_unchanged: bool,
    },
    Updated {
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
            Self::Refreshed {
                receipt,
                output,
                output_files,
                lock_unchanged,
                registry_unchanged,
            } => {
                if receipt.profile != "local-library-mvp"
                    || receipt.profile_version != "0.1.0-draft.1"
                    || receipt.registry != "local"
                    || [
                        receipt.timestamp_digest.as_str(),
                        receipt.snapshot_digest.as_str(),
                    ]
                    .iter()
                    .any(|digest| !digest.strip_prefix("sha256:").is_some_and(is_sha256_hex))
                    || *output != OutputState::Absent
                    || !output_files.is_empty()
                    || !*lock_unchanged
                    || !*registry_unchanged
                {
                    return Err("invalid MVP refreshed observation".into());
                }
            }
            Self::Resolved {
                output,
                output_files,
                lock_unchanged,
                registry_unchanged,
            }
            | Self::Updated {
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
    fn new(
        inventory: &AdmittedMvpInventory,
        program: &OsStr,
        args: &[OsString],
        limits: Limits,
    ) -> Self {
        let driver = crate::provenance::Driver::current();
        Self {
            contract_version: Version::parse(REPORT_VERSION).expect("static MVP report version"),
            suite: "package".into(),
            started_at: crate::report::iso_timestamp(SystemTime::now()),
            driver: MvpDriver {
                name: driver.name.into(),
                version: driver.version.into(),
                commit: driver.commit.map(str::to_owned),
                dirty: driver.dirty,
            },
            adapter: MvpAdapter {
                command: std::iter::once(program.to_string_lossy().into_owned())
                    .chain(args.iter().map(|arg| arg.to_string_lossy().into_owned()))
                    .collect(),
                request_timeout_ms: limits.request_timeout.as_millis() as u64,
                session_timeout_ms: limits.session_timeout.as_millis() as u64,
            },
            selection: MvpSelection { kind: "all".into() },
            profile: PROFILE.into(),
            scope: "fresh-local-library-workflow".into(),
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

    pub fn from_json(text: &str) -> Result<Self, String> {
        let report: Self = serde_json::from_str(text).map_err(|e| e.to_string())?;
        if report.contract_version
            != Version::parse(REPORT_VERSION).expect("static MVP report version")
            || report.suite != "package"
            || report.profile != PROFILE
            || report.scope != "fresh-local-library-workflow"
            || report.selection.kind != "all"
            || report.driver.name.is_empty()
            || report.driver.version.is_empty()
            || report
                .adapter
                .command
                .first()
                .is_none_or(|program| program.is_empty())
            || chrono::DateTime::parse_from_rfc3339(&report.started_at).is_err()
            || report.driver.commit.as_ref().is_some_and(|commit| {
                commit.len() != 40 || !commit.bytes().all(|b| b.is_ascii_hexdigit())
            })
            || report.adapter.request_timeout_ms == 0
            || report.adapter.session_timeout_ms == 0
        {
            return Err("invalid MVP report context or unsupported version".into());
        }
        Ok(report)
    }

    pub fn check_inventory(&self, inventory: &AdmittedMvpInventory) -> Result<usize, String> {
        if self.kit_hash != inventory.content_hash().to_string() {
            return Err(
                "MVP report kit hash differs from the independently loaded inventory".into(),
            );
        }
        if self.adapter_error.is_some() {
            return Err("MVP adapter session failed".into());
        }
        let capabilities_valid = self.testee.as_ref().is_some_and(|caps| {
            serde_json::to_value(caps)
                .ok()
                .and_then(|value| MvpCapabilities::parse(value).ok())
                .is_some_and(|parsed| parsed.supports_mvp())
        });
        if !capabilities_valid {
            return Err("required MVP capabilities were not negotiated".into());
        }
        if self.records.len() != inventory.cases().len() {
            return Err(format!(
                "MVP record inventory count: expected {}, found {}",
                inventory.cases().len(),
                self.records.len()
            ));
        }
        for (index, (record, case)) in self.records.iter().zip(inventory.cases()).enumerate() {
            if record.case_id != case.id() {
                return Err(format!("MVP record inventory differs at index {index}"));
            }
            if record.result != MvpResult::Pass || record.message.is_some() {
                return Err(format!("MVP case {} did not pass", record.case_id));
            }
        }
        Ok(self.records.len())
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
    let mut run = MvpRun::new(inventory, program, args, limits);
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
        assert_eq!(inventory.cases().len(), 70);
        for case in inventory.cases() {
            let value = serde_json::from_slice(case.expected()).unwrap();
            Observation::parse(value).unwrap_or_else(|error| panic!("{}: {error}", case.id()));
        }
    }
}
