use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

use super::*;
use crate::commands::ui::protocol::{PlaygroundDiagnostic, PlaygroundGenerateParams};

#[derive(Debug)]
pub struct ArtifactGenerateRequest {
    pub contract_version: ArtifactContractVersion,
    pub provider_id: ProviderId,
    pub generation: ArtifactGenerationInput,
}
#[derive(Debug)]
pub struct ArtifactGenerationInput {
    ir: Value,
    ir_version: GenerationIrVersion,
    target: GenerationTarget,
    options: ArtifactGenerationOptions,
}

/// The SDK accepts named options. Preserve arbitrary JSON only inside that
/// validated map instead of silently replacing a caller's non-object value.
#[derive(Debug)]
struct ArtifactGenerationOptions(serde_json::Map<String, Value>);
impl ArtifactGenerationOptions {
    fn parse(value: Value) -> Result<Self, ArtifactError> {
        match value {
            Value::Object(options) => Ok(Self(options)),
            _ => Err(ArtifactError::InvalidRequest),
        }
    }
    fn into_json(self) -> Value {
        Value::Object(self.0)
    }
}
impl ArtifactGenerationInput {
    pub fn target(&self) -> &GenerationTarget {
        &self.target
    }
    pub fn ir_version(&self) -> &GenerationIrVersion {
        &self.ir_version
    }
    pub fn into_playground(self) -> PlaygroundGenerateParams {
        PlaygroundGenerateParams {
            ir: self.ir,
            ir_version: self.ir_version.as_str().to_owned(),
            target: self.target.as_str().to_owned(),
            options: self.options.into_json(),
        }
    }
}
impl TryFrom<PlaygroundGenerateParams> for ArtifactGenerationInput {
    type Error = ArtifactError;
    fn try_from(params: PlaygroundGenerateParams) -> Result<Self, Self::Error> {
        Ok(Self {
            ir: params.ir,
            ir_version: GenerationIrVersion::parse(&params.ir_version)?,
            target: GenerationTarget::parse(&params.target)?,
            options: ArtifactGenerationOptions::parse(params.options)?,
        })
    }
}
pub fn decode_generate(raw: &str) -> Result<ArtifactGenerateRequest, ArtifactError> {
    let value = parse_document(raw, MAX_GENERATE_REQUEST_BYTES)?;
    let mut fields = closed_object(value, &["contractVersion", "providerId", "generation"])?;
    let contract_version: ArtifactContractVersion =
        serde_json::from_value(fields.remove("contractVersion").expect("closed version"))
            .map_err(|_| ArtifactError::Unavailable)?;
    let provider_id = ProviderId::parse(
        fields["providerId"]
            .as_str()
            .ok_or(ArtifactError::InvalidIdentity)?,
    )?;
    let mut generation = closed_object(
        fields.remove("generation").expect("closed generation"),
        &["ir", "irVersion", "target", "options"],
    )?;
    let ir_version = GenerationIrVersion::parse(
        generation["irVersion"]
            .as_str()
            .ok_or(ArtifactError::InvalidIdentity)?,
    )?;
    let target = GenerationTarget::parse(
        generation["target"]
            .as_str()
            .ok_or(ArtifactError::InvalidIdentity)?,
    )?;
    // Opaque application JSON remains literal even when user keys happen to
    // match serde's internal arbitrary-number/raw-value marker spellings.
    Ok(ArtifactGenerateRequest {
        contract_version,
        provider_id,
        generation: ArtifactGenerationInput {
            ir: generation.remove("ir").expect("closed ir"),
            ir_version,
            target,
            options: ArtifactGenerationOptions::parse(
                generation.remove("options").expect("closed options"),
            )?,
        },
    })
}

pub(crate) fn closed_object(
    value: Value,
    keys: &[&str],
) -> Result<serde_json::Map<String, Value>, ArtifactError> {
    let Value::Object(fields) = value else {
        return Err(ArtifactError::InvalidRequest);
    };
    if fields.len() != keys.len() || fields.keys().any(|key| !keys.contains(&key.as_str())) {
        return Err(ArtifactError::InvalidRequest);
    }
    Ok(fields)
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
#[serde(transparent)]
pub struct ArtifactDiagnostics(Vec<PlaygroundDiagnostic>);
impl ArtifactDiagnostics {
    pub fn from_sdk(
        diagnostics: &[morphir_extension_sdk::Diagnostic],
    ) -> Result<Self, ArtifactError> {
        // Count the projected strings by reference before cloning. Related SDK
        // information is outside this existing UI diagnostic projection.
        struct BorrowedDiagnostics<'a>(&'a [morphir_extension_sdk::Diagnostic]);
        impl Serialize for BorrowedDiagnostics<'_> {
            fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
                use serde::ser::SerializeSeq;
                #[derive(Serialize)]
                struct Diagnostic<'a> {
                    severity: morphir_extension_sdk::DiagnosticSeverity,
                    code: &'a Option<String>,
                    message: &'a str,
                    location: &'a Option<morphir_extension_sdk::SourceLocation>,
                }
                let mut sequence = serializer.serialize_seq(Some(self.0.len()))?;
                for diagnostic in self.0 {
                    sequence.serialize_element(&Diagnostic {
                        severity: diagnostic.severity,
                        code: &diagnostic.code,
                        message: &diagnostic.message,
                        location: &diagnostic.location,
                    })?;
                }
                sequence.end()
            }
        }
        check_reply_budget(&BorrowedDiagnostics(diagnostics))?;
        Ok(Self(
            diagnostics
                .iter()
                .map(crate::commands::ui::provider::playground::playground_diagnostic)
                .collect(),
        ))
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ArtifactReleaseRequest {
    pub contract_version: ArtifactContractVersion,
    pub generation_id: GenerationId,
}
pub fn decode_release(raw: &str) -> Result<ArtifactReleaseRequest, ArtifactError> {
    let value = parse_document(raw, MAX_CONTROL_REQUEST_BYTES)?;
    let _: ArtifactContractVersion = serde_json::from_value(value["contractVersion"].clone())
        .map_err(|_| ArtifactError::Unavailable)?;
    serde_json::from_value(value).map_err(|_| ArtifactError::InvalidRequest)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtifactFailure {
    status: FailedStatus,
    profile: ProfileName,
    contract_version: ArtifactContractVersion,
    diagnostics: ArtifactDiagnostics,
}
#[derive(Debug, Serialize)]
enum FailedStatus {
    #[serde(rename = "failed")]
    Failed,
}
impl ArtifactFailure {
    pub fn diagnostics(diagnostics: ArtifactDiagnostics) -> Self {
        let failure = Self {
            status: FailedStatus::Failed,
            profile: ProfileName,
            contract_version: ArtifactContractVersion,
            diagnostics,
        };
        if check_reply_budget(&failure).is_ok() {
            failure
        } else {
            Self::error(ArtifactError::ReplyLimit)
        }
    }
    pub fn error(error: ArtifactError) -> Self {
        Self::coded(error.code(), &error.to_string())
    }
    pub fn generation_failed() -> Self {
        Self::coded("artifacts.generation_failed", "Artifact generation failed.")
    }
    fn coded(code: &str, message: &str) -> Self {
        Self {
            status: FailedStatus::Failed,
            profile: ProfileName,
            contract_version: ArtifactContractVersion,
            diagnostics: ArtifactDiagnostics(vec![PlaygroundDiagnostic {
                severity: "error".into(),
                code: Some(code.into()),
                message: message.into(),
                location: None,
            }]),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ProfileName;
impl Serialize for ProfileName {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(PROFILE)
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ArtifactContractVersion;
impl Serialize for ArtifactContractVersion {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(CONTRACT_VERSION)
    }
}
impl<'de> Deserialize<'de> for ArtifactContractVersion {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let value = String::deserialize(d)?;
        let version = semver::Version::parse(&value).map_err(serde::de::Error::custom)?;
        if value != CONTRACT_VERSION || version.to_string() != value {
            return Err(serde::de::Error::custom("unsupported exact artifact draft"));
        }
        Ok(Self)
    }
}

#[derive(Debug)]
pub struct ArtifactReadRequest {
    pub generation_id: GenerationId,
    pub artifact_id: ArtifactId,
    pub offset: ByteOffset,
    pub max_bytes: ChunkLimit,
}

pub fn decode_read(raw: &str) -> Result<ArtifactReadRequest, ArtifactError> {
    let value = parse_document(raw, MAX_CONTROL_REQUEST_BYTES)?;
    let fields = value.as_object().ok_or(ArtifactError::InvalidRequest)?;
    if fields.len() != 5
        || fields.keys().any(|key| {
            !matches!(
                key.as_str(),
                "contractVersion" | "generationId" | "artifactId" | "offset" | "maxBytes"
            )
        })
    {
        return Err(ArtifactError::InvalidRequest);
    }
    let _: ArtifactContractVersion = serde_json::from_value(value["contractVersion"].clone())
        .map_err(|_| ArtifactError::Unavailable)?;
    Ok(ArtifactReadRequest {
        generation_id: GenerationId::parse(
            value["generationId"]
                .as_str()
                .ok_or(ArtifactError::InvalidIdentity)?,
        )?,
        artifact_id: ArtifactId::parse(
            value["artifactId"]
                .as_str()
                .ok_or(ArtifactError::InvalidIdentity)?,
        )?,
        offset: ByteOffset::new(
            exact_bounded_integer(&value["offset"], MAX_FILE_BYTES)
                .ok_or(ArtifactError::InvalidRange)?,
        )?,
        max_bytes: ChunkLimit::new(
            exact_bounded_integer(&value["maxBytes"], MAX_CHUNK_BYTES)
                .ok_or(ArtifactError::InvalidRange)?,
        )?,
    })
}

pub(super) fn parse_document(raw: &str, max_bytes: usize) -> Result<Value, ArtifactError> {
    if raw.len() > max_bytes {
        return Err(ArtifactError::InvalidRequest);
    }
    morphir_mck::json::parse_exact_document(raw).map_err(|_| ArtifactError::InvalidRequest)
}

/// Inspect the decimal token, not a rounded float. Integral spellings such as
/// 1.0 and 1e0 are accepted; fractional and nonzero underflow tokens are not.
pub fn exact_bounded_integer(value: &Value, bound: usize) -> Option<usize> {
    let token = value.as_number()?.to_string();
    let unsigned = token.strip_prefix('-').unwrap_or(&token);
    let (mantissa, exponent) = unsigned.split_once(['e', 'E']).unwrap_or((unsigned, "0"));
    let fraction = mantissa.split_once('.').map_or(0, |(_, right)| right.len());
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    let significant = digits.trim_start_matches('0');
    if significant.is_empty() {
        return Some(0);
    }
    if token.starts_with('-') {
        return None;
    }
    let integer = significant.trim_end_matches('0');
    let zeros = significant.len() - integer.len();
    let scale = exponent
        .parse::<i64>()
        .ok()?
        .checked_sub(fraction as i64)?
        .checked_add(zeros as i64)?;
    if !(0..=20).contains(&scale) || (integer.len() as i64).checked_add(scale)? > 20 {
        return None;
    }
    let mut result = integer.parse::<u64>().ok()?;
    for _ in 0..scale {
        result = result.checked_mul(10)?;
    }
    usize::try_from(result)
        .ok()
        .filter(|result| *result <= bound)
}
